"""
ops.py -- STRUCTURAL edits, expressed as byte splices.

The rule that must never be broken: we do not re-serialize Lua tables. config.lua
is 800+ lines of load-bearing comments and this tool is not allowed to lose one of
them. So a structural edit inserts or deletes WHOLE TABLE ENTRIES in place, and
everything else in the file stays byte-identical.

The client never computes a structural byte offset. It sends a high-level op
naming a tree / node / choice; the server re-parses the file it is about to write
and resolves the op against the CURRENT parse tree. That means an op can't be
stale, and it means the offsets always come from the same parser that verifies
the result.

Supported ops
-------------
  setField    set / clear one field on a line or choice  (`sfx`, `to`)
  addChoice   append a reply option to a node
  deleteChoice
  addNode     create a node AND the link that reaches it (never an orphan)
  deleteNode  refuses while any choice still points at it, or if it's `start`
"""

import re

import luaparse
from luaparse import Table, Str

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class OpError(Exception):
    """A structural op that must not be applied. Message is shown to the user."""


# ---------------------------------------------------------------------------
# resolving an op's target in the freshly-parsed tree
# ---------------------------------------------------------------------------

def resolve_tree(assigns, ref):
    """ref = {assign: "Config.date", sub: ["seatedTree"]} -> the tree's Table."""
    node = assigns.get(ref["assign"])
    if node is None:
        raise OpError("Can't find %s in the file any more." % ref["assign"])
    for k in ref.get("sub") or []:
        if not isinstance(node, Table):
            raise OpError("Can't walk to %s.%s." % (ref["assign"], k))
        node = node.get(k)
        if node is None:
            raise OpError("Can't find %s.%s in the file any more."
                          % (ref["assign"], k))
    if not isinstance(node, Table):
        raise OpError("%s is not a table." % ref["assign"])
    return node


def nodes_table(tree):
    nt = tree.get("nodes")
    if not isinstance(nt, Table):
        raise OpError("That tree has no `nodes` table.")
    return nt


def get_node(tree, key):
    n = nodes_table(tree).get(key)
    if not isinstance(n, Table):
        raise OpError('Node "%s" is not in the tree any more — reload the page.' % key)
    return n


def get_target(tree, addr):
    """addr = {node, src: jackie|jackiePool|choices, index} -> the item's Table."""
    node = get_node(tree, addr["node"])
    src = addr.get("src")
    if src == "jackie":
        t = node.get("jackie")
        if not isinstance(t, Table):
            raise OpError('Node "%s" has no `jackie` line.' % addr["node"])
        return t
    if src not in ("jackiePool", "choices"):
        raise OpError("Unknown target %r." % src)
    arr = node.get(src)
    if not isinstance(arr, Table):
        raise OpError('Node "%s" has no `%s`.' % (addr["node"], src))
    i = int(addr["index"])
    if not (0 <= i < len(arr.array)):
        raise OpError('%s[%d] no longer exists on node "%s" — reload the page.'
                      % (src, i + 1, addr["node"]))
    item = arr.array[i]
    if not isinstance(item, Table):
        raise OpError("That entry isn't an editable table.")
    return item


# ---------------------------------------------------------------------------
# rendering new entries (the ONLY place we emit Lua)
# ---------------------------------------------------------------------------

def render_choice(text, to, m=None):
    bits = ["text = %s" % luaparse.lua_quote(text)]
    bits.append("to = %s" % (luaparse.lua_quote(to) if to else "nil"))
    if m:
        bits.append("m = { text = %s }" % luaparse.lua_quote(m))
    return "{ %s }" % ", ".join(bits)


def render_line(text, sfx=None, m=None, msfx=None):
    bits = ["text = %s" % luaparse.lua_quote(text)]
    if sfx:
        bits.append("sfx = %s" % luaparse.lua_quote(sfx))
    if m:
        mb = ["text = %s" % luaparse.lua_quote(m)]
        if msfx:
            mb.append("sfx = %s" % luaparse.lua_quote(msfx))
        bits.append("m = { %s }" % ", ".join(mb))
    return "{ %s }" % ", ".join(bits)


def render_node(src, nodes_tbl, key, line, choices):
    """
    A whole `key = { jackiePool = {...}, choices = {...} }` entry.

    insert_entry prefixes the FIRST line with the table's entry indent, so every
    continuation line here has to be measured from that same base -- otherwise the
    node lands with its body under-indented and the file reads badly.
    """
    base = luaparse.entry_indent(src, nodes_tbl)   # where `key = {` will sit
    i1 = base + "  "        # inside the node
    i2 = base + "    "      # inside jackiePool / choices
    out = ["%s = {" % key]
    out.append("%sjackiePool = {" % i1)
    out.append("%s%s," % (i2, line))
    out.append("%s}," % i1)
    if choices:
        out.append("%schoices = {" % i1)
        for c in choices:
            out.append("%s%s," % (i2, c))
        out.append("%s}," % i1)
    out.append("%s}" % base)
    return "\n".join(out)


# ---------------------------------------------------------------------------
# the ops
# ---------------------------------------------------------------------------

def op_set_field(src, tree, op):
    """Set or clear `sfx` / `to` on a line or choice."""
    key = op["key"]
    if key not in ("sfx", "to"):
        raise OpError("Only `sfx` and `to` can be set this way (not %r)." % key)

    target = get_target(tree, op["addr"])

    # the Hermano sub-table has its own sfx
    if op.get("variant") == "m":
        m = target.get("m")
        if not isinstance(m, Table):
            raise OpError("That line has no Hermano (`m`) variant to put an sfx on.")
        target = m

    value = op.get("value")
    if value is not None:
        value = str(value).strip()
    if not value:
        value = None

    if key == "sfx":
        lit = luaparse.lua_quote(value) if value else None
        return luaparse.set_field(src, target, "sfx", lit)

    # `to`: an empty value means "ends the conversation"
    if value:
        return luaparse.set_field(src, target, "to", luaparse.lua_quote(value))
    # keep an explicit `to = nil` if one is already written (it's the house style)
    if target.entry("to") is not None:
        return luaparse.set_field(src, target, "to", "nil")
    return []


def op_add_choice(src, tree, op):
    node = get_node(tree, op["node"])
    text = (op.get("text") or "").strip()
    if not text:
        raise OpError("A reply option needs some text.")
    to = (op.get("to") or "").strip() or None
    if to and nodes_table(tree).get(to) is None:
        raise OpError('This reply would point at "%s", which is not a node in '
                      'this tree.' % to)

    ch = node.get("choices")
    entry = render_choice(text, to, (op.get("m") or "").strip() or None)
    if isinstance(ch, Table):
        return luaparse.insert_entry(src, ch, entry)

    # the node has no `choices` table at all -> create one, aligned to the node's
    # own fields (insert_entry indents the first line for us).
    base = luaparse.entry_indent(src, node)
    block = "choices = {\n%s  %s,\n%s}" % (base, entry, base)
    return luaparse.insert_entry(src, node, block)


def op_delete_choice(src, tree, op):
    node = get_node(tree, op["node"])
    ch = node.get("choices")
    i = int(op["index"])
    if not isinstance(ch, Table) or not (0 <= i < len(ch.array)):
        raise OpError('That reply option is no longer on node "%s" — reload.'
                      % op["node"])
    entry = ch.item(i)

    # removing the LAST choice would leave an empty `choices = {}`, which the mod
    # reads as "no options" -- same as having no choices key. Drop the whole table
    # so the node reads cleanly as a terminal.
    if len(ch.array) == 1:
        e = node.entry("choices")
        return [luaparse.delete_entry(src, node, e)]
    return [luaparse.delete_entry(src, ch, entry)]


def op_add_node(src, tree, op):
    """
    Create a node AND the link that reaches it. Linking is mandatory -- an
    orphan node is invisible in-game, so we never make one.
    """
    nt = nodes_table(tree)
    key = (op.get("key") or "").strip()
    if not IDENT.match(key):
        raise OpError('"%s" is not a valid node name. Use letters, numbers and '
                      'underscores, starting with a letter (e.g. "bike_thanks").'
                      % key)
    if nt.get(key) is not None:
        raise OpError('This tree already has a node called "%s".' % key)

    text = (op.get("text") or "").strip()
    if not text:
        raise OpError("The new node needs a line for Jackie to say.")

    link = op.get("link") or {}
    parent = (link.get("node") or "").strip()
    if not parent:
        raise OpError("Pick which node should lead to the new one — a node "
                      "nothing points at can never be reached in-game.")
    parent_tbl = get_node(tree, parent)

    # the new node's own way out (optional -- no choices == a terminal node)
    out = []
    oc = op.get("out") or {}
    if (oc.get("text") or "").strip():
        oto = (oc.get("to") or "").strip() or None
        if oto and oto != key and nt.get(oto) is None:
            raise OpError('The new node\'s reply points at "%s", which is not a '
                          'node in this tree.' % oto)
        out.append(render_choice(oc["text"].strip(), oto))

    line = render_line(text, (op.get("sfx") or "").strip() or None,
                       (op.get("m") or "").strip() or None)
    splices = luaparse.insert_entry(src, nt, render_node(src, nt, key, line, out))

    # --- the link in ---------------------------------------------------------
    mode = link.get("mode") or "newChoice"
    if mode == "repoint":
        i = int(link["index"])
        ch = parent_tbl.get("choices")
        if not isinstance(ch, Table) or not (0 <= i < len(ch.array)):
            raise OpError("That reply option no longer exists — reload.")
        splices += luaparse.set_field(src, ch.array[i], "to",
                                      luaparse.lua_quote(key))
    else:
        ctext = (link.get("text") or "").strip()
        if not ctext:
            raise OpError("The reply option that leads to the new node needs text.")
        entry = render_choice(ctext, key)
        ch = parent_tbl.get("choices")
        if isinstance(ch, Table):
            splices += luaparse.insert_entry(src, ch, entry)
        else:
            base = luaparse.entry_indent(src, parent_tbl)
            block = "choices = {\n%s  %s,\n%s}" % (base, entry, base)
            splices += luaparse.insert_entry(src, parent_tbl, block)

    return splices


def op_delete_node(src, tree, op):
    """
    Refuse while anything still points at the node. A dangling `to` is valid Lua
    and a broken quest -- exactly the failure this tool exists to prevent -- so we
    name the offending choices and make the user repoint them first.
    """
    nt = nodes_table(tree)
    key = op["key"]
    if nt.get(key) is None:
        raise OpError('Node "%s" is already gone — reload.' % key)

    start = tree.get("start")
    if isinstance(start, Str) and start.value == key:
        raise OpError('"%s" is the START node — the conversation begins there. '
                      'Point `start` at another node first.' % key)

    refs = []
    for nkey in nt.order:
        n = nt.map[nkey]
        if not isinstance(n, Table):
            continue
        ch = n.get("choices")
        if not isinstance(ch, Table):
            continue
        for i, c in enumerate(ch.array):
            if not isinstance(c, Table):
                continue
            to = c.get("to")
            if isinstance(to, Str) and to.value == key:
                txt = c.get("text")
                refs.append('%s → reply %d ("%s")'
                            % (nkey, i + 1,
                               (txt.value[:36] + "…") if isinstance(txt, Str) else "?"))
    if refs:
        raise OpError(
            'Can\'t delete "%s" — %d reply option%s still lead%s to it:\n\n  • %s\n\n'
            'Repoint or delete those first, or the conversation would dead-end '
            'there in-game.'
            % (key, len(refs), "" if len(refs) == 1 else "s",
               "s" if len(refs) == 1 else "", "\n  • ".join(refs)))

    return [luaparse.delete_entry(src, nt, nt.entry(key))]


HANDLERS = {
    "setField": op_set_field,
    "addChoice": op_add_choice,
    "deleteChoice": op_delete_choice,
    "addNode": op_add_node,
    "deleteNode": op_delete_node,
}

# Ops carry indices captured from the page (choice 3 of node "hub"). Applying them
# in the wrong order invalidates those indices, so we fix the order here rather
# than trust whatever sequence the UI happened to queue them in:
#
#   1. setField    -- pure value changes, no index moves
#   2. addChoice / addNode -- always APPEND, so existing indices are untouched
#   3. deleteChoice -- highest index FIRST, so the lower ones stay valid
#   4. deleteNode   -- last; by then every choice that pointed at it is gone
PHASE = {"setField": 0, "addNode": 1, "addChoice": 1,
         "deleteChoice": 2, "deleteNode": 3}


def order_ops(ops_list):
    def sort_key(o):
        t = o.get("type")
        phase = PHASE.get(t, 1)
        # within deleteChoice: same node, descending index
        idx = -int(o.get("index", 0)) if t == "deleteChoice" else 0
        return (phase, o.get("node") or "", idx)
    return sorted(ops_list, key=sort_key)


def splices_for(src, assigns, ops):
    """Resolve every op against the current parse of `src` -> a list of splices."""
    out = []
    for op in ops:
        h = HANDLERS.get(op.get("type"))
        if not h:
            raise OpError("Unknown operation %r." % op.get("type"))
        tree = resolve_tree(assigns, op["ref"])
        out.extend(h(src, tree, op))

    # Two ops that both append to the same table each emit the identical
    # "the last entry needs a trailing comma" splice. Emitting it twice would
    # write `,,`. Dedupe exact duplicates.
    seen = set()
    uniq = []
    for s in out:
        if s in seen:
            continue
        seen.add(s)
        uniq.append(s)
    return uniq
