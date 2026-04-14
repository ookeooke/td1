# Sessions Log

One line per session: date, phase, what worked, what broke.

---

## 2026-04-14 — Phase 0 + Phase 1: Skeleton
- Consolidated nested `td1/.git` to project root (remote: github.com/ookeooke/td1)
- Configured `project.godot`: portrait 375×812, canvas_items/expand, emulate touch, 6 autoloads, Main.tscn as entry
- Created folder structure for all 41 phases
- Wrote 6 autoload stubs; `EventBus.gd` contains every signal from CLAUDE.md
- `Main.tscn` + `Main.gd` prints 6 "[X] loaded" lines + signal count
- Works: project opens, skeleton runs
- Broke: none
- Next: Phase 2 — Map + multiple Path2Ds + fixed tower spots

---

## 2026-04-14 — Phase 2: Map + Paths + Spots
- `map/Map.tscn`: green background, NavigationRegion2D, 3 Path2Ds (left/right/top), 6 Marker2D tower spots, GridManager
- `map/Map.gd`: builds Curve2D points in code for all 3 paths, debug `_draw()` renders paths as brown lines + spots as yellow circles
- `map/GridManager.gd`: spot registry with occupancy tracking (`register_spot`, `is_occupied`, `get_free_spot_ids`)
- `main/Main.tscn` instances Map; `Main.gd` prints registered spots
- Works: map draws, 6 spots registered, 3 paths built
- Broke: none
- Next: Phase 3 — SpawnMarkers on screen edges (direction indicators)

---

## 2026-04-14 — Phase 3: Spawn direction markers
- `map/SpawnMarker.tscn` + `.gd`: Node2D with @export `path_id`, `direction_degrees`, `enemy_icon_color`. `_draw()` renders a yellow arrow with a red-circle enemy-icon placeholder
- Placed 3 markers in `Map.tscn` at path entry points: left (0°), right (180°), top (90°)
- `Map.gd` prints marker count alongside paths/spots
- Static visuals only — Phase 11 wires show/hide to wave countdown and per-wave enemy-icon updates
- Works: 3 arrows visible at screen edges pointing into the map
- Broke: none
- Next: Phase 4 — one enemy walking one path and dying
