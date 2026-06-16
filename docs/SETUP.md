# SETUP — environment & modding stack (Steam, Patch 2.3/2.31)

Target game: **Cyberpunk 2077 on Steam, Patch 2.3 / hotfix 2.31** (current public build, Oct 2025).
Mod manager: **Vortex** (recommended for a beginner — handles the dependency stack automatically).

> Do the phases in order. Don't skip Phase 0 — protecting the install version is what prevents the
> "everything broke after an update" disaster.

## Phase 0 — Protect the install (do this first)
1. **Stop auto-updates:** Steam → Library → right-click *Cyberpunk 2077* → **Properties → Updates** →
   set **"Only update this game when I launch it."**
2. **Don't update past 2.31** until the core mods post compatibility for the next patch. If Steam ever
   wants to update, hold off and check Nexus first.
3. **Back up saves:** copy
   `C:\Users\ficht002\Saved Games\CD Projekt Red\Cyberpunk 2077\`
   to a safe folder. Mods can corrupt saves.
4. **Make a dedicated test save** (a fresh one we can throw away).
5. (Hardware note: the game runs poorly on this laptop. That's fine for dev — drop all graphics to Low;
   mod logic doesn't care about visuals. We iterate on behavior, not framerate.)

## Phase 1 — Mod manager
6. Create a free **Nexus Mods** account (nexusmods.com).
7. Install **Vortex** (nexusmods.com/about/vortex).
8. In Vortex: **Games** tab → find **Cyberpunk 2077** → **Manage**. Let it auto-detect the Steam install
   (or point it at `...\steamapps\common\Cyberpunk 2077`).

## Phase 2 — Core framework (install via Vortex, in this order)
Each is on Nexus; "Mod Manager Download" sends it straight to Vortex. Install, then **Deploy**.
9.  **RED4ext** (native plugin loader — foundation).
10. **redscript** (game-logic scripting compiler).
11. **Cyber Engine Tweaks (CET)** (Lua runtime + console — our prototyping tool).
12. **TweakXL** (runtime TweakDB records).
13. **ArchiveXL** (runtime new entities/appearances/world additions).
14. **Codeware** (scripting extension lib — persistent NPC spawning etc.).
15. (Common helpers other mods want) **Mod Settings**, **Input Loader**.
16. (Optional) Install the free official **REDmod** DLC from Steam — some mods deploy through it; our
    stack doesn't strictly need it, but it's handy to have.

## Phase 3 — Prototyping mod
17. **AppearanceMenuMod (AMM)** (depends on CET + Codeware). This is our fast feasibility tester — it can
    already spawn Jackie and make him follow.

## Phase 4 — Verify the stack works
18. Launch the game normally (Steam → Play). Load the test save.
19. Press the **`~` / tilde** key (or the key CET prompts for on first launch) → the **CET overlay**
    should appear. If it does, RED4ext + CET are working. ✅
20. Open **AMM** in the CET overlay → spawn **Jackie** → set him to follow. If he appears and follows,
    we've basically proven MVP-0/MVP-1 are reachable. ✅

## Maintenance rules
- After any future game patch: **don't launch modded** until RED4ext + the core mods update. Watch Nexus.
- Keep a written list of installed mod **versions** (add to this file) so we can reproduce the setup.
- Our own mod will live in a tracked dev folder under this project and deploy into the game dir
  (workflow TBD once the stack is verified).

## Installed versions (fill in as we go)
| Mod | Version | Date installed |
|-----|---------|----------------|
| Game (Cyberpunk 2077) | 2.3 / 2.31 | |
| RED4ext | 1.30.0 | |
| redscript | 0.5.31 | |
| CET | 1.37.1 | |
| TweakXL | 1.11.3 | |
| ArchiveXL | 1.26.8 | |
| Codeware | 1.20.3 | |
| AMM | 2.12.5 | |
