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

---

## 2026-04-14 — Phase 4: One enemy walking + dying
- `enemies/EnemyData.gd`: Resource with all spec fields (health, speed, armor, flags, etc.)
- `enemies/data/enemy_basic.tres`: Orc Grunt, 10hp, 70 px/s, 1 life, 5 gold
- `enemies/base_enemy.gd` (class_name BaseEnemy, extends Area2D): state machine via `change_state()`, `_physics_process` increments parent PathFollow2D progress, emits `enemy_reached_end` on arrival and despawns itself + PathFollow2D
- `enemies/EnemyBasic.tscn`: Area2D with CircleShape2D on collision_layer 2; `_draw()` paints a red placeholder disc
- `autoloads/WaveManager.gd`: added `spawn_enemy(path, path_id, scene)` — creates PathFollow2D under target Path2D, instances enemy as its child, calls setup(), emits `enemy_spawned`
- `main/Main.gd`: connects enemy signals to printouts, spawns one enemy on "left" path 1s after ready (Phase 11 replaces with real waves)
- Works: red disc appears at left edge, walks the brown path, prints "reached end" and vanishes
- Broke: none
- Next: Phase 5 — Damage type system + DamageCalculator

---

## 2026-04-15 — Phase 5: DamageCalculator + take_damage
- `autoloads/DamageCalculator.gd`: real enum `DamageType { PHYSICAL, MAGIC, TRUE }`, `calculate_damage(amount, type, target)` respecting armor / magic_resist / true-damage rules. Clamps resist 0..1. Missing `target.data` → unmitigated pass-through.
- `enemies/base_enemy.gd`: add `take_damage(amount, type, source)` → routes through DamageCalculator, `ceil()`s to int, triggers `_die()` at 0 hp. `_die()` emits `enemy_died(self, gold_worth)` and despawns.
- `main/Main.gd`: connects `enemy_died`; test harness now applies 999 TRUE damage 3 seconds after spawn so the enemy dies mid-path instead of reaching the end.
- Works: enemy spawns, walks partway, test damage kills it, prints `+5 gold`.
- Broke: none.
- Next: Phase 6 — one tower detecting, shooting, killing.
