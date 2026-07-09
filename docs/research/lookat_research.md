# NPC head-tracking (look-at) — verified research

Research for JackieLives, patch 2.x (CET/Lua). Goal: a venue Jackie (standing, leaning, or sitting in an
AMM workspot) turns his head toward V the way he already does as a companion. Verified against the CDPR
script decompile and the NativeDB RTTI JSON dumps. Implemented as `Config.lookAt` + `jlLookAt*` in `init.lua`.

## Why he was frozen

As a **companion**, `sendWalkToPlayer()` issues an `AIFollowTargetCommand` and sets
`cmd.lookAtTarget = Game.GetPlayer()`. The head-tracking is a property of the *follow command*.

A **venue** Jackie has no follow command — he's placed by `aiTeleport`/`placeAtExact` and then pinned by an
AMM sit workspot. So nothing was ever telling him to look anywhere, and he stared at the baked seat yaw.

Good news from tracing the idle path: **nothing re-applies his yaw per frame while he dwells or sits.**
Rotation is only written at discrete moments (waypoint arrival, and the one-shot `placeAtExact` sit lock).
So a look-at has nothing to fight.

## The mechanism — `entLookAtAddEvent`

**CONFIRMED.** RTTI `entLookAtAddEvent`, REDscript alias `LookAtAddEvent`, parent `entAnimTargetAddEvent`
(← `redEvent`). Source: `scripts/core/events/lookAtEvents.script`.

```
importonly abstract class AnimTargetAddEvent extends Event
{
    import var bodyPart : CName;
    public import function SetEntityTarget( targetEntity : weak<Entity>, slotTargetName : CName, targetOffsetEntity : Vector4 );
    public import function SetStaticTarget( staticTargetPositionWs : Vector4 );
    public import function SetPositionProvider( provider : IPositionProvider );
}

import class LookAtAddEvent extends AnimTargetAddEvent
{
    import var request : LookAtRequest;
    import var outLookAtRef : LookAtRef;
    public import function SetStyle( style : animLookAtStyle );
    public import function SetLimits( softLimitDegreesType : animLookAtLimitDegreesType,
                                      hardLimitDegreesType : animLookAtLimitDegreesType,
                                      hardLimitDistanceType : animLookAtLimitDistanceType,
                                      backLimitDegreesType : animLookAtLimitDegreesType );
    public import function SetAdditionalPartsArray( additionalParts : array<LookAtPartRequest> );
}
```

Enums (verbatim): `animLookAtStyle { VerySlow, Slow, Normal, Fast, VeryFast }` ·
`animLookAtLimitDegreesType { Narrow, Normal, Wide, None }` ·
`animLookAtLimitDistanceType { Short, Normal, Long, None }`

Two properties make this exactly the right tool:

1. **`SetEntityTarget(player, ...)` makes the engine follow the live entity every frame.** We queue the
   event **once**; the engine tracks V as she moves. No per-frame loop, no yaw math, no jitter. Vanilla's
   `AIGenericEntityLookatTask.ActivateLookat` early-returns if the event already exists — proof it isn't
   re-issued per frame.
2. **It's an additive animation-graph overlay**, so it composes with a workspot and turns the *head*, not
   the body — it cannot eject him from the barstool.

Vanilla usage to copy (`scripts/core/components/scriptComponents/reactionComponent.script`, verbatim):

```
lookAtEvent = new LookAtAddEvent;
lookAtEvent.SetEntityTarget( targetEntity, 'pla_default_tgt', Vector4.EmptyVector() );
lookAtEvent.SetStyle( animLookAtStyle.Normal );
lookAtEvent.request.limits.softLimitDegrees = 360.0;
lookAtEvent.request.limits.hardLimitDegrees = 270.0;
lookAtEvent.request.limits.backLimitDegrees = 210.0;
lookAtEvent.request.calculatePositionInParentSpace = true;
lookAtEvent.bodyPart = 'Eyes';
owner.QueueEvent( lookAtEvent );
```

Removal (static helper on the remove event):
`LookAtRemoveEvent.QueueRemoveLookatEvent( owner : GameObject, addedBeforeEvent : LookAtAddEvent )`

## Does it survive a sit workspot?

**Yes.** Nothing in `workspotSystem.script` references look-at and nothing in `lookAtEvents.script` checks
workspot state — they're independent subsystems, the look-at layering on top of the base pose. Real-world
confirmation: the **Sit Anywhere** mod (Nexus 7299) exposes per-workspot head-turn yaw limits
(`maxYaw`/`minYaw`) so users can "look more to the left/right when sitting" — i.e. head look-at is
demonstrably live during a sit workspot.

Caveat: a seated pose already twists the head, so a narrow cone would hit the hard limit before he faces V.
Hence the **Wide** soft/hard limits in `Config.lookAt` (mirroring vanilla's 360/270/210).

## Dead ends (checked so nobody re-checks them)

- **There is no cheap AI-command win.** `AIHoldPositionCommand` (fields: `duration` only) and
  `AIUseWorkspotCommand` (`workspotNode`, `jumpToEntry`, `entryId`, `entryTag`) have **no** `lookAtTarget`.
  `AIIdleCommand` / `AIWorkspotCommand` don't exist under those names. Only `AIFollowTargetCommand` carries
  `lookAtTarget` (confirmed type `whandle:gameObject`) — and it's a *move* command, so forcing it on a
  seated Jackie would fight the workspot and could stand him up.
- **`NPCPuppet.SetLookAtTarget` does not exist.** The only `LookAt` identifiers on `NPCPuppet`/`ScriptedPuppet`
  are scanner-UI related and set a UI bool.
- **These classes do not exist** (despite sounding plausible): `entLookAtTargetEntityDescription`,
  `entLookAtTargetPositionDescription`, `entLookAtDescription`. Targeting is done with the parent's
  **methods**, not a description struct. Nor do the fields `additive`, `calculatePositionOnce`, `lookAtType`
  (the real one is `calculatePositionInParentSpace`).
- **Photo mode is not a usable POC.** Its "look at camera" is a native C++ attribute pushed through
  `OnAttributeUpdated(attributeKey, value)`; no photo-mode script touches `LookAtAddEvent`.
- **Per-frame teleport yaw** rotates the *whole body*, jitters, and fights the workspot. Strictly worse.

## What is UNVERIFIED — and how the code copes

The **CET-Lua marshalling** of this event. No shipped CET-Lua mod constructs an `entLookAtAddEvent`, so
which form CET accepts is unknown:

- `entLookAtAddEvent.new()` vs `NewObject("entLookAtAddEvent")` vs `NewObject("handle:entLookAtAddEvent")`
- whether `animLookAtStyle` / `animLookAtLimitDegreesType` are exposed as Lua globals

`jlNewLookAtEvent()` **tries all three constructors** and caches the winner; `jlAnimEnum()` falls back from
the global table to `Enum.new()` and returns nil (skipping that setter) if neither works. `jlLookAtStart()`
wraps setup + `QueueEvent` in a `pcall` and, on failure, logs **once** and disables tracking for the session.

**The failure mode is "Jackie behaves exactly as he did before".** It cannot break him.

### First in-game test (Windows)
Walk up to Jackie at a venue and watch `jackie_debug.log`:
- `LookAt: now tracking V (ctor=..., bodyPart=Eyes).` → working; note which `ctor` won.
- `LookAt: cannot construct entLookAtAddEvent -> head tracking OFF` → try `bodyPart = "Head"`, and report
  the ctor line so we can drop the dead branches.

Also unverified: the full set of valid `bodyPart` CNames. Only `'Eyes'` and `'LeftHand'` are confirmed
literals; `'Head'` / `'Chest'` are plausible but live in TweakDB `LookAtPreset_Record` and weren't enumerated.

## Sources
- `lookAtEvents.script`, `reactionComponent.script`, `aiLookats.script`, `workspotSystem.script`,
  `teleportationFacility.script` — https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts
- RTTI JSON dumps (`entLookAtAddEvent.json`, `animLookAtRequest.json`, `AIFollowTargetCommand.json`,
  `AIHoldPositionCommand.json`, `AIUseWorkspotCommand.json`) —
  https://github.com/striderxfossility/NativeDB/tree/master/public/dumps/classes
- Seated look-at works in practice (Sit Anywhere) — https://www.nexusmods.com/cyberpunk2077/mods/7299
- Browsable RTTI — https://nativedb.red4ext.com/entLookAtAddEvent
