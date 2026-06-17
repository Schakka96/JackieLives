# Native phone / holocall — in-game probes

Goal: find out whether we can drive the **real** phone dialing UI (Jackie's contact
thumbnail + ringtone) from script, keep it open ~2.5s, then hand off to our voice line +
dialogue box. We can't tell from outside the game, so we probe live in the CET console.

How to run a probe:
1. Launch Cyberpunk, load a save.
2. Press the CET overlay key (default **`~`** / the key left of `1`).
3. Click the **Console** tab (or the "Game Log / Console" window).
4. Paste the whole probe block into the input line, press **Enter**.
5. Copy every `[PROBE]` / `[HOOK]` line it prints and send them back.

Output also lands in:
`...\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.log`

---

## Probe 1 — what phone/holocall objects can Lua reach? (read-only, safe)

```lua
do
  local function P(label, fn)
    local ok, v = pcall(fn)
    print(("[PROBE] %-30s = %s"):format(label, ok and tostring(v) or ("ERR "..tostring(v))))
  end
  P("Game.GetPhoneSystem",      function() return Game.GetPhoneSystem() end)
  P("Game.GetHolocallSystem",   function() return Game.GetHolocallSystem() end)
  P("Game.GetJournalManager",   function() return Game.GetJournalManager() end)
  P("container PhoneSystem",    function() return Game.GetScriptableSystemsContainer():Get(CName.new("PhoneSystem")) end)
  P("container HolocallSystem", function() return Game.GetScriptableSystemsContainer():Get(CName.new("HolocallSystem")) end)
  P("player GetPhone",          function() return Game.GetPlayer():GetPhone() end)
  P("phone fact: jackie_dead",  function() return Game.GetQuestsSystem():GetFactStr("q003_jackie_dead") end)
  print("[PROBE] Probe 1 done. Send me every [PROBE] line above.")
end
```

What each line tells us:
- A non-nil `...System` / `GetPhone` = Lua can reach that object (good — gives us something to hook).
- `ERR ...` = that access pattern doesn't exist on this build; we use whichever one worked.
- The `jackie_dead` fact value (0/1/nil) tells us if there's a readable death flag to flip.
  (The exact fact name is a guess — if it's nil we'll hunt the real one next.)

### Probe 1 RESULT (2026-06-16)
- `Game.GetPhoneSystem` / `GetHolocallSystem` / `player:GetPhone` = ABSENT (no such getters).
- `container PhoneSystem` = **userdata (reachable)** — scripted system, hookable + callable.
- `container HolocallSystem` = nil — native IGameSystem, no instance, but its methods are still hookable.
- `JournalManager` = reachable. `jackie_dead` fact = 0 (inconclusive; unknown facts also read 0).

---

## Probe 2 — what fires when you CALL Jackie? (live hooks; the decisive test)

NOTE: the CET console truncates big pasted blocks (Probe 2 failed that way), so these hooks were
MOVED INTO THE MOD instead — guarded by `Config.probeNativePhone = true`. Just **restart the game**,
**open the phone, call Jackie**, then read the `[JackieLives] PROBE ...` lines in the CET console.
Turn the flag off when done. (Old console version kept below for reference.)

```lua
do
  local function HOOK(cls, method)
    local ok, err = pcall(function()
      ObserveAfter(cls, method, function() print(("[HOOK] %s :: %s"):format(cls, method)) end)
    end)
    print(("[PROBE] reg %-42s = %s"):format(cls.."::"..method, ok and "ok" or ("FAIL "..tostring(err):sub(1,50))))
  end
  -- native holocall system (fires if Jackie's contact triggers a real holocall):
  HOOK("HolocallSystem", "AddHolocall")
  HOOK("HolocallSystem", "ChangeHolocallStatus")
  HOOK("HolocallSystem", "RemoveHolocall")
  -- scripted phone system (the reachable one):
  HOOK("PhoneSystem", "OnContactSelected")
  HOOK("PhoneSystem", "RequestPhoneCall")
  HOOK("PhoneSystem", "OnPhoneCallStarted")
  -- phone/contacts UI controllers (these also fire when the phone just OPENS = sanity check):
  HOOK("PhoneDialerGameController", "OnInitialize")
  HOOK("gameuiContactsListGameController", "OnContactActivated")
  HOOK("ContactsListItemVirtualController", "OnSelected")
  print("[PROBE] hooks set. Now OPEN the phone, CALL Jackie, then send me every [HOOK] line.")
  print("[PROBE] If NOTHING fires even when the phone just opens -> tell me (means console hooks")
  print("[PROBE] don't catch here, and I'll move the probe into the mod and redeploy).")
end
```

What the outcomes mean:
- **`HolocallSystem::AddHolocall` fires when you call Jackie** → his contact triggers a real holocall we
  can hook → native integration is viable (we override status/hangup to keep it open + hand off).
- **Dialer/contacts hooks fire but no HolocallSystem** → the dialing screen shows but no holocall connects
  (dead contact, no scene) → we hijack at the dialer level or supply our own.
- **Nothing fires at all, even on phone open** → console-registered hooks don't catch; I move these same
  hooks into `init.lua` and redeploy (Observe definitely works from the mod context).

---

## Probe 2 RESULT — reflection dump (2026-06-16): the real architecture

The console truncated the pasted block, so hooks were moved into the mod and dump to files I read
directly (`mods/JackieLives/phone_methods.txt`, `probe_fires.txt`). Codeware reflection gave the REAL
method names:
- **NO `HolocallSystem` class exists** (NOT FOUND). Calls are not holocall-system driven.
- **`PhoneSystem` (scriptable, reachable) is the call engine.** Critical methods:
  - `TriggerCall(questPhoneCallMode, Bool, CName, Bool, questPhoneCallPhase, Bool, Bool, Bool, questPhoneCallVisuals)`
    — quests start a call here; the **CName** = call id, **questPhoneCallVisuals** = Holo vs Audio.
  - `OnTriggerCall(questTriggerCallRequest)`, `OnPickupPhone(PickupPhoneRequest)`,
    `GetPhoneCallFactName(CName)->CName`, `IsCallingAvaliable`, `SetPhoneFact(...)`.
- **`PhoneDialerGameController`**: `CallSelectedContact()` = fires when the player calls a picked contact
  (our DETECTION hook). Also `Show`/`Hide`, `OnItemSelected`, `GetSelectedContactData`.
- **`PhoneMessagePopupGameController`**: `TryCallContact()`, `CallContact()`.
- First in-mod hooks (AddHolocall etc.) never fired — all names wrong; `probe_fires.txt` wasn't created.

**Emerging plan (pending Probe 3):** native path = Observe `CallSelectedContact` / `PhoneSystem.TriggerCall`
to DETECT the player calling Jackie → native ringing UI (thumbnail + ring) shows → after ~2.5s hand off to
our voice + dialogue box. A full custom-content native call would need a `questPhoneCall` record + scene
(WolvenKit/TweakXL) — heavy; detection + handoff is the light path.

## Probe 3 — confirm the detection hook fires (corrected names, file-logged)

Deployed. Restart → open phone → **call Jackie** → I read `probe_fires.txt`. Watching for
`PhoneDialerGameController::CallSelectedContact` and/or `PhoneSystem::TriggerCall` (+ its CName arg =
Jackie's call id). If `TriggerCall` fires with a CName, we can even trigger the native ringing UI ourselves.

### Probe 3 RESULT (2026-06-16) — DECISIVE. Calling dead-Jackie fired:
```
t64.2  TriggerCall( mode=Video(2),     false, CName=jackie_dead, true, phase=IncomingCall(1) )  <- ring
t77.0  TriggerCall( mode=Undefined(0), false, CName=jackie_dead, true, phase=EndCall(3)      )  <- ends ~13s
```
- Jackie's call **IS a real holocall** (`mode=Video(2)`, avatar shows). Call id CName = **`jackie_dead`**.
- `questPhoneCallPhase` enum: `IncomingCall=1`, `EndCall=3` (Undefined=0). The dead call rings then ends
  because nothing CONNECTS it — that timeout is the gap we fill with our voice + box.
- **We can call `PhoneSystem.TriggerCall` ourselves** to start the ringing holocall on demand.
- `CallSelectedContact` did NOT fire (she called from contacts/messages path) — `TriggerCall` is the better,
  lower-level hook anyway. Dropped the noisy `GetPhoneCallFactName` (it spams every call-fact lookup).

### Probe 4 — call ALIVE Jackie (he picks up): get the CONNECTED phase
Need the phase value used when a call actually connects (between IncomingCall and EndCall) so we can HOLD
the call open. Probe now logs all 9 TriggerCall args. Antonia: load a save where Jackie is alive, call him,
let him pick up & talk a bit, hang up. Then read `probe_fires.txt`.

### Probe 4 RESULT (2026-06-16) — alive Jackie, FULL recipe captured
```
TriggerCall( Video(2), false, CName=jackie, true, IncomingCall(1), false,false,false, Default(0) )  ring
TriggerCall( Video(2), false, CName=jackie, true, StartCall(2),    false,false,false, Default(0) )  PICKS UP
TriggerCall( Video(2), false, CName=jackie, true, EndCall(3),      false,false,false, Default(0) )  hang up
```
- **Connected phase = `StartCall(2)`** (holds the call live, avatar on screen). Enum: Undefined0 / IncomingCall1 / StartCall2 / EndCall3.
- Alive call id CName = **`jackie`** (dead = `jackie_dead`). visuals = `Default(0)`, mode `Video(2)` = holo.
- Signature: `TriggerCall(mode, false, callId, true, phase, false,false,false, visuals)`.

## v0.29 — driving it ourselves (test buttons)
`Config.nativeCall.id` + `triggerNativeCall(id, phase)` call `PhoneSystem:TriggerCall` directly. UI test
buttons: **Native RING / CONNECT / END**. Open question to answer in-game: does `CONNECT (StartCall)` on
`jackie` ALSO play the game's canned Jackie call (its own VO/choices), or just show him connected & silent
(so we inject our own voice + dialogue box)? If it plays canned content, we either (a) ring-only then hand
off to our overlay, or (b) make our own quest-call record via TweakXL with his avatar + no scene.
The probe hooks stay on, so clicking the buttons also logs any cascading TriggerCall to `probe_fires.txt`.
