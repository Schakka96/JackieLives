# Nexus update notes — JackieLives

Player-facing release notes, ready to paste into the Nexus **Changelog** tab (or the description's
"latest update" block). Written for players, not maintainers — no file names, no internals.

Keep the newest release at the top. The maintainer-facing detail for every version lives in
[`TODO.md`](../TODO.md).

---

## v1.64.1 — the dialogue box is the real one now (and the questline actually starts)

*Covers everything since the last release, v1.61.*

### 🔴 Fixed: the reunion questline never started — for anyone

If you installed JackieLives and nothing ever happened at Vik's clinic, **that wasn't your setup.
It was broken for every player, on every save.** The mod checked whether you'd finished the Heist by
asking the game a question it couldn't answer, got no reply, and then deliberately stayed silent —
including hiding the welcome card that would have told you the manual start button existed. So it sat
there doing nothing and never explained why.

It now reads the Heist completion directly and reliably. Load a post-Heist save and the search for
Jackie begins as intended.

- **Nothing to do** — just update. It picks up on your existing save.
- **No spoilers on early saves.** A pre-Heist save still stays completely silent, as before.
- If you were stuck on v1.63 or earlier, the workaround was
  **Esc → Settings → Mods → JackieLives → "Start the search for Jackie"**. You don't need it any more,
  and using it earlier does no harm.

### ⭐ Jackie's conversations now use the game's own dialogue box

Your replies to Jackie used to appear in a box the mod drew itself — a hand-made imitation of the
real thing. It's gone. Conversations now render in **the game's actual dialogue widget**, the same one
every vanilla conversation uses.

What you'll notice:

- It looks right, because it *is* right — real colours, the real selection bar, the real fade
  animations, and the speaker plate drawn the way the game draws it.
- **Correct at any resolution and aspect ratio.** The old box was positioned by hand and drifted on
  4K and ultrawide displays. There is nothing left to line up.
- Arrows or the mouse wheel move the highlight, **F** selects — as before.

**If you play in Japanese, Russian, Chinese, Polish or any non-Latin language:** your dialogue choices
used to show as boxes (`□□□`) unless you manually installed a CJK/Cyrillic font into Cyber Engine
Tweaks. **That is no longer necessary.** The game's own fonts cover every language the mod ships in.
Just set your game language and leave the mod on Auto.

### Jackie behaves better around the main story

- **He no longer walks off the second a main quest re-appears.** Finishing a side job makes the game
  auto-track a main quest again, which used to make Jackie excuse himself instantly — abrupt and
  annoying. He now **warns you and waits about a minute**. Pick up a side job again inside that window
  and he stays, with a line acknowledging it. Ignore him and he leaves when the timer runs out.
  A cutscene still ejects him immediately, and a brief flicker of auto-tracking no longer sets him off.
- **He stops walking away when you talk to him.** Starting a conversation with a departing Jackie
  freezes his retreat and turns him to face you. If you don't invite him to dinner, he carries on out
  afterwards.
- **He turns to face you** when a face-to-face conversation opens, instead of talking past your
  shoulder. Skipped when he's seated or mid-arrival, where turning him would have broken his pose.

### Blaze of Glory (experimental mode)

- **Both escape exits work.** The spawned VTOL and the level's own roof AV will each trigger the
  escape — reaching either one ends the set-piece.
- **The escape prompt now beats an open conversation.** Previously, if you had a conversation with
  Jackie open when you reached the AV, pressing **F** picked a dialogue line instead of getting in,
  with no way out but finishing the conversation first.

### Also

- New optional setting: lock V's weapon while a conversation is on screen, so a stray click can't
  ruin a moment. **Off by default** — it's a real gameplay change, so it's opt-in.
- Installing and updating is one step now: the repo ships a script that fetches the newest version
  and copies it into the game (relevant if you install from source rather than the Nexus archive).

**Requirements are unchanged.** No new dependencies.

---

## v1.61 and earlier

See the Nexus changelog history and [`TODO.md`](../TODO.md).
