# Research — Scripted text messaging from Jackie (TODO feature #1)

_Written 2026-07-03. Feasibility spike for pre-written SMS threads that unlock after quest beats._

## The goal (Antonia)
Jackie can **text V** — pre-written messages (NOT AI-generated; we script them with Claude beforehand) that
become **available after major quest developments** ("you can update your partner on what's been going on").
Data-driven, in-character, unlocked by the mod's own story progress.

## Verdict
**Feasible, moderate effort.** The CP2077 phone/messenger system is well-trodden; multiple shipping mods
inject messages. The catch for *this* project: JackieLives is **100% CET Lua** today, and messaging lives on
the **redscript/journal** side — so the one thing to prove first is whether we can reach it from Lua or need
a small redscript shim. Everything else (content, gating, "new message" ping) is stuff the mod already does.

## Reference mod (inspiration only — we build our own, do NOT extend it)
**Immersive Generative Texting** — github.com/Hugana/Immersive-Generative-Texting-Cyberpunk-2077
- **100% redscript** (`.reds`). Files like `ContextDataSystem.reds`, `GenerativeTextingUtilities.reds`,
  `GenerativeTextingHttpRequests.reds`.
- Hooks native systems (`PreventionSystem`, `PhoneUI`, a custom `ContextEventManager`); pipes an LLM's reply
  through tag-parsing (`[ACTION: …]`) into the phone UI. We want the **delivery half only**, none of the LLM.
- Takeaway: it proves runtime message injection from redscript is solid; it does NOT expose the low-level
  journal call in its README (see Path A unknown below).

## Two real implementation paths

### Path A — runtime injection, gated on our game facts  ★ recommended
Push a phone message into the journal/messenger at runtime when a `jackielives_*` fact flips.
- **Native pieces:** `JournalManager` (owns journal/phone state) + a `gameJournalPhoneMessage` entry inside a
  `gameJournalPhoneConversation` thread. Delivering = adding/activating that entry + firing the "new message"
  notification.
- **Why it fits JackieLives:** the mod ALREADY tracks its own per-save game facts for story stage and gates
  behaviour on them. "Unlock a text after a quest beat" = set-fact → deliver-text. No quest-graph web, no
  cascading dependency (same reasoning that made us pick the summon/fact design over editing `.scene` files).
- **Content = data-driven** `Config.texts` tree, same shape as the existing dialogue `Config` trees:
  `{ id, afterFact, from="Jackie", lines={…}, sfx? }`. Writing new texts = editing config, no code.
- **★ THE ONE UNKNOWN TO SPIKE FIRST:** can we construct + deliver a `gameJournalPhoneMessage` from **CET
  Lua** (keeps 100% of the mod in one stack), or does it need a small **redscript** module?
  - CET can call native/redscript methods and **Codeware** adds reflection + persistent-entity helpers, so
    Lua *may* reach `JournalManager`. If yes → this is a ~1-file Lua addition.
  - If the journal add-path is redscript-only → write a tiny `.reds` that exposes one function
    (`JackieSendText(threadId, body)`) and call it from Lua. That makes texting the project's **first
    redscript component** — manageable, but a new build step (scripts land in `Cyberpunk 2077\r6\scripts`).
  - **Do this spike before estimating further.** It's the whole fork in the road.

### Path B — authored `.journal` + `.questphase` (WolvenKit / ArchiveXL)  ← fallback
The official "add a new text-message thread" route (wiki.redmodding.org → quest → *How to add new text
messages thread*).
- **Tools:** WolvenKit (+ ArchiveXL; TweakXL only if the thread needs a custom contact image).
- **Files:** create a `.journal` (message storage), a `.questphase` graph (the runtime trigger), an onscreen
  `.json` (localised text), optional `.inkatlas` (contact image); record `gamedataJournalIcon_Record`.
- **Trigger:** runtime, via questphase **Pause conditions** waiting on a **custom Fact** or a quest-completion
  state — e.g. `[1147] Pause condition – waits for the certain custom Fact`. So gating is still fact-based,
  which is compatible with our facts.
- **Complexity: intermediate–advanced** — questphase graph logic + journal structure + localisation JSON.
  Heavier WolvenKit work for Antonia and pulls in quest-graph editing we've otherwise avoided.
- **Use only if** Path A's journal API turns out to be closed to both Lua and a thin redscript shim.

## Scope decision to make up front: replies?
- **MVP = one-way** (Jackie texts, V reads). Trivial once delivery works. Do this first.
- **Branching V replies** need the phone's choice-hub reply UI — meaningfully harder (that's most of what the
  generative-texting mods wrestle with). Defer to a v2.

## Recommended plan
1. **SPIKE (Path A from CET):** hard-code one Jackie text and try to make it land in V's phone via
   `JournalManager` + `gameJournalPhoneMessage` from Lua (lean on Codeware reflection).
2. If Lua can't, write the minimal redscript shim; call it from Lua.
3. Wire `Config.texts` + fact gates (reuse the story-stage facts) + the "new message" ping. One-way MVP.
4. Later: branching replies, contact photo, SFX.
- **200-local cap:** any init.lua touch goes in as globals or a new module (e.g. `texting.lua`), never new
  top-level `local`s.

## Sources
- Immersive Generative Texting — github.com/Hugana/Immersive-Generative-Texting-Cyberpunk-2077
- redmodding wiki — *How to add new text messages thread to Cyberpunk 2077*
  (wiki.redmodding.org/…/modding-guides/quest/how-to-add-new-text-messages-thread-to-cyberpunk-2077)
- redmodding wiki — *How to edit in-Game Messages*
