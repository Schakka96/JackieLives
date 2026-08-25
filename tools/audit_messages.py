#!/usr/bin/env python3
"""audit_messages.py — is the SMS content finished, and does it still match the storyboard?

    python3 tools/audit_messages.py            # the worklist + the storyboard diff
    python3 tools/audit_messages.py --ids      # just the beat ids needing work, one per line

TWO JOBS, and the second one is JackieLives-only.

1. THE WORKLIST (ported from NCLives). Which incoming beats have no reply options, and which have
   replies he never answers. Antonia's standing rule: every incoming beat gets authored replies and
   at least a short conversation after it, roughly 50:50 between longer exchanges and short factual
   ones.

2. THE STORYBOARD DIFF (new here). mod/JackieLives/storyboard.lua is the SINGLE SOURCE OF TRUTH for
   the questline, and its arc beats carry their text messages verbatim in `sms = { ... }` blocks.
   content/*_messages.json holds a COPY of those words, because only the JSON reaches the generator
   and the archive. Two copies of the same words is exactly the arrangement that drifts, so this
   tool diffs them and FAILS (exit 1) the moment they disagree.

   ⚠️ THE STORYBOARD WINS, ALWAYS. If this reports a mismatch, the fix is to copy the storyboard's
   wording INTO the JSON — never the other way round. The storyboard is where the writing happens.

WHY THIS EXISTS (2026-08-22). A player reported "it never gets me to be able to reply to anything.
I can only reply to the first message." Two engine bugs were behind most of that and are fixed — but
the rest is content: most incoming beats are one-liners with no `replies` block at all, so there is
genuinely nothing to tap. Antonia's call: *"all incoming messages should have authored replies and at
least short conversations following. Some can be longer, some just factual and short (50:50)."*

This is the worklist for that, and the check that it stays done.

⚠️ AUTHORING IS ONLY HALF. Reply options are journal entries: they must exist in the .archive before
the mod can activate them (see ../NCLives/docs/MESSAGES.md). After editing content/*_messages.json
you must run tools/gen_messages.py, and then rebuild the archive ON WINDOWS with
`python tools\\build_archive.py`. A reply added to the JSON alone will not appear in game.
"""
import argparse, glob, json, io, os, re, sys, collections

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load():
    for f in sorted(glob.glob(os.path.join(HERE, "content", "*_messages.json"))):
        with io.open(f, encoding="utf-8") as fh:
            yield os.path.basename(f), json.load(fh)

def followups_of(beat, reply):
    """What he says back to this reply.

    ⚠️ `followups` is a BEAT-level map keyed by reply id — NOT a field on the reply. Reading it off
    the reply returns nothing for every beat in the file, which reports a fully-authored opener as
    unanswered. (It did exactly that on the first run of this tool.)"""
    return (beat.get("followups") or {}).get(reply.get("id")) or []


# ===========================================================================================
# THE STORYBOARD DIFF
# ===========================================================================================
STORYBOARD = os.path.join(HERE, "mod", "JackieLives", "storyboard.lua")

# storyboard `sms.thread` -> the journal contact id that thread's words must live under.
#
# ⚠️ THIS IS A REAL CHECK, NOT BOOKKEEPING. It is not enough that a beat id exists SOMEWHERE in
# content/: the unknown number's two lines appearing under Jackie's contact would render as Jackie
# telling V he is Arasaka property, which is the opposite of the beat. So the differ verifies the
# thread landed on the right contact, and a thread with no mapping here is reported rather than
# quietly accepted — adding a voice to the story must be a deliberate act in three places (the
# storyboard, a content file, and this map), because a contact is a permanent journal path.
THREAD_CONTACT = {
    "jackie":  "jackie",                 # merged into his VANILLA contact
    "unknown": "jackielives_unknown",    # private, anonymous, no portrait
    "nix":     "jackielives_nix",        # private: his vanilla avatarID was never verified
}

# A deliberately SMALL, dumb reader. It does not evaluate Lua and it never will: storyboard.lua is
# prose-heavy, under active editing by other people, and the whole point of this check is to be a
# canary — a reader clever enough to be wrong quietly would be worse than none. It finds each
# `sms = { ... }` block by brace balance, then pulls out `id`, `thread`, and the ORDERED list of
# `text = "..."` values in `messages` / `replies` / `followups`.
#
# ⚠️ Only DOUBLE-quoted Lua strings are matched, because that is what the storyboard uses. If a beat
# ever switches to [[long brackets]] this reader will report it as missing rather than as matching —
# loud, and in the right direction.
_STR = r'"((?:[^"\\]|\\.)*)"'

def _unescape(v):
    return v.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")

def _blocks(src, key="sms"):
    """Every `<key> = { ... }` in `src`, as raw text, found by balancing braces."""
    for m in re.finditer(r"\b%s\s*=\s*\{" % key, src):
        i, depth, instr, esc = m.end() - 1, 0, False, False
        while i < len(src):
            ch = src[i]
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif instr:
                if ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    yield src[m.end() - 1: i + 1]
                    break
            i += 1

def _sub(block, key):
    """The `<key> = { ... }` nested inside `block`, or ''."""
    for b in _blocks(block, re.escape(key)):
        return b
    return ""

def _texts(block):
    """Every `text = "..."` in order."""
    return [_unescape(m.group(1)) for m in re.finditer(r"\btext\s*=\s*" + _STR, block)]

def storyboard_sms():
    """-> [{id, thread, messages, replies:{id:text}, followups:{replyId:[text]}}] in file order."""
    if not os.path.isfile(STORYBOARD):
        return None
    src = io.open(STORYBOARD, encoding="utf-8").read()
    out = []
    for blk in _blocks(src, "sms"):
        m = re.search(r"\bid\s*=\s*" + _STR, blk)
        if not m:
            continue
        thread = re.search(r"\bthread\s*=\s*" + _STR, blk)
        msgs = _sub(blk, "messages")
        reps = _sub(blk, "replies")
        fups = _sub(blk, "followups")
        replies = {}
        for rm in re.finditer(r"\{\s*id\s*=\s*" + _STR + r"\s*,\s*text\s*=\s*" + _STR, reps):
            replies[_unescape(rm.group(1))] = _unescape(rm.group(2))
        followups = {}
        # `followups` is a map keyed by reply id: `worried = { {..text="a"}, {..text="b"} }`
        for fm in re.finditer(r"(\w+)\s*=\s*\{", fups):
            inner = _sub(fups[fm.start():], fm.group(1))
            followups[fm.group(1)] = _texts(inner)
        out.append({
            "id": _unescape(m.group(1)),
            "thread": _unescape(thread.group(1)) if thread else "jackie",
            "messages": _texts(msgs),
            "replies": replies,
            "followups": followups,
        })
    return out

def check_storyboard(content):
    """Diff storyboard.lua's `sms` blocks against the authored JSON. Returns (fatal, pending, lines).

    `fatal` is a real disagreement: a beat missing from the JSON, one whose words no longer match, one
    filed under the wrong contact, or one whose `kind` is not "story" (which would let the scheduler
    draw a plot point at random). `pending` is a thread THREAD_CONTACT has no mapping for — a new
    voice somebody added to the storyboard that has not been given a contact yet.
    """
    blocks = storyboard_sms()
    lines = []
    if blocks is None:
        return [], [], ["storyboard.lua not found — skipping the storyboard diff"]
    if not blocks:
        return [], [], ["storyboard.lua has no `sms` blocks yet — nothing to diff"]

    # beat id -> (contact id, beat). Ids must be unique across the WHOLE content folder, because
    # Msg.sendStory() searches every contact and takes the first match.
    authored, dupes = {}, []
    for _name, doc in content:
        cid = (doc.get("contact") or {}).get("id")
        for b in doc.get("beats", []):
            if b.get("id") in authored:
                dupes.append(b.get("id"))
            authored[b.get("id")] = (cid, b)

    fatal, pending = [], []
    for d in sorted(set(dupes)):
        fatal.append("beat id %r is declared in more than one content file — ids must be unique "
                     "across the folder, because Msg.sendStory takes the first match" % d)
    matched = 0
    for sb in blocks:
        want_contact = THREAD_CONTACT.get(sb["thread"])
        if want_contact is None:
            pending.append("%s (thread %r has no contact in THREAD_CONTACT — add one there and a "
                           "content/<name>_messages.json to match)" % (sb["id"], sb["thread"]))
            continue
        found = authored.get(sb["id"])
        if not found:
            fatal.append("%s is in storyboard.lua and NOT in content/*_messages.json "
                         "(expected under contact %r)" % (sb["id"], want_contact))
            continue
        got_contact, beat = found
        if got_contact != want_contact:
            fatal.append("%s is filed under contact %r but its storyboard thread %r maps to %r"
                         % (sb["id"], got_contact, sb["thread"], want_contact))
        if beat.get("kind") != "story":
            fatal.append("%s is a storyboard beat but its JSON kind is %r, not \"story\" — the "
                         "scheduler would draw a plot point at random" % (sb["id"], beat.get("kind")))
        want, got = sb["messages"], (beat.get("bubbles") or [])
        if want != got:
            fatal.append("%s: bubbles differ from the storyboard\n"
                         "      storyboard: %s\n"
                         "      json      : %s" % (sb["id"], want, got))
        jr = {r.get("id"): r.get("text") for r in (beat.get("replies") or [])}
        if sb["replies"] != jr:
            fatal.append("%s: reply options differ from the storyboard\n"
                         "      storyboard: %s\n"
                         "      json      : %s" % (sb["id"], sb["replies"], jr))
        jf = {k: list(v) for k, v in (beat.get("followups") or {}).items() if v}
        sf = {k: v for k, v in sb["followups"].items() if v}
        if sf != jf:
            fatal.append("%s: followups differ from the storyboard\n"
                         "      storyboard: %s\n"
                         "      json      : %s" % (sb["id"], sf, jf))
        matched += 1

    lines.append("storyboard: %d sms block(s) across %d thread(s); %d fully matched in content/"
                 % (len(blocks), len(set(b["thread"] for b in blocks)), matched))
    return fatal, pending, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", action="store_true", help="print only the beat ids needing work")
    args = ap.parse_args()

    content = list(load())

    need_replies, need_followup, ok_short, ok_long = [], [], [], []
    for name, doc in content:
        for b in doc.get("beats", []):
            if b.get("kind") == "outgoing":
                continue                      # V speaks first; replies ARE the beat
            if b.get("kind") == "story":
                continue                      # the storyboard decides what an arc beat says, and
                                              # some arc beats are deliberately unanswerable

            where = "%s:%s" % (name, b.get("id"))
            replies = b.get("replies") or []
            if not replies:
                need_replies.append((where, b.get("kind")))
            elif not any(followups_of(b, r) for r in replies):
                need_followup.append((where, b.get("kind")))
            elif max(len(followups_of(b, r)) for r in replies) >= 2:
                ok_long.append(where)
            else:
                ok_short.append(where)

    if args.ids:
        for w, _ in need_replies + need_followup:
            print(w)
        return 0

    total = len(need_replies) + len(need_followup) + len(ok_short) + len(ok_long)
    print("incoming beats: %d" % total)
    print("  %3d have replies AND a conversation after them" % (len(ok_short) + len(ok_long)))
    print("       of those: %d short (one line back), %d longer (two or more)" % (len(ok_short), len(ok_long)))
    if ok_short or ok_long:
        done = len(ok_short) + len(ok_long)
        print("       split: %.0f%% short / %.0f%% longer   (target 50/50)"
              % (100.0 * len(ok_short) / done, 100.0 * len(ok_long) / done))
    print("  %3d have NO replies at all — nothing to tap" % len(need_replies))
    print("  %3d have replies but he never answers back" % len(need_followup))

    for title, rows in (("NO REPLIES", need_replies), ("NO ANSWER BACK", need_followup)):
        if not rows:
            continue
        print("\n%s (%d):" % (title, len(rows)))
        by_kind = collections.defaultdict(list)
        for w, k in rows:
            by_kind[k].append(w)
        for k in sorted(by_kind):
            print("  %-10s %s" % (k, ", ".join(sorted(x.split(":")[1] for x in by_kind[k]))))

    if need_replies or need_followup:
        print("\n⚠️ After authoring: tools/gen_messages.py, then rebuild the archive ON WINDOWS")
        print("   (python tools\\build_archive.py). JSON alone never reaches the game.")

    # --- job 2: does the content still say what the storyboard says? ---------------------
    fatal, pending, lines = check_storyboard(content)
    print("\n---- storyboard diff ----")
    for l in lines:
        print(l)
    if pending:
        print("\nNO CONTACT YET (%d) — a storyboard thread nothing can deliver:" % len(pending))
        for p in pending:
            print("  %s" % p)
    if fatal:
        print("\n❌ CONTENT AND STORYBOARD DISAGREE (%d):" % len(fatal))
        for f in fatal:
            print("  %s" % f)
        print("\n   THE STORYBOARD WINS. Copy its wording into content/*_messages.json (never the")
        print("   other way round), then re-run tools/gen_messages.py.")
        return 1
    print("content and storyboard agree.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
