#!/usr/bin/env python3
r"""Generate JackieLives' SMS archive sources + the Lua index from content/<persona>_messages.json.

    python3 tools/gen_messages.py

Writes three kinds of output, all from the SAME content file, which is what stops the archive and the
Lua runtime from drifting apart:

  archive/source/mod/jackielives/journal/jackielives_messages.journal.json     the .journal (CR2W-JSON)
  archive/source/mod/jackielives/onscreens/<locale>/jackielives_msgs.json.json        the text, per locale
  mod/JackieLives/messages_index.lua                                        ids/tiers/kinds for messages.lua

Then run tools/build_archive.py ON WINDOWS to turn those into JackieLives.archive via WolvenKit CLI.

Read ../NCLives/docs/MESSAGES.md for the schema and the two traps (LocKey hashing, key collisions),
and docs/research/messages_port_spec.md for what is different here. There is deliberately no second
copy of the schema doc in this repo — one copy, or the two drift.
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, ".."))
CONTENT_DIR = os.path.join(PROJ, "content")
ARCH_SRC = os.path.join(PROJ, "archive", "source", "mod", "jackielives")
JDIR = os.path.join(ARCH_SRC, "journal")
OSDIR = os.path.join(ARCH_SRC, "onscreens")
LUA_INDEX = os.path.join(PROJ, "mod", "JackieLives", "messages_index.lua")
TRANS_DIR = os.path.join(HERE, "messages")   # per-locale translations, one line per key

# ⚠️ Every write below pins newline="\n". Python's text mode translates "\n" to "\r\n" on Windows, so
# the SAME content generated on the Mac and on the Windows box produced byte-different files — which
# made the archive's content stamp mismatch even when the archive was perfectly current, and would
# also have churned these committed sources on every cross-platform regenerate.

# en-us is canonical (the JSON content itself). Others read tools/messages/<locale>.txt, one line per
# key in the SAME order the keys are emitted; a blank/missing line falls back to English.
#
# ⚠️ These are the GAME's locale codes, from mod/JackieLives/lang.lua's `game` column — NOT our own
# two-letter codes, and NOT a copy of NCLives' list. NCLives writes "jp-jp"; the game's Japanese
# locale is "ja-jp" (lang.lua:45), so copying that list blindly would have shipped a folder the
# engine never reads.
#
# Only the locales we ACTUALLY translate belong here. translations.lua ships exactly one, Japanese.
# An untranslated locale is not free — it bakes a byte-identical English copy of all ~140 strings
# into the archive — so add a code the day its tools/messages/<locale>.txt gets real text, not
# before. (A missing line in that file falls back to English per-string, so a half-done translation
# is always safe.) The other nine codes the mod supports are in lang.lua when you need them.
LOCALES = ["en-us", "ja-jp"]

# Every localization key we emit is prefixed with this.
# ⚠️ NEVER key onscreens by bare display text: FNV-1a hashes of short English phrases collide with
# base-game localization entries, which crashes the game (BowieKnife99 shipped that bug once).
KEY_PREFIX = "jackielives_msg_"

# Bubble ids are "<beat>_b<N>"; a beat's Nth bubble is therefore addressable on its own, which is what
# lets the runtime stagger them into the thread instead of dumping the whole text at once.
BLANK_KEY = KEY_PREFIX + "blank"

# Every kind the runtime knows. The first seven are the SCHEDULER's (messages.lua `eligible`/`pick`);
# "story" is JackieLives-only and is deliberately NOT in any of those lists — an arc beat is fired by
# name from arc.lua via Msg.sendStory(), never drawn at random, because its words are a plot point.
# Validated here so a typo'd kind is a loud build error instead of a beat that silently never fires.
KINDS = ("opener", "checkin", "question", "invite", "standup", "afterdate", "outgoing", "story")


def fnv1a64(s):
    """CP2077 LocKey id = FNV-1a 64-bit of the key string.

    The phone resolves text through this NUMERIC id (localizationString.unk1), so unk1 and the
    onscreens primaryKey must both be this hash or the thread renders a raw `LocKey#<id>`.
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


def tdbid_str(v):
    return {"$type": "TweakDBID", "$storage": "string", "$value": v}


def tdbid(v):
    """A TweakDBID that may be given EITHER as a symbolic name or as the raw 64-bit number.

    Jackie is already a vanilla contact, and his portrait is stored as a bare uint64 (121253599929).
    Its symbolic name could not be recovered — the id encodes len=28 | fnv1a32=0x3b471ab9 and no
    obvious `PhoneAvatars.*` string of length 28 hashes to it — so we pass the number, which is
    exactly what the engine itself stores. NCLives only ever needed the string form
    ("PhoneAvatars.Avatar_Unknown"), which stays the fallback if this ever misbehaves.
    """
    if isinstance(v, bool):
        raise SystemExit("avatar must be a TweakDBID name or number, not a bool")
    if isinstance(v, int):
        return {"$type": "TweakDBID", "$storage": "uint64", "$value": str(v)}
    sv = str(v)
    if sv.isdigit():
        return {"$type": "TweakDBID", "$storage": "uint64", "$value": sv}
    return tdbid_str(sv)


def tdbid_zero():
    return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}


class Handles:
    """CR2W HandleIds must be unique and dense across the whole resource."""

    def __init__(self):
        self.n = 0

    def next(self):
        h = str(self.n)
        self.n += 1
        return h


def load_content():
    """Every content/<persona>_messages.json, sorted so output is deterministic."""
    out = []
    for name in sorted(os.listdir(CONTENT_DIR)):
        if name.endswith("_messages.json"):
            with open(os.path.join(CONTENT_DIR, name), encoding="utf-8") as f:
                out.append((name, json.load(f)))
    if not out:
        raise SystemExit("no content/*_messages.json found")
    return out


def build(personas):
    """-> (journal dict, [(key, english text)], lua index rows). One contact per persona."""
    h = Handles()
    strings = [(BLANK_KEY, "")]
    contacts = []
    index = []

    root_h = h.next()
    prim_h = h.next()

    for fname, data in personas:
        c = data["contact"]
        cid, convo_id = c["id"], c["conversation"]
        name_key = KEY_PREFIX + cid + "_name"
        strings.append((name_key, c["name"]))

        contact_h = h.next()
        convo_h = h.next()
        entries = []          # children of the conversation, in authored order
        beats_index = []

        for beat in data["beats"]:
            bid = beat["id"]
            if beat.get("kind") not in KINDS:
                raise SystemExit("beat %r has unknown kind %r (expected one of %s)"
                                 % (bid, beat.get("kind"), ", ".join(KINDS)))
            base = "contacts/%s/%s" % (cid, convo_id)

            # --- her bubbles ---------------------------------------------------------------
            bubble_paths = []
            for i, text in enumerate(beat.get("bubbles") or [], 1):
                mid = "%s_b%d" % (bid, i)
                key = "%s%s_%s" % (KEY_PREFIX, cid, mid)
                strings.append((key, text))
                entries.append({
                    "HandleId": h.next(),
                    "Data": {
                        "$type": "gameJournalPhoneMessage",
                        "attachment": None,
                        # delay is the GAME's inter-message pause, used when a quest delivers a whole
                        # batch. We activate bubbles one at a time from Lua, so it stays 0 — otherwise
                        # the two pacings fight each other.
                        "delay": 0,
                        "id": mid,
                        "imageId": tdbid_zero(),
                        "isQuestImportant": 0,
                        "journalEntryOverrideDataList": [],
                        "sender": "NPC",
                        "text": loc(key),
                    },
                })
                bubble_paths.append("%s/%s" % (base, mid))

            # --- V's replies, and what she says back --------------------------------------
            replies_index = []
            if beat.get("replies"):
                gid = bid + "_g"
                choice_entries = []
                for r in beat["replies"]:
                    key = "%s%s_%s_%s" % (KEY_PREFIX, cid, gid, r["id"])
                    strings.append((key, r["text"]))
                    choice_entries.append({
                        "HandleId": h.next(),
                        "Data": {
                            "$type": "gameJournalPhoneChoiceEntry",
                            "id": r["id"],
                            "isQuestImportant": 0,
                            "journalEntryOverrideDataList": [],
                            # Gating happens in Lua (familiarity, pending rendezvous), never here —
                            # a questCondition would need a quest phase graph we deliberately don't ship.
                            "questCondition": None,
                            "text": loc(key),
                        },
                    })
                    replies_index.append({
                        "id": r["id"],
                        "path": "%s/%s/%s" % (base, gid, r["id"]),
                        "fam": r.get("fam", 0),
                        "accept": bool(r.get("accept")),
                        # Carried through for the questline only: a story reply may cost eddies
                        # (Nix's jammer). messages.lua never spends anything itself — it reports
                        # which reply was tapped and arc.lua does the charging, because only arc.lua
                        # knows whether the player can afford it and what to do if they cannot.
                        "cost": r.get("cost"),
                    })
                entries.append({
                    "HandleId": h.next(),
                    "Data": {
                        "$type": "gameJournalPhoneChoiceGroup",
                        "entries": choice_entries,
                        "id": gid,
                        "journalEntryOverrideDataList": [],
                    },
                })

                # her answer to each reply, as its own set of bubbles
                for r in beat["replies"]:
                    follow = (beat.get("followups") or {}).get(r["id"]) or []
                    paths = []
                    for i, text in enumerate(follow, 1):
                        mid = "%s_%s_f%d" % (bid, r["id"], i)
                        key = "%s%s_%s" % (KEY_PREFIX, cid, mid)
                        strings.append((key, text))
                        entries.append({
                            "HandleId": h.next(),
                            "Data": {
                                "$type": "gameJournalPhoneMessage",
                                "attachment": None,
                                "delay": 0,
                                "id": mid,
                                "imageId": tdbid_zero(),
                                "isQuestImportant": 0,
                                "journalEntryOverrideDataList": [],
                                "sender": "NPC",
                                "text": loc(key),
                            },
                        })
                        paths.append("%s/%s" % (base, mid))
                    for ri in replies_index:
                        if ri["id"] == r["id"]:
                            ri["followup"] = paths

            # An OUTGOING beat has no bubbles: V starts it, so there is nothing of hers to deliver
            # first — only the reply group, which the runtime leaves armed on the thread.
            if not bubble_paths and not beat.get("replies"):
                raise SystemExit("beat %r has neither bubbles nor replies — it can never appear" % bid)

            beats_index.append({
                "id": bid,
                "kind": beat["kind"],
                "tier": beat.get("tier", 0),
                "once": bool(beat.get("once")),
                "afterHours": beat.get("afterHours"),
                "venue": beat.get("venue"),
                "bubbles": bubble_paths,
                "group": ("%s/%s_g" % (base, bid)) if beat.get("replies") else None,
                "replies": replies_index,
            })

        contacts.append({
            "HandleId": contact_h,
            "Data": {
                "$type": "gameJournalContact",
                "id": cid,
                "journalEntryOverrideDataList": [],
                "avatarID": tdbid(c["avatar"]),
                "isCallableDefault": 0,
                "name": loc(name_key),
                "type": c.get("type", "Texter"),
                "useFlatMessageLayout": 1 if c.get("flatLayout", True) else 0,
                "entries": [{
                    "HandleId": convo_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "id": convo_id,
                        "journalEntryOverrideDataList": [],
                        # Resolves to "" so IsStringValid(GetTitle()) is false and the contact row
                        # previews the LAST MESSAGE, like a real thread. `unk1: "0"` does NOT do this —
                        # it hashes "" to a valid LocKey and shows that as the title.
                        "title": loc(BLANK_KEY),
                        "entries": entries,
                    },
                }],
            },
        })

        index.append({
            "source": fname,
            "contact": cid,
            "contactPath": "contacts/" + cid,
            "convoPath": "contacts/%s/%s" % (cid, convo_id),
            "beats": beats_index,
        })

    journal = {
        "Header": header("jackielives_messages.journal"),
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
                            "DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"},
                            "Flags": "Soft",
                        },
                        "entries": [{
                            "HandleId": prim_h,
                            "Data": {
                                "$type": "gameJournalPrimaryFolderEntry",
                                "id": "contacts",
                                "journalEntryOverrideDataList": [],
                                "entries": contacts,
                            },
                        }],
                    },
                },
            },
        },
    }
    return journal, strings, index


def build_onscreens(strings):
    return {
        "Header": header("jackielives_msgs.json"),
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_None",
                "root": {
                    "HandleId": "0",
                    "Data": {
                        "$type": "localizationPersistenceOnScreenEntries",
                        "entries": [{
                            "$type": "localizationPersistenceOnScreenEntry",
                            "femaleVariant": text,
                            "maleVariant": text,
                            "primaryKey": fnv1a64(key),
                            "secondaryKey": key,
                        } for key, text in strings],
                    },
                },
            },
        },
    }


def locale_strings(locale, canonical):
    """`canonical` is [(key, english)]. Non-English locales read tools/messages/<locale>.txt, one line
    per entry in the same order; a blank or missing line falls back to English. Bootstraps an
    English-filled template the first time so it can be translated in place."""
    if locale == "en-us":
        return list(canonical)
    path = os.path.join(TRANS_DIR, locale + ".txt")
    if not os.path.isfile(path):
        os.makedirs(TRANS_DIR, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            # newlines would break the one-line-per-key alignment; content has none, but be safe
            f.write("\n".join(t.replace("\n", " ") for _, t in canonical) + "\n")
        print("  bootstrapped translation template (English-filled):", path)
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    out = []
    for i, (key, en) in enumerate(canonical):
        t = lines[i].strip() if i < len(lines) and lines[i].strip() else en
        out.append((key, t))
    return out


def lua_index(index):
    """Emit messages_index.lua. GENERATED — messages.lua reads it and never guesses a path."""
    def q(s):
        return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')

    L = []
    L.append("-- messages_index.lua — GENERATED by tools/gen_messages.py. DO NOT EDIT BY HAND.")
    L.append("-- Edit content/*_messages.json and re-run the generator; see docs/MESSAGES.md.")
    L.append("--")
    L.append("-- Every string here is a journal `uniquePath` accepted by")
    L.append("--   JournalManager:ChangeEntryState(path, className, state, notifyOption)")
    L.append("-- The archive must contain the matching entries, which is exactly why both sides are")
    L.append("-- generated from one file: a beat cannot exist in Lua and be missing from the archive.")
    L.append("")
    L.append("local Index = { personas = {} }")
    L.append("")
    for p in index:
        L.append("-- from content/%s" % p["source"])
        L.append("Index.personas[%s] = {" % q(p["contact"]))
        L.append("  contactPath = %s," % q(p["contactPath"]))
        L.append("  convoPath   = %s," % q(p["convoPath"]))
        L.append("  beats = {")
        for b in p["beats"]:
            parts = [
                "id = %s" % q(b["id"]),
                "kind = %s" % q(b["kind"]),
                "tier = %d" % b["tier"],
            ]
            if b["once"]:
                parts.append("once = true")
            if b["afterHours"]:
                parts.append("afterHours = %s" % b["afterHours"])
            if b["venue"]:
                parts.append("venue = %s" % q(b["venue"]))
            L.append("    { %s," % ", ".join(parts))
            L.append("      bubbles = { %s }," % ", ".join(q(x) for x in b["bubbles"]))
            if b["group"]:
                L.append("      group = %s," % q(b["group"]))
                L.append("      replies = {")
                for r in b["replies"]:
                    fu = ", ".join(q(x) for x in (r.get("followup") or []))
                    cost = (", cost = %d" % r["cost"]) if r.get("cost") else ""
                    L.append("        { id = %s, path = %s, fam = %d, accept = %s%s, followup = { %s } },"
                             % (q(r["id"]), q(r["path"]), r["fam"],
                                "true" if r["accept"] else "false", cost, fu))
                L.append("      },")
            L.append("    },")
        L.append("  },")
        L.append("}")
        L.append("")
    L.append("return Index")
    L.append("")
    return "\n".join(L)


def journal_paths(journal):
    """Every addressable uniquePath in the emitted journal, as ChangeEntryState would take it:
    the chain of `id`s below the "contacts" primary folder, no leading slash."""
    out = {}

    def walk(node, prefix):
        for e in (node.get("entries") or []):
            d = e["Data"]
            path = "%s/%s" % (prefix, d["id"]) if prefix else d["id"]
            out[path] = d["$type"]
            walk(d, path)

    root = journal["Data"]["RootChunk"]["entry"]["Data"]
    walk(root, "")
    return out


def check_parity(journal, index):
    """Every path messages.lua will ask for must exist as a node in the archive we just wrote.

    This is the failure this whole generated-from-one-file design exists to prevent: a beat that is
    real in Lua and missing from the archive is a message that silently never arrives, and the only
    symptom is a line in the log. Cheap to assert here, miserable to debug in game.
    """
    have = journal_paths(journal)
    missing = []
    for p in index:
        want = [(b, "gameJournalPhoneMessage") for beat in p["beats"] for b in beat["bubbles"]]  # empty for outgoing
        want.append((p["contactPath"], "gameJournalContact"))
        want.append((p["convoPath"], "gameJournalPhoneConversation"))
        for beat in p["beats"]:
            if beat["group"]:
                want.append((beat["group"], "gameJournalPhoneChoiceGroup"))
            for r in beat["replies"]:
                want.append((r["path"], "gameJournalPhoneChoiceEntry"))
                want += [(f, "gameJournalPhoneMessage") for f in (r.get("followup") or [])]
        for path, cls in want:
            if have.get(path) != cls:
                missing.append("%s (want %s, journal has %s)" % (path, cls, have.get(path) or "nothing"))
    if missing:
        raise SystemExit("index/archive mismatch:\n  " + "\n  ".join(missing))
    return len(have)


def main():
    personas = load_content()
    journal, strings, index = build(personas)
    n_paths = check_parity(journal, index)

    # a duplicated key would silently make two different texts share one string
    seen = {}
    for key, text in strings:
        if key in seen and seen[key] != text:
            raise SystemExit("duplicate localization key with different text: %s" % key)
        seen[key] = text

    os.makedirs(JDIR, exist_ok=True)
    jpath = os.path.join(JDIR, "jackielives_messages.journal.json")
    with open(jpath, "w", encoding="utf-8", newline="\n") as f:
        json.dump(journal, f, indent=2, ensure_ascii=False)
    print("wrote", os.path.relpath(jpath, PROJ))

    for locale in LOCALES:
        loc_strings = locale_strings(locale, strings)
        odir = os.path.join(OSDIR, locale)
        os.makedirs(odir, exist_ok=True)
        opath = os.path.join(odir, "jackielives_msgs.json.json")
        with open(opath, "w", encoding="utf-8", newline="\n") as f:
            json.dump(build_onscreens(loc_strings), f, indent=2, ensure_ascii=False)
        n = sum(1 for i, (_, t) in enumerate(loc_strings) if t != strings[i][1])
        note = "canonical" if locale == "en-us" else "%d/%d translated" % (n, len(strings))
        print("wrote %s  [%s: %s]" % (os.path.relpath(opath, PROJ), locale, note))

    with open(LUA_INDEX, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua_index(index))
    print("wrote", os.path.relpath(LUA_INDEX, PROJ))

    beats = sum(len(p["beats"]) for p in index)
    print("\n%d contact(s), %d beats, %d localized strings, %d journal entries"
          % (len(index), beats, len(strings), n_paths))
    print("index/archive parity: OK")


if __name__ == "__main__":
    main()
