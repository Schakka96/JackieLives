# Jackie Voice-line Tagger

A phone-friendly web app to audition Jackie's voice lines and tag each one with category, mood, triggers,
play-chance, locations, and notes. Output feeds the mod's contextual voice system later.

## Run it on your laptop
Double-click `index.html`. Import/export and tagging all work; audio plays if a line has a reachable
`file`.

## Run it on your phone
You don't need Python. Easiest options, simplest first:
1. **Just open the file (transcript-only, zero setup):** put `index.html` in OneDrive (or email it to
   yourself), open it in your phone's browser. Tagging works offline; audio won't play (no files), which
   is fine for tagging by transcript on the bus. Export sends a JSON to your phone's downloads — mail it
   back to yourself to merge with the laptop copy.
2. **Netlify Drop (best — public URL, audio works, no install):** go to https://app.netlify.com/drop and
   drag the whole `voice-tagger` folder onto the page. You get an `https://…netlify.app` link you can
   open on your phone anywhere (mobile data included). Re-drag to update.
3. **Local server (needed for audio + auto-loading lines.json):** opening via `file://` can't `fetch`
   `lines.json` or play the audio. Serve the folder instead — simplest first:
   - `python -m http.server 8123` then open `http://localhost:8123` (Python is installed).
   - or `npx http-server` (Node is installed). For your phone, open `http://<laptop-ip>:8123` on the
     same Wi-Fi. VS Code's "Live Server" extension does the same with a click.

⚠️ Tags save **per device/browser** (localStorage). If you tag on your phone, **Export** and send the
file to your laptop to merge — clearing site data wipes untagged-only-on-phone work.

## Data format (`lines.json`)
Click **Import lines.json** and pick a file shaped like this:
```json
[
  { "id": "jackie_0001", "file": "audio/jackie_0001.wav", "transcript": "¡Preem!", "category": "greetings" },
  { "id": "jackie_0002", "file": null,                      "transcript": "Stay frosty.", "category": "" }
]
```
- `id` — unique; the tagger keys your tags to it.
- `file` — relative path or URL to the audio, or `null` to tag by transcript only.
- `transcript` — the line text.
- `category` — optional starting guess; you can change it in the app.

`lines.sample.json` is a tiny example.

## Getting the real voice files — one command (`scrape_jackie.py`)
`scrape_jackie.py` pulls **all of Jackie's lines** (transcript + String ID + real `.ogg` audio) straight
from the public SoundDB API, so you can listen while you tag. No WolvenKit, no manual extraction.

From this folder, in PowerShell:
```powershell
python scrape_jackie.py            # ~777 lines + audio into audio/  (a few minutes, ~3.5 MB)
python scrape_jackie.py --no-audio # transcripts only, fast
python scrape_jackie.py --limit 20 # quick test (first 20)
```
It writes `lines.json` here and the audio to `audio/<id>.ogg`. Re-running **resumes** (skips files you
already have). `lines.json` also carries extra fields the mod uses later — `string_id`, `vo_wem`,
`context`, `expression`, `quests` — which the tagger shows as hints and preserves on export.

> The `.ogg` previews come from SoundDB's static host. They're game audio — fine for our personal,
> non-commercial mod (you own the game); the scraper throttles itself to be polite.

`lines.sample.json` is a tiny example of the format if you'd rather hand-make one.

## Output (`Export tags`)
Downloads `jackie_voice_tags.json`: each line merged with its tags
(`category, mood[], triggers[], probability, locations[], notes, done`). That's what the mod will read.

## Notes
- Tags auto-save to the browser/device (localStorage). **Export regularly** to back up — clearing site
  data wipes localStorage.
- Categories, moods and locations are defined at the top of `index.html` (easy to edit).
