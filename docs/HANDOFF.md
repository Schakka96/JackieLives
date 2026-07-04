# HANDOFF — Jackie Lives (machine transfer + next-session brief)

_Written 2026-06-23. Snapshot for moving the project to a new machine and onboarding the next
user/Claude session. For full history see `docs/logbook.txt`; for live tasks see `TODO.md`._

## 1. Repo state at transfer
- **GitHub:** https://github.com/Schakka96/JackieLives.git (`origin/main`).
- **Local `main` == `origin/main` (in sync, 0/0).** Everything is committed AND pushed — a fresh clone
  on the new machine has the complete project. Nothing is stranded in an uncommitted working tree.
- **Latest commit:** `18350bb` "docs: session wrap-up — save open progress + log v0.60 tagger rework".
- **Mod version:** `Config.version = "0.65"` (`mod/JackieLives/config.lua`). NOTE: version numbers jump
  around because several Claude sessions edit in parallel — treat in-code `vX.Y` comment tags as
  historical labels, not a reliable order. See `memory/shared-working-tree-concurrent-sessions.md`.

## 2. New-machine setup checklist
1. **Game:** install Cyberpunk 2077 — **GOG or Steam, NOT Game Pass/MS Store** (much harder to mod).
   **Pin the version and disable auto-update** — game-patch vs mod mismatch is the #1 source of breakage.
2. **Mod tooling** (install into the game dir, standard CP2077 stack):
   RED4ext · redscript · **Cyber Engine Tweaks (CET) 1.18.1+** · TweakXL · ArchiveXL · Codeware ·
   Audioware · **AppearanceMenuMod (AMM)** · **Native Settings UI**.
   - ⚠️ Native Settings UI folder MUST be named exactly `nativeSettings` under
     `…\cyber_engine_tweaks\mods\` (`GetMod` matches by folder name).
3. **Clone** this repo anywhere, then deploy:
   ```powershell
   .\deploy.ps1                      # auto-detects Steam install
   .\deploy.ps1 -GameDir "X:\...\Cyberpunk 2077"   # if auto-detect fails
   ```
   `deploy.ps1` copies `mod\JackieLives` → CET mods folder and `audioware\JackieLives` → `r6\audioware`.
4. **Iterate:** edit files → `.\deploy.ps1` → CET overlay → "Reload all mods" (console prints
   `[JackieLives] Loaded vX`). Load a SAVE to test spawning (no world at the main menu). Test on a
   backup save — mods can corrupt saves.

## 3. What's been built recently (v0.44 → v0.65)
- **Esc-menu settings panel** (Native Settings UI, `nsTick` in init.lua): **Go Home Jackie** recovery
  button (`hardReset` — despawn-all + full state wipe + return to schedule), **Husbando mode** toggle,
  **Disable vehicle arrivals** toggle, and **persistence** across saves via `jl_settings.txt`
  (`jlSaveSettings`/`jlLoadSettings`, key list = `JL_SETTINGS_KEYS`, boolean-only for now).
- **Voice bank refresh 777 → 1280 lines** + tagger rework + String-ID recovery (String ID = decimal of
  the wem hash); `tools/` Whisper transcription + `tag_usage.py`; `docs/VOICE_LINES.md` canonical labels.
- **Track A lipsync probe** — play a line by stringId with native lipsync (dump-first; awaiting test).
- **Bike-model test harness** — ✅ RESOLVED: Jackie's real (gold) Arch is
  `Vehicle.v_sportbike2_arch_jackie_player` (appearance "default"), confirmed in-game and used by all
  vehicle flows. Harness kept only as a fallback for any future livery regression.
- **Arrival system** — unified to two modes (foot / bike) through `vehicleArrivalTick`; side-spawn,
  park-and-walk, height/respawn guards, arrival grunt; **catch-his-eye smile**, **ambient grunts**,
  **dinner outings**, **asleep (00:00–06:00) no-pickup**.

## 4. Open threads / next-session priorities (see TODO.md for the full list)
- **Lots of "awaiting test" items** — most recent features are deployed but unverified in-game. The
  highest-value next move is a play session ticking off the `- [ ] TEST:` boxes in `TODO.md`.
- **Husbando mode is INERT** — the toggle sets `JL.husbando` but nothing reads it yet. Next: branch
  dialogue (endearments/couple banter, no Misty refs) + alternate venue schedule (`Config.daySchedules`).
  ⚠️ **Design ambiguity to resolve:** this session's toggle = a *romance* flag ("Jackie & V closer, broke
  up with Misty"); but TODO §"Hermano/Husbando = V-gender modes" frames it as male-V vs female-V. Decide
  whether it's one switch (romance) or tied to V's gender before wiring content.
- **Esc-menu settings backlog** — schedule on/off + proximity slider, arrival-method dropdown, companion
  auto-leave, barks/dinner/secret toggles, dismiss-all + reset buttons, debug subcategory. Needs
  **non-boolean persistence** (`jlSave/LoadSettings` are boolean-only today).
- ~~**Bike-model test** — click B1/B2/B3 / M1/M2/M3 in-game, report which spawns the correct gold Arch.~~
  ✅ RESOLVED — his Arch is `v_sportbike2_arch_jackie_player` (default), locked into all vehicle flows.
- **Release prep** — `init.lua` is large; a discussed `modules/` split (start with lowest-risk
  `modules/diag.lua`). `package.ps1` for a Nexus-ready zip + Nexus page text. ⚠️ **Cannot ship CDPR
  voice audio** (copyright) — distribute build scripts, not `.ogg`s. See
  `memory/nexus-publishing-constraints.md`.
- **Verify main-quest API in-game** (journal reflection) — gates the "decline summon during main quests"
  rule.

## 5. Working agreements / gotchas (read before editing)
- **Concurrent sessions share this working tree.** `git status` flip-flops and the version jumps. NEVER
  blind-commit (`git add -A`) — stage specific files so you don't capture another session's half-finished
  work. The tree was clean at transfer; keep it coordinated.
- **Native Settings:** register from `onUpdate` (`nsTick`), not `onInit` (load order); guard dupes on the
  TAB path only — `pathExists` on a sub-path throws before the tab exists. See
  `memory/native-settings-ui-integration.md`.
- **Deploy is last-writer-wins** into one shared CET mods folder; re-deploy after someone else deploys.
- Project rules + lore live in `CLAUDE.md` and `docs/DESIGN.md`. Keep `TODO.md` + `docs/logbook.txt`
  current after every major change.
