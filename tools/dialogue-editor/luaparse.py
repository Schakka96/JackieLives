"""
luaparse.py -- a tiny, dependency-free Lua 5.x tokenizer + *value* parser.

It is NOT a full Lua parser. It does exactly two things, which is all the
dialogue editor needs:

  1. tokenize()      -- turn a .lua source string into tokens, skipping comments
                        (line + long-bracket) and correctly handling string
                        literals (single, double, and long-bracket).

  2. parse_assigns() -- find top-level statements of the form

                            <Name>.<field>.<field> = <expression>

                        and parse the right-hand side into a small value tree
                        made of Table / Str / Raw nodes.

Every node records its EXACT span (start, end) as indices into the original
source string, so the caller can splice replacement text straight back into
the raw file without ever re-serializing the Lua (which would destroy the
comments -- and in this project the comments are the documentation).

A Str node's span covers the WHOLE string expression, including the quotes and
including every part of a `"a" .. "b" .. "c"` concatenation chain. Replacing
that span with one freshly-escaped `"..."` literal is valid Lua and is what
save() does.
"""

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while",
}


class LuaSyntaxError(Exception):
    pass


class Tok(object):
    __slots__ = ("kind", "val", "start", "end")

    def __init__(self, kind, val, start, end):
        self.kind = kind      # 'name' | 'num' | 'str' | 'op' | 'eof'
        self.val = val        # for 'str' this is the DECODED text
        self.start = start
        self.end = end        # exclusive

    def __repr__(self):
        return "Tok(%s,%r,%d,%d)" % (self.kind, self.val, self.start, self.end)


# ---------------------------------------------------------------------------
# tokenizer
# ---------------------------------------------------------------------------

_NAME_START = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
_NAME_BODY = _NAME_START | set("0123456789")
_DIGITS = set("0123456789")

# longest first, so '...' wins over '..' wins over '.'
_OPS = [
    "...", "..", "::", "<<", ">>", "//", "==", "~=", "<=", ">=",
    "+", "-", "*", "/", "%", "^", "#", "&", "~", "|", "<", ">", "=",
    "(", ")", "{", "}", "[", "]", ";", ":", ",", ".",
]


def _long_bracket_level(src, i):
    """If src[i:] opens a long bracket `[==[`, return its level, else None."""
    if i >= len(src) or src[i] != "[":
        return None
    j = i + 1
    level = 0
    while j < len(src) and src[j] == "=":
        level += 1
        j += 1
    if j < len(src) and src[j] == "[":
        return level
    return None


def _read_long_bracket(src, i, level):
    """Read a long bracket starting at src[i] == '['. Returns (text, end_index)."""
    open_len = 2 + level
    body = i + open_len
    # a newline immediately after the opening bracket is skipped by Lua
    if body < len(src) and src[body] == "\n":
        body += 1
    close = "]" + ("=" * level) + "]"
    k = src.find(close, body)
    if k < 0:
        raise LuaSyntaxError("unterminated long bracket at offset %d" % i)
    return src[body:k], k + len(close)


_ESCAPES = {
    "a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r",
    "t": "\t", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n",
}


def _read_quoted(src, i):
    """Read a quoted string starting at src[i] (the quote). Returns (text, end)."""
    quote = src[i]
    j = i + 1
    out = []
    n = len(src)
    while True:
        if j >= n:
            raise LuaSyntaxError("unterminated string starting at offset %d" % i)
        c = src[j]
        if c == quote:
            return "".join(out), j + 1
        if c == "\n":
            raise LuaSyntaxError("unescaped newline in string at offset %d" % i)
        if c == "\\":
            j += 1
            if j >= n:
                raise LuaSyntaxError("unterminated escape at offset %d" % j)
            e = src[j]
            if e in _ESCAPES:
                out.append(_ESCAPES[e])
                j += 1
            elif e == "x":  # \xXX
                out.append(chr(int(src[j + 1:j + 3], 16)))
                j += 3
            elif e == "z":  # skip following whitespace
                j += 1
                while j < n and src[j] in " \t\r\n":
                    j += 1
            elif e in _DIGITS:  # \ddd
                k = j
                num = ""
                while k < n and src[k] in _DIGITS and len(num) < 3:
                    num += src[k]
                    k += 1
                out.append(chr(int(num)))
                j = k
            elif e == "u":  # \u{XXX}
                k = src.index("}", j)
                out.append(chr(int(src[j + 2:k], 16)))
                j = k + 1
            else:
                raise LuaSyntaxError("bad escape \\%s at offset %d" % (e, j))
            continue
        out.append(c)
        j += 1


def tokenize(src):
    toks = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]

        if c in " \t\r\n":
            i += 1
            continue

        # comments
        if src.startswith("--", i):
            lvl = _long_bracket_level(src, i + 2)
            if lvl is not None:
                _, i = _read_long_bracket(src, i + 2, lvl)
            else:
                nl = src.find("\n", i)
                i = n if nl < 0 else nl + 1
            continue

        # long-bracket string
        lvl = _long_bracket_level(src, i)
        if lvl is not None:
            text, end = _read_long_bracket(src, i, lvl)
            toks.append(Tok("str", text, i, end))
            i = end
            continue

        # quoted string
        if c in "\"'":
            text, end = _read_quoted(src, i)
            toks.append(Tok("str", text, i, end))
            i = end
            continue

        # number
        if c in _DIGITS or (c == "." and i + 1 < n and src[i + 1] in _DIGITS):
            j = i
            if src.startswith("0x", i) or src.startswith("0X", i):
                j = i + 2
                while j < n and (src[j] in "0123456789abcdefABCDEF.pP+-"):
                    if src[j] in "+-" and src[j - 1] not in "pP":
                        break
                    j += 1
            else:
                while j < n and (src[j] in _DIGITS or src[j] in ".eE"
                                 or (src[j] in "+-" and src[j - 1] in "eE")):
                    j += 1
            toks.append(Tok("num", src[i:j], i, j))
            i = j
            continue

        # name / keyword
        if c in _NAME_START:
            j = i
            while j < n and src[j] in _NAME_BODY:
                j += 1
            toks.append(Tok("name", src[i:j], i, j))
            i = j
            continue

        # operator
        for op in _OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, i, i + len(op)))
                i += len(op)
                break
        else:
            raise LuaSyntaxError("unexpected character %r at offset %d" % (c, i))

    toks.append(Tok("eof", None, n, n))
    return toks


# ---------------------------------------------------------------------------
# value tree
# ---------------------------------------------------------------------------

class Node(object):
    __slots__ = ("start", "end")


class Str(Node):
    """A string expression: one literal, or a `..` chain of literals."""
    __slots__ = ("value", "parts")

    def __init__(self, value, start, end, parts):
        self.value = value      # decoded, concatenated text
        self.start = start      # span of the WHOLE expression (quotes included)
        self.end = end
        self.parts = parts      # number of literals in the chain (>1 == was concatenated)

    def __repr__(self):
        return "Str(%r)" % (self.value,)


class Raw(Node):
    """Any expression we don't model (number, bool, nil, identifier, call...)."""
    __slots__ = ("text",)

    def __init__(self, text, start, end):
        self.text = text
        self.start = start
        self.end = end

    def __repr__(self):
        return "Raw(%s)" % (self.text,)


class Table(Node):
    """A table constructor. `array` = positional items, `map` = key -> value."""
    __slots__ = ("array", "map", "order")

    def __init__(self, array, map_, order, start, end):
        self.array = array      # list[Node]
        self.map = map_         # dict[str, Node]
        self.order = order      # list[str] -- key order as written
        self.start = start
        self.end = end

    def get(self, key, default=None):
        return self.map.get(key, default)

    def __repr__(self):
        return "Table(arr=%d, keys=%s)" % (len(self.array), self.order)


class Parser(object):
    def __init__(self, src, toks):
        self.src = src
        self.toks = toks
        self.i = 0

    def peek(self, k=0):
        return self.toks[min(self.i + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def accept(self, kind, val=None):
        t = self.peek()
        if t.kind == kind and (val is None or t.val == val):
            self.i += 1
            return t
        return None

    def expect(self, kind, val=None):
        t = self.accept(kind, val)
        if t is None:
            got = self.peek()
            raise LuaSyntaxError(
                "expected %s %r but got %s %r at offset %d"
                % (kind, val, got.kind, got.val, got.start))
        return t

    # -- expressions -------------------------------------------------------

    def parse_value(self):
        """Parse ONE value expression and return a Node."""
        t = self.peek()

        # string, possibly a `..` chain of strings
        if t.kind == "str":
            start = t.start
            parts = [self.next()]
            while (self.peek().kind == "op" and self.peek().val == ".."
                   and self.peek(1).kind == "str"):
                self.next()                    # consume '..'
                parts.append(self.next())      # consume the next literal
            end = parts[-1].end
            return Str("".join(p.val for p in parts), start, end, len(parts))

        if t.kind == "op" and t.val == "{":
            return self.parse_table()

        # anything else: consume a balanced run of tokens up to the next
        # separator at this nesting level -> a Raw node.
        return self.parse_raw()

    def parse_raw(self):
        """
        Consume ONE table item we don't model (number, bool, nil, a dotted
        reference, a nested call...). Only ever called INSIDE a table
        constructor, where the item boundary is unambiguous: a ',' / ';' / '}'
        at nesting depth 0.
        """
        start = self.peek().start
        depth = 0
        end = start
        while True:
            t = self.peek()
            if t.kind == "eof":
                break
            if t.kind == "op":
                if t.val in "({[":
                    depth += 1
                elif t.val in ")}]":
                    if depth == 0:
                        break
                    depth -= 1
                elif t.val in (",", ";") and depth == 0:
                    break
            end = t.end
            self.next()
        return Raw(self.src[start:end], start, end)

    def parse_table(self):
        open_tok = self.expect("op", "{")
        array = []
        map_ = {}
        order = []
        while True:
            if self.accept("op", "}"):
                break
            if self.accept("op", ",") or self.accept("op", ";"):
                continue

            # [ "key" ] = value    /   [ expr ] = value
            if self.peek().kind == "op" and self.peek().val == "[":
                save = self.i
                self.next()
                kt = self.peek()
                if kt.kind == "str":
                    self.next()
                    if self.accept("op", "]") and self.accept("op", "="):
                        key = kt.val
                        val = self.parse_value()
                        if key not in map_:
                            order.append(key)
                        map_[key] = val
                        continue
                self.i = save
                # not a string key -> treat the whole item as a positional raw
                array.append(self.parse_raw_item())
                continue

            # name = value
            if (self.peek().kind == "name" and self.peek().val not in KEYWORDS
                    and self.peek(1).kind == "op" and self.peek(1).val == "="):
                key = self.next().val
                self.next()  # '='
                val = self.parse_value()
                if key not in map_:
                    order.append(key)
                map_[key] = val
                continue

            # positional value
            array.append(self.parse_value())

        end = self.toks[self.i - 1].end
        return Table(array, map_, order, open_tok.start, end)

    def parse_raw_item(self):
        """Consume one comma-separated item, whatever it is, as Raw."""
        return self.parse_raw()


# ---------------------------------------------------------------------------
# top-level assignment scan
# ---------------------------------------------------------------------------

def parse_assigns(src, roots):
    """
    Find `<root>.<a>.<b> = <expr>` statements whose leading name is in `roots`,
    and parse each right-hand side.

    Returns a dict: "root.a.b" -> Node

    Only statements at brace/paren depth 0 are considered, so table *fields*
    (which look identical) are not mistaken for top-level assignments.
    """
    toks = tokenize(src)
    out = {}
    depth = 0
    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        if t.kind == "op":
            if t.val in "({[":
                depth += 1
            elif t.val in ")}]":
                depth -= 1

        if depth == 0 and t.kind == "name" and t.val in roots:
            # collect a dotted path
            def at(k):
                return toks[min(k, n - 1)]

            path = [t.val]
            j = i + 1
            while (at(j).kind == "op" and at(j).val == "."
                   and at(j + 1).kind == "name"):
                path.append(at(j + 1).val)
                j += 2
            toks_j = at(j)
            rhs = at(j + 1)
            is_assign = (toks_j.kind == "op" and toks_j.val == "="
                         and not (rhs.kind == "op" and rhs.val == "="))
            # We only model TABLE and STRING right-hand sides. Anything else
            # (numbers, booleans, references) we skip -- there is no reliable
            # statement terminator in Lua, so guessing where a bare expression
            # ends is exactly how a naive parser runs away and eats the file.
            if is_assign and (rhs.kind == "str"
                              or (rhs.kind == "op" and rhs.val == "{")):
                p = Parser(src, toks)
                p.i = j + 1
                node = p.parse_value()
                out[".".join(path)] = node
                i = p.i
                continue
        i += 1
    return out


# ---------------------------------------------------------------------------
# escaping (for write-back)
# ---------------------------------------------------------------------------

def lua_quote(s):
    """Render a Python string as a double-quoted Lua literal."""
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 0x20:
            out.append("\\%d" % ord(ch))
        else:
            out.append(ch)          # UTF-8 passes through untouched
    out.append('"')
    return "".join(out)


def sanity_check(src, roots):
    """
    Structural verification used when no `lua`/`luac` binary is available.
    Raises LuaSyntaxError if the source no longer tokenizes cleanly, if the
    brackets are unbalanced, or if the top-level assignments won't re-parse.
    """
    toks = tokenize(src)                     # raises on an unterminated string
    depth = {"(": 0, "{": 0, "[": 0}
    pairs = {")": "(", "}": "{", "]": "["}
    for t in toks:
        if t.kind == "op":
            if t.val in depth:
                depth[t.val] += 1
            elif t.val in pairs:
                depth[pairs[t.val]] -= 1
                if depth[pairs[t.val]] < 0:
                    raise LuaSyntaxError("unbalanced %r at offset %d" % (t.val, t.start))
    for k, v in depth.items():
        if v != 0:
            raise LuaSyntaxError("unbalanced %r (delta %d)" % (k, v))
    return parse_assigns(src, roots)         # raises if an RHS won't parse
