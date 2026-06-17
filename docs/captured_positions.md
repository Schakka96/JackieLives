# Captured Jackie schedule positions

Durable record of in-game positions captured with the CET "Capture current position" button.
These feed `Config.locations` in `mod/JackieLives/config.lua`.

**Format:** `pos = { x, y, z }`, `yaw` in degrees. Each location has one **anchor** (where Jackie
first appears / falls back to) plus a list of **waypoints** he free-roams between (see
`Config.wander`). `pose` is `stand` / `sit` / `lean` — a hint for what he does at that point.

> NOTE (session 3, 2026-06-17): all of these are now MERGED into the live
> `mod/JackieLives/config.lua` (`Config.locations.*` with `waypoints`). The free-roam wander
> (v0.35) walks him between a location's waypoints. `pose = sit/lean` currently just plants him
> on the exact spot facing `yaw` — a real sit/lean **workspot** animation is still a TODO, so
> the `pose` tags are forward-looking data for that feature.

---

## Noodle bar  (`noodle`)

| # | pos                                | yaw   | pose | Notes |
|---|------------------------------------|-------|------|-------|
| 1 | `{ -1441.064, 1257.748, 23.090 }`  | -87.1 | sit  | There's a **chair** here → sit once the workspot feature lands. Anchor. |

## Misty's Esoterica  (`misty`)

| # | pos                                | yaw  | pose  | Notes |
|---|------------------------------------|------|-------|-------|
| 1 | `{ -1541.072, 1195.238, 15.869 }`  | 50.9 | stand | **Replaces Vik/Vic** as a destination. Anchor. |

## El Coyote Cojo  (`coyote`)  — Mama Welles' bar

| # | pos                                 | yaw   | pose  | Notes |
|---|-------------------------------------|-------|-------|-------|
| 1 | `{ -1262.463, -1002.345, 12.037 }`  | -50.9 | lean  | Right of bar, leaning. Anchor. |
| 2 | `{ -1243.806,  -993.222, 12.505 }`  | -79.2 | stand | At arcade station. |
| 3 | `{ -1257.939,  -987.950, 16.038 }`  |  64.1 | sit   | Upstairs at table. |
| 4 | `{ -1267.961,  -990.652, 16.027 }`  | 175.8 | stand | Upstairs at vending machine. |
| 5 | `{ -1263.294,  -996.467, 16.017 }`  | -80.0 | lean  | Upstairs, looking over railing. |
| 6 | `{ -1262.646,  -984.029, 12.037 }`  |   6.5 | lean  | Outside door, leaning. |

## Afterlife  (`afterlife`)  — merc legends bar (night)

| # | pos                                | yaw    | pose  | Notes |
|---|------------------------------------|--------|-------|-------|
| 1 | `{ -1457.063, 1018.598, 16.524 }`  |  -96.9 | lean  | Near entrance, leaning. Anchor. |
| 2 | `{ -1441.141, 1011.210, 16.532 }`  |  147.1 | sit   | At bar, left. |
| 3 | `{ -1444.870, 1034.471, 16.923 }`  |   54.9 | stand | Alcove left, watching a dance. |
| 4 | `{ -1454.586, 1009.834, 16.500 }`  |   65.3 | stand | Watching 2 dancers. |
| 5 | `{ -1450.311, 1012.359, 16.522 }`  | -164.2 | sit   | At bar, right. |

## Ginger Panda  (`ginger`)  — restaurant

Captured + wired, **not in the daily schedule yet** (swap into `Config.schedule` to use).
Waypoints 2–7 are the **"Any Austin" walk-in-circles easter egg** (he can pace the room in
order 2→3→4→5→6→7 and loop). True ordered-loop mode is a TODO; for now he random-roams them
and treats the bar (1) as a long-dwell sit.

| # | pos                              | yaw    | pose  | Notes |
|---|----------------------------------|--------|-------|-------|
| 1 | `{ -485.426, 576.939, 31.302 }`  |  -17.1 | sit   | At the bar (long dwell). Anchor. |
| 2 | `{ -491.638, 592.985, 31.802 }`  | -113.3 | stand | Circle pt 1. |
| 3 | `{ -483.382, 588.253, 31.802 }`  | -153.4 | stand | Circle pt 2. |
| 4 | `{ -475.878, 581.170, 31.802 }`  | -174.1 | stand | Circle pt 3. |
| 5 | `{ -485.072, 570.963, 31.802 }`  |  113.3 | stand | Circle pt 4. |
| 6 | `{ -494.347, 576.980, 31.802 }`  |  -82.7 | stand | Circle pt 5. |
| 7 | `{ -496.151, 584.078, 31.802 }`  |  -36.3 | stand | Circle pt 6 → loop back to 2. |

## Redwood Market  (`redwood`)

Captured + wired, **not in the daily schedule yet**.

| # | pos                               | yaw   | pose  | Notes |
|---|-----------------------------------|-------|-------|-------|
| 1 | `{ -402.802, 710.778, 123.000 }`  | 108.1 | lean  | Upstairs, good view. Anchor. |
| 2 | `{ -422.418, 700.581, 114.999 }`  |  58.9 | stand | On bridge. |
| 3 | `{ -448.024, 685.905, 115.028 }`  | 106.2 | stand | Coffee vendor. |
| 4 | `{ -431.550, 669.948, 115.010 }`  | -33.5 | stand | Noodle place. |

## Test spot  (`test`)

| # | pos                                | yaw  | pose  | Notes |
|---|------------------------------------|------|-------|-------|
| 1 | `{ -854.737, 1833.329, 36.207 }`   | 44.4 | stand | Native-box test save standing spot. |

---

## Behaviour requirements tied to these spots

- **Idle Jackie at these places must NOT be a follower.** Already true: the schedule spawns him
  passive (`ammSpawn(0)` in `scheduleTick`), so scheduled/idle Jackie just stands / sits / roams —
  he is not a companion.
- **Free-roam wander (v0.35, built):** between a location's waypoints he stands/sits/leans for a
  random dwell, then strolls to a **random other** point (never an immediate repeat → no pacing
  back-and-forth), and repeats. Tuning in `Config.wander`.
- Going from idle → follower happens **only via dialogue** ("go a job" / "let's hang out"), which
  flips him to companion behaviour. — TODO, not built.
- A **dismiss dialogue** sends him back to idle/schedule. — TODO, not built.
- **Real sit / lean workspots:** the hard part. `pose` tags are stored; playing an actual
  chair-sit or wall-lean animation needs a workspot resource (and, for "nearest chair", finding
  the chair device at runtime). — TODO; see TODO.md feasibility note.
- **Ginger Panda "Any Austin" ordered-loop easter egg:** waypoints 2–7 in order, loop ~3×, then
  long dwell at the bar. — TODO (random-roam for now).
