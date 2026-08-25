#!/usr/bin/env python3
r"""Generate JackieLives' journal-quest + shard archive sources from the STORYBOARD.

    python3 tools/gen_journal_quests.py            # write everything
    python3 tools/gen_journal_quests.py --check    # verify the committed files are current (CI/Mac)

WHY THIS EXISTS
---------------
`mod/JackieLives/storyboard.lua` and `mod/JackieLives/sidequests.lua` are the single source of
truth for the story. Two of the things a beat can declare are player-facing engine content:

    journal = { quest = "ghost", phase = "p1", objective = "take_jackie_to_vik",
                text = "Take Jackie to Vik" }
    shard   = { id = "arc_scan", title = "...", author = "...", body = { "...", ... } }

Neither can be created at runtime. Both have to be BAKED into a `.journal` resource that
ArchiveXL merges into the game's journal tree, with the words in a separate localization
resource. Hand-maintaining that would be thousands of lines of CR2W-JSON that must stay
byte-perfectly in step with the Lua — the exact drift NCLives solved for SMS with
`tools/gen_messages.py`. This is the same trick for quests and shards.

Everything below is DERIVED. Never edit an output file; edit the storyboard and re-run.

WHAT IT WRITES
--------------
  archive/source/mod/jackielives/journal/jackielives_quests.journal.json
        the quest tree + the readable-shard entries (one CR2W-JSON resource)
  archive/source/mod/jackielives/questtext/<locale>/jackielives_questtext.json.json
        the words, per locale (quest titles, objective lines, shard bodies, item names)
  mod/JackieLives/journalquest_index.lua
        the paths + text journalquest.lua feeds to JournalManager:ChangeEntryState
  mod/JackieLives_shards/tweaks/JackieLives/jl_shards.yaml
        the TweakXL item + read-action record for every shard (deploys LOOSE, no archive)

Then, ON WINDOWS: `python tools\build_archive.py` (see the handoff note in
docs/research/journal_quests_and_shards_spec.md — build_archive.py needs a small patch to
notice non-localized sources like a .journal).

READ FIRST: docs/research/journal_quests_and_shards_spec.md — the verified class shapes, the
LocKey trap, and why we track an OBJECTIVE and never a quest.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, ".."))
MOD = os.path.join(PROJ, "mod", "JackieLives")
ARCH_SRC = os.path.join(PROJ, "archive", "source", "mod", "jackielives")
JDIR = os.path.join(ARCH_SRC, "journal")
TEXTDIR = os.path.join(ARCH_SRC, "questtext")
LUA_INDEX = os.path.join(MOD, "journalquest_index.lua")
SHARDS_DIR = os.path.join(PROJ, "mod", "JackieLives_shards")
YAML_OUT = os.path.join(SHARDS_DIR, "tweaks", "JackieLives", "jl_shards.yaml")
TRANS_DIR = os.path.join(HERE, "journal_text")

# en-us is canonical (the storyboard itself). Others read tools/journal_text/<locale>.txt, one
# RECORD per key, in the same order the keys are emitted, separated by a line containing only
# "%%". A blank record falls back to English. Shard bodies are multi-line, which is why this is
# record-separated rather than one-line-per-key like NCLives' SMS translations.
LOCALES = ["en-us", "ja-jp"]
SEP = "\n%%\n"

# ⚠️ NEVER key a localization entry by bare display text. The key is hashed with FNV-1a64 and a
# hash of a short English phrase can collide with a base-game entry, which crashes the game
# (BowieKnife99 shipped that bug once — see ../NCLives/docs/MESSAGES.md §2). Prefix everything.
KEY_PREFIX = "jl_j_"

# Where our quests live in the game's journal tree. Both folders exist in vanilla (VERIFIED-GAME,
# spec §3.1). "ghost" is a multi-part story, so it gets the SideQuest shelf; the Heywood jobs are
# MinorQuests. The uniquePath a player-visible objective is addressed by is therefore
#   quests/<folder>/<questId>/<phaseId>/<objectiveId>
QUEST_PLACEMENT = {
    "ghost": ("side_quest", "SideQuest"),
}
DEFAULT_PLACEMENT = ("minor_quest", "MinorQuest")

# Readable shards are onscreens, not quests, and they live on their own shelf:
#   onscreens/emails/quests/minor_quest/jl_shards/shards/<shardId>
# The leaf's parent is a gameJournalOnscreenGroup — a DIFFERENT class from the folders above it.
SHARD_FOLDERS = ["emails", "quests", "minor_quest", "jl_shards"]
SHARD_GROUP = "shards"
SHARD_PATH_PREFIX = "onscreens/" + "/".join(SHARD_FOLDERS) + "/" + SHARD_GROUP

# Shards that are NOT in the storyboard: the retrieval questline predates storyboard.lua and its
# note is given by retrieval.lua, not by a beat. The words are carried VERBATIM from the old
# mod/JackieLives_shards/localization/jl_shards.json so nothing is lost in the move.
EXTRA_SHARDS = [{
    "id": "jl_shard_badlands_note",
    "title": "Shard — Jackie Welles",
    "author": "Jackie Welles",
    "itemName": "Shard: Jackie Welles",
    "source": "retrieval.lua (Rocky Ridge hideout, stage 2)",
    "body": (
        "If you're readin' this, V, then the doc kept his word and you made it out here. "
        "It's me. I'm alive.\n"
        "\n"
        "Vik patched me up and smuggled me out before 'Saka could stamp my name on a slab. "
        "Been layin' low ever since.\n"
        "\n"
        "Mama Welles was so mad when she heard. Think she'd kill me if I went back runnin' the "
        "streets again — and this time, maybe she's right. I'm done with the merc life, V. "
        "For real. But I couldn't let you go on thinkin' you buried me.\n"
        "\n"
        "Give me a call when you read this. — Jackie"
    ),
}]


# ---------------------------------------------------------------------------- reading the Lua
# The storyboard is Lua, and Lua is the only thing that can read Lua correctly (its strings are
# built with `..` concatenation across a dozen source lines). So: run the real interpreter over
# the real files and have it hand us JSON. No regex parsing of the story, ever.

LUA_DUMPER = r"""
package.path = arg[1] .. "?.lua;" .. package.path
local esc = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}
local function q(s)
  s = tostring(s):gsub('[%z\1-\31"\\]', function(c)
    return esc[c] or string.format('\\u%04x', string.byte(c))
  end)
  return '"' .. s .. '"'
end
local buf = {}
local function w(s) buf[#buf+1] = s end

local function arr(list, fn)
  w('[')
  for i = 1, #list do if i > 1 then w(',') end; fn(list[i]) end
  w(']')
end

local function journalObj(b, owner, ownerTitle, ownerDesc, phaseTitle)
  local j = b.journal
  w('{"kind":"journal"')
  w(',"beat":' .. q(b.id))
  w(',"quest":' .. q(j.quest) .. ',"phase":' .. q(j.phase))
  w(',"objective":' .. q(j.objective) .. ',"text":' .. q(j.text or ""))
  w(',"owner":' .. q(owner) .. ',"ownerTitle":' .. q(ownerTitle or ""))
  w(',"ownerDesc":' .. q(ownerDesc or "") .. ',"phaseTitle":' .. q(phaseTitle or ""))
  w('}')
end

local function shardObj(b)
  local s = b.shard
  local body = s.body
  if type(body) == "table" then body = table.concat(body, "\n") end
  w('{"kind":"shard"')
  w(',"beat":' .. q(b.id))
  w(',"id":' .. q(s.id) .. ',"title":' .. q(s.title or ""))
  w(',"author":' .. q(s.author or "") .. ',"body":' .. q(body or ""))
  w('}')
end

local sb = require("storyboard")
local sq = require("sidequests")

w('{"arc":{"id":' .. q(sb.arc.id) .. ',"title":' .. q(sb.arc.title or ""))
w(',"desc":' .. q((sb.arc.opening_card or {}).text or "") .. '},"items":[')
local first = true
local function emit(fn, ...)
  if not first then w(',') end
  first = false
  fn(...)
end

for _, part in ipairs(sb.arc.parts or {}) do
  for _, b in ipairs(part.beats or {}) do
    if b.journal then
      emit(journalObj, b, sb.arc.id, sb.arc.title, (sb.arc.opening_card or {}).text, part.title)
    end
    if b.shard then emit(shardObj, b) end
  end
end
for _, quest in ipairs(sq.quests or {}) do
  for _, b in ipairs(quest.beats or {}) do
    if b.journal then
      emit(journalObj, b, quest.id, quest.title, quest.logline, quest.title)
    end
    if b.shard then emit(shardObj, b) end
  end
end
w(']}')
io.write(table.concat(buf))
"""


def find_lua():
    for exe in ("lua", "luajit", "lua5.4", "lua5.3", "lua5.1"):
        if shutil.which(exe):
            return exe
    raise SystemExit(
        "no Lua interpreter found (tried lua, luajit, lua5.4, lua5.3, lua5.1).\n"
        "  brew install lua   — this generator READS the storyboard with the real interpreter\n"
        "  rather than regex-parsing it, because its strings are built with `..` concatenation."
    )


def read_storyboard():
    """-> (arc dict, [journal/shard items in declaration order])."""
    script = os.path.join(HERE, ".gen_journal_dump.lua")
    with open(script, "w", encoding="utf-8", newline="\n") as f:
        f.write(LUA_DUMPER)
    try:
        raw = subprocess.run(
            [find_lua(), script, MOD + os.sep],
            capture_output=True, check=True,
        ).stdout.decode("utf-8")
    except subprocess.CalledProcessError as e:
        raise SystemExit("storyboard would not load:\n" + e.stderr.decode("utf-8", "replace"))
    finally:
        if os.path.isfile(script):
            os.remove(script)
    data = json.loads(raw)
    return data["arc"], data["items"]


# ------------------------------------------------------------------------- CR2W-JSON primitives

def fnv1a64(s):
    """CP2077 LocKey id = FNV-1a 64-bit of the key string.

    ArchiveXL registers a localization entry under this hash, and the journal's LocalizationString
    resolves against it. Writing the hash on BOTH sides (unk1 here, primaryKey there) is what our
    shipped NCLives pipeline does, so it is the form we know renders rather than showing a raw
    `LocKey#...` on screen.
    """
    h = 0xCBF29CE484222325
    for b in s.encode("utf-8"):
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return str(h)


def header(name):
    return {
        "WolvenKitVersion": "8.18.0",
        "WKitJsonVersion": "0.0.9",
        "GameVersion": 2310,
        "DataType": "CR2W",
        "ArchiveFileName": name,
    }


def loc(key):
    return {"unk1": fnv1a64(key), "value": key}


def cname(v):
    return {"$type": "CName", "$storage": "string", "$value": v}


def tdbid_zero():
    return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}


def noderef_zero():
    return {"$type": "NodeRef", "$storage": "uint64", "$value": "0"}


class Handles:
    """CR2W HandleIds must be unique within the resource. Dense integers, in emit order."""

    def __init__(self):
        self.n = 0

    def next(self):
        h = str(self.n)
        self.n += 1
        return h


# ------------------------------------------------------------------------------ the model
# One pass over the storyboard items turns them into the shape both the archive and the Lua
# index need. Order is DECLARATION order throughout: the tracker shows objectives in the order
# the writer wrote them, and a diff of a regenerated file stays readable.

ID_RE = re.compile(r"^[a-z0-9_]+$")


def key(*parts):
    k = KEY_PREFIX + "_".join(parts)
    if not ID_RE.match(k):
        raise SystemExit("localization key is not [a-z0-9_]: %r" % k)
    return k


def build_model(arc, items):
    quests, shards, warnings = {}, {}, []
    order = []

    for it in items:
        if it["kind"] == "shard":
            sid = it["id"]
            if sid in shards:
                raise SystemExit("two beats declare the same shard id %r (second: beat %s)"
                                 % (sid, it["beat"]))
            if not ID_RE.match(sid):
                raise SystemExit("shard id is not [a-z0-9_]: %r (beat %s)" % (sid, it["beat"]))
            shards[sid] = {
                "id": sid,
                "title": it["title"],
                "author": it["author"],
                "body": it["body"],
                # The inventory row's name. The shard's on-screen title comes from the JOURNAL
                # entry, not from here (spec §5.4.3) — this only shows in the Shards tab.
                "itemName": it["title"],
                "source": "beat " + it["beat"],
            }
            continue

        qid, pid, oid = it["quest"], it["phase"], it["objective"]
        for label, v in (("quest", qid), ("phase", pid), ("objective", oid)):
            if not ID_RE.match(v):
                raise SystemExit("journal %s id is not [a-z0-9_]: %r (beat %s)"
                                 % (label, v, it["beat"]))
        if qid not in quests:
            folder, qtype = QUEST_PLACEMENT.get(qid, DEFAULT_PLACEMENT)
            quests[qid] = {
                "id": qid, "title": it["ownerTitle"], "desc": it["ownerDesc"],
                "folder": folder, "type": qtype, "phases": {},
                "path": "quests/%s/%s" % (folder, qid),
            }
            order.append(qid)
            if qid != it["owner"]:
                # Not fatal and NOT something this tool may fix: the storyboard is the source of
                # truth for wording and ids. Surfaced so a human decides.
                warnings.append(
                    "beat %s declares journal quest %r but lives inside %r (%r). Using the "
                    "declared id %r and the container's title. If the id is the typo, fix it in "
                    "the storyboard — this tool will not."
                    % (it["beat"], qid, it["owner"], it["ownerTitle"], qid))
        q = quests[qid]
        if pid not in q["phases"]:
            q["phases"][pid] = {"id": pid, "title": it["phaseTitle"], "objectives": [],
                                "path": "%s/%s" % (q["path"], pid)}
        ph = q["phases"][pid]
        if any(o["id"] == oid for o in ph["objectives"]):
            raise SystemExit("duplicate objective %s/%s/%s (beat %s)" % (qid, pid, oid, it["beat"]))
        if not it["text"]:
            warnings.append("beat %s: journal objective %s/%s/%s has no `text` — the tracker line "
                            "would be blank." % (it["beat"], qid, pid, oid))
        ph["objectives"].append({
            "id": oid, "text": it["text"], "beat": it["beat"],
            "path": "%s/%s" % (ph["path"], oid),
        })

    for extra in EXTRA_SHARDS:
        if extra["id"] in shards:
            raise SystemExit("EXTRA_SHARDS id %r now also exists in the storyboard — delete the "
                             "hard-coded copy here, the storyboard wins." % extra["id"])
        shards[extra["id"]] = dict(extra)

    for s in shards.values():
        s["path"] = "%s/%s" % (SHARD_PATH_PREFIX, s["id"])
        s["item"] = "Items.jl_shard_" + s["id"] if not s["id"].startswith("jl_shard_") \
            else "Items." + s["id"]
        s["action"] = s["item"] + "_read"

    return [quests[q] for q in order], list(shards.values()), warnings


def collect_strings(quests, shards):
    """[(key, english)] in emit order. Every LocalizationString in the journal points at one."""
    out = []
    for q in quests:
        out.append((key("q", q["id"], "title"), q["title"]))
        if q["desc"]:
            out.append((key("q", q["id"], "desc"), q["desc"]))
        for ph in q["phases"].values():
            for o in ph["objectives"]:
                out.append((key("o", q["id"], ph["id"], o["id"]), o["text"]))
    for s in shards:
        out.append((key("s", s["id"], "title"), s["title"]))
        out.append((key("s", s["id"], "body"), s["body"]))
        out.append((key("s", s["id"], "item"), s["itemName"]))
        if s["author"]:
            out.append((key("s", s["id"], "by"), s["author"]))
    return out


# ------------------------------------------------------------------------- the .journal resource

def build_journal(quests, shards):
    h = Handles()
    root_h = h.next()

    # --- quests/<folder>/<quest>/<phase>/<objective>
    folders = {}
    folder_order = []
    for q in quests:
        entries = []
        if q["desc"]:
            entries.append({"HandleId": h.next(), "Data": {
                "$type": "gameJournalQuestDescription",
                "id": "desc",
                "description": loc(key("q", q["id"], "desc")),
                "journalEntryOverrideDataList": [],
            }})
        for ph in q["phases"].values():
            objs = []
            for o in ph["objectives"]:
                objs.append({"HandleId": h.next(), "Data": {
                    "$type": "gameJournalQuestObjective",
                    "id": o["id"],
                    "description": loc(key("o", q["id"], ph["id"], o["id"])),
                    "locationPrefabRef": noderef_zero(),
                    "journalEntryOverrideDataList": [],
                    "entries": [],     # no map pins in v1 — see spec §6
                }})
            entries.append({"HandleId": h.next(), "Data": {
                "$type": "gameJournalQuestPhase",
                "id": ph["id"],
                "locationPrefabRef": noderef_zero(),
                "journalEntryOverrideDataList": [],
                "entries": objs,
            }})
        # ⚠️ No districtID and recommendedLevelID 0 on purpose. Both are optional in vanilla
        # (258/360 and 280/360) and a district TweakDBID we cannot verify on the Mac is a risk
        # for no player-visible gain. `type` is NOT optional: omit it and the quest presents as
        # a MAIN quest (spec §3.2).
        quest_entry = {"HandleId": h.next(), "Data": {
            "$type": "gameJournalQuest",
            "id": q["id"],
            "title": loc(key("q", q["id"], "title")),
            "type": q["type"],
            "recommendedLevelID": tdbid_zero(),
            "journalEntryOverrideDataList": [],
            "entries": entries,
        }}
        if q["folder"] not in folders:
            folders[q["folder"]] = []
            folder_order.append(q["folder"])
        folders[q["folder"]].append(quest_entry)

    quest_folders = [{"HandleId": h.next(), "Data": {
        "$type": "gameJournalFolderEntry",
        "id": name,
        "journalEntryOverrideDataList": [],
        "entries": folders[name],
    }} for name in folder_order]

    # --- onscreens/emails/quests/minor_quest/jl_shards/shards/<shard>
    leaves = [{"HandleId": h.next(), "Data": {
        "$type": "gameJournalOnscreen",
        "id": s["id"],
        "title": loc(key("s", s["id"], "title")),
        "description": loc(key("s", s["id"], "body")),
        # Only generic collectibles carry a tag; a quest shard's is None (spec §5.2). A wrong tag
        # files the note under someone else's Codex category.
        "tag": cname("None"),
        "iconID": tdbid_zero(),
        "journalEntryOverrideDataList": [],
    }} for s in shards]

    node = {"HandleId": h.next(), "Data": {
        "$type": "gameJournalOnscreenGroup",
        "id": SHARD_GROUP,
        "journalEntryOverrideDataList": [],
        "entries": leaves,
    }}
    for name in reversed(SHARD_FOLDERS):
        node = {"HandleId": h.next(), "Data": {
            "$type": "gameJournalFolderEntry",
            "id": name,
            "journalEntryOverrideDataList": [],
            "entries": [node],
        }}

    primaries = [
        {"HandleId": h.next(), "Data": {
            "$type": "gameJournalPrimaryFolderEntry",
            "id": "quests",
            "journalEntryOverrideDataList": [],
            "entries": quest_folders,
        }},
        {"HandleId": h.next(), "Data": {
            "$type": "gameJournalPrimaryFolderEntry",
            "id": "onscreens",
            "journalEntryOverrideDataList": [],
            "entries": [node],
        }},
    ]

    return {
        "Header": header("jackielives_quests.journal"),
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "gameJournalResource",
                "cookingPlatform": "PLATFORM_None",
                "entry": {
                    "HandleId": root_h,
                    "Data": {
                        "$type": "gameJournalRootFolderEntry",
                        "descriptor": {
                            "DepotPath": {"$type": "ResourcePath", "$storage": "uint64",
                                          "$value": "0"},
                            "Flags": "Soft",
                        },
                        "entries": primaries,
                    },
                },
            },
            "EmbeddedFiles": [],
        },
    }


def build_questtext(strings):
    return {
        "Header": header("jackielives_questtext.json"),
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_None",
                "root": {"HandleId": "0", "Data": {
                    "$type": "localizationPersistenceOnScreenEntries",
                    "entries": [{
                        "$type": "localizationPersistenceOnScreenEntry",
                        "femaleVariant": text,
                        "maleVariant": text,
                        "primaryKey": fnv1a64(k),
                        "secondaryKey": k,
                    } for k, text in strings],
                }},
            },
            "EmbeddedFiles": [],
        },
    }


# ------------------------------------------------------------------------------- the Lua index

def lq(s):
    """A Lua string literal. Bodies contain real newlines; escape rather than long-bracket, so a
    stray `]]` in the prose can never terminate the literal early."""
    return '"%s"' % (str(s).replace("\\", "\\\\").replace('"', '\\"')
                     .replace("\n", "\\n").replace("\r", ""))


def lua_index(quests, shards):
    L = []
    A = L.append
    A("-- journalquest_index.lua — GENERATED by tools/gen_journal_quests.py. DO NOT EDIT BY HAND.")
    A("-- Edit mod/JackieLives/storyboard.lua or sidequests.lua and re-run the generator.")
    A("--")
    A("-- Every `path` here is a journal uniquePath accepted verbatim by")
    A("--   JournalManager:ChangeEntryState(path, className, state, notifyOption)")
    A("-- and by GetEntryByString(path, className). The archive built from the SAME run of the")
    A("-- generator contains exactly these nodes, which is the whole point of generating both")
    A("-- sides together: an objective cannot exist in Lua and be missing from the archive.")
    A("--")
    A("-- `text` / `title` / `body` are the ENGLISH originals. In game the words come from the")
    A("-- archive's localization, in the player's language; these copies exist so the mod can")
    A("-- still show the beat on the message band when the archive isn't installed.")
    A("")
    A("local Index = { quests = {}, questOrder = {}, shards = {}, shardOrder = {} }")
    A("")
    for q in quests:
        A("Index.questOrder[#Index.questOrder + 1] = %s" % lq(q["id"]))
        A("Index.quests[%s] = {" % lq(q["id"]))
        A("  id = %s, path = %s," % (lq(q["id"]), lq(q["path"])))
        A("  title = %s," % lq(q["title"]))
        A("  hasDescription = %s," % ("true" if q["desc"] else "false"))
        A("  phaseOrder = { %s }," % ", ".join(lq(p) for p in q["phases"]))
        A("  phases = {")
        for ph in q["phases"].values():
            A("    [%s] = {" % lq(ph["id"]))
            A("      id = %s, path = %s," % (lq(ph["id"]), lq(ph["path"])))
            A("      objectiveOrder = { %s },"
              % ", ".join(lq(o["id"]) for o in ph["objectives"]))
            A("      objectives = {")
            for o in ph["objectives"]:
                A("        [%s] = { id = %s, path = %s, beat = %s, text = %s },"
                  % (lq(o["id"]), lq(o["id"]), lq(o["path"]), lq(o["beat"]), lq(o["text"])))
            A("      },")
            A("    },")
        A("  },")
        A("}")
        A("")
    for s in shards:
        A("Index.shardOrder[#Index.shardOrder + 1] = %s" % lq(s["id"]))
        A("Index.shards[%s] = {" % lq(s["id"]))
        A("  id = %s, path = %s," % (lq(s["id"]), lq(s["path"])))
        A("  item = %s, action = %s," % (lq(s["item"]), lq(s["action"])))
        A("  title = %s," % lq(s["title"]))
        A("  author = %s," % lq(s["author"]))
        A("  body = %s," % lq(s["body"]))
        A("}")
        A("")
    A("return Index")
    A("")
    return "\n".join(L)


# ------------------------------------------------------------------------------- the TweakXL YAML

YAML_PREAMBLE = """\
# TweakXL — JackieLives readable shards.        GENERATED, DO NOT EDIT BY HAND.
# ---------------------------------------------------------------------------
# Regenerate with:  python3 tools/gen_journal_quests.py
# The words live in mod/JackieLives/storyboard.lua (the `shard = { ... }` block on a beat) and
# are baked into the archive's localization; nothing player-facing is in this file.
#
# DEPLOY: copy to  <game>\\r6\\tweaks\\JackieLives\\jl_shards.yaml
# It loads LOOSE — no archive, no WolvenKit, no rebuild. The archive is only needed for the
# READABLE TEXT; without it the item still exists and reads as an empty entry.
#
# HOW A SHARD ACTUALLY WORKS (all four points cost us a debugging session once):
#   1. `itemSecondaryAction` is the line the whole thing hangs off. It names an ItemAction record
#      whose `journalEntry` flat is the onscreen path. All 335 vanilla shards are built this way.
#   2. `objectActions` is a DIFFERENT property and is NOT the read action. Vanilla's is
#      [Drop, Disassemble]; overriding it costs the player Disassemble and buys nothing.
#   3. The title the player sees on the loot prompt and in the scanner is the JOURNAL ENTRY's
#      title, not `displayName`. `displayName` only names the inventory row.
#   4. `displayName` takes a BARE ArchiveXL key. A `LocKey#<name>` prefix on a non-numeric key
#      renders raw on screen — that bug shipped in the hand-written version of this file.
# Full reasoning: docs/research/journal_quests_and_shards_spec.md §5.4.
# ---------------------------------------------------------------------------
"""


def build_yaml(shards):
    out = [YAML_PREAMBLE]
    for s in shards:
        out.append("\n# --- %s — %s\n" % (s["id"], s["title"].replace("\n", " ")))
        out.append("%s:\n" % s["item"])
        out.append("  $type: gamedataItem_Record\n")
        out.append("  animFeatureName: ItemData\n")
        out.append("  itemType: ItemType.Gen_Readable\n")
        out.append("  itemSecondaryAction: %s\n" % s["action"])
        out.append("  canDrop: True\n")
        out.append("  dropObject: defaultItemDrop\n")
        out.append("  displayName: %s\n" % key("s", s["id"], "item"))
        if s["author"]:
            out.append("  localizedDescription: %s\n" % key("s", s["id"], "by"))
        out.append("  objectActions:\n")
        out.append("    - ItemAction.Drop\n")
        out.append("    - ItemAction.Disassemble\n")
        out.append("  tags:\n")
        for t in ("Readable", "Shard", "SkipActivityLog", "HideInBackpackUI", "HideAtVendor"):
            out.append("    - %s\n" % t)
        out.append("\n")
        out.append("%s:\n" % s["action"])
        out.append("  $type: gamedataItemAction_Record\n")
        out.append("  actionName: Read\n")
        out.append("  hackCategory: HackCategory.DeviceHack\n")
        out.append("  objectActionType: ObjectActionType.Item\n")
        out.append("  journalEntry: %s\n" % s["path"])
    return "".join(out)


# ------------------------------------------------------------------------------------- locales

def locale_strings(locale, canonical):
    """`canonical` is [(key, english)]. A non-English locale reads tools/journal_text/<locale>.txt:
    one RECORD per key, in the same order, separated by a line containing only `%%`. A blank
    record falls back to English, so a partly-translated file is always safe to ship."""
    if locale == "en-us":
        return list(canonical)
    path = os.path.join(TRANS_DIR, locale + ".txt")
    seed = SEED_TRANSLATIONS.get(locale, {})
    if not os.path.isfile(path):
        os.makedirs(TRANS_DIR, exist_ok=True)
        body = SEP.join(seed.get(k, en) for k, en in canonical)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("-- %s translations for tools/gen_journal_quests.py.\n"
                    "-- One record per key, in this exact order, separated by a line of `%%%%`.\n"
                    "-- A blank record falls back to English. Do not reorder or delete records:\n"
                    "-- they are matched by POSITION. Re-run the generator after editing.\n%s\n"
                    % (locale, SEP.lstrip("\n")))
            f.write(body + "\n")
        print("  bootstrapped translation template:", os.path.relpath(path, PROJ))
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    # drop the header block (everything before the first separator)
    parts = raw.split("\n%%\n")
    if parts and parts[0].lstrip().startswith("--"):
        parts = parts[1:]
    out = []
    for i, (k, en) in enumerate(canonical):
        t = parts[i].strip("\n") if i < len(parts) else ""
        out.append((k, t if t.strip() else en))
    return out


# Carried across from the retired mod/JackieLives_shards/localization/jl_shards.ja-jp.json so the
# one already-translated shard survives the move to generated files.
SEED_TRANSLATIONS = {
  "ja-jp": {
    "jl_j_s_jl_shard_badlands_note_title":
        "シャード — ジャッキー・ウェルズ",
    "jl_j_s_jl_shard_badlands_note_body":
        "これを読んでるってことは、V、ドクは約束を守って、あんたはここまで来たんだな。オレだ。生きてるぜ。\n\nヴィクがオレを繕って、サカがオレの名を石板に刻む前に、こっそり運び出してくれた。それからずっと身を潜めてる。\n\nママ・ウェルズは聞いてカンカンだった。またストリートで走り出したら殺されるだろうな——今度ばかりは、それが正しいのかもしれん。オレは傭兵稼業とはおさらばだ、V。本気でな。だが、あんたにオレを埋めたままにさせとくわけにはいかなかった。\n\nこれを読んだら、電話をくれ。 — ジャッキー",
    "jl_j_s_jl_shard_badlands_note_item":
        "シャード：ジャッキー・ウェルズ",
  },
}


# ---------------------------------------------------------------------------------- parity check

def journal_paths(journal):
    """Every addressable uniquePath in the emitted journal, as ChangeEntryState takes it: the
    chain of `id`s below the root folder, no leading slash. -> {path: $type}"""
    out = {}

    def walk(node, prefix):
        for e in (node.get("entries") or []):
            d = e["Data"]
            path = "%s/%s" % (prefix, d["id"]) if prefix else d["id"]
            out[path] = d["$type"]
            walk(d, path)

    walk(journal["Data"]["RootChunk"]["entry"]["Data"], "")
    return out


def check_parity(journal, quests, shards, strings):
    """Every path the Lua index will ask the game for must exist as a node in the archive we just
    wrote, with the right class. This is the failure the generate-both-sides-together design
    exists to prevent: an objective that is real in Lua and missing from the archive is a tracker
    line that silently never appears, and the only symptom is one line in jackie_debug.log."""
    have = journal_paths(journal)
    want = []
    for q in quests:
        want.append((q["path"], "gameJournalQuest"))
        for ph in q["phases"].values():
            want.append((ph["path"], "gameJournalQuestPhase"))
            for o in ph["objectives"]:
                want.append((o["path"], "gameJournalQuestObjective"))
    for s in shards:
        want.append((s["path"], "gameJournalOnscreen"))

    bad = ["%s (want %s, journal has %s)" % (p, c, have.get(p) or "nothing")
           for p, c in want if have.get(p) != c]
    if bad:
        raise SystemExit("index/archive mismatch:\n  " + "\n  ".join(bad))

    # A duplicated key would silently make two different texts share one string.
    seen = {}
    for k, text in strings:
        if k in seen and seen[k] != text:
            raise SystemExit("duplicate localization key with different text: %s" % k)
        seen[k] = text

    # FNV-1a64 is what the engine keys on; two of our own keys colliding would be invisible.
    hashes = {}
    for k, _ in strings:
        h = fnv1a64(k)
        if h in hashes and hashes[h] != k:
            raise SystemExit("FNV-1a64 collision between %s and %s" % (hashes[h], k))
        hashes[h] = k

    return len(have), len(want)


# ----------------------------------------------------------------------------------------- main

def write(path, text, check, changed):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = None
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            old = f.read()
    rel = os.path.relpath(path, PROJ)
    if old == text:
        print("  ok      %s" % rel)
        return
    changed.append(rel)
    if check:
        print("  STALE   %s" % rel)
        return
    # ⚠️ newline="\n" everywhere. Python's text mode turns "\n" into "\r\n" on Windows, so the
    # same content generated on the Mac and on the Windows box produced byte-different files —
    # which churns committed sources and breaks the archive's content stamp.
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("  wrote   %s" % rel)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="don't write; exit non-zero if any output is out of date")
    args = ap.parse_args()

    arc, items = read_storyboard()
    quests, shards, warnings = build_model(arc, items)
    strings = collect_strings(quests, shards)
    journal = build_journal(quests, shards)
    n_nodes, n_paths = check_parity(journal, quests, shards, strings)

    changed = []
    write(os.path.join(JDIR, "jackielives_quests.journal.json"),
          json.dumps(journal, indent=2, ensure_ascii=False) + "\n", args.check, changed)
    for locale in LOCALES:
        ls = locale_strings(locale, strings)
        write(os.path.join(TEXTDIR, locale, "jackielives_questtext.json.json"),
              json.dumps(build_questtext(ls), indent=2, ensure_ascii=False) + "\n",
              args.check, changed)
        n = sum(1 for i, (_, t) in enumerate(ls) if t != strings[i][1])
        if locale != "en-us":
            print("          [%s: %d/%d translated]" % (locale, n, len(strings)))
    write(LUA_INDEX, lua_index(quests, shards), args.check, changed)
    write(YAML_OUT, build_yaml(shards), args.check, changed)

    n_obj = sum(len(ph["objectives"]) for q in quests for ph in q["phases"].values())
    print("\n%d quest(s), %d phase(s), %d objective(s), %d shard(s), %d localized strings"
          % (len(quests), sum(len(q["phases"]) for q in quests), n_obj, len(shards), len(strings)))
    print("%d journal nodes, %d addressed by the Lua index — parity OK" % (n_nodes, n_paths))

    for w_ in warnings:
        print("\nWARNING: " + w_, file=sys.stderr)

    if args.check and changed:
        print("\n%d file(s) out of date. Run: python3 tools/gen_journal_quests.py"
              % len(changed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
