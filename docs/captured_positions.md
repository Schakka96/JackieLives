# Captured Jackie schedule positions

Durable record of in-game positions captured with the CET "Capture current position" button.
These feed `Config.locations` in `mod/JackieLives/config.lua`. Format: `pos = { x, y, z }`, `yaw` in degrees.

> NOTE (session 2, 2026-06-16): captured by Antonia, now MERGED into the live
> `mod/JackieLives/config.lua` (`Config.locations.misty` + `Config.locations.noodle`).

| Key      | Place                | pos                              | yaw   | Notes |
|----------|----------------------|----------------------------------|-------|-------|
| `misty`  | Misty's Esoterica    | `{ -1541.072, 1195.238, 15.869 }`| 50.9  | **Replaces Vik/Vic** as a possible destination. |
| `noodle` | Noodle bar           | `{ -1441.064, 1257.748, 23.090 }`| -87.1 | There's a **chair** here → Jackie should find the nearest chair and **sit** once loaded (`sitNearest = true`). Not built yet — see TODO. |
| `test`   | Test spot (native-box test save) | `{ -854.737, 1833.329, 36.207 }` | 44.4 | Pre-existing test coord. |

## Behaviour requirements tied to these spots (Antonia, session 2)

- **Idle Jackie at these places must NOT be a follower.** Already true: the schedule spawns him
  with the passive flag (`ammSpawn(0)` in `scheduleTick`), so scheduled/idle Jackie just stands
  (or sits) around — he is not a companion.
- Going from idle → follower happens **only via dialogue** ("go a job" / "let's hang out"), which
  flips him to companion behaviour. — TODO, not built.
- A **dismiss dialogue** sends him back to idle/schedule. — TODO, not built.
- **Chair-sit at the noodle bar:** on idle-spawn, find the nearest seat and play a sit workspot.
  — TODO, not built (feasibility note in TODO.md).
