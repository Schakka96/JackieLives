#!/usr/bin/env python3
"""Keyword-bucket Jackie's voiced lines into call-relevant bins.

Reads the Audioware index (id -> {event, text}) so every suggestion is a line that
actually has playable audio (event name jl_<id>). Writes classify_out.json with the
best candidates per bin, for use as random pools in the call flow (and to seed the
tagger bins). Heuristic only — curate the output; a line can land in several bins.
"""
import json, re, os

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "..", "..", "audioware", "JackieLives", "index.json")

# (bin, [regexes]). Lowercased transcript is matched. Order = priority for ranking.
BINS = {
    "greeting": [
        r"\bhey,? hey\b", r"^hey\b", r"\bwhat'?s up\b", r"\bwhat'?s good\b",
        r"\bgood to (see|hear)\b", r"\blook who\b", r"\blong time\b",
        r"\bwhat'?s the word\b", r"\btalk to me\b", r"\bqué pasa\b", r"\bmi vida\b",
        r"\bchica\b.*\?", r"\bhola\b", r"\bhow you been\b", r"\bthere (she|he) is\b",
    ],
    "farewell": [
        r"\blater\b", r"\bsee (you|ya)\b", r"\bcatch you\b", r"\badios\b", r"\bhasta\b",
        r"\btake care\b", r"\bbe safe\b", r"\bgotta (go|run|bounce)\b", r"\btalk to you\b",
        r"\buntil\b", r"\bbye\b", r"\bciao\b", r"\bpeace\b", r"\bstay (frosty|safe|cool)\b",
        r"\bwe('| a)?re on our way\b", r"\bon our way\b",
    ],
    "agreement": [
        r"\blet'?s do\b", r"\bi'?m in\b", r"\bcount me in\b", r"\blet'?s go\b",
        r"\bon my way\b", r"\blet'?s roll\b", r"\blet'?s mosey\b", r"\bsay no more\b",
        r"\bdo our thing\b", r"\bi'?m ready\b", r"\blet'?s ride\b", r"\blet'?s get\b",
        r"\bi'?m comin'?\b", r"\bbe right there\b", r"\byou got it\b", r"\bhell yeah\b",
        r"\bfor you,? anything\b", r"\bwhatever you need\b",
    ],
    "howdoing": [
        r"\bi'?m good\b", r"\bdoin'? (good|fine|great)\b", r"\bcan'?t complain\b",
        r"\bdoes not get any higher\b", r"\bnever better\b", r"\ball good\b",
        r"\blivin'?\b", r"\byou know me\b", r"\bsame old\b", r"\bhangin'?\b",
        r"\bholdin'? up\b", r"\bi'?m fine\b", r"\bgreat,? choom\b", r"\bup top\b",
    ],
}

def main():
    with open(INDEX, encoding="utf-8") as f:
        idx = json.load(f)
    rows = [(sid, d.get("text", "")) for sid, d in idx.items()]
    out = {}
    for binname, pats in BINS.items():
        regs = [re.compile(p, re.I) for p in pats]
        hits = []
        for sid, text in rows:
            t = text.lower()
            score = sum(1 for r in regs if r.search(t))
            # prefer short, punchy, question-free greetings etc.
            if score:
                hits.append({"id": sid, "event": "jl_" + sid, "text": text,
                             "score": score, "len": len(text)})
        # rank: more keyword hits first, then shorter lines
        hits.sort(key=lambda h: (-h["score"], h["len"]))
        out[binname] = hits
        print(f"\n=== {binname}: {len(hits)} candidates (top 15) ===")
        for h in hits[:15]:
            print(f'  jl_{h["id"]}  | {h["text"]}')

    outpath = os.path.join(HERE, "classify_out.json")
    with open(outpath, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"\nwrote {outpath}")

if __name__ == "__main__":
    main()
