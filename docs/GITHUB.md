# GitHub workflow

This repo lives **only** in `Cyberpunk_modding/` (its own git repo — the parent
`Projects/` folder is NOT tracked). Identity is set repo-local
(`Antonia <schakka83@gmail.com>`) because the global git config is unavailable.

## One-time: connect to GitHub

1. On https://github.com → **New repository**.
   - Name: `jackie-lives` (or your choice)
   - Visibility: **Public**
   - **Do NOT** add a README, .gitignore, or license (we already have them).
   - Click **Create repository**.
2. Copy the repo URL (HTTPS), e.g. `https://github.com/<you>/jackie-lives.git`.
3. Wire it up and push (run in `Cyberpunk_modding/`):
   ```powershell
   git remote add origin https://github.com/<you>/jackie-lives.git
   git push -u origin main
   ```
   First push opens a browser (Git Credential Manager) to log into GitHub — approve it.

## Regular pushes (after the one-time setup)

```powershell
git add -A
git commit -m "Describe what changed"
git push
```

## What is and isn't published

- ✅ Published: mod code (`mod/`), Audioware manifest (`.yml`), tools/scripts, docs.
- 🚫 Never published (gitignored, regenerated locally): game audio (`*.ogg/.wav/.wem`),
  the full dialogue transcript dumps (`lines.json`, `index.json`), the ffmpeg binary,
  chat history, and `.claude/settings.local.json`.

Before any push, sanity-check nothing copyrighted slipped in:
```powershell
git status            # review staged files
git ls-files | Select-String -Pattern '\.(ogg|wav|wem)$'   # should print nothing
```

See `ASSETS_NOTICE.md` for the copyright rationale.
