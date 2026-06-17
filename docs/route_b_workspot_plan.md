# Route B — workspot talk-loop (lip-movement Phase 1 fallback)

> **OUTCOME: ABANDONED (2026-06-17).** Superseded by Route C (`PlayVoiceOver` + facial flap) — see
> `lipsync.md`. Route B was confirmed *callable* (`gameWorkspotGameSystem` reachable) but we could not
> extract a usable conversation-workspot path: a talking ambient NPC reports `IsActorInWorkspot=true` yet
> 0 workspot tags and no readable resource, and a body workspot wouldn't reliably carry a facial track.
> Kept below for reference only.

Status (historical): staged, pending Route-A result.

## Why this route
Phase-0b probe confirmed `gameWorkspotGameSystem` is reachable with the needed methods:
`PlayInDevice`, `PlayInDeviceSimple`, `StopInDevice`, `PlayNpcInWorkspot`, `StopNpcInWorkspot`,
`SendJumpToAnimEnt`, `SendJumpToTagCommandEnt`. The RED-modding "abusing workspots" guide confirms
you can **reference base-game animations/workspots directly** — no animation authoring.

## The technique (from the wiki)
1. (Optional) spawn an invisible `.ent` containing only a `workWorkspotResourceComponent` that
   references a `.workspot` by `name` + `DepotPath`. The `.workspot` holds `worksSequence`(s) of
   `workAnimClip` entries with `idleName` / `animName`.
2. Runtime: `GetWorkspotSystem().PlayInDevice(device, npc)` then
   `SendJumpToAnimEnt(npc, n"animName", true)`. Stop with `StopInDevice` / `StopNpcInWorkspot`.
   - Driver already written: `mod/JackieWorkspotTest/init.lua` (standalone; tries
     `PlayNpcInWorkspot(npc, workspot)` + `SendJumpToAnimEnt`, with a Probe + Stop, all logged).

## THE OPEN RISK (decides if B works at all)
A workspot drives a **body** animation track. We need the **face/mouth** to move. So we must
reference a workspot whose animation includes a **facial talk track** — i.e. an ambient
**conversation / "chitchat"** workspot that background NPCs use when they appear to talk, NOT a
body-only idle (lean/smoke). If no vanilla workspot carries a facial talk track, B needs a custom
`.workspot` referencing a facial talk `.anims` (heavier; only then consider authoring).

## Next concrete steps (need WolvenKit)
1. In WolvenKit, browse `base\workspot\` (and `base\animations\...` facial/conversation) for a
   **conversation/talk** workspot used by ambient NPCs. Candidates to search by name:
   `chitchat`, `conversation`, `talk`, `civilian ... talk`, `crowd ... talk`.
2. Note its **DepotPath** and the **animName/idleName** of the talking clip inside it.
3. Put both into `WORKSPOT_PATH` + `ANIM_NAME` at the top of `mod/JackieWorkspotTest/init.lua`,
   redeploy that folder, reload mods, look at Jackie, click **Start talk workspot** → watch mouth.
4. If the mouth flaps: wire the same `PlayNpcInWorkspot`/`SendJumpToAnimEnt` + stop into the main
   mod's dialogue runner (`speakJackieLine`/`dialogueTick`) — start on line begin, stop when the
   Audioware clip duration elapses. (Do that edit in JackieLives only when no other session is in it.)
5. If body moves but mouth doesn't: the chosen workspot has no facial track → try another, or
   escalate to a custom `.workspot` + facial `.anims` (last resort).

## Deploy note
These test mods are deployed by direct robocopy (not `deploy.ps1`), e.g.:
`robocopy mod\JackieWorkspotTest "<game>\bin\x64\plugins\cyber_engine_tweaks\mods\JackieWorkspotTest" /E`
