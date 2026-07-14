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


class Entry(object):
    """
    One item inside a table constructor, with the byte spans a structural edit
    needs:

      start      first byte of the entry (the key, or the value if positional)
      end        last byte of the VALUE (exclusive) -- before any trailing comma
      comma_end  byte after the trailing ',' / ';', or None if there isn't one
      key        the map key, or None for a positional (array) item
      value      the value Node
    """
    __slots__ = ("key", "value", "start", "end", "comma_end", "index")

    def __init__(self, key, value, start, end, index):
        self.key = key
        self.value = value
        self.start = start
        self.end = end
        self.comma_end = None
        self.index = index      # position among array items, else None

    def __repr__(self):
        return "Entry(%s)" % (self.key if self.key else "[%s]" % self.index)


class Table(Node):
    """A table constructor. `array` = positional items, `map` = key -> value."""
    __slots__ = ("array", "map", "order", "entries", "open_end", "close_start")

    def __init__(self, array, map_, order, entries, start, end,
                 open_end, close_start):
        self.array = array          # list[Node]
        self.map = map_             # dict[str, Node]
        self.order = order          # list[str] -- key order as written
        self.entries = entries      # list[Entry] -- every item, in source order
        self.start = start          # the '{'
        self.end = end              # after the '}'
        self.open_end = open_end    # byte after '{'
        self.close_start = close_start   # byte of '}'

    def get(self, key, default=None):
        return self.map.get(key, default)

    def entry(self, key):
        for e in self.entries:
            if e.key == key:
                return e
        return None

    def item(self, index):
        """The Entry for the index-th positional item."""
        for e in self.entries:
            if e.key is None and e.index == index:
                return e
        return None

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
        reference, or a `function() ... end` literal). Only ever called INSIDE a
        table constructor, where the item boundary is unambiguous: a ',' / ';' /
        '}' at nesting depth 0 AND outside any `... end` block.

        The block counter is what makes `cond = function() local f = x; return
        f() == 1 end` parse as ONE item. Without it the `;` inside the function
        body reads as an item separator, the function gets split in half, and any
        structural splice computed from those offsets would corrupt the file.

        Block openers that take a matching `end` are `function`, `if` and `do`.
        `for`/`while` are NOT counted -- their `do` is, and there is only one
        `end` between them.
        """
        start = self.peek().start
        depth = 0        # () [] {} nesting
        block = 0        # function/if/do ... end nesting
        end = start
        while True:
            t = self.peek()
            if t.kind == "eof":
                break
            if t.kind == "name":
                if t.val in ("function", "if", "do"):
                    block += 1
                elif t.val == "end":
                    block -= 1
                elif t.val == "repeat":
                    block += 1
                elif t.val == "until":
                    block -= 1
            elif t.kind == "op":
                if t.val in "({[":
                    depth += 1
                elif t.val in ")}]":
                    if depth == 0 and block <= 0:
                        break
                    if depth > 0:
                        depth -= 1
                elif t.val in (",", ";") and depth == 0 and block <= 0:
                    break
            end = t.end
            self.next()
        return Raw(self.src[start:end], start, end)

    def parse_table(self):
        open_tok = self.expect("op", "{")
        array = []
        map_ = {}
        order = []
        entries = []
        close_start = None

        while True:
            t = self.peek()
            if t.kind == "op" and t.val == "}":
                close_start = t.start
                self.next()
                break
            if t.kind == "eof":
                raise LuaSyntaxError("unterminated table from offset %d" % open_tok.start)
            # a stray separator (e.g. a trailing comma) -- attach it to the entry
            # we just finished, so deletion can take the comma with it.
            if t.kind == "op" and t.val in (",", ";"):
                self.next()
                if entries:
                    entries[-1].comma_end = t.end
                continue

            estart = t.start
            key = None
            val = None

            # [ "key" ] = value
            if t.kind == "op" and t.val == "[":
                save = self.i
                self.next()
                kt = self.peek()
                if kt.kind == "str":
                    self.next()
                    if self.accept("op", "]") and self.accept("op", "="):
                        key = kt.val
                        val = self.parse_value()
                if val is None:
                    self.i = save
                    val = self.parse_raw()

            # name = value
            elif (t.kind == "name" and t.val not in KEYWORDS
                  and self.peek(1).kind == "op" and self.peek(1).val == "="
                  and not (self.peek(2).kind == "op" and self.peek(2).val == "=")):
                key = self.next().val
                self.next()                     # '='
                val = self.parse_value()

            # positional value
            else:
                val = self.parse_value()

            if key is None:
                idx = len(array)
                array.append(val)
                entries.append(Entry(None, val, estart, val.end, idx))
            else:
                if key not in map_:
                    order.append(key)
                map_[key] = val
                entries.append(Entry(key, val, estart, val.end, None))

        end = self.toks[self.i - 1].end
        return Table(array, map_, order, entries, open_tok.start, end,
                     open_tok.end, close_start)


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


# ---------------------------------------------------------------------------
# structural splices
#
# A "splice" is (start, end, text): replace src[start:end] with text. Deleting is
# text="". Inserting is start==end. The caller applies them sorted by start
# DESCENDING, so earlier offsets stay valid.
#
# Everything here works on WHOLE TABLE ENTRIES. We never re-serialize a table, so
# every comment, blank line and unmodelled field in the file survives untouched.
# ---------------------------------------------------------------------------

def _line_start(src, i):
    j = src.rfind("\n", 0, i)
    return 0 if j < 0 else j + 1


def _indent_of(src, i):
    ls = _line_start(src, i)
    k = ls
    while k < len(src) and src[k] in " \t":
        k += 1
    return src[ls:k]


def delete_entry(src, table, entry):
    """
    Splice that removes one table entry.

    Two cases, and getting the second one wrong is what leaves a file that is
    valid but not byte-clean:

    * the entry has a trailing comma -> delete `entry,`. If it sits on its own
      line, take the indentation and the newline with it.

    * the entry is the LAST one and has no trailing comma (`{ text = "x", sfx =
      "y" }`) -> deleting just the entry would strand the separator before it
      (`{ text = "x",  }`). So we delete from the END OF THE PREVIOUS VALUE
      instead, taking the `, ` with us. That's what makes add-then-remove an
      exact byte round-trip.

    It deliberately STOPS BEFORE a trailing comment (`}, -- 1 = JL_BIKE_KEPT`).
    Comments are this project's documentation: we never delete one the user
    didn't explicitly ask us to. A stale comment left behind is cosmetic; a
    deleted one is lost work.
    """
    if entry.comma_end is None:
        prev = None
        for e in table.entries:
            if e is entry:
                break
            prev = e
        if prev is not None:
            # swallow the separator that precedes us
            return (prev.end, entry.end, "")

    start = entry.start
    end = entry.comma_end if entry.comma_end is not None else entry.end

    ls = _line_start(src, start)
    if src[ls:start].strip() == "":          # entry starts its own line
        start = ls

    j = end
    while j < len(src) and src[j] in " \t":
        j += 1
    if j < len(src) and src[j] == "\n":      # nothing but whitespace after it
        end = j + 1
    elif src[j:j + 2] == "\r\n":
        end = j + 2
    # else: a trailing comment follows -> keep it, stop at the comma

    return (start, end, "")


def entry_indent(src, table):
    """
    The indentation insert_entry will put a new entry at -- i.e. the indent of
    this table's existing entries. Callers that render a MULTI-LINE entry need it
    so their continuation lines line up with the first one.
    """
    if table.entries:
        return _indent_of(src, table.entries[-1].start)
    return _indent_of(src, table.start) + "  "


def insert_entry(src, table, text):
    """
    Splices that append `text` (one rendered entry, no trailing comma) as the
    LAST entry of `table`.

    Returns a LIST of splices, because an existing final entry with no trailing
    comma needs one adding -- Lua allows omitting it, and we must not produce
    `{ a = 1  b = 2 }`.

    The new entry goes on its own line just above the closing `}`, so it never
    steals a trailing comment that belongs to the entry before it.
    """
    out = []
    close = table.close_start
    ls = _line_start(src, close)
    multiline = src[ls:close].strip() == ""     # `}` sits on its own line

    if multiline:
        # A block table (nodes, choices, jackiePool). Put the new entry on a
        # clean line just above the `}` -- never straight after the previous
        # entry, or it would steal that entry's trailing comment.
        if table.entries:
            last = table.entries[-1]
            indent = _indent_of(src, last.start)
            if last.comma_end is None:
                out.append((last.end, last.end, ","))
        else:
            indent = _indent_of(src, table.start) + "  "
        out.append((ls, ls, "%s%s,\n" % (indent, text)))
        return out

    # An inline table -- `{ text = "x" }`, i.e. one line/choice. Anchor the
    # insert to the LAST ENTRY, not to the brace: inserting at the brace would
    # swallow the space in `" }"` and leave `"...sfx = "y"}`. Appending after the
    # last value keeps the original spacing byte-for-byte, and emits no trailing
    # comma -- which is exactly what lets delete_entry put it back to the letter.
    if not table.entries:
        out.append((table.open_end, table.open_end, " %s " % text))
        return out

    last = table.entries[-1]
    if last.comma_end is not None:
        out.append((last.comma_end, last.comma_end, " %s" % text))
    else:
        out.append((last.end, last.end, ", %s" % text))
    return out


def set_field(src, table, key, literal):
    """
    Splices that set `key = <literal>` on `table`, or REMOVE the key entirely
    when `literal` is None.

    * key present, literal given -> replace just the value's bytes
    * key present, literal None  -> delete the whole `key = value,` entry
    * key absent,  literal given -> insert a new entry
    * key absent,  literal None  -> nothing to do
    """
    e = table.entry(key)
    if e is not None:
        if literal is None:
            return [delete_entry(src, table, e)]
        return [(e.value.start, e.value.end, literal)]
    if literal is None:
        return []
    return insert_entry(src, table, "%s = %s" % (key, literal))


def apply_splices(src, splices):
    """Apply (start, end, text) triples back-to-front. Raises on any overlap."""
    ordered = sorted(splices, key=lambda s: (s[0], s[1]), reverse=True)
    prev_start = None
    for start, end, _ in ordered:
        if not (0 <= start <= end <= len(src)):
            raise LuaSyntaxError("splice %d-%d out of range" % (start, end))
        if prev_start is not None and end > prev_start:
            raise LuaSyntaxError(
                "overlapping splices (%d-%d overlaps a later one at %d)"
                % (start, end, prev_start))
        prev_start = start
    out = src
    for start, end, text in ordered:
        out = out[:start] + text + out[end:]
    return out


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
