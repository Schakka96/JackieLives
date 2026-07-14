"""
extract.py -- turn the parsed Lua value tree into the dialogue model the
front end renders.

Nothing here ever *writes*. It only reads the value tree and records, for every
editable string, the (file, start, end) span of the literal in the raw source.
Saving is a pure byte-splice against those spans (see serve.py).
"""

import luaparse
from luaparse import Str, Table, Raw

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

CONFIG = "config"
RETRIEVAL = "retrieval"


def field(fkey, node):
    """Make an editable field from a Str node. Returns None for anything else."""
    if not isinstance(node, Str):
        return None
    return {
        "id": "%s:%d:%d" % (fkey, node.start, node.end),
        "file": fkey,
        "start": node.start,
        "end": node.end,
        "value": node.value,
        "concat": node.parts > 1,
    }


def raw_text(node):
    """Best-effort readable rendering of a non-string node (for badges)."""
    if isinstance(node, Str):
        return node.value
    if isinstance(node, Raw):
        return node.text.strip()
    if isinstance(node, Table):
        return "{...}"
    return None


def str_value(node):
    return node.value if isinstance(node, Str) else None


# metadata we surface as read-only badges on a line/choice
META_KEYS = ("chance", "once", "final", "dur", "to", "action", "restaurantPicker",
             "cooldownSeconds", "drinks", "key")


def meta_of(tbl, skip=()):
    out = {}
    if not isinstance(tbl, Table):
        return out
    for k in tbl.order:
        if k in ("text", "sfx", "m", "textPool") or k in skip:
            continue
        if k in META_KEYS:
            v = raw_text(tbl.map[k])
            if v is not None:
                out[k] = v
    return out


def line_from(fkey, tbl, kind="line"):
    """A spoken line: { text, sfx, m = { text } }."""
    if isinstance(tbl, Str):          # a bare string in a plain array pool
        f = field(fkey, tbl)
        return {"kind": kind, "text": f, "m": None, "sfx": None,
                "speaker": None, "meta": {}, "textPool": None}
    if not isinstance(tbl, Table):
        return None

    m_tbl = tbl.get("m")
    m_field = field(fkey, m_tbl.get("text")) if isinstance(m_tbl, Table) else None

    pool = None
    tp = tbl.get("textPool")
    if isinstance(tp, Table):
        pool = [field(fkey, x) for x in tp.array if isinstance(x, Str)]

    return {
        "kind": kind,
        "text": field(fkey, tbl.get("text")),
        "m": m_field,
        "sfx": str_value(tbl.get("sfx")),
        "sfxM": str_value(m_tbl.get("sfx")) if isinstance(m_tbl, Table) else None,
        "speaker": str_value(tbl.get("speaker")),
        "textPool": pool,
        "meta": meta_of(tbl),
    }


# ---------------------------------------------------------------------------
# trees
# ---------------------------------------------------------------------------

def tree_from(fkey, tbl, sid, title, subtitle="", ref=None):
    """Config.<x>Tree = { start = "k", nodes = { k = {...} } }"""
    if not isinstance(tbl, Table):
        return None
    nodes_tbl = tbl.get("nodes")
    if not isinstance(nodes_tbl, Table):
        return None

    start = str_value(tbl.get("start"))
    nodes = []
    for key in nodes_tbl.order:
        n = nodes_tbl.map[key]
        if not isinstance(n, Table):
            continue

        # `addr` is how a structural op names this exact line/choice. The server
        # re-parses the file and walks the same path, so the client never has to
        # compute a byte offset for anything structural.
        lines = []
        single = n.get("jackie")
        if isinstance(single, Table):
            ln = line_from(fkey, single)
            if ln:
                ln["addr"] = {"node": key, "src": "jackie", "index": 0}
                lines.append(ln)
        pool = n.get("jackiePool")
        if isinstance(pool, Table):
            for i, item in enumerate(pool.array):
                ln = line_from(fkey, item)
                if ln:
                    ln["addr"] = {"node": key, "src": "jackiePool", "index": i}
                    lines.append(ln)

        choices = []
        ch_tbl = n.get("choices")
        if isinstance(ch_tbl, Table):
            for i, c in enumerate(ch_tbl.array):
                if not isinstance(c, Table):
                    continue
                ch = line_from(fkey, c, kind="choice")
                ch["to"] = str_value(c.get("to"))          # None when `to = nil`
                ch["action"] = str_value(c.get("action"))
                ch["addr"] = {"node": key, "src": "choices", "index": i}
                # `cond` is a real Lua FUNCTION. Show it, never touch it.
                cnd = c.get("cond")
                ch["cond"] = cnd.text if isinstance(cnd, Raw) else None
                fct = c.get("fact")
                if isinstance(fct, Table):
                    ch["fact"] = {"name": str_value(fct.get("name")),
                                  "value": raw_text(fct.get("value"))}
                choices.append(ch)

        action = str_value(n.get("action"))
        extra = {}
        if isinstance(n.get("restaurantPicker"), Raw):
            extra["restaurantPicker"] = raw_text(n.get("restaurantPicker"))

        nodes.append({
            "key": key,
            "isStart": key == start,
            "lines": lines,
            "choices": choices,
            "action": action,
            "extra": extra,
            # terminal: nothing leaves this node
            "terminal": not any(c.get("to") for c in choices),
        })

    cooldown = raw_text(tbl.get("cooldownSeconds")) if tbl.get("cooldownSeconds") else None
    mute = raw_text(tbl.get("muteFallback")) if tbl.get("muteFallback") else None

    return {
        "id": sid, "kind": "tree", "title": title, "subtitle": subtitle,
        "file": fkey, "start": start, "nodes": nodes, "cooldownSeconds": cooldown,
        "muteFallback": mute, "ref": ref,
    }


def pool_from(fkey, sid, title, subtitle, columns):
    """columns = [(column title, Table|None)] -- parallel Husbando / Hermano pools."""
    cols = []
    for ctitle, tbl in columns:
        lines = []
        if isinstance(tbl, Table):
            if tbl.array:
                for item in tbl.array:
                    ln = line_from(fkey, item)
                    if ln:
                        lines.append(ln)
            else:                                   # keyed map (Config.hermanoLines)
                for k in tbl.order:
                    ln = line_from(fkey, tbl.map[k])
                    if ln:
                        ln["poolKey"] = k
                        lines.append(ln)
        # An absent variant pool (e.g. a note with no `linesM`) would render as an
        # empty column. Drop it -- Lua's mvar() falls through to the base pool anyway.
        if lines:
            cols.append({"title": ctitle, "lines": lines})
    if not cols:
        return None
    return {"id": sid, "kind": "pool", "title": title, "subtitle": subtitle,
            "file": fkey, "columns": cols}


def fields_from(fkey, sid, title, subtitle, rows):
    """rows = [(label, base Node|None, m Node|None, sfx str|None)]"""
    out = []
    for label, base, mnode, sfx in rows:
        fb = field(fkey, base)
        fm = field(fkey, mnode)
        if fb is None and fm is None:
            continue
        out.append({"label": label, "text": fb, "m": fm, "sfx": sfx})
    if not out:
        return None
    return {"id": sid, "kind": "fields", "title": title, "subtitle": subtitle,
            "file": fkey, "fields": out}


# ---------------------------------------------------------------------------
# the actual JackieLives layout
# ---------------------------------------------------------------------------

def build(config_src, retrieval_src):
    C = luaparse.parse_assigns(config_src, {"Config"})
    R = luaparse.parse_assigns(retrieval_src, {"M"})

    def c(path):
        return C.get(path)

    date = c("Config.date")
    call = c("Config.call")
    venue = c("Config.venueGreet")
    dismiss = c("Config.dismiss")
    locdlg = c("Config.locationDialogue")
    rcfg = R.get("M.Config")

    groups = []
    warnings = []

    # ---------------- Jackie ----------------
    jackie = []

    def add(sec):
        if sec:
            jackie.append(sec)
        return sec

    def ref(assign, *sub):
        return {"file": CONFIG, "assign": assign, "sub": list(sub)}

    add(tree_from(CONFIG, c("Config.reunionCallTree"), "reunionCallTree",
                  "Reunion call", "The long phone call after the shard. THE emotional payoff.",
                  ref("Config.reunionCallTree")))
    add(tree_from(CONFIG, c("Config.reunionMeetTree"), "reunionMeetTree",
                  "Reunion — first meeting", "Face to face when he walks in.",
                  ref("Config.reunionMeetTree")))
    add(tree_from(CONFIG, c("Config.blazeFinaleTree"), "blazeFinaleTree",
                  "Blaze finale", "After the finale: the biochip reveal.",
                  ref("Config.blazeFinaleTree")))
    add(tree_from(CONFIG, c("Config.callTree"), "callTree",
                  "Holocall — call him onto a gig", "The everyday phone call.",
                  ref("Config.callTree")))
    add(tree_from(CONFIG, c("Config.dialogueTree"), "dialogueTree",
                  "Generic talk tree", "The original v0.23 tree (fallback).",
                  ref("Config.dialogueTree")))

    LOC_TITLES = {
        "noodle": ("At the noodle bar", "Daytime, casual, food."),
        "coyote": ("At El Coyote Cojo", "Mama Welles' bar — family, drinks."),
        "afterlife": ("At the Afterlife", "Merc legends bar, night — bittersweet."),
        "misty": ("At Misty's Esoterica", "Calm, spiritual, his girl Misty."),
        "everywhere": ("Anywhere else (backup)", "Short 2-option exchange, 60s cooldown."),
    }
    if isinstance(locdlg, Table):
        for key in locdlg.order:
            t, sub = LOC_TITLES.get(key, (key, ""))
            add(tree_from(CONFIG, locdlg.map[key], "loc." + key, t, sub,
                          ref("Config.locationDialogue", key)))

    if isinstance(date, Table):
        add(tree_from(CONFIG, date.get("tree"), "date.tree",
                      "Dinner — the invite", "V asks him out; the venue picker.",
                      ref("Config.date", "tree")))
        add(tree_from(CONFIG, date.get("seatedTree"), "date.seatedTree",
                      "Dinner — seated small talk", "Only while he's seated at dinner.",
                      ref("Config.date", "seatedTree")))

    if isinstance(call, Table):
        add(pool_from(CONFIG, "arrivalGreetings", "Arrival greetings",
                      "He says one of these when he walks up after a summon.",
                      [("Husbando (female V)", call.get("arrivalGreetings")),
                       ("Hermano (male V)", call.get("arrivalGreetingsM"))]))
    if isinstance(venue, Table):
        add(pool_from(CONFIG, "venueGreet", "Venue hello (first approach of the day)",
                      "Called out across the bar the first time you approach him each in-game day.",
                      [("Husbando (female V)", venue.get("greetings")),
                       ("Hermano (male V)", venue.get("greetingsM"))]))
    if isinstance(dismiss, Table):
        add(pool_from(CONFIG, "partingPool", "Parting lines (send-off)",
                      "Picked at random when you send him home.",
                      [("Husbando (female V)", dismiss.get("partingPool")),
                       ("Hermano (male V)", dismiss.get("partingPoolM"))]))
        add(fields_from(CONFIG, "dismiss.fields", "Send-off — fixed lines", "", [
            ("V's send-off choice (menu text)", dismiss.get("choiceText"), None, None),
            ("Fallback parting line", dismiss.get("partingText"), None,
             str_value(dismiss.get("partingSfx"))),
        ]))

    add(pool_from(CONFIG, "hermanoLines", "Hermano line map (male-V overrides)",
                  "Keyed by the clip id of the Husbando line it replaces. "
                  "One edit here fixes that line in EVERY tree that uses the clip.",
                  [("Hermano replacement", c("Config.hermanoLines"))]))

    if isinstance(date, Table):
        rows = [
            ("Dinner invite (V's menu option)", date.get("inviteText"), None, None),
            ("Accept — heading out", date.get("ackText"), None, str_value(date.get("ackSfx"))),
            ("Seated, 2s after sitting", date.get("doneText"), None, str_value(date.get("doneSfx"))),
            ("V walks off — he gets up", date.get("getUpText"), None, str_value(date.get("getUpSfx"))),
            ("Refuse (already ate today)", date.get("refuseText"), None, str_value(date.get("refuseSfx"))),
            ("Objective banner (food)", date.get("objectiveText"), None, None),
            ("Objective banner (drinks)", date.get("objectiveTextDrinks"), None, None),
        ]
        ji = date.get("jackieInvite")
        if isinstance(ji, Table):
            rows.append(("Jackie's hungry hint (he starts it)",
                         ji.get("text"), None, str_value(ji.get("sfx"))))
        add(fields_from(CONFIG, "date.fields", "Dinner — one-liners",
                        "Single spoken beats around the dinner outing.", rows))

        rest = date.get("restaurants")
        if isinstance(rest, Table):
            rows = []
            for r in rest.array:
                if not isinstance(r, Table):
                    continue
                k = str_value(r.get("key")) or "?"
                rows.append(('Venue name — "%s"' % k, r.get("name"), None, None))
                if isinstance(r.get("pickText"), Str):
                    rows.append(('He picks it — "%s"' % k, r.get("pickText"), None,
                                 str_value(r.get("pickSfx"))))
            add(fields_from(CONFIG, "date.restaurants", "Dinner — venues",
                            "Venue names shown in the picker + his 'you pick' lines.", rows))

    add(pool_from(CONFIG, "testDialogue", "Test dialogue (debug scene)",
                  "The old scripted V<->Jackie test exchange. Debug only.",
                  [("Lines", c("Config.testDialogue"))]))

    groups.append({"npc": "Jackie", "sections": jackie})

    # ---------------- V ----------------
    v = []
    v.append(pool_from(CONFIG, "callFarewells", "Call sign-offs",
                       "V's hang-up line at the end of any call. Text only — V has no voice.",
                       [("V's lines", c("Config.callFarewells"))]))
    v.append(fields_from(CONFIG, "declineLine", "Main-quest refusal", "", [
        ("V's spoken refusal", c("Config.declineLine"), None, None),
        ("On-screen notice band", c("Config.mainQuestBlockNotice"), None, None),
    ]))
    groups.append({"npc": "V", "sections": [s for s in v if s]})

    # ---------------- Vik / notes + shards ----------------
    if isinstance(rcfg, Table):
        vik = fields_from(RETRIEVAL, "retrieval.tip", "Retrieval tip (the reveal)",
                          "Vik's lower-left popup when V returns to the clinic. "
                          "Long concatenated strings — saving rewrites them as one literal.",
                          [("Popup title", rcfg.get("tipTitle"), None, None),
                           ("The tip", rcfg.get("tipText"), rcfg.get("tipTextM"), None)])
        groups.append({"npc": "Vik", "sections": [s for s in [vik] if s]})

        notes = []
        shard = pool_from(RETRIEVAL, "retrieval.shard", "Jackie's shard (Rocky Ridge)",
                          "The note V reads at the Badlands hideout. Shown as one block, "
                          "one line per paragraph.",
                          [("Husbando (female V)", rcfg.get("shardLines")),
                           ("Hermano (male V)", rcfg.get("shardLinesM"))])
        if shard:
            title = fields_from(RETRIEVAL, "retrieval.shard.title", "", "",
                                [("Shard title", rcfg.get("shardTitle"), None, None)])
            if title:
                shard["titleFields"] = title["fields"]
            notes.append(shard)

        ps = rcfg.get("postShards")
        if isinstance(ps, Table):
            for idx, sh in enumerate(ps.array):
                if not isinstance(sh, Table):
                    continue
                t = str_value(sh.get("title")) or ("Post-reunion shard %d" % (idx + 1))
                sec = pool_from(RETRIEVAL, "retrieval.postShard.%d" % idx, t,
                                "Shown once, on proximity, after Jackie is back.",
                                [("Husbando (female V)", sh.get("lines")),
                                 ("Hermano (male V)", sh.get("linesM"))])
                if sec:
                    tf = fields_from(RETRIEVAL, "retrieval.postShard.%d.title" % idx, "", "",
                                     [("Shard title", sh.get("title"), None, None)])
                    if tf:
                        sec["titleFields"] = tf["fields"]
                    notes.append(sec)
        groups.append({"npc": "Notes / Shards", "sections": notes})
    else:
        warnings.append("retrieval.lua: could not find M.Config")

    # prune empty groups
    groups = [g for g in groups if g["sections"]]
    return groups, warnings


# ---------------------------------------------------------------------------
# GRAPH VALIDATION
#
# This is the gate that `luac -p` cannot be. A structural edit can produce a file
# that is PERFECTLY VALID LUA but a BROKEN DIALOGUE: delete a node that a choice
# still points at and luac is happy, while in-game Branch.start finds no node and
# the conversation dead-ends. Lua-valid != dialogue-valid.
#
#   ERRORS  block the save (the file is rewritten only if there are none):
#     * the tree's `start` node doesn't exist
#     * a choice's `to` names a node that isn't in the tree
#
#   WARNINGS never block -- they're surfaced in the UI before AND after saving:
#     * a node unreachable from `start` (deleting a choice may strand one; that
#       has to stay legal, or "delete choice is always allowed" is a lie)
#     * a terminal node with no `action` (legal -- it just ends the conversation)
# ---------------------------------------------------------------------------

def validate(groups):
    errors = []
    warnings = []
    info = []

    for g in groups:
        for s in g["sections"]:
            if s["kind"] != "tree":
                continue
            where = "%s / %s" % (g["npc"], s["title"])
            keys = [n["key"] for n in s["nodes"]]
            bykey = {n["key"]: n for n in s["nodes"]}

            if not s["start"]:
                errors.append({"section": s["id"], "msg":
                               "%s: the tree has no `start`." % where})
                continue
            if s["start"] not in bykey:
                errors.append({"section": s["id"], "node": s["start"], "msg":
                               "%s: `start` points at node \"%s\", which does not exist."
                               % (where, s["start"])})
                continue

            # every choice's `to` must resolve
            for n in s["nodes"]:
                for i, c in enumerate(n["choices"]):
                    if c.get("to") and c["to"] not in bykey:
                        errors.append({
                            "section": s["id"], "node": n["key"], "choice": i,
                            "msg": '%s: node "%s", choice %d ("%s") points at '
                                   '"%s" — no such node. In-game this conversation '
                                   'would DEAD-END here.'
                                   % (where, n["key"], i + 1,
                                      (c.get("text") or {}).get("value", "?")[:40],
                                      c["to"])})

            # reachability from start
            seen = set()
            stack = [s["start"]]
            while stack:
                k = stack.pop()
                if k in seen or k not in bykey:
                    continue
                seen.add(k)
                for c in bykey[k]["choices"]:
                    if c.get("to"):
                        stack.append(c["to"])
            for k in keys:
                if k not in seen:
                    warnings.append({
                        "section": s["id"], "node": k, "msg":
                        '%s: node "%s" is UNREACHABLE — no choice leads to it, so '
                        'the player can never see it.' % (where, k)})

            # terminals with no action anywhere. NOTE the action may sit on the
            # NODE (`action = "reunion_arrival"`) or on a CHOICE that ends the
            # conversation (`{ to = nil, action = "recruit_here" }`) -- both are
            # real. Only flag a node where neither exists.
            for n in s["nodes"]:
                if not n["terminal"]:
                    continue
                if n["action"] or any(c.get("action") for c in n["choices"]):
                    continue
                info.append({
                    "section": s["id"], "node": n["key"], "msg":
                    '%s: node "%s" just ends the conversation (no `action`). '
                    'That is legal — most sign-off nodes do exactly this.'
                    % (where, n["key"])})

    return errors, warnings, info


def validate_sources(config_src, retrieval_src):
    groups, _ = build(config_src, retrieval_src)
    return validate(groups)


def count_editable(groups):
    """(sections, nodes, editable string fields) -- for the startup report."""
    secs = nodes = fields_n = 0

    def bump_line(ln):
        nonlocal fields_n
        if ln.get("text"):
            fields_n += 1
        if ln.get("m"):
            fields_n += 1
        for p in (ln.get("textPool") or []):
            if p:
                fields_n += 1

    for g in groups:
        for s in g["sections"]:
            secs += 1
            if s["kind"] == "tree":
                for n in s["nodes"]:
                    nodes += 1
                    for ln in n["lines"]:
                        bump_line(ln)
                    for ch in n["choices"]:
                        bump_line(ch)
            elif s["kind"] == "pool":
                for col in s["columns"]:
                    for ln in col["lines"]:
                        bump_line(ln)
                for f in s.get("titleFields", []):
                    bump_line(f)
            elif s["kind"] == "fields":
                for f in s["fields"]:
                    bump_line(f)
    return secs, nodes, fields_n
