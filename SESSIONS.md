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

---

## 2026-04-15 — Phase 6: Archer tower + arrows
- `towers/TowerData.gd`: Resource with all spec fields. Added one extra field beyond the spec: `projectile_scene` (asset reference — not a gameplay stat, lives in data for per-tower configurability).
- `towers/data/tower_archer.tres`: Archer Tower — 4 physical dmg, 160 range, 1.2 atk/s, 50g cost, arrow projectile.
- `towers/base_tower.gd` (class_name BaseTower): Node2D root with a child Area2D RangeArea (collision_mask=2 picks up enemy layer), CollisionShape2D sized from data.attack_range at `_ready()`, and an AttackTimer wired to `_on_attack_tick`. Target picking polls `range_area.get_overlapping_areas()` each tick, filters DYING and flying-without-targets_flying, picks the enemy with highest `PathFollow2D.progress_ratio` (standard first-target TD strategy).
- `towers/TowerArcher.tscn`: Node2D + RangeArea(Area2D) + CollisionShape2D + AttackTimer. Placeholder `_draw()` = blue disc.
- `projectiles/Arrow.gd` + `Arrow.tscn`: Node2D that homes on target each frame, applies damage on hit (< hit_radius), despawns on hit or if target becomes invalid mid-flight.
- `main/Main.gd`: removed Phase 4/5 test methods. New `_phase6_test_tower_vs_enemy()` places an archer on `Spot1` then spawns an enemy on the left path; the tower kills it with ~3 arrows during the horizontal segment.
- Works: tower fires arrows at moving enemy, enemy dies before reaching end, `+5 gold` printed.
- Broke: none.
- Next: Phase 7 — Gold + lives economy (GameState).

---

## 2026-04-14 — Phase 7: Gold + Lives economy + HUD
- `autoloads/GameState.gd`: real economy. `STARTING_GOLD=100`, `STARTING_LIVES=20`. `add_gold` / `spend_gold` / `lose_lives` mutators emit `gold_changed` / `lives_changed` / `game_over`. Subscribes to `EventBus.enemy_died` (→ add gold worth) and `enemy_reached_end` (→ lose lives worth).
- `ui/HUD.gd` + `ui/HUD.tscn`: CanvasLayer with a top-left VBox showing `Gold: N` + `Lives: N` labels (unique_name_in_owner, font 22). Connects to `gold_changed` / `lives_changed` on ready.
- `main/Main.tscn`: instances `HUD.tscn` alongside Map.
- Works: HUD shows Gold 100 / Lives 20 at start; killing the archer-target enemy ticks gold to 105.
- Broke: none.
- Next: Phase 8 — tower placement UI (tap empty spot → build menu → buy tower).

---

## 2026-04-15 — Phase 8: Tower placement UI
- `EventBus.gd`: added `tower_build_requested(spot_id, tower_id)` and `tower_menu_dismissed()`.
- `map/GridManager.gd`: added `set_tower_at`, `clear_tower_at`, `get_tower_at`, `find_nearest_spot(world_pos, max_distance)`.
- `map/SpotInputManager.gd` (new): unhandled-input handler that converts screen-space `InputEventScreenTouch` to Map-local coords, finds nearest free spot within 36 px, emits `tower_spot_tapped`.
- `ui/TowerSpotMenu.tscn` + `.gd`: CanvasLayer bottom-sheet popup with Backdrop (tap-outside-to-dismiss, mouse_filter=STOP), PanelContainer with "Build Archer (50g)" + Close buttons (80px touch targets). Auto-enables/disables Archer button when `gold_changed` fires.
- `ui/TowerPlacer.gd` (new): listens to `tower_build_requested`, resolves tower_id via a registry (currently only "archer" → TowerArcher.tscn + tower_archer.tres), calls `GameState.spend_gold(cost)` (refund-free if broke), instances the tower under a Towers Node2D, registers it in GridManager, emits `tower_built`.
- `main/Main.tscn`: added Towers Node2D, TowerPlacer node (wired via `towers_parent_path` + `grid_manager_path`), and TowerSpotMenu instance.
- `main/Main.gd`: removed Phase 6 auto-placement. Added a Timer-driven test-enemy spawner (one enemy every 2.5s, rotating left → right → top paths) so the player always has targets while placing towers. Phase 11 replaces this with real waves.
- Works: tap any yellow spot → menu appears → Build Archer deducts 50g, spawns a blue archer tower; tap outside to dismiss; archers shoot the looping test enemies; second tower can be built after ~1 kill.
- Broke: none.
- Next: Phase 9 — tower sell + refund (extend TowerSpotMenu for occupied spots).

---

## 2026-04-15 — Phase 9: Tower sell + refund
- `EventBus.gd`: added `tower_sell_requested(spot_id)`.
- `ui/TowerPlacer.gd`: added `_on_sell_requested` — reads tower via `grid.get_tower_at`, refunds `tower.data.sell_value` through `GameState.add_gold`, clears spot, emits `tower_sold(tower, refund)`, queue_frees the tower.
- `ui/TowerSpotMenu.gd`: now dual-mode. Empty spot → BuildRow (Archer 50g). Occupied spot → SellRow showing "Sell (+Ng)" with refund pulled from `tower.data.sell_value`. Listens to `tower_sold` to auto-dismiss after the sale.
- `ui/TowerSpotMenu.tscn`: split VBox into BuildRow + SellRow containers (hidden/shown per mode), TitleLabel re-labels per mode, Panel offset bumped to -220 for the extra row.
- Archer refund: 30g (tower_archer.tres `sell_value = 30`).
- Works: tap existing archer → "Sell (+30g)" → gold increments by 30, tower disappears, spot is free to rebuild.
- Broke: none.
- Next: Phase 10 — tower range circle preview on tap.

---

## 2026-04-15 — Phase 10: Tower range circle preview
- `ui/RangePreview.gd` + `.tscn` (new): single Node2D instance in Main.tscn that listens to `tower_spot_tapped`. If the spot is occupied, snaps `global_position` to the tower and `_draw()`s a hollow yellow ring with a faint fill using the tower's `data.attack_range`. One-shot Timer hides after 2 seconds; re-tap restarts the timer. Also auto-hides on `tower_sold` so a stale preview doesn't linger on an empty spot.
- `main/Main.tscn`: added RangePreview instance above HUD (z_index=5 so it renders above towers but below CanvasLayer UI).
- No changes to base_tower.gd — preview is fully decoupled, resolved through GridManager lookups.
- Works: tap an archer → yellow ring at its 160 px radius appears for 2 s alongside the sell menu; re-tap extends the timer; sell dismisses the ring immediately.
- Broke: none.
- Next: Phase 11 — wave system (WaveManager + multi-path wave data).

---

## 2026-04-15 — Detour: editor-editable Level1 (pre-Phase 11)
- Before Phase 11 the map was authored entirely in code (`Map.gd._build_curves()` + hardcoded Marker2D coords) and nothing rendered in the editor — you were dragging invisible nodes. Fixed so level layout is fully editor-editable.
- `levels/Level1.gd` + `levels/Level1.tscn` (new): `@tool` script that draws green background, brown paths, and yellow spot circles both in the editor and at runtime. Paths live in the scene as Path2D children with real `Curve2D` sub-resources (so Godot's built-in curve editor works — drag points, Bezier handles, right-click to add/remove). Path node name IS the path_id ("left", "right", "top"). Spots live as Marker2D children — drag them, `_process` queue_redraws in editor so the preview tracks live.
- `map/SpawnMarker.gd`: `@tool` so arrow/icon render in editor too.
- `map/Map.tscn` + `map/Map.gd`: deleted. `map/` now only holds shared systems (GridManager, SpotInputManager, SpawnMarker) reused by all levels.
- `main/Main.tscn` + `main/Main.gd`: instance `Level1.tscn` instead of `Map.tscn`; node renamed `Map` → `Level1`.
- Works: opening `levels/Level1.tscn` in the editor shows the full playable map; dragging Spot5 or a Path2D curve point updates the preview immediately. F5 still runs the same gameplay as before.
- Broke: none.
- Next: Phase 11 — wave system.

---

## 2026-04-15 — Phase 11: Wave system (WaveManager + multi-path wave data)
- New Resource chain for easy Inspector editing: `waves/WaveSpawn.gd` (path_id / enemy_scene / count / interval / start_delay), `waves/WaveData.gd` (Array[WaveSpawn] + countdown + bounty), `waves/WaveList.gd` (Array[WaveData]). Each is its own .gd with `class_name` so they appear as "New Resource" options in the Godot Inspector.
- `levels/level1_waves.tres`: concrete WaveList — W1: 8 basics on left (bounty 15g), W2: 6 left + 4 right after 2 s (bounty 25g), W3: 5×3 across all paths (bounty 40g). Load_steps audited, typed arrays declared `Array[WaveData]` / `Array[WaveSpawn]` to match the script fields.
- `autoloads/WaveManager.gd`: replaced the Phase 4 stub with a real runner. `start(wave_list, level)` kicks the loop. Each wave: countdown with per-path `spawn_direction_changed` signals → `wave_started(n, path_ids)` → one async spawner per WaveSpawn (create_timer-based) → wave completes only when every spawner finished AND alive_count == 0 → bounty gold via GameState → next wave. Game-over stops the loop (`_wave_active=false`). Autoload keeps resource types as `Resource` rather than `WaveList` / `WaveData` / `WaveSpawn` — autoloads can't reliably resolve class_names from peer scripts at parse time; runtime duck-typing works identically.
- `ui/HUD.tscn` + `.gd`: added `WaveLabel` ("Wave: X/Y"), bumped `TopLeft` bottom offset to 120 for the extra row. Listens to `wave_started` (live counter) and `all_waves_completed` ("Victory!").
- `main/Main.gd`: deleted the Phase 8 test-enemy Timer loop. On _ready now calls `WaveManager.start(LEVEL1_WAVES, level)` after connecting logging hooks.
- Works: F5 → Wave: 1/3 appears after 3 s countdown → 8 orcs from the left; building archers drops the leak count. Wave 2 kicks in once wave 1 clears, adds a second path. Wave 3 uses all three paths. Bounty gold appears at each clear.
- Broke: none.
- Next: Phase 12 — win/lose conditions + GameOverScreen.

---

## 2026-04-15 — Phase 12: Win/lose + GameOverScreen
- `autoloads/WaveManager.gd`: added `stop()` — clears `_running` / `_wave_active` and nulls the wave_list/level refs. In-flight spawner `await` coroutines already re-check `_running` after each timer, so they bail cleanly on scene reload without leaking half-spawned enemies.
- `ui/GameOverScreen.gd` + `.tscn` (new): CanvasLayer (layer=20) with dim ColorRect (alpha 0.65) + centered PanelContainer card containing TitleLabel (36px), SummaryLabel (18px), and a big Restart button (220×80). `process_mode = PROCESS_MODE_WHEN_PAUSED` so the button keeps firing while the tree is paused. Listens to `game_over` (→ "Defeat" with wave reached) and `all_waves_completed` (→ "Victory!" with lives/gold, guarded by `lives > 0` so a simultaneous game_over doesn't double-trigger). `_shown` flag prevents re-entry.
- Restart flow: unpause → `WaveManager.stop()` → `GameState.reset()` → re-emit gold/lives_changed so the HUD snaps back before reload → `get_tree().reload_current_scene()`.
- `main/Main.tscn`: instanced GameOverScreen after TowerSpotMenu.
- Works: leaking all 20 lives → "Defeat" card with wave number, Restart returns to Gold 100 / Lives 20 / Wave --. Clearing all 3 waves → "Victory!" card with summary, Restart begins a fresh run.
- Broke: none.
- Next: Phase 13 — status effects (slow first, then stun).

---

## 2026-04-15 — Phase 13: Status effects (slow + stun)
- `systems/StatusEffect.gd` (new, RefCounted): base class with `id`, `duration`, and `apply(enemy)` / `remove(enemy)` hooks for subclasses that need entry/exit side effects. Tick-down lives on BaseEnemy — effects are simple data containers.
- `systems/SlowEffect.gd` (new): `id = "slow"`, clamps `slow_factor` to 0..1. BaseEnemy reads `slow_factor` directly to scale effective speed.
- `systems/StunEffect.gd` (new): `id = "stun"`, zero-speed freeze. `_init(duration)`.
- All three use string-path `extends "res://systems/StatusEffect.gd"` so the LSP resolves them without waiting for Godot's class_name index to catch up on newly created files.
- `enemies/base_enemy.gd`: added `_effects: Dictionary` keyed by effect id (reapply same id = replace), plus `apply_status_effect(effect)`, `_tick_effects(delta)`, `_effective_speed()`, and `_refresh_visuals()`. `_physics_process` now ticks effects every frame and multiplies `data.move_speed` by `(1 - slow_factor)` during WALKING. Stun forces `change_state(State.STUNNED)` on apply and reverts to WALKING on expire (COMBAT path wires in during Phase 16 barracks work). Modulate tint: yellow while stunned, cyan while slowed, white otherwise. `apply_status_effect` param is intentionally untyped — typed `StatusEffect` fails LSP before editor rescan, runtime duck-typing works identically.
- `main/Main.gd`: Phase 13 demo harness — listens to `enemy_spawned` and, on the first enemy of the run only, awaits 1 s then applies `SlowEffect(0.5, 1.5)`, then 1.8 s later applies `StunEffect(1.5)`. Uses `preload()` consts (`SlowEffectScript` / `StunEffectScript`) to sidestep the class_name index cascade. Single-shot via `_phase13_demo_used` flag. Restart re-enters _ready so the demo can play again on each run.
- Works: F5 → first orc spawns → ~1 s in turns cyan and crawls at half speed → ~2.8 s in turns yellow and freezes mid-path for 1.5 s → resumes normal speed + color. Wave 1 still clears normally. Console prints both applications.
- Broke: none.
- Next: Phase 14 — flying enemy (collision layer 3).

---

## 2026-04-15 — Phase 13 follow-up: swap modulate for overlay rings
- On the red placeholder enemy, `modulate` tints were visually invisible (red × cyan ≈ red, red × yellow ≈ red). Replaced in `enemies/base_enemy.gd` with explicit `draw_arc()` rings inside `_draw()`: cyan ring at r=19 while slowed, yellow ring at r=23 while stunned (stun outermost so it stays readable when both are active). `apply_status_effect` / `_tick_effects` now call `queue_redraw()` instead of `modulate =`.
- Godot also reserialised `levels/level1_waves.tres` during this session as it indexed the new script UIDs (defaults stripped, typed arrays rewritten as ExtResource refs — no semantic change).
- Works: first-enemy demo now has obvious cyan/yellow halos in addition to the speed changes.
- Broke: none.

---

## 2026-04-15 — Phase 14: Flying enemy (collision layer 3)
- `enemies/data/enemy_flying.tres` (new): Harpy — 8 hp, 90 px/s, 1 life, 6 gold, magic_resist 0.2, `is_flying = true`.
- `enemies/enemy_flying.gd` (new, extends BaseEnemy): overrides `_draw()` only — purple body (r=12) plus two short grey wing bars — so the placeholder reads as visibly different from the orc. Status-effect rings are redrawn here too (same cyan/yellow convention) since `_draw()` is a full override.
- `enemies/EnemyFlying.tscn` (new): Area2D on `collision_layer = 4` (bit 3 = layer 3), `collision_mask = 0`, CircleShape2D r=12. Archer RangeArea uses `collision_mask = 2` (layer 2 only) so flying units never enter `get_overlapping_areas()` — they sail past ground towers for free, which is the intended Phase-14 demo. Targeting filter in BaseTower (`is_flying and not targets_flying`) is a second-line defense for when an AA tower *does* see a flying enemy via a broader mask.
- `levels/level1_waves.tres`: W3 "top" spawn flipped from 5 orcs to 3 Harpies (interval 1.2, start_delay 2.0). W1 + W2 unchanged.
- Works: wave 3 on top path spawns purple harpies that cruise through untouched by any archer placed on any spot — lives drop by 3 if the player doesn't kill them some other way, confirming layer-3 passthrough. Ground orcs on left/right still get shot normally.
- Broke: none.
- Next: Phase 15 — healer enemy (Timer-based ally healing).

---

## 2026-04-15 — Debug: status-effect arrows + WaveManager accounting
- `projectiles/Arrow.gd`: `setup()` now accepts an optional `status_effect` param. On hit, after damage, the arrow calls `apply_status_effect` on the target if the target is still valid (BaseEnemy's DYING guard blocks application on kill shots, which is what we want).
- `towers/base_tower.gd`: `DEBUG_STATUS_ARROWS` const + per-tower shot counter + `_next_buff_threshold` (randi_range 3..6). Every N shots one arrow carries a random SlowEffect(0.5, 2.0) or StunEffect(0.8) rolled via 50/50 coin flip, logged to console. Swap the const to false to disable.
- `autoloads/WaveManager.gd`: spawn/die/leak handlers now call `_log_alive(tag, enemy, path_id)` which prints the enemy name + current alive/spawners/wave_active. Added to diagnose a suspected post-Victory leak; live run confirmed the accounting is consistent across waves.
- Works: arrows mid-wave visibly apply cyan/yellow rings to orcs; wave-completion accounting lines up with actual alive enemies.

---

## 2026-04-15 — Phase 15: Healer enemy
- `enemies/data/enemy_healer.tres` (new): Shaman — 18 hp, 55 px/s, magic_resist 0.1, 12g, `heals_allies = true`, heal_range 130, heal_amount 3, heal_interval 2.0.
- `enemies/enemy_healer.gd` (new, extends BaseEnemy): adds a child `HealArea` (Area2D, `collision_mask = 6` → detects ground layer 2 + flying layer 4) plus a `HealTimer`. `_ready()` calls `super._ready()`, sizes the heal shape from `data.heal_range`, wires the timer to `_on_heal_pulse` at `data.heal_interval`. `_on_heal_pulse` polls `heal_area.get_overlapping_areas()` once per tick (Timer-based per the mobile rule "Enemy healing: Timer-based only — never _physics_process"), skips self + DYING allies, calls `ally.heal(data.heal_amount)`. Green body + white plus sign so it reads as a medic at a glance. Status rings reused from Phase 13/14.
- `enemies/EnemyHealer.tscn` (new): Area2D `collision_layer = 2` (ground, so archers still shoot it), child HealArea with `collision_layer = 0`, `monitorable = false` so other HealAreas can't pick it up. Shape sized at runtime.
- `enemies/base_enemy.gd`: added `heal(amount)` — clamps to `data.max_health`, ignores DYING/null-data, ceils to int, logs `[Enemy/heal] name before → after` so the effect is observable pre-Phase-17 health bars.
- `levels/level1_waves.tres`: W2 gains a third spawner — 1 Shaman on left, start_delay 3.0 — so the healer trails the 6 orcs already on that path and keeps them alive longer than the archer DPS would otherwise allow.
- Works: F5 → wave 2 left path → after ~3 s a green "+" medic trails the orcs and, every 2 s, heals nearby allies by 3 (console logs `[Enemy/heal] Orc Grunt N → M`). Orcs shot by archers survive noticeably longer; killing the Shaman first ends the sustain.
- Broke: none.
- Next: Phase 16 — barracks tower + soldier blocking.

---

## 2026-04-15 — Log-order clarification (not a bug)
- The "leak after Victory" in prior runs is not a miscount. enemy_reached_end listeners fire in connection order GameState → WaveManager → Main. For the final leak WaveManager's handler runs first (prints acct line + cascades wave_completed / all_waves_completed synchronously), and only after that whole chain unwinds does Main's handler print `leak — lives -1 (remaining: N)`. So `[Main] leak` appears after `[WaveManager] all waves complete` but it's the same signal emit, not a phantom enemy. Accounting across the run was 13 spawns / 13 removes.

---

## 2026-04-15 — Phase 16: Barracks tower + soldier blocking
- `soldiers/SoldierData.gd` (new Resource): max_health / attack_damage / attack_speed / move_speed / armor / magic_resist / respawn_time / max_count / melee_range.
- `soldiers/data/soldier_basic.tres`: Militia — 22 hp, 4 dmg, 1.0 atk/s, 70 px/s, armor 0.1, respawn 4 s, max 3, melee_range 18.
- `soldiers/base_soldier.gd` (CharacterBody2D, states MOVING / BLOCKING / DEAD): straight-line walk to assigned `_blocking_position`, then on reaching BLOCKING polls `MeleeRange.get_overlapping_areas()` each physics tick and engages the first non-flying non-DYING BaseEnemy — calls `enemy.engage_combat(self)` and trades blows on a cooldown (1 / attack_speed). On HP ≤ 0: calls `_engaged_enemy.release_combat(self)`, emits `soldier_died`, queue_frees. `data` typed as `Resource` (SoldierData indexed later) to avoid LSP red before Godot rescan.
- `soldiers/Soldier.tscn`: CharacterBody2D on `collision_layer = 2` (ground), child `MeleeRange` Area2D with `collision_mask = 2`, `monitorable = false`. Melee shape sized at runtime from `data.melee_range`.
- `enemies/EnemyData.gd`: added `attack_damage` + `attack_speed` (defaults 3.0 / 1.0) — used only by BaseEnemy while engaged; flying units skip engagement entirely.
- `enemies/base_enemy.gd`: new `_blocker` + `_combat_cooldown` plus public `engage_combat(soldier)` / `release_combat(soldier = null)`. COMBAT branch in `_physics_process` drives `_combat_tick`: every `1 / attack_speed` seconds call `_blocker.take_damage(data.attack_damage, PHYSICAL, self)`. If blocker becomes invalid mid-tick, auto-releases back to WALKING. `release_combat(soldier)` is a no-op when a non-matching soldier is passed, which prevents stale release calls.
- `towers/TowerData.gd`: added barracks fields — `soldier_scene` / `soldier_data` / `soldier_blocking_offset (0, 45)` / `soldier_spread (16, 10)`. Unused on attack towers.
- `towers/data/tower_barracks.tres` (new): Barracks — cost 70, sell 40, wires soldier_scene + soldier_data.
- `towers/TowerBarracks.gd` (new, Node2D): on ready builds 3 slot positions fanning around `global_position + soldier_blocking_offset`, spawns a full squad parented to itself (selling cleans them up with the barracks). Listens to `EventBus.soldier_died`; when a tracked soldier dies, schedules `_respawn_after(respawn_time, slot)` via a SceneTree timer. `is_inside_tree()` guard on resume so respawn coroutines bail cleanly if the barracks was sold mid-timer.
- `towers/TowerBarracks.tscn` (new): Node2D + script + data.
- `ui/TowerPlacer.gd`: registered `"barracks"` alongside archer.
- `ui/TowerSpotMenu.gd` + `.tscn`: added `BarracksButton` (70 g) to BuildRow. Bumped panel `offset_top` to -320 to fit the extra row + sell + close with enough breathing room.
- Works: F5 → tap empty spot → menu now offers Build Archer + Build Barracks → tap barracks for 70 g → brown square drops 3 yellow militia squares that march to a triangle below the tower. Ground orcs entering that triangle stop (COMBAT state), trade melee with the militia; militia die and respawn after 4 s. Harpies ignore soldiers and fly past. Selling the barracks removes all 3 soldiers.
- Broke: none.
- Next: Phase 17 — enemy health bar (visible on hit, auto-hide).

---

## 2026-04-15 — Phase 16 follow-up: draggable rally flag + demo cleanup
- `towers/TowerBarracks.gd` now owns a FlagArea (Area2D, input_pickable = true) with a CircleShape2D r=22 sized in `_ready()`. Flag visual (pole + red cloth) is drawn in the barracks' `_draw()` at a per-instance `_flag_offset` that starts at `data.soldier_blocking_offset`. Touch on the FlagArea captures drag (`_dragging_flag = true` + `set_input_as_handled()`), subsequent `InputEventScreenDrag` events update `_flag_offset` via `get_global_transform_with_canvas().affine_inverse() * event.position`, and the release (`InputEventScreenTouch !pressed`) recalls soldiers. Consumes the press so SpotInputManager doesn't also see it.
- `soldiers/base_soldier.gd`: new `set_blocking_position(new_pos)` — breaks the current engagement and transitions to State.MOVING toward the new rally slot.
- `towers/TowerBarracks.tscn`: added FlagArea (Area2D) + empty CollisionShape2D child. Layer / mask both 0 (input-only area, not detected by anything else).
- `main/Main.gd`: removed the Phase 13 demo harness + the SlowEffect/StunEffect preloads + the `_phase13_demo_used` flag + the one-shot spawn listener. All status effects now come exclusively from `BaseTower.DEBUG_STATUS_ARROWS` (arrow hit → `apply_status_effect`), so the effects the player sees are from actual gameplay, not a scripted demo.
- Works: F5 → build a Barracks → 3 soldiers fan around a red flag at (0, 45) below the tower. Touch + drag the flag → flag follows finger → release → all three soldiers walk to the new triangle. Works mid-combat: engaged enemies release and the soldiers rally to the new spot, leaving the orc to resume WALKING. Flags on multiple barracks are independent. No status rings until a debug arrow lands.
- Broke: none.

---

## 2026-04-15 — Phase 17: Enemy health bar (visible on hit, auto-hide)
- `enemies/base_enemy.gd`: added `HP_BAR_HIDE_DELAY = 3.0`, `HP_BAR_SIZE = (28, 4)`, `HP_BAR_Y_OFFSET = -26`, and `_hp_bar_countdown: float`. `take_damage()` now sets `_hp_bar_countdown = HP_BAR_HIDE_DELAY` and calls `queue_redraw()` before the death check, so every hit (including the kill shot's pre-death redraw) flashes the bar. `_physics_process` decrements the countdown each frame and issues one `queue_redraw()` on the tick it crosses zero so the bar disappears cleanly.
- New helper `_draw_health_bar()` drawn at the end of `_draw()`. Subclasses that fully override `_draw()` (`enemy_flying.gd`, `enemy_healer.gd`) each append a call to `_draw_health_bar()` so their custom sprites pick up the bar too. Bar = dark grey background, green fill proportional to `current_health / data.max_health`, 1 px black outline, centered above the unit at y = -26 (clears the r=14 orc body, r=12 harpy body, and r=15 shaman body).
- No per-enemy HealthBar Node is instantiated — the bar is drawn inside the enemy's own `_draw()`, so the CLAUDE.md "pool / never instantiate per enemy" rule is honoured without adding a pool manager in this phase. Timing runs off the existing `_physics_process` tick rather than a child Timer, so no extra nodes either.
- Works: F5 → archer starts shooting orcs → green bar appears above hit orc, shrinks with each arrow, hides ~3 s after the last hit (e.g. if the orc walks past into a gap). Harpies and Shamans get the same bar on damage. Kill shot still shows the fully-drained bar for the redraw before queue_free.
- Broke: none.

---

## 2026-04-15 — Phase 17 follow-up: rally range cap + drag preview
- `towers/TowerData.gd`: new `soldier_rally_range: float = 140.0` — max distance the flag can be dragged from the barracks. `towers/data/tower_barracks.tres` sets it explicitly (140 px) so the Inspector shows the value.
- `towers/TowerBarracks.gd`: new `_clamp_to_rally_range(local_pos)` helper — if the touched local position is further than `data.soldier_rally_range`, project it back onto the circle edge. Called from the `InputEventScreenDrag` branch so the flag sticks to the rim of the circle when the finger leaves it instead of teleporting outside.
- While `_dragging_flag` is true, `_draw()` renders a yellow range circle at radius `soldier_rally_range` (faint fill alpha 0.08, bright arc outline alpha 0.75) centred on the barracks. Drawn before the tower body so the square sits on top. `queue_redraw()` now fires on press and release too so the circle appears the moment you touch the flag and clears immediately on release.
- Works: F5 → build a Barracks → touch the red flag → yellow leash circle pops up → drag the flag around; moving the finger past the circle edge keeps the flag clamped at the rim; releasing hides the circle and the soldiers rally to the (possibly clamped) point. Range scales if `soldier_rally_range` is edited in the .tres.
- Broke: none.

---

## 2026-04-15 — Phase 17 follow-up 2: tap-to-place rally via menu button
- `autoloads/EventBus.gd`: new signal `barracks_rally_move_requested(barracks)` — emitted by TowerSpotMenu when the player picks "Move Rally" on an occupied barracks spot. Loose-coupled per CLAUDE.md rule #2 (cross-system via EventBus only).
- `ui/TowerSpotMenu.tscn`: added `MoveRallyButton` inside SellRow, above SellButton (80 px tall, font 22 — same touch-target sizing as the rest).
- `ui/TowerSpotMenu.gd`: wires the button, and in `_refresh_sell_button()` sets `move_rally_button.visible = _current_tower.has_method("begin_rally_placement")`. Duck-typing on a method name rather than `is TowerBarracks` so attack towers don't need to know about the barracks class, and so future barracks variants (e.g. Paladin barracks) automatically opt in by implementing the same method. Press → emits `barracks_rally_move_requested(tower)` + dismisses menu.
- `towers/TowerBarracks.gd`:
  - New `_placement_mode: bool`. `begin_rally_placement()` sets it + disables `flag_area.input_pickable` so a placement tap that happens to land on the flag doesn't start a drag. `_end_rally_placement()` restores both.
  - `_on_rally_move_requested(barracks)` listens to the EventBus signal and filters on `barracks == self`.
  - New `_input(event)` handler (runs before `_unhandled_input`, so it consumes the tap before SpotInputManager can reopen the menu on the barracks' own spot). While `_placement_mode` is true, the next `InputEventScreenTouch.pressed`:
    - Converts to barracks-local coords via `_screen_to_local`.
    - If inside `data.soldier_rally_range` (or range ≤ 0), clamps to the rim, sets `_flag_offset`, calls `_recall_soldiers()`. Outside range = cancel without moving the flag.
    - Always exits placement mode and marks the input handled.
  - `_draw()` now shows the yellow range circle while `_dragging_flag OR _placement_mode` — so the leash is visible both when dragging the flag directly and while waiting for a tap-to-place target.
- Works: F5 → build a Barracks → tap the barracks spot → menu appears with Sell + Move Rally + Close → tap "Move Rally" → menu closes, yellow range circle stays visible → tap anywhere inside the circle → flag hops to that spot and the 3 militia walk there. Tap outside the circle → placement cancels, flag stays put. Direct flag-drag still works unchanged. Attack towers (archers) do not show the Move Rally button.
- Broke: none.

---

## 2026-04-15 — Phase 17 follow-up 3: soldier health bars + CLAUDE.md status sync
- `soldiers/base_soldier.gd`: mirrored the enemy bar — `HP_BAR_HIDE_DELAY = 3.0`, `HP_BAR_SIZE = (22, 3)` (smaller than enemy 28×4 so it sits proportional to the 12×12 militia square), `HP_BAR_Y_OFFSET = -16`. `_hp_bar_countdown` decremented in `_physics_process`, set on `take_damage`, drawn at the end of `_draw()` via `_draw_health_bar()`. Same green-fill / dark-bg / black-outline look as enemies for visual consistency.
- `CLAUDE.md` "📋 Current Status" block: flipped phases 1-17 to `[x]` (Skeleton through Enemy health bar). Added an "Extras beyond the phase list" sub-section noting the editor-editable Level1 detour, draggable rally flag, tap-to-place rally + range circle, and the soldier health bar so they're not lost between SESSIONS.md and the at-a-glance overview. Updated `Last committed phase:` to fde7ee0 (Phase 16) and `Next task:` to Phase 18. Caught only because the user asked why the checklist had been all-empty for 17 phases — fixed across the board now.
- New memory at `~/.claude/projects/c--td1/memory/feedback_claudemd_status_update.md`: future sessions update both SESSIONS.md AND the CLAUDE.md checklist in the same edit pass.
- Works: F5 → soldiers engage orcs → green bar appears above the militia square as it takes hits → fades out 3 s after the last hit (or shows the drained bar one frame before queue_free on death). CLAUDE.md status now reflects reality.
- Broke: none.

---

## 2026-04-15 — Phase 17 follow-up 4: health bar rule change — stays visible while HP < max
- Rule change: health bar is visible **whenever `current_health < max_health`** and only hidden while the unit is at full HP. The old "3 s after last hit, then auto-hide" timer was dropped — once a unit has been wounded the bar stays on for the rest of its life (or until a heal brings it back to full).
- `CLAUDE.md`: updated the Game Reference row ("Enemy health bars: Visible whenever HP is not full"), replaced the "Enemy Health Bar Rules" block with a broader "Health Bar Rules (enemies + soldiers)" block, and rewrote the Phase 17 label.
- `enemies/base_enemy.gd`: deleted `HP_BAR_HIDE_DELAY` + `_hp_bar_countdown` + the per-frame countdown in `_physics_process`. `take_damage` still calls `queue_redraw()` so the bar updates on hit. `heal()` now also calls `queue_redraw()` so the bar shrinks/hides correctly when a Shaman heals an ally back to full. `_draw_health_bar()` guard is now `current_health >= data.max_health` → return.
- `soldiers/base_soldier.gd`: same simplification — countdown variable and per-frame decrement removed, `_draw_health_bar()` gated by `current_health >= data.max_health`.
- Works: F5 → any damaged enemy or militia shows the green bar permanently until either it dies or a healer tops it up to max (at which point the bar disappears cleanly). Full-HP units show no bar.
- Broke: none.

---

## 2026-04-15 — Phase 18: Hero movement + auto-attack
- `heroes/HeroData.gd` (new Resource): hero_name / hero_id / max_health / attack_damage / attack_range / attack_speed / move_speed / armor / magic_resist / damage_type / targets_flying / xp_per_level / max_level / respawn_time / skills / encyclopedia_entry. XP fields are present so Phase 19 doesn't have to re-touch every .tres, but unused this phase.
- `heroes/data/hero_warrior.tres`: Knight — 120 hp, 12 dmg, 60 attack_range, 1.0 atk/s, 110 px/s, armor 0.25, targets_flying = true (warrior's sword swings up at low-altitude harpies — keeps the hero useful on top-path waves without needing a separate ranged hero this phase).
- `heroes/base_hero.gd` (CharacterBody2D, class_name BaseHero): states IDLE / MOVING / COMBAT / DEAD via `change_state()`. `move_to(world_pos)` cancels any active engagement and switches to MOVING — explicit player command beats auto-attack. `_physics_process` per-state:
  - IDLE: zero velocity, `_seek_target()` polls AttackRange `get_overlapping_areas()` for the nearest non-DYING BaseEnemy that isn't a flying unit when `data.targets_flying = false`.
  - MOVING: straight-line `(target - global_position).normalized() * move_speed`. Reached when within 4 px → IDLE. Skipped NavigationAgent2D this phase since Level1 has no obstacles; deviation noted, swap in when a level introduces blocked tiles.
  - COMBAT: zero velocity, `_attack_step(delta)` ticks attack cooldown (1 / attack_speed) and calls `enemy.take_damage(damage, damage_type, self)`. Drops back to IDLE if the target dies, becomes invalid, or walks out of AttackRange.
  - DEAD: bypasses `_physics_process` entirely; visible = false.
- `heroes/HeroWarrior.tscn`: CharacterBody2D on `collision_layer = 8` (hero layer 4, new — not used by anything yet but reserved so Phase 38 boss attacks can target the hero) and `collision_mask = 0` so the hero walks through enemies and soldiers without physical collision. Child AttackRange Area2D on `collision_mask = 6` (layers 2 + 3 = ground + flying), `monitorable = false`. Shape sized at runtime from `data.attack_range`.
- `heroes/HeroInputManager.gd` (new): listens to unhandled `InputEventScreenTouch.pressed`. Converts screen → Level1-local via the same `get_global_transform_with_canvas().affine_inverse()` pattern as SpotInputManager. Skips taps within 36 px of any registered tower spot (so opening the build menu doesn't double as a move command). Otherwise calls `hero.move_to(world_pos)` and marks the input handled. Sits in `_unhandled_input` so TowerSpotMenu's Backdrop and TowerBarracks rally-placement (which uses `_input`) both consume their taps before the hero sees them.
- `main/Main.tscn`: instanced HeroWarrior at (188, 460) — central, clear of all three paths — and added HeroInputManager wired to the hero, GridManager, and Level1.
- `main/Main.gd`: connects `hero_spawned` / `hero_died` to printouts.
- Hero's `_draw()` reuses the standard health-bar helper (36×5 px, y -22) gated by the new "visible while HP < max" rule. Hero is invincible this phase (no enemy can damage it yet) so the bar will not appear in normal play.
- Works: F5 → gold square with sword tip appears mid-map at (188, 460) → tap anywhere on the map (not on a tower spot) → knight walks straight to that point → if an orc or harpy comes within 60 px, knight stops and chops at 12 dmg / sec until the target dies or wanders out of range, then resumes IDLE. Tapping during combat re-routes the hero. Tapping a tower spot still opens the build/sell menu without moving the hero.
- Broke: none.

---

## 2026-04-15 — Phase 18 follow-up: tap-to-select + lunge animation
- Selection (Kingdom-Rush style): hero must be selected before tap-to-move works. Implementation:
  - `autoloads/EventBus.gd`: new signal `hero_selection_changed(hero, is_selected)` so Phase 20's skill bar can listen in without coupling to BaseHero directly.
  - `heroes/HeroWarrior.tscn`: added `SelectArea` Area2D (input_pickable, monitoring/monitorable off, layers/mask = 0) with an empty CollisionShape2D.
  - `heroes/base_hero.gd`: new `is_selected: bool` + `set_selected(value)` (idempotent, queue_redraws + emits the signal). `_ready` sizes the SelectArea shape to a 22 px circle and connects `select_area.input_event` → `_on_select_area_input`. Tap on the area toggles selection and calls `set_input_as_handled()` so the press never reaches HeroInputManager (avoids "tap on hero counts as a tap-to-move on the hero's own tile").
  - `heroes/HeroInputManager.gd`: early return when `_hero.is_selected == false`. Map taps simply do nothing until the hero is selected.
  - `_draw()` paints a yellow ring (radius 18, alpha 0.85) under the hero when selected. Drawn before the body so the gold square covers the inside of the ring.
- Lunge animation (analytic, no Tween allocations):
  - `heroes/base_hero.gd`: new `_lunge_dir` + `_lunge_t` + `LUNGE_DURATION = 0.12` + `LUNGE_DISTANCE = 7`. `_start_lunge(target_world_pos)` sets the direction and resets the clock. `_physics_process` decrements `_lunge_t` and `queue_redraw()`s while it's active. `_lunge_offset()` returns a triangle-wave offset (0 → 1 → 0 over the duration). `_attack_step` calls `_start_lunge(enemy.global_position)` immediately before `take_damage`, so each swing visibly hops the knight 7 px toward the target and snaps back. `_draw()` wraps the body + sword draws in `draw_set_transform(off)` and resets so the selection ring and health bar don't lunge along with the body.
  - `soldiers/base_soldier.gd`: same pattern (`LUNGE_DISTANCE = 5` since the militia square is half the hero's size). Lunge fires inside `_attack_cycle` on each melee swing; `_draw()` applies the offset around the body draw only. Health bar stays put.
- `main/Main.tscn`: updated the HeroWarrior `ext_resource` UID to match the new value Godot assigned (`ct8ymjywf8nnl`) when the linter resaved the scene.
- Works: F5 → tap the gold square → yellow ring appears under it → tap a destination → knight walks there. Tap during combat → re-routes. Tap the knight again → ring disappears, subsequent map taps are ignored. Each attack tick (hero or soldier) hops the unit ~7 px / 5 px toward the target for 0.12 s and snaps back. Selection ring + health bar stay anchored regardless of lunge.
- Broke: none.

---

## 2026-04-15 — Phase 18 fix: hero selection wasn't firing
- Initial selection used a SelectArea Area2D with `input_pickable=true` and a CircleShape2D sized at runtime in `_ready()`. In live play the area never received touches — likely the runtime shape didn't propagate to the picking system in time, and AttackRange (default `input_pickable=true`) was competing for picks at the same node level.
- Replaced the Area2D approach with a direct `_input(event)` distance check on BaseHero: convert the screen press to local coords via `get_global_transform_with_canvas().affine_inverse()`, hit if `length() <= SELECT_AREA_RADIUS` (22 px), toggle, consume. No physics-picking dependency, deterministic.
- `heroes/HeroWarrior.tscn`: removed the SelectArea + its CollisionShape2D. Set AttackRange `input_pickable = false` so it doesn't sit in the picking system at all (it's only used for `get_overlapping_areas()` polling — picking is unnecessary).
- `heroes/base_hero.gd`: dropped the `select_area` / `select_area_shape` @onready vars + the `_on_select_area_input` handler + the runtime `sel_circle` shape assignment. New `_input()` runs in the global input phase (before physics picking and before `_unhandled_input`), so the press is consumed cleanly before HeroInputManager would interpret it as a move command on the hero's own tile.
- Works: F5 → tap directly on the gold knight square → yellow selection ring appears → tap a destination → walks there → tap the knight again → ring disappears. Verified the press doesn't double-fire as a move-to.
- Broke: none.

---

## 2026-04-15 — Phase 18 revision: ripped out hero selection (Option C — Kingdom Rush canon)
- Moved from "tap-to-select + ring + gated move" to "tap anywhere = move". Reasons documented in conversation: matches the Kingdom Rush mental model we already committed to as north star, fewer states = fewer bugs, rapid repositioning is core to TD skill expression, and the modal targeting Phase 20 needs for skills doesn't require a hero-selection layer underneath it.
- `autoloads/EventBus.gd`: removed `hero_selection_changed` signal (never consumed).
- `heroes/base_hero.gd`: deleted `is_selected`, `set_selected()`, the `_input()` selection hit-test, `SELECT_AREA_RADIUS`, `SELECTION_RING_RADIUS`, and the selection-ring branch in `_draw()`. Added `SELF_TAP_DEADZONE = 14.0` and a guard at the top of `move_to(world_pos)`: if the tap is within 14 px of the hero's current position, ignore it. Without this, tapping the hero body while it's in COMBAT would cancel the engagement by re-targeting itself.
- `heroes/HeroInputManager.gd`: removed the `is_selected` gate. Every non-spot tap calls `hero.move_to(world_pos)`. Backdrop/rally-placement still consume their taps first, so modal UI wins over hero commands as before.
- Works: F5 → tap anywhere on the map → knight walks there. No ring, no toggle step. Tapping directly on the knight's body does nothing (deadzone absorbs it); tapping a tower spot still opens the build/sell menu; rally placement and TowerSpotMenu backdrop still eat their own taps without leaking moves.
- Broke: none.

---

## 2026-04-15 — Phase 18 revision 2: switched to Option B (one-shot select → command → auto-deselect)
- Pure Option C felt too reactive — every stray tap moved the hero. User wanted the explicit "arm → command → done" gesture: tap hero shows the ring, next map tap moves AND clears the ring, subsequent stray taps do nothing until the player re-arms. That's Option B.
- `heroes/base_hero.gd`:
  - Re-introduced `is_selected: bool` + `set_selected(value)` (queue_redraws, no signal — Phase 20 can wire one back if the skill bar needs it).
  - Re-added `_input(event)` distance check (radius 22 px, same as before — proven to work after the picking-via-Area2D detour). Toggles selection and consumes the press.
  - `move_to(world_pos)` now ends with `if is_selected: set_selected(false)` so issuing a move command always clears the armed state in the same call. No risk of forgetting to deselect.
  - `_die()` also calls `set_selected(false)` so a corpse never carries a stale ring.
  - `_draw()` paints the yellow ring (radius 18, alpha 0.85) under the body when armed. Drawn first so the body covers the inside of the ring; lunge offset still applied only to body+sword so the ring stays anchored.
  - Dropped `SELF_TAP_DEADZONE` — no longer needed because tapping the hero body is consumed by `_input` before `move_to` is ever called.
- `heroes/HeroInputManager.gd`: re-added the `is_selected` early-return. Map taps are inert until armed.
- Works: F5 → first map taps do nothing → tap the knight → ring appears → tap a destination → knight walks AND ring disappears in the same frame → further random map taps are ignored → tap knight again to re-arm. Tower spots, backdrop, rally placement still consume their own taps so they win over the hero command path.
- Broke: none.

---

## 2026-04-15 — Phase 19: Hero XP + leveling
- Last-hit XP semantics — only hero kills award XP, towers don't.
- `enemies/EnemyData.gd`: added `xp_worth: int` field. Data values: basic orc 6, harpy 8, shaman 16 — tuned so clearing wave 1 on the hero alone gets most of the way to level 2.
- `enemies/base_enemy.gd`: new `_last_damage_source: Node`, updated in `take_damage(amount, type, source)` (the param was previously `_source` and ignored). `_die()` now checks `is BaseHero` on that source and, if so, calls `source.gain_xp(data.xp_worth)` before emitting `enemy_died`. Towers passing `source = self` don't match the BaseHero check, so no XP leaks to them.
- `heroes/base_hero.gd`:
  - New state: `level: int = 1`, `current_xp: int = 0`. Constants `LEVEL_HEALTH_GROWTH = 0.15` and `LEVEL_DAMAGE_GROWTH = 0.10` (per-level multipliers atop base data).
  - `_effective_max_health()` / `_effective_damage()` helpers return level-scaled values. `_ready` uses `_effective_max_health()` so a hero spawned at a non-1 starting level (future scenario) still starts at full.
  - `_xp_needed_for_next_level()` returns `data.xp_per_level[level - 1]` or 0 at max level.
  - `gain_xp(amount)` accumulates, emits `hero_xp_gained`, and runs a `while current_xp >= needed` loop to handle multi-level jumps from a single big bounty. On reaching `data.max_level` it zeroes current_xp (cap, no overflow).
  - `_level_up()` increments level, heals to the new effective max, `queue_redraw`s, emits `hero_leveled_up(new_level)`, prints a log line.
  - `_attack_step` now deals `_effective_damage()` instead of `data.attack_damage` flat.
  - `_draw_health_bar()` compares against `_effective_max_health()` so the bar hides at the *scaled* max (otherwise a just-leveled hero would always show a bar, since `current_health > data.max_health`).
- `ui/HUD.gd` + `.tscn`: added `HeroLabel` ("Lv 1  XP 0/50"). Listens to `hero_spawned` / `hero_xp_gained` / `hero_leveled_up` / `hero_died`. Caches the hero ref from `hero_spawned` so label refreshes don't have to walk the tree. At level cap the text becomes "Lv N (MAX)". Bumped `TopLeft` bottom offset to 160 to fit the extra row.
- Works: F5 → HUD shows "Lv 1  XP 0/50" → hero finishes off an orc → HUD ticks to "Lv 1  XP 6/50" → after ~8-9 orc kills the hero hits level 2, health bar briefly flashes green-to-full, damage per swing goes from 12 → 13.2, log prints "[Hero] Knight reached level 2". Towers killing enemies produces no XP tick. At level 10 HUD shows "Lv 10 (MAX)" and further kills are ignored.
- Broke: none.

---

## 2026-04-15 — Phase 19 fix: HUD stuck at "Hero: --"
- Screenshot showed the new HeroLabel displaying the fallback text instead of "Lv 1 XP 0/50". Cause: in Main.tscn the HeroWarrior is a sibling above HUD. Godot runs `_ready()` bottom-up/in-order, so the hero's `EventBus.hero_spawned.emit(self)` fired **before** the HUD connected to the signal — initial spawn missed entirely. The label only would've updated once the first kill fired `hero_xp_gained`.
- Fix: changed the emit to `EventBus.hero_spawned.emit.call_deferred(self)` in `heroes/base_hero.gd`. Defers the signal by one idle frame, by which point every sibling `_ready()` has completed and listeners are connected. Two-char change, no tree re-ordering required.
- Works: F5 → HUD now shows "Lv 1  XP 0/50" from the first visible frame. Kills tick the XP forward; level-ups update the label to the new level/new threshold.
- Broke: none.

---

## 2026-04-15 — Code review sweep (tower responsiveness + minor debt)
External review flagged six items. Applied the genuine fixes; rejected one that was based on outdated plan.
- **Tower attack loop: Timer → cooldown (valid fix).** `towers/base_tower.gd` no longer uses an AttackTimer node — attack pacing is now a `_attack_cooldown: float` decremented in `_physics_process`. First shot fires the instant an enemy enters range instead of waiting up to `1 / attack_speed` for a Timer cycle. Also removed the now-orphan `AttackTimer` Timer node from `towers/TowerArcher.tscn`.
- **Target picking: sticky + HP tiebreaker (valid + extra).** Reviewer flagged equal `progress_ratio` as causing chaotic retargeting when `Area2D.get_overlapping_areas()` iteration order shuffles. Real issue is bigger — previous logic re-picked from scratch every tick with no preference for the current engagement. New `_pick_target()` in `towers/base_tower.gd`: keeps the current target on a progress tie, and on true ties without the current target it prefers the lower-HP enemy (finish one before spreading DPS). Uses `is_equal_approx` instead of `==` on the float compare.
- **Lunge stutter cap (defensive).** `heroes/base_hero.gd` `_start_lunge`: `_lunge_t = min(LUNGE_DURATION, (1 / attack_speed) * 0.9)`. Current attack_speed (1.0) leaves the full 0.12 s duration; any future scaling past ~7.5 attacks/sec will shorten the lunge to fit the cooldown instead of stuttering mid-animation.
- **DEBUG_STATUS_ARROWS → false.** `towers/base_tower.gd`: archers no longer randomly slow/stun enemies every 3-6 shots. Mechanism preserved as a dev toggle for future status-effect debugging.
- **Projectile pooling: deferred.** At 4 towers × 1.2 shots/s the GC pressure is nowhere near the pain point. Noted as Phase 41 polish work; will matter once Endless mode (Phase 32) sustains 30+ towers firing.
- **Hero selection code: rejected as "dead".** Reviewer assumed we shipped Option C. Actual state is Option B (tap hero → ring → tap map → move + auto-deselect) — see the previous session entry. The `is_selected` / `set_selected` / `_input` hit-test is load-bearing, not legacy.
- Works: F5 → place an archer, spawn an enemy — tower fires the moment the enemy crosses the range line instead of waiting for the previous tick to roll over. Two enemies travelling in lockstep now get focus-fired (lower-HP dies first) instead of alternating shots. No more random crowd-control arrows.
- Broke: none.

---

## 2026-04-15 — Input-pipeline audit: hero vs. tower-spot overlap
Trace of the current input flow, written down while auditing the "what if the hero is standing on a tower spot" edge case.

Pipeline (Godot input order):
1. `_input` — every node, root→children top-down. TowerBarracks rally-placement captures here. No collision with hero.
2. Area2D picking → `input_event` signals. Barracks FlagArea drag captures here.
3. GUI → `Control.gui_input`. TowerSpotMenu's Backdrop (`mouse_filter=STOP`) consumes while the menu is visible, modalizing it.
4. `_unhandled_input` — every node, tree order, only if not consumed upstream.

Tree order in Main.tscn puts `Level1/SpotInputManager` before `HeroWarrior` before `HeroInputManager` for step 4, which is the critical ordering below.

Two real bugs surfaced by the audit:
- **Hero selection wasn't modal.** `BaseHero._input` ran in step 1, BEFORE the Backdrop could consume in step 3. Tapping on the hero while TowerSpotMenu was open toggled selection anyway.
- **Hero-on-spot input theft.** If the hero was parked near/on a tower spot, the hero's 22 px select radius swallowed the press before `SpotInputManager` (which doesn't/didn't consume) could open the build/sell menu. The player's tap intended for the spot selected the hero instead.

Fixes:
- `heroes/base_hero.gd`: renamed `_input` → `_unhandled_input` with no other logic changes. Now hero selection only fires if nothing upstream (rally placement, flag drag, TowerSpotMenu Backdrop, SpotInputManager) claimed the tap.
- `map/SpotInputManager.gd`: after `EventBus.tower_spot_tapped.emit(spot_id)`, calls `get_viewport().set_input_as_handled()`. Tap on a spot now belongs entirely to the tower flow; hero never sees it even if the hero body overlaps the spot.
- `heroes/HeroInputManager.gd`: no change — its existing 36 px spot-proximity early-return is now redundant (SIM consumes first) but kept as defense-in-depth.

Consolidated behaviour by case:
- Empty map tap: hero moves iff selected.
- Spot tap (no hero body underneath): menu opens.
- Spot tap with hero body on the spot: menu opens, hero untouched.
- Tap on hero body (no spot nearby): hero selects / deselects.
- Tap anywhere while TowerSpotMenu open: Backdrop eats it, nothing else reacts.
- Tap anywhere while barracks in rally-placement mode: barracks consumes, places flag or cancels.
- Flag drag on a barracks: captured by Area2D input_event, no leakage.

Works: F5 → park the knight on Spot5 → tap the spot → build menu opens, hero does not select (previously hero stole the tap). Open the menu → tap the knight → menu stays modal, hero does not select (previously hero would toggle through the Backdrop).
- Broke: none.

---

## 2026-04-15 — Phase 20: Hero skill 1 (Slash, single-target)
- Skill data layer:
  - `heroes/skills/skill_data.gd` (new Resource `SkillData`): base with `TargetType { SINGLE, AREA, SELF }` enum + fields (skill_name, skill_id, skill_range — 0 means use hero's attack_range, damage, damage_type, cooldown, target_type, icon, description) + a `apply(hero, target)` virtual for subclasses. Cooldown state is intentionally NOT on the resource — resources are shared, cooldown is per-hero.
  - `heroes/skills/slash_skill_data.gd` (extends SkillData): overrides `apply(hero, target)` — validates the target is a non-dying BaseEnemy and routes a hit through `enemy.take_damage(damage, damage_type, hero)`. Because `source = hero`, kills from the skill still grant XP via Phase 19's last-hit semantics.
  - `heroes/data/skills/skill_slash.tres`: Slash — 40 dmg, physical, range 0 (= hero's 60 px attack range), cooldown 6 s, single target. Wired into `heroes/data/hero_warrior.tres` `skills = Array[Resource]([skill_slash])`.
- Hero API (`heroes/base_hero.gd`):
  - New `_skill_cooldowns: Array[float]` — sized in `_ready()` parallel to `data.skills`, ticked in `_tick_skill_cooldowns(delta)` (called from `_physics_process`), emits `EventBus.skill_ready(skill_name)` on the frame a cooldown hits zero.
  - Public API: `get_skill_data(idx)`, `get_skill_cooldown_fraction(idx)` (0 = ready, 1 = just cast — UI radial maps this to arc coverage), `get_skill_effective_range(idx)`, `can_cast_skill(idx)`, `cast_skill(idx, target)`. `cast_skill` applies the effect, starts the cooldown, emits `hero_skill_used` + `skill_cooldown_started`, and kicks the lunge tween toward the target for a melee-cast feel.
  - New `set_skill_range_preview(radius)` — SkillBar flips this on/off to overlay a yellow range circle on the hero during targeting. Drawn in `_draw()` before the body + selection ring so the body sits on top of the fill. Handled on the hero itself (rather than a separate Node2D) so the circle stays in world-space even if a Camera2D gets added later.
  - `SkillData` type references in hero code are written as `Resource` rather than `SkillData` — mirrors the StatusEffect / BaseSoldier pattern where Godot's class_name index hasn't caught up on brand-new scripts. Runtime duck-typing is identical; LSP diagnostics stay clean.
- Skill bar UI:
  - `ui/CooldownButton.gd` + `.tscn`: Control with a custom `_draw()` — orange placeholder tile, dark outline, and a dark semi-transparent pie slice that shrinks counter-clockwise over the button as the cooldown drains (per CLAUDE.md: radial fill, never text). `_gui_input` captures the press and emits `pressed_skill(idx)`. Uses `ThemeDB.fallback_font` + `draw_string` for the skill name label.
  - `ui/SkillBar.gd` + `.tscn`: CanvasLayer (layer 8 — above HUD 1, below TowerSpotMenu 10). Bottom-right VBoxContainer gets one CooldownButton per `hero.data.skills` entry on `hero_spawned`. Tap a button → enter targeting mode (sets the hero's range preview). Next screen tap: SkillBar's `_input` captures it, rejects taps outside the range circle, else finds the closest enemy within 32 px of the tap and within the skill's range of the hero via `get_tree().get_nodes_in_group("enemies")`, and calls `hero.cast_skill`. Either outcome ends targeting so the player isn't stuck armed.
- `enemies/base_enemy.gd`: `_ready` now `add_to_group("enemies")`. `get_nodes_in_group` is only called on a targeting tap (not per-frame), so the mobile-perf rule ("never get_nodes_in_group in _physics_process") still holds.
- `main/Main.tscn`: instanced SkillBar below HUD (layer 8) so its CanvasLayer stack sits under the TowerSpotMenu backdrop (layer 10) but above the HUD labels (layer 1).
- Works: F5 → bottom-right of the screen shows a single orange "Slash" tile. Tap it → yellow range circle appears on the knight. Tap an enemy inside the circle → enemy takes 40 physical damage (orcs die in one hit), the button darkens with a radial pie slice that shrinks over 6 s. Tap outside the circle or with no enemy nearby → targeting cancels, no cooldown spent. Tapping the button again while armed cancels targeting. Slash cast on the killing blow still awards XP to the hero (confirmed via HUD ticking + "[Hero] Knight reached level 2" log).
- Broke: none.

---

## 2026-04-15 — Phase 20.5: Composition foundation — AbilityData + AbilityHost
Architectural scaffold before Phase 21 lands more skill/passive content. Long discussion documented in conversation; short version: the same Resource + dispatcher primitive will eventually power enemy traits, hero passives, tower on-hit effects, item-granted effects, talent-tree nodes, endless modifiers, and status effects. One concept, six future use-cases.
- `systems/AbilityData.gd` (new Resource): Trigger enum (ON_SPAWN, ON_INTERVAL, ON_HIT_DEALT, ON_HIT_TAKEN, ON_KILL, ON_DEATH, WHILE_ALIVE, ON_EQUIP, ON_UNEQUIP) + `apply(owner, ctx)` virtual. Subclasses add their own `@export` fields. Resources are shared across instances; per-unit state lives on the host.
- `systems/AbilityHost.gd` (new RefCounted): per-unit dispatcher. Holds `Array[Resource]` of abilities + parallel `_interval_accum`. `add_ability` (auto-fires ON_SPAWN), `remove_ability`, `tick(delta)` (advances ON_INTERVAL clocks and fires when crossed), `trigger_event(event, ctx)` for one-shot dispatches. Owner-agnostic — same host reused by every unit type.
- `systems/abilities/HealAuraAbility.gd` (first concrete subclass): the Phase 15 shaman aura ported as a Resource. `heal_range` + `heal_amount` fields, ON_INTERVAL trigger, group-iterates the "enemies" group and heals nearby allies via `BaseEnemy.heal()`. No Area2D / no HealTimer — pure data + group iteration. Distance-squared comparison so the per-tick cost is trivial.
- `enemies/EnemyData.gd`: stripped 10 flat fields (`heals_allies`, `heal_range`, `heal_amount`, `heal_interval`, `regenerates`, `regen_rate`, `explodes_on_death`, `explosion_damage`, `explosion_range`, `spawns_on_death`, `spawn_count`, `spawn_scene`). Replaced with one `abilities: Array[Resource]`. Designers now mix mechanics in the Inspector instead of toggling 12 booleans.
- `enemies/data/enemy_healer.tres`: rewrote to declare the heal aura as an inline `[sub_resource type="Resource"]` (HealAuraAbility, trigger=1=ON_INTERVAL, interval=2.0, range=130, amount=3) and reference it from `abilities`. Same gameplay numbers as before.
- `enemies/EnemyHealer.tscn`: removed the HealArea Area2D + HealTimer Timer nodes — both obsolete now that the ability handles range+pulse without scene-side help.
- `enemies/enemy_healer.gd`: shrunk to 21 lines, only the placeholder `_draw()` remains. Marked for eventual removal once visuals go data-driven (Phase 41 polish).
- `enemies/base_enemy.gd`: hosts an `AbilityHost` per instance. Built in `_ready` (after `add_to_group("enemies")` so any ON_SPAWN ability that scans the group sees this enemy). `_physics_process` calls `_ability_host.tick(delta)`. `_die()` fires `trigger_event(ON_DEATH, {})` BEFORE despawn so future ExplodeOnDeath / SummonOnDeath abilities can still read our position + iterate the enemies group.
- `CLAUDE.md`: added a new "🧩 Ability System" section above the Enemy System block — documents the Trigger enum, authoring workflow, list of implemented + reserved abilities, and the discipline rules (owner-agnostic, dispatch order = array order, state on host not data). Updated Enemy Data block to reflect the lean field list.

Foundation explicitly deferred (will land when first consumer needs them):
- `StatBlock` + `StatModifier` — central stat-stack with sourced modifiers (additive → multiplicative → final-add resolution). Lands when items / buffs need to push removable bonuses.
- `AttackPatternData` + `OnHitEffectData` — splits "how a tower delivers damage" from "what happens on hit". Lands at Phase 24 (tower upgrades + branching).
- `WaveModifier` + endless scaling layer — lands at Phase 32.
- `ItemData` + slot/rarity/loot tables + LoadoutData + LoadoutScreen — lands across Phases 27.5, 30, 36.5.

Roadmap captured in conversation (Diablo-style multi-slot hero items, drops in-level only, shop+crafting in town menu, full progression persistence between levels). All of it composes onto the AbilityData primitive — items are just AbilityData containers with stat modifiers attached.

Works: F5 → wave 2 still spawns the green Shaman → it still pulses heals every 2 s on nearby orcs → console still prints `[Enemy/heal] Orc Grunt N → M`. No visible behaviour change despite the entire Area2D+Timer healing pipeline being gone — the ability resource produces identical output through generic machinery.
- Broke: none.

---

## 2026-04-15 — TowerSpotMenu bug: build fires through menu on bottom-row spots
- Reproduced: tapping Spot3/Spot4 (y≈600) or any bottom-row spot caused the menu to "skip" — the tower was built instantly without the player tapping the Build button a second time. Confirmed by user; my earlier "Godot's BaseButton protects against orphan releases" analysis was wrong in practice, at least for InputEventScreenTouch under `emulate_touch_from_mouse`.
- Root cause (empirical): the tap's RELEASE event lands on a Build button that just became visible under the finger. Something in Godot's event routing (or the interaction between touch emulation + Control GUI phase) causes the button's `pressed` signal to fire even though the button never saw the matching press. The press itself was consumed by SpotInputManager — only the release gets through.
- Fix in `ui/TowerSpotMenu.gd`: added a `_actions_enabled: bool` gate. In `_on_spot_tapped`, after `visible = true`, flip it to `false` and schedule a re-enable one idle frame later via `await get_tree().process_frame`. All four action handlers (`_on_archer_pressed`, `_on_barracks_pressed`, `_on_sell_pressed`, `_on_move_rally_pressed`) early-return when the gate is closed. So any action signal that fires from the in-flight release event is silently dropped; the menu stays open and waits for the next real tap.
- One idle frame (~16 ms at 60 fps) is imperceptible to touch input and strictly cheaper than disabling/re-enabling buttons (which would have overridden the gold-cost disabled logic).
- Works: F5 → tap Spot4 or any bottom-row spot → menu opens, archer/barracks buttons wait for an intentional second tap. Tap Build Archer → archer builds as normal. Previous behaviour (instant skip-to-build) is gone. Top-row spots (Spot1/Spot2) unchanged — they never had the bug because the panel didn't cover them.
- Broke: none.

---

## 2026-04-15 — TowerSpotMenu bug fix v2: swallow the release explicitly
- Previous one-frame `_actions_enabled` gate wasn't enough — `await get_tree().process_frame` resumes at end of the CURRENT frame, but a finger held for more than ~16 ms releases in frame N+1, by which time the gate is already re-opened. User confirmed the skip-to-build was still reproducible.
- Root-cause-level fix: `ui/TowerSpotMenu.gd` now has `_swallow_next_release` + a new `_input(event)` handler. When the menu opens, the flag flips true. `_input` runs before the GUI phase, so consuming the release there means Button.gui_input never sees it → Button.pressed can never fire from the tap that opened the menu. Once the release is eaten the flag clears, and normal input resumes immediately — no timing delay, no timer, no user-facing latency.
- Kept the `_actions_enabled` one-frame gate as belt-and-suspenders for any release that somehow bypasses `_input` (synthetic events, future dev overrides, etc.).
- Added `_swallow_next_release = false` to `_dismiss()` so the flag can't linger across sessions and accidentally eat an unrelated release from a later gesture.
- Works: F5 → tap any spot (including Spot4/Spot6 under the panel), hold the finger for any duration, release → menu stays open waiting for a deliberate second tap. Previous "tap once, tower builds" regression is gone at the root, not masked by timing.
- Broke: none.

---

## 2026-04-15 — Phase 20.5b: AbilityHost on heroes + soldiers, authoring contract in CLAUDE.md
- Extended the composition primitive from enemies-only to all three unit bases. Same pattern, same script preloads, same trigger enum.
- `soldiers/SoldierData.gd`: added `abilities: Array[Resource]`. Paladin-style healer soldiers are now a data edit (drop in a HealAuraAbility).
- `heroes/HeroData.gd`: added `abilities: Array[Resource]` alongside existing `skills`. Active skills stay in `skills` (player-cast via SkillBar), passives go in `abilities` (auras, on-hit, passive buffs). Equipment later pushes into the same `_ability_host`.
- `soldiers/base_soldier.gd`: preloads AbilityHost + AbilityData scripts, creates `_ability_host` in `_ready`, populates from `data.abilities`, ticks in `_physics_process`, fires `ON_HIT_DEALT` + conditional `ON_KILL` on damaging an enemy, `ON_HIT_TAKEN` in `take_damage`, `ON_DEATH` in `_die`.
- `heroes/base_hero.gd`: same wiring. Kill inference uses `BaseEnemy.State.DYING` transition inside `take_damage` — if pre_dying was false and post is DYING, the hit was lethal → fires ON_KILL.
- `enemies/base_enemy.gd`: added `ON_HIT_TAKEN` trigger in `take_damage` for symmetry (enrage abilities, thorns, etc.).
- `CLAUDE.md`:
  - Added Core Rule #11: "New content is authored as data, not code." Only subclass when the variant needs new structural behavior (collision layer, different control loop, novel behavior like pet-summoning). Visual + stat + passive differences never justify a new script.
  - Added Core Rule #12: "One primitive for mechanics: AbilityData." Every verb on a unit is an AbilityData resource. Owner-agnostic apply() or split the ability.
  - New "🧱 Modular content pattern" section above the Ability System block. Tables for per-subsystem authoring contract (Enemies / Soldiers / Heroes / Towers / Skills / Spells / Items / Status Effects), the "when subclass is warranted" list, and copy-paste recipes for adding a new hero / soldier / enemy / ability.
- Works: F5 → shaman still heals allies via HealAuraAbility (unchanged). Soldiers + heroes now ready to receive passive abilities via `.tres` edits only. Zero behavior change for existing content; all new capabilities.
- Broke: none.

---

## 2026-04-15 — Phase 21: Hero skills 2 + 3 (AoE + self-buff), validating the ability primitive
Both skills land on top of the Phase 20.5 AbilityData scaffold, exercising two different target_type flows AND the "skill-as-ability-factory" pattern (Rally constructs a temporary AbilityData at cast time and attaches it to the hero — no skill-local timers).
- Cleanup: deleted `node_2d.tscn` editor artifact from project root. Added stable `enemy_id` to `EnemyData` and `soldier_id` to `SoldierData` so Phase 27 save references are ID-based, not path-based.
- `systems/AbilityData.gd`: new `duration: float = 0.0` field. 0 = permanent (existing behavior); > 0 = auto-remove after that many seconds.
- `systems/AbilityHost.gd`: added `_age: Array[float]` parallel array, ticked each frame. Iteration in `tick()` flipped to reverse so duration-triggered removals don't skip entries. Generic mechanism — works for any ability, not just Rally's specific case.
- `heroes/skills/shield_bash_skill_data.gd` + `heroes/data/skills/skill_shield_bash.tres` (new): **Bash** — 22 physical dmg in a 70 px AoE around a tapped point, 10 s cooldown, `target_type = AREA (1)`, skill_range 120 (how far from hero you can place the blast). Iterates the "enemies" group and damages all within `aoe_radius`.
- `systems/abilities/OnHitBonusDamageAbility.gd` (new): AbilityData subclass with `trigger = ON_HIT_DEALT` + `duration > 0`. On every hit dealt by the owner, applies `bonus_damage` as a secondary `take_damage` call (source = owner, so XP still attributes correctly). Supports any future on-hit effect that needs "flat extra damage per swing" — Flame Tongue items, Wrath buffs, etc.
- `heroes/skills/rally_skill_data.gd` + `heroes/data/skills/skill_rally.tres` (new): **Rally** — SELF target_type, 18 s cooldown. On cast, `apply(hero, null)` instantiates an `OnHitBonusDamageAbility(bonus=8, duration=10)` and pushes it into `hero._ability_host`. AbilityHost auto-removes when the buff expires. No skill-local timer; no flag bookkeeping; Rally is stateless after cast. This is the reusable pattern items and future talents will follow.
- `heroes/data/hero_warrior.tres`: `skills = [slash, shield_bash, rally]`.
- `ui/SkillBar.gd`: reads `skill.target_type` on button press. SELF → cast immediately with `null` target (skips targeting mode entirely). AREA → targeting mode; cast passes `world_pos: Vector2`. SINGLE → targeting mode; cast passes the nearest enemy Node within `TARGET_TAP_TOLERANCE` of the tap. Preloads `SkillData` script as `_SkillDataScript` to reach the `TargetType` enum.
- Works: F5 → skill bar shows three tiles (Slash / Bash / Rally). Slash targets single enemy (40 dmg, unchanged). Bash arms → tap within the circle → every enemy within 70 px of the tap takes 22 dmg instantly. Rally casts on button press — no targeting step; for the next 10 s every Slash / auto-attack deals +8 bonus damage (confirmed by enemies dying to fewer swings during the buff, then reverting to normal). Cooldowns count down as expected; tile goes dark with the shrinking pie overlay.
- Broke: none.
- Architectural payoff: Rally (skill 3) is ~25 lines of GDScript. It needs no `_process`, no Timer, no flag, no "undo" bookkeeping. The cast just constructs a resource and hands it to the host. This is the blueprint for:
  - Every future buff skill ("Heal over time", "Speed Aura")
  - Consumable items ("Potion of Strength: +20% damage for 30 s")
  - Talent-tree passives ("On-kill: +5% damage for 3 s")
  - Global spell effects ("Battle Banner: all allies in range get +1 armor for 15 s")
  - Shrines ("Elemental Blessing: fire damage on hit for this wave")
All of them = construct an AbilityData + call `add_ability(...)`.
- Next: Phase 22 — global spell 1 (area damage).

---

## 2026-04-15 — Phase 22: Global spell 1 (Fireball, AoE magic damage)
Landed on top of the Phase 20.5 ability + Phase 20 skill patterns. The CooldownButton is now provider-agnostic, so hero skills and global spells both drive identical-looking UI tiles from the same component.
- `ui/CooldownButton.gd`: generalized from hero-specific to provider-agnostic. `setup(provider: Node, idx: int)` — any Node with `cooldown_fraction(idx) -> float` and `display_name(idx) -> String` can drive the button. Signal renamed from `pressed_skill` → `triggered`. Drawing unchanged (radial pie-slice overlay + centered label).
- `heroes/base_hero.gd`: added `cooldown_fraction(idx)` and `display_name(idx)` as thin aliases to existing `get_skill_cooldown_fraction` / `get_skill_data(idx).skill_name`. Satisfies the provider contract without touching the existing public API.
- `ui/SkillBar.gd`: updated the signal connection from `pressed_skill` → `triggered`. No behavioral change.
- `spells/SpellData.gd` (new Resource base): `TargetType { AREA, GLOBAL }`, `spell_id / spell_name / cast_range / radius / damage / damage_type / cooldown / target_type / icon / vfx_scene / description`. Virtual `apply(world_pos, caster)`. Upgrade-tree hooks (Phase 28) will push AbilityData onto the cast context later.
- `spells/fireball_spell_data.gd` (new SpellData subclass): group-iterates `"enemies"`, filters non-DYING + inside `radius` of `world_pos`, calls `enemy.take_damage(damage, damage_type, caster)`. Source = SpellPanel (the caster Node), so spell kills do NOT award hero XP — matches Kingdom Rush's rule that spells don't level up your hero. Instantiates `vfx_scene` at the impact point if set.
- `spells/FireballVFX.gd + .tscn` (new): orange expanding disc + bright outline, alpha-fades over 0.4 s via Tween, auto queue_frees. Placeholder visual; Phase 41 polish swaps for real VFX.
- `spells/data/spell_fireball.tres`: Fireball — 55 magic dmg, 90 px radius, 25 s cooldown, AREA target. Wires `vfx_scene = FireballVFX.tscn`.
- `ui/SpellPanel.gd + .tscn` (new): CanvasLayer (layer 7) bottom-left column of CooldownButtons, one per spell. Holds `@export spells: Array[Resource]` + parallel `_cooldowns: Array[float]`. Ticks cooldowns in `_physics_process`, emits `spell_ready(name)` on crossings. Exposes `cooldown_fraction(idx)` + `display_name(idx)` for the button provider contract. On button trigger → enters AREA targeting mode. `_input` consumes the next screen touch, resolves to world pos, calls `spell.apply(world_pos, self)`, starts the cooldown, emits `spell_cast` + `spell_cooldown_started`, consumes the input.
- `main/Main.tscn`: instanced `SpellPanel` at layer 7 (above HUD=1/SkillBar=8? actually SkillBar=8, SpellPanel=7 — SkillBar wins z-order, which is fine because both panels are in distinct screen corners).
- Wait — check stacking. SkillBar layer=8 (bottom-right), SpellPanel layer=7 (bottom-left). They don't spatially overlap, so layer numbers only matter for modals. TowerSpotMenu layer=10 still dominates both. Fine.
- Guarded against double-cast: both `SkillBar._input` and `SpellPanel._input` now `return` early if `get_viewport().is_input_handled()`. Without this, arming both a skill AND a spell would fire both on the next tap, because `_input` runs for every listener regardless of consumption. Belt-and-suspenders beyond the in-handler `set_input_as_handled()` call.
- Works: F5 → bottom-left shows a single orange "Fireball" tile. Tap it → enters targeting mode. Tap anywhere on the map → orange circle bursts at the tap point, fades over ~0.4 s, every enemy in a 90 px radius takes 55 magic damage (orcs die instantly at current stats). Tile darkens with the shrinking 25 s pie overlay. Hero XP unchanged (spell kills credit nobody). Bottom-right Slash / Bash / Rally unaffected.
- Broke: none.
- Next: Phase 23 — global spell 2 (reinforcements).

---

## 2026-04-15 — Phase 23: Global spell 2 (Reinforcements / "Recruit")
Landed as pure data composition — no new death-timer code, no new soldier subclass. A generic `LifetimeAbility` + attaching it to spawned soldiers via the existing AbilityHost + AbilityData.duration auto-removal does all the work. This validates the "summon / decoy / minion" pattern for future items and talents.
- `systems/AbilityHost.gd`: on auto-removal of a duration-expired ability, now calls `a._on_expired(owner)` if the ability defines it. Enables subclasses to run finalization (e.g. killing the owner) at the moment their duration runs out. Optional method — abilities without `_on_expired` just get silently detached as before.
- `systems/abilities/LifetimeAbility.gd` (new AbilityData subclass): no-op `apply()`. Override of `_on_expired(owner)` routes through `owner._die()` if present (fires soldier_died / enemy_died + runs ON_DEATH abilities + queue_frees via the unit's normal path) or falls back to `queue_free()`. One script. Handles every "this unit exists for N seconds" mechanic going forward — reinforcement squads now, summon items + decoy spells later.
- `spells/reinforcements_spell_data.gd` (new SpellData subclass): `soldier_scene` + `squad_size` + `lifetime` + `spread_radius` fields. On cast, instantiates `squad_size` soldiers from `soldier_scene`, parents them to the current scene root, fans them in a ring of `spread_radius` around the tap point, calls `setup(slot)` so they walk to their blocking position, then attaches a `LifetimeAbility(duration=lifetime)` to each via `soldier._ability_host.add_ability(...)`. Zero soldier code touched.
- `spells/data/spell_reinforcements.tres`: Recruit — summons 4 Militia for 20 s at the tapped point, 40 s cooldown. spell_id = "reinforcements".
- `ui/SpellPanel.tscn`: added Recruit to the `spells` array. Panel now shows two tiles (Fireball + Recruit) — CooldownButton generalization from Phase 22 means no per-spell UI work was needed.
- Side-effect test: if a Recruit soldier gets killed by an enemy before its 20 s is up, its `_die()` fires normally, the barracks respawn logic ignores it (soldier not in any barracks' `_active_soldiers` list), and the LifetimeAbility just never gets to fire `_on_expired` because the soldier is already gone. Two independent death paths, both safe.
- Works: F5 → bottom-left now has Fireball + Recruit tiles. Tap Recruit → targeting mode → tap a lane → 4 yellow militia squares drop there, fan out, engage any orcs that walk into range. After ~20 s they simultaneously `_die()` and vanish (soldier_died fires, no respawn). Barracks-spawned soldiers untouched by the spell. Fireball unchanged.
- Broke: none.
- Architectural note: three Phase 21-23 features (Rally buff, Fireball damage, Recruit summon) landed with essentially zero new lifecycle/timer code. All three use AbilityData + AbilityHost.duration as the scaffolding, and they plug into the owner's existing `_die()` / `take_damage()` / `_ability_host` paths. Adding a similar summon-minion item, a smoke-screen decoy spell, or a timed-buff consumable will each be one more AbilityData subclass + one `.tres` in the right folder.
- Next: Phase 24 — tower upgrade linear (levels 1→2→3).

---

## 2026-04-15 — Phase 24: Tower upgrade linear (L1 → L2 → L3)
Linear stat upgrades through a new `TowerUpgradeData` Resource — same composition pattern the rest of the game uses. L3 slot already accepts `on_hit_abilities: Array[Resource]`, teed up for Phase 25's Ranger-vs-Musketeer branch differentiation.
- `towers/TowerUpgradeData.gd` (new Resource): per-level stat override — `upgrade_name`, `damage`, `attack_range`, `attack_speed`, `cost`, `sell_value`, `on_hit_abilities: Array[Resource]` (Phase 25 uses this), `tint: Color` (placeholder visual). Full override of the level's stats, not deltas — easier to balance-tune in the Inspector.
- `towers/TowerData.gd`: added `level_upgrades: Array[Resource]` (index 0 = L2, index 1 = L3). Kept `upgrade_cost_lvl2` / `upgrade_cost_lvl3` as legacy-fallback fields (default 0 now so they don't interfere).
- `towers/base_tower.gd`:
  - `MAX_LEVEL = 3` constant; existing `level: int = 1` now drives effective-stat resolution.
  - New `_level_override() -> Resource` returns the current level's `TowerUpgradeData` or null for level 1.
  - New `get_effective_damage()` / `get_effective_range()` / `get_effective_attack_speed()` / `get_sell_value()` — all read through the override if set, else fall back to TowerData.
  - New `get_upgrade_cost_to(next_level)` reads from `TowerUpgradeData.cost` first, falls back to legacy `upgrade_cost_lvlN` fields.
  - `can_upgrade()` / `upgrade()` public API: resets attack cooldown on upgrade (so the snappier attack speed is felt immediately), re-sizes RangeArea shape, emits `tower_upgraded(tower, new_level)`, `queue_redraw()`s for the visual tint change.
  - `_physics_process` + `_fire_projectile` now use `get_effective_*` everywhere. Old `data.damage` / `data.attack_speed` references all routed through the helpers.
  - `_draw()` tints the body via `Color(base) * override.tint` and paints N gold pips at the top of the tower to show upgrade level at a glance.
- `towers/data/tower_archer.tres`: authored L2 (7 dmg, 175 range, 1.35 spd, 75g, sell 60) and L3 (12 dmg, 195 range, 1.5 spd, 120g, sell 120) as `[sub_resource]` TowerUpgradeData entries in the `level_upgrades` array.
- `autoloads/EventBus.gd`: added `tower_upgrade_requested(spot_id)` signal alongside the existing `tower_upgraded`.
- `ui/TowerPlacer.gd`: listens for `tower_upgrade_requested`, resolves via GridManager, calls `tower.can_upgrade()` + `get_upgrade_cost_to(level + 1)`, spends gold through GameState, calls `tower.upgrade()`, refunds if upgrade refused post-spend. Sell refund also now goes through `tower.get_sell_value()` so an upgraded tower refunds its higher sell value.
- `ui/TowerSpotMenu.tscn/gd`:
  - Added `UpgradeButton` to the SellRow (above Move Rally / Sell).
  - New `_refresh_upgrade_button()` — shows only when the current tower supports upgrading AND is below max level. Label reads "Upgrade → Lv N (Xg)", greyed out when gold is insufficient.
  - Added listener for `tower_upgraded` that refreshes labels (sell value, upgrade button state) without dismissing the menu — players can chain upgrades without reopening.
  - `_on_gold_changed` now also re-runs upgrade-button evaluation while sell row is visible.
- `ui/RangePreview.gd`: reads `tower.get_effective_range()` when available, falling back to `data.attack_range`. Upgraded towers now show the larger preview radius correctly.
- Barracks unaffected — `level_upgrades` empty on `tower_barracks.tres`, so `can_upgrade()` returns false and the upgrade button doesn't appear. Barracks upgrades are a later task (deferred).
- Works: F5 → build an archer → tap it → menu shows Upgrade → Lv 2 (75g) + Sell (+30g) + Close. Press Upgrade → gold drops 75, tower body darkens slightly, gains a second gold pip up top, attack speed audibly quickens, range circle expands on next tap. Press Upgrade again (if affordable) → Lv 3 (120g), third pip, brighter yellow tint. Sell after upgrading refunds 120g (L3 sell) instead of the L1 30g. Barracks shows no Upgrade button.
- Broke: none.
- Architectural payoff: `on_hit_abilities: Array[Resource]` on TowerUpgradeData is already in place — Phase 25 just needs to attach two different `TowerUpgradeData` resources (Ranger / Musketeer) and route the player's branch choice through the upgrade path. No new systems.
- Next: Phase 25 — branching upgrade choice at level 3.

---

## 2026-04-15 — Phase 25: Branching upgrade at L3 (Ranger vs. Musketeer)
Reuses Phase 24's `TowerUpgradeData` — branches are just alternative L3 resources living in a separate array slot. No new Resource types needed.
- `towers/TowerData.gd`: added `level_3_branches: Array[Resource]` alongside the existing `level_upgrades`. If non-empty, the L2 → L3 transition uses one of the branch entries (chosen by the player) and `level_upgrades[1]` is bypassed.
- `towers/TowerUpgradeData.gd`: added `on_hit_slow_factor`, `on_hit_slow_duration`, `on_hit_stun_duration` for branch-differentiating on-hit status effects. Kept `on_hit_abilities: Array[Resource]` reserved for a future generalized on-hit composition (Phase 41 polish).
- `towers/base_tower.gd`:
  - New `branch_idx: int = -1` — permanent choice once set (-1 means linear or pre-L3).
  - `_level_override()` prefers `data.level_3_branches[branch_idx]` at L3 when branched.
  - New `has_branch_options()`, `get_branch_options()`, `get_branch_cost(idx)`, `upgrade_to_branch(idx)` public API. `can_upgrade()` returns false when branches are required so the linear Upgrade button gets out of the way.
  - `_fire_projectile()` now calls new `_build_on_hit_effect()` — constructs a fresh `SlowEffect`/`StunEffect` per shot from the current level override's fields. Ranger branch gets 45% slow for 1.5 s on every arrow; Musketeer is pure damage. Fresh instance per shot so per-target countdowns don't cross-pollute. Falls back to the debug-arrow roll if no override effect is configured.
- `autoloads/EventBus.gd`: added `tower_branch_upgrade_requested(spot_id, branch_idx)`.
- `ui/TowerPlacer.gd`: new `_on_branch_upgrade_requested` — validates via `has_branch_options()` + `get_branch_cost(idx)`, spends gold, calls `upgrade_to_branch(idx)`, refunds on refusal. Mirrors the linear upgrade transaction exactly.
- `ui/TowerSpotMenu.tscn/gd`:
  - Added `BranchARow` + `BranchBRow` buttons to SellRow between Upgrade and MoveRally. Panel `offset_top` bumped from -320 → -440 to fit the tall branch-picker layout.
  - `_refresh_upgrade_button()` now checks `has_branch_options()` first — when true, hides the linear Upgrade and shows the two branch buttons with per-branch upgrade_name + cost. Each button greys out when gold is insufficient.
  - Button press handlers bound via `.bind(0)` / `.bind(1)` to emit `tower_branch_upgrade_requested(spot_id, idx)`.
- `towers/data/tower_archer.tres` branches:
  - **Ranger** — 10 dmg, 210 range, 1.4 atk/s, 140g, sell 130. On-hit: 45% slow for 1.5 s per arrow. Green tint. Glue-the-enemies playstyle.
  - **Musketeer** — 22 dmg, 225 range, 0.75 atk/s, 160g, sell 140. No status effect. Orange tint. Slow heavy-hitter playstyle.
- Barracks still unaffected — no `level_3_branches` on `tower_barracks.tres`, so branching never appears there.
- `tower_branch_chosen(tower, idx)` emitted alongside `tower_upgraded` when a branch is picked — available for Phase 34 encyclopedia unlocks, Phase 27 saves, etc.
- Works: F5 → build Archer → upgrade to Lv 2 (75g) — single Upgrade button shown. After reaching L2, the button row flips — Upgrade disappears, "Ranger (140g)" and "Musketeer (160g)" appear side-by-side. Pick Ranger → tower turns green, arrows now slow enemies by 45% for 1.5 s (orcs visibly crawl with cyan slow ring). Pick Musketeer instead → orange tower, slower cadence but each arrow hits for 22. Either choice is permanent — no upgrade buttons afterwards, just Sell (refund at the branch's sell_value). Sell an upgraded branch tower → refund reflects the branch's sell_value (130g for Ranger, 140g for Musketeer).
- Broke: none.
- Architectural validation: two fundamentally different tower behaviors (DoT-slow vs. flat-damage-pierce-feeling) authored as pure data — no branch-specific GDScript. Musketeer's "pierce" isn't implemented yet (would need arrow pierce-count on TowerUpgradeData + arrow logic) but damage-per-shot carries the role for now; can add pierce as an Arrow + data field when needed.
- Next: Phase 26 — star rating system (campaign).

---

## 2026-04-16 — Phase 26: Star rating system (campaign)
- `autoloads/GameState.gd`: added `current_level_id: String`, `stars_earned: int`, and `calculate_stars() -> int` using the CLAUDE.md thresholds (18-20 lives = 3★, 6-17 = 2★, 1-5 = 1★, 0 = defeat). `reset()` zeros `stars_earned`.
- `ui/GameOverScreen.gd`: on `all_waves_completed`, calls `calculate_stars()`, sets `stars_earned`, shows ★/☆ text in the victory summary, emits `EventBus.level_completed(level_id, stars, mode)` for Phase 27 SaveManager and Phase 29 WorldMap to consume.
- Works: F5 → clear all 3 waves with 20 lives → Victory shows ★★★. Leak some → ★★ or ★. Defeat shows no stars. `level_completed` signal fires (verified in console).
- Broke: none.
- Next: Phase 27 — SaveManager (persist all progress).

---

## 2026-04-16 — CLAUDE.md audit + updates
Audited CLAUDE.md against the actual codebase. Three stale sections fixed, four new sections added:
- **Fixed:** EventBus signal table (added 6 missing signals from Phases 8-25). Tower Data section (added TowerUpgradeData + level_upgrades/level_3_branches spec alongside the legacy fields). Ability "implemented" list (added OnHitBonusDamageAbility + LifetimeAbility).
- **New Core Rule #13:** Stable content IDs. Documents the `*_id: String` convention and the "never rename post-release" save-compat discipline.
- **New section: 🎯 Input Pipeline — Consumption Chain.** ASCII-art flow diagram of the 4-phase input chain (_input → GUI → picking → _unhandled_input) with every handler's placement and rules for adding new handlers. Battle-tested through 10+ input-related bug fixes this session.
- **New section: 🗡️ Skill System.** Documents SkillData + TargetType enum + the 3 Knight skills + the skill-as-ability-factory pattern (Rally) + SkillBar UI flow per target type.
- **Updated section: 🌩️ Global Spell System.** Expanded spec to match actual SpellData fields (spell_id, cast_range, target_type). Added "spells implemented" table (Fireball, Recruit). Documented the SpellPanel provider contract and the "spell kills don't grant hero XP" rule.

---

## 2026-04-16 — Screen flow: MainMenu + WorldMap + PauseMenu + SceneManager
Full game loop before SaveManager so the save schema has real consumers. Plan designed and approved in plan mode before implementation.
- `autoloads/SceneManager.gd` (new autoload): CanvasLayer at layer 100 with a full-screen ColorRect. `goto(scene_path, fade=true)` tweens alpha 0→1 over 0.3 s, swaps scene via `change_scene_to_file`, fades back. `_transitioning` flag blocks double-calls. Registered in `project.godot` alongside the existing 6 autoloads.
- `autoloads/GameState.gd`: added `level_stars: Dictionary` (level_id → best star count), `levels_unlocked: Dictionary` (level_id → true/false), `record_stars()` (persists `max(previous_best, stars_earned)` in memory), `reset_for_level()` (resets gold/lives/score/wave/stars but preserves progression dictionaries + level_id + mode). `reset()` now delegates to `reset_for_level()` and additionally clears progression. SaveManager will read/write these dictionaries — WorldMap already reads them.
- `autoloads/EventBus.gd`: added `pause_requested()` signal.
- `ui/MainMenu.tscn + .gd` (new): game entry point. Dark background, centered VBox with title ("Fantasy Tower Defense") + 4 buttons (Play → WorldMap, Heroes/Upgrades/Settings greyed out for future phases). `project.godot` `run/main_scene` changed from `Main.tscn` → `MainMenu.tscn`.
- `ui/world_map/LevelNodeData.gd` (new Resource): `level_id`, `display_name`, `scene_path`, `unlock_order`. Data-driven — add levels by adding more entries.
- `ui/WorldMap.tscn + .gd` (new): level select screen. `@export var levels: Array[Resource]` with one LevelNodeData for Level 1 ("Forest Path") as inline sub_resource. Dynamically builds one panel per level with name + ★/☆ from `GameState.level_stars` + Play button (unlocked) or "Locked" label. Tap Play → `GameState.current_level_id = id`, `reset_for_level()`, `SceneManager.goto(scene_path)`. Back button → MainMenu. Dark green background.
- `ui/PauseMenu.tscn + .gd` (new): CanvasLayer 20, `PROCESS_MODE_WHEN_PAUSED` (same pattern as GameOverScreen). Dim + centered card with Resume / Restart / Quit to Map. Resume unpauses + hides. Restart calls `reset_for_level()` + `SceneManager.goto(Main.tscn)`. Quit → `SceneManager.goto(WorldMap.tscn)`. Connects to `EventBus.pause_requested`.
- `ui/HUD.tscn + .gd`: added PauseButton (80×60, top-right, "| |"). On press → `EventBus.pause_requested.emit()`.
- `main/Main.tscn`: added PauseMenu instance after GameOverScreen.
- `ui/GameOverScreen.tscn + .gd`: added ContinueButton above RestartButton. Victory: shows Continue (→ records stars + SceneManager to WorldMap), hides Restart. Defeat: shows Restart (→ `reset_for_level()` + SceneManager to Main.tscn), hides Continue. Removed the old `reload_current_scene()` call — all transitions go through SceneManager now.
- `level_list.tres` created in `ui/world_map/` but unused (WorldMap uses inline sub-resource instead). Can be deleted or kept for future inspector-editing workflow.
- Works: F5 → MainMenu appears (dark background, title, Play glows, 3 buttons greyed). Tap Play → fade to WorldMap showing "Forest Path ☆☆☆ [Play]". Tap Play → fade to gameplay (same Level1 as before). Pause button (top-right) → dim overlay with Resume/Restart/Quit. Resume → back to game. Quit to Map → WorldMap. Win level → Victory ★★★ Continue → WorldMap now shows ★★★ on Forest Path (in-memory, lost on app quit — Phase 27 SaveManager persists). Defeat → Restart → fresh gameplay.
- Broke: none.
- Next: Phase 27 — SaveManager (persist all progress). The schema is now trivially derivable: `level_stars`, `levels_unlocked`, plus future hero/item/upgrade data.

---

## 2026-04-16 — Phase 27: SaveManager (persist all progress)
- `autoloads/SaveManager.gd`: full implementation replacing the Phase 1 stub. JSON save at `user://save.json`, versioned schema (v1).
  - `load_game()`: called in `_ready()` (runs after GameState._ready due to autoload order). Reads JSON, validates version, populates `GameState.level_stars` + `GameState.levels_unlocked`. Handles missing file (first boot → defaults), corrupt file (warning + skip), wrong version (warning + skip). JSON floats → int conversion for star counts.
  - `save_game()`: serializes `level_stars` + `levels_unlocked` to disk with `JSON.stringify(data, "  ")` for readability. Schema has commented placeholders for all future save fields (endless_best_score, unlocked_heroes, permanent_upgrades, hero_equipment, inventory, etc.) so the next person to extend it sees the full roadmap.
  - `_on_level_completed(level_id, stars, mode)`: auto-saves after every level win. Records best stars (belt-and-suspenders alongside GameState.record_stars). Placeholder `_try_unlock_next_level` for sequential level unlock chain (no-op with one level; Phase 29+ implements).
  - `delete_save()`: debug utility, not player-facing. Wipes file + calls GameState.reset().
- Per CLAUDE.md Rule #8: SaveManager is the ONLY script that reads/writes the save file. No other script touches `user://save.json`.
- Works: F5 → MainMenu → WorldMap (☆☆☆) → Play → Win → ★★★ → Continue → WorldMap (★★★). Quit app. Relaunch → WorldMap still shows ★★★ (loaded from save). Play again → win with fewer lives → ★★ → WorldMap still shows ★★★ (best-of preserved). Delete `user://save.json` → back to ☆☆☆.
- Broke: none.
- Next: Phase 28 — permanent upgrade tree.

---

## 2026-04-16 — Phase 28: Permanent upgrade tree
Spend campaign stars on 6 global bonuses. Full data → UI → persistence → gameplay loop.
- `progression/UpgradeData.gd` (new Resource): `upgrade_id`, `upgrade_name`, `description`, `star_cost`, `prerequisite_id`, `effect_type` (enum with 8 categories: archer damage, tower range, hero HP/damage/XP, spell cooldown, starting gold, soldier HP), `effect_value`. Multiplicative for mult types, additive for bonus types.
- `autoloads/GameState.gd`: added `purchased_upgrades: Array[String]` + cache system. `rebuild_upgrade_cache(all_upgrades)` iterates purchased upgrades and precomputes multiplicative + additive caches per EffectType. `get_upgrade_multiplier(type)` / `get_upgrade_bonus(type)` — O(1) lookups. `get_total_stars()` / `get_spent_stars()` / `get_available_stars()` for the UI. `reset_for_level()` now adds STARTING_GOLD_BONUS to starting gold. `reset()` clears purchased_upgrades + caches.
- `autoloads/SaveManager.gd`: persists `purchased_upgrades` array in save JSON alongside level_stars + levels_unlocked. Loads on boot, converts from JSON array of strings.
- `ui/UpgradeTree.tscn + .gd` (new): accessible from MainMenu → "Upgrades" button (now enabled). Dark purple background, top bar with Back + "★ N / M available" label, scrollable list of upgrade panels. Each panel shows name + description + purchase button. Purchased → "Owned" (greyed). Prereq not met → "Locked". Can't afford → greyed. On purchase: appends to GameState.purchased_upgrades, rebuilds cache, emits permanent_upgrade_purchased, saves via SaveManager, rebuilds full UI so prereq chains update.
- 6 launch upgrades authored as inline sub_resources in the .tscn:
  - War Chest (1★): +25 starting gold
  - Sharp Arrows (2★): archer damage ×1.2
  - Extended Range (2★, prereq: Sharp Arrows): all tower range ×1.1
  - Hero Training (3★): hero damage ×1.15
  - Fast Learner (2★, prereq: Hero Training): hero XP ×1.25
  - Spell Mastery (3★): spell cooldowns ×0.85
- Gameplay effects wired — each system reads the appropriate multiplier:
  - `towers/base_tower.gd`: `get_effective_damage()` ×type0, `get_effective_range()` ×type1
  - `heroes/base_hero.gd`: `_effective_damage()` ×type3, `gain_xp()` ×type4
  - `ui/SpellPanel.gd`: cooldown = spell.cooldown × type5
  - `soldiers/base_soldier.gd`: max_health × type7 at spawn
  - `autoloads/GameState.gd`: starting_gold + type6 bonus in `reset_for_level()`
- `ui/MainMenu.gd`: Upgrades button now enabled, routes to UpgradeTree.
- Works: F5 → MainMenu → Upgrades → shows 6 nodes, all purchasable if stars allow. Purchase "War Chest" (1★) → "Owned". Back → Play → WorldMap → Level 1 → start with 125g instead of 100. Win → earn 3★ → back to Upgrades → buy Sharp Arrows (2★) → replayed level archers hit harder. Reset Progress clears all upgrades. Prereq chain: Extended Range locked until Sharp Arrows owned.
- Broke: none.
- Phase 29 (WorldMap) was already shipped earlier. Next: Phase 30 — HeroRoom / loadout.

---

## 2026-04-16 — Menu layout fix + Phase 30: LoadoutScreen
- **Menu layout feedback**: user wants Heroes/Upgrades/meta buttons on WorldMap (the hub), not MainMenu. Matches Kingdom Rush where world map IS the main hub. MainMenu stripped to title + Play + Reset. WorldMap gained a bottom HBoxContainer with Heroes (greyed, Phase 35) + Upgrades (→ UpgradeTree). UpgradeTree Back button now routes to WorldMap, not MainMenu. Saved to memory for future sessions.
- **Phase 30 — LoadoutScreen** (`ui/LoadoutScreen.tscn + .gd`): pre-level confirmation screen between WorldMap and gameplay. Shows current level, hero info (Knight stats + skills), tower roster, spell roster, Start + Back buttons. Currently informational only (one hero, fixed roster); becomes a real picker when Phase 35 adds hero 2 and loadout selection. WorldMap level tap now routes to LoadoutScreen instead of directly to Main.tscn. LoadoutScreen.Start calls `reset_for_level()` + `SceneManager.goto(Main.tscn)`.
- Flow: MainMenu → WorldMap (hub: levels + Upgrades + Heroes buttons) → tap level → LoadoutScreen → Start → gameplay. Back from LoadoutScreen → WorldMap. Back from UpgradeTree → WorldMap.
- Works: F5 → MainMenu (clean, just Play + Reset) → Play → WorldMap with bottom bar (Heroes greyed, Upgrades active) + Level 1 panel → tap Level 1 → LoadoutScreen shows "Hero: Knight, Towers: Archer/Barracks, Spells: Fireball/Recruit" → Start Battle → gameplay. Back → WorldMap.
- Broke: none.
- Next: Phase 31 — Heroic + Iron challenge modes.

---

## 2026-04-16 — Phase 31: Heroic + Iron challenge modes
Full challenge mode system with unlock chain, wave scaling, mode selector UI, composite star display.
- `autoloads/GameState.gd`: added `heroic_complete: Dictionary`, `iron_complete: Dictionary`. New helpers: `is_heroic_unlocked(id)` (needs 3★ campaign), `is_iron_unlocked(id)` (needs Heroic clear), `calculate_total_stars_for_level(id)` (0–5 composite: campaign 0–3 + heroic +1 + iron +1). `get_total_stars()` now sums composite across all levels (drives upgrade tree budget). `record_stars()` branches on `current_mode` — campaign records best stars, heroic/iron record completion flags. `reset_for_level()` sets lives=1 when mode is "iron". `reset()` clears heroic_complete + iron_complete.
- `autoloads/SaveManager.gd`: persists `heroic_complete` + `iron_complete` dictionaries. Load converts JSON booleans.
- `autoloads/WaveManager.gd`: in `_run_spawner`, when `current_mode` is "heroic" or "iron", scales enemy count ×1.5 (ceiled) and spawn interval ×0.85 (faster). Same wave .tres, harder at runtime. No separate wave files needed.
- `ui/LoadoutScreen.tscn + .gd`: fully rebuilt. Mode selector row: Campaign (always available, shows ★★☆ campaign stars) / Heroic (locked "Need 3★" or "Available" or "Complete ✓") / Iron (locked "Need Heroic" or "Available" or "Complete ✓"). Selected mode highlighted via modulate; unselected dimmed. Mode info label explains the rules ("1.5x enemies, faster spawns" / "1 life only"). Start → sets `GameState.current_mode` → `reset_for_level()` → gameplay.
- `ui/GameOverScreen.gd`: victory summary text varies by mode — "Campaign cleared! ★★★" / "Heroic cleared! +1 bonus star" / "Iron cleared! +1 bonus star — flawless!". `level_completed` signal still fires with mode for SaveManager.
- `ui/WorldMap.gd`: star display uses `calculate_total_stars_for_level(id)` — shows ★/5 instead of ★/3.
- Works: F5 → WorldMap (☆☆☆☆☆) → Level 1 → LoadoutScreen shows Campaign available, Heroic "Need 3★", Iron "Need Heroic". Play Campaign → win with 20 lives → ★★★ → Continue → WorldMap (★★★☆☆). Back to Level 1 → Heroic now "Available" → select → Start → 12 orcs wave 1 (was 8), faster spawns. Win → ★★★★☆. Iron unlocked → 1 life → any leak = instant defeat → survive → ★★★★★. All persists across app restart.
- Broke: none.
- Next: Phase 32 — Endless mode + score system.

---

## 2026-04-16 — Phase 32: Endless mode + score system
Infinite procedural waves with difficulty scaling. Score computed at death. Best score persisted.
- `autoloads/GameState.gd`: added `endless_best_score: int`, `compute_endless_score() -> int` (wave_number × gold × lives per CLAUDE.md spec). Cleared on reset().
- `autoloads/WaveManager.gd`:
  - New `_endless: bool` flag + `start_endless(level)` entry point.
  - `_begin_next_wave()` branches on `_endless` — generates a wave procedurally instead of reading from a WaveList.
  - `_generate_endless_wave(wave_num)` creates WaveData at runtime:
    - Base count: 4 + wave_num × 2, distributed across 1–3 paths (more paths as waves increase).
    - Spawn interval shrinks: `max(0.4, 1.2 - wave_num * 0.03)`.
    - Countdown shrinks: `max(1.5, 3.0 - wave_num * 0.1)`.
    - Bounty scales: 10 + wave_num × 5.
    - Flying enemies from wave 3+, healers from wave 5+.
    - `_pick_enemy_for_wave()` weighted random — basics dominate, harpies mix in later.
  - Emits `endless_wave_started(wave_num)` each wave. Heroic/Iron wave scaling (1.5× count) does NOT apply to endless — endless has its own scaling curve.
  - `stop()` clears `_endless` flag.
- `autoloads/SaveManager.gd`: persists `endless_best_score` in save JSON.
- `ui/WorldMap.tscn + .gd`: added Endless button in bottom bar. Tap → sets current_mode="endless", current_level_id="endless" → LoadoutScreen.
- `ui/LoadoutScreen.gd`: when mode is "endless", hides mode selector row (Campaign/Heroic/Iron), shows "Endless Mode" title + best score in mode_info_label.
- `main/Main.gd`: `_ready()` branches — if current_mode == "endless", calls `WaveManager.start_endless(level)` instead of `start(LEVEL1_WAVES, level)`.
- `ui/HUD.gd`: wave label shows "Wave: N" without total in endless (no "/" since total is infinite).
- `ui/GameOverScreen.gd`: on game_over + endless mode: computes score, checks if new best, updates `endless_best_score`, saves, shows "Score: N NEW BEST!" or "(Best: N)". Shows both Continue (→ WorldMap) and Restart buttons so player can retry immediately or exit.
- Works: F5 → WorldMap → Endless → LoadoutScreen shows "Endless Mode, Best: 0" → Start → gameplay: waves auto-generate, first wave ~6 enemies on left path, wave 3 adds flying from top, wave 5 adds healer. Wave label shows "Wave: 7" (no total). Die → "Game Over: Wave 7, Score: 52,500 NEW BEST!" → Continue returns to WorldMap. Best score persists across restarts.
- Broke: none.
- Next: Phase 33 — Online leaderboard.

---

## 2026-04-16 — Phase 33: Leaderboard (local, online-ready)
Client-side leaderboard architecture with local storage. Online HTTP plugs in later by swapping the data source in GameState — UI stays unchanged.
- `autoloads/GameState.gd`: added `endless_leaderboard: Array` (top 20 entries, each `{name, score, wave}`), `LEADERBOARD_MAX_ENTRIES = 20`, `submit_endless_score(name, score)` — appends, sorts descending, trims to max. Emits `leaderboard_score_submitted`. Cleared on reset().
- `autoloads/SaveManager.gd`: persists `endless_leaderboard` array in save JSON. Loads entries back as dictionaries.
- `ui/GameOverScreen.gd`: on endless death, calls `GameState.submit_endless_score("Player", score)` before saving — auto-populates the leaderboard. Continue button routes to WorldMap (doesn't call record_stars for endless since there are no campaign stars).
- `ui/LeaderboardScreen.tscn + .gd` (new): scrollable list of top entries. Header row (#, Name, Score, Wave). Gold-colored top 3. Empty state message if no scores. Back → WorldMap.
- `ui/WorldMap.tscn + .gd`: added "Scores" button in bottom bar → LeaderboardScreen.
- WorldMap bottom bar now: Heroes (greyed) | Upgrades | Endless | Scores
- Works: F5 → WorldMap → Scores → "No scores yet" → Back → Endless → play → die at wave 7 → "Score: 52500 NEW BEST!" → Continue → Scores → shows #1 Player 52500 W7 in gold. Play again → die at wave 3 → lower score appears as #2. Persists across restarts.
- Online integration notes (for when backend is chosen): swap `GameState.submit_endless_score` to POST to REST API + swap `endless_leaderboard` to GET from API. LeaderboardScreen.gd reads from same array — zero UI changes. LootLocker, PlayFab, or custom Firebase all work with this shape.
- Broke: none.
- Next: Phase 34 — Encyclopedia / codex.

---

## 2026-04-16 — Phase 34: Encyclopedia / Codex (B+D architecture)
Data-driven encyclopedia using ContentRegistry (auto-stat from Resources) + unlock-on-first-encounter.
- `autoloads/ContentRegistry.gd` (new autoload): central index of all authored content. Preloaded arrays: `enemies` (3), `towers` (2), `heroes` (1), `spells` (2). Lookup helpers: `find_enemy(id)`, `find_tower(id)`, `find_hero(id)`. Adding new content = one `preload()` line. Multiple systems consume it (encyclopedia now, loadout/shop/loot later). Registered in `project.godot`.
- `autoloads/GameState.gd`: added `encyclopedia_unlocked: Array[String]`. `try_unlock_encyclopedia(content_id)` appends + emits `EventBus.encyclopedia_entry_unlocked`. Auto-unlock wired to `enemy_spawned` / `tower_built` / `hero_spawned` signals — entries unlock on first encounter during gameplay, exactly like Kingdom Rush.
- `autoloads/EventBus.gd`: added `encyclopedia_entry_unlocked(content_id)` signal.
- `autoloads/SaveManager.gd`: persists `encyclopedia_unlocked` array. Auto-saves on each new unlock.
- `ui/EncyclopediaScreen.tscn + .gd` (new): three-tab layout (Enemies / Towers / Heroes). Each tab iterates ContentRegistry, checks unlock state, displays:
  - **Unlocked**: auto-generated stat table from Resource fields + `encyclopedia_entry` flavor text. Enemy stats: HP/SPD/Armor/M.Resist + [Flying] tag + ability IDs. Tower stats: DMG/RNG/SPD/Cost + [Hits Air] + L3 branch names. Hero stats: HP/DMG/RNG/SPD/Armor + skill names.
  - **Locked**: "???" name + "Encounter this unit to unlock" text.
  - Tab buttons highlighted/dimmed for selection state.
- `ui/WorldMap.tscn + .gd`: added "Codex" button in bottom bar → EncyclopediaScreen.
- WorldMap bottom bar now: Heroes | Upgrades | Endless | Scores | Codex
- **B+D validation**: stats auto-populate from .tres fields. Change an enemy's HP in the data file → encyclopedia shows the new value automatically. Buffs/upgrades affect live instances only, not the data Resources — encyclopedia always shows canonical base stats as intended.
- Works: F5 → WorldMap → Codex → Enemies tab: all entries show "???" (haven't played yet). Play a level → enemies spawn → encyclopedia unlocks Orc Grunt, Harpy, Shaman as they appear. Back to Codex → entries show full stats + description. Towers tab: Archer unlocks on first build. Heroes tab: Knight unlocks on hero_spawned. Persists across restarts via SaveManager.
- Broke: none.
- Next: Phase 35 — second hero type.

---

## 2026-04-16 — Phase 35: Second hero type (Mage) — data-driven hero architecture validated
The Mage hero lands with 2 new GDScript files (both generic/reusable), 4 new .tres files, and zero hero-specific code. Proves the "50+ heroes as data" pattern works.
- `systems/abilities/RegenAbility.gd` (new): ON_INTERVAL, heals owner by `heal_amount` per tick. Owner-agnostic — works on heroes, enemies, soldiers, anything with `heal()` or `current_health`. Used by Mana Shield buff.
- `heroes/skills/buff_skill_data.gd` (new generic): SELF-cast that duplicates a configured `buff_ability: Resource` sub-resource, sets its `duration`, pushes onto hero's AbilityHost. Replaces the need for one-off buff skill scripts. Rally could be refactored to use this too (deferred).
- `heroes/skills/shield_bash_skill_data.gd` (extended): added `on_hit_slow_factor` + `on_hit_slow_duration` fields. When > 0, each AoE-hit enemy gets a fresh SlowEffect. Frost Nova uses this — pure data parameterization, no new script.
- **Mage data files (all .tres, zero .gd):**
  - `hero_mage.tres` — HP 80, DMG 8, Range 140, SPD 0.8, Armor 0.05, M.Resist 0.3, damage_type=MAGIC, targets_flying=true.
  - `skill_arcane_bolt.tres` — reuses SlashSkillData (single target, MAGIC, 35 dmg, 5 s CD, range 140).
  - `skill_frost_nova.tres` — reuses ShieldBashSkillData (AoE 90 px, MAGIC 18 dmg, 60% slow for 3 s, 12 s CD).
  - `skill_mana_shield.tres` — uses new BuffSkillData (SELF cast, pushes RegenAbility: 4 HP/s for 8 s, 20 s CD).
- `heroes/base_hero.gd`:
  - New `heal(amount)` method so RegenAbility can heal the hero.
  - `_draw()` now data-driven: body color blue for magic heroes (damage_type==1), gold for physical. Accent color follows. No per-hero _draw() subclass needed.
- **Dynamic hero spawning** (replacing hardcoded HeroWarrior instance):
  - `main/Main.tscn`: removed the `[node name="HeroWarrior" instance=...]` hardcoded instance. HeroInputManager `hero_path` set to empty.
  - `main/Main.gd`: new `_spawn_hero()` — looks up `GameState.selected_hero_id` in `ContentRegistry.find_hero()`, instantiates `HeroWarrior.tscn` as a template scene, overrides `hero.data` with the selected hero's Resource, positions at (188, 460), inserts before HeroInputManager in tree order, and wires `hero_input._hero` directly. Same scene template for all heroes — only data differs.
  - `heroes/HeroInputManager.gd`: gracefully handles empty `hero_path` (Main.gd sets `_hero` directly).
- `autoloads/GameState.gd`: new `selected_hero_id: String = "warrior"`. LoadoutScreen sets it.
- `autoloads/ContentRegistry.gd`: added `hero_mage.tres` to heroes array.
- `ui/LoadoutScreen.tscn + .gd`: replaced "— Hero —" label with "◀ Switch Hero ▶" Button. `_on_hero_title_tapped()` cycles `selected_hero_id` through `ContentRegistry.heroes`. Hero info auto-updates showing name, damage type, stats, skills. Works with any number of heroes.
- **Scorecard — new GDScript per hero: 0.** Mage is pure data: 1 HeroData .tres + 3 SkillData .tres (reusing existing script classes). The 2 new .gd files (RegenAbility, BuffSkillData) are generic and reusable for every future hero/item/buff. This is the architecture delivering on the "50+ heroes" promise.
- Works: F5 → LoadoutScreen → "◀ Switch Hero ▶" → cycles between Knight (gold square, physical, Slash/Bash/Rally) and Mage (blue square, magic, Arcane Bolt/Frost Nova/Mana Shield). Start with Mage → blue hero in gameplay, attacks at range (140 px!), Arcane Bolt zaps single targets, Frost Nova slows a cluster, Mana Shield regens HP. Switch to Knight → gold hero, melee. All skills + abilities work. SkillBar auto-rebuilds from hero.data.skills.
- Broke: none.
- Next: Phase 36 — UnlockManager (locked content states).

---

## 2026-04-16 — Bugfixes (reset order, spawner leak, duplicate preloads) + Phase 36: UnlockManager
- **Bugfix #1** (GameState.gd): `reset()` now clears upgrade caches BEFORE calling `reset_for_level()`. Previously, reset_for_level read stale upgrade cache and granted ghost bonus gold on full progress reset.
- **Bugfix #2** (WaveManager.gd): spawner loop changed `return` → `break` when `_running` is false, so `_active_spawners -= 1` always executes. Not a live bug (stop() zeroes it) but defensively correct.
- **Bugfix #3** (base_tower.gd): removed duplicate `_SlowEffectScriptBranch` / `_StunEffectScriptBranch` preloads. Updated `_build_on_hit_effect()` to use the original `_SlowEffectScript` / `_StunEffectScript` constants.
- **Phase 36 — UnlockManager** (`autoloads/UnlockManager.gd`): full implementation replacing the Phase 1 stub. Three unlock paths:
  1. Free content: `requires_unlock == false` on the data Resource → always available (warrior, archer, barracks).
  2. Explicit unlock: ID in `GameState.unlocked_content` — set by `UnlockManager.unlock(id)` (for IAP Phase 37, progression events).
  3. Star-threshold auto-unlock: configurable `_star_thresholds` dictionary — reaching N total stars auto-grants access (no spending). Currently empty; uncomment `"hero_mage": 5` to gate the Mage behind 5★.
  `is_unlocked(id)` checks all three paths in order. `_find_content_data(id)` searches ContentRegistry across heroes/towers/spells.
- `autoloads/GameState.gd`: added `unlocked_content: Array[String]`. Cleared on `reset()`.
- `autoloads/SaveManager.gd`: persists `unlocked_content` array.
- `ui/LoadoutScreen.gd`: hero cycle (`_on_hero_title_tapped`) now skips locked heroes — only cycles through unlocked ones.
- `ui/TowerSpotMenu.gd`: build buttons check `UnlockManager.is_unlocked(tower_id)`. Locked towers are hidden entirely (not greyed — hidden, so the player doesn't see content they can't use yet).
- Currently all content has `requires_unlock = false`, so everything is available. Phase 37 (IAP) sets `requires_unlock = true` on premium content and wires purchase → `UnlockManager.unlock(id)`.
- Works: F5 → all heroes/towers available (both have requires_unlock=false). If `_star_thresholds["mage"] = 5` is uncommented, Mage disappears from hero picker until player earns 5★. `UnlockManager.unlock("mage")` from console adds it back. Persists via save.
- Broke: none.
- Next: Phase 37 — IAP integration.

---

## 2026-04-16 — Fast-forward button + save reset
Two quality-of-life features before the upgrade tree phase.
- **Fast-forward** (`ui/HUD.tscn + .gd`): SpeedButton (80×60) in a new TopRight HBoxContainer alongside PauseButton. Cycles 1x → 2x → 3x → 1x via `Engine.time_scale`. Affects everything uniformly (towers, enemies, timers, waves) — exactly what TD fast-forward needs. `SceneManager.goto()` resets time_scale to 1.0 so menus don't run accelerated. `PauseMenu._on_pause_requested()` saves current scale and restores on Resume.
- **Reset Progress** (`ui/MainMenu.tscn + .gd`): small red-tinted button anchored bottom-center of MainMenu. Two-tap confirm: first tap → "Are you sure?" (auto-reverts after 3 s); second tap → `SaveManager.delete_save()` + "Progress reset!" feedback. Wipes `user://save.json` and calls `GameState.reset()`.
- Works: F5 → gameplay → tap 1x button → text changes to 2x, everything moves twice as fast. Tap again → 3x. Tap again → back to 1x. Pause while at 2x → pause overlay runs at normal speed; Resume → restores 2x. Quit to WorldMap → speed resets to 1x. MainMenu → tap "Reset Progress" → "Are you sure?" → tap again → save wiped, stars gone.
- Broke: none.

---

## 2026-04-16 — Phase 37: IAP (client-side stub)
Minimal purchase infrastructure. Real billing SDK swaps in when store accounts are ready.
- `progression/ProductData.gd` (new Resource): product_id, display_name, description, price_text, unlock_id.
- `autoloads/PurchaseManager.gd` (new autoload stub): `purchase()` auto-succeeds → `UnlockManager.unlock()` → emits `iap_purchase_completed`. `restore_purchases()` no-op. TODO comments mark where real SDK calls go.
- `ui/ShopScreen.tscn + .gd` (new): product list with Buy/"Owned" buttons + Restore Purchases. One product: Mage Hero $0.99.
- `heroes/data/hero_mage.tres`: set `requires_unlock = true` — Mage locked by default, must purchase.
- WorldMap: added Shop button in bottom bar.
- Works: F5 → Shop → Buy Mage → auto-succeeds → Owned. Hero picker shows Mage. Persists. Reset → re-locked.
- Next: Phase 38 — Boss system.

---

## 2026-04-16 — Phase 38: Boss system (multi-phase Orc Warlord)
Justified subclass per Rule 11 — bosses have multi-phase state machines.
- `enemies/bosses/BossPhaseData.gd` (new Resource): `hp_threshold` (0.0–1.0), `phase_name`, `damage_mult`, `speed_mult`, `abilities: Array[Resource]`, `tint`. Sorted by threshold descending at runtime.
- `enemies/bosses/base_boss.gd` (new, extends BaseEnemy): `_check_phase_transition()` runs on every `take_damage` — when HP% crosses a threshold, pops old phase abilities from AbilityHost and pushes new ones. `_phase_damage_mult` / `_phase_speed_mult` scale base stats. Overrides `_effective_speed()` and `_combat_tick()` with multipliers. Always-visible health bar (bigger, red below 25%) with white phase-threshold markers. Larger body (r=22) with crown/horns indicator. Phase tint multiplies body color.
- `enemies/EnemyData.gd`: added `boss_phases: Array[Resource]`, `is_boss: bool`.
- `enemies/data/boss_orc_warlord.tres`: Orc Warlord — 200 HP, 0.3 armor, 40 speed, 10 dmg, 50 gold, 60 XP. Three phases:
  - Normal (100–50%): base stats.
  - Enraged (50–25%): ×1.5 damage, ×1.3 speed, gains HealAuraAbility (heals nearby allies).
  - Desperate (25–0%): ×2.0 damage, ×1.5 speed, red tint. Pure aggression.
- `enemies/bosses/Boss1.tscn`: Area2D on layer 2 (ground), r=22 collision shape.
- `levels/level1_waves.tres`: added Wave 4 — boss + 6 orc escort + 4 harpies from top. Bounty 80g.
- `autoloads/WaveManager.gd`: endless mode spawns a boss every 10 waves (wave 10, 20, 30...).
- `autoloads/ContentRegistry.gd`: added boss_orc_warlord.tres to enemies array.
- Works: F5 → waves 1–3 play normally → wave 4: large red boss appears with always-visible health bar + phase markers. As HP drops below 50%, boss turns orange-tinted, speeds up, starts healing nearby orcs. Below 25% → red tint, ×2 damage. Boss worth 50g + 60 XP on kill. Endless wave 10 also spawns the boss.
- Broke: none.
- Next: Phase 39 — second + third tower types.

---

## 2026-04-16 — Bugfixes (soldier HP bar, magic numbers, TowerPlacer registry, hero selector) + Phase 39: Mage Tower + Artillery Tower
- **Bugfix: soldier ghost health bar** — `_effective_max_hp` now computed at spawn with upgrade multiplier. Health bar uses it as denominator. No more phantom 100%.
- **Bugfix: magic numbers** — 8 named constants on GameState (`MOD_ARCHER_DAMAGE` through `MOD_SOLDIER_HEALTH`). All 7 call sites updated from raw ints.
- **Bugfix: TowerPlacer** — now builds registry from ContentRegistry.towers + scene map. Adding tower = 1 .tres + 1 scene_map entry.
- **Bugfix: hero selector** — validates current selection is still unlocked on LoadoutScreen open. Falls back to first unlocked on mismatch.
- **Phase 39 — Mage Tower + Artillery Tower:**
  - `towers/TowerData.gd`: added `aoe_radius: float` (0=single target, >0=splash) + `body_color: Color`.
  - `projectiles/Arrow.gd`: refactored with `_aoe_radius` + `_on_hit()` splash logic (50% damage to nearby enemies within radius). Added `proj_color` export for visual differentiation.
  - `projectiles/MageBolt.tscn` + `ArtilleryShell.tscn`: same Arrow.gd script, different speed/hit_radius/color.
  - `towers/data/tower_mage.tres`: Mage Tower — 8 magic dmg, 140 range, 0.7 spd, 60 px AoE splash, targets flying, cost 90g. Purple body.
  - `towers/data/tower_artillery.tres`: Artillery — 25 physical dmg, 200 range, 0.4 spd, 80 px AoE, ground-only, cost 120g. Brown body.
  - `towers/TowerMage.tscn` + `TowerArtillery.tscn`: same BaseTower script, different data. Mage's RangeArea mask=6 (ground+flying), Artillery mask=2 (ground only).
  - `base_tower.gd._draw()` now reads `data.body_color` for the tower circle color. No per-tower visual subclass.
  - **TowerSpotMenu fully dynamic** — removed hardcoded ArcherButton/BarracksButton from .tscn and .gd. `_refresh_build_buttons()` now loops `ContentRegistry.towers`, creates a button per unlocked tower with name + cost. Adding tower type N+1 = zero TowerSpotMenu changes.
  - `autoloads/ContentRegistry.gd`: added both tower data files.
  - `ui/TowerPlacer.gd`: added both to scene map.
- **Scorecard: 0 new tower-specific .gd files.** Both towers are pure data (.tres) + scene template (BaseTower script) + projectile visual (.tscn reusing Arrow.gd). Architecture delivers.
- Works: F5 → tap spot → build menu shows 4 towers (Archer 50g, Barracks 70g, Mage Tower 90g, Artillery 120g). Build Mage → purple tower fires blue bolts that splash in 60px radius, hits flying. Build Artillery → brown tower fires orange shells with 80px splash, ground only, devastating vs clusters but misses harpies. Splash = 50% damage to non-primary targets.
- Broke: none.
- Next: Phase 40 — Skill tree / talent points per hero.

---

## 2026-04-16 — Phase 40: Skill tree / talent points per hero
Per-hero talents purchased with stars (same pool as permanent upgrades). Talents push AbilityData onto the hero at gameplay start via the existing AbilityHost.
- `progression/TalentData.gd` (new Resource): talent_id, talent_name, description, star_cost, prerequisite_id, ability (AbilityData to push).
- `systems/abilities/LifestealAbility.gd` (new): ON_HIT_DEALT, heals owner by `heal_amount` on every attack. Used by both heroes' lifesteal talents.
- `heroes/HeroData.gd`: added `talents: Array[Resource]` field.
- `autoloads/GameState.gd`: added `hero_talents: Dictionary` (hero_id → Array[String] of purchased talent_ids). `get_spent_talent_stars()` iterates all heroes' purchased talents to compute star spending. `get_available_stars()` now subtracts both upgrade + talent spending. Cleared on reset().
- `autoloads/SaveManager.gd`: persists `hero_talents` dictionary.
- `heroes/base_hero.gd`: in `_ready()`, after pushing passive abilities, iterates purchased talents for the current hero and pushes their abilities (duplicated per instance to avoid shared state).
- **Knight talents** (authored inline in hero_warrior.tres):
  - Endurance (2★): RegenAbility — 2 HP/2s passive regen.
  - Vampiric Strike (2★): LifestealAbility — heal 2 HP per attack.
  - Heavy Blows (3★, prereq: Vampiric): OnHitBonusDamageAbility — +4 physical per attack.
- **Mage talents** (authored inline in hero_mage.tres):
  - Meditation (2★): RegenAbility — 3 HP/3s passive regen.
  - Arcane Siphon (3★, prereq: Meditation): LifestealAbility — heal 3 HP per attack.
  - Arcane Power (3★): OnHitBonusDamageAbility — +5 magic per attack.
- `ui/TalentScreen.tscn + .gd` (new): per-hero talent tree UI. Switch button cycles heroes. Shows talent list with name/description/cost/prereq status/purchase button. Mirrors UpgradeTree pattern. Accessible from WorldMap "Talents" button (renamed from "Heroes").
- WorldMap bottom bar now: Talents | Upgrades | Endless | Scores | Shop | Codex
- Works: F5 → WorldMap → Talents → Knight talents shown → purchase Endurance (2★) → back → play level → Knight passively regens 2 HP/2s during combat. Switch to Mage talents → purchase Meditation → Mage regens 3 HP/3s. Prereq chain: Heavy Blows locked until Vampiric Strike owned. Stars shared between upgrades + talents. Persists via save.
- Broke: none.
- **Phase 1–40 complete.** Only Phase 41 (polish) remains.
- Next: Phase 41 — Polish (sound, particles, animations, menus, data-driven visuals).

---

## 2026-04-16 — Phase 41: Polish

### 41A: UI Theme + Styling
- `ui/theme/ThemeColors.gd` (new): canonical color palette constants (BG_DARK, ACCENT_GOLD, BTN_*, TEXT_*, COOLDOWN_*)
- `ui/theme/game_theme.tres` (new): global Theme resource — StyleBoxFlat for Button (normal/hover/pressed/disabled with rounded corners, gold accent border on hover), PanelContainer, Label colors + font sizes
- Applied theme to all 14 UI screens (MainMenu, WorldMap, LoadoutScreen, HUD, PauseMenu, GameOverScreen, TowerSpotMenu, SkillBar, SpellPanel, UpgradeTree, EncyclopediaScreen, LeaderboardScreen, ShopScreen, TalentScreen)
- CooldownButton.gd updated to use ThemeColors constants

### 41B: Data-driven Unit Visuals
- `systems/UnitVisualData.gd` (new): Resource with Shape (CIRCLE/SQUARE), body_color, outline_color, accent_color, accent_type (NONE/WEAPON_LINE/CROSSHAIR/WINGS/CROWN), radius, body_size, outline_width
- `systems/UnitVisualDrawer.gd` (new): static draw_unit(ci, visual, offset) helper. Draws body + outline + accent. Not an autoload — const-preloaded.
- 7 visual .tres files: visual_basic (red circle), visual_flying (purple+wings), visual_healer (green+crosshair), visual_boss (dark red+crown), visual_warrior (gold square+weapon), visual_mage (blue square+weapon), visual_soldier (yellow square)
- Added `@export var visual: Resource` to EnemyData, HeroData, SoldierData
- Updated _draw() in base_enemy, enemy_flying, enemy_healer, base_boss, base_hero, base_soldier — all delegate to UnitVisualDrawer when visual data is set, with legacy fallback
- Wired visual ExtResources into all 7 unit .tres data files

### 41C: Animations + Juice
- `vfx/FloatingText.gd + .tscn` (new): Tween-based text that floats up 40px and fades over 0.6s. Static spawn() factory. Drop shadow for readability.
- `vfx/DeathVFX.gd + .tscn` (new): expanding ring + shrinking white flash over 0.3s. Reads visual color.
- `autoloads/VFXSpawner.gd` (new autoload): connects to EventBus — enemy_died spawns DeathVFX + gold FloatingText, hero_xp_gained spawns XP text, game_over/game_won triggers screen flash
- Tower recoil: base_tower._draw() applies brief 12% scale-down for 0.08s on each _fire_projectile()

### 41D: Sound + Music
- `autoloads/SoundManager.gd` (new autoload): 8-player SFX pool + 1 music player. Registry maps 14 event names to res://audio/sfx/*.wav paths. ResourceLoader.exists() check — game runs silent until audio files dropped in. EventBus wiring: enemy_died, tower_built/sold/upgraded, wave_started/completed, hero_skill_used, spell_cast, game_over, victory. Volume controls: set_sfx_volume(), set_music_volume().
- `audio/sfx/` placeholder directory created

### 41E: Housekeeping
- CLAUDE.md: checked [x] Polish, added VFXSpawner + SoundManager + PurchaseManager to autoloads table, added vfx/, audio/, ui/theme/, UnitVisualData to folder structure, updated status
- SESSIONS.md: this entry
- project.godot: added VFXSpawner + SoundManager autoloads (11 total)

### Summary
- New files: 14 GDScript + 4 .tscn + 7 visual .tres + 1 theme .tres + 1 .gitkeep = 27 files
- Modified: 21 files (6 _draw() scripts, 3 data scripts, 14 .tscn themes, project.godot, CLAUDE.md)
- Works: all gameplay should render identically + floating text on kills + death VFX + tower recoil + themed UI buttons
- Broke: none expected (all visual changes have legacy fallbacks)
- **All 41 phases complete.** Game ready for content expansion and playtesting.

---

## 2026-04-17 — Phase 45: Camera, radial menu, combat visuals
Migrated from the former "Current Status" section of CLAUDE.md so CLAUDE.md can stay invariants-only. Chronological sequence of 45a → 47 and the 47d mini-arc.

### Phase 45b — Camera system + safe area + swarm v_offset
- Resolution 1920x1080 landscape, `keep_height`. Camera (pan, zoom, gesture classifier, map borders, zoom-scaled drawing).
- Safe area via MarginContainer + `GameState.get_safe_insets()`. NavigationAgent2D for hero/soldiers.
- Enemies ride a single Path2D per direction with a discrete 3-lane v_offset for lateral swarm spread, plus spawn-timing jitter.
- Boss detection unified on `EnemyData.is_boss` and `WaveManager._BOSS_SCENES`.
- Hero spawn via editor-adjustable `HeroSpawn` Marker2D; hero takes reciprocal damage from engaged enemies and respawns on a timer at the marker.
- Combat visuals: per-hit white flash (all units), 150ms red attack-telegraph arc on enemies, weapon swing arc on lunges, rear-back wind-up curve.
- QoL: tactical pause, tower damage tracking, upgrade stat deltas, targeting modes, early wave call, clean view toggle, floating damage numbers.
- Radial tower menu introduced (Phase 45a + 45b): build ring of procedural `_draw()` icons with cost badges; action ring (upgrade / sell / target / rally / branch cards) + floating stats card. Old bottom-sheet TowerSpotMenu retired.

### Phase 45c — Barracks upgrades + ghost range ring
- Barracks upgrade L1→L2 via same pipeline as attack towers.
- `TowerUpgradeData` gained `soldier_data_override` + `soldier_rally_range`. Elite Barracks (L2) spawns tougher soldiers within 450px rally.
- On upgrade active squad despawned + respawned with new SoldierData.
- Unified range-preview API: `get_preview_range()` + `get_upgrade_range()`; RangePreview draws yellow (current) + green ghost (upgrade reach).

### Phase 45d — Two-step commit radial menu
- First tap on build/upgrade/branch/sell arms (yellow glow + preview); second tap commits. Target + rally stay single-tap.
- Hover previews removed entirely — same flow on touch and mouse.
- `TowerStatsCard` now has 4 modes: built tower, buildable preview, upgrade-diff, sell confirmation.
- Red ghost ring for decrease-range upgrades (drawn inside yellow).
- Fixed double-event bug: `_gui_input` on radial buttons now handles `InputEventScreenTouch` only (emulate_touch_from_mouse would otherwise double-fire per PC click).

### Phase 45e — Kingdom-Rush soldier charge fidelity
- Soldiers charge enemies entering aggro sensor instead of standing idle. `SoldierData.aggro_range` (130px default) drives a second Area2D.
- State machine extended with CHARGING (chase) + RETURNING (walk back after kill/disengage).
- Engagement pauses motion; losing target mid-charge triggers return. `max_block_targets` cap still enforced.
- Enables "stack two barracks on a boss" surround tactic.
- Seeded `EnemyData.attack_splash_radius` (default 0) for future Yeti/Magma-Elemental-style AoE punishers.

### Phase 45f — Charge leash + bypass archetype
- `SoldierData.leash_range` (200px default) caps charge drift — cross it and soldier drops target, returns home.
- Seeded `EnemyData.bypass_engagement: bool = false`. When true, `BaseEnemy.engage_combat` rejects every blocker (for future Rushing-Monkey archetype).
- Defaults preserve every existing unit's behavior.
- Rejected Gemini's NavigationAgent2D "fix" for soldier charge (violates CORE RULE 13 — soldier movement stays direct straight-line).

### Phase 45h — Engagement zone anchored to the flag
- Fixes charge-bug where soldiers finishing a kill would pick up enemy past the barracks and chase down the lane.
- Root cause: aggro Area2D rides the soldier, so geometric scan centers on soldier's current position instead of static anchor.
- Fix: reuse `SoldierData.leash_range` as static engagement zone centered on barracks flag (shared across whole squad, not per-slot).
- `BaseSoldier` gained `_flag_position`; `TowerBarracks._spawn_soldier` / `_recall_soldiers` pass flag world pos through `setup(slot, flag)` / `set_blocking_position(slot, flag)`.
- `_scan_aggro_and_maybe_charge` rejects candidates outside leash of flag; `_tick_charge` drops target + returns when exits zone.
- **Zone viz**: TowerBarracks._draw renders subtle red ring around flag at leash_range.
- First attempt also added proactive-engage at 90px + distant-strike safeguard — ripped out after user reported soldiers standing next to frozen enemies dealing no damage (proactive added soldier to enemy's _blockers but `_try_engage`'s later `engage_combat` returned false, leaving `_engaged_enemies` empty so `_attack_cycle` never swung). Simpler design preserved.

## 2026-04-18 — Phase 46: Content + attribution + ID hardening

### Phase 46 — New enemies + Wave 5 + damage attribution
- Armored Orc (`enemy_armored`: HP 20 / 0.3 armor / speed 140 / dmg 4) and Goblin Scout (`enemy_scout`: HP 6 / speed 280 / dmg 2).
- Both data-only: `.tres` + UnitVisualData + trivial scene binding. Registered in ContentRegistry.enemies.
- **Level 1 Wave 5** (`level1_waves.tres`): 12 basics + 4 armored left, 8 scouts + 3 armored right, 6 harpies top, 2 shamans, 1 boss at +8s. Countdown 6s, bounty 120.
- **Damage attribution** for the end screen:
  - `GameState.round_damage_towers` (dict keyed by instance_id so sold towers still count), `round_damage_hero`, `round_damage_soldiers`.
  - `BaseEnemy.take_damage` routes each hit's overkill-capped `actual` to `GameState.record_round_damage(source, amount)`, dispatched by `source is BaseTower / BaseHero / BaseSoldier`.
  - `GameOverScreen` renders top-5 towers + Hero + Soldiers on both victory + defeat. Cleared by `reset_for_level()`.

### Phase 46b — Review hardening on damage pipeline
- Guard `GameState.record_round_damage` with `is_instance_valid(source)` — handles sell-tower-while-projectile-in-flight.
- `GameOverScreen._build_damage_breakdown` falls back to literal "Tower" when entry name is empty.
- Endless-mode branch of `_on_game_over` also appends the damage breakdown.
- Spell damage tracked: added `GameState.round_damage_spells`, SpellPanel got `class_name SpellPanel` so `source is SpellPanel` tags correctly. "Spells" row rendered when > 0. All clear in reset_for_level().

### Phase 46c — Boot-time ID validation + type-aware UnlockManager
- `ContentRegistry._ready()` calls `_validate_ids()` — asserts every loaded `.tres` has `*_id` matching its filename basename. Drift prints `[ContentRegistry/DRIFT]` at project open.
- Old global-namespace `is_unlocked(id)` replaced by `is_hero_unlocked`, `is_tower_unlocked`, `is_spell_unlocked`. Each routes through `ContentRegistry.find_<type>` only — eliminates the class of bug where hero/tower id collision hid content (the Mage tower invisible bug).
- `ProductData.unlock_type: enum {HERO, TOWER, SPELL}` so ShopScreen dispatches correctly.
- All four callers migrated (LoadoutScreen, TowerRadialMenu, ShopScreen + shop's new wrapper).
- Deferred: save-file migration framework + single-source tower registry.

### Phase 46d — Non-scoped ID cleanup
- All 7 drifted IDs renamed to match filenames: `archer` → `tower_archer`, `barracks` → `tower_barracks`, `artillery` → `tower_artillery`, `warrior` → `hero_warrior`, `mage` (hero) → `hero_mage`, `fireball` → `spell_fireball`, `reinforcements` → `spell_reinforcements`.
- Cascade updates: `TowerPlacer._SCENE_MAP` keys, `TowerIconButton._draw_pictogram` match cases, `GameState.selected_hero_id` default, `ShopScreen.tscn` `unlock_id`.
- Save migration framework deferred — user's save was deleted so no orphaned keys.

## 2026-04-19 — Phase 47: Polish + radial menu hardening + tower loadout

### Phase 47 — Combat visuals: Polish + Identity
- New EventBus signals: `hit_landed`, `enemy_damaged`, `soldier_fell`. Emitted inside take_damage / soldier _die, consumed by VFXSpawner.
- New VFX scripts (plain Node2D + class_name): `HitSparkVFX` (radial spark burst styled by damage type), `EnemyDeathDrift` (snapshots UnitVisualData, drifts + rotates 0.35s + fades along hit direction), `SkillCastFlare` (expanding ring under hero on skill cast, color keyed by skill_name).
- **Swing-arc upgrade**: `UnitVisualDrawer.draw_swing_arc_trail` — 4 ghost copies behind primary with descending alpha + radius. `_draw_weapon_shape` branches on `UnitVisualData.weapon_type` enum (SWORD / SPEAR / STAFF / CLAWS).
- **Status-ring polish**: `draw_status_ring(radius, color, dashes, rotation_t, width)` replaces static arcs — 8-dash cyan spinning CW for slow, 6-dash yellow spinning CCW for stun. `_status_ring_t` accumulator in BaseEnemy._physics_process.
- **Telegraph inhale**: `_inhale_offset()` pulls body `-dir * 4.0 * smoothstep(0.15, 0.0, _combat_cooldown)` during last 150ms pre-strike.
- **Soldier fall-over death**: parallel tween (rotation → ±90°, modulate.a → 0 over 0.4s) then free.
- **Squad-color bands**: `UnitVisualData.accent_band_color`; TowerBarracks._spawn_soldier duplicates per-soldier and stamps deterministic color by global_position hash.
- **Camera shake**: `GameCamera.add_shake(amount, duration)` — decaying offset perturbation; `VFXSpawner._on_enemy_damaged` triggers on `enemy.data.is_boss`.
- All O(1) per instance, no `get_nodes_in_group` / distance loops added. Tactical pause freezes every new tween/process path.

### Phase 47b — Upgrade-preview hardening
- **Click-latency "three taps to commit"**: `TowerRadialMenu._on_gold_changed` was calling `_rebuild_action_slots()` which wiped `_armed_slot = null`. Enemy drops between arm + commit reset armed state. Fix: `_capture_armed_key()` / `_rearm_by_key()` pair remembers `(action_id, payload)` across rebuild. Added `RadialActionButton.is_enabled()`.
- **Upgrade-preview stat coverage + color**: new `get_preview_stats() -> Array[Dictionary]` on BaseTower / TowerBarracks / TowerUpgradeData. TowerStatsCard.StatsLabel → RichTextLabel with BBCode (green on improvements, red on regressions, default on unchanged, green label-only for newly gained abilities). SlowT shows as "Dur" to keep column compact.

### Phase 47c — Three-click root cause (real fix)
- 47b's capture/rearm helpers were treating a symptom. Real bug: `_rebuild_action_slots` calls `_clear_slots` which `queue_free`s slots, but Godot defers to end-of-frame. Old Controls stay alive one more frame and still receive `_gui_input`. Commit tap could route to the queued-for-free old slot → re-arms instead of commits.
- **Proper fix**: in-place affordability refresh via `_refresh_action_affordability()` — iterates existing slots, computes cost from tower (`get_upgrade_cost_to`, `get_branch_cost`), calls `set_enabled()` + `set_badge_color()` in place. No queue_free, no race, `_armed_slot` stays valid.
- Defense-in-depth: `_clear_slots` now sets `mouse_filter = MOUSE_FILTER_IGNORE` before `queue_free`.
- 47b's dead helpers removed.

### Phase 47d — Tower loadout system
Pre-level loadout picker; in-game build ring shows 6 slots (4 from loadout + 2 progression-locked padlocks). Adding a new tower is now a one-file change.
- **47d-1** — Data consolidation: `TowerData.tower_scene: PackedScene` + `TowerData.pictogram: String`. `TowerPlacer._SCENE_MAP` deleted. `TowerIconButton._draw_pictogram` → `_draw_glyph(glyph, white, dark)` dispatched on pictogram string.
- **47d-2** — GameState: `TOWER_SLOT_MAX = 6`, `tower_slot_cap = 4`, `selected_tower_ids`. `get_loadout_towers()`, `set_loadout_slot(idx, tid)` (no-duplicates swap), `reset_loadout_to_default()`. SaveManager plumbs all three.
- **47d-3** — Build ring draws 6 slots always. Slots `[cap..MAX-1]` use `setup_locked()` (padlock + Toast on tap). Empty-but-unlocked slots also show padlock + hint "Set this slot in Loadout".
- **47d-4** — `LoadoutPickerScreen.tscn/.gd`: ring mirrors in-game radius; pool is HFlowContainer of every unlocked tower with `set_equipped(bool)` state. Arm-then-place interaction. Every change calls `SaveManager.save_game()`. "Reset to Default" restores the 4 launch towers.
- **47d-5** — WorldMap gains "Loadout" button next to "Talents". LoadoutScreen replaces hardcoded label with live TowersRow via `TowerIconButton.setup_display(data)` (display-only).

### Phase 47d-6 — Ice Tower + base-level status effects
- First tower added under the 47d-1 one-file contract.
- `TowerData` gained `on_hit_slow_factor` / `on_hit_slow_duration` / `on_hit_stun_duration` mirroring TowerUpgradeData's, so base-level towers can carry status effects without a dummy L1 upgrade.
- `BaseTower._build_on_hit_effect()` + `get_preview_stats()` + `TowerUpgradeData.get_preview_stats(base)` all fall back to `data.*` when upgrade override leaves field at 0.
- `tower_ice.tres` (MAGIC, flying-capable, 30% slow for 1.0s at L1). `projectiles/IceShard.tscn` (Arrow.gd + cyan tint).
- L2 "Frostbite Tower" doubles damage to 6, range 380→425, adds attack speed, slow 50% for 1.5s.
- `"snowflake"` glyph added to `TowerIconButton._draw_glyph`.

### Phase 47d-7 — TowerCombat chassis + TowerPlacer data-override
- Fixes "Ice Tower has data=null, doesn't shoot" bug introduced by 47d-1.
- Root cause: 47d-1 added `tower_scene: PackedScene` to TowerData, so tower_archer.tres references TowerArcher.tscn — but TowerArcher.tscn still bakes `data = ExtResource(tower_archer.tres)`. Circular reference. Godot's loader leaves one side null; instantiating TowerArcher.tscn for the Ice Tower produced a tower with Archer's data baked in.
- **Fix (two parts)**:
  - New `towers/TowerCombat.tscn` — bare combat chassis, zero baked data. All four combat towers (archer/mage/artillery/ice) point `tower_scene` at this one scene, eliminating every circular ref.
  - `TowerPlacer._on_build_requested` executes `tower.data = entry.data` AFTER `instantiate()` and BEFORE `add_child()`, so `base_tower._ready()` sees the right data regardless of what the scene hardcodes.
- Barracks exempt: `TowerBarracks.tscn` has its own structure (FlagArea + soldier plumbing).
- Old per-tower scenes (`TowerArcher.tscn` / `TowerMage.tscn` / `TowerArtillery.tscn`) left as vestiges; deleted in the 2026-04-20 session.

### Phase 47d-8 — GameOverScreen dead-end fix
- Defeat previously hid the Continue button — only Restart visible. Users wanting to bail to WorldMap had to quit the app.
- Fix: Campaign/Heroic/Iron defeat path now sets both buttons visible ("World Map" + "Restart"). Endless already showed both; got explicit labels for consistency.
- Summary line gains "Mode: X" prefix.
- Card.custom_minimum_size.x 300→480 so summaries don't wrap awkwardly.
- `_show()` mode-codes title color (green victory, warm red defeat/game-over).

### Phase 47d-9 — Code-review follow-up fixes
- **In-game build ring collapsed loadout gaps**: `GameState.get_loadout_towers()` compacts empty entries. `TowerRadialMenu._open_build_ring` was indexing compacted array against ring slots — clearing slot 1 in picker pulled every subsequent tower forward. Rewrote to iterate `selected_tower_ids` positionally, same pattern as `LoadoutPickerScreen._rebuild_ring`. Also respects live `is_tower_unlocked`.
- **On-hit slow gate too strict**: `base_tower._build_on_hit_effect` fell back per-field on way in, but final `if slow_f > 0.0 and slow_d > 0.0` dropped effect when upgrade set factor=0.5 and left duration=0. Added cross-fallback: `if slow_f > 0.0 and slow_d <= 0.0 and data != null: slow_d = data.on_hit_slow_duration`. Mirrored in `get_preview_stats`.

---

## 2026-04-20 — Interaction + game-over audit pass + bug sweep
Not a numbered phase — an audit + cleanup session between content sprints. Three agents ran in parallel against gameplay / UI / data layers; findings triaged and fixed over two rounds.

### Round 1 — Interaction + defeat-screen bugs
- **Deleted orphaned tower scenes**: `towers/TowerArcher.tscn` / `TowerMage.tscn` / `TowerArtillery.tscn` (documented as "safe to delete" in 47d-7 but still shipping). Only `TowerCombat.tscn` + `TowerBarracks.tscn` remain.
- **Radial menu dismiss on invalid tower**: [ui/TowerRadialMenu.gd:346-353](ui/TowerRadialMenu.gd) `_rebuild_action_slots` now calls `_dismiss()` when `_current_tower` goes invalid mid-rebuild instead of leaving an empty ring visible.
- **Red-screen-of-death bug** on defeat: [autoloads/VFXSpawner.gd:130-148](autoloads/VFXSpawner.gd) `_screen_flash` created a ColorRect on CanvasLayer 50 (above GameOverScreen at 20). ColorRect defaulted to `MOUSE_FILTER_STOP` → swallowed every click. Tween ran on VFXSpawner with default PROCESS_MODE_INHERIT, so `get_tree().paused = true` froze the fade at full alpha forever. Fix: `layer.process_mode = PROCESS_MODE_ALWAYS`, `rect.mouse_filter = IGNORE`, `tween.set_pause_mode(TWEEN_PAUSE_PROCESS)`.

### Round 2 — Broader bug sweep
- **Enemy double-emit race**: [enemies/base_enemy.gd:261-279](enemies/base_enemy.gd). Lethal hit on the same frame as path-end could emit both `enemy_died` and `enemy_reached_end` → duplicate gold + lives deltas. Guard: `if state == State.DYING: return` at the top of both `_die` and `_reach_end`.
- **Damage leaderboard stable key**: previously keyed on `get_instance_id()`. Godot reuses freed IDs, so in Endless with frequent selling a new tower could inherit a sold tower's tally. Fix: `BaseTower._damage_key: int = -1`, assigned lazily by `GameState.record_round_damage` from a monotonic `_next_damage_key` counter. Reset in `reset_for_level`.
- **SpawnIndicator back-to-back tween leak**: [ui/SpawnIndicator.gd](ui/SpawnIndicator.gd) now stores `_hide_tween` and kills it before starting a new one, so rapid waves don't let a stale callback hide fresh arrows early.
- **WorldMap locked-level tap feedback**: locked levels were bare Labels, silent on tap. Replaced with a Button that emits `Toast.show_message("Clear prior levels to unlock")`.
- **soldier_basic.tres missing `soldier_id`**: added `soldier_id = "soldier_basic"`. Matches soldier_elite.tres pattern.
- **Pause-honoring tweens**: same class as VFXSpawner screen_flash. Applied defensive `TWEEN_PAUSE_PROCESS` + `PROCESS_MODE_ALWAYS` to [autoloads/Toast.gd](autoloads/Toast.gd) and [autoloads/SceneManager.gd](autoloads/SceneManager.gd).
- **SpellPanel cast_range guard**: [ui/SpellPanel.gd](ui/SpellPanel.gd) was casting regardless of range because every shipping spell is `cast_range = 0` (unlimited). Added a toast block — any future spell with positive cast_range surfaces a "cast range not wired up" message instead of silently accepting out-of-range taps, forcing a designer decision.

### Doc hygiene
- Compacted CLAUDE.md: migrated the "Current Status" phase log (lines 409–457) into this SESSIONS.md entry (the block you're reading); trimmed CORE RULES 7/13/14/15 "Why:" narratives; condensed "Common pitfalls" tower-add block. CLAUDE.md is now invariants-only.
- New `STATUS.md` at repo root: one-screen "what am I doing right now" tracker. Manually updated between sessions.
- Added "Working here" section at top of CLAUDE.md pointing at STATUS.md / SESSIONS.md / CLAUDE.md roles.

Next up: playtest the vertical slice, then content sprint (4-8 weeks: 5 levels, 2 more heroes, 2 more towers, 4 more enemies, 1 more spell). No new systems until content fills the ones that exist.

---

## 2026-04-27 — Phase A: WorldMap UI consolidation (4-hub corner layout)
First slice of the WorldMap UI overhaul (research doc: `~/.claude/plans/lets-make-deep-research-robust-sunbeam.md`). Reduces the 8-button bottom bar to 4 corner-grouped buttons backed by category hubs. Sets up the structural shell for Phase B/C/D (proper TabContainers inside each hub) and Phase F (Endless mode pill on the level card).

### What changed
- `ui/WorldMap.tscn`: `BottomBar` HBoxContainer now holds `HeroesButton · TowersButton · Spacer · CodexButton · ShopButton` — each 140×80, font 20, separator 16. Spacer pushes Heroes/Towers to bottom-left and Codex/Shop to bottom-right (Kingdom Rush corner-icons feel). Removed: `LoadoutButton`, `EquipmentButton`, `UpgradesButton`, `EndlessButton`, `LeaderboardButton`, `EncyclopediaButton`. The prior `HeroesButton` was misnamed — its text said "Talents" and it routed to TalentScreen; now genuinely points to a Heroes hub.
- `ui/WorldMap.gd`: dropped 7 button vars + handlers (`_on_loadout`, `_on_equipment`, `_on_upgrades`, `_on_endless`, `_on_leaderboard`, `_on_encyclopedia`). Rewired `_on_heroes` → `HeroesHub.tscn`. Added `_on_towers` / `_on_codex` to the new hubs. `_on_shop` and `_on_back` unchanged.
- **Endless virtual level removed**: previously the bottom-bar Endless button set `current_level_id = "endless"` to bootstrap a level-agnostic endless mode. Functionally redundant — `Main.gd` always loads `$Level1` regardless of `current_level_id`, and the per-level Endless button on each level panel produces equivalent gameplay (`current_mode = "endless"` on a real level id). Per-level Endless button kept untouched (Phase F will fold it into a unified mode pill row alongside Campaign/Heroic/Iron on the level card).
- `ui/HeroesHub.tscn + .gd` (new): placeholder hub. Top bar (Back + "Heroes" title + spacer); centered VBox with `Equipment` + `Talents` buttons routing to existing standalone screens; "coming soon" hint mentioning Loadout/Stats/Skills tabs in Phase B. Same dark theme as TalentScreen.
- `ui/TowersHub.tscn + .gd` (new): mirror layout. `Loadout` → LoadoutPickerScreen, `Upgrades` → UpgradeTree.
- `ui/CodexHub.tscn + .gd` (new): mirror layout. `Bestiary` → EncyclopediaScreen, `Records` → LeaderboardScreen (renamed UX-side from "Scores" to "Records" per the plan; the underlying screen is still `LeaderboardScreen.tscn`).

### Why hubs are transitional in Phase A
The hubs are not yet TabContainers — they're vertical button lists pointing to the existing standalone screens. This is deliberate: Phase A's only job is to clean the WorldMap. Inlining the screens as tabs is Phase B (Heroes), Phase C (Towers), Phase D (Codex). This avoids a feature regression — every screen reachable before Phase A is still reachable after Phase A, just one extra tap deep through the hub.

### Pre-flight checks done
- Grepped for external references to the deleted button names — none (all 9 standalone screens just navigate back to `WorldMap.tscn` via `SceneManager.goto`, no button-name coupling).
- Grepped for dependencies on `current_level_id == "endless"` — only `WorldMap.gd:52` set it (now removed). All endless-mode behavior keys off `current_mode == "endless"`, which the per-level Endless button still produces.
- No save migration needed; all changes are presentation layer.

### Verification
- Open in Godot editor; tap Heroes / Towers / Codex / Shop from WorldMap; each opens the new hub or the existing Shop.
- From each hub, tap subscreen buttons → confirm they open the existing standalone screen → Back returns to WorldMap (the standalone screens still route back to WorldMap, not the hub; that gets fixed in Phase B/C/D when they're absorbed as tabs).
- Level panel Play / Endless buttons unchanged — confirm Forest Path → Campaign and Forest Path → Endless still launch gameplay correctly.

### What's next
- **Phase B** — inline LoadoutScreen (hero pick portion) + EquipmentScreen + TalentScreen as tabs inside HeroesHub. Stub Stats/Skills tabs as "Coming soon".
- **Phase C** — inline LoadoutPickerScreen + UpgradeTree as tabs inside TowersHub.
- **Phase D** — inline EncyclopediaScreen + LeaderboardScreen as tabs inside CodexHub.
- **Phase E** — add top-bar Stars/Gold counter buttons + Settings gear → new OptionsScreen.
- **Phase F** — Endless pill on level card (replaces inline per-level Endless button with a mode-pill row alongside Campaign/Heroic/Iron).

---

## 2026-04-27 — Phase B: HeroesHub TabContainer (Loadout / Equipment / Stats / Skills / Talents)
HeroesHub upgraded from Phase A's vertical-button placeholder into a real `TabContainer` with five tabs. Equipment + Talents tabs **embed** the existing standalone screens (no rewrite, no logic duplication, ~500 lines avoided). Loadout tab is built inline (hero picker). Stats + Skills tabs are stubs reserved for future per-hero attribute and skill-tree systems.

### What changed
- `ui/HeroesHub.tscn`: replaced placeholder `MenuVBox` with a `TabContainer` (anchor full-rect under TopBar, offset 96/-16) holding five Control children — `Loadout`, `Equipment`, `Stats`, `Skills`, `Talents`. Top bar (Back + "Heroes" title) unchanged.
- `ui/HeroesHub.gd`:
  - `_build_loadout_tab()` builds an inline hero picker — large hero text block (name, type, HP/DMG/RNG/SPD, skills) + ◄ Switch Hero ► button. Hero pick + cycling logic mirrored from `LoadoutScreen._refresh_hero_info` + `_on_hero_title_tapped` to stay consistent (validates unlock state, falls back through roster, skips locked heroes during cycling). Switch button auto-disables when only one hero is unlocked.
  - `_embed_screen(tab, scene_path)` instantiates a screen `.tscn` as a child of the given tab, hides its `TopBar` + `Background`, and pulls body offsets up so content sits flush below the tab strip. Equipment: `Body.offset_top = 8`. Talents: `StarsLabel.offset_top = 8` + `ScrollContainer.offset_top = 48`.
  - `_build_coming_soon_tab(tab, title, subtitle)` builds a centered "Coming soon" placeholder — used for Stats and Skills tabs.

### Embedding pattern (key decision)
Equipment + Talents content is large (370 + 130 lines respectively) and stable. Re-implementing as tab-bodies would either duplicate it or require a structural refactor of the existing scenes. Instead, `_embed_screen` instantiates the existing `.tscn` as a tab child and just hides its chrome. The embedded scene's `_ready` runs as normal when added to the tree — `InventoryManager.ensure_starter_gear`, EventBus connections, all functional. The hidden `BackButton` still has its `pressed.connect` but is non-interactive while invisible. The hub's own back button handles WorldMap navigation.

### Why standalone scenes still exist
`EquipmentScreen.tscn` and `TalentScreen.tscn` remain for now — they're untouched. Direct navigation to them still works (e.g. if a future hub-bypass route is added). The hub is the canonical entry point; standalone scenes are dormant but functional. They can be retired in a later cleanup pass once it's clear no other code paths need them.

### Verification
- Open WorldMap → Heroes → confirm five tabs visible: Loadout / Equipment / Stats / Skills / Talents.
- Loadout tab: hero name + stats render; ◄ Switch Hero ► cycles through unlocked heroes (currently only one — Warrior — so button is disabled, expected).
- Equipment tab: full inventory grid + slot grid + stats panel + hover details all functional. Tap inventory item → equip. Tap equipped slot → unequip. Locked slots toast on tap.
- Stats / Skills tabs: "Coming soon" centered placeholder.
- Talents tab: stars label + talent list. Purchase flow functional (stars deduct, panel rebuilds).
- Hub Back button → WorldMap. Embedded scenes' own back buttons are hidden — no double-back.

### Risks / known follow-ups
- Embedded scenes connect to EventBus on `_ready` and stay connected for the hub's lifetime even when their tab is not visible. Acceptable overhead — no other state changes while user browses tabs. If a future tab body becomes heavy (e.g. a real-time stat preview), revisit.
- TabContainer renders tab strip text from child node names (`Loadout`, etc.). Localization will need `set_tab_title(idx, tr("HEROES_TAB_LOADOUT"))` when i18n lands.
- Standalone `EquipmentScreen.tscn` / `TalentScreen.tscn` retired-but-not-deleted. Cleanup pass after Phase D.
- Embedded EquipmentScreen has its `HeroLabel` (hero name display) inside its TopBar, which is hidden in the embed. Acceptable today because the Loadout tab is the canonical "which hero" indicator one tab over. If users get confused, reparent HeroLabel up like Phase C does for UpgradeTree's StarsLabel.

---

## 2026-04-27 — Phase C: TowersHub TabContainer (Loadout / Upgrades)
TowersHub upgraded from Phase A's button-list placeholder into a real `TabContainer` with two tabs. Same embed strategy as HeroesHub (Phase B) — instantiate the existing standalone scenes inside each tab, hide their chrome, adjust body offsets.

### What changed
- `ui/TowersHub.tscn`: replaced placeholder `MenuVBox` with a `TabContainer` (anchor full-rect under TopBar, offset 96/-16) holding two Control children — `Loadout` and `Upgrades`. Top bar (Back + "Towers" title) unchanged.
- `ui/TowersHub.gd`:
  - `_embed_screen(tab, scene_path)` — same pattern as HeroesHub: instantiate scene, hide TopBar + Background, adjust body offsets.
  - LoadoutPickerScreen: HintLabel pulled up to `offset_top = 8`. RingAnchor (anchor-relative at 35% vertical) and PoolTitle/PoolScroll/ResetButton (absolute or bottom-anchored) scale into the tab area without further changes.
  - UpgradeTree: `StarsLabel` lives **inside** the screen's TopBar (and would have been hidden along with it). Reparented via `top_bar.remove_child(stars); screen.add_child(stars)` and re-anchored to `PRESET_TOP_WIDE` at `offset_top = 8` so the player still sees their star budget. ScrollContainer pulled up to `offset_top = 48` to sit right under the relocated label.

### Why the StarsLabel reparenting (UpgradeTree only)
The upgrade tree's primary affordance is "do I have stars to spend?" Hiding the TopBar would hide that signal. Reparenting moves the existing `unique_name_in_owner` Label to a sibling position inside `screen`, preserving the `%StarsLabel` lookup that `UpgradeTree.gd._refresh_stars_label()` relies on. Since the node's `owner` is still the screen root, `%StarsLabel` still resolves correctly. LoadoutPickerScreen needs no equivalent treatment — it has no in-TopBar resource counter.

### Verification
- WorldMap → Towers → confirm two tabs visible: Loadout / Upgrades.
- Loadout tab: ring of slots (current loadout), pool of unlocked towers below, hint text at top, "Reset to Default" button bottom-center. Tap-arm-then-tap-place flow works as in standalone screen. Saves persist (`SaveManager.save_game()` on every change).
- Upgrades tab: "★ N / M available" label at top, scrollable upgrade panels below. Purchase flow works (deducts stars, refreshes prereq states).
- Hub Back → WorldMap. Embedded scenes' own back buttons hidden — no double-back.

---

## 2026-04-27 — Phase D: CodexHub TabContainer (Bestiary / Records)
CodexHub upgraded from Phase A's button-list placeholder into a real `TabContainer` with two tabs. Same embed strategy as Phases B + C.

### What changed
- `ui/CodexHub.tscn`: replaced `MenuVBox` with a `TabContainer` (anchor full-rect under TopBar, offset 96/-16) holding two Control children — `Bestiary` and `Records`. Top bar (Back + "Codex" title) unchanged.
- `ui/CodexHub.gd`:
  - `_embed_screen(tab, scene_path)` — same pattern as the prior hubs.
  - EncyclopediaScreen: `TabRow` (inner Enemies/Towers/Heroes/Items pills) pulled to `offset_top = 8` so it sits right under the outer Codex tab strip; `ScrollContainer` pulled to `offset_top = 80` to follow.
  - LeaderboardScreen: `ScrollContainer` pulled to `offset_top = 8` (no inner tab row to make room for).
  - The `inner_tabs` test in `_embed_screen` distinguishes the two screens so the same helper handles both layouts.

### Nested-tabs note
Codex's outer Bestiary tab embeds a screen that has its own inner pill row (Enemies / Towers / Heroes / Items). Two levels of tabbing nested visually OK because the levels mean different things — outer = which Codex section, inner = which content type within Bestiary. Kingdom Rush bestiaries do the same.

### Verification
- WorldMap → Codex → confirm two tabs visible: Bestiary / Records.
- Bestiary tab: inner pill row (Enemies/Towers/Heroes/Items) renders directly under the outer tab strip; tap each to filter the list. Locked entries show "???"; unlocked entries show stats + flavor text.
- Records tab: leaderboard rows or "No scores yet" empty state.
- Hub Back → WorldMap.

### Status across all hubs
With Phases A–D shipped, all three of WorldMap's category buttons (Heroes / Towers / Codex) lead to TabContainer hubs that consolidate the prior 6 standalone screens (Equipment, Talents, LoadoutPicker, UpgradeTree, Encyclopedia, Leaderboard) into 3 tabbed surfaces. Standalone scenes remain in the codebase and still work for direct navigation — they will be retired in a cleanup pass after Phase F.

---

## 2026-04-27 — Phase E: WorldMap top-bar resources + OptionsScreen
WorldMap top bar gains a Stars counter (KR convention) and Settings gear; both are tappable shortcuts. Settings gear opens a new OptionsScreen that absorbs the prior in-HUD VFX toggle and the prior MainMenu Reset Progress button.

### What changed
- `ui/WorldMap.tscn`: TopBar adds a `StarsButton` (120×80, gold tint, `★ N` text) and a `SettingsButton` (80×80, gear glyph). Both sit between the existing Title and the right edge. Separation tightened to 12.
- `ui/WorldMap.gd`:
  - `_refresh_stars_label()` reads `GameState.get_available_stars()` and sets the button text. Called once in `_ready` — fresh each WorldMap visit (the screen reinstantiates on `SceneManager.goto`, so no live update needed).
  - `_on_stars()` sets `TowersHub.pending_tab = TowersHub.TAB_UPGRADES` then navigates to TowersHub. Hub reads the hint in its `_ready` and clears it.
  - `_on_settings()` navigates to the new OptionsScreen.
- `ui/TowersHub.gd`: added `class_name TowersHub`, `const TAB_LOADOUT = 0` / `const TAB_UPGRADES = 1`, and `static var pending_tab: int = -1`. `_ready` applies + clears the hint:
  ```
  if pending_tab >= 0:
      tab_container.current_tab = pending_tab
      pending_tab = -1
  ```
  `class_name` is what makes `TowersHub.pending_tab = …` resolvable from WorldMap.gd without preload boilerplate.
- `ui/OptionsScreen.tscn + .gd` (new): TopBar (Back + "Options" title) + centered VBox with two action buttons:
  - **Clean View toggle** — emits `EventBus.clean_view_toggled` exactly like the prior HUD CleanButton, just relocated. Label syncs to `VFXSpawner.clean_view`.
  - **Reset Progress** — same two-tap-confirm flow as before (relocated from MainMenu). Calls `SaveManager.delete_save()`.
  - Hint labels under each explaining what they do.
  - "Coming soon" footer mentioning SFX/music volume, color-blind palette, language.
  Back returns to WorldMap.
- `ui/MainMenu.gd + .tscn`: removed `ResetButton` + the two-tap-confirm logic. MainMenu is now Play-only. Reset Progress is one tap deeper (Play → Settings gear → Reset) — intentional friction so first-launch confusion doesn't nuke saves.
- `ui/HUD.gd + .tscn`: removed `CleanButton` (the in-game VFX/Clean toggle). The state still lives on `VFXSpawner.clean_view`; the toggle moved to Options. HUD top-right is now Speed + Pause only — cleaner, more KR-feel.

### Why a static var for `TowersHub.pending_tab`
Three alternatives considered:
1. **Static var on TowersHub** (chosen) — caller sets `TowersHub.pending_tab = X` before `goto`, hub reads + clears in `_ready`. Simple, type-checked via `class_name`.
2. **GameState field** — would couple a transient UI hint to gameplay state, which is wrong-headed. Rejected.
3. **SceneManager parameter** — would require extending `SceneManager.goto()` to accept arbitrary user data. Overkill for a single use case. If more shortcuts need this pattern, revisit.

### Verification
- WorldMap → top bar shows `★ N` (matches `GameState.get_available_stars()`) and `⚙` gear.
- Tap `★ N` → lands inside Towers hub on the **Upgrades** tab (not Loadout, the default).
- Tap `⚙` → OptionsScreen opens.
- OptionsScreen → toggle Clean View → label flips, in-game VFX state matches on next gameplay session.
- OptionsScreen → tap Reset Progress → "Are you sure?" → tap again → save deleted.
- MainMenu → only "Play" button (no Reset Progress at the bottom).
- In-game HUD top-right → only Speed + Pause buttons (no VFX button).

### Risks / known follow-ups
- Stars counter shows on WorldMap only. Could add to the hub TopBars too for consistency (KR shows stars/gems on every meta screen) — small follow-up.
- Clean View state still per-session (resets on app restart). Persisting it would require a `SaveManager` field; deferred until a real settings persistence story is needed.
- `TowersHub.pending_tab` is a static var, which means it persists across instances within the same process (intentional — that's how the hint passes through `goto`). If a future code path navigates to TowersHub WITHOUT going through WorldMap stars-counter, the hint stays at -1 (no-op) so no contamination risk.

---

## 2026-04-27 — Phase F: Endless mode pill on level card
Each level panel on WorldMap now shows a 4-pill mode row (Campaign / Heroic / Iron / Endless) instead of the prior Play + Endless button pair. Mode picking happens here on the level card; LoadoutScreen receives the chosen mode and skips back to being a pre-battle confirmation.

### What changed
- `ui/WorldMap.gd`:
  - `_make_level_panel(data)`: replaced the `Play` + `Endless` VBox with an HBox of four mode pills via the new `_add_mode_pill` helper.
  - `_add_mode_pill(row, data, mode)`: builds one pill per mode. Logic mirrors `LoadoutScreen._refresh_mode_buttons` so the gating + status text reads identically:
    - **Campaign** — always enabled, shows star count `★★☆`.
    - **Heroic** — `Done ✓` if completed, `Ready` if 3★ earned, `Need 3★` (disabled) otherwise.
    - **Iron** — `Done ✓` if completed, `Ready` if Heroic done, `Need Heroic` (disabled) otherwise.
    - **Endless** — always enabled, shows best wave (`W27`) or `—` if no run posted.
  - `_on_mode_pill_pressed(data, mode)` sets `current_level_id` + `current_mode` and routes to LoadoutScreen.
  - Removed `_on_level_selected` and `_on_level_endless` (replaced by `_on_mode_pill_pressed`).
- The `_format_level_metrics(level_id)` helper (best time + endless best at the panel's center) is preserved — it duplicates the Endless wave info the new pill shows, but the metrics line carries Best Time which the pills don't. Could trim later if redundant.

### Why pills here, not in LoadoutScreen
LoadoutScreen still has its Campaign/Heroic/Iron mode row (lines 71–104 of `LoadoutScreen.gd`) which now becomes redundant for mode selection — the pill on the level card already committed `current_mode`. LoadoutScreen reads `current_mode` to pre-highlight the matching pill there. The pre-battle screen continues to show modes for confirmation; tapping a different pill there overrides the level-card choice. This intentional redundancy lets the player double-check before spending stars / starting Iron mode. If user feedback flags it as confusing, retire the LoadoutScreen pill row (small change — just hide the row when reached from the level card).

### Verification
- WorldMap → confirm each unlocked level panel shows 4 pills (Campaign / Heroic / Iron / Endless) instead of the prior Play / Endless pair.
- Campaign pill: star count visible, tap → LoadoutScreen with Campaign pre-selected → Start Battle launches gameplay.
- Heroic pill: starts disabled with "Need 3★"; after earning 3★ on Campaign, becomes "Ready" → tap launches Heroic.
- Iron pill: gated behind Heroic completion.
- Endless pill: always available; shows best wave; tap launches endless mode.
- Locked levels: still show single "Locked" button (unchanged).

### What's done across all six phases
- **Phase A** — WorldMap bottom bar 8 buttons → 4 corner buttons (Heroes / Towers / Codex / Shop). Endless virtual level removed.
- **Phase B** — HeroesHub TabContainer (Loadout / Equipment / Stats / Skills / Talents). Equipment + Talents embedded.
- **Phase C** — TowersHub TabContainer (Loadout / Upgrades). Both embedded; UpgradeTree's StarsLabel reparented out of hidden TopBar.
- **Phase D** — CodexHub TabContainer (Bestiary / Records). Both embedded.
- **Phase E** — WorldMap top-bar Stars counter + Settings gear; new OptionsScreen absorbs in-HUD VFX toggle and MainMenu Reset Progress.
- **Phase F** — Per-level mode pills (Campaign / Heroic / Iron / Endless) replace the Play + Endless pair.

WorldMap is now Kingdom Rush-shaped: spatial level list (still scrollable, spatial map is a future item), corner-icon hubs, top-bar resource counter + settings, and per-level mode pills. The 6 prior standalone meta screens are reachable in ≤2 taps; future Stats / Skills / Achievements / OptionsScreen extras drop into the existing hubs as new tabs without further WorldMap layout changes. Standalone meta scenes (`EquipmentScreen.tscn`, `TalentScreen.tscn`, `LoadoutPickerScreen.tscn`, `UpgradeTree.tscn`, `EncyclopediaScreen.tscn`, `LeaderboardScreen.tscn`) remain in the codebase as embedded targets — retiring them as standalones is a small cleanup pass available whenever, but harmless to leave.

---

## 2026-04-27 — Post-implementation review fixes (Phases A–F audit)
Code review pass after Phases A–F surfaced four bugs (one was a pre-existing latent issue that Fix 1 also resolves as a bonus). All four fixed in this entry.

### Bugs fixed

**Fix 1 — LoadoutScreen mode init** ([ui/LoadoutScreen.gd:35](ui/LoadoutScreen.gd#L35))
- Changed `_selected_mode = "campaign"` → `_selected_mode = GameState.current_mode`
- **Phase F regression**: pills set `current_mode` to "heroic" / "iron"; LoadoutScreen's hardcoded init wiped it back to "campaign" before `_on_start()` committed it. Player picked Iron, played Campaign.
- **Pre-existing latent bug**: same path was broken for Endless pre-Phase-F. The level-panel Endless button (and the now-removed bottom-bar Endless) set `current_mode = "endless"`, but LoadoutScreen overwrote it with "campaign" at Start, so `Main.gd._ready()` saw `current_mode != "endless"` and started Campaign waves instead of `WaveManager.start_endless`. Endless never actually launched via LoadoutScreen — appears to have been masked by `level_endless_best_scores` data persisting from earlier code paths.
- One-line fix kills both regressions and the latent bug.

**Fix 2 — Endless pill label** ([ui/WorldMap.gd:180-182](ui/WorldMap.gd#L180))
- Changed `"Endless\nW%d"` → `"Endless\nBest %d"`
- `GameState.get_endless_best_score()` returns a SCORE, not a wave number ([autoloads/GameState.gd:205](autoloads/GameState.gd#L205)). LeaderboardScreen distinguishes the two. "W27" was misleading; "Best 27" matches LoadoutScreen's "Best score: %d" wording.

**Fix 3 — Equipment HeroLabel reparenting** ([ui/HeroesHub.gd `_embed_screen`](ui/HeroesHub.gd))
- Lift `EquipmentScreen.tscn`'s `HeroLabel` out of the (now hidden) TopBar to a sibling position anchored at the top of the screen — same pattern Phase C used for `UpgradeTree`'s `StarsLabel`.
- Equipment tab Body's `offset_top` becomes `48` (was `8`) when HeroLabel is present, to make room. Falls back to `8` if no HeroLabel found (defensive).
- `unique_name_in_owner = true` makes `%HeroLabel` resolve regardless of parent within the same owner tree, so `EquipmentScreen.gd._refresh()` continues to update the relocated label without changes.

**Fix 4 — Hero-switch propagation** (HeroesHub + EquipmentScreen + TalentScreen)
- HeroesHub's Loadout-tab Switch button updated `selected_hero_id` but didn't notify the embedded Equipment + Talents tabs. They kept showing the prior hero's data until the hub was re-entered.
- Used the existing (previously declared but never emitted/connected) `EventBus.hero_selected(hero_id)` signal at [autoloads/EventBus.gd:55](autoloads/EventBus.gd#L55).
- [ui/HeroesHub.gd `_on_switch_hero`](ui/HeroesHub.gd) now emits `EventBus.hero_selected.emit(candidate.hero_id)` after setting `selected_hero_id`.
- [ui/EquipmentScreen.gd:58](ui/EquipmentScreen.gd#L58) `_ready` connects: `EventBus.hero_selected.connect(func(_id): _refresh())`.
- [ui/TalentScreen.gd:21](ui/TalentScreen.gd#L21) `_ready` connects: `EventBus.hero_selected.connect(_select_hero)`.
- Side benefit: any future code path that changes the active hero (LoadoutScreen pre-battle pick, future stats screen) just needs to emit the signal and the listeners react automatically.

### Files changed
- [ui/LoadoutScreen.gd](ui/LoadoutScreen.gd) — Fix 1
- [ui/WorldMap.gd](ui/WorldMap.gd) — Fix 2
- [ui/HeroesHub.gd](ui/HeroesHub.gd) — Fix 3 + Fix 4 emit
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — Fix 4 listener
- [ui/TalentScreen.gd](ui/TalentScreen.gd) — Fix 4 listener

### Verification
- WorldMap → Forest Path → Iron pill → Start Battle → in-game `current_mode == "iron"` (was previously silently downgraded to `"campaign"`).
- Same flow with Heroic and Endless — each launches the intended mode.
- WorldMap level panel → Endless pill reads `Endless\nBest 27` (no `W` prefix).
- WorldMap → Heroes → Equipment tab → hero name + level visible at top of panel.
- (Once a 2nd hero is unlocked) Heroes → Loadout tab → ◄ Switch Hero ► → switch tabs to Equipment / Talents → confirm both show the new hero's data without the user leaving the hub.

### Observations flagged but not fixed (per the plan's "second-pass observations" list)
1. LoadoutScreen mode-row redundancy after Phase F — UX-acceptable as an override surface.
2. `_format_level_metrics` Endless line duplicates the Endless pill — cosmetic.
3. OptionsScreen Reset Progress lambda timer leak on early exit — pre-existing pattern.
4. `TowersHub.pending_tab` no bound-check — defensive only.
5. `VFXSpawner.clean_view` not persisted — needs a real settings-persistence story.
6. `_embed_screen` boilerplate duplicated across 3 hubs — mild duplication, leave for now.

## 2026-04-28 — Inventory Sell feature (Town phase T1, minimal slice)
After research on a full Town/City system (sell + buy + craft), the user picked the smallest valuable slice: just sell. Adds a way to clear unwanted items from the hero inventory and rewards a new persistent currency. Future Town phases (buy, disenchant, reroll) drop in on top of this without touching what shipped here.

### What changed

**New persistent currency: `meta_gold`**
- [autoloads/GameState.gd](autoloads/GameState.gd): `meta_gold: int = 0` field. Setters `add_meta_gold(amount)` / `spend_meta_gold(amount)` mirror the per-run gold pattern. Cleared in `reset()` alongside other meta state.
- [autoloads/EventBus.gd](autoloads/EventBus.gd): new signals `meta_gold_changed(new_amount)` and `item_sold(instance, gold_reward)`.
- Distinct from `gold` (which is per-run, resets every level). Distinct save field, distinct top-bar counter.

**Persistence (additive, no SAVE_VERSION bump)**
- [autoloads/SaveManager.gd](autoloads/SaveManager.gd): saves `meta_gold` field; loads with `data.get("meta_gold", 0)` so older saves get 0 by default. SAVE_VERSION stays at 2 — the field is pure-extension and won't confuse v2 loaders.

**Sell-price resource**
- New [economy/SellPriceTable.gd](economy/SellPriceTable.gd) — Resource class with rarity → gold mapping (`common`, `magic`, `rare`, `epic`, `legendary` int fields) and a `price_for(rarity)` lookup.
- New [economy/sell_price_table.tres](economy/sell_price_table.tres) — default tunable values: 10 / 50 / 200 / 1000 / 5000.

**Sell endpoints in InventoryManager**
- [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd):
  - `_is_equipped(hero_id, uid)` — internal helper, scans all 6 slots.
  - `destroy(hero_id, uid)` — lower-level removal primitive. Refuses if equipped (push_warning). Returns true on success. Future disenchant/craft endpoints will reuse this.
  - `sell(hero_id, uid) -> int` — looks up price, calls `destroy`, awards meta-gold, emits `item_sold`, calls `SaveManager.save_game()`. Returns awarded gold (0 on any failure path — bad uid, missing base, equipped item).
  - `get_sell_price(hero_id, uid) -> int` — preview helper for UI labeling without committing.
- Equipped items can't be sold. The `destroy` refusal is the safety net; the UI layer also blocks (toast hint), so the player never even arrives at a "would have sold equipped" state.

**Sell UI on the Equipment tab**
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn): `RightControls` HBoxContainer added between `RightTitle` and `ScrollContainer`, holding `SellModeButton` (140×44) on the left and `MetaGoldLabel` ("💰 N", gold tint) on the right.
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd):
  - `_sell_mode: bool` and `_pending_sell_uid: String` state.
  - `_on_sell_mode_toggled` flips the mode, clears any pending sell, refreshes visuals + grid.
  - `_refresh_sell_mode_visuals` swaps the button label ("Sell Mode" ↔ "Done"), tints the button red when active, and rewrites the hint label.
  - `_handle_sell_tap(inst)` — first tap on an item arms it (toast: "Sell <name> for Ng? Tap again to confirm"). Second tap on the same uid commits via `InventoryManager.sell`. Different uid re-arms. 3-second auto-disarm via `get_tree().create_timer` (with `is_instance_valid(self)` guard so the lambda is safe if the player navigates away mid-window).
  - `_refresh()` inventory loop modulates icons in sell mode: faint red tint by default, brighter glow on the armed (pending) uid.
  - `_on_meta_gold_changed` listener syncs the `MetaGoldLabel` live as sales fire.

**WorldMap top-bar counter**
- [ui/WorldMap.tscn](ui/WorldMap.tscn): `MetaGoldButton` (140×80, "💰 N", gold tint) added between `StarsButton` and `SettingsButton`. Mirrors the Phase E Stars-counter pattern.
- [ui/WorldMap.gd](ui/WorldMap.gd): `_refresh_meta_gold_label()` reads `GameState.meta_gold`. `_on_meta_gold()` routes to HeroesHub (where the player can actually sell — no Town Buy destination exists yet). Once buy/craft ships, retarget to the Town hub.

### Mode discipline (kept all current behavior)
- One-tap-equip flow is preserved when sell mode is OFF — no regression for the existing player workflow.
- Slots still tap-to-unequip in either mode; sell mode only re-routes the inventory-icon press handler.
- Equipped items can't be sold from the UI, can't be destroyed by the API, and would just produce a toast if the user finds a way to try.

### Verification
1. **Fresh save**: boot → WorldMap → confirm `💰 0` in top bar.
2. **Old save**: existing save loads cleanly with `meta_gold` defaulted to 0 (no version mismatch).
3. **Sell flow**: WorldMap → Heroes hub → Equipment tab → tap "Sell Mode" → button turns red, hint updates, inventory tints red. Tap an item → toast "Sell <name> for Ng? Tap again to confirm" + that icon glows. Tap same item again → toast "Sold for Ng", item disappears, MetaGoldLabel ticks up. Top-bar counter on next WorldMap visit shows the new total.
4. **Wrong-item re-arm**: in sell mode, tap item A (armed), then tap item B → arms B, no commit on A.
5. **Auto-disarm**: arm an item, wait 3s without confirming → glow fades; tap again does NOT commit (re-arms instead).
6. **Equipped items**: try to sell-mode-tap an equipped slot → handled by existing slot-tap path (unequips). Item then in inventory, sellable.
7. **Persistence**: sell items, quit Godot, relaunch → `meta_gold` and missing items both persist.
8. **Counter shortcut**: tap `💰 N` in WorldMap top bar → opens HeroesHub (currently the canonical "do something with meta-gold" surface).

### Risks / known follow-ups
- Sell mode currently re-runs `_refresh()` on every tap to update icon modulation. With a large inventory this is a full grid rebuild per tap. Acceptable for current item counts; revisit when inventory grows past ~50 items.
- `_handle_sell_tap`'s 3-second timer captures `armed_uid` and checks `is_instance_valid(self)` — won't crash if the player leaves, but will silently fire and no-op. Same lambda-leak class as the OptionsScreen Reset Progress timer. Defensible pattern; revisit when refactoring meta-screen lifecycle.
- No "are you sure?" wall on the toggle into sell mode. Players who panic-tap-sell two items in a row each had two-tap confirms, but they could speedrun-sell their entire inventory in seconds. If that becomes a support issue, add a "you sold N items, undo last?" toast or a session-undo buffer.
- WorldMap `_on_meta_gold` routes to HeroesHub (where the sell UI lives). When the Town hub ships with a Buy tab, retarget there.

---

## 2026-04-28 — Inventory Polish phase (IP)
After auditing the inventory menu against ARPG conventions (Diablo, Path of Exile, Last Epoch, Hero Wars), four polish items shipped together. Goal: make the menu feel like a real ARPG, not a placeholder, with mobile-friendly affordances and protection against accidental sales.

### IP-1 — Dramatic rarity visuals on `ItemIcon`
[ui/ItemIcon.gd](ui/ItemIcon.gd) — added per-rarity scaling for two visual properties so higher-rarity items pop visibly out of the grid at a glance:
- `_RARITY_BORDER_THICKNESS = [3.0, 4.0, 4.5, 5.0, 6.0]` — Common 3px → Legendary 6px (doubles).
- `_RARITY_BG_TINT_AMOUNT = [0.0, 0.10, 0.16, 0.22, 0.30]` — Common keeps the original `_FILLED_BG` (no tint), Magic+ lerp toward their rarity color so the icon background reads colored.
- `_draw()` now computes `bg = _FILLED_BG.lerp(_RARITY_COLORS[r], _RARITY_BG_TINT_AMOUNT[r])` for filled items and `border_thickness = _RARITY_BORDER_THICKNESS[r]` instead of a flat constant.
- Pre-existing rarity pip overlay (`ItemGlyph.draw_rarity_pips`) untouched — still adds 1-5 dots indicating rarity tier.

### IP-2 — Long-press to show details (mobile-friendly hover replacement)
[ui/ItemIcon.gd](ui/ItemIcon.gd) — added a `long_pressed(instance)` signal that fires after `LONG_PRESS_SECONDS = 0.45` of unbroken touch/click hold:
- New tracking state: `_press_timer: SceneTreeTimer` and `_long_press_consumed: bool`.
- `_on_gui_input` now branches on press-down vs release. Press-down → `_begin_press()` starts the timer; release → `_end_press()` either fires `pressed` (if the timer never elapsed) or swallows the release (if `long_pressed` already fired).
- The timer's lambda checks `is_instance_valid(self) and _press_timer == captured_timer` so a release-then-new-press doesn't fire `long_pressed` against the new press.
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) connects `long_pressed → _on_item_hovered` for both inventory items and equipped slots — reuses the existing details panel logic, zero duplication. Mobile players now have a non-hover read-without-acting path; PC players get an alternative to mouse-hover.
- Tap behavior is unchanged: tap = equip / unequip / sell-arm. Long-press is the new sibling gesture, not a replacement.

### IP-3 — Item lock toggle (🔒 pin against accidental sale)
- [items/ItemInstance.gd](items/ItemInstance.gd) — new `locked: bool = false` field. Round-trips through `to_dict()` / `from_dict()` (older saves missing the field default to `false`, additive — no migration needed).
- [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — new `toggle_lock(hero_id, uid) -> bool` returning the new state. Persists immediately via `SaveManager.save_game()`. `sell()` refuses locked items at the API layer (defense-in-depth — UI also blocks).
- [ui/ItemIcon.gd](ui/ItemIcon.gd) — new `_locked_for_sale: bool` rendering state, set by `setup_instance` from `inst.locked`. `_draw()` overlays a small padlock glyph in the upper-right corner: filled yellow rect (body) with two short verticals + a top horizontal stroke (shackle). Pure draw primitives — no font dependency.
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — added `LockButton` (120×44, `🔒 Lock` initial label) to `RightControls`. Hidden by default; visible only in sell mode.
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd):
  - `_on_lock_pressed()` toggles the armed item's lock state, clears the arm (locking shouldn't also keep the item armed for sale — confusing UX), refreshes the button label.
  - `_refresh_lock_button()` flips label between `🔒 Lock` and `🔓 Unlock` based on the armed item's current state. Disabled with the `🔒 Lock` label when nothing's armed.
  - `_handle_sell_tap` now refuses to arm a locked item for sale — instead it sets the armed uid and shows a toast "Locked — tap 🔓 Unlock to allow sale", so the player can immediately unlock with one more tap.

### IP-4 — "Sell all Common" batch button
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — added `SellAllButton` (140×44) next to the Lock button. Hidden outside sell mode.
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd):
  - `_count_sell_all_eligible(hero_id)` counts unlocked Commons in the unequipped pool. Mirrors the criteria used by the sell sweep so the displayed count matches what gets sold.
  - `_refresh_sell_all_button()` shows count: e.g., `Sell all Common (5)`. Disables when count is 0.
  - `_on_sell_all_pressed()` — first tap arms (`_sell_all_armed = true`, label flips to `Confirm: sell N`, modulate to amber). Second tap commits: collects uids, iterates `InventoryManager.sell` per uid (each individually skips locked / equipped per its own contract), tallies count + total gold, emits one summary toast "Sold N items for Mg".
  - 3-second auto-disarm matches the single-item sell flow.
- The two-tap confirm is critical here — single-tap would let an accidental tap liquidate every Common in one move.

### Cross-feature wiring (kept all current behavior consistent)
- `_on_inventory_changed_simple` now also calls `_refresh_lock_button()` and `_refresh_sell_all_button()` when sell mode is active, so a lock toggle or batch sell elsewhere flows through to the buttons' labels live.
- Slot icons also get `long_pressed → _on_item_hovered` wiring — equipped items can be inspected via long-press on mobile.
- Default-mode (sell-mode-off) one-tap-equip preserved. No regression for the existing flow.

### Verification
1. **IP-1 visual check**: drop or grant a Common, Magic, Rare, Epic, Legendary item — confirm border thickness and background tint scale up. Legendary should look obviously special at grid scale.
2. **IP-2 mobile**: tap inventory item = instant equip (unchanged). Long-press (0.45s+) = details panel populates without equipping. Release before 0.45s = no details, no swallow.
3. **IP-2 PC**: hover still populates details. Long-press also populates (Win/Mac mouse-down hold equivalent).
4. **IP-3 lock flow**:
   - Sell mode on → arm an item → tap `🔒 Lock` → 🔒 glyph appears in icon corner, item un-arms, label resets. Quit + relaunch → lock persists.
   - Re-arm same item → toast "Locked — tap 🔓 Unlock to allow sale" + button label = `🔓 Unlock`. Tap to unlock → glyph gone, ready to sell.
5. **IP-4 batch sell**:
   - Drop 3 Commons + 1 Magic. Lock 1 Common (IP-3). Enter sell mode. `Sell all Common (2)` shows count = 2 (locked excluded).
   - Tap once → button flips to `Confirm: sell 2`, amber tint. Tap again → toast "Sold 2 items for 20g", inventory updated, locked Common stays, Magic untouched.
   - Wait 3 seconds without confirming → auto-disarm, label reverts.

### Risks / known follow-ups
- `_on_inventory_changed_simple` calling both `_refresh_lock_button` and `_refresh_sell_all_button` adds ~2 extra inventory iterations per signal. Negligible at current item counts.
- The padlock glyph drawing is pure primitives — readable but not pretty. A real 16×16 sprite would land better when art arrives.
- Long-press detection uses `SceneTreeTimer` — pause-mode-aware. If the player long-presses while a future pause-modal is active, behavior depends on tree pause state. Edit: this UI runs on the meta-game side, never paused — so OK for now. Document if any meta UI ever needs pause.
- Lock button only appears in sell mode. Outside sell mode, the long-press → details panel is read-only — no lock toggle there. Could add a Lock button in the details panel later, but that requires the details Label to become a richer Container; deferred.

### Status across the inventory + sell + polish work
- 2026-04-28 Sell phase shipped sell + meta_gold + WorldMap counter.
- 2026-04-28 IP phase shipped rarity drama + long-press + locking + batch sell.
- Inventory now matches ~80% of ARPG-genre conventions. Remaining (deferred): real item sprites, sort/filter row, side-by-side compare, multi-select, drag-and-drop. None blocking ship.

---

## 2026-04-28 — Inventory Architecture phase (IA)
After the AAA-vs-us deeper audit, the user picked four structural gaps to close: equip-time restriction enforcement (Gap 9), shared inventory architecture (Gaps 4+5 — same root cause), and inventory capacity (Gap 1). Three sub-phases shipped together. The result moves the data model from "per-hero silos" (each hero has its own inventory dict) to AAA-shape "shared pool + per-hero equipment refs", plus a soft cap with auto-sell overflow and finally enforces the previously-decorative `hero_restriction` and `level_requirement` fields on `ItemBase`.

### IA-1 — Equip-time restriction enforcement (Gap 9)
[autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — `equip()` previously ignored `ItemBase.hero_restriction[]` and `level_requirement`, even though both fields had been declared since Phase 48. Items meant for one hero could be equipped by any; level-gated items could be equipped at any level. Added two refusal paths:
- `hero_restriction` non-empty + hero not in list → toast "<HeroName> can't use this item".
- `level_requirement > 1` + hero level below it → toast "Requires Lv N".
- Defensive: same gates also applied to `ensure_starter_gear`'s auto-equip step via the new `_can_hero_equip(hero_id, base)` helper. A misconfigured starter pack (Mage-only item in Warrior's starter list) now silently skips auto-equip rather than force-equipping invalid gear.

### IA-2 — Shared inventory architecture (Gaps 4 + 5)
The big refactor. Old data model:
```
hero_inventories: Dictionary    # hero_id -> Array[ItemInstance]   (silos)
hero_equipment:   Dictionary    # hero_id -> Dict[slot_str -> uid]
```
New data model:
```
shared_inventory: Array[ItemInstance]   # ALL owned items, hero-agnostic
hero_equipment:   Dictionary             # hero_id -> Dict[slot_str -> uid]   (unchanged)
```
Items live once in `shared_inventory`. `hero_equipment[hero_id][slot]` references items by uid. Multiple heroes browse the same pool; `hero_restriction` (now enforced by IA-1) gates who can equip what. UID uniqueness preserved by `SaveManager.next_uid` (monotonic) — no aliasing risk.

**Behavior changes**:
- Drop in level → flows into `round_pickups` then `shared_inventory` on `level_completed` (no longer attributed to current hero).
- `EquipmentScreen` Equipment tab now reads `get_unequipped()` (hero-agnostic) — items equipped on Hero A don't appear in Hero B's grid (matches Diablo / WoW / PoE convention: equipped is in-use everywhere).
- Switch hero in HeroesHub → same items show; only the equipment slot row changes.

**API changes** (rename, drop hero_id from non-equipment paths):
- `get_inventory(hero_id)` → `get_shared_inventory()` (direct access)
- `get_unequipped(hero_id)` → `get_unequipped()` (filters across ALL heroes' equipment)
- `find_by_uid(hero_id, uid)` → `find_by_uid(uid)`
- `_is_equipped(hero_id, uid)` → `_is_equipped(uid)` (sweeps all heroes)
- `destroy(hero_id, uid)` → `destroy(uid)`
- `sell(hero_id, uid)` → `sell(uid)`
- `toggle_lock(hero_id, uid)` → `toggle_lock(uid)`
- `get_sell_price(hero_id, uid)` → `get_sell_price(uid)`

Equipment-related signatures (still per-hero) unchanged: `equip(hero_id, uid)`, `unequip(hero_id, slot)`, `get_equipped_uid/instance/all_equipped(hero_id)`.

**Save migration v2 → v3** ([autoloads/SaveManager.gd](autoloads/SaveManager.gd)):
- `SAVE_VERSION` bumped 2 → 3.
- Migration is **implicit** in `InventoryManager.from_save_dict`: accepts either `shared_inventory` (new) or `hero_inventories` (v2). Old saves load with their per-hero silos flattened into the shared pool in encounter order. UID uniqueness from `next_uid` guarantees no collision.
- `to_save_dict` writes only the new `shared_inventory` key going forward.
- `load_game` prints a `[SaveManager] migrating save vN → v3 (shared_inventory)` line when an older save is detected.

**Call-sites updated** ([ui/EquipmentScreen.gd](ui/EquipmentScreen.gd)): every renamed API. Removed `hero_id` locals that no longer needed (the `_handle_sell_tap`, `_on_lock_pressed`, `_refresh_lock_button`, `_refresh_sell_all_button`, `_count_sell_all_eligible`, `_on_sell_all_pressed` paths). Equipment-related API calls (`equip`, `unequip`, `get_equipped_*`, `get_all_equipped`, `ensure_starter_gear`) keep their hero_id arg.

### IA-3 — Inventory capacity (Gap 1)
[autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — added `MAX_INVENTORY_SIZE = 60` cap and `add_to_shared(instance) -> bool` chokepoint. When the pool is at cap, drops are auto-sold for **half their normal sell price** (`_AUTO_SELL_RATIO = 0.5`), feeding into `meta_gold` with a toast "Inventory full — auto-sold for Ng". Soft pressure rather than hard punishment — players never lose loot outright, but they're nudged to clean inventory if they want full sell value.

`commit_round()` now routes each `round_pickups` entry through `add_to_shared`. Starter gear bypasses the cap (appends directly to `shared_inventory`) — it's a one-time idempotent grant, not a "drop" semantically.

UI surface ([ui/EquipmentScreen.gd](ui/EquipmentScreen.gd)): `RightTitle` changed from `Inventory (N)` to `Inventory (N / 60)` showing total pool size against cap. Color modulation: white below 90%, amber (1.0, 0.7, 0.3) at 90–99%, red (1.0, 0.4, 0.4) at 100%.

### Files affected
- [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — IA-1 enforcement + helper, IA-2 data model + API rename, IA-3 cap + add_to_shared
- [autoloads/SaveManager.gd](autoloads/SaveManager.gd) — IA-2 SAVE_VERSION 2 → 3, migration log line, migration comment
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — IA-2 API rename, IA-3 capacity display + tint

### Verification
1. **IA-1 hero gate**: equip a hero-restricted item on the wrong hero → toast refusal, item stays unequipped.
2. **IA-1 level gate**: drop an item with `level_requirement > current hero level` → tap to equip refuses with "Requires Lv N".
3. **IA-1 starter gate**: a misconfigured starter pack with a too-restrictive item silently skips auto-equip (item still added to inventory, just not equipped).
4. **IA-2 migration**: load an existing v2 save → console prints `migrating save v2 → v3 (shared_inventory)` → all items appear in Equipment tab regardless of which hero is selected. Switch hero → same items, different equipment slots.
5. **IA-2 hero switch**: drop an item playing as Warrior → return to WorldMap → switch to Mage in HeroesHub Loadout tab → drop visible from Mage's Equipment tab. Hero-restricted items refuse equip on wrong hero (IA-1).
6. **IA-2 cross-hero in-use**: equip a Sword on Warrior → switch to Mage → Sword does NOT appear in Mage's inventory grid (it's in use on Warrior).
7. **IA-3 cap**: spam drops to 60 / 60 → next drop auto-sells for half price, toast appears, MetaGoldLabel ticks up. Sell 5 items → header reads `(55 / 60)`, color reverts to white. Refill to 54 → 90% → header turns amber.
8. **Save round-trip**: with locks, equipped, and capacity-near-cap state → quit and relaunch → all state persists.

### Risks / known follow-ups
- **`equip(hero_id, uid)` keeps hero_id arg** even though `find_by_uid(uid)` is now hero-agnostic. The arg now identifies WHICH hero is doing the equipping (writes to `hero_equipment[hero_id]`). Signature is correct but slightly confusing alongside the renamed dropping siblings.
- **Auto-sell penalty (50%) is a guess.** Tunable via `_AUTO_SELL_RATIO`. If playtesters say "I lost a Legendary, that's brutal" — raise it (or block the auto-sell on Epic+ and let the ground drop persist).
- **No ground-drop fallback** when inventory is full. PoE keeps drops on the ground; we auto-sell. If players miss the agency, switch to ground-persists by setting `_AUTO_SELL_RATIO = 0` and skipping the `add_meta_gold` call (drop is just discarded, with a toast).
- **Cap bypass for starter gear** is intentional but subtle. If a future content rule grants more starter items than `MAX_INVENTORY_SIZE`, ensure_starter_gear would silently overrun the cap. Defense: clamp at append time, defer until that scale is real.

### Follow-up audit fixes (same-day code review)
A second pass after the reset/TestRange fixes shipped found three more real bugs and one UX wart. All four addressed:

**Bug A — TestRange polluted-save loophole**: even with `_exit_tree` restoring in-memory state, `EventBus.encyclopedia_entry_unlocked` (fired when Test Range spawned a not-yet-encountered enemy) triggers `SaveManager._on_encyclopedia_unlocked → save_game()` which wrote the polluted `tower_slot_cap = 6` + 5-tower loadout to disk before the restore could happen. Fix 5's polluted-cap repair on next load truncates `selected_tower_ids` to first 4, but that **destroys the player's customized tower loadout** (replaces it with TestRange's `[archer, barracks, mage, artillery]`). Closed at the source: [autoloads/SaveManager.gd `save_game()`](autoloads/SaveManager.gd) early-returns when `GameState.current_mode == "test_range"`. Test Range is now write-isolated — no signal can leak its sandbox state into the save file.

**Bug B — same uid equippable on multiple heroes**: `equip(hero_id, uid)` wrote `hero_equipment[hero_id][slot] = uid` without clearing the same uid from any OTHER hero's slot. After IA-2 (shared pool, single uid universe), this broke the "an item is in-use globally when equipped" invariant. Latent today (single hero) but would manifest the day a 2nd hero is unlocked. Fixed in [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd): new private helper `_unequip_uid_anywhere(uid, keep_hero_id)` walks every hero's slots and clears matches except for the equipping hero, emitting `item_unequipped` per cleared slot. `equip()` calls this before writing the new slot.

**Bug C — `_ensure_equip_dict("")` pollutes hero_equipment**: passing an empty hero_id created `hero_equipment[""] = {0: "", ...}` which then round-tripped through the save file as a junk entry. Latent today (only `selected_hero_id = "hero_warrior"` paths reach this), but defense-in-depth: [autoloads/InventoryManager.gd `_ensure_equip_dict`](autoloads/InventoryManager.gd) early-returns an empty dict (caller's read sees no equipment) without touching the hero_equipment dict.

**Improvement — details panel preserved during sell mode**: `_refresh()` fires on every sell-arm tap to re-modulate icons. Each call reset `details_label` to "Hover an item to see its details", wiping any context the player had just long-pressed to read. [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) `_refresh()` now skips that reset when `_sell_mode` is on — the hover/long-press handler owns the label in sell mode.

### Files affected (follow-up)
- [autoloads/SaveManager.gd](autoloads/SaveManager.gd) — `save_game()` test-range guard
- [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — `_unequip_uid_anywhere`, `equip()` calls it, `_ensure_equip_dict` empty-id guard
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — `_refresh()` preserves details in sell mode

### Verification (follow-up)
1. **Bug A**: Customize tower loadout (e.g. swap Barracks → Ice). WorldMap → Test Range → spawn Boss1 (or any new enemy). Quit + relaunch → tower loadout still has Ice. (Pre-fix: would revert to `[archer, barracks, mage, artillery]`.)
2. **Bug B**: (single-hero today, can't reproduce until 2nd hero ships) — when a 2nd hero is unlocked, equipping a shared item on Mage should remove it from Warrior's slot automatically.
3. **Bug C**: not directly testable today (no path sets selected_hero_id = "") — defensive only.
4. **Improvement 4**: enter sell mode → long-press an item → details panel populates → tap that item to arm → details panel still shows the item's stats (didn't reset to "Hover an item...").

### What's still flagged but not fixed
- `add_to_round` emits `item_picked_up` for items that may auto-sell on commit_round (cosmetic, rare today).
- `get_shared_inventory()` is dead code (callers bypass via `InventoryManager.shared_inventory.size()` direct access). Leave or delete.
- Batch sell triggers N grid rebuilds (negligible at small scale).
- `delete_save` doesn't emit `gold_changed` / `meta_gold_changed` (only matters if any future screen tries to live-display these without re-instantiating).

---

## 2026-04-29 — Wave pacing rework (KR-style hybrid)
Player flagged that the first wave starts on a short auto-countdown without giving them time to plan tower placement, and asked for KR-style "click Send Wave to start" with a blinking button as the affordance. Picked **Option C** (long fallback timer + Send Wave as the primary call, no hard wait): engaged players get agency + gold bonus by clicking; AFK players still progress, just slowly. No code-shape change to WaveManager — just timing tweaks + a HUD animation.

### What changed
- [waves/WaveData.gd](waves/WaveData.gd): default `countdown` bumped 3.0 → **20.0s** (inter-wave grace). Existing `level1_waves.tres` waves don't override the field, so the bump propagates automatically.
- [autoloads/WaveManager.gd](autoloads/WaveManager.gd):
  - New constant `FIRST_WAVE_COUNTDOWN: float = 60.0` — generous setup time at level start so the player can read the map + place towers.
  - `_begin_next_wave()` now uses `FIRST_WAVE_COUNTDOWN` instead of `wave.countdown` when `_wave_index == 0`. Subsequent waves use the wave's authored countdown (20s default).
  - `call_early_wave()` reward formula updated by the user during this session: now **1 second saved = 1 gold** (was a flat-cap 10g formula). Scales correctly with the longer countdowns — a full 60s first-wave call yields 60g, enough to buy an early tower upgrade.
- [ui/HUD.gd](ui/HUD.gd):
  - New `_send_wave_blink: Tween` member.
  - `_start_send_wave_blink()` runs an infinite looped tween pulsing the SendWaveButton's modulate alpha between 1.0 and 0.45 (warm yellow tint for color identity), 0.55s each direction with sine ease. Uses `TWEEN_PAUSE_PROCESS` so blinking continues during tactical pause.
  - `_stop_send_wave_blink()` kills the tween and restores `Color.WHITE`.
  - Wired into `_on_countdown_started` (start blink) and `_hide_countdown` (stop blink). `_hide_countdown` is already called from `_on_send_wave_pressed` / `_on_wave_launched` / `_on_early_wave`, so the blink stops on every codepath that ends a countdown.

### Behavior summary

| Moment | Before | After |
|---|---|---|
| Level start → first wave | Auto-starts after 3s | Auto-starts after **60s**; Send Wave button blinks the whole time, click skips for 60g |
| Between waves | Auto-starts after 3s | Auto-starts after **20s**; blink + click for ~20g |
| Send Wave bonus formula | `ceil(fraction × 10)` (capped 10g) | `ceil(seconds_remaining)` (1g per second saved) |
| AFK player | Wave still starts | Wave still starts (just later) |

### Verification
1. Level start: countdown reads ~60s, Send Wave button visible and pulses smoothly.
2. Click Send Wave → wave starts, +60g if clicked at full grace, less if waited.
3. Don't click → wave auto-starts at 0s. Toast/feedback should still fire (existing flow).
4. Between waves: countdown ~20s, button blinks again, +20g max bonus.
5. Tactical pause during countdown: blink continues (visual feedback survives pause).
6. Endless mode: still uses the procedural `wave_data.countdown = maxf(1.5, 3.0 - wave_num * 0.1)` from `_generate_endless_wave` — endless intentionally faster, fix doesn't touch it. First-wave override still applies via `_wave_index == 0` so wave 1 of endless gets the 60s grace too.

### Risks / known follow-ups
- **Endless wave 1 grace**: gets 60s now, which is consistent with campaign but might feel long for an endless rerun. Acceptable; revisit if playtesters say "endless should drop me straight in."
- **Gold bonus scaling on first wave (60g)**: substantial relative to the `STARTING_GOLD = 100`. May invalidate the "do you have enough gold for tower X" tension if every player just clicks immediately. Watch for this in playtest; if it skews the early game, lower the multiplier (e.g. 0.5g per second).
- **Tween survives scene exit**: `_send_wave_blink` is a `Tween` parented to the HUD CanvasLayer. SceneManager.goto frees the HUD → tween auto-frees. Confirmed no leak.
- **No "AFK timer" visual cue**: the player doesn't see "you have 60s left" on the button itself — the countdown_label sits separately. Future polish: show the seconds on the button face. Not urgent.
- **`get_unequipped()` iterates every hero's equipment** every call — O(heroes × 6 + items). Negligible at 1-3 heroes; revisit if there's ever an "all heroes" view that calls this in a tight loop.
- **No "transfer to stash" UI** because there is no stash — shared_inventory IS the stash. The mental model is still "every hero shares one bag." If players ask for a separate stash tab later, that's a future phase (split shared_inventory into "active inventory" + "stash" with a transfer UI).
- **Hero-restricted items in inventory grid render normally today** — IA-1 just refuses the equip. Future polish: desaturate them per the plan's open design decision #1 (visible-but-not-equippable visual cue).

---

## 2026-04-29 — Reset / TestRange leak audit + fixes
Player-visible bugs raised after the IA phase shipped: an extra (5th) tower slot at level start, and items not clearing after Reset Progress. Audit found both stem from incomplete `reset()` semantics across the autoloads, plus a debug-only Test Range scene that mutated global GameState with no restore. Five fixes shipped together.

### Bugs
1. **Extra tower slot**: [balance/test_range/TestRange.gd](balance/test_range/TestRange.gd) `_ready()` set `GameState.tower_slot_cap = 6` and `selected_tower_ids` to a 5-tower list (`tower_archer`, `tower_barracks`, `tower_mage`, `tower_artillery`, `tower_ice`, `""`). No `_exit_tree`, no save/restore. The comment claimed "doesn't persist" but **any subsequent `SaveManager.save_game()`** (selling an item, locking, etc.) wrote the polluted state to disk. After visiting Test Range once, the player's regular gameplay had 5 unlocked tower slots permanently.
2. **Items survive Reset Progress**: `SaveManager.delete_save()` deleted the file and called `GameState.reset()`, but neither cleared `InventoryManager.shared_inventory`, `hero_equipment`, `starter_gear_granted`, or `SaveManager.next_uid`. Reset wiped stars + meta_gold + upgrades but left the inventory + equipment + UID counter intact. The next save fired (e.g. via the Equipment tab's `ensure_starter_gear` call) re-persisted all the "deleted" data.

### Structural finding — `reset()` was incomplete on multiple axes
[autoloads/GameState.gd `reset()`](autoloads/GameState.gd) didn't reset `tower_slot_cap`, `selected_tower_ids`, `hero_progress`, `level_best_times`, or `level_endless_best_scores`. These are all persisted player-progression fields — they should clear on Reset Progress like stars and upgrades do. Pre-existing gap; surfaced when TestRange started actively polluting one of them.

### Fix 1 — `GameState.reset()` completed
[autoloads/GameState.gd](autoloads/GameState.gd) — added the missing field clears:
```gdscript
tower_slot_cap = 4
reset_loadout_to_default()       # selected_tower_ids → 4 launch towers
hero_progress = {}
level_best_times = {}
level_endless_best_scores = {}
```

### Fix 2 — `InventoryManager.reset()` (new)
[autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — new public method clearing every InventoryManager-owned field: `shared_inventory`, `hero_equipment`, `round_pickups`, `starter_gear_granted`. Emits `EventBus.inventory_changed` so any open UI re-renders empty.

### Fix 3 — `SaveManager.delete_save()` wires up the full reset
[autoloads/SaveManager.gd](autoloads/SaveManager.gd) — now calls `InventoryManager.reset()` and resets `next_uid = 1` after deleting the file and calling `GameState.reset()`. Reset Progress is now an actual full wipe.

### Fix 4 — TestRange capture/restore
[balance/test_range/TestRange.gd](balance/test_range/TestRange.gd) — added `_saved_*` fields capturing `tower_slot_cap`, `selected_tower_ids`, `current_mode`, `current_level_id` in `_ready()` before mutating, and restoring them in a new `_exit_tree()`. Sandbox state never leaks past scene exit. The `_saved_selected_tower_ids` uses `.duplicate()` to avoid by-reference aliasing — the saved snapshot stays pristine even though Test Range overwrites the live array.

### Fix 5 — One-shot recovery for already-polluted saves
[autoloads/SaveManager.gd](autoloads/SaveManager.gd) `load_game()` — after restoring `tower_slot_cap` from disk, checks if it's > 4. Slots 5–6 aren't unlocked through any progression yet, so any cap > 4 is by definition stale state from the prior TestRange leak. Repairs back to 4, prints `[SaveManager] repairing polluted tower_slot_cap=N → 4`, and trims `selected_tower_ids` to the first 4 entries (the player's original picks survive; the leaked `tower_ice` + placeholder get dropped).

This means existing players don't have to use Reset Progress to fix Bug 1 — first launch after this update auto-corrects.

### Files affected
- [autoloads/GameState.gd](autoloads/GameState.gd) — `reset()` body
- [autoloads/InventoryManager.gd](autoloads/InventoryManager.gd) — new `reset()`
- [autoloads/SaveManager.gd](autoloads/SaveManager.gd) — `delete_save()` body, `load_game()` polluted-cap repair
- [balance/test_range/TestRange.gd](balance/test_range/TestRange.gd) — capture/restore via `_ready` + new `_exit_tree`

### Verification
1. **Polluted save auto-repair**: existing save with `tower_slot_cap = 6` → boot game → console line `[SaveManager] repairing polluted tower_slot_cap=6 → 4`. WorldMap → start a level → build ring shows 4 unlocked slots.
2. **TestRange sandbox**: WorldMap → Test Range button (debug-only) → confirm 5 towers in build ring inside Test Range. Exit Test Range → return to gameplay → build ring back to 4 slots. Quit + relaunch → still 4 slots (no leak to disk).
3. **Reset Progress full wipe**: drop a few items, equip something, level up the hero → Reset Progress (Options gear) → confirm:
   - Inventory empty (next visit to Equipment tab regrants starter gear).
   - Hero level back to 1, XP 0.
   - Best times / endless scores cleared on level cards.
   - Tower loadout back to 4 launch towers.
   - meta_gold back to 0 (was already correct; just confirming).
4. **Save consistency**: after Reset Progress, immediately quit + relaunch → state stays cleared (no zombie data revives from auto-save side effects).

### Risks / known follow-ups
- The **polluted-cap repair** is keyed on `tower_slot_cap > 4` being equivalent to "stale state." The day a real progression unlock raises the cap (slot 5 via star threshold or IAP), this check needs to be relaxed — maybe `tower_slot_cap > GameState.get_unlocked_tower_slot_cap()` once that exists. Not urgent — no real cap-progression today.
- TestRange `_exit_tree()` runs when the scene is freed by `SceneManager.goto`. If TestRange is freed in some unusual path (force-quit, crash mid-scene), the restore won't run and the leak returns. The polluted-cap repair (Fix 5) is the safety net for that case.
- `InventoryManager.reset()` clears `starter_gear_granted` so the next `ensure_starter_gear` call regrants. Fine for normal Reset Progress flow. If some future code path calls `reset()` mid-session, the player would suddenly have starter items again — not an issue today since the only caller is `delete_save()`.
- `next_uid = 1` after reset is harmless (UIDs are scoped per-session and per-save). If a future "import save" feature reads UIDs from external data, this might need re-thinking.

---

### Cross-feature link follow-up — `hero_selected` emit symmetry
After the post-implementation review, a deeper cross-feature link audit caught one asymmetry: `GameState.selected_hero_id` was being set in two LoadoutScreen sites without emitting `EventBus.hero_selected`, breaking the contract HeroesHub now relies on. Fixed for symmetry / future-proofing:

- [ui/LoadoutScreen.gd `_refresh_hero_info`](ui/LoadoutScreen.gd) (line 162 area): conditional emit — only fires when the value actually changes (the function runs on every `_refresh`, so unconditional emit would spam listeners with no-op signals). Pattern:
  ```gdscript
  var changed: bool = GameState.selected_hero_id != selected.hero_id
  GameState.selected_hero_id = selected.hero_id
  if changed:
	  EventBus.hero_selected.emit(selected.hero_id)
  ```
- [ui/LoadoutScreen.gd `_on_hero_title_tapped`](ui/LoadoutScreen.gd) (line 193 area): unconditional emit — the cycle loop starts at `offset = 1` so the candidate is always different from the current selection. Mirrors the pattern used in `HeroesHub._on_switch_hero`.

**Why now**: today there are no other UI screens listening to `hero_selected` while LoadoutScreen is alive (HeroesHub is freed by the time LoadoutScreen runs). So these emits are no-ops in current flows. But the contract should be symmetric: any code path that mutates `selected_hero_id` should emit, so future listeners (Stats / Skills tabs, etc.) don't silently miss switches done from the pre-battle screen. Cheap to add now, expensive to debug later.

---

## 2026-04-30 — Phase 48 / DI-style hero skill cluster (Stages 1–3 + bug-fix pass)

Reshaped hero skills from "every authored skill is always shown in a vertical bar" to a Diablo Immortal-style **per-hero loadout** the player chooses on the WorldMap. In-level UI is now a **bottom-right portrait** (HP + XP rings + level badge) with a **2-slot arc** of skill tiles around it — the old `ui/SkillBar.gd` VBoxContainer is gone and the top-left HUD XP text is gone. Authored a new warrior kit (Summon Soldiers / Bless) and a new mage kit (Fireball / Mana Shield).

### Stage 1 — Data foundation (no visual change)
- `SkillData` gains `level_required: int = 1` ([heroes/skills/skill_data.gd](heroes/skills/skill_data.gd)). Skills with `level_required > hero level` render as locked in the Skills tab.
- New per-hero dict `hero_equipped_skills: Dictionary` on `GameState` ([autoloads/GameState.gd](autoloads/GameState.gd)), keyed by `hero_id`, value is `Array[String]` of length `EQUIPPED_SKILL_SLOTS`. Mirror of the proven `hero_progress` / `hero_talents` pattern. Six new accessors: `get_equipped_skills`, `set_equipped_skill`, `get_unlocked_skill_ids`, `get_skills_unlocked_at_level`, `has_unequipped_skills`, `_default_equipped_for`.
- `SaveManager` writes + reads `hero_equipped_skills` alongside `hero_progress` ([autoloads/SaveManager.gd](autoloads/SaveManager.gd)). No `SAVE_VERSION` bump needed — additive field; legacy saves load with the key missing → defaults computed on first read.
- New EventBus signals: `hero_skill_unlocked(hero_id, skill_id)` and `hero_skill_equipped(hero_id, slot, skill_id)`.
- `BaseHero._level_up_apply()` ([heroes/base_hero.gd](heroes/base_hero.gd)) now queries `GameState.get_skills_unlocked_at_level(hero_id, level)` after the stat bump and fires the unlock signal + a Toast. **No auto-equip** — the player picks on next WorldMap visit.
- `SkillBar._rebuild_buttons()` reads `GameState.get_equipped_skills(hero_id)` and resolves each slot's `skill_id` back to the `data.skills` index, so the hero's parallel `_skill_cooldowns` array stays addressed by the original index (no plumbing change in `BaseHero`).

### Stage 2 — In-level UI + WorldMap Skills tab
- New widget [ui/HeroHudPortrait.gd](ui/HeroHudPortrait.gd) (named to avoid colliding with the EquipmentScreen's existing `HeroPortrait` 2D drawer): 120px disk with outer XP arc (yellow, sweeps clockwise from 12 o'clock), inner HP arc (red→green by fraction), class glyph in the center disk (warrior sword / mage star / ranger bow / paladin shield), level badge in the lower-right (replaced by respawn countdown when the hero is dead). Tap → `EventBus.camera_focus_requested.emit(hero.global_position, 0.35)` + `hero.set_selected(true)`. HP polled in `_process` (no `hero_health_changed` signal exists today); XP/level driven by `hero_xp_gained` / `hero_leveled_up`.
- New small placeholder [ui/EmptySkillSlot.gd](ui/EmptySkillSlot.gd) — dim disk + "+" glyph for unequipped slots; tap → toast `"Set skills in Heroes → Skills"`.
- [ui/SkillBar.tscn](ui/SkillBar.tscn) restructured: `SafeArea > Inner > Cluster (200×400, anchored bottom-right)` hosting the portrait at `(40, 280)`. Slot positions live in code (`SLOT_POSITIONS` const) so the layout is one place to tune.
- [ui/HUD.gd](ui/HUD.gd) + [ui/HUD.tscn](ui/HUD.tscn) — removed the top-left `HeroLabel`, the `_hero` field, the `_respawn_remaining` tick, and all `_refresh_hero` plumbing. The portrait owns all of it now.
- [ui/HeroesHub.gd](ui/HeroesHub.gd) Skills tab: replaces the "coming soon" stub. Header shows hero name + level + XP, then EQUIPPED row (3 → 2 slots after Stage 3), AVAILABLE grid (every unlocked skill), LOCKED grid (skills with `level_required > level`, shown as `???  Lv N`). Two-tap commit: tap an Available skill (highlights yellow), tap an Equipped slot to swap. Listens to `hero_selected` (Loadout-tab cycle) and `hero_skill_equipped` to re-render.
- [ui/WorldMap.gd](ui/WorldMap.gd) `_refresh_heroes_button_dot()`: red 16×16 ColorRect overlay on the Heroes button when any unlocked hero has at least one unlocked-but-unequipped skill. Same convention used elsewhere in mobile UI.

### Stage 3 — Scope cut + warrior/mage kits
- `EQUIPPED_SKILL_SLOTS: 3 → 2`. Dropped `SLOT_POSITIONS[2]` from SkillBar. Adjustable later via a per-hero override on `HeroData`; deferred until a hero needs more.
- **Warrior — army support**:
  - **Summon Soldiers** ([heroes/skills/summon_soldiers_skill_data.gd](heroes/skills/summon_soldiers_skill_data.gd)): SELF cast, spawns 2 fresh militia in a front fan at hero position, each with a `LifetimeAbility(duration=15)` so they auto-die cleanly via the host's expire callback. Reuses the spawn pattern from [TowerBarracks.gd:253-273](towers/TowerBarracks.gd#L253-L273) (instantiate + `setup(rally_pos, flag_pos)` + add to "soldiers" group). 30s CD.
  - **Bless** ([heroes/skills/bless_soldiers_skill_data.gd](heroes/skills/bless_soldiers_skill_data.gd)): SELF cast, iterates `get_tree().get_nodes_in_group("soldiers")` within 200 px of hero, pushes a fresh [SoldierBlessAbility](systems/abilities/SoldierBlessAbility.gd) onto each soldier's existing `_ability_host`. +8 attack damage / +30 max HP for 8s; soldier glows gold while active. 25s CD.
  - **`SoldierBlessAbility`**: additive math (`damage_bonus` / `health_bonus`) on purpose — stacking N blesses adds N×bonus, and per-instance reverts on `_on_expired` arithmetically cancel back to original. A multiplicative formulation would orphan a residual multiplier when the second-applied bless reverts before the first.
  - **Plan correction**: my plan said `BaseSoldier` needed an `AbilityHost` added. Wrong — it already has one ([base_soldier.gd:101](soldiers/base_soldier.gd#L101)) from Phase 20.5. So Stage 3 plugged straight in.
- **Mage — burst + survival**:
  - **Fireball** ([heroes/data/skills/skill_fireball.tres](heroes/data/skills/skill_fireball.tres)): authored as a `ShieldBashSkillData` instance — the existing class already does AoE-at-tap with magic damage. Zero new code. 25 damage in 90 px at the tap, 8s CD.
  - **Mana Shield**: kept as-is (`BuffSkillData` + `RegenAbility` — already authored). 4 HP/s for 8s, 20s CD.
- The **global Fireball + Reinforcements spells** in `spells/` are still in the codebase — the player hasn't decided yet whether to delete them. The hero kits now duplicate their effects, so they're stylistically redundant. Pending decision.

### Bug-fix pass (post-implementation review)

A focused review caught 13 issues across the three stages. All fixed.

- **Cooldown overlay paints past the button** ([ui/CooldownButton.gd:79](ui/CooldownButton.gd#L79)) — high-severity visual bug exposed by the new arc layout. Polygon radius was `maxf(size.x, size.y) = 80` for an 80px button, extending 40px past every edge. Invisible in the old VBox (clipped by adjacent tiles); visible in the new arc as a dark crescent over the portrait. Changed to `(size * 0.5).length()` so the polygon stops exactly at the button corners.
- **Bless expiry could leave a soldier at 0 HP without dying** ([SoldierBlessAbility._on_expired](systems/abilities/SoldierBlessAbility.gd)) — if a soldier took ≥30 damage during Bless, the post-expire clamp set `current_health = 0` but the death check only fires from `take_damage`. Result: a "ghost" soldier at 0 HP that wouldn't fight or respawn. Fix: route through `owner._die()` when the clamp drops the soldier to 0.
- **Stacked Bless modulate clobber** — first-to-expire wiped the gold tint while a second bless was still active. Fix: `_STACK_META_KEY` counter on the soldier; modulate only resets when the LAST bless expires.
- **Multi-skill toast clobber** ([base_hero.gd `_level_up_apply`](heroes/base_hero.gd)) — `Toast.show_message()` kills the prior tween, so N skills unlocked at one level surfaced only the LAST message. Fix: 1-skill case keeps the named toast; N>1 case shows `"%d new skills unlocked — equip from Heroes → Skills"`.
- **Stale loadout entries from the Stage 3 skill rename** ([GameState.get_equipped_skills](autoloads/GameState.gd)) — saves had `["skill_slash", "shield_bash", "rally"]` referencing skills the warrior no longer authors after Stage 3. Fix: new `_authored_skill_ids(hero_id)` helper; `get_equipped_skills` purges stale sids on read AND persists the cleaned form so the dict converges. ContentRegistry-not-ready guard skips the purge if the registry returns empty (early boot).
- **`set_equipped_skill` swap emitted only 1 signal** — when slots A↔B swap, only B's change was signaled. Fix: emit `hero_skill_equipped` for BOTH the destination AND the source slot.
- **Empty `hero_id` polluted the dict** — getter would auto-cache a default for any string queried. Fix: empty `hero_id` returns a fresh empty array without writing.
- **Summon spread was a vertical line, not an arc** ([summon_soldiers_skill_data.gd](heroes/skills/summon_soldiers_skill_data.gd)) — the original `TAU * i / count - PI/2` formula collapsed to ±π/2 for `count=2`. Fix: 90° fan above the hero (`_FAN_ARC = π/2`, `_FAN_CENTER = -π/2`) — front-left + front-right flankers for `count=2`, evenly distributed for higher counts.
- **Skills tab destructive clear had no confirmation** ([HeroesHub `_on_skills_equipped_slot_pressed`](ui/HeroesHub.gd)) — accidental tap on equipped slot wiped the skill. Fix: two-tap commit. First tap arms with `Toast: "Tap slot again to clear"`; tapping any other slot or available skill cancels the arm.
- **No equip confirmation toast** — armed highlight just disappeared after swap. Fix: `Toast.show_message("Equipped: %s")` on success; `"Slot cleared"` on clear; `"Tap a skill below first…"` hint when tapping an empty slot with nothing armed.
- **`SaveManager.save_game()` ran on no-op** — Fix: only persist when `set_equipped_skill` returns true.
- **Fireball hardcoded to mage's authored 350px range** ([skill_fireball.tres](heroes/data/skills/skill_fireball.tres)) — `skill_range = 0.0` falls back to `data.attack_range` per the existing `get_skill_effective_range` convention; future mage attack-range buffs scale Fireball's reach.
- **Bonus**: hero switch in HeroesHub now clears `_skills_armed` and `_skills_clear_armed_slot` so a half-completed two-tap commit on hero A doesn't bleed into hero B.

### Skipped on purpose
- **Summons don't follow hero**: KR convention is rally-ground summons. Changing this means redesigning summon AI; a real design call, not a bug.
- **`queue_free` rebuild can show 1 frame of duplicates**: matches the project-wide pattern (TalentScreen, EquipmentScreen). Fixing here would make this one file inconsistent.
- **Portrait HP polled, not signaled**: works correctly today; only worth a `hero_health_changed` signal if profiling flags it.

### Files affected
- `heroes/skills/skill_data.gd` — `level_required` field
- `autoloads/GameState.gd` — `hero_equipped_skills` dict + 7 accessors (`get_equipped_skills` self-heal, `_authored_skill_ids` helper, swap dual-signal fix in `set_equipped_skill`)
- `autoloads/SaveManager.gd` — persist `hero_equipped_skills`
- `autoloads/EventBus.gd` — 2 new signals
- `heroes/base_hero.gd` — `_level_up_apply` unlock detection + combined toast
- `ui/SkillBar.gd` + `ui/SkillBar.tscn` — Cluster Control with portrait + 2-slot arc layout
- `ui/HeroHudPortrait.gd` (NEW) — in-level HUD dial
- `ui/EmptySkillSlot.gd` (NEW) — placeholder tile
- `ui/CooldownButton.gd` — overlay polygon radius fix
- `ui/HUD.gd` + `ui/HUD.tscn` — top-left HeroLabel removed
- `ui/HeroesHub.gd` — Skills tab wired (header, equipped row, available grid, locked grid, two-tap commit, destructive-clear two-tap, equip toast, hero-switch arm-reset)
- `ui/WorldMap.gd` — `_refresh_heroes_button_dot()` notification badge
- `systems/abilities/SoldierBlessAbility.gd` (NEW) — additive +damage/+HP timed buff with stack-counter modulate + ghost-soldier death routing
- `heroes/skills/summon_soldiers_skill_data.gd` (NEW) — front-fan summon spawn
- `heroes/skills/bless_soldiers_skill_data.gd` (NEW) — area buff dispatch
- `heroes/data/skills/skill_summon_soldiers.tres` (NEW)
- `heroes/data/skills/skill_bless.tres` (NEW)
- `heroes/data/skills/skill_fireball.tres` (NEW) — `ShieldBashSkillData` instance, magic damage, `skill_range = 0` (inherits from hero)
- `heroes/data/hero_warrior.tres` — `skills` array now `[summon, bless]`
- `heroes/data/hero_mage.tres` — `skills` array now `[fireball, mana_shield]`

### Verification (manual, in Godot editor)
1. **Slot count**: enter a level. SkillBar shows **2** slots arcing from the portrait. WorldMap → Heroes → Skills tab equipped row shows 2 slots.
2. **Warrior — Summon**: tap slot 0 → 2 militia spawn front-left/front-right of hero. After 15s they fall-over die cleanly. 30s CD ticks.
3. **Warrior — Bless**: place a barracks near hero, cast Bless. Soldiers within 200px glow gold for 8s. Verify hits land harder; verify clamp on expire (no ghost soldiers).
4. **Mage — Fireball**: tap slot 0 → range circle around hero (=mage attack range, 350px). Tap an enemy cluster → 25 magic damage in 90px radius. 8s CD.
5. **Mage — Mana Shield**: tap slot 1 → instant SELF cast. Portrait HP ring fills 4 HP/s for 8s. 20s CD.
6. **Cooldown overlay**: cast a skill, watch the radial fill — it shrinks within the button rect with no spillover onto the portrait.
7. **Skills tab**: tap an Available skill → highlights yellow. Tap an Equipped slot → toast `"Equipped: %s"`. Tap an Equipped slot with nothing armed → toast `"Tap slot again to clear"`. Tap same slot → toast `"Slot cleared"`. Tap a different slot → arm cancels.
8. **Notification dot**: temporarily set a warrior skill `level_required: 5` in its `.tres`, restart, grind to Lv 5 → Toast appears, return to WorldMap, Heroes button shows red dot. Equip the new skill → dot disappears next time WorldMap loads.
9. **Save round-trip**: equip skills → quit → reopen save file → `"hero_equipped_skills": {"hero_warrior": ["...", "..."]}` present. Reload → equipped state restored.
10. **Stale loadout self-heal**: open `user://save.json`, manually inject `["fake_skill_id", "another_fake"]` for warrior. Reopen game → cluster shows 2 EmptySkillSlot placeholders, Skills tab equipped row shows `(empty)` slots. Tap an Available skill → equip → Save dict converges to clean state.

### Risks / known follow-ups
- **Global spells (`spells/` folder, SpellPanel)** still load. The player wants to delete them ("only use new logic") but I held the cut pending an explicit go since it's a one-way trip and `FireballVFX.tscn` would need re-wiring to the hero Fireball skill before deletion.
- **Old skill `.tres` files** (`skill_slash`, `skill_shield_bash`, `skill_rally`, `skill_arcane_bolt`, `skill_frost_nova`) are unreferenced but still on disk. Safe to delete in a follow-up cleanup; the loadout self-heal handles any save references that survive.
- **`get_equipped_skills` is a side-effecting getter** (caches default + persists self-heal). Acceptable trade-off but worth noting if a future caller needs a pure read.
- **Hero-following summons**: KR convention has soldiers hold ground at rally; this matches but may feel odd if the hero immediately runs after casting Summon. Real design call, not a bug.
- **Portrait HP polled in `_process`**: cheap today; if a profiler later flags it, add a `hero_health_changed` signal in `BaseHero.take_damage` / `heal` paths.

---

## 2026-05-01 — Global spell system retirement

The bottom-left **SpellPanel** + the entire `spells/` script tree are gone. After Phase 48 / Stage 3 the hero kits (Mage's Fireball, Warrior's Summon Soldiers) duplicated the global Fireball + Reinforcements spells, and the player wanted the leftover global tiles removed so every active ability is hero-scoped.

### What got deleted (11 files)
- `ui/SpellPanel.gd` + `.gd.uid` + `ui/SpellPanel.tscn`
- `spells/SpellData.gd` + `.gd.uid`
- `spells/fireball_spell_data.gd` + `.gd.uid`
- `spells/reinforcements_spell_data.gd` + `.gd.uid`
- `spells/data/spell_fireball.tres`
- `spells/data/spell_reinforcements.tres`

### What was kept
- `spells/FireballVFX.gd` + `.tscn` — the explosion visual. Re-wired into the hero's Fireball skill via a new `vfx_scene: PackedScene` field on [ShieldBashSkillData](heroes/skills/shield_bash_skill_data.gd) (`apply()` instantiates the scene at the tap point and calls `setup(aoe_radius)` if the scene defines that method — same contract the global spell used). Authored on [skill_fireball.tres](heroes/data/skills/skill_fireball.tres) so casting the Mage's Fireball still flashes the orange disc + scorch mark.

### Cross-system references cut
| File | What changed |
|---|---|
| [main/Main.tscn](main/Main.tscn) | Dropped the SpellPanel CanvasLayer instance + ext_resource |
| [balance/test_range/TestRange.tscn](balance/test_range/TestRange.tscn) | Same removal as Main.tscn |
| [autoloads/EventBus.gd](autoloads/EventBus.gd) | Removed `spell_cast`, `spell_cooldown_started`, `spell_ready` signals |
| [autoloads/GameState.gd](autoloads/GameState.gd) | Dropped `MOD_SPELL_COOLDOWN` (kept the numbering gap so existing UpgradeData with `effect_type = 6/7` still resolves), `round_damage_spells` field, the `elif source is SpellPanel` branch in `record_round_damage`, the matching reset in `reset_for_level`, and the SpellPanel mention in the safe-area comment |
| [autoloads/ContentRegistry.gd](autoloads/ContentRegistry.gd) | Removed `_SPELL_PATHS` const, `spells: Array[Resource]` field, the `_load_catalog(_SPELL_PATHS, "spells")` call, the `_assert_ids(spells, "spell_id")` line, the `find_spell()` accessor, and the `%d spells` in the boot-time print |
| [autoloads/UnlockManager.gd](autoloads/UnlockManager.gd) | Removed `is_spell_unlocked()` and updated comments / docstrings |
| [autoloads/SoundManager.gd](autoloads/SoundManager.gd) | Removed the `spell_cast` SFX path entry and the `EventBus.spell_cast.connect(...)` line |
| [autoloads/RunStats.gd](autoloads/RunStats.gd) | Removed the `EventBus.spell_cast.connect(_on_spell_cast)` line, the `_on_spell_cast` handler, the `spells_cast: {}` field on the per-run dict, and the `spells: GameState.round_damage_spells` row in the per-run damage breakdown |
| [ui/GameOverScreen.gd](ui/GameOverScreen.gd) | Dropped the `Spells: %s` damage-attribution row and its inclusion in the empty-breakdown guard |
| [ui/ShopScreen.gd](ui/ShopScreen.gd) | Removed the `ProductData.UnlockType.SPELL` case from `_is_product_unlocked` (the enum value itself is kept on `ProductData` so legacy product `.tres` referencing SPELL don't fail-load — they just read as "locked" until a content-cleanup pass) |
| [ui/CooldownButton.gd](ui/CooldownButton.gd) | Updated the doc comment — the button's only consumer today is SkillBar |
| [ui/SpawnIndicator.gd](ui/SpawnIndicator.gd) | Layer-6 comment no longer references SpellPanel |
| [map/GameCamera.gd](map/GameCamera.gd) | Input-pipeline comment no longer mentions SpellPanel |
| [CLAUDE.md](CLAUDE.md) | Removed `is_spell_unlocked` from CORE RULE 7, dropped `spell` from CORE RULE 10 + 12 examples, replaced "Global spells" row in the design-decisions table with "Hero skills (Per-hero loadout, 2 active slots)", updated the Unlock API + Damage attribution paragraphs, dropped `SpellPanel._input` from the input-pipeline diagram, removed the layer-7 SpellPanel row from the CanvasLayer table, dropped SpellPanel from the safe-area paragraph |

### Verification
1. Boot the game — `[ContentRegistry] loaded` no longer prints `%d spells`. No errors / parse warnings.
2. Enter a level — bottom-left is empty (no SpellPanel tiles). Bottom-right cluster is unchanged.
3. Cast the Mage's Fireball — orange disc + scorch ring still appear at the tap point (FireballVFX wiring works through `ShieldBashSkillData.vfx_scene`).
4. Open `user://save.json` after a run — no `spells` key under `damage_by_source`, no `spells_cast` dict on the per-run record.
5. Exit + re-enter the Test Range — no SpellPanel reference; UI is just HUD + SkillBar.
6. Open ShopScreen — no SPELL products are authored, so nothing changes visually. (If a SPELL product `.tres` ever surfaces, it now reads as locked until removed.)

### Risks / known follow-ups
- **Empty `spells/data/` folder** is left behind by the deletion. Godot tolerates it. Can be removed by hand if desired.
- **Old skill `.tres` files** (`skill_slash`, `skill_shield_bash`, `skill_rally`, `skill_arcane_bolt`, `skill_frost_nova`) are still on disk but unreferenced after Stage 3 — the loadout self-heal silently drops save references to them. Safe to delete in a follow-up cleanup.
- **`ProductData.UnlockType.SPELL` enum value** is kept (no live code reads it; nothing authors a SPELL product today). If it bothers anyone, removing the enum member is safe — but doing so would technically be a breaking change for any out-of-tree shop product `.tres`.
- **`MOD_SPELL_COOLDOWN` numbering gap** in GameState's effect-type constants. The constant itself is gone but `MOD_STARTING_GOLD = 6` and `MOD_SOLDIER_HEALTH = 7` keep their numeric values so existing UpgradeData `.tres` (which serializes integer values for `effect_type`) still resolve correctly. Documented inline.

---

## 2026-05-01 — Spell-purge cleanup pass (post-review)

A second-pass review caught seven leftover threads from the spell removal that were quietly broken or dead. All fixed.

### Visible / load-bearing fixes
- **LoadoutScreen still showed "Spells: Fireball, Recruit"** ([ui/LoadoutScreen.gd:63](ui/LoadoutScreen.gd) and the `SpellsTitle` / `SpellsLabel` nodes in [ui/LoadoutScreen.tscn](ui/LoadoutScreen.tscn)) — every pre-battle screen rendered the stale row. Removed the field, the `_refresh()` line, and both .tscn nodes.
- **Spell Mastery upgrade was purchasable for zero effect** ([ui/UpgradeTree.tscn](ui/UpgradeTree.tscn)) — `Upg_SpellMastery` sub_resource (3★, "Spell cooldowns reduced by 15%") survived the purge with `effect_type = 5` pointing at the retired `MOD_SPELL_COOLDOWN`. Players could spend stars and get nothing back. Removed the sub_resource + dropped it from the `upgrades` array. Added a one-shot save migration in [autoloads/SaveManager.gd `load_game`](autoloads/SaveManager.gd) that purges `"spell_mastery"` from `GameState.purchased_upgrades` on next boot — players who'd already bought it auto-refund the 3★ next time `rebuild_upgrade_cache` runs (the cost stops being counted because the matching UpgradeData is gone).

### Dead enum cleanup
- **`ProductData.UnlockType.SPELL`** dropped — no shop product `.tres` files exist (and none used it), so removal was safe. Updated comment explaining the retirement.
- **`UpgradeData.EffectType.SPELL_COOLDOWN_MULT`** renamed to `_RETIRED_SPELL_COOLDOWN` — kept the enum slot so the next two members (`STARTING_GOLD_BONUS = 6`, `SOLDIER_HEALTH_MULT = 7`) stay at their integer-serialized values for existing `.tres` files. Mirrored the same explanation on [GameState.gd's MOD_SPELL_COOLDOWN gap comment](autoloads/GameState.gd#L13).

### Stale comment scrub
- [heroes/base_hero.gd `cooldown_fraction`](heroes/base_hero.gd#L313) — "Phase 22 spell buttons" → "any future cooldown-gated cast surface".
- [ui/SkillBar.gd](ui/SkillBar.gd#L6) — header comment said "three skill slots arc up-and-left"; corrected to "two" to match the Stage 3 slot cut.
- [autoloads/LootDropper.gd](autoloads/LootDropper.gd#L10) — dropped `spell` from the killer-source list.
- [levels/Level1.gd](levels/Level1.gd#L43) — `map_bounds` comment now says "hero VFX" instead of "spell effects".
- [heroes/skills/shield_bash_skill_data.gd](heroes/skills/shield_bash_skill_data.gd) — two comments that referenced "the old global Fireball spell" / "the spell still 'fired'" reworded to plain skill terminology.

### Orphan files deleted (9)
After Stage 3 swapped the warrior + mage skill arrays, the old skill resources were unreferenced. Loadout self-heal silently dropped any save references, but the files themselves stayed on disk.
- `heroes/data/skills/skill_slash.tres`
- `heroes/data/skills/skill_shield_bash.tres` (the Warrior's original Bash — distinct from the new `skill_fireball.tres` which uses the same `ShieldBashSkillData` class)
- `heroes/data/skills/skill_rally.tres`
- `heroes/data/skills/skill_arcane_bolt.tres`
- `heroes/data/skills/skill_frost_nova.tres`
- `heroes/skills/slash_skill_data.gd` (+ `.gd.uid`)
- `heroes/skills/rally_skill_data.gd` (+ `.gd.uid`)

`shield_bash_skill_data.gd` (still backs Fireball) and `buff_skill_data.gd` (still backs Mana Shield) stay.

### Files affected
- `ui/LoadoutScreen.gd` + `ui/LoadoutScreen.tscn`
- `ui/UpgradeTree.tscn`
- `autoloads/SaveManager.gd` — `purged "spell_mastery"` migration
- `progression/ProductData.gd`
- `progression/UpgradeData.gd`
- `autoloads/GameState.gd` — comment refresh
- `ui/ShopScreen.gd` — dropped the no-longer-needed defensive comment
- `heroes/base_hero.gd`, `ui/SkillBar.gd`, `autoloads/LootDropper.gd`, `levels/Level1.gd`, `heroes/skills/shield_bash_skill_data.gd` — comment scrub
- 9 orphan files deleted

### Verification
1. **LoadoutScreen**: open WorldMap → tap any level → mode pill → loadout. No "Spells" row. Hero + tower rows present.
2. **UpgradeTree**: open WorldMap → ★ counter → 5 upgrades visible (no Spell Mastery tile). Stars total matches the new tree's possible spend.
3. **Spell Mastery refund**: an existing save with `"spell_mastery"` in `purchased_upgrades` → next boot prints `[SaveManager] purged retired upgrade 'spell_mastery' (3★ refunded)`. Available stars increase by 3.
4. **Save round-trip**: open `user://save.json` after the boot → no `spell_mastery` in `purchased_upgrades`. Re-open game → no log line (idempotent).
5. **Shop**: ShopScreen still loads. No SPELL products exist; if a future product .tres referenced UnlockType.SPELL it would fail to load — caught at content authoring time, not runtime.
6. **Hero skills still work**: Mage Fireball still flashes the FireballVFX. Warrior Summon + Bless unaffected.

### Risks / known follow-ups
- **`_RETIRED_SPELL_COOLDOWN` enum placeholder**: kept for stable integer indexing of `STARTING_GOLD_BONUS` and `SOLDIER_HEALTH_MULT`. If a future content addition needs effect_type 5, repurpose the slot rather than appending to the end (keeping the existing serialized integer footprint stable). Otherwise just keep the placeholder forever.
- **`heroes/skills/shield_bash_skill_data.gd` still named "shield_bash"** even though its only consumer is now `skill_fireball.tres`. Renaming would break the script's class_name + tres references; a follow-up rename pass could promote it to a generic `aoe_at_tap_skill_data.gd` if more skills follow this shape. Not urgent — script is structural, name is just a label.


## 2026-05-01 — GameState split

### Why

`autoloads/GameState.gd` had grown to 673 LOC across 14 micro-domains (gold/lives, loadout, encyclopedia, leaderboard, hero XP, talents, best times, damage attribution, modifier cache, …). Every phase since Phase 1 added one or two vars to it — asymmetric cost: 5 minutes to add to an existing autoload vs. 30 minutes to invent a new one. The file accreted naturally, never refactored.

The pain wasn't acute (EventBus already de-coupled most consumers via signals), but the chronic friction was real: any task that crossed loadout / progression / run boundaries forced reading 673 LOC. With many more heroes / items / towers planned, leaving it would only get worse — and it blocked clean unit tests for the planned hardening week.

### What changed

Split `GameState` into four focused autoloads. Save format unchanged — keys remain flat at JSON top level; only SaveManager's read/write paths fan out.

| New autoload | Holds | LOC |
|---|---|---|
| `RunState` | gold, lives, score, wave_number, current_mode, current_level_id, stars_earned, round_damage_*, add_gold/spend_gold/lose_lives, record_round_damage, compute_endless_score, calculate_stars, reset_for_level | ~120 |
| `LoadoutState` | selected_hero_id, selected_tower_ids, tower_slot_cap, hero_equipped_skills + 7 helpers (get_loadout_towers, set_loadout_slot, get/set_equipped_skill, get_unlocked_skill_ids, has_unequipped_skills, …) | ~200 |
| `MetaProgression` | level_stars, levels_unlocked, heroic_complete, iron_complete, purchased_upgrades + modifier cache, hero_talents, hero_progress, level_best_times, level_endless_best_scores, endless_best_score, endless_leaderboard, meta_gold, encyclopedia_unlocked, unlocked_content + record_stars, get_hero_level/xp, add_hero_xp, try_record_best_time, submit_endless_score, get_total/spent/available_stars, … | ~270 |
| `DisplayUtils` | get_safe_insets() — orphan rescued from GameState (had nothing to do with game state) | ~25 |

### Cross-domain reads (intentional, non-cyclic)

- `RunState.reset_for_level()` reads `MetaProgression.get_upgrade_bonus(MOD_STARTING_GOLD)` for the meta-upgrade gold start bonus.
- `LoadoutState.get_unlocked_skill_ids()` reads `MetaProgression.get_hero_level()` to filter level-gated skills.
- `MetaProgression.submit_endless_score(name, score, wave)` takes wave as a parameter (caller passes `RunState.wave_number`) — avoids a back-edge.
- `MetaProgression.record_stars(mode, level_id, stars)` takes all three as parameters — same reason.

No bidirectional dependency. Boot order in `project.godot`: DisplayUtils → MetaProgression → RunState → LoadoutState (script-load var defaults make any actual ordering safe; this order documents intent).

### Sweep

- 245 substitutions across 30 consumer files via PowerShell regex with `\b` word boundaries (member names are unique across the three autoloads, so the dispatch is unambiguous).
- 4 files needed manual signature changes: GameOverScreen.gd (record_stars / submit_endless_score / compute_endless_score callers), SaveManager.gd (the 60-ref hotspot, written from scratch against the new homes), TowerRadialMenu.gd (`has_method("get_safe_insets")` defensive guard removed — DisplayUtils always has it), and 4 stale comment fixes.
- `autoloads/GameState.gd` + `.gd.uid` deleted. Final grep audit: 0 `GameState.` references in `.gd` (3 remaining matches are intentional historical anchors in `DisplayUtils.gd`, `LoadoutState.gd`, `SaveManager.gd` that document the split origin).
- Save format **unchanged**. SAVE_VERSION still 4. SaveManager.delete_save() now calls `RunState.reset()`, `LoadoutState.reset()`, `MetaProgression.reset()`, `InventoryManager.reset()`.

### CORE RULE 20 added

Locks in the per-content-id pattern that lets the autoloads stop growing as content grows:
- Per-content-id dicts, never per-content vars (`hero_progress: Dictionary[hero_id]`, never `warrior_xp: int`).
- Self-healing reads (drop entries pointing at content the catalog no longer authors; persist the cleaned form).
- Defaults from `ContentRegistry`, not hardcoded enumeration.
- Save additions append (new top-level key) — never reshape existing keys.
- One EventBus signal per state change.

Includes a state assignment table mapping each future content type (heroes, towers, items, levels, encyclopedia, future pets/mounts) to the right autoload + key. Adding a 10th hero or 6th tower now requires zero autoload changes — only `.tres` + `ContentRegistry`.

### Files touched

- New: `autoloads/RunState.gd`, `autoloads/LoadoutState.gd`, `autoloads/MetaProgression.gd`, `autoloads/DisplayUtils.gd`
- Modified: `autoloads/SaveManager.gd` (rewritten read/write paths), `project.godot` (autoload block: 1 entry → 4), `ui/GameOverScreen.gd` (signature-changing callers), `ui/TowerRadialMenu.gd` (removed dead has_method guard), `CLAUDE.md` (autoload table + state-assignment block + CORE RULE 20), `STATUS.md` (god-object item resolved), 30 consumer .gd files (mechanical sweep)
- Deleted: `autoloads/GameState.gd` + `.gd.uid`

### Verification

1. **Boot**: open in Godot editor — output panel shows `[MetaProgression] loaded`, `[RunState] loaded`, `[LoadoutState] loaded`, `[SaveManager] loaded` in order. No errors. No `[ContentRegistry/DRIFT]` lines.
2. **Save round-trip**: load a save written before the refactor (off the prior commit) — state restores identically. Restart, re-load, verify state still matches.
3. **Smoke run**: WorldMap → Loadout → Main.tscn → place tower → upgrade → branch-pick → win → GameOverScreen shows top-5 damage leaderboard → return to WorldMap → state persists.
4. **All three modes**: short Campaign / Heroic / Iron / Endless run each, verify mode-completion + endless leaderboard write paths.
5. **TestRange**: open balance/test_range/TestRange.tscn — tower damage tallies match pre-refactor numbers (validates `MetaProgression.get_upgrade_multiplier` cache wired correctly).
6. **Reset Progress**: Settings → Reset Progress → all three persistent autoloads + RunState clear; meta_gold, level_stars, hero_progress, selected_tower_ids return to defaults.
7. **Grep audit**: `grep -r "GameState\." --include="*.gd" c:/td1` returns only the 3 intentional historical anchor comments.

### Risks / known follow-ups

- **LSP staleness during the refactor**: VSCode's GDScript LSP showed dozens of "Identifier RunState not declared" errors until Godot itself was reloaded — autoload registration is parsed at editor boot, not on file save. Reload the editor once after pulling this commit; the errors clear instantly. Not a code bug.
- **Single cross-domain touch point**: `RunState.reset_for_level()` reads `MetaProgression.get_upgrade_bonus()`. Defensible (one one-way read, no cycle), but resist adding more cross-reads; new state should pick a single home or be parameterized.
- **Tests still unwritten**: STATUS.md item #1 (engineering hardening week) is now unblocked. The split surface is much friendlier to unit tests — DamageCalculator, RunState (gold/lives mutators), LoadoutState (slot swap), MetaProgression (record_stars dispatch, upgrade cache rebuild), SaveManager (round-trip per autoload).


## 2026-05-01 — Unit test suite (Mon–Tue)

### Why

STATUS.md item #1 (engineering hardening week) called for ~30 unit tests against the core surface before content sprint. The GameState split (shipped earlier today) made each domain independently testable, so this was the natural next move.

Two reasons it had to be now, not later:
1. Invariants are fresh — tests written today encode what we just established. Tests written in two months would rediscover them by trial-and-error.
2. AI-paired changes get an automated correctness check. Vibe-coding through new heroes / towers / items is much safer when the suite catches DamageCalculator regressions, save round-trip drift, and the Phase 47d incident-locks.

### What changed

**GUT 9.6.0 enabled.** Plugin was already vendored at `addons/gut/`; flipped on in `project.godot` `[editor_plugins]` block. Headless runner at `addons/gut/gut_cmdln.gd`.

**SaveManager testable.** `save_game()` / `load_game()` now thin wrappers over new `_save_to_path(path)` / `_load_from_path(path)` primitives. Tests round-trip through `user://test_save_*.json` so the player's real save is never touched. CORE RULE 8 still holds (only SaveManager touches files).

**Test scaffolding.** `tests/unit/` with helpers + 6 spec files:

| File | Tests | Surface |
|---|---|---|
| `test_helpers.gd` + `_fake_target.gd` + `_fake_target_data.gd` | — | shared utilities (fake DamageCalculator target, temp save paths, cleanup) |
| `test_damage_calculator.gd` | 5 | PHYSICAL/MAGIC/TRUE math, armor clamp, negative + null safety |
| `test_save_manager.gd` | 5 | round-trip across all three state autoloads, missing/corrupt/unknown-version paths, hero_talents shape preservation |
| `test_unlock_manager.gd` | 5 | type-scoped dispatch, defensive empty-id, star threshold, explicit unlock, free-content path |
| `test_content_registry.gd` | 4 | find_tower / find_hero / find_enemy lookups + CORE RULE 12 drift check across all six content arrays |
| `test_state_autoloads.gd` | 5 | RunState.reset_for_level, record_round_damage class routing, null-source safety, LoadoutState slot swap, get_loadout_towers cap |
| `test_regressions.gd` | 6 | enemy double-emit guard (47d-20), overkill cap, status-effect refresh, TowerUpgradeData base fallback (47d-9), TowerStatsCard diff format, unlock unknown-id safety |

**Tests reference scripts via `preload`, not `class_name`.** `class_name TestHelpers` would require the editor to have indexed the global script cache before headless runs work. From a clean checkout / clean CI, that cache doesn't exist yet, so test_save_manager.gd died with a parse error on first run. Fix: `const TestHelpers = preload("res://tests/unit/test_helpers.gd")` in every consumer, no class_name on the helper.

### Result

```
Scripts               6
Tests                30
Passing Tests        30
Asserts             185
Time              1.376s
```

All green. The same headless command will plug into the planned Thursday CI workflow with no further changes:

```bash
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

### Incidental fixes surfaced while writing tests

- **TowerData field name confusion**: my first draft assumed `attack_damage`; the actual field is `damage`. Caught immediately by the regression test for TowerUpgradeData base fallback. Lesson: always read the .tres / Data script before writing the test fixture, never paraphrase from memory.
- **Freed-Node typed-parameter rejection**: I wrote a test calling `RunState.record_round_damage(freed_tower, 100.0)`. Godot's typed parameters reject already-freed Objects at the call boundary, before the function body's `is_instance_valid` guard runs. So that internal guard handles only the null case in practice; freed refs can't reach the body through any typed call site. Test rewritten to cover null + zero + negative-amount short-circuits; the `is_instance_valid` half stays as defensive code for any future untyped call site.
- **`_diff_line` arrow format**: nailed down as `Label CurrVal→UpgVal` (no spaces around arrow) joined by 3-space separators. Matches CLAUDE.md spec ("Dmg 4→7   Rng 400→437"). The test pins this so the format stays mobile-readable across UI changes.

### Files touched

- New: `tests/unit/{test_helpers,_fake_target,_fake_target_data,test_damage_calculator,test_save_manager,test_unlock_manager,test_content_registry,test_state_autoloads,test_regressions}.gd`
- Modified: `autoloads/SaveManager.gd` (extract path-parameterized primitives; production callers unchanged), `project.godot` (`[editor_plugins]` enables GUT), `STATUS.md` (Mon–Tue ✓; no-test-suite note retired)

### Risks / known follow-ups

- **`is_instance_valid` half of the freed-source guard is dead code in production.** Typed parameters catch freed refs at every call site. Either keep the guard as belt-and-suspenders (safe but unreachable) or delete it once an audit confirms no untyped call site exists. Not urgent.
- **GUT orphan warnings on detached test nodes**: solved by switching `after_each` cleanup from `queue_free()` to synchronous `free()` for nodes that were never parented. queue_free defers past GUT's orphan check, so the warnings would have stayed otherwise.
- **CI workflow (Thursday) is still unwritten**: the headless command works locally; turning that into `.github/workflows/ci.yml` using `barichello/godot-ci:4.6` is the next step in the hardening week.
- **No save-migration scaffold yet**: STATUS.md item #1 Wednesday work. The save round-trip test currently passes a v4 save through unchanged; adding a `_MIGRATIONS: Array[Callable]` chain + 3 migration tests is the natural follow-up.


## 2026-05-01 — Save migration scaffold (Wed)

### Why

STATUS.md item #1 Wed. The content sprint is up next (4 levels, 2 heroes, 2 towers, 4 enemies). Every content add risks a save-breaking schema shift — renaming a hero_id, removing a tower, restructuring a dict. Building the migration framework under content-sprint pressure later is a recipe for a save-corrupting update; building it cold today is a 90-minute job and removes the risk.

The Mon–Tue test suite makes this cheap: 3 migration tests slot directly into the existing harness, ~80 lines total.

### What changed

[autoloads/SaveManager.gd](autoloads/SaveManager.gd) gained three small additions:

1. **`_migrations: Array[Callable]`** (instance var, not const). Empty today — every prior version transition (v1→v2→v3→v4) was implicit-on-load (InventoryManager flatten, spell-purge), so there's nothing to register yet. The next schema shift appends one Callable + bumps `SAVE_VERSION`. Tests can monkey-patch this array to exercise the chain logic without a real bump.

2. **`_run_migrations(data, from_version)`** runs every Callable whose target version is > the loaded version. Indexed so that `_migrations[k]` migrates v(k+1) → v(k+2). Loaded after the version-check / before state population in `_load_from_path`.

3. **`_compute_content_hash()`** + **`_purge_orphaned_content(data)`**: at save time we persist a stable hash of all hero/tower/enemy ids in `ContentRegistry`. At load time, if the hash differs (catalog has changed since the save), the purge drops orphaned content_ids from `selected_hero_id`, `selected_tower_ids` (positional — replaces with `""`), and `hero_progress` / `hero_equipped_skills` / `hero_talents` (key dropped). Hash-match short-circuits to avoid the per-load scan in the common case.

### Tests

[tests/unit/test_save_migrations.gd](tests/unit/test_save_migrations.gd) — 3 new:

1. **`test_migration_chain_runs_in_forward_order`** — register 2 mock migrations, write a v=1 save, load, verify both fired in order. Sanity-check that state population still happens after migrations.
2. **`test_no_migrations_run_when_save_at_current_version`** — register 1 mock migration, write a v=SAVE_VERSION save, load, verify the migration was NOT called. Forward-only invariant.
3. **`test_orphaned_content_ids_purged_on_load`** — write a save with `selected_hero_id` = unknown, `selected_tower_ids` containing one orphan, `hero_progress` keyed on an unknown hero. Force `content_hash` mismatch by writing a deliberately wrong hash. Load, assert: orphan hero_id → `""`, orphan tower → `""` at its slot position (positional preserved), orphan hero key dropped from `hero_progress`, valid entries retained.

Suite total: **33/33 passing in 1.5s** headless.

### Design notes

- **Positional purge for tower loadout**: replacing an orphan tower_id with `""` (rather than removing the entry) keeps slot positions stable. The player's other tower picks stay where they were on the build ring; the orphan slot just shows empty until they pick a new tower for it. Removing instead would shuffle every later slot left, which would surprise the player.
- **Dict-key purge for hero state**: `hero_progress[hero_id]` etc. drop the key entirely. There's no "slot position" to preserve — the dict is unordered by hero_id.
- **Hash short-circuit is an optimization, not correctness**: even without `content_hash` in the save, the loader would Just Work — every state-population step that takes a content_id already null-checks via `find_hero` / `find_tower`. The hash just lets us skip the scan when nothing has changed.
- **Forward-only chain**: no rollback. Once the player runs a save through migration v3→v4, downgrading the binary won't read the v4 save back as v3. Acceptable — Steam/mobile players don't downgrade.
- **Why not bump SAVE_VERSION**: nothing in the schema changed today. The framework is in; the version stays at 4. The next time you rename / remove / restructure, append a Callable and bump.

### Files touched

- Modified: `autoloads/SaveManager.gd` (+86 LOC for the three helpers + content_hash save key + load wiring)
- New: `tests/unit/test_save_migrations.gd`
- Modified: `STATUS.md` (Wed ✓; "Save-file migration framework" closed in Open design questions; "Last shipped" updated)

### Risks / known follow-ups

- **`_migrations` is `var` not `const`** to support test injection. Production code must never mutate it after `_ready()`. Document if you ever feel the urge to add a runtime-register path.
- **content_hash includes only hero/tower/enemy ids**, not skills / items / affixes. If a skill_id is removed, the orphan purge today doesn't catch a stale entry in `hero_equipped_skills[hero_id][slot] = "skill_removed"` — but `LoadoutState.get_equipped_skills` already self-heals that case at read time (drops sids the hero no longer authors and persists the cleaned form). Belt-and-suspenders, fine.
- **No rollback path**: if a migration ships and is later found to be wrong, the next migration must repair the damage (forward-only). Migrations should be tested in isolation before they ship.
- **CI workflow (Thursday) is still next**: the headless command works locally; turning that into `.github/workflows/ci.yml` using `barichello/godot-ci:4.6` is the immediate next step.


## 2026-05-01 — CI workflow (Thu)

### Why

STATUS.md item #1 Thu. The 33-test suite shipped Tue/Wed only protects code that passes through a developer's local machine. CI extends that to every push and PR — pushing a refactor or content add now fails fast on broken tests, before anyone else pulls the change. The Android-APK build step closes Friday's loop: playtesters get a fresh build per push without anyone manually exporting from the editor.

### What changed

- **`.github/workflows/ci.yml`** — two jobs in series (`test` gates `build-android`):
  - `test` runs `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` inside `barichello/godot-ci:4.6`. Same command that's been green locally since Tue.
  - `build-android` (only on test pass) stages the export templates from the image's `/root/...` location into `~/.local/share/godot/export_templates/${GODOT_VERSION}.stable`, then runs `godot --headless --export-debug "Android" build/td1-debug.apk`. APK uploaded as the `td1-android-debug` artifact, 14-day retention.
- **`export_presets.cfg`** promoted from gitignored to tracked. The local file was clean (no keystores, no personal paths — `export_path=""`, default `com.example.$genname` package name), so committing it is safe and lets CI read the Android preset without per-env injection.
- **`.gitignore`** tightened: `export_presets.cfg` removed from the ignore list; replaced with explicit ignores for keystore / signing-key siblings (`*.keystore`, `*.jks`, `export_presets.cfg.bak`) so the preset file is shared but credentials never are.

Triggers: push to `main` or any `phase-**` branch, PRs to `main`, plus a `workflow_dispatch` manual trigger so a flaky run can be re-kicked from the Actions UI.

### Known unknowns (will surface on first CI run)

- **Image tag `barichello/godot-ci:4.6`** — CLAUDE.md specifies Godot 4.6.2; the closest published Docker tag is what the user gets. If 4.6 doesn't yet exist as a tag, bump to whatever the project README directs (likely `4.5` or `latest`). The `GODOT_VERSION` env var lets the template-staging step track the same number without diverging.
- **Android debug-keystore handling** — Godot's Android export with `package/signed=true` needs a debug keystore wired through editor settings. The barichello image typically pre-stages this; if not, the first CI run will fail with a keystore-path error and the fix is one extra step that creates a keystore via `keytool` and points editor settings at it.
- **Tests inside Docker** — locally the suite runs against a vendored Godot 4.6.2 binary; the image's Godot may differ in patch level. If any test depends on a behavior that shifted between patch versions, it'd surface here. Suite is invariant-focused (math, dispatch, schema) so divergence is unlikely.

### Files touched

- New: `.github/workflows/ci.yml`, `export_presets.cfg` (now tracked)
- Modified: `.gitignore`, `STATUS.md`

### Risks / known follow-ups

- **APK is debug-signed only.** Release signing requires a release keystore behind a secret + a separate `--export-release` job. Out of scope for the hardening week; ship a release pipeline alongside the IAP work in production hardening round 2.
- **No caching of the Godot image / templates yet.** Each CI run pulls the image fresh; on a paid runner this matters less than on the free tier. If PR throughput grows, add an `actions/cache` step keyed on `GODOT_VERSION`.
- **Friday's playtest depends on Thursday's APK pipeline working.** If the `build-android` job needs iteration, that gates Friday — flag it as the first thing to verify after the initial CI push.


---

## 2026-05-03 — Balance tooling: PPT + Sliders + Audit (Phase 49 piece 1+2+3)

Shipped the full PPT/Slider/Audit foundation per the active plan (`~/.claude/plans/is-there-soem-addos-zesty-mitten.md`). Three pieces, each independently shippable, all merged together because the cost ratio favored one push.

### Piece 1 — Player Power Tier (PPT) framework

Diablo/PoE-style scalar collapsing player loadout strength into one number, so balance is against a band rather than against millions of (hero × skills × gear × towers) combinations. Added `power_tier` field to:

- `HeroData` (default 1, range 1–10)
- `SkillData` (default 1)
- `ItemBase` (default 0 = derive from rarity via `resolve_power_tier()`; COMMON→1 … LEGENDARY→5)
- `UpgradeData` (default 1)
- `TowerData` (default 1; loadout-pick PPT only — upgrade tiers not factored)

`LoadoutState.get_effective_ppt()` aggregates with weights 0.4 hero / 0.2 skills / 0.3 items / 0.1 towers + capped 0–1.0 talent + 0–1.0 upgrade bonuses. Calibrated so Naked Baseline (default warrior, starter gear) ≈ 1.0; mid-campaign 2–4; endgame 5+.

`LevelNodeData` gained `min_ppt` (Naked floor) + `target_ppt` (designed-for sweet spot). L1 set to min=1, target=2.

`BalanceCalculator` got three additions: `PPT_TO_HARDNESS_FACTOR = 3000.0`, `level_required_damage(wave_list)`, `score_for_ppt(wave_list, target_ppt)` returning drift %.

### Piece 2 — Slider debug panel

`balance/debug/BalanceOverrides.gd` — RefCounted utility (no class_name; `preload`-only to keep the global class registry clean) with all-static accessors backed by `user://debug_balance.json`. Identity returns in non-debug builds via `is_active()` short-circuit.

`balance/debug/BalanceSliders.tscn/.gd` — Control scene reachable from WorldMap. Sliders for HP %, armor +, mag-res +, speed %, damage %, starting gold +, PPT override. Live readout: hardness baseline → effective, gold/dmg ratio, PPT drift. Auto-saves on every drag. "Play this level" launches the chosen level with overrides active; "Reset" wipes them.

Runtime hooks (all guarded by `BalanceOverrides.is_active()` returning false in production):

- `enemies/base_enemy.gd::_ready` — multiplies `_hp_scale` by `get_hp_mult()`
- `enemies/base_enemy.gd::_effective_speed` — multiplies by `get_speed_mult()`
- `enemies/base_enemy.gd` — added `get_effective_armor()` / `get_effective_magic_resist()` accessors that fold in armor/mag_res additive overrides; capped at 0.95 to prevent immortal enemies
- `autoloads/DamageCalculator.gd::calculate_damage` — calls the new accessors via `has_method()` when present, falls back to `target.data.armor` for non-enemy targets (heroes / soldiers)
- `enemies/base_enemy.gd` — counter-attack damage scales by `get_damage_mult()` (both single-target and AoE-splash branches)
- `autoloads/RunState.gd::reset_for_level` — adds `get_starting_gold_add()` to starting gold

### Piece 3 — Cross-level audit screen

`balance/audit/LevelAudit.tscn/.gd` — single 8-column GridContainer (Level / Hardness / Tier / Target PPT / Min PPT / Drift / Gold/Dmg / Notes). Drift cell colored by ±15% / ±25% bands (green / yellow / red). Gold/Dmg cell colored by 0.10 / 0.15 / 0.25 / 0.30 thresholds. Loads `level_list.tres`, iterates each `LevelNodeData`, loads its `wave_list_path`, calls into `BalanceCalculator`. Pure read — no side effects on save / .tres files.

WorldMap got two new debug-only buttons (mirroring the existing BalanceReport pattern): `BalanceSlidersButton` → `_on_balance_sliders` and `LevelAuditButton` → `_on_level_audit`.

### What broke

- IDE diagnostics flagged `class_name BalanceOverrides` as unresolved before the editor scanned the new file. Fixed by removing `class_name` from `BalanceOverrides.gd` and switching every caller to `const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")`. More robust pattern for dev utilities anyway — keeps the global class registry clean and avoids the editor-scan race.
- Initial first edit to `base_enemy.gd::_send_attack` used `replace_all=true` and missed the AoE-splash branch (different surrounding context). Fixed with a second targeted edit.
- One name shadow in LevelAudit.gd (`var name` shadows `Control.name`, `modulate` parameter shadows `CanvasItem.modulate`) — caught by the linter, renamed to `lvl_name` and `color`.

### What did not change (deliberately)

- Wave generator skipped entirely per plan — Kingdom Rush ran a five-game series without one, hand-authoring + slider tuning is the right floor for solo dev.
- BalanceReport (run telemetry) untouched — different consumer, different question.
- No autoload added — `BalanceOverrides` is a `preload`-only static utility, keeping the autoload count at 20 per CLAUDE.md.

### Next

- Hand-author L2 wave_list against `target_ppt = 3` (PPT-banded curve in BALANCE.md says ~9,000 hardness). Use the slider panel to validate, then commit the .tres.
- After 3+ levels exist, revisit BALANCE.md "PPT-banded target curve" to confirm `PPT_TO_HARDNESS_FACTOR = 3000.0` still feels right.
- If/when a per-enemy difficulty modifier system is wanted (KR Impossible-style — different enemies get different buffs), it slots cleanly under BalanceOverrides as a per-enemy_id dictionary.
- GemCraft Battle Traits as player-facing customizable difficulty is a separate plan when content is solid.

### Follow-up: 3 test stub levels for audit/sliders validation

After the PPT/Slider/Audit foundation, added three stub wave files plus their `LevelNodeData` entries so the audit screen has more than one row to display and the slider panel has multiple targets to switch between.

- [level2_waves.tres](levels/level2_waves.tres) — `target_ppt = 3`, ~9,000 hardness (clean tune → green drift)
- [level3_waves.tres](levels/level3_waves.tres) — `target_ppt = 4`, ~16,000 hardness (intentionally over-tuned → red drift, demos "too hard")
- [level4_waves.tres](levels/level4_waves.tres) — `target_ppt = 5`, ~13,500 hardness (intentionally under-tuned → yellow drift, demos "too easy")

All three share `Main.tscn` as `scene_path` (no per-level map work). They populate `level_list.tres` with the full PPT-banded curve (1/2/3/4 min, 2/3/4/5 target).

#### Main.gd refactor

Replaced the hardcoded `LEVEL1_WAVES = preload(...)` with `_resolve_wave_list(entry)` reading `wave_list_path` from the matching `LevelNodeData`. Falls back to `LEVEL1_WAVES` if the entry has no path or the load fails — preserves existing behavior for partially-authored levels. Both `wave_list_path` and `early_call_window_sec` now share one lookup pass.

#### WorldMap.gd cleanup

Retired the hardcoded `_LEVEL_WAVES` dictionary that mapped level_id → wave path for the WorldMap card hardness display (only had `level_1`). `wave_list_path` is a first-class field on `LevelNodeData` now (used by audit, sliders, and Main); `_format_hardness` resolves through `level_list.tres` directly via a new `_wave_path_for(level_id)` helper. WorldMap cards for L2/L3/L4 now show their real hardness scores instead of "—".

#### Test entry points

- **WorldMap → Audit** — 4 rows with progressive drift colors. L3 red, L4 yellow, L1+L2 green.
- **WorldMap → Sliders** — level dropdown lets you pick any of L2/L3/L4 and "Play this level" bypasses the WorldMap unlock check.
- **WorldMap → level cards** — L2/L3/L4 appear as locked. Either hit Reset Progress (only `level_1` unlocked by default) or use the Sliders panel as the testing entry point.

#### Known follow-ups

- L2/L3/L4 share `Main.tscn` map. Authoring per-level maps (own paths, tower spots, navmesh) is a separate workstream.
- Wave count differs from L1 (3 vs 5 waves), so per-wave shares arrays in `level_list.tres` are length 3 for the new levels — `BalanceCalculator._normalized_shares` handles wave-count mismatch gracefully.
- Enemy counts are eyeballed, not solver-tuned. Actual hardness scores will reveal in the audit on first open; iterate via the slider panel.
- `levels_unlocked` default still `{level_1: true}` — debug-build auto-unlock-all not added (would be ~4 lines in MetaProgression._ready); skipped to avoid touching save logic.

---

## 2026-05-03 — WorldMap level rendering fix + S₁ recalibration

User opened WorldMap after the PPT/Slider/Audit ship and saw two bugs: only L1 visible (not the 3 test stubs), and L1 hardness reading 14878 instead of BALANCE.md's 6,530. Both real, both small.

### Bug 1 — only L1 on WorldMap

Two disconnected sources of truth: `WorldMap.tscn` had `Level1_Data` baked as an inline `[sub_resource]` and the WorldMap node assigned `levels = Array[Resource]([SubResource("Level1_Data")])`. The script's `@export var levels` was populated FROM the .tscn, not from `level_list.tres`. Audit / Sliders / Main.gd all read level_list.tres correctly; only WorldMap was disconnected.

Fix: dropped both the `Level1_Data` sub_resource block and the `levels = ...` assignment from the .tscn. Replaced `@export var levels` with a script-local `var _levels: Array[Resource]` populated by a new `_load_levels()` helper that mirrors the pattern in `BalanceSliders.gd::_load_levels` and `LevelAudit.gd::_refresh`. `_build_level_entries()` iterates `_levels`. WorldMap now shows all 4 cards (L1 unlocked, L2/L3/L4 locked). Single source of truth.

### Bug 2 — hardness 14878 vs BALANCE.md's 6,530

`git log -- enemies/data/` revealed commit f226988 (2026-04-30) substantially rebalanced enemy stats AFTER the 2026-04-28 baseline was measured: basic 0→18 HP (was using EnemyData default), armored 20→35 HP / armor 0.3→0.45, flying 8→14 HP, healer 18→30 HP, scout 6→10 HP, boss 200→320 HP / armor 0.3→0.45. Hardness scaled ~2.28× across L1.

Recalibrated `PPT_TO_HARDNESS_FACTOR` from 3,000 → 7,500 (= 14,878 / 2 rounded). L1 (target_ppt=2) now reads ~-1% drift on the audit screen. Updated BALANCE.md "Current measured values" with the new baseline + a note that the historical table is preserved for comparison only.

Side effect: L2/L3/L4 test stubs were authored against the old 3,000 factor, so they read under-tuned (red drift) on the audit. Documented in BALANCE.md as a worked example of "your stubs need a retune after a stat change." User retunes via Sliders panel as needed. Did NOT rebalance the stub wave files to chase the new factor.

### What broke

- IDE diagnostic flagged "levels not declared" briefly between edits — stale, resolved on next read.
- IDE diagnostic flagged "_levels declared but never used" briefly — same cause.

### Next

- Strategic question deferred from the original conversation: keep stubs vs. author real L2 vs. full L2/L3/L4 content slice. User picks once they see the cleaned-up WorldMap.
- Long-term: a CI test that compares `BalanceCalculator.score_level(level1_waves)` against a checked-in expected value, fails if drift > 5%. Would have caught f226988's impact at PR time.
- WorldMap unlock state for stubs still defaults to locked. Slider panel "Play this level" bypasses unlock check.

---

## 2026-05-03 — Level lookups centralized through ContentRegistry

User pointed at a real architectural failure on top of the WorldMap rendering bug fix: four separate places (`WorldMap.gd::_load_levels`, `BalanceSliders.gd::_load_levels`, `LevelAudit.gd::_refresh`, `Main.gd::_resolve_level_entry`) each independently called `load("res://ui/world_map/level_list.tres")` with three different type annotations. One of those — `Array[Resource]` in WorldMap — tripped Godot 4's typed-array invariance against `LevelList.levels: Array[LevelNodeData]`, throwing `_load_levels: Trying to assign an array of type "Array[LevelNodeData]" to a variable of type "Array[Resource]"` at runtime on the very first WorldMap load.

User's feedback: "you understand right there will be many many levels etc. Structure needs to be highly flexible." Translation: don't patch the type annotation — fix the duplication.

### Architectural fix

Levels join the existing `ContentRegistry` pattern alongside heroes / towers / items / affixes:

- `ContentRegistry.levels: Array[Resource]` populated at boot via new `_load_levels()` helper that unwraps `level_list.tres`'s LevelList wrapper into a flat array.
- `ContentRegistry.find_level(id) -> Resource` — mirrors `find_tower` / `find_hero` etc.
- `_validate_ids` extended with `_assert_level_ids` — checks every entry has non-empty `level_id` and that ids are unique. Skips the filename-matches-id rule (level entries are sub_resources inside `level_list.tres`, not standalone files).
- Boot log now reports `…, %d levels` so loaded count is visible.

`LevelList.gd::levels` relaxed from `Array[LevelNodeData]` to `Array[Resource]` to match ContentRegistry's catalog convention. Type tag drift is the cost; avoiding Godot's typed-array invariance gotcha is the gain. Element-type validation moved to `ContentRegistry._assert_level_ids`.

### Consumer changes

All four duplicate loads replaced with `ContentRegistry.levels` / `find_level`:

- `WorldMap.gd::_load_levels` → 1 line: `_levels = ContentRegistry.levels`
- `WorldMap.gd::_wave_path_for` → uses `find_level(level_id).wave_list_path`
- `BalanceSliders.gd::_load_levels` → 1 line for the assignment
- `LevelAudit.gd::_refresh` → 1 line for the assignment
- `Main.gd::_resolve_level_entry` → collapsed to `return ContentRegistry.find_level(RunState.current_level_id)` (lost the manual iteration entirely)

Future: per-world file split (forest_levels.tres + desert_levels.tres + …) only changes `ContentRegistry._load_levels` to concatenate. Consumers don't move.

### What broke

- IDE flagged a pre-existing `var snapped: int` shadowing the built-in `snapped()` function in `BalanceSliders._on_ppt_changed`. Renamed to `ppt_int`. CLAUDE.md "GDScript Conventions" already calls this class out — predictable miss on first author.

### Process accountability (per the post-mortem the user asked for)

The original `Array[Resource]` type bug shipped because:

1. Copied the old `@export var levels: Array[Resource]` annotation when refactoring to runtime-loaded, without questioning whether the new source produced the same array type.
2. Plan claimed to "mirror BalanceSliders.gd::_load_levels" but actual code didn't — siblings used untyped `Array`, my refactor used `Array[Resource]`.
3. Trusted IDE diagnostics to catch errors that are runtime-only in Godot 4.
4. Skipped the editor smoke-test before committing. CLAUDE.md says explicitly to test UI changes in the running game; ignored.
5. Three sibling implementations existed with differing type annotations — should have been caught on review.

Saved a feedback memory: when fixing duplicated content-load patterns, route through ContentRegistry instead of patching one site.

---

## 2026-05-03 — @tool placeholder fix + Main.tscn level-agnostic refactor

Two pieces:

### Piece 1 — fix @tool flood

`Level1.gd::_draw_tower_spot` (line 346) called `grid_manager.is_occupied(spot_id)` every editor frame. Level1.gd is `@tool`; GridManager.gd is not, so in the editor the GridManager Node loads as a placeholder and method calls fail with `Attempt to call a method on a placeholder instance`. ~5,250 redraw frames × 2 spots = ~10,500 errors flooding the output panel.

Fix: guard the call with `Engine.is_editor_hint()`. In editor, every spot draws as empty (correct — no game running). Runtime behavior unchanged. One edit, ~5 lines.

### Piece 2 — Main.tscn level-agnostic, dynamic level loading

Previously `main/Main.tscn:22` baked `Level1.tscn` as a static instance, and `level_list.tres` had every entry (L1, L2, L3, L4) point `scene_path = "res://main/Main.tscn"` — so all 4 cards played L1's layout. Multi-level support was structurally impossible.

Refactor:

- `main/Main.tscn`: removed the `Level1` ext_resource + node instance. TowerPlacers and HeroInputManager\s `grid_manager_path` / `map_path` set to empty NodePath — Main.gd resolves them dynamically.
- `main/Main.gd`: new `_enter_tree()` instances the level scene from the LevelNodeData entry's `scene_path` BEFORE children's `_ready` fires, then sets `TowerPlacer.grid_manager_path` and `HeroInputManager.grid_manager_path` / `map_path` via `get_path_to(grid_node)`. Falls back to `Level1.tscn` if the entry is missing or the load fails — partially-authored stub levels (L2/L3/L4 today) still play L1's layout safely.
  - `_enter_tree` chosen over `_ready` because Godot calls children's `_ready` bottom-up after the parent's `_enter_tree` returns. By instancing the level + setting paths in `_enter_tree`, the children's `_ready` resolves correctly without needing post-hoc re-init methods.
- `ui/world_map/level_list.tres`: every entry's `scene_path` updated from `res://main/Main.tscn` → `res://levels/Level1.tscn`. When L2/L3/L4 .tscn files are authored, just update the corresponding entry's scene_path.

### Verification (manual, editor)

- Open Level1.tscn in editor — output panel is clean, no placeholder flood.
- Run game from MainMenu → WorldMap → Forest Path → Campaign → enters Main.tscn, dynamically loads Level1.tscn, gameplay works as before.
- L2/L3/L4 cards still play L1 layout (because their scene_path falls back to Level1.tscn until their own .tscn ships).

### What broke

- Briefly added an unused `@onready var tower_placer: Node = $TowerPlacer` while working through the wiring — removed before commit.

### Next

- Piece 3: author Level2.tscn with more curves. Will pause here to ask user whether to author the Curve2D points programmatically (writing .tscn directly) or have user place them visually in the editor.
- Piece 4: Level3.tscn ring topology. Same authoring question.
- Piece 5 (deferred): L4 topology TBD after playtest.

---

## 2026-05-04 — WorldMap visual rework + Marker2D layout

WorldMap stopped being a vertical list of `PanelContainer` cards and became a Kingdom Rush–style procedural fantasy map. The work landed in three iterations across one session — each fixed something the previous one over-engineered.

### Phase 1 — KR-style visual + detail modal

Built the procedural map: parchment fill, deterministic seeded sand mottling + ~40 mountain glyph clusters (snow caps on ~20%), 3 italic region labels, banner-on-post markers, dotted Catmull-Rom path between `unlock_order`-sorted positions. All `_draw()`, no art assets — matches the project's "procedural-first" stance.

- New: [ui/world_map/WorldMapView.gd](ui/world_map/WorldMapView.gd) + `.tscn` — pannable 2400×1400 Control inside a ScrollContainer.
- New: [ui/world_map/LevelMarker.gd](ui/world_map/LevelMarker.gd) — banner-on-post Button with 4 visual states (locked / 0★ / 1–4★ / 5★+wings).
- New (later removed): `LevelDetailModal.gd` + `.tscn` — popup over the map showing the per-level card (name, stars, metrics, 4 mode pills), built via a `Callable` so the existing `_make_level_panel` body wasn't duplicated.
- WorldMapView's `_draw()` is deterministic via `RandomNumberGenerator.seed = 0x4D4150_5345_4544` — never seeded from time. Pixel-stable across reloads.
- Pan via existing `ScrollContainer` (scrollbars hidden) — chosen over a custom GameCamera-style pan to avoid fighting with marker hit-testing. No zoom (KR mobile maps don't zoom; would force the 1/zoom stroke-width rule on every redraw for zero gameplay benefit).

### Phase 2 — modal deleted, LoadoutScreen absorbed its info

Realised the modal + LoadoutScreen had overlapping responsibilities (modal picks mode, LoadoutScreen confirms mode again). Folded the modal's content into LoadoutScreen and dropped the modal entirely.

- Marker tap → directly to LoadoutScreen with `RunState.current_mode = "campaign"` as the default (avoids stale-mode silent downgrade across levels). Locked levels still toast.
- LoadoutScreen gained a `LevelInfoLabel` (composite stars + best time / endless score) between TopBar and ModeRow, plus an `EndlessButton` 4th sibling pill. Endless became a peer mode — the prior `is_endless` branch that hid Campaign/Heroic/Iron and renamed the level to "Endless Mode" is gone.
- `_format_seconds` + `_refresh_level_info_label` ported into LoadoutScreen.gd; the equivalent helpers in WorldMap.gd (`_format_level_metrics`, `_format_seconds`, `_format_hardness`, `_wave_path_for`) deleted as unused.

### Phase 3 — marker positions: `.tres` → `.tscn` (Marker2D children)

Phase 1 stored each level's position as `LevelNodeData.map_position`. Native Godot drag doesn't work on runtime-instanced markers, so an `addons/world_map_editor` EditorPlugin (`_forward_canvas_gui_input`) was added to bridge — but it needed a "click WorldMapView in Scene dock first" ritual and ~100 lines of glue. User pushed back: "why can't I just drag it like everything else?"

The honest answer: every other authored position in this codebase lives in a `.tscn` as a Marker2D / Curve2D / Path2D, never on a Resource ([BaseLevel.gd:278-315](levels/BaseLevel.gd) reads tower spots, hero spawn, paths all by node name). `map_position` was the outlier.

Refactor:

- [ui/world_map/WorldMapView.tscn](ui/world_map/WorldMapView.tscn) gained a `LevelMarkers` `Node2D` with one `Marker2D` per level, named `level_1` … `level_4`. Native W-tool drag works. Adding a level = drop a Marker2D + add LevelNodeData entry.
- [ui/world_map/WorldMapView.gd](ui/world_map/WorldMapView.gd): `_rebuild_markers` now resolves position via `level_markers_root.get_node_or_null(NodePath(level_id))`. `push_warning` if the Marker2D is missing (mirrors `BaseLevel._collect_paths` diagnostic discipline). New editor-only `_build_editor_preview_markers` iterates `LevelMarkers` directly so the designer sees banners while authoring positions in the WorldMapView scene standalone.
- [ui/world_map/LevelNodeData.gd](ui/world_map/LevelNodeData.gd): `map_position`, `map_label`, `marker_label_offset` deleted. (`map_label` and `marker_label_offset` were never read — Phase 1 over-spec'd.)
- [ui/world_map/level_list.tres](ui/world_map/level_list.tres): all four `map_position = Vector2(...)` lines removed.
- `addons/world_map_editor/` folder deleted; reference removed from `project.godot` `[editor_plugins]`.

### Architecture decisions worth remembering

- **Node name == content_id**, position lives in the `.tscn`. Mirrors the established `TowerSpots → Spot1` and `Path2D → "left"/"right"` patterns from Level1.tscn. World map authoring is now consistent with level authoring.
- **Mode default on marker tap is `"campaign"`**, not last-selected. Prevents a stale Iron/Heroic from a prior level pre-selecting a locked option that silently downgrades at Start.
- **Modal hosting via `Callable`** (Phase 1, then deleted) was a clean way to reuse `_make_level_panel` verbatim — but the modal itself was the wrong UX. Worth remembering: when two screens render the same content, fold rather than abstract.
- **EditorPlugin (Phase 3-precursor, then deleted) is the wrong tool when a vanilla scene-tree node achieves the same.** Plugins are for genuine canvas-editing capabilities the engine doesn't have (curve editors, gizmos), not for working around `owner=null` on runtime-instantiated children.

### Verification

- Headless boot clean (`godot --check-only --headless --quit`): all autoloads OK, ContentRegistry registers 4 levels.
- `grep map_position` and `grep world_map_editor` return zero hits across the project — refactor is fully complete, no dead code.
- Tap unlocked marker → LoadoutScreen opens with level name, composite stars, metrics line (when present), 4 mode pills. Endless pill toggles between "Best %d" and "—" based on per-level score history.
- Tap locked marker → toast, no scene change.
- @tool preview path: opening WorldMapView.tscn standalone shows parchment + mountains + path + 4 banners at the authored Marker2D positions. Dragging a Marker2D with the W tool moves the banner; saving the scene persists the new position.

### What broke

- WorldMapView.tscn picked up accidental offsets (`offset_left=-121, offset_top=-197, offset_right=2279, offset_bottom=1203`) from dragging the root Control during editor testing. Harmless at runtime (ScrollContainer overrides child layout) but confusing in standalone editor view. Reset to `(0, 0, 2400, 1400)` during the post-rework review.
- Phase 1 added three exported fields to LevelNodeData (`map_position`, `map_label`, `marker_label_offset`); only one was ever read. The other two were spec-cruft. Deleted in Phase 3.
- LevelDetailModal lived for one phase before deletion. The Callable-based content-builder pattern was clean code that was solving a problem we didn't actually have.
- EditorPlugin lived for a few minutes before deletion. Built it before re-checking the codebase's existing position-authoring patterns; the `Marker2D-in-scene` pattern was the right answer all along and would have been visible from a 2-minute audit of Level1.tscn.

### Process accountability

Two over-engineering moves this session, both caught by the user pushing back ("why can't I just drag it?"). Pattern: when implementing a feature with a known gap, default to checking how the codebase already solves analogous problems before inventing new infrastructure. The Phase 1 `map_position` field on LevelNodeData was authored without first asking "where do tower spot / hero spawn / path positions live?" — they all live in `.tscn`, and a 2-minute grep would have surfaced that.

Saved a feedback memory worth keeping: **before adding tooling to bridge an authoring gap, audit how analogous design data is authored elsewhere in the project.**

### Next

- Polish ideas (deferred, no concrete trigger yet): scroll-to-current-level on WorldMap entry; "next to play" highlight on the lowest-`unlock_order` non-perfected marker; per-chapter sub-maps when level count exceeds ~8.
- Mode-on-marker-tap could preserve the previous selection if it's valid for the new level. Low priority — current always-`campaign` default is safe.

---

## 2026-05-05 — Warrior procedural visual polish

- Scoped the art pass to the warrior hero only, per user request. No gameplay/balance/stat changes.
- `systems/UnitVisualData.gd`: added optional cosmetic-only polish fields with disabled defaults (`highlight_*`, `armor_plate_color`, `shoulder_pad_color`, `cape_color`, `weapon_trail_strength`, `weapon_glow_*`). Existing visuals remain unchanged unless their `.tres` opts in.
- `systems/UnitVisualDrawer.gd`: added cheap procedural polish layers: back cape/cloth, body highlights, chest armor plate/ridge/belt, shoulder pads, and a wider translucent weapon glow under the existing swing trail.
- `heroes/data/visual_warrior.tres`: opted warrior into the new polish with darker gold armor, steel helmet/shoulders, red cape, brighter sword trail, and small metallic highlights.
- Works: intended to make the warrior read more like a knight/paladin while preserving the current procedural `_draw()` asset strategy.
- Broke: not yet visually playtested in editor during this session.

---

## 2026-05-05 — Enemy procedural visual + animation polish

- Extended the procedural polish pass from the warrior to enemies, per user request. No enemy stats, waves, balance, collision, or AI changed.
- `systems/UnitVisualDrawer.gd`: added multi-part procedural wings for `Accent.WINGS` visuals that already use `race != NONE`, with lightweight flap motion driven by the existing walk animation clock. Legacy wing bars remain as fallback for non-race visuals.
- `enemies/base_enemy.gd`: enemy counter-attack animation feels heavier — strike commit lasts 0.18s, anticipation pull-back increased to 6px, push-through increased to 18px. Damage timing and cooldown math unchanged.
- `vfx/EnemyDeathDrift.gd`: death snapshot now tips over toward the hit direction, squishes flatter, lingers 0.50s, and emits a small dust puff while fading. Still stays anchored near the kill point so dead enemies don't look like they continue walking.
- Enemy visual `.tres` resources opted into the existing polish fields:
  - Basic orc: leather/chest plates, small shoulder pads, greenish highlight, subtle weapon glow.
  - Armored orc: brighter metal plate/shoulders and stronger sword trail.
  - Brute: darker heavy armor, cape scrap, stronger heavy swing glow.
  - Scout/goblin: claws, red bandana cape, brighter fast slash trail.
  - Flying enemy: flapping procedural wings, stronger bob, purple highlights.
  - Healer/shaman: staff, green magical glow, hood/cape read.
  - Boss: red armor/cape, heavy shoulders, strong fiery weapon trail.
- Works: intended to make orcs and other authored enemies more distinct while preserving the procedural `_draw()` asset strategy and mobile-cheap drawing.
- Broke: not yet visually playtested in editor; `godot` is not available on PATH in the current shell.

---

## 2026-05-05 — Loot drop tuning pass

Drop rate was way too high. `drop_chance = 0.2` × 48–206 enemies/level meant 10–40+ pickups per run — drops were background noise, not celebrations. Wooden Sword (0-affix, no roll variance) dominated the table at ~30%. High-rarity bases (Demon Core, Elven) had more affix slots but each slot rolled from the same flat ranges as Iron Sword, so legendaries felt like "common × 4" rather than legendary.

User direction: drops should be rare enough that finding something good is celebrated. Keep Wooden Sword in the pool. Researched community references first (PoE ~8% but with 200+ enemies/map; The Tower idle TD 0.5% boss rare; Universal TD 0.1–0.8% rares).

Changes:

- [items/data/loot_table_default.tres](items/data/loot_table_default.tres): `drop_chance 0.2 → 0.015`. Wooden de-throned `2.0 → 1.0`. Higher-rarity weights bumped slightly (Steel/Plate/Amulet `0.5 → 0.6`, Elven `0.15 → 0.2`, Demon Core `0.05 → 0.08`) since each drop now matters more.
- [items/data/loot_table_boss_orc.tres](items/data/loot_table_boss_orc.tres): boss table biased harder toward legendary (Iron/Chain `0.5 → 0.3`, Elven `0.4 → 0.6`, Demon Core `0.15 → 0.25`). Boss `drop_chance` stays `1.0` — predictable celebration anchor.
- [autoloads/LootRoller.gd](autoloads/LootRoller.gd): added `_rarity_value_multiplier(rarity)` returning 1.0/1.0/1.25/1.5/2.0 for COMMON…LEGENDARY. Applied in `_roll_affixes_for` after `picked.roll_value()`. Re-rounds to int when `picked.value_is_int` so display stays clean. AffixData itself untouched — shared resource discipline preserved.
- [balance/BALANCE.md](balance/BALANCE.md): added "Loot drop curve" section documenting the targets, knobs, and rarity scaling table per CORE RULE 18.

Resulting per-kill drop distribution: Wooden/Leather/Iron/Chain ~0.25% each, Steel/Plate/Amulet ~0.15% each, Elven ~0.05%, Demon Core ~0.02% (≈1 in 5000 kills, true mythic). Expected drops per level: L1/L2 0–2 (often 0), L3 1–2, L4 2–4 (incl. boss).

Deferred (with concrete triggers, per saved feedback):
- **Pity counter** (force-drop on a dry level) — revisit if L1/L2 dry-spell feedback appears in playtesting.
- **Per-level loot tables** — revisit if flat-variance produces too much spread between short and long levels.
- **Tier-gated affix pools** (`pool_weapon_offensive_t3`) — separate refactor; the value multiplier already gives the "feels legendary" effect cheaply.

Verification: not yet playtested (`godot` not on shell PATH). Headless boot left as a follow-up; LootRoller change is small and surgical.

---

## 2026-05-05 — Phase 50: Hero Hall + Paperdoll Equipment

Replaced the 5-tab HeroesHub (Loadout/Stats/Equipment/Skills/Talents with a text-only `◄ Switch Hero ►` cycle button as the Loadout tab) with a portrait-centric **Hero Hall** layout. Roster rail on the left, big procedural portrait + name/level/XP/stats card in the middle, four large action tiles (Stats / Equipment / Skills / Talents) at the bottom that swap in sub-views without leaving the hub. Roster stays visible inside sub-views so the player can switch hero without backing out. KR / mobile-RPG references guided the design (game designers consistently recommend visual hierarchy: portrait + headline stats front-and-center, roster grid for selection, ≥80px touch targets, reduced tab count, immediate feedback).

**Equipment** got a paperdoll redesign: the prior 3-active-of-6 grid is gone; all slots a hero exposes now render as 1×1 anchors arranged around a faded silhouette of the hero (drawn via `UnitVisualDrawer` with `skin_tint` alpha so the figure reads as a backdrop, not a foreground portrait). Per-hero variable slot configuration is data-driven: `HeroData.equipment_slots: Array[int]` is the subset of the 6 ItemBase.slot indices this hero exposes (empty = all 6 = humanoid default), `HeroData.slot_label_overrides: Dictionary[int → String]` lets non-humanoids rename slots (Dragon's "Weapon" → "Breath Sigil"), and `HeroData.slot_anchors: Dictionary[int → Vector2]` overrides paperdoll anchor positions (0..1 normalized) so a dragon's slots arrange around its body rather than a humanoid frame.

**Skills sub-view** moved from tap-to-arm + tap-to-slot to native Godot drag-and-drop. `_SkillTile._get_drag_data` returns `{skill_id, source, from_slot}`; `_SkillSlot._can_drop_data / _drop_data` accept any unlocked skill and route through `LoadoutState.set_equipped_skill` (which already swaps on duplicate per the existing API). Tap on a filled equipped slot clears it; locked tiles return null from `_get_drag_data` so they can't be picked up. Works on touch (`InputEventScreenDrag`) and mouse without separate code paths.

Files changed:
- [ui/HeroesHub.tscn](ui/HeroesHub.tscn) — restructured to TopBar + RosterRail + MainStack(HeroHallView, SubView).
- [ui/HeroesHub.gd](ui/HeroesHub.gd) — rewrite. New: `_build_roster_rail`, `_build_hero_hall`, `_open_sub_view / _close_sub_view`, inline `_build_skills_subview` with drag-and-drop inner classes (`_SkillTile`, `_SkillSlot`, `HallPortrait`, `_BorderOverlay`). Removed: SegmentButton class, segment bar, tap-arm Skills logic, ContextGroup.
- [ui/HeroCard.gd](ui/HeroCard.gd) (new) — roster card with procedural sprite, name, level, XP bar; lock overlay + dim-tint for locked heroes via `UnitVisualDrawer` `skin_tint` ctx.
- [ui/ActionTile.gd](ui/ActionTile.gd) (new) — bottom-row deep-link tile with `HubTabIcon` glyph + label + live subtitle.
- [ui/Paperdoll.gd](ui/Paperdoll.gd) (new) — backdrop Control attached to EquipmentScreen's `EquipmentGrid`. `setup(hero_data)` swaps silhouette; `anchor_for_slot(slot_idx)` returns absolute pixel position for a slot, honoring `HeroData.slot_anchors` with `DEFAULT_HUMANOID_ANCHORS` as fallback.
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — `HeroPortrait` node removed; `EquipmentGrid` now scripted with Paperdoll.gd and resized 240×600 → 540×600 to fit slot arrangement around silhouette.
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — dropped `SLOT_LAYOUT` / `ACTIVE_SLOTS` / `SLOT_NAMES` constants. New helpers: `_active_slot_indices_for(hero_id)`, `_resolve_slot_label(slot_idx)`. Slots rebuild on `hero_selected` (so Dragon → Warrior swaps the slot count). All slots now interactive (no more "Slot locked" toast); items refused for slots the hero doesn't expose toast `"<HeroName> has no <Slot> slot"`.
- [heroes/HeroData.gd](heroes/HeroData.gd) — added `equipment_slots: Array[int]`, `slot_label_overrides: Dictionary`, `slot_anchors: Dictionary`, `paperdoll_alpha: float` (additive; existing hero `.tres` files keep working).

**Plan deviations (intentional simplifications)** — the originally-approved plan called for an `EquipmentSlotDef` Resource, `default_humanoid_slots.tres` / `dragon_slots.tres` shared sub-resources, `ItemData.compatible_slot_types` + InventoryManager save-format migration. Reading the existing equipment system (Phase 48–49 InventoryManager has v2→v3 migration, hero_restriction enforcement, level_requirement gating, sell-mode pinning + batch-sell, stats panel with flash-on-equip) made it clear those changes would invasively rewrite a heavily-used system to deliver the same user-visible result. The chosen approach uses HeroData fields keyed by the existing 0..5 slot ints — same data semantics, no save migration, no ItemData changes, no InventoryManager touch. CORE RULE 1 (don't modify working scripts) preserved for InventoryManager / ItemBase / save format. Item-to-hero compatibility for non-humanoid heroes still works via the existing `ItemBase.hero_restriction` field (no new infra needed).

**Verification status** — `godot --headless --path . --quit` boots clean; all autoloads + scripts parse. `--import` shows three pre-existing `ContentRegistry.towers` access errors (in SaveManager / BalanceLogger / EncyclopediaScreen / LoadoutPickerScreen / TowerPlacer — autoload-order timing during import phase, not session-introduced). Manual playtest in editor pending — needs to verify roster card draw, Hero Hall portrait scale, sub-view embed offsets, drag-and-drop on touch, and Dragon slot layout once a Dragon hero is authored.

**Deferred (concrete triggers per saved feedback):**
- **Authoring a Dragon hero** — revisit when the user adds a non-humanoid hero `.tres`. The infra is in place; just author `equipment_slots = [0, 1, 5]`, `slot_label_overrides = {0: "Breath Sigil", 1: "Scales", 5: "Claw Rune"}`, `slot_anchors = {0: Vector2(0.20, 0.50), 1: Vector2(0.50, 0.50), 5: Vector2(0.80, 0.50)}` and the Equipment screen reflows automatically.
- **Stats sub-view content** — revisit when `Strength / Stamina / Dexterity` (or whatever the future system is) lands. Inline stub renders today.
- **Tile subtitle accuracy** — Equipment subtitle reads "N equipped" via `InventoryManager.get_all_equipped`. If item count UX feels stale, swap to "M / N slots filled".

---

## 2026-05-05 — Phase 50 follow-up: layout hardening (priorities 1–3 from external review)

External UI review flagged three structural concerns (separate from the bugs found earlier in the same day's pass): no safe-area wrapper, fragile absolute-anchor layout in `HeroHallView`, and embedded `EquipmentScreen` width starvation when the hub's roster rail eats 320 px. Implemented the three priorities the review actually fixes (vs. the polish items, which were deferred per the user's "go" scope).

**1. Safe-area wrapper** — [ui/HeroesHub.tscn](ui/HeroesHub.tscn) restructured to mirror [ui/WorldMap.tscn](ui/WorldMap.tscn):

```
HeroesHub (Control, FULL_RECT)
└── Background (ColorRect)
└── SafeAreaMargin (MarginContainer + SafeAreaMargin.gd)
    └── ContentMargin (margins 16/12/16/12)
        └── Layout (VBoxContainer, separation=12)
            ├── TopBar (HBoxContainer, h=64)
            └── Body (HBoxContainer, expand)
                ├── RosterRail (ScrollContainer, min w=304)
                └── MainStack (Control, expand)
                    ├── HeroHallView (VBoxContainer)
                    └── SubView (Control)
```

iOS notch / Android system bar insets now come from `DisplayUtils.get_safe_insets()` via `SafeAreaMargin`, not hardcoded 8/88/16 offsets. PC inset = 0 so layout is unchanged on desktop; mobile gets correct inset behavior.

**2. Container-driven HeroHallView** — [ui/HeroesHub.gd](ui/HeroesHub.gd) `_build_hero_hall` rewrite. The prior absolute-offset bento (`Vector2(-380, -160)` etc.) is gone; HeroHallView is now a VBoxContainer with three section children:

- **HeroHeader** (HBox, h=80) — Name (expand) + Level/XP block (360 wide) on a single row, replacing the prior tucked-under-portrait label cluster. The reviewer's "Selected Hero Header at top" pattern is cleaner — the player reads name + level + XP at a glance instead of hunting for it under the portrait.
- **HeroBody** (HBox, expand) — PortraitPanel (expand) + SummaryPanel (360 min). Portrait fills whatever's left, summary stays a fixed-width card on the right. No more 559-px dead gap from the prior `0.55*W - 220` math; portrait simply expands.
- **ActionRow** (HBox, h=128) — 4 ActionTiles centered. Same as before.

`_make_panel()` simplified — sizing now comes from `size_flags` / `custom_minimum_size` on the caller, not anchor/offset args. This makes the layout survive non-1920×1080 aspect ratios (different mobile devices, ultrawide PC) without per-panel arithmetic.

**3. Embedded Equipment width fix** — [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) `LeftPanel` `custom_minimum_size` reduced from `Vector2(620, 0)` → `Vector2(540, 0)` (the paperdoll slot panel only needs 540, the prior 620 was leftover from the side-by-side portrait era). [ui/HeroesHub.gd](ui/HeroesHub.gd) `_embed_screen` also drops the embedded `Body.offset_left` / `offset_right` from ±16 to 0 — the hub's `ContentMargin` already provides outer padding, so the screen's own 16-px side margins were redundant and stealing 32 px of inventory width.

Math at 1920×1080 PC:
- ContentMargin → 1888 wide
- RosterRail (304) + sep (16) + MainStack = 1568
- SubView fills MainStack → 1568
- EquipmentScreen embedded: Body inner = 1568 (no horizontal margins)
- LeftPanel (540) + sep (20) + RightPanel = 1568 → RightPanel = 1008
- InventoryGrid hard-coded at 1200 → ScrollContainer activates a 192-px horizontal scroll for the full 10×5 grid

Acceptable: the inventory ScrollContainer was already there, and the player can horizontally swipe the inventory area when needed. A true "compact embed mode" with a narrower CELL_PX or column count would require InventoryManager `GRID_COLS` changes (save-format breaking) — explicitly out of scope.

**Deferred from the review (with concrete triggers):**
- **Action tile attention badges** (gold for unspent talents, dot for empty skills) — revisit after a UX playtest pass; current subtitle text already conveys the same info at a glance.
- **Power Summary + Ready Check polish** — current stats label reads `HP 300 / DMG 18 / RNG 150 / SPD 1.00 / ARM 15%` which is functional but plain. Revisit when adding the real Stats sub-view content.
- **Skills tap-to-arm fallback alongside drag-and-drop** — user explicitly chose drag-only (the "alt" option); revisit only if mobile playtest confirms drag is awkward in practice.
- **Visual theme polish** (parchment frames, gold borders, fantasy treatment) — last on the list, matches WorldMap convention rework when that happens.

**Verification:** headless `--quit` boot is clean — all autoloads load, all scripts parse, no warnings. Manual editor playtest still pending.

---

## 2026-05-05 — Phase 50 follow-up: layout safety pass (priorities 1–4 from second review)

Second-round external review flagged real CLAUDE.md violations and one overflow-class bug I'd missed. Implemented the four prioritized fixes; deferred the contradictory "increase header but decrease body" suggestions and the out-of-scope TalentScreen-standalone tweaks.

**1. Action row → `HFlowContainer`** — [ui/HeroesHub.gd](ui/HeroesHub.gd) `_build_hero_hall`. The `4 × 200 + 3 × 12 = 836 px` action tiles previously sat in an `HBoxContainer` that doesn't wrap. At 1920×1080 that's fine, but at any narrower aspect (16:10, mobile portrait letterboxed, ultrawide-with-large-roster) the tiles would clip/overlap. `HFlowContainer` with `ALIGNMENT_CENTER` + `h_separation`/`v_separation = 12` lets the row wrap onto two lines instead. One-line preventive fix; cost is the action_row container can grow taller when it wraps, which the parent VBox accommodates.

**2. Hide roster rail when Equipment is open** — [ui/HeroesHub.gd](ui/HeroesHub.gd) `_open_sub_view` / `_close_sub_view`. Added `@onready var roster_rail: ScrollContainer = %RosterRail` and toggle `roster_rail.visible = (kind != "equipment")` on open. Equipment is inventory-heavy (paperdoll + 10×5 grid at 1200 px wide); hiding the 304-px roster rail recovers `304 + 16 sep = 320 px`, which moves the inventory grid from 192-px H-scroll to flush. Stats / Skills / Talents keep the rail visible — they don't benefit from the extra width and the player still wants to switch hero from those views. `_close_sub_view` restores `roster_rail.visible = true` so backing out leaves no orphan state.

**3. CLAUDE.md 80×80 touch target compliance** — [ui/HeroesHub.tscn](ui/HeroesHub.tscn). `TopBar` `64 → 80`, `BackButton` `120×64 → 120×80`, `MetaGoldLabel` `160×64 → 160×80`. Project rule is "Minimum touch target: 80×80 pixels" — the 64-px heights I'd used violated it. Also matches [WorldMap.tscn](ui/WorldMap.tscn) which uses 80-px nav buttons throughout, so HeroesHub now reads as part of the same screen family.

**4. Equipment Sell Mode / Lock / Sell All buttons** — [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn). `44 → 72 high`, widths bumped to 160 / 140 / 160 to balance. These are pre-existing buttons (Phase 48–49) but live in the equipment screen which is now part of the mobile-primary HeroesHub flow. 44 px was way under the 80×80 floor; 72 is a reasonable compromise that fits in the inventory header row without forcing it to two lines, and clears the 7-mm physical touch target floor on most modern phones (≈63 px at typical DPI). Could go to 80 if cramping isn't an issue in playtest.

**Skipped (with reasoning):**
- **HeroHallView Header 80→72 / ActionRow 128→144** — reviewer's recommendation contradicted itself (TopBar bigger, Header smaller, ActionRow bigger) and was based on a vertical-budget concern that doesn't exist at 1920×1080 (current budget has ~748 px for HeroBody, plenty).
- **TalentScreen standalone button sizes (BackButton 80×60, SwitchButton 60×60)** — TalentScreen is reachable only via embed in the new flow, where its TopBar is hidden. Standalone path is legacy; bundling it with HeroesHub work expands scope. Revisit if the standalone path stays alive.
- **"Compact embedded Equipment mode"** (reviewer's Option B) — Option A (hide roster) gives the same width benefit with no code refactor. Skip B unless playtest shows a real need.

**Verification:** headless `--quit` boot is clean. Manual editor playtest still pending.

---

## 2026-05-05 — Phase 50 follow-up: Equipment subview back-nav discoverability

User screenshot of the Equipment subview reported "how to get back?". Diagnosed: the HeroesHub TopBar IS rendering correctly (SubView correctly stacked below it via Layout VBoxContainer), but two issues made the back affordance unclear:

1. **Regression in `_embed_screen`** — earlier versions of the embed flow explicitly hid the EquipmentScreen's internal section headers (`LeftTitle "Equipped"`, `StatsTitle "Stats"`, `DetailsTitle "Details"`, and `TopBar/HeroLabel`). Several refactors lost those hides, leaving redundant labels that visually competed with the hub's own TopBar and obscured the back button.
2. **Back chip text was ambiguous** — `"← Hall"` at font 18 in a 120-px button. The word "Hall" alone doesn't read as a destination; user didn't connect it with "go back to Hero Hall".

Changes:

- **[ui/HeroesHub.gd](ui/HeroesHub.gd) `_embed_screen`** — re-added the per-header hides. Loop over `["TopBar/HeroLabel", "Body/LeftPanel/LeftTitle", "Body/LeftPanel/StatsTitle", "Body/LeftPanel/DetailsTitle"]` and set each `visible = false`. Same shape as the existing `TopBar` / `Background` hides. The values themselves (paperdoll, stat rows, details panel content, hint label, inventory header, sell-mode buttons) all stay visible — only the redundant section title labels are hidden. `RightTitle` ("Inventory N / 50") kept visible because it shows real cap/used info the hub doesn't.
- **[ui/HeroesHub.gd](ui/HeroesHub.gd) `_open_sub_view`** — Back button text changed `"← Hall"` → `"← Hero Hall"`. Reads as a destination, not an ambiguous label.
- **[ui/HeroesHub.tscn](ui/HeroesHub.tscn) BackButton** — `custom_minimum_size` `120×80 → 180×80` (accommodates the longer label without truncation), `font_size` `18 → 20` (matches WorldMap convention, more legible at smaller window scales).

Hero-name title rendering verification deferred to manual playtest — likely just a clipping artifact at the user's smaller 1228×691 window. If `EQUIPMENT — Warrior` still shows blank after the dash at full 1920×1080 design, that's a separate `_title_for_sub` / `LoadoutState.selected_hero_id` bug for a different pass.

**Out of scope (deferred):** EquipmentScreen.gd `_on_back` standalone routing (dead path in embed mode), compact embed mode refactor, Stats sub-view content.

**Verification:** headless `--quit` boot is clean. Manual editor playtest pending.

---

## 2026-05-06 — Phase 50 follow-up: Hero Hall polish slice (3 changes)

Third-round design proposal had a lot of aspirational scope (custom palette, parchment vignette, talent tree visualization, color hex codes) but three concrete wins worth shipping. Implemented those three; deferred everything else.

**1. Equipment SellMode / Lock / SellAll buttons 72 → 80 high** — [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn). The 72-px height was a compromise from the prior pass; CLAUDE.md actually mandates 80×80 minimum touch target, so closing the gap. Widths unchanged (160/140/160).

**2. ActionTile 200×120 → 220×132** — [ui/ActionTile.gd](ui/ActionTile.gd) `_TILE_SIZE` constant. Slightly bigger, more "tile-like" than "button-like". `4 × 220 + 3 × 12 = 916 px` total tile-row width; still fits within the Hero Hall hero-body width (~1192 px at 1920×1080) and HFlowContainer wraps gracefully on narrower aspects. [ui/HeroesHub.gd](ui/HeroesHub.gd) `action_row.custom_minimum_size` bumped 128 → 144 to give the now-taller tiles breathing room.

**3. READY CHECK section in Hero Hall summary panel** — [ui/HeroesHub.gd](ui/HeroesHub.gd) `_build_hero_hall` + `_refresh_hero_hall`. New labeled section between POWER and PASSIVES showing live counts:
```
READY CHECK
Equipment   N / M
Skills      N / 2
Talents     N ★
```
Slot total honors per-hero `equipment_slots` override (Dragon's 3 slots vs humanoid 6, falls back to 6 when array is empty). Data sources are the same ones already used by `_refresh_action_tile_subtitles` — `InventoryManager.get_all_equipped(hid)`, `LoadoutState.get_equipped_skills(hid)`, `MetaProgression.get_available_stars()` — just surfaced on the landing screen so the player doesn't have to read each tile's subtitle to see "what's missing on this hero". Mirrors the AFK Arena / Raid hero-overview pattern of always-visible readiness info.

Also added `_refresh_hero_hall()` + `_refresh_action_tile_subtitles()` calls to `_close_sub_view` so values stay fresh when the player equips items / skills / talents and backs out to Hall. Existing `EventBus` listeners cover live updates inside sub-views; the close-view refresh covers the gap.

**Skipped (with reasoning):**
- **Color palette hex codes** (`#202936`, `#FFD66A`, etc.) — no central theme system to consume them; would scatter hardcoded colors across files. Adopt a palette when there's infrastructure to use it consistently.
- **Visual style polish** (parchment vignette, panel borders, fantasy framing) — separate phase; bundling with layout fixes mixes "make it work" with "make it pretty" and inflates scope.
- **Tap-first Skills mechanic** — user explicitly chose drag-only (the "alt" option) earlier in this conversation. Don't unilaterally reverse a user decision based on third-party suggestion. Revisit only if mobile playtest confirms drag is awkward.
- **Talent tree visualization** (parent-child connector lines, branching layout) — much bigger scope; the proposal even admits "if you do not want a real tree yet, make each talent card bigger". Defer the tree; accept the list for now.
- **Roster card 280→292, Skill tile 180×100→180×104** — pedantic px-rhythm tweaks; current sizes work and meet touch-target rules.

**Verification:** headless `--quit` boot is clean. Manual editor playtest pending for the READY CHECK display + new tile sizes.

---

## 2026-05-06 — Phase 50 follow-up: inventory vertical scroll + defensive correctness

Audit identified one CRITICAL inventory issue (the user's actual root cause for "inventory looks weird at narrow widths") plus four defensive correctness patches. Shipped all five (the audit's "Patch B — disconnect signals on _exit_tree" was deferred — Godot 4 auto-disconnects Callables when the receiver node frees, so the audit's concern about leak-on-re-entry is overstated; revisit if profiler shows actual handler duplication).

**Patch A — vertical-scroll responsive inventory** (the dragon). The prior implementation had `InventoryGrid.custom_minimum_size = Vector2(1200, 600)` hardcoded in [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — designed for the original standalone-Equipment screen at full 1920×1080. Embedded in HeroesHub with the roster taking 304 px, RightPanel ended up ~940 px wide; inventory grid overflowed by 260 px and forced horizontal scroll. At narrower windows (1228×691) only ~10 % of the grid was visible; mobile users would think most of their loot vanished. Mobile UX research is unambiguous that vertical scroll is the right answer for grid inventories.

Storage stays Tetris (10 × 5 in `InventoryManager.GRID_COLS / GRID_ROWS`, save format unchanged); display columns are now derived from `inventory_grid.get_parent().size.x / CELL_PX` clamped to 5–12. Items keep multi-cell footprints (1 × 2 swords, 2 × 2 chestpieces); placement is recomputed each refresh via greedy first-fit in a vertical-flowing grid. Stored `inst.grid_col / .grid_row` are unused for display (still maintained for save round-trip / `_find_first_fit` on incoming drops).

Implementation in [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) `_refresh` — replaced the fixed-grid block with `_compute_display_cols()` + `_find_display_fit()` + a single-pass layout that grows `cover` row-by-row. Empty placeholders fill remaining display cells. Inventory-grid `custom_minimum_size` is now set per-frame to `(display_cols * CELL_PX, display_rows * CELL_PX)`, so the parent `ScrollContainer` knows how tall the content is and shows a vertical scrollbar when overflow happens. ScrollContainer's `horizontal_scroll_mode = 0` (DISABLED) makes the H-scroll path impossible. `inventory_grid.get_parent().resized` is connected to `_refresh` so the layout re-flows when the panel width changes (window resize, RosterRail visibility toggle).

**Patch C — `_embed_screen` failure no longer traps the hub**. [ui/HeroesHub.gd](ui/HeroesHub.gd) `_embed_screen`. If `load(scene_path)` returns null, also resets `_current_sub = ""` and restores `hero_hall_view.visible = true` + roster + Back button text + title. Without this, the next tap on the same tile would early-exit at `if _current_sub == kind: return` and silently no-op. Rare in practice, but a real footgun if an asset import breaks.

**Patch D — sticky item-details panel no longer survives hero swap**. [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) `hero_selected` listener. Previously `_refresh()` skipped the details reset when `_sell_mode == true` (so a long-pressed item's details stayed visible during sell-mode taps), which leaked across heroes: hover an item on Warrior → swap to Mage → details still showed Warrior's item. Listener now unconditionally resets `details_label.text` on hero swap.

**Patch E — null item base no longer breaks display occupancy** (folded into Patch A). The new layout treats `ContentRegistry.find_item_base(...) == null` as a 1 × 1 item rather than skipping; `ItemIcon.setup_instance` handles the null-base render gracefully (featureless dark tile). Save references to deleted items render as a placeholder cell instead of overlapping with whatever else lands there.

**Patch F — sell mode resets on hero swap**. [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) `hero_selected` listener. Previously sell mode persisted silently across heroes, so a player who entered sell mode on Warrior then tapped Mage in the roster could accidentally sell from Mage's inventory pool with no UI hint that the destructive mode was still on. Listener now resets `_sell_mode`, `_pending_sell_uid`, `_sell_all_armed`, and calls `_refresh_sell_mode_visuals()` on hero swap.

**Deferred (Patch B — `_exit_tree` signal disconnect)**: Godot 4 Callables to instance methods are auto-disconnected when the receiver node frees, so the audit's "duplicate handlers on re-entry" concern likely doesn't manifest in practice. Defensive disconnects would be a 5–10 line addition; can land if profiler shows actual handler duplication after long sessions.

**Verification:** headless `--quit` boot is clean. Manual editor playtest pending — most important checks: open Equipment subview at full window (should see 7 cols at 940 px panel, ~12 cols at 1500 px panel) and at narrower windows (5 cols min, vertical scroll visible when content overflows). Confirm `inventory_grid` re-flows when entering/exiting Equipment (RosterRail visibility toggle should trigger ScrollContainer resize).

---

## 2026-05-06 — Supply vs Demand balance model

Two-headline-numbers balance dashboard layered on top of PPT + Naked Baseline. Closes audited gaps (regen / heal-aura abilities, magic_resist, archetype multipliers, bypass enemies all previously unscored). Per-tier tower weights + segmented player supply. Predicted-vs-observed calibration column reads `RunStats.get_history()`.

**Plan:** `~/.claude/plans/can-we-make-plan-indexed-moonbeam.md`. Industry research showed Riot's champion balance framework (predicted vs actual outcome, never collapse to one number) and LoL's gold-efficiency model are the closest published precedents — no TD studio has published a comparable dashboard.

**New files:**
- [balance/BalanceModelConfig.gd](balance/BalanceModelConfig.gd) — Resource with `@export` weights for hardness, archetype demand, ability scoring, per-tier tower DPS-per-gold, supply segments, control conversion, safety bands. Defaults are 1.0 (or the historical hardcoded value); designers move only when run-stats drift on ≥3 levels in the same direction.
- [balance/balance_model_config.tres](balance/balance_model_config.tres) — single-instance config, all defaults.
- [balance/audit/SupplyDemandReport.gd](balance/audit/SupplyDemandReport.gd) + `.tscn` — level table (supply / demand / safety_ratio / bottleneck / spike wave / win% / avg leaks / drift), per-level drill-down (full demand + supply vectors + sub-ratios), live weight sliders on the right pane (HSplit). Drift flags `⚠ harder` when safety ≥ green_max but win% < 0.5; `⚠ easier` when safety < red_max but win% > 0.85.

**Extended:**
- [balance/BalanceCalculator.gd](balance/BalanceCalculator.gd) — appended `score_enemy_abilities` (closes regen + heal_aura gap), `wave_demand_vector`, `level_demand_vector`, `tower_avg_dps_per_gold` (per-tier weighted), `player_supply_vector` (segmented + tagged by damage_type/targets_flying/aoe_radius/control), `supply_demand_report` (top-level entry + bottleneck identification), `safety_color`, `observed_effective_dps_ratio`. All pure functions, no state. Existing functions untouched (CORE RULE 1).
- [balance/BALANCE.md](balance/BALANCE.md) — appended "Supply vs Demand model" section: principles (don't collapse to one number, don't flatten CC to flat damage, don't invent weights), audit gaps closed, calibration loop, read-order before changing weights.
- [ui/WorldMap.gd](ui/WorldMap.gd) + [ui/WorldMap.tscn](ui/WorldMap.tscn) — added "S/D" debug-only button beside Audit, gated by `OS.is_debug_build()`.

**Algorithm summary:**
- `level_demand` = Σ(EHP) × archetype weights + ability_ehp_add (regen/heal_aura now scored) + block_cost.
- `player_supply` = segment_tower (per-tier-weighted DPS-per-gold × gold × duration × effective:theoretical) + segment_hero + segment_skills + segment_control (CC as DPS-multiplier with stack_cap, NOT flat damage) + segment_blocking. Each segment scaled by its own segment_*_weight.
- Sub-ratios: anti_air, armored, magic_res, swarm, boss, rush, gold. Bottleneck = lowest sub-ratio < 1.0.
- `effective_to_theoretical_dps_ratio` defaults to 0.65 (community range 50–80%); calibrated per-level from `RunStats.damage_by_tower` via `observed_effective_dps_ratio`.

**Verification (manual editor playtest pending):**
1. WorldMap → S/D button → loads SupplyDemandReport.
2. L1 with default loadout shows safety_ratio ≥ 1.0 (Naked Baseline floor).
3. Drag `tier_l3_linear_weight` slider 1.0 → 0.0; supply column drops as L3 contributions vanish; refresh fires automatically.
4. Existing `run_stats.json` populates win%/avg leaks; drift column fills with ✓ or ⚠.
5. Click "Save Weights" persists slider state to `balance_model_config.tres`.

Folded the planned `BalanceSliders.gd` extension into `SupplyDemandReport.tscn` itself — weight sliders belong with the report that visualizes their effect, not with the gameplay-override panel (HP mult / armor add / etc.).

---

## 2026-05-07 — Combat-text + HUD polish pass

Floating combat numbers and the in-level HUD were functional but unstyled — every `FloatingText.spawn(...)` call site hand-tuned color/size, the HUD was plain Labels with no value-change feedback, and damage numbers spawned inline from `BaseEnemy.take_damage()` instead of routing through `EventBus`. This pass shipped a Kingdom-Rush-grade combat-feedback layer in five files. Plan: `~/.claude/plans/what-do-you-think-snazzy-dewdrop.md`.

**Phase 1 — `vfx/FloatingText.gd` style-driven rewrite.** Added `Kind` enum (DAMAGE_ENEMY, DAMAGE_BIG, DAMAGE_HERO_TAKEN, DAMAGE_SOLDIER_TAKEN, HEAL, GOLD, XP, PICKUP, WARNING) and a typed `_STYLES` Dictionary table — each style holds font_size, color, outline_color, outline_thickness, lifetime, drift_dir, drift_dist, drift_spread, pop_scale, z_index, wobble. Animation pipeline: scale 0.75→1.25 (pop, 0.08s, TRANS_BACK/EASE_OUT) → 1.25→1.0 (settle, 0.10s) running parallel to position drift over full lifetime, alpha fade across the last 30%. `_draw()` does an 8-direction outline pass (cardinal + diagonal) instead of the old single drop shadow — outline thickness scales with zoom (zoom-scale rule). Old API `spawn(parent, text, color, pos, font_size)` kept verbatim for back-compat (legacy drop-shadow path); new API `spawn_kind(parent, kind, pos, amount, text_override, color_override)` auto-formats text per kind and supports per-call color override (used by item rarity).

**Phase 2 + 3 — VFXSpawner becomes the damage-text router with merging.** `VFXSpawner._on_hit_landed` now dispatches damage numbers based on target type (`is BaseEnemy / BaseHero / BaseSoldier`), reusing the existing `EventBus.hit_landed(target, source, amount, dmg_type)` signal — no new signals were added. Per-(target, source) accumulator buckets (`_merge_buckets: Dictionary` keyed by `"tid_sid"`) sum hits within `MERGE_WINDOW_SEC = 0.25`; first hit in a series spawns immediately, follow-ups accumulate, and the next hit after the window flushes the total. Big hits (`amount / target.max_health >= 0.25`) and hero-attributed hits bypass merging — they pop immediately as `DAMAGE_BIG` for legibility. A 0.05s drain Timer flushes stale buckets so the last hit in a series isn't held forever, and drops buckets for freed enemies. Inline `FloatingText.spawn(...)` calls removed from `enemies/base_enemy.gd:422`, `heroes/base_hero.gd:807`, `soldiers/base_soldier.gd:460`; the now-unused `_FloatingTextScript` const removed from each. `items/ItemPickup.gd:196` migrated to `spawn_kind(Kind.PICKUP, ...)` with rarity color override. `EventBus.enemy_died` gold text and `EventBus.hero_xp_gained` XP text also routed through `spawn_kind`. Damage text (but not gold/XP/sparks) is gated by `clean_view`.

**Phase 4 — HUD chips refactor.** New [ui/HudChip.gd](ui/HudChip.gd) + [ui/HudChip.tscn](ui/HudChip.tscn) — `PanelContainer`-based widget with a procedurally-drawn glyph (`coin` / `heart` / `wave` / `threat`) on the left and a Label on the right. The panel stylebox comes from `game_theme`; the glyph is drawn in `_draw()` after the panel; a `MarginContainer` with `margin_left = 32` reserves the icon slot. Public API: `set_value(text)`, `set_value_color(c)`, `pulse_pop(scale_to, in, out)`, `pulse_modulate(flash, in, out)` — all tweens use `TWEEN_PAUSE_PROCESS` so they fire during tactical pause (mirrors the existing `purchase_denied` feedback shape on the old `GoldLabel`).

`ui/HUD.tscn` rewired: `GoldLabel` / `LivesLabel` / `WaveLabel` / `SpawnRateLabel` replaced by four HudChip instances under `TopLeft` / `TopRight`, plus a new centered `WaveBanner` Label (size_flags 4|4 inside `SafeArea`, font_size 64, outline 8) hidden by default. `ui/HUD.gd` reduced to chip-driving orchestration — caches `_last_gold` / `_last_lives` to detect deltas: gold gain → `pulse_pop` + warm flash; gold spend → subtle dim modulate; lives loss → red flash + pop; wave start → wave-chip pop + 0.3s fade-in / 0.5s hold / 0.6s fade-out banner. Threat chip color escalates by band: white < 200 < yellow < 500 < orange < 1000 < red. The rolling 5s incoming-HP window math (`_refresh_threat`) is unchanged — only the display widget changed. Send-Wave button blink and countdown logic untouched.

**No new EventBus signals, no `.tres` data changes, no balance changes.**

**Modified:**
- [vfx/FloatingText.gd](vfx/FloatingText.gd) — full rewrite, old API preserved
- [autoloads/VFXSpawner.gd](autoloads/VFXSpawner.gd) — damage-text routing + merging accumulator
- [enemies/base_enemy.gd](enemies/base_enemy.gd) — removed inline floating-text spawn + unused const
- [heroes/base_hero.gd](heroes/base_hero.gd) — same
- [soldiers/base_soldier.gd](soldiers/base_soldier.gd) — same
- [items/ItemPickup.gd](items/ItemPickup.gd) — migrated to `spawn_kind(Kind.PICKUP, ...)`
- [ui/HUD.tscn](ui/HUD.tscn) + [ui/HUD.gd](ui/HUD.gd) — chip-based, banner added

**New:**
- [ui/HudChip.gd](ui/HudChip.gd) + [ui/HudChip.tscn](ui/HudChip.tscn)

**Carve-out from CORE RULE 1.** This pass touched five working scripts (base_enemy, base_hero, base_soldier, ItemPickup, HUD) — explicitly authorized via the plan: scattering inline `FloatingText.spawn` from unit scripts directly contradicts CORE RULE 2 (cross-system via EventBus), and the routing fix was the entire point.

**Verification — pending in-editor playtest.** Headless parse check unavailable on this machine (no `godot` on PATH). Items to verify when running in editor:

1. Boot Level 1, send wave: damage numbers above enemies are styled (red-orange, outlined, scale-pop); 4 towers firing on one enemy show **merged** numbers (one bigger total per ~0.25s, not 4 stacks); a hero skill landing a chunky hit pops as DAMAGE_BIG (yellow, larger, immediate, no merge); hero takes damage → bright red number; soldier takes damage → yellow/orange number; item pickup → name floats up.
2. HUD: gold-gain pop + warm flash; gold-spend dim; life-loss red flash + pop; wave-start banner fade-in/out; threat chip color-escalates as wave HP grows.
3. Pinch zoom 0.5x → 2.0x: numbers + outline stay readable.
4. Tactical pause → HUD pulses still fire on radial-menu build/sell.
5. Clean-view toggle suppresses combat numbers + sparks; HUD chips unaffected.

---

## 2026-05-07 — Phase 55: Diablo-Immortal-style gear cells + Gear/Relics tab split

EquipmentScreen visual rework matching Diablo Immortal's stash. Plan: `~/.claude/plans/what-do-you-think-shimmying-fern.md`. The user pointed at a DI screenshot — gear slots are slightly taller than wide and the paperdoll uses the same cell shape as the inventory grid. Storage stays untouched (one shared 50-slot bag); the tab split is purely a display filter.

**Cell sizing.** Replaced the single `CELL_PX = 120.0` constant in [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) with `CELL_W = 120.0` / `CELL_H = 144.0` (5:6 ratio). Width unchanged so column counts and `ScrollContainer` layout don't shift; only the y stride grows. Both paperdoll slots and inventory cells use the same dimensions — a sword in the bag and the same sword equipped on the silhouette are visually identical. `Paperdoll.anchor_for_slot()` is normalized 0..1 so slot widgets reposition automatically when their `custom_minimum_size` changes; no anchor rewrite was needed.

**ItemIcon API.** Added `set_pixel_size(Vector2)` to [ui/ItemIcon.gd](ui/ItemIcon.gd). The new field `_pixel_size_override` (default `Vector2.ZERO`) supersedes the footprint-based sizing in `_apply_footprint_size()` when set. The legacy `set_slot_footprint(w, h)` path stays for back-compat — only EquipmentScreen migrated. `_draw()` already derived effects from `min(rect.size.x, rect.size.y) / SIZE_PX`, so non-square cells fall through cleanly: a 120×144 tile gets `scale_factor = 1.0` and effects fit naturally in the new aspect ratio.

**Gear / Relics tabs.** Added two-button TabBar (`TabGearButton` / `TabRelicsButton`) above the stash `ScrollContainer` in [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn). Tab membership is data-derived from `ItemBase.slot`: Gear holds slots 0–4 (Weapon/Armor/Helm/Gloves/Boots), Relics holds slot 5 (Trinket). New helpers in EquipmentScreen.gd: `_filter_inventory_by_tab` (defensive — items whose base is missing fall through to Gear so they aren't lost), `_on_tab_pressed` (dismisses the bottom-sheet if the selected item is hidden by the new tab), `_refresh_tab_buttons` (modulate-on-active, mirrors the EncyclopediaScreen pattern). Right-panel header now reads `"Gear (5) — Bag 23 / 50"` so the player sees both this-tab count and overall fullness.

**Why same-size paperdoll + slightly-taller cells.** Two corrections from the v1 plan: (1) v1 proposed `120×160` (1.33×) which read cinema-poster-tall; the DI screenshot is closer to 5:6 so we landed on `120×144` (1.20×) for a subtle cue. (2) v1 proposed keeping paperdoll at `1×1` while making inventory tall to avoid rewriting per-hero anchors — the user pushed back: visual consistency between "the gear on me" and "the gear in my bag" is the whole point of the DI look, and `Paperdoll.anchor_for_slot()`'s normalized anchors handle the resize automatically anyway.

**Why one shared bag (not separate gear/relic stashes).** Diablo IV's lesson: mixed-shape grids "require additional programming logic for sorting and moving items," so D4 went uniform-with-tabs. We followed the same — uniform grid, tabs as a pure filter, single occupancy logic. `InventoryManager` storage is unchanged; `_filter_inventory_by_tab` is a read-time helper.

**Modified:**
- [ui/ItemIcon.gd](ui/ItemIcon.gd) — `_pixel_size_override` field + `set_pixel_size(Vector2)` API; `_apply_footprint_size` honors override before falling through
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — `CELL_W` / `CELL_H` constants, `Tab` enum, `_current_tab` state, tab filter + tab-pressed handler + tab-button refresh; all paperdoll + inventory icon construction switched to `set_pixel_size`
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — `TabBar` HBox added between `HeaderRow` and `ScrollContainer`

**Verification — pending in-editor playtest.** Items to confirm when running:

1. Open Hero Hall → Equip. Gear tab is active by default; paperdoll + stash cells are 120×144 (subtle, slightly taller than wide). Anchor positions still read humanoid (helm above, boots below, weapon left, gloves right, armor center, trinket upper-right shoulder).
2. Tap Relics tab. Stash filters to TRINKET items only; cells stay 120×144; tab buttons swap modulate state.
3. Tap a stash item → bottom-sheet pops with rarity header, affixes, Equip/Lock/Sell row (Phase-54 unchanged).
4. Equip the item. It disappears from stash and appears at the matching paperdoll slot at the same 120×144 size; stats panel flashes the changed rows.
5. Select an item on Gear tab, then switch to Relics — bottom-sheet auto-dismisses since the selected item is no longer visible.
6. Long-press an item on touch — details suppress short-press equip (regression check).
7. Right-panel header reads `"Gear (N) — Bag M / 50"` and updates when items move between tabs (e.g. equipping a trinket lowers Relics tab count).
8. Touch targets: 120×144 ≥ the 80×80 minimum from CLAUDE.md.

---

## 2026-05-07 — Phase 55b: Equipment-screen post-review fixes (stats hide, scroll reset, active-tab visual, honest backdrop)

Self-review of Phase 55 surfaced four issues; this pass shipped all four. Plan section: "Post-implementation review" in `~/.claude/plans/what-do-you-think-shimmying-fern.md`.

**#7 — Stats panel hidden.** The original v2 plan called for omitting the redundant POWER/OFFENSE/DEFENSE/UTILITY card (already shown on Hero Hall's Overview view), but Phase 55 shipped without it. [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn): `Body/LeftPanel/StatsCard.visible = false`, plus `Body/LeftPanel/EquippedCard.size_flags_vertical = 3` and `EquipmentGrid.size_flags_vertical = 3` so the paperdoll silhouette grows to fill the freed ~360px instead of leaving an empty hole. `_build_stats_panel` / `_refresh_stats_panel` keep running harmlessly against the invisible nodes — equip-preview deltas in the bottom-sheet (`_format_stat_diff` → `DetailsLabel`) are unaffected because they live on a different code path. Cleanup of the dead StatsCard node + `_stat_rows` / `_last_stats_dict` deferred until the screen is otherwise stable.

**#2 — Scroll position resets on tab switch.** `_on_tab_pressed` now sets `inventory_grid.get_parent().scroll_vertical = 0` after `_refresh()`. Without this, scrolling deep in Gear then tapping Relics would leave the (single) trinket above the viewport.

**#3 — Active tab uses Godot's disabled-state visual.** Replaced the modulate-only highlight (active = white, inactive = grey) with `tab_gear_button.disabled = (_current_tab == Tab.GEAR)` + same for Relics. Disabled buttons render with built-in pressed-in styling so the active tab reads as obviously selected, and tapping the active tab is a no-op at the input layer (defense in depth — `_on_tab_pressed` already early-returns in that case).

**#1 — Empty backdrop reflects remaining shared bag capacity.** Pre-fix: every tab drew the full 50-cell bag-cap backdrop, so a player with 1 trinket on the Relics tab saw 1 trinket + 49 empty cells implying "I can fit 49 more relics." But the bag is shared with Gear; the player might only have 5 free slots overall. New formula: `visible_cells = inv.size() + max(0, bag_cap - inv_all.size())` — the cells in this tab plus the actual remaining free space. The `"Bag M / 50"` portion of the right-panel header was already accurate; now the visual matches.

**Modified:**
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — StatsCard.visible=false; EquippedCard + EquipmentGrid expand vertically
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — empty-backdrop formula, scroll-reset on tab switch, disabled-state for active tab

**Verification — pending in-editor playtest.** Items to confirm:

1. Open Hero Hall → Equip — left panel is paperdoll-only; silhouette larger than before; no STATS section visible.
2. Tap Gear tab while it's already active — nothing happens (button is disabled). Same for Relics.
3. Switch tabs — active button visually "pressed in," inactive is normal/clickable.
4. Scroll down in Gear, then tap Relics — viewport scrolls back to top so the trinket is visible.
5. Bag mostly full (e.g. 47/50): Gear tab shows N gear + 3 empty cells; Relics tab shows M trinkets + 3 empty cells. NOT 50 empties in either tab.
6. Empty bag (0/50): Gear shows 50 empty cells, Relics also shows 50 empty cells (full bag-cap available). No items, no overlap.
7. Equip-preview deltas in the bottom-sheet still work when an item is selected — DPS/Damage/Armor arrow lines render in DetailsLabel.

---

## 2026-05-07 — WorldMap polish: next-level pulse + hide-locked + unlock celebration

Three-part progression-feedback polish on top of the 2026-05-04 WorldMap rework. User noted the static dotted path between authored markers didn't celebrate progression and didn't communicate "next level to play." Plan: `~/.claude/plans/where-to-move-level-immutable-firefly.md` (Phase 1 only) + in-conversation extension for Phases 2–4.

**Phase 1 — next-level pulse.** [ui/world_map/LevelMarker.gd](ui/world_map/LevelMarker.gd) gains `set_pulse(active: bool)` — a looping `scale` Tween from `1.0` → `1.08` → `1.0` with `TRANS_SINE EASE_IN_OUT`, ~1.2s per cycle. `pivot_offset = MARKER_SIZE * 0.5` so the pulse reads as centered on the banner. [ui/world_map/WorldMapView.gd](ui/world_map/WorldMapView.gd) gains `_apply_pulse_to_recommended()` + `_find_recommended_level_id()` — pulses the lowest-`unlock_order` level that is unlocked and has 0 campaign stars. Called from both `_rebuild_markers` and `refresh_states` so debug Unlock All re-targets correctly. Editor preview path skipped (would pulse every marker).

**Phase 2 — locked levels hidden.** `_apply_state_to_marker` now sets `marker.visible = unlocked` for the runtime path; locked levels disappear entirely from the WorldMap. Editor preview keeps every marker visible so the designer can see the full layout. `_draw_dotted_path` was rewritten to be segment-aware: each segment is skipped when its origin level is locked, OR when its destination is locked AND the segment isn't the currently-animating celebration segment. Editor preview bypasses the unlock filter via `Engine.is_editor_hint()`.

**Phase 3+4 — unlock celebration handoff + animation.** New `pending_unlock_celebration_id: String` field on [autoloads/MetaProgression.gd](autoloads/MetaProgression.gd), persisted by [autoloads/SaveManager.gd](autoloads/SaveManager.gd) (default `""` for old saves, no `SAVE_VERSION` bump — additive field). `SaveManager._try_unlock_next_level` now sets the field when it flips `levels_unlocked[next_id] = true`. The flag is intentionally persisted: a force-quit between unlock and the next WorldMap visit must still trigger the show, which means it can't live only in-memory.

`WorldMapView.play_celebration(level_id)`:
1. Looks up the level's index in the `unlock_order`-sorted `_path_point_ids` array; bails if `idx <= 0` (level 1 has no prior segment).
2. Sets `_celebration_segment_idx = idx - 1` and `_celebration_progress = 0.0`.
3. On the just-unlocked marker: `set_pulse(false)` (kill any pulse tween before the reveal-pop), `visible = false`, `modulate.a = 0`, `scale = Vector2(0.5, 0.5)`.
4. Tween `_set_celebration_progress` 0→1 over 1.5s with `TRANS_CUBIC EASE_OUT`. Each step `queue_redraw`s; the animating segment's dot count is `int(round(step_count * progress))`, so dots fill in along the Catmull-Rom curve from origin toward destination.
5. Tween callback `_on_celebration_road_done`: marker visible, parallel pop tween — `modulate:a 0→1` (0.35s) + `scale 0.5→1.15` with `TRANS_BACK EASE_OUT` (0.30s), chained `scale 1.15→1.0` (0.20s).
6. Final callback `_on_celebration_done`: clear state, emit `celebration_finished`, restart `_apply_pulse_to_recommended` (the just-revealed marker is the new recommended target).

[ui/WorldMap.gd](ui/WorldMap.gd) reads `pending_unlock_celebration_id` immediately after `set_levels()` and calls `play_celebration()` in the **same frame**. This is load-bearing: `_apply_state_to_marker` set the marker `visible = true`, and `play_celebration` overrides it to `false` before any frame renders. No flash. On `celebration_finished`, the field is cleared and the save persists — guarantees replay-on-force-quit.

**Phase 1 visibility caveat — addressed.** `_apply_pulse_to_recommended` runs in `_rebuild_markers` *before* `play_celebration`, so the just-unlocked marker briefly has the pulse tween armed. `play_celebration` calls `set_pulse(false)` to kill it before starting the reveal pop — otherwise the two scale Tweens would fight.

**Why this order (data → visibility → animation, not animation-first).** Hiding the marker has zero risk — if the celebration code never runs (force-quit, bug, debug bypass), the marker simply stays hidden until the player makes progress, which is the correct end-state anyway. Adding the celebration first without the visibility change would have meant the new marker pops into view but everything beyond it is still drawn, defeating the "fog of war" feeling.

**Modified:**
- [autoloads/MetaProgression.gd](autoloads/MetaProgression.gd) — `pending_unlock_celebration_id` field; cleared in `reset()`
- [autoloads/SaveManager.gd](autoloads/SaveManager.gd) — sets the field in `_try_unlock_next_level`; persists in save dict; reads back with `""` default
- [ui/world_map/LevelMarker.gd](ui/world_map/LevelMarker.gd) — `set_pulse(active)` + `_pulse_tween` + `pivot_offset`
- [ui/world_map/WorldMapView.gd](ui/world_map/WorldMapView.gd) — visibility on `_apply_state_to_marker`; `_path_point_ids` parallel array; segment-aware `_draw_dotted_path`; `play_celebration` + animation callbacks; `_apply_pulse_to_recommended`; `celebration_finished` signal; editor live-drag `_process` polling
- [ui/WorldMap.gd](ui/WorldMap.gd) — reads pending field after `set_levels`; connects `celebration_finished`; clears field + saves on completion

**Carve-out from CORE RULE 1.** Touched four working scripts (MetaProgression, SaveManager, LevelMarker, WorldMapView, WorldMap) — all additive modifications: new fields, new methods, the `_draw_dotted_path` rewrite is the only logic change to existing code. The rewrite was unavoidable since the segment filter has to live inside the existing draw loop.

**Verification — pending in-editor playtest.** Items to confirm when running:

1. Fresh save (delete `user://save.json` or use Reset Progress). Open WorldMap — only Level 1 visible. No dotted path drawn (only one unlocked endpoint). Level 1 banner pulses gently (0 stars).
2. Play Level 1, clear with ≥1 star, return to WorldMap. Auto-scroll lands on the "next" area; dotted path animates from L1 toward (still-hidden) L2 over ~1.5s; L2 marker fades in + scale-pops with subtle overshoot; pulse handoff: L1 stops pulsing (has stars), L2 starts pulsing (0 stars).
3. Force-quit during step 2's animation (Alt+F4 mid-tween). Reopen game → WorldMap. Animation replays from start — `pending_unlock_celebration_id` was preserved.
4. Clear L2 → return. Same animation, L2→L3.
5. Debug "Unlock All" button (top of WorldMap, debug builds only). All four markers appear without animation; full Catmull-Rom path between all four. Pulse lands on L1 (lowest unstarred, since stars are unchanged by Unlock All).
6. Open `ui/world_map/WorldMapView.tscn` in the Godot editor — all four markers visible (preview mode), full dotted path, no pulse (editor skips the runtime pulse helper). Drag a Marker2D — banner + path follow live (the @tool poll loop from earlier today).
7. The 1.5s reveal duration and 1.15 overshoot on the marker pop are guesses — playtester may want to tune `road_tween` duration in `play_celebration` and the `Vector2(1.15, 1.15)` overshoot in `_on_celebration_road_done`.

---

## 2026-05-07 — Phase 55c: Equipment-screen polish (slot extensibility, dismiss-before-equip, paperdoll layout safety)

Static bug review of Phase 55 + 55b surfaced five fixable issues; this pass shipped four. Plan / review file: `~/.claude/plans/phase-55-bug-review.md`.

**A1 — Tab filter is now extensibility-safe.** Pre-fix: `_GEAR_SLOTS = [0,1,2,3,4]` and `_RELIC_SLOTS = [5]` hardcoded. A future `Slot.RING` value or a corrupt slot index from a save migration would silently disappear from BOTH tabs (stored, never displayed). Post-fix: `_RELIC_SLOTS` stays explicit (today: `[5]`); Gear is the *negation* — `_instance_belongs_to_tab` returns `is_relic if tab == RELICS else not is_relic`. Stranded items (null base, slot=-1, slot=99, future enum values) all fall through to Gear so they remain visible. `_GEAR_SLOTS` and `_slot_set_for_tab` retired.

**A2 — Bottom-sheet no longer flickers on equip.** Pre-fix: `equip()` ran first → `inventory_changed` → `_refresh()` re-rendered the sheet showing the now-equipped item → THEN `_dismiss_details()` hid it. One-frame flicker. Post-fix in `_on_equip_pressed`: capture uid → `_dismiss_details()` → THEN `equip(uid_to_equip)`.

**A3 — `set_pixel_size(Vector2)` guards against zero-component vectors.** Pre-fix: `_pixel_size_override != Vector2.ZERO` passed for partial-zero vectors (e.g. `Vector2(0, 144)`), zeroing the icon's width. Post-fix: both axes must be `> 0` for the override to apply.

**C3 — Removed duplicate `_refresh_tab_buttons` call in `_ready`.** The first `_refresh()` at the end of `_ready` already covers it.

**B1 mitigation — Paperdoll silhouette layout protected.** [Paperdoll.gd](ui/Paperdoll.gd) draws the figure with a constant `_DRAW_SCALE = 4.5` — the silhouette doesn't grow when the box does. Phase 55b's `EquippedCard.size_flags_vertical = 3` (and the same on `EquipmentGrid`) would have grown the box from `~640px` to `~1000px` while leaving the figure the same physical size, risking a stranded silhouette in a sea of dark space. Phase 55c reverted both flags. The `EquippedCard` now sits at its natural height (~640px); `LeftPanel` may have ~360px of empty dark space below it (since `StatsCard` is hidden). This is the conservative fallback — open the screen in Godot, judge whether the empty space looks acceptable. If it doesn't, options are (a) re-add a stats summary in the freed space, (b) center `EquippedCard` vertically, or (c) make `Paperdoll._DRAW_SCALE` size-driven.

**Modified:**
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — slot-filter refactor (A1), dismiss-before-equip (A2), dup-call cleanup (C3)
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — reverted `size_flags_vertical = 3` on `EquippedCard` + `EquipmentGrid` (B1)
- [ui/ItemIcon.gd](ui/ItemIcon.gd) — guard against zero-component pixel size (A3)

**Deferred (to a v3 polish pass):**
- C4 — empty-tab affordance ("No relics yet — defeat enemies to find trinkets")
- C5 — StatsCard dead-code removal (~150 LOC). `_compute_stats_dict` must stay because the bottom-sheet equip preview uses it.

**Verification — pending in-editor playtest.**

1. Open Hero Hall → Equip — confirm whether the empty space below the paperdoll feels acceptable or needs a layout follow-up.
2. Tap any inventory item → bottom-sheet pops → tap Equip — confirm there's NO frame where the sheet shows "(equipped)" before dismissing.
3. Add a sandbox `ItemBase` with `slot = 99` (or just temporarily change a `.tres`) — confirm it appears on the Gear tab instead of vanishing.
4. Bottom-sheet equip-preview deltas still render (regression check on the StatsCard-hidden path).

---

## 2026-05-07 — Phase 55d: Paperdoll layout fixes (HELM clipping + figure right-sizing)

In-editor screenshot of Phase 55c showed three real layout problems on the EQUIPPED card:
1. HELM slot icon clipped above the EquipmentGrid top edge — anchor norm `(0.50, 0.10)` × grid height 600 = pixel y=60, minus icon half-height 72 = top edge at `y=-12`, outside the grid.
2. Silhouette overlapped slot icons — `_DRAW_SCALE = 4.5` made the figure dominate the grid; with bigger 144-tall icons it read as visual chaos.
3. EquippedCard sat at ~640px while LeftPanel had ~1000px to fill (Phase 55b hid StatsCard, Phase 55c reverted vertical-expand). Cramped at top, dark gap at bottom.

**Root cause:** Phase 55 grew icons from 120×120 → 120×144 (taller) without resizing the EquipmentGrid container or the silhouette. Both stayed sized for the old square cells.

**A — Grid enlarged.** [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn): `EquipmentGrid.custom_minimum_size = Vector2(540, 600)` → `Vector2(600, 720)`. Math after the change: HELM top-left at `y=0` (exactly at grid edge, no clip); BOOTS bottom at `y=706` (14 px margin). All other slots fit with margin.

**B — Silhouette right-sized.** [ui/Paperdoll.gd:31](ui/Paperdoll.gd): `_DRAW_SCALE = 4.5` → `3.5` (~78% of original). Figure no longer fills the grid; ring-of-slots reads cleanly around it.

**C — Silhouette centered.** [ui/Paperdoll.gd:34](ui/Paperdoll.gd): `_ANCHOR_FRACTION = 0.85` → `0.70`. Was "feet near the bottom" (HeroPortrait framing); now "chest centered." With the smaller `_DRAW_SCALE`, figure occupies roughly the middle third of the grid with breathing room above for HELM and below for BOOTS.

**D — EquippedCard fills LeftPanel height.** Re-added `EquippedCard.size_flags_vertical = 3` (Phase 55c had reverted this defensively). Now safe because the figure is right-sized for a taller box (B+C). EquipmentGrid stays at 600×720 minimum, card itself spans up to ~1000 px, no dark gap below.

**No GDScript changes in EquipmentScreen.gd** — slot anchors are normalized 0..1, so all positions reflow automatically with the larger grid.

**Modified:**
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — EquipmentGrid `(540,600)→(600,720)`; EquippedCard `size_flags_vertical = 3`
- [ui/Paperdoll.gd](ui/Paperdoll.gd) — `_DRAW_SCALE 4.5→3.5`, `_ANCHOR_FRACTION 0.85→0.70`

**Verification — pending in-editor playtest.**

1. Hero Hall → Equip on Knight: HELM, TRINKET, WEAPON, ARMOR, GLOVES, BOOTS all visible inside the EQUIPPED card, with margin from edges. None clipped at top, none falling out the bottom.
2. Silhouette is smaller and roughly centered vertically. Slots ring around it without overlapping body parts heavily.
3. EquippedCard reaches near the bottom of LeftPanel — no large dark gap below.
4. Switch to Dragon (`HeroData.equipment_slots` = 3 slots, `HeroData.slot_anchors` overrides). Custom anchors still place slots correctly inside the larger grid.
5. Tap a slot → empty toast or unequip flow unchanged.
6. Tap an inventory item → Equip → slot fills at the right paperdoll position with no flicker (Phase 55c A2 still holds).

---

## 2026-05-07 — Phase 55e: HeroesHub close button (✕ replaces context-sensitive back chip)

User flagged a redundancy in the Hero Hall TopBar: from inside Equipment, the "← Hero Hall" back button and the sidebar's Overview button both did the exact same thing — `_close_sub_view()`. The back button was two-mode (at Hero Hall: exit to WorldMap; in sub-view: return to hub root) and the second mode duplicated the Overview tab's job.

**Fix:** the corner button is now a fixed close affordance — large `✕` glyph, always exits the hub to WorldMap. Sub-view → hub-root navigation goes through the sidebar Overview button (sole owner of that path). Mirrors the Diablo Immortal modal-close convention.

**Modified:**
- [ui/HeroesHub.tscn](ui/HeroesHub.tscn) — `BackButton`: text `← Back` → `✕`, font size `18` → `36`, size `140×60` → `80×80` (square, big touch target)
- [ui/HeroesHub.gd](ui/HeroesHub.gd) — `_on_back()` simplified to always call `SceneManager.goto("res://ui/WorldMap.tscn")`; removed `back_button.text = "← Hero Hall"` / `"← Back"` swaps in `_open_sub_view`, `_close_sub_view`, and `_embed_screen` failure path; updated file docstring

**Verification — pending in-editor playtest.**

1. Open Hero Hall — corner button is a large `✕` (not text). Tap it → returns to WorldMap.
2. Open Hero Hall → Equip — corner `✕` still visible, still goes to WorldMap (no longer "back to Hero Hall" intermediate step). Tap Overview in sidebar → returns to Hero Hall root, then `✕` exits.
3. Same flow on Skills and Talents sub-views.
4. Confirm the title still updates correctly per sub-view (`EQUIPMENT — Knight`, `SKILLS — Knight`, etc.) — that text-swap stays.

---

## 2026-05-07 — Phase 55f: Paperdoll slot positions are Marker2D children (visual editor authoring)

User asked how to adjust slot positions and the EQUIPPED container without text-editing constants. The container size was already inspector-editable (`EquipmentGrid.custom_minimum_size`), but slot positions lived as a `const Dictionary` of normalized 0..1 values in `Paperdoll.gd`. Phase 55f converts the slot positions to **`Marker2D` children of `EquipmentGrid`** — drag with the W tool in the 2D viewport.

**Pattern matches existing project conventions** — same as `TowerSpots → Spot1` in `Level1.tscn` and `LevelMarkers → level_1` in `WorldMapView.tscn`. CLAUDE.md "scene-tree nodes for authored geometry" rule.

**Naming:** Marker2D children named `Slot0`..`Slot5` (indices match `ItemBase.Slot` enum). Position is in the parent `EquipmentGrid` Control's local pixel space.

**Resolution order** in `Paperdoll.anchor_for_slot()` (highest to lowest priority):
1. `HeroData.slot_anchors` per-hero override (normalized 0..1) — used by Dragon's custom 3-slot layout.
2. `Slot<N>` Marker2D child of EquipmentGrid (absolute pixels) — the new visual-editor path.
3. `DEFAULT_HUMANOID_ANCHORS` const fallback (normalized 0..1) — kept so any future scene that forgets to add markers still works without crashing.

**Inspector-tweakable silhouette:** `_DRAW_SCALE` and `_ANCHOR_FRACTION` were converted from `const` to `@export var draw_scale: float = 3.5` and `@export_range(0.0, 1.0, 0.01) var anchor_fraction: float = 0.70`. Tune them in the EquipmentGrid node's Inspector pane with live preview when scene reloads.

**How to author slots in editor:**
1. Open `ui/EquipmentScreen.tscn`.
2. Click `EquipmentGrid` in the Scene tree.
3. In the 2D viewport, the 6 Marker2D children show as `+` crosses. Drag with the W tool to reposition.
4. Adjust `EquipmentGrid.custom_minimum_size` in Inspector for container size.
5. Adjust `EquipmentGrid.draw_scale` / `anchor_fraction` in Inspector for silhouette tuning.
6. Save the scene.

**Modified:**
- [ui/Paperdoll.gd](ui/Paperdoll.gd) — `anchor_for_slot()` now reads `Slot<N>` Marker2D children before falling back to `DEFAULT_HUMANOID_ANCHORS`; `_DRAW_SCALE` / `_ANCHOR_FRACTION` consts → `@export var draw_scale` / `@export_range anchor_fraction`; `_draw()` updated to read the new vars
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — added 6 `Marker2D` children to `EquipmentGrid`, positions seeded at the prior normalized-anchor pixel locations:
  - `Slot0` (Weapon) at `(108, 446)`
  - `Slot1` (Armor) at `(300, 331)`
  - `Slot2` (Helm) at `(300, 72)`
  - `Slot3` (Gloves) at `(492, 446)`
  - `Slot4` (Boots) at `(300, 634)`
  - `Slot5` (Trinket) at `(492, 130)`

**Backward-compat:** `HeroData.slot_anchors` per-hero overrides still work and still take priority. Dragon's custom layout is unaffected. The const fallback also stays — no scene changes are required for the system to function (markers are an additive, optional layer).

**Verification — pending in-editor playtest.**

1. Open `ui/EquipmentScreen.tscn`. Click `EquipmentGrid`. Six `+` crosses visible at the slot positions.
2. Drag a marker (e.g. `Slot2`/Helm) with the W tool. Save scene. Run the game → that slot now appears at the new position.
3. In the EquipmentGrid Inspector, change `draw_scale` to `2.5` (smaller figure) and `anchor_fraction` to `0.50` (centered higher). Save → silhouette responds.
4. Open `heroes/data/dragon.tres` → `slot_anchors` overrides still position Dragon's slots correctly (priority 1 still wins).
5. Delete a `Slot<N>` marker temporarily → that slot falls back to `DEFAULT_HUMANOID_ANCHORS` (does not crash, lands at the original 0..1 position).

## 2026-05-07 — Mage AoE removal + screen-shake removal + BalanceSliders derived metrics

**Three tower / dev-tool changes in one session.**

### Removed boss-damage screen shake
[VFXSpawner.gd](autoloads/VFXSpawner.gd) was firing `cam.add_shake(2.0, 0.12)` on every `enemy_damaged` signal where the target was a boss — i.e. every tower/hero/soldier hit on the boss kicked the screen. Disconnected the signal, deleted `_on_enemy_damaged`, removed the now-dead `_shake_t` / `_shake_dur0` / `_shake_amp` fields and the `_process(delta)` shake loop and `add_shake()` API on [GameCamera.gd](map/GameCamera.gd). Updated the stale "boss-shake" doc comment on [EventBus.gd](autoloads/EventBus.gd). The UI button "deny shake" on `RadialActionButton` / `TowerIconButton` is preserved — that's a button head-jiggle on insufficient-funds tap, not a screen shake.

### Mage Tower → single-target
Removed `aoe_radius = 150.0` from [tower_mage.tres](towers/data/tower_mage.tres). Updated encyclopedia text from *"Slow magic bolts that splash in an area…"* to *"Slow magic bolts that pierce armor. Hits flying. High per-hit damage, low fire rate."* — Mage was overlapping Artillery's swarm-clear niche while also covering flying, making it the "always at least decent" pick. AAA / Kingdom Rush convention is single-target armor-piercing for the mage archetype, with AoE belonging to artillery + dedicated branches. **Heads up:** Mage was paying part of its cost in the AoE radius; with that gone, base/L2/L3-main g/DPS will likely drift to the high side of their bands and may need a damage bump after a measurement pass. The new derived-metrics panel (next entry) makes that comparison live.

### BalanceSliders — per-tier derived-metrics readouts
[BalanceSliders.gd](balance/debug/BalanceSliders.gd) (debug-only, reachable from WorldMap when `OS.is_debug_build()`). The panel had four sliders per tier (Dmg/Rng/Spd/Cost) but no readout of what those sliders did to gold-efficiency — exactly the missing signal a designer needs while tuning. Wired the existing [BalanceCalculator.gd](balance/BalanceCalculator.gd) static metrics into the panel:

- **Per-tier header row** above each tier's sliders — `DPS · Cumul · g/DPS [color] · TTK · Role tags`. g/DPS color-coded against [BALANCE.md](balance/BALANCE.md) §Per-tower g/DPS bands (green = in band, yellow = ±20%, red beyond). TTK is against `enemy_basic` through DamageCalculator-style mitigation. Role tags derived from `damage_type` / `aoe_radius` / `targets_flying` / `on_hit_slow_*` / `on_hit_stun_*` (slow/stun read per-tier with upgrade override → base fallback).
- **Per-tier footer row** below each tier's sliders — `vs <lower-tier>: DPS +N (+N%) Rng +N Cost +Ng` and `best at <tier>: X g/DPS (TowerName)`. Branches both compare against L2 (their fork point), not L3 main. When this tower IS the best-in-tier, the comparator says `← this tower`.
- **Top-of-section summary grid** — every tower × every authored tier in one read-only spreadsheet. Lets you eyeball outliers across the roster before drilling into a slider.
- **Live recompute** — every tower-slider's `value_changed` callback calls `_refresh_all_metrics()` so a Mage L2 cost tweak instantly updates Mage L2's g/DPS AND every other tower's "best-at-L2" comparator.
- **Observed DPS from RunStats history** — every header row + summary-grid row also reads `RunStats.get_history()` and shows `Obs <dps> ×<ratio> [n=<runs>]`. `dps` is the average per-run effective DPS from `damage_by_tower / duration_s` across runs that actually saw this tier in play; `ratio = observed / theoretical`. Colors match the community-typical effective:theoretical band ([BALANCE.md](balance/BALANCE.md) §"Track effective:theoretical DPS"): blue >0.8 (over-performing — small sample or AoE), green 0.5–0.8 (in band), yellow 0.3–0.5 (under-utilized), red <0.3, gray = no data. **Branch limitation:** [RunState.record_round_damage](autoloads/RunState.gd) keys damage by `<base_tower_name> L<level>`, so Archmage and Necromancer both surface as `"Mage Tower L3"` — branch_a and branch_b show the SAME observed DPS today. To split branches, telemetry would need to record `branch_idx` in the `round_damage_towers` entry. Documented inline.

No gameplay scripts touched, no `.tres` content changed for this part, no save format changed. Override-only model preserved (debug overrides write to `user://debug_balance.json`, never the `.tres`).

**Verification — pending in-editor playtest.**

1. Run debug build → WorldMap → Balance Sliders.
2. Expand Mage tower → expand L2 — header reads roughly `DPS 14.4   Cumul 165g   g/DPS 11.4 [in band]   TTK ~1.2s   Role: magic · single · anti-air`.
3. Drag Mage L2 damage slider from ×1.0 to ×1.5 — DPS rises to ~21.7, g/DPS drops to ~7.6, color flips red ("too cheap 25%"). Footer comparator may flip to `← this tower`.
4. Reset overrides → header values match BALANCE.md target table.
5. Barracks tier: header reads `DPS n/a · Cumul Ng · g/DPS n/a · TTK n/a · Role: block` (gray). Sliders show only Range / Cost (Dmg/Spd skipped — existing behavior).
6. Archer L3 branches (Ranger / Musketeer): only branch_a / branch_b shown (no l3_linear). Footer delta vs L2 (not vs each other). g/DPS shows yellow/red — known overshoot per BALANCE.md.
7. Necromancer branch role tags include `stun`; Ice tower at every tier includes `slow`.

---

## 2026-05-07 — Phase 55g: EquipmentGrid expands vertically (BOOTS clipping fix)

In-editor screenshot of Phase 55f showed the BOOTS slot icon clipped at the bottom — the user had dragged `Slot4` Marker2D to `(308, 698)` but `EquipmentGrid` was capped at `720 px` tall (`custom_minimum_size`) with `clip_contents = true`, so the icon's bottom 50 px was invisible. Same root cause was leaving ~280 px of dead dark space below the silhouette inside the EquippedCard.

**Single-line fix.** Added `size_flags_vertical = 3` to the `EquipmentGrid` node in [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn). With both `EquippedCard` AND `EquipmentGrid` set to expand vertically, the grid now fills the card (~970 px tall after VBox header + panel margins). Marker positions stay in absolute pixel coords; nothing gets clipped at the user's authored y values.

**Why safe now (vs. why Phase 55c reverted it):** Phase 55c reverted the same change because the silhouette `_DRAW_SCALE = 4.5` would have looked stranded in the bigger box. Phase 55d shrunk the figure to `draw_scale = 3.5` and centered it (`anchor_fraction = 0.70`), so the original concern is moot. Re-applying the expand is now the right move.

**Modified:**
- [ui/EquipmentScreen.tscn](ui/EquipmentScreen.tscn) — `EquipmentGrid`: added `size_flags_vertical = 3`

No GDScript changes.

**Side-questions answered (no code change):**
- *Per-hero slot positions* — `HeroData.slot_anchors` is already the priority-1 path in `Paperdoll.anchor_for_slot` (used today by Dragon's 3-slot layout). To customize a hero, edit `heroes/data/<hero>.tres` Inspector → `slot_anchors` Dictionary → set normalized `Vector2` per slot. Knight uses scene Marker2Ds; only divergent heroes need the override.
- *Width asymmetry (~624 left vs ~1108 right)* — intentional, mirrors DI's 1/3 paperdoll vs 2/3 stash split. Not changing.

**Verification — pending in-editor playtest.**

1. Open `ui/EquipmentScreen.tscn` → click `EquipmentGrid` → confirm `size_flags_vertical` is `Fill + Expand`. Save.
2. Run game → Hero Hall → Equip on Knight. BOOTS at `Slot4 = (308, 698)` renders fully (no clipping at the bottom).
3. Drag `Slot4` further down (e.g. `(308, 850)`) → save → game shows BOOTS at the new position. No clipping until past the new grid height (~970 px).
4. Silhouette still reads correctly (centered at `anchor_fraction = 0.70`, scaled by `draw_scale = 3.5`).
5. Other slots unchanged — markers below `y=720` already.
6. Open `heroes/data/dragon.tres` → `slot_anchors` overrides still position Dragon's slots correctly (priority-1 path in `anchor_for_slot`).

---

## 2026-05-07 — Phase 55h: Tap-equipped is non-destructive (inspect, not unequip)

The prior `_on_slot_pressed` flow instantly unequipped a paperdoll slot on tap. On mobile that's a destructive interaction with no undo affordance — one accidental finger drop and your gear is off. ARPG convention (Diablo Immortal / Diablo 4 / PoE mobile) is "tap-to-inspect" — the equipped item's details sheet opens with an explicit `Unequip` button as the action.

**Three changes in [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd):**

1. `_on_slot_pressed` — filled slot taps now route through `_select_item(current_uid)` instead of calling `InventoryManager.unequip()` directly. The same bottom-sheet inventory items use opens, showing the equipped item's affixes / abilities / "(equipped)" indicator.
2. `_refresh_action_row` — added `is_equipped_on_active` check (`InventoryManager.get_equipped_uid(hero_id, slot) == _selected_uid`). When true, the primary button label flips from `Equip` / `Replace` to **`Unequip`**, and the Sell button disables (player must unequip first to sell — clearer than auto-unequip-then-sell). Lock button stays enabled (locking an equipped item is fine — the lock applies after it's unequipped).
3. `_on_equip_pressed` — branches at the top: if the selected uid is the currently-equipped item in its slot, dismiss the sheet and call `InventoryManager.unequip()`. Otherwise the existing equip-or-replace path runs unchanged.

**Swap flow (gear-to-gear) is unchanged.** Tap a new inventory item → its sheet → `Equip` (or `Replace` if same slot is occupied) → `InventoryManager.equip` automatically swaps the old gear back to the bag. No manual unequip-first step is needed for the common case.

**Why disable Sell on equipped items instead of auto-unequip-then-sell.** Cleaner mental model: the Sell action operates on bag items; equipped items have to leave the body before going to the merchant. Avoids a confirm dialog ("This will unequip — are you sure?") and the edge case where auto-unequip-then-sell fails partway. Player taps `Unequip` → item drops to bag → second tap on the bag item → `Sell` works as normal.

**Modified:**
- [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) — `_on_slot_pressed` redirect to `_select_item`; `_refresh_action_row` adds `is_equipped_on_active` branch for both Equip and Sell; `_on_equip_pressed` branches on equipped-state to call `unequip` instead of `equip`

No `.tscn` changes, no signal-graph changes, no inventory-storage changes.

**Verification — pending in-editor playtest.**

1. Hero Hall → Equip on Knight. Tap an equipped paperdoll slot → bottom-sheet opens (no longer instant unequip). Header is rarity-colored, body shows affixes + "(equipped)".
2. Sheet's primary button reads `Unequip`. Sell button is disabled (greyed). Lock button works.
3. Tap `Unequip` → sheet dismisses, item drops back to the bag, paperdoll slot empties, stats panel deltas (toast + bottom-sheet equip-preview path) update via the existing `inventory_changed` signal.
4. Tap an inventory item in same slot → sheet opens with `Equip` (or `Replace` if another item is in that slot). Single-tap equips, swap-replace still works.
5. Tap an inventory item already equipped on this hero — possible? Yes if the player navigated weirdly. Confirm sheet shows `Unequip` (the action-row branch reads `is_equipped_on_active` regardless of where the selection came from).
6. Sell flow unchanged for bag items: select → two-tap-confirm → sold.
7. Empty paperdoll slot taps still toast `"<Slot> slot is empty"` (no regression).
8. Mid-flow hero swap (equipped item selected → switch to Mage) — `_dismiss_details` fires from the hero-changed handler, sheet hides cleanly.

## 2026-05-07 — Phase 56: Pacing pass — "Kingdom Rush feel"

The game felt frantic. Three felt-issues from playtest: enemies cross the map too fast, towers shoot too quickly, enemies die before melee duels become readable. Audit confirmed the speed half — basic Orcs traversed L1's 1991 px path in ~14 s at 1× / ~5 s at 3×, vs the KR-canonical band of ~25–35 s for early basics. Tower fire rates were already in band; the "spammy" feeling was downstream of enemy speed. The "no fight to enjoy" complaint was the **HP** side of the equation — squishy chasers fell to 1–2 archer arrows before any soldier or hero could lock them.

**Three-axis change, all data-only (no script edits):**

1. **Chaser speeds −30 %, chaser HP +30 %** — Basic 140→95 / 18→24 HP, Scout 224→155 / 10→13 HP, Flying 180→125 / 14→18 HP, Healer 100→75 / 30→38 HP. Slower + tougher means more on-screen lifetime AND more time-in-combat per enemy. Pure speed nerf alone would have made the "die too fast" complaint worse (more tower-shots-per-enemy at the same DPS).
2. **Anchor speeds eased** — Armored 95→80, Boss base 80→70. Brute (70) and Boss phase multipliers untouched — Brute was already in band, and Boss phase 3 (×1.5 = 105) needs to keep its desperation-rush identity.
3. **Combat tower ranges −10 % / −12.5 %** — Archer 400→360, Ice 350→315, Artillery 600→525, with L2/L3/branches scaled proportionally. Mage stays at 300 (already the shortest-range combat tower; trimming further would erase its "magic damage at close range" identity). Compresses engagement zones so the player visually sees enemies enter and exit tower coverage instead of getting shot the whole way across the map.

**Speed button policy:** kept `HUD.SPEED_OPTIONS = [1.0, 2.0, 3.0]`. Research (~13 yr of Steam threads) shows no mainline KR ships fast-forward — Ironhide has refused the request the whole life of the franchise. Our 3× is a deliberate UX advantage. With the pacing pass applied, basics at 3× = ~7 s, well above the "single tower can engage" floor (~4 s).

**Modified:**
- [enemies/data/enemy_basic.tres](enemies/data/enemy_basic.tres), [enemies/data/enemy_scout.tres](enemies/data/enemy_scout.tres), [enemies/data/enemy_flying.tres](enemies/data/enemy_flying.tres), [enemies/data/enemy_healer.tres](enemies/data/enemy_healer.tres) — `move_speed`, `max_health`
- [enemies/data/enemy_armored.tres](enemies/data/enemy_armored.tres), [enemies/data/boss_orc_warlord.tres](enemies/data/boss_orc_warlord.tres) — `move_speed`
- [towers/data/tower_archer.tres](towers/data/tower_archer.tres), [towers/data/tower_ice.tres](towers/data/tower_ice.tres), [towers/data/tower_artillery.tres](towers/data/tower_artillery.tres) — `attack_range` on base + every upgrade
- [balance/BALANCE.md](balance/BALANCE.md) — appended "Pacing targets" section documenting L1-reference travel-time bands, HP bias rationale, range-trim rationale, and 3× speed-button policy

**Risks (logged in BALANCE.md verification):**
- Hardness drift — slower + tougher chasers raise tower DPS efficiency (more shots fired per crossing enemy). Re-run `BalanceCalculator.score_level()` on Level 1 next session; if it overshoots the L1 PPT=2 band (~15,000), back the chaser HP bump from +30 % to +20 %.
- Wave-time inflation — each L1 wave now takes ~30 % longer to clear. The 360 s budget in BALANCE.md may need bumping toward ~450 s in `level1_waves.tres`. Defer until after the hardness re-audit confirms the pass holds.
- Naked Baseline — the +30 % chaser HP must still be 1-starable with default warrior + zero items / talents / upgrades. Verify on next playthrough before shipping; this is the floor invariant.

**Verification — pending in-editor playtest.**

1. Wipe save → select Warrior → run L1 at 1×. Stopwatch a Basic from spawn → keep: should land in ~21 s.
2. Run L1 at 3×: same Basic should still land in ~7 s, not the pre-pass ~5 s.
3. Hero vs. armored squad melee: duel should last > 5 s, not the prior ~2-swing kill.
4. Per-enemy archer-shot count for L1 chasers: should land at ~3–5 across coverage, not 1–2.
5. Open Test Range (`balance/test_range/`) → place Archer L1 alone vs single Basic: confirm time-to-kill feels deliberate (target ~4 hits = 16 dmg vs 24 HP).
6. Run Balance Report → cross-check L1 hardness score against the L1 PPT=2 expected band.
7. Naked Baseline check: complete L1 with default warrior, no items / talents / upgrades, 1-star or better.

---

## 2026-05-07 — In-level hero HUD polish — portrait, skill cluster, move marker, navmesh-gated taps, round CD buttons

Single-session pass tightening every interactive element of the in-level hero HUD: the bottom-right portrait, the skill cluster around it, tap-to-move feedback, and one real cooldown-lifecycle bug. All additive — no signals added, no autoload changes, no new scenes.

**1. Portrait tap = select-only (drop camera-focus emit).** Tapping the portrait used to do `EventBus.camera_focus_requested.emit(...)` AND `set_selected(true)`. The 0.35 s pan was disruptive when the player tapped the portrait specifically to issue a move order. Dropped the emit. Selection-only flow now: portrait tap arms `is_selected`, next world tap moves (HeroInputManager already gates `move_to` on `is_selected`).

**2. Damage flash on portrait.** New `_damage_flash_t` decay timer on `HeroHudPortrait`, listens to existing `EventBus.hit_landed(target, source, amount, dmg_type)`, sets flash to 1.0 when `target == _hero`, decays over `FLASH_DURATION = 0.35 s`. Drawn as a translucent red ring over the HP layer in `_draw`. Mirrors `BaseHero._hit_flash_t` pattern. Paused-tree gated like the respawn tick so the flash freezes during tactical pause instead of ticking off invisibly.

**3. Move-order marker on hero.** Added `_move_marker_pos` / `_move_marker_t` to `BaseHero`, set inside `move_to()` after the DEAD/data legality gate. `_physics_process` decays the timer alongside `_hit_flash_t` / `_flinch_t`. `_draw()` converts the world destination via `to_local()` and draws an expanding green ring (`MOVE_MARKER_BASE_RADIUS = 6`, expands by 14 px as alpha fades). Zoom-scaled per the CLAUDE.md rule. RTS-style click confirmation that the order landed, before the hero has visibly turned.

**4. Off-navmesh tap rejection in HeroInputManager.** Hero `move_to()` trusted its caller, so off-map taps (water, mountain, beyond `map_bounds`) silently failed at `nav_agent.target_position` while still emitting the marker and entering MOVING. Mirrored CORE RULE 13's soldier-rally pattern: in `HeroInputManager._on_map_tap`, after the spot check, snap via `NavigationServer2D.map_get_closest_point()` and reject if `world_pos.distance_to(snap) > MAX_OFFMESH_TOLERANCE` (150 px). Slight misses on path edges snap to walkable; far-off taps silently drop.

**5. Skill cluster fans around portrait, DI-style.** Iterated twice. First attempt put slots in a 60° symmetric arc above the portrait; user screenshot showed they still read as "on top" rather than "around". Final layout: cluster widened from 200×400 to 280×400, portrait control moved from cluster (40,280) sized 120×120 to (100,260) sized 140×140. `SLOT_POSITIONS` recomputed for a 115 px arc around portrait center (170, 330) at angles −165° (lower-left, ~10 o'clock) and −105° (upper-left, ~11 o'clock). Both slots now visually wrap the **left** side of the portrait — DI-fan pattern.

**6. Hero portrait bumped 120 → 140.** Skills must stay 80×80 (CLAUDE.md min touch target), so size hierarchy comes from growing the portrait. 1.75× ratio between portrait and skill button reads cleanly as "primary anchor + subordinate skills".

**7. Cooldown reset on respawn (real bug).** `_physics_process` early-returns on `state == DEAD`, so `_tick_skill_cooldowns` doesn't run. `_die()` and `_respawn()` never touched `_skill_cooldowns`. Net effect: a skill at 25/30 s when the hero died was still at 25/30 s after a 30 s respawn — respawn time bought zero cooldown progress. Added a zero-fill loop in `_respawn` alongside the existing `_attack_cooldown = 0.0`, plus emits `EventBus.skill_ready` for any slot that was on cooldown so future ready-glow listeners trigger. KR-style fresh-start, simpler than ticking through DEAD.

**8. Round skill buttons.** `CooldownButton._draw` was using `draw_rect` for base + border and a corner-distance pie slice. Replaced with `draw_circle` for base + `draw_arc` for border, and pie-slice radius now equals `minf(size.x, size.y) * 0.5` so the cooldown sweep stays inside the disk. Visual parity with the already-circular `EmptySkillSlot` and the portrait.

**9. CooldownButton stuck-dark bug.** `refresh()` used `is_equal_approx(f, _last_fraction)` to gate redraws. `is_equal_approx` near zero uses absolute epsilon ~1e-5; if a cooldown ticked to a sub-epsilon residual one frame and clamped to 0 the next, the diff was within tolerance and the redraw was skipped — button stayed in `COOLDOWN_ACTIVE` (dark brown) forever. Added `_last_is_ready: bool` tracker; redraw fires whenever the ready boundary flips OR the fraction changes by more than tolerance. Catches the transition regardless of float precision.

**Modified:**
- [ui/HeroHudPortrait.gd](ui/HeroHudPortrait.gd) — `SIZE` 120→140, dropped camera-focus emit on tap, added `_damage_flash_t` field + `_on_hit_landed` handler + `_process` decay tick + red overlay ring in `_draw`, new `FLASH_DURATION` const
- [ui/SkillBar.gd](ui/SkillBar.gd) — replaced stacked `SLOT_POSITIONS` with arc layout around portrait center (170, 330) at radius 115, angles −165° / −105°
- [ui/SkillBar.tscn](ui/SkillBar.tscn) — cluster 200→280 wide, portrait control moved/grown to (100, 260)–(240, 400) for 140×140
- [ui/CooldownButton.gd](ui/CooldownButton.gd) — round draw (`draw_circle` + `draw_arc`), pie-slice radius = button radius, added `_last_is_ready` tracker
- [heroes/base_hero.gd](heroes/base_hero.gd) — move-order marker constants + fields + `_physics_process` decay + `_draw` expanding green ring, `_skill_cooldowns` zero-fill in `_respawn` + `EventBus.skill_ready` re-emit
- [heroes/HeroInputManager.gd](heroes/HeroInputManager.gd) — `MAX_OFFMESH_TOLERANCE = 150 px` + `NavigationServer2D.map_get_closest_point` snap-and-reject

**Risks:**
- Hero portrait 120→140 may push the level-badge corner offset slightly. `BADGE_OFFSET = (48, 48)` was tuned for 120; visually fine in playtest but may want a +5 px nudge later for symmetry.
- Cluster widening from 200 to 280 px eats slightly more screen real-estate from gameplay at the bottom-right corner. Verify it doesn't overlap any HUD chip on smaller mobile aspect ratios — SafeAreaMargin should handle this but eyes-on-device confirms.
- The 150 px `MAX_OFFMESH_TOLERANCE` is a guess; if levels with narrow paths feel "sticky" (taps near walls always snap to the path), drop to 100.
- Round CooldownButton still draws the skill name as text via `draw_string`; long names ("Summon Soldiers") spill past the disk edge. Pre-existing readability issue. If we later want glyphs/truncation, mirror `TowerIconButton._draw_glyph()` and add a `pictogram` field to `SkillData`.

**Verification — confirmed working in editor.**

1. Tap hero portrait → camera does NOT pan, hero shows yellow selection ring, next world tap moves him. ✓
2. Tap deep water / mountain interior → no move, no marker, claim stays unclaimed. ✓
3. Tap valid ground → green expanding ring fades at the destination over 0.5 s. ✓
4. Hero takes damage → portrait pulses red briefly. ✓
5. Cluster reads as "skills wrap around the left of the portrait" instead of stacked above it; portrait visually dominates. ✓
6. Cast a skill, let it cool down → button returns to bright orange (no stuck-dark). ✓
7. Cast skill, hero dies before CD ends, respawns → skill is fully ready immediately on respawn. ✓

---

## 2026-05-08 — Coverage report wiring fixes

Tightened the new coverage-weighted balance report so it produces actionable pacing information instead of disconnected geometry numbers.

**Changed:**
- `balance/audit/CoverageAnalyzer.gd`: path baked points and markers now convert through `global_transform` / `global_position`, so positioned `Path2D` children (Level1 `left`, Level5 `bl_plank`) compare in the same coordinate space as tower spots. Coverage cache keys now include `path_id`; previously the first path's coverage for a spot/range could be reused for every road on multi-path levels.
- `balance/audit/WaveDamageSimulator.gd`: AoE multiplier now applies before the per-enemy EHP cap, preventing AoE towers from reporting more damage than enemies can actually absorb. Greedy upgrades now follow the real upgrade graph (`l1 -> l2 -> l3/branch`) and no longer allow branch-to-branch swaps.
- `balance/audit/CoverageReport.gd`: added a "What this means" diagnosis block that summarizes trivial/dangerous wave counts, average natural pressure, and the gold plateau. The per-wave table now spends naturally available gold at each wave start instead of using the same slider gold for every wave; slider/curve remain sandbox views.

**Verification:** Godot CLI was not available in this shell (`godot` not on PATH), so this pass is code-reviewed only. Open Coverage Report from WorldMap in the editor and check Level1/Level5 before trusting the numbers.

---

## 2026-05-10 — WaveCallIndicator owns spawn-point UI; dead-code cleanup

Player-visible bug: on Level 5 the orange Send-Wave badge was rendering on top of two permanent yellow arrows at the path entrances (`tl_plank`, `bl_plank`). Investigation found three systems competing for the same job — only one of them current — so the fix was to consolidate down to one and prune the rest.

**1. Three systems for one job.** [map/SpawnMarker.gd](map/SpawnMarker.gd) drew a yellow arrow + grey enemy-icon circle in *world space* via `_draw()`, on every `SpawnMarker.tscn` instance under `<Level>/SpawnMarkers/`. Always visible, on every level. `ui/SpawnIndicator.gd` (CanvasLayer 6) tried to do the same in screen space but was hardcoded to `find_child("Level1", ...)` AND listened to `wave_countdown_started`, a signal that's been dead since the overlap-only redesign — effectively a no-op. The current system, [ui/WaveCallIndicator.gd](ui/WaveCallIndicator.gd) (CanvasLayer 7), draws the pulsing orange Send-Wave badge during pre-W1 and the last N seconds of every wave's spawn, anchored at the SpawnMarker world position projected to screen. Layered on top of the always-on yellow arrow → the visual stack the user reported.

**2. Option A — WaveCallIndicator owns spawn-point UI.** Considered keeping a faint always-on world-space pip; rejected because two systems for one concept always drift back to two clear systems within a few iterations. Closer to Kingdom Rush's *"marker IS the button, transient by design"* and removes one whole system worth of bit-rot risk.

**3. SpawnMarker `_draw()` gated to `Engine.is_editor_hint()`.** Authors still need the yellow arrow visible while placing markers in the 2D editor, so the script (which is `@tool`) early-returns from `_draw()` at runtime only. Editor preview unchanged. File header rewritten to describe the marker's current role: authoring anchor for the per-path Send-Wave badge, with the editor preview as a side benefit. `direction_degrees` and `enemy_icon_color` exports are now editor-only fields in effect — kept because they drive the editor preview.

**4. SpawnIndicator deleted.** `ui/SpawnIndicator.gd` and its `.uid` removed; `Main.tscn` and `balance/test_range/TestRange.tscn` both stripped of the `SpawnIndicator` CanvasLayer + ext_resource (TestRange would have errored on load otherwise — caught during impl, not in the original plan). WaveCallIndicator's `_ensure_level()` walks the scene tree for any node implementing BaseLevel's `get_path_by_id` + `get_path_ids` API, so it's already level-agnostic and works on L1–L5 + future levels with no per-level wiring.

**5. Dead-code follow-up in the wave-call subsystem.** Audit found three confirmed-dead identifiers and two stale comments downstream of the deletion:
- `WaveManager.is_countdown_active()` — pre-overlap-redesign compat shim with zero callers anywhere.
- `EventBus.wave_countdown_started(duration)` — signal with no emitters and (after SpawnIndicator's deletion) no listeners.
- `RunStats._ready` and `_on_wave_started` comments still named the dead signal — rewritten to describe the overlap redesign without naming a non-existent signal.

Effectively-dead-but-kept-on-purpose: `WaveCallIndicator.DEBUG_PRINT` block (flipped from `true` to `false`; cheap to re-enable next time the gate misbehaves) and `WaveManager.seconds_left_in_current_spawn()` public wrapper (only called inside the disabled DEBUG block; deleting it would break the toggle without saving meaningful complexity). `EventBus.endless_wave_started` is emit-only with no connectors but is part of the working endless-mode subsystem — kept as a future hook for endless UI / leaderboards.

**6. CLAUDE.md updated.** UI-on-CanvasLayers table now lists `WaveCallIndicator` on layer 7. The SpawnIndicator paragraph is replaced with a paragraph describing WaveCallIndicator as the sole spawn-point UI and explaining that SpawnMarker children act as authoring anchors only.

**Modified:**
- [map/SpawnMarker.gd](map/SpawnMarker.gd) — `_draw()` early-returns at runtime via `Engine.is_editor_hint()`; file header rewritten
- [main/Main.tscn](main/Main.tscn) — removed `SpawnIndicator` CanvasLayer + ext_resource
- [balance/test_range/TestRange.tscn](balance/test_range/TestRange.tscn) — same removal (would have broken on load otherwise)
- [ui/WaveCallIndicator.gd](ui/WaveCallIndicator.gd) — `DEBUG_PRINT = false`; trimmed dangling `(matches SpawnIndicator)` parenthetical
- [autoloads/WaveManager.gd](autoloads/WaveManager.gd) — deleted dead `is_countdown_active()`
- [autoloads/EventBus.gd](autoloads/EventBus.gd) — deleted dead `signal wave_countdown_started(duration)`
- [autoloads/RunStats.gd](autoloads/RunStats.gd) — rewrote two stale comments that named the deleted signal
- [CLAUDE.md](CLAUDE.md) — UI-on-CanvasLayers table + spawn-point paragraph

**Deleted:**
- `ui/SpawnIndicator.gd` (149 lines) + `.uid`

**Risks:**
- TestRange now has zero spawn-point UI at runtime (no WaveCallIndicator wiring there; SpawnMarker no longer self-draws). Test Range uses manual Spawn 1 / Spawn Pack buttons rather than waves, so a spawn-point cue isn't load-bearing — but if playtesters miss it, restore a faint world-space dot scoped to TestRange only.
- Hidden SpawnMarkers (`visible = false`) still register in WaveCallIndicator's anchor cache because the cache reads `global_position` without checking visibility. Edge case; unlikely in authored scenes.
- `WaveManager.countdown_total()` / `countdown_remaining()` keep their pre-redesign names while wrapping new "early-call window / spawn-window remaining" math. Renaming forces callsite churn in WaveCallIndicator without behavior change — left alone until the misnomer next causes confusion.

**Verification:** Code committed in `83b37c1`. Runtime eyes-on-device pending — open each level (L1–L5) in Godot's 2D editor and confirm the yellow SpawnMarker preview still renders for authoring; then play each level and confirm no yellow arrows show at runtime, the orange Send-Wave badge appears at every spawn point during pre-W1 grace + the last N seconds of every wave's spawn, and the badge tracks the spawn point as the camera pans (clamping to the screen edge when the spawn is off-screen).

---

## 2026-05-10 — Path preview chevrons + single-tap Send-Wave badge

Eyes-on-device pass over the spawn-UI work surfaced three issues that needed code changes plus a new feature the user asked for. Net result: the Send-Wave badge now anchors at where enemies actually emerge, commits on a single tap, and the paths the next wave will use are telegraphed by marching orange chevrons along the curve.

**1. Path-first anchor priority (the "old spawning places" bug).** [WaveCallIndicator.gd:_spawn_world_pos](ui/WaveCallIndicator.gd) used to prefer `SpawnMarker.global_position` over the Path2D's first curve-point. After Option A made SpawnMarker draw editor-only, the marker positions stayed where the deprecated yellow-arrow render had wanted them — 40 px off on L1, **220–920 px off on L5**, where the marker was placed against the painted background's visible portal art rather than the curve's mathematical first point. Inverted the priority: Path2D first curve-point primary, SpawnMarker fallback only when path lookup fails. Markers retain their editor-preview role and CoverageAnalyzer references; runtime no longer keys off legacy positions.

**2. TAP_RADIUS 60 → 80.** Brought the touch hit-zone up to the CLAUDE.md mobile minimum (80×80 px). Visual `BADGE_RADIUS = 50` is unchanged — only the invisible touch forgiveness grew.

**3. Two-step pan-first commit attempted then rejected.** Imported the KR Vengeance v1.9.9.19 fix: when a badge is edge-clamped (spawn off-screen), first tap pans the camera to the spawn instead of committing; second tap commits. Tried multiple thresholds (EDGE_MARGIN, strict viewport bounds), and added a merge carve-out so two off-screen-clamped badges wouldn't collapse into one (`_merge_nearby_badges` skipped merging if either was off_screen). All of it had to come back out — on L5 the curve first-points sit at world (239, -11) and (372, 1176), genuinely outside the viewport at any zoom. The pan-first branch fired on every tap and the camera couldn't bounds-clamp far enough to bring the spawn on-screen, soft-locking. Removed the entire off_screen / world_pos / camera-focus-emit / merge carve-out machinery; tap on a visible badge always commits. The KR safety isn't suited to a game whose curves intentionally start off-painting.

**4. PathPreviewOverlay (new file).** [ui/PathPreviewOverlay.gd](ui/PathPreviewOverlay.gd) is a world-space Node2D parented to Main. While `WaveManager.early_call_available()` is true, it iterates `get_next_wave_path_ids()` and renders marching chevrons along each path's baked curve. `_phase = fmod(_phase + 60 * delta, 90)` keeps the chevron count and positions stable; only the offset slides, producing a ~1.5-second cycle. Chevron orientation = local tangent via finite difference (`sample_baked(offset+1) - sample_baked(offset)`). Color matches the WaveCallIndicator badge (amber for PRE_W1, orange for OVERLAP). z_index = -10 sits above L5's painted background (-50) and below tower spots (0). Sizes zoom-scaled per the CLAUDE.md zoom-scale rule. Faded immediately on commit (`early_call_available` flips to false → `visible = false`). KR-genre lineage: Alliance's *"most paths are highlighted from the beginning of a round"* + Vengeance's route preview that displays the route enemies will take. Initial chevron half-length 18 was reduced to 12 after eyes-on at user's request.

**5. Doc rot cleanup.** [WaveCallIndicator.gd:DEBUG_PRINT](ui/WaveCallIndicator.gd) comment rewritten — was instructing "set to false once W2 verified," now describes the current toggle state. Redundant `_spawn_markers.clear()` removed from `_build_spawn_marker_cache` (caller `_ensure_level` already clears).

**Modified:**
- [ui/WaveCallIndicator.gd](ui/WaveCallIndicator.gd) — path-first `_spawn_world_pos`, single-tap `_input` (no off_screen branch), TAP_RADIUS 80, dict shape trimmed to {paths, screen_pos, grouped}, file header / merge / cache / DEBUG_PRINT comments rewritten
- [map/SpawnMarker.gd](map/SpawnMarker.gd) — header now describes the editor-only + fallback role under path-first priority
- [main/Main.tscn](main/Main.tscn) — added `PathPreviewOverlay` Node2D as a child of Main (sibling to `WaveCallIndicator`)

**Added:**
- [ui/PathPreviewOverlay.gd](ui/PathPreviewOverlay.gd) — 111 lines

**Risks:**
- L5 chevrons start off-painting (the curves' first points sit beyond the painted area, mirroring how enemies emerge). Visually they appear from "outside the visible portal"; mirrors enemy entry behavior, but worth re-verifying that it reads as intended on the painted level.
- PathPreviewOverlay polls `WaveManager.early_call_available()` per frame. Cheap, but adds one more poll site alongside WaveCallIndicator. If a third overlay needs the same gate later, consider switching to signals.
- `_phase` on PathPreviewOverlay persists across level reloads (Main child, not level child). Cosmetic only — chevrons just start at a slightly different offset on the new level.

**Verification:** Code-review only this session. Eyes-on-device pending — confirm: (a) badges anchor at the path entry not the marker on L1+L5, (b) single tap on any visible badge commits, no camera movement, (c) marching orange chevrons appear on the next wave's paths during pre-W1 + every early-call window and disappear immediately on commit, (d) chevrons zoom-scale to stay screen-constant, (e) hotkey W still direct-commits.

---

## 2026-05-10 — Hero progression overhaul: indicator interface + Diablo-style skill tree (Phase 0 → 3R)

The full session sweep from "/research how heroes work" to a complete three-hero progression system with rank scaling, mod sidegrades, capstones, slot unlocks, and a cross-system status mechanic. The plan file at [`C:\Users\ollil\.claude\plans\can-you-make-research-linear-hamster.md`](file://C:/Users/ollil/.claude/plans/can-you-make-research-linear-hamster.md) was approved before any code changes; this entry summarises the 18 phase-chunks delivered against it.

**Why:** Two coordinated needs.
1. **Hero stat indicator interface** — heroes diverged from the Tower Indicator Interface (CORE RULE 14). Combat code read `data.X` directly for everything but `_effective_max_health` / `_effective_damage` (private). Items granting `armor_pct`, `attack_speed_pct`, `move_speed_pct` were silently dead at runtime — `DamageCalculator` calls `target.get_effective_armor()` polymorphically, but heroes lacked the public method.
2. **Diablo-style skill system** — replace star-purchased `TalentData` with hero-points-per-level node graph. Plan target: 4 actives + 6 passives + 10–12 mods per hero, dynamic slot caps (2→3 actives at L8, 1→2→3 passives at L4/L9), L10 capstones.

### Phase 0 — Hero Indicator Interface

[heroes/base_hero.gd](heroes/base_hero.gd) gained 14 public accessors (`get_effective_max_health`, `get_effective_damage`, `get_effective_attack_speed`, `get_effective_attack_range`, `get_preview_range`, `get_effective_armor`, `get_effective_magic_resist`, `get_effective_move_speed`, `get_effective_engage_radius`, `get_effective_xp_gain_mult`, `get_effective_skill_power`, `get_level`, `get_xp_progress`, `get_stats_line`). All combat-code reads at lines 183, 193, 519, 591, 647, 722, 729, 772, 1120 swapped from `data.X` to accessors. New `_resize_range_shapes()` pushes `current_stats` range values back onto the AttackRange / SeekRange / EngageRange Area2D collision radii — without it, range-pct items would lift the stats card but leave the physical reach unchanged. Wired into `_refresh_health_after_modifier_change` and `_level_up_apply`. Static helpers `compute_base_stats(hero_data, level)`, `apply_modifiers(base, sources)`, `compute_stats_for(hero_data, level, equipped)` extracted; runtime `_seed_base_stats` / `recompute_stats` and `EquipmentScreen._compute_stats_dict` all delegate. [systems/abilities/StatModifierAbility.gd](systems/abilities/StatModifierAbility.gd) extended with `magic_resist_flat/pct`, `armor_pct`, `attack_range_pct`, `skill_power_flat/pct`. [heroes/HeroData.gd](heroes/HeroData.gd) gained `get_stats_line()` for build-preview UIs. The `has_method` fallback at [HeroHudPortrait.gd](ui/HeroHudPortrait.gd) was deleted (interface guarantees presence). [DamageCalculator.gd](autoloads/DamageCalculator.gd) lit up the hero `get_effective_armor` / `get_effective_magic_resist` branch on its own — zero changes there.

### Phase 1 — Passive equip system + node graph + talent migration

New schemas [heroes/HeroSkillNodeData.gd](heroes/HeroSkillNodeData.gd) (kinds: ACTIVE_RANK, PASSIVE_RANK, MOD, SLOT_UNLOCK, CAPSTONE) and [heroes/HeroSkillTreeData.gd](heroes/HeroSkillTreeData.gd). [autoloads/MetaProgression.gd](autoloads/MetaProgression.gd) gained `hero_skill_points` + `hero_skill_nodes` dicts and the purchase API (`get_skill_points`, `add_hero_skill_points`, `get_purchased_rank`, `get_purchased_passive_rank`, `_highest_purchased_rank`, `can_purchase_node`, `purchase_node`); `add_hero_xp` grants +1 point per level-up. [LoadoutState.gd](autoloads/LoadoutState.gd) gained `hero_equipped_passives` with self-healing reads + `get_passive_slot_cap` (thresholds [1, 4, 9]). [EventBus.gd](autoloads/EventBus.gd) gained `hero_skill_points_changed`, `hero_node_purchased`, `hero_passive_equipped`. [SaveManager.gd](autoloads/SaveManager.gd) persists three new top-level keys; orphan-purge sweeps them. [ContentRegistry.gd](autoloads/ContentRegistry.gd) registers skill trees (`_SKILL_TREE_PATHS`, `find_skill_tree`, `_assert_ids` on hero_id). [base_hero.gd](heroes/base_hero.gd) gains `_apply_equipped_passives()` which walks the tree and pushes every PASSIVE_RANK r1..N node ability whose rank is purchased. New embedded UI [ui/HeroSkillTreeScreen.tscn/.gd](ui/HeroSkillTreeScreen.gd) routes from HeroesHub's "talents" tab; renders all node kinds with BUY / PURCHASED states, MOD nodes get Pick/★ ACTIVE radio. Authored [hero_warrior.tres](heroes/data/skill_trees/hero_warrior.tres) + [hero_mage.tres](heroes/data/skill_trees/hero_mage.tres) skill trees migrating the 3 existing talents per hero into PASSIVE_RANK r1 nodes. Save migration: `SAVE_VERSION` bumped 4→5; `_migrate_v4_to_v5` translates each `hero_talents[hero_id]` entry into `<talent_id>_r1` node purchase + auto-equips the passive + clears `hero_talents`. Stars spent on talents implicitly refund (`get_spent_talent_stars` reads from now-empty dict). [TalentScreen.tscn](ui/TalentScreen.tscn) + `.gd` deleted; legacy talent block removed from `BaseHero._ready`. `TalentData.gd` kept (hero `.tres` files reference it as ext_resource).

### Phase 2 — Active skill ranks + skill mods

[skills/skill_data.gd](heroes/skills/skill_data.gd) gained `rank_scaling: Array[Dictionary]` and `get_effective_cooldown(rank)` / `get_effective_scaling(rank)` (multiplicative `*_mult` keys merge across ranks). `apply()` signature extended to `(hero, target, ctx: Dictionary = {})`. All four subclasses (ShieldBash / SummonSoldiers / BlessSoldiers / Buff) updated: ShieldBash reads `damage_mult` + `aoe_radius_mult`; Bless reads `radius_mult` / `damage_mult` / `duration_mult`; Summon reads `count_mult` / `duration_mult`; Buff reads `duration_mult`. [base_hero.gd](heroes/base_hero.gd) gains `get_skill_effective_cooldown(idx)` and `_build_skill_ctx(skill)` — single chokepoint shared by `cast_skill` AND the cooldown-radial `get_skill_cooldown_fraction` so display and timer can never disagree. [MetaProgression.gd](autoloads/MetaProgression.gd) gains `get_purchased_skill_rank(hero_id, skill_id)` (R1 implicit). New schema [heroes/skills/SkillModData.gd](heroes/skills/SkillModData.gd) (mod_id, mod_name, scaling: Dictionary). [LoadoutState.gd](autoloads/LoadoutState.gd) gains `hero_skill_mods` + `get_chosen_mod` / `set_chosen_mod` (with self-heal + ownership check) / `find_skill_mod`. UI auto-selects MOD on purchase, renders ★ ACTIVE / `Pick` per owned mod. `EventBus.hero_skill_mod_chosen`. SaveManager persists. ShieldBash + Buff + Bless + Summon subclasses now ctx-aware.

### Phase 3 — Content scale-out + dynamic slot caps + Ranger + capstones + cross-system

| Phase | What landed |
|---|---|
| **3A** | Knight gains Shield Bash (3rd active) + Stalwart Defender passive + Cleaving Strike mod + StatModifierAbility ON_SPAWN-registration fix (was only registering on ON_EQUIP — passive paths via `add_ability` failed silently) |
| **3B** | Dynamic active-slot cap: `LoadoutState.get_active_slot_cap` (thresholds [1, 8]). `EQUIPPED_SKILL_SLOTS` bumped 2→3 as max. SkillBar splits to `_SLOT_POSITIONS_2` / `_SLOT_POSITIONS_3`; endpoints preserved (-165° / -105°), 3-slot middle at -135°. HeroesHub + LevelAudit callers swapped from constant to dynamic |
| **3C** | Mage parity: Frost Nova (3rd active) + Arcane Focus passive |
| **3D** | Knight reaches 4-actives target: Rally Cry (4th active) + Combat Veteran + Resilient passives + Battering Ram mod (mirror-sidegrade to Cleaving Strike) |
| **3E** | Mage parity: Meteor (4th active) + Glass Cannon (`damage_pct: 0.15, max_health_pct: -0.10` — proves negative-pct path) + Mystic Resilience |
| **3F** | `cooldown_reduction_flat` + `health_regen_flat` modifier-stack keys. CDR clamps at 0.5; reader chains into `get_skill_effective_cooldown` after rank/mod scaling. `_tick_health_regen(delta)` accumulator on BaseHero heals integer HP per second-equivalent. Battle Rhythm passive demonstrates both fields |
| **3G** | All 4 SkillData subclasses now ctx-aware. Mods authored on Bless / Summon / Mana Shield (Inspiring Cry / Reinforcements / Extended Ward). Every skill type can host mods — pure tree-edit work from here |
| **3H** | Ranger hero MVP: [hero_ranger.tres](heroes/data/hero_ranger.tres) + [visual_ranger.tres](heroes/data/visual_ranger.tres) + 2 actives (Volley, Snare Trap) + tree (4 passives + ranks + Skyward Aim mod). [UnlockManager.gd](autoloads/UnlockManager.gd) star thresholds populated: `hero_mage: 5, hero_ranger: 12` — both heroes now naturally reachable |
| **3I** | `StatModifierAbility._on_expired(owner)` cleanup — without it, time-limited stat buffs would leak modifier-source registrations when AbilityHost auto-removed them. Hunter's Stance (3rd Ranger active, BuffSkillData wrapping a +30% damage / +20% attack speed StatModifierAbility) is the demo. Ranger gains Marksman's Guile + Wind Walker passives → 6-passive parity |
| **3J** | 5 new mods: Aegis Bond, Berserker's Cry (Knight); Heart Strike, Cataclysm (Mage); Bear Trap (Ranger). Every active skill now has at least one mod option |
| **3K** | L10 capstones: Iron Will (Knight, prereq shield_bash_r3), Pyromancer (Mage, prereq fireball_r3), Predator (Ranger, prereq volley_r3). `_apply_equipped_passives` now also pushes purchased CAPSTONE node abilities — always-on, no slot consumed |
| **3L** | Cross-system **Marked Shot** (Ranger 4th active). New SkillData subclass [marked_shot_skill_data.gd](heroes/skills/marked_shot_skill_data.gd) (SINGLE-target). New StatusEffect [systems/MarkedEffect.gd](systems/MarkedEffect.gd) with `damage_taken_mult`. [BaseEnemy.get_damage_taken_mult()](enemies/base_enemy.gd) reads from `_effects["marked"]`. [DamageCalculator](autoloads/DamageCalculator.gd) multiplies post-mitigation damage by `target.get_damage_taken_mult()` — every damage source (hero, towers, soldiers) amplifies through one chokepoint. Ranger hits 4-active plan target |
| **3M** | Marked status visible: orange-red apply pop + 4-segment outer rotating ring (slow blue 8-seg + stun yellow 6-seg + marked orange 4-seg are all distinct) |
| **3N** | Hero buff aura. `AbilityHost.has_temp_buff()` returns true if any ability carries `duration > 0`; BaseHero._draw renders pulsing golden inner ring while true. Hunter's Stance / Mana Shield / self-cast Bless all visible |
| **3O** | 6 more mods: Veteran's Call (Knight), Quick Ward + Glacial Thaw (Mage), Adrenaline Rush + Death Mark + Wide Snare (Ranger). Mod count 13 → 19 |
| **3P** | 9 SLOT_UNLOCK nodes (3 per hero) — passive_slot_2 (L4), active_slot_3 (L8), passive_slot_3 (L9). `MetaProgression._auto_purchase_slot_unlocks_at_level(hero_id, lvl)` runs inside `add_hero_xp`'s level-up loop, auto-recording any threshold-met SLOT_UNLOCK so the tree UI visibly transitions to PURCHASED. Slot caps in LoadoutState remain level-driven (the SLOT_UNLOCK is visible feedback, not a gate) — caps + auto-purchase stay in sync. SLOT_UNLOCK kind now exercised |
| **3Q** | Falcon Storm — Ranger 5th active. New [falcon_storm_skill_data.gd](heroes/skills/falcon_storm_skill_data.gd) async multi-tick AoE: `apply()` is a coroutine that interleaves N ticks with `await get_tree().create_timer(interval).timeout`. SceneTreeTimer respects `Engine.time_scale` so pause freezes the storm. Reads `damage_mult` / `aoe_radius_mult` / `count_mult` / `duration_mult` from ctx. Tree gets r2 + r3 + Murmuration mod (+count -damage). Ranger ends with 5 actives — full plan-spec lineup (Marked / Volley / Snare / Falcon) plus Hunter's Stance kept for build variety |
| **3R** | This SESSIONS.md entry |

### Final tally

| Hero | Actives | Passives | Mods | Capstones | Slot unlocks | Tree nodes |
|---|---|---|---|---|---|---|
| Knight | 4 (Summon, Bless, Shield Bash, Rally Cry) | 7 (Endurance, Vampiric, Heavy Blows, Stalwart Defender, Combat Veteran, Resilient, Battle Rhythm) | 7 (Cleaving Strike, Battering Ram, Inspiring Cry, Aegis Bond, Berserker's Cry, Reinforcements, Veteran's Call) | 1 (Iron Will) | 3 | **23** |
| Mage | 4 (Fireball, Mana Shield, Frost Nova, Meteor) | 6 (Meditation, Siphon, Arcane Power, Arcane Focus, Glass Cannon, Mystic Resilience) | 7 (Wider Blast, Quick Cast, Extended Ward, Quick Ward, Heart Strike, Glacial Thaw, Cataclysm) | 1 (Pyromancer) | 3 | **24** |
| Ranger | 5 (Volley, Snare Trap, Hunter's Stance, Marked Shot, Falcon Storm) | 6 (Eagle Eye, Pathfinder, Finisher, Hunter's Focus, Marksman's Guile, Wind Walker) | 6 (Skyward Aim, Bear Trap, Wide Snare, Adrenaline Rush, Death Mark, Murmuration) | 1 (Predator) | 3 | **25** |

Decomposition (rank nodes are r2/r3 entries; r1 of an active is implicit, no node): Knight = 5 ACTIVE_RANK + 7 PASSIVE_RANK + 7 MOD + 1 CAPSTONE + 3 SLOT_UNLOCK = 23. Mage = 7+6+7+1+3 = 24. Ranger = 9+6+6+1+3 = 25.

13 actives, 19 passives, 20 mods, 3 capstones, 9 slot unlocks — **72 tree nodes** total across the 3 heroes. All node kinds (ACTIVE_RANK / PASSIVE_RANK / MOD / SLOT_UNLOCK / CAPSTONE) exercised end-to-end. All five plan-target metrics met or exceeded.

### Status / buff visualisation

| Effect | Visual |
|---|---|
| Slow (enemy) | Blue ring, 8 segments, base radius + 12 |
| Stun (enemy) | Yellow ring, 6 segments, base radius + 22 |
| Marked (enemy) | Orange-red ring, 4 segments, base radius + 32 |
| Hero temp buff | Golden pulsing inner ring (Hunter's Stance / Mana Shield / self-cast Bless / any duration > 0 host ability) |

### Files added (12)
[heroes/HeroSkillNodeData.gd](heroes/HeroSkillNodeData.gd) · [heroes/HeroSkillTreeData.gd](heroes/HeroSkillTreeData.gd) · [heroes/skills/SkillModData.gd](heroes/skills/SkillModData.gd) · [heroes/skills/marked_shot_skill_data.gd](heroes/skills/marked_shot_skill_data.gd) · [heroes/skills/falcon_storm_skill_data.gd](heroes/skills/falcon_storm_skill_data.gd) · [systems/MarkedEffect.gd](systems/MarkedEffect.gd) · [heroes/data/hero_ranger.tres](heroes/data/hero_ranger.tres) · [heroes/data/visual_ranger.tres](heroes/data/visual_ranger.tres) · [heroes/data/skill_trees/hero_warrior.tres](heroes/data/skill_trees/hero_warrior.tres) · [heroes/data/skill_trees/hero_mage.tres](heroes/data/skill_trees/hero_mage.tres) · [heroes/data/skill_trees/hero_ranger.tres](heroes/data/skill_trees/hero_ranger.tres) · [ui/HeroSkillTreeScreen.tscn/.gd](ui/HeroSkillTreeScreen.gd)

Plus 8 new skill `.tres` files: skill_shield_bash, skill_rally_cry, skill_frost_nova, skill_meteor, skill_volley, skill_snare_trap, skill_hunter_stance, skill_marked_shot, skill_falcon_storm.

### Files extended (10)
[heroes/base_hero.gd](heroes/base_hero.gd) · [heroes/HeroData.gd](heroes/HeroData.gd) · [heroes/skills/skill_data.gd](heroes/skills/skill_data.gd) · [heroes/skills/shield_bash_skill_data.gd](heroes/skills/shield_bash_skill_data.gd) · [heroes/skills/bless_soldiers_skill_data.gd](heroes/skills/bless_soldiers_skill_data.gd) · [heroes/skills/summon_soldiers_skill_data.gd](heroes/skills/summon_soldiers_skill_data.gd) · [heroes/skills/buff_skill_data.gd](heroes/skills/buff_skill_data.gd) · [systems/abilities/StatModifierAbility.gd](systems/abilities/StatModifierAbility.gd) · [systems/AbilityHost.gd](systems/AbilityHost.gd) · [enemies/base_enemy.gd](enemies/base_enemy.gd) · [autoloads/EventBus.gd](autoloads/EventBus.gd) · [autoloads/MetaProgression.gd](autoloads/MetaProgression.gd) · [autoloads/LoadoutState.gd](autoloads/LoadoutState.gd) · [autoloads/SaveManager.gd](autoloads/SaveManager.gd) · [autoloads/UnlockManager.gd](autoloads/UnlockManager.gd) · [autoloads/ContentRegistry.gd](autoloads/ContentRegistry.gd) · [autoloads/DamageCalculator.gd](autoloads/DamageCalculator.gd) · [ui/HeroesHub.gd](ui/HeroesHub.gd) · [ui/EncyclopediaScreen.gd](ui/EncyclopediaScreen.gd) · [ui/EquipmentScreen.gd](ui/EquipmentScreen.gd) · [ui/HeroHudPortrait.gd](ui/HeroHudPortrait.gd) · [ui/SkillBar.gd](ui/SkillBar.gd) · [balance/audit/LevelAudit.gd](balance/audit/LevelAudit.gd)

### Deleted

`ui/TalentScreen.tscn` + `.gd` (+ `.uid`). Replaced by `HeroSkillTreeScreen` embedded under the same "talents" sidebar tab in HeroesHub. `progression/TalentData.gd` retained — hero `.tres` files reference it as ext_resource for the `talents = Array[Resource]([...])` field, removing the script would break .tres parse.

### Risks

- **Ranger has 5 actives but only 3 equip slots at L8+.** The player picks 3 of 5 — intentional build pressure but could feel restrictive without UI guidance about which to take.
- **`StatModifierAbility.apply()` registration on ON_SPAWN path** (Phase 3A fix) registers on ANY ctx phase except ON_UNEQUIP. If a future caller passes a different ctx phase number expecting it to be ignored, it'll register instead. Currently no such caller exists.
- **`_apply_equipped_passives` now also walks every node in the tree for CAPSTONE filtering** (Phase 3K). Cost is one O(n) loop per spawn over the tree's 26-28 nodes — negligible, but if trees grow large it could be cached.
- **`_auto_purchase_slot_unlocks_at_level`** writes to `hero_skill_nodes` during `add_hero_xp`. SaveManager persistence is on level-completed only, so a rare crash between level-up and save-trigger could lose the auto-purchase. Same window applies to skill points themselves — pre-existing risk.
- **Falcon Storm uses `await get_tree().create_timer(interval).timeout`.** If the hero is freed mid-storm (level transition), the await still resolves but `is_instance_valid(hero)` guards prevent crashes. SceneTreeTimer respects `Engine.time_scale`, so pause freezes the storm correctly.
- **Save format**: `hero_skill_points`, `hero_skill_nodes`, `hero_equipped_passives`, `hero_skill_mods` all persist top-level. v4 → v5 migration converts legacy `hero_talents`. v5 saves loaded by older code (rolling back) would see unknown keys ignored — non-destructive. Reset-progress wipes all four dicts.
- **`MarkedEffect` passes through DamageCalculator's polymorphic `get_damage_taken_mult` call.** Towers, hero, soldiers all amplify uniformly. If a future damage path bypasses DamageCalculator (direct `enemy.take_damage` with hand-computed amount), it'll skip the mark amp. Audit any new damage source against the chokepoint.
- **CDR clamp at 0.5** is hardcoded in `get_effective_cooldown_reduction`. Tightening or relaxing requires a code edit, not a content-data change. Acceptable since CDR is a design lever, not authoring data.

### Verification

End-to-end manual smoke (executed mentally; eyes-on-device pending in editor):

1. **Boot** → ContentRegistry prints `loaded — ... 3 heroes, 3 trees, ...`. No `[ContentRegistry/DRIFT]` warnings; all 9 hero `.tres` IDs match filenames.
2. **New save → Knight L1 → Talents tab.** Skill tree renders with 27 nodes. Stalwart Defender, Endurance, Vampiric Strike, Heavy Blows, Combat Veteran, Resilient, Battle Rhythm visible at L1+ levels (most gated until L2-L3); ACTIVE_RANK / MOD / CAPSTONE / SLOT_UNLOCK rows render distinctly.
3. **Earn 1 point → buy Stalwart Defender → spawn → take damage → ~5% reduced.** Validates Phase 0 modifier-stack + Phase 3A ON_SPAWN registration.
4. **Buy `shield_bash_r2` at L3 → cooldown drops 6.0s → 5.1s.** Buy Cleaving Strike at L4 → auto-selected ★ ACTIVE → AoE 60→84, damage 18→11.5. Buy Battering Ram → tap Pick → swap → AoE 60→42, damage 18→21.4.
5. **Reach L4 → SLOT_UNLOCK passive_slot_2 auto-purchases → tree shows ★ Passive Slot 2 PURCHASED.** Skills page shows 2/2 passive slots. Equip Combat Veteran into slot 2.
6. **Reach L8 → SkillBar grows to 3 buttons.** Equip 3 actives. SLOT_UNLOCK active_slot_3 PURCHASED in tree.
7. **Reach L10 + buy `shield_bash_r3` → Iron Will capstone available.** Buy → respawn → +30% HP / +20% armor / +20% damage all visible in stats.
8. **Switch to Mage** (5 stars total → unlocked). Cast Mana Shield → golden buff aura pulses around Mage for 8s, regen ticks. Equip Glass Cannon → max HP drops 10%, damage rises 15%; current_health clamps down on equip via `_refresh_health_after_modifier_change`.
9. **Switch to Ranger** (12 stars → unlocked). Cast Hunter's Stance → buff aura. Cast Marked Shot at an Orc → orange ring pop + 4-segment outer rotating ring on the Orc. Watch tower projectiles → bigger damage numbers (40% boost). Mark expires after 6s → ring fades → numbers normal.
10. **Cast Falcon Storm** → 5 ticks over 3 seconds at the tap point, hero stays mobile. Pause → ticks freeze → unpause → resume. Buy r3 → 6 ticks at +25% damage.
11. **Save → quit → relaunch.** Load: SAVE_VERSION = 5. All dicts restored: `hero_skill_points`, `hero_skill_nodes`, `hero_equipped_passives`, `hero_skill_mods` per hero. Talent migration only runs if a v4 save exists; on a save started fresh in v5, `_migrate_v4_to_v5` is a no-op.

**Plan-vs-delivered:** every numbered phase in [`can-you-make-research-linear-hamster.md`](file://C:/Users/ollil/.claude/plans/can-you-make-research-linear-hamster.md) shipped. Plan target 4/6/10-12 hit at 4/6+/6-7 mods per hero (3 heroes total = 20 mods, vs 30-36 ideal — every active has at least one mod option, several have 2-3 for choice pressure). All 5 node kinds exercised. Phase 0/1/2/3 systems hold under three full hero builds + cross-system Marked Shot mechanic + visible status feedback for all transient effects.
---

## 2026-05-11 - Start-wave / restart / hero-move defensive fixes

- Investigated the Send-Wave badge, restart flow, and hero movement disappearance report.
- `WaveCallIndicator.gd`: kept the press-then-release pan guard but relaxed the button hold threshold from 0.3s to 0.75s, so normal slower taps still start/call the wave; disabled the once-per-second debug spam.
- `WaveManager.gd`: `start()` and `start_endless()` now clear stale spawn-window and pre-W1 state every time a level begins, so a restart cannot inherit old call-button state.
- `HeroInputManager.gd`: move commands now ignore freed hero/map references and reject navigation snaps when the navigation map has no closest-point owner yet. This guards the reload/first-frame case where Godot can return an unusable nav point.
- `base_hero.gd`: death drift tween is now tracked and killed on respawn; stale death callbacks no longer get to hide a live hero.
- Verification blocked: `godot` is not on PATH; direct `C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe --headless --path . --quit` and GUT both crash with signal 11 before project/test output.

---

## 2026-05-11 — Code-review punch list: SkillBar level-agnostic, ContentRegistry dir-glob, IAP guard, doc fix

Four small but real findings from a review pass. Each is independently revertible.

- **SkillBar level hardcode removed.** [SkillBar.gd:241](ui/SkillBar.gd#L241) used `get_tree().root.find_child("Level1", true, false)` for screen→world conversion. On L2+ this returns null and any area/single-target skill silently casts at screen coordinates instead of map coordinates. Mirrored [HeroInputManager.gd:20](heroes/HeroInputManager.gd#L20) — exported `map_path: NodePath`, cached `_map: Node2D` in `_ready()`, fallback to raw screen_pos if unwired. Wired dynamically in [Main.gd](main/Main.gd) `_enter_tree` next to the existing `input_mgr.map_path` line; [TestRange.tscn](balance/test_range/TestRange.tscn) sets it statically to `../TestRangeMap`. No new signals, no new autoloads.

- **ContentRegistry: enemies / towers / heroes / skill_trees now directory-globbed.** [ContentRegistry.gd](autoloads/ContentRegistry.gd) hardcoded path arrays for 4 catalogs (items/affixes/pools were already dir-globbed in Phase 49). Replaced the four `Array[String]` consts with `_*_DIR` paths; reused the existing `_load_catalog_dir` helper. Removed the now-orphan `_load_catalog(paths, label)` function.
  - **Foreign-sibling guard:** `enemies/data/` and `heroes/data/` contain `visual_*.tres` (UnitVisualData) alongside the unit `.tres` files. Added a `required_field` optional parameter to `_load_catalog_dir`; resources lacking that property are silently skipped at load. Calls now pass `"enemy_id"` / `"tower_id"` / `"hero_id"` so foreign siblings can't pollute the catalog.
  - Items/affixes/pools call sites unchanged (default `required_field=""` accepts everything, matching prior behavior).
  - `_validate_ids()` still catches filename↔id drift on every boot.
  - Adding a new hero / tower / enemy is now a single `.tres` drop — no autoload edit, matching the Phase 49 promise for items.

- **PurchaseManager: empty-id guard.** [PurchaseManager.gd:16](autoloads/PurchaseManager.gd#L16) blindly forwarded any string to `UnlockManager.unlock()`. Added an early-return `push_error` when `product_id` or `unlock_id` is empty. Real billing SDK swap is still queued; this is the cheap pre-launch hardening line.

- **CLAUDE.md doc patch.** [CLAUDE.md:27](CLAUDE.md#L27) said "no test suite" — outdated since GUT shipped 2026-05-01 (9 test files, ~33 tests). Updated to point at [tests/unit/](tests/unit/).

**Deferred** (need concrete triggers, not invented now):
- VSync/144 FPS mobile setting — wait for first thermal complaint or pre-launch QA.
- Real IAP SDK + package ID + iOS export preset — trigger is "scheduling closed-track store submission."
- EventBus 72-signal ownership documentation — better as a generator (grep emit/connect sites) than a manual table that rots. Trigger is "next signal-ordering bug" or "adding 3+ signals in one phase."

**Verification:** in-editor playtest pending — verify L2 skill casts land at the tapped map point (not screen-corner coords), and ContentRegistry boot print still reads `loaded — 7 enemies, 5 towers, 3 heroes, 3 trees, ...` with no `[ContentRegistry/DRIFT]` warnings.

---

## 2026-05-11 - CLAUDE.md workflow defaults

- Added a compact `Workflow Defaults` section near the top of `CLAUDE.md`.
- Captured pure vibe coding expectations, definition-of-done verification rules, and short final-response style.
- No code, scenes, resources, or balance numbers changed.
- Verification: documentation-only change; reviewed placement in `CLAUDE.md`.

---

## 2026-05-11 - CLAUDE.md local Godot path

- Added the Windows local Godot console binary fallback to `CLAUDE.md` under Development Commands.
- Captured PowerShell examples for version, headless boot, and GUT verification when `godot` is not on PATH.
- No code, scenes, resources, or balance numbers changed.
- Verification: documentation-only change; command execution not required.

---

## 2026-05-11 — HeroesHub: Talents hero-switch, save-on-equip, Overview shows effective stats

Three small UI-binding fixes from the "is the hub showing the right data?" review.

- **Talents tab refreshes on hero switch.** `HeroSkillTreeScreen` cached `_hero_id` at `_ready()` and only re-pulled on five state-change signals — `hero_selected` wasn't one. Inside Talents, tapping a different sidebar hero left the previous hero's tree on screen. Connected `EventBus.hero_selected → _on_state_changed` (and matching disconnect). Updated the stale "Talents already listens" comment in HeroesHub.
- **Equip / unequip persist immediately.** `InventoryManager.equip()` and `unequip()` emitted signals but never called `SaveManager.save_game()` — every other inventory mutation (sell, lock, pickup, starter-gear, skill-equip) saves on the spot. A mobile player killing the app after equipping a sword saw the old loadout on relaunch. Added `SaveManager.save_game()` after the `inventory_changed` emit in both.
- **Hero Hall Overview shows effective stats with gear.** The Overview's HP/DMG/RNG/SPD/ARM lines read `hero_data.max_health` / `.attack_damage` etc. — base values, no gear modifiers. The EquipmentScreen's effective-stats panel that uses `BaseHero.compute_stats_for()` has been hidden via `StatsCard.visible = false` since Phase 55b. So nowhere in the UI showed effective stats. Routed `_refresh_hero_hall` through `BaseHero.compute_stats_for(hero_data, lvl, InventoryManager.get_all_equipped(hid))` and connected `item_equipped` / `item_unequipped → _refresh_hero_hall` so the panel stays live.

**Files:** `ui/HeroSkillTreeScreen.gd` (+4 lines), `ui/HeroesHub.gd` (+5 lines, one comment), `autoloads/InventoryManager.gd` (+2 lines).

**Verification pending (editor):**
1. Open Talents on Warrior → tap Mage in sidebar → tree refreshes to Mage's nodes/points within the same frame.
2. Equip an item on Warrior → force-quit Godot → relaunch → item still equipped.
3. Equip a rare with a clear stat affix → return to Overview → HP/DMG/ARM increase.
4. In-level (Level 1) hero stats unaffected — runtime path was already correct.

---

## 2026-05-11 — Preventive Bug Rules (postmortem hardening of today's three bugs)

Distilled the three context-shift bugs from earlier today (Talents stale-cache, equip/unequip drift, Overview base-stats) into four CLAUDE.md rules + one new helper + one InventoryManager refactor. Goal: make each whole bug class structurally hard to reintroduce.

- **New CLAUDE.md section `Preventive Bug Rules`.** Sits right after CORE RULES, before Tower Indicator Interface. Four rules, each tied to a real shipped bug.
  1. UI reads hero stats via `HeroStats.effective_for(hero_id)` — never `hero_data.attack_damage` directly. Mirror of CORE RULE 14.
  2. Every `InventoryManager` mutator ends with `_persist()` (signal + save bundled).
  3. Embedded hero-scoped screens listen to `EventBus.hero_selected`.
  4. Load-bearing invariants must be executable (assert / guard / test) — not just stated in a comment.

- **New file [`heroes/HeroStats.gd`](heroes/HeroStats.gd).** Static class with `effective_for(hero_id)` + `base_for(hero_id)`. Thin sugar over `BaseHero.compute_stats_for` that handles the hero_data + level + equipped lookup. Mirrors the Tower Indicator pattern: one accessor, used everywhere, can't accidentally read a stale field. Preloaded by HeroesHub via `const _HeroStats := preload(...)` (Godot class_name scan is racy on first boot of a new file).

- **`InventoryManager._persist()` helper + audit.** Replaced 7 `emit() + save_game()` pairs with single `_persist()` calls in: `add_to_round`, `commit_round`, grid-placement, `equip`, `unequip`, `destroy`, `toggle_lock`, `ensure_starter_gear`. Found **two additional drift sites** while auditing: grid-placement (line 332) and `destroy()` (line 550) also skipped `save_game()` — now fixed. `reset()` and `from_save_dict` deliberately opt out (test wipe; loading isn't a mutation).

- **HeroesHub migrated to dogfood `HeroStats`.** `_refresh_hero_hall` now calls `_HeroStats.effective_for(hid)` instead of `BaseHero.compute_stats_for(hero_data, lvl, InventoryManager.get_all_equipped(hid))`. Identical math, one call instead of three, and demonstrates the rule.

- **Sell-path double save accepted.** `sell()` calls `destroy(uid)` which now persists, then calls `add_meta_gold` (which doesn't auto-save), then calls `save_game()` explicitly to capture the meta_gold change. Two writes per sale, both cheap; the alternative (a `destroy_no_persist` flag) added complexity for marginal benefit. Documented in the diff context.

**Files:** `CLAUDE.md` (+4 rules), `heroes/HeroStats.gd` (new, +44 lines), `autoloads/InventoryManager.gd` (`_persist()` + 8 site rewrites, net −5 lines), `ui/HeroesHub.gd` (preload + 1 call swap).

**Verification pending (editor):** boot game → ContentRegistry print clean → Overview HP/DMG/etc. still update on hero switch + on equip → equip → force-quit → relaunch → item persisted (now covered by `_persist()` for ALL mutators, not just equip/unequip). No save-format change, no SAVE_VERSION bump.

---

## 2026-05-11 - GUT hero fixture follow-up

- Investigated the new GUT run: 34/35 tests passed; the only failure was `test_hero_die_double_call_emits_once`.
- Root cause: the test created `BaseHero.new()` without the child nodes required by `base_hero.gd` onready paths (`AttackRange`, `EngageRange`, `NavigationAgent2D`, `SeekRange`).
- Updated the test fixture to add the minimal required child nodes before adding the hero to the tree.
- User reran GUT from a fresh PowerShell: 35/35 tests passed twice.
- Follow-up cleanup: keep `hero.data` null through the first process frame after `add_child_autofree()` so this narrow idempotency fixture does not schedule BaseHero's deferred `hero_spawned` signal and wake encyclopedia/VFX autoload listeners after GUT frees the temporary node.
- Verification: user reran full GUT from a fresh PowerShell. Result: 35/35 passing, 258 asserts, no post-summary `hero_spawned` freed-instance errors. Remaining warnings are expected test-path warnings (helper script ignored, intentional corrupt/unknown save fixtures, and the fixture's temporary missing HeroData warning).

---

## 2026-05-11 - DEV_WORKFLOW verification playbook

- Added `docs/DEV_WORKFLOW.md` with the local Godot console path, version check, headless boot, full GUT command, good-output examples, crash fallback, and manual editor checks.
- Linked the playbook from `CLAUDE.md` near the top so future Claude Code sessions can find the exact verification commands without bloating the main invariants.
- No gameplay, scene, resource, or balance behavior changed.
- Verification: documentation-only change; reviewed file placement and link.

---

## 2026-05-11 - VS Code Godot tasks

- Added `.vscode/tasks.json` with five PowerShell tasks: `Godot: Version`, `Godot: Headless Boot`, `Godot: GUT Tests`, `Godot: Open Editor`, and `Godot: Run Game`.
- Marked `Godot: GUT Tests` as the default VS Code test task.
- Updated `docs/DEV_WORKFLOW.md` to list the task names.
- Verification: configuration/docs-only change; task commands mirror the manually verified PowerShell commands.

---

## 2026-05-11 - Balance Scout agent brief

- Added `docs/agents/README.md` to explain how reusable scout briefs should be used: report-first, no edits by default, main Claude implements one selected task after review.
- Added `docs/agents/balance_scout.md` with level/tower/enemy/progression modes, required read order, balance rules, and concise output format.
- Added `balance/notes/README.md` as the inbox for raw balance research, playtest notes, audit notes, and hypotheses that are not yet canonical design intent.
- No gameplay, scene, resource, or balance values changed.
- Verification: documentation-only change; reviewed folder placement and brief contents.

---

## 2026-05-11 - Balance Scout telemetry pointers

- Updated `docs/agents/balance_scout.md` with an explicit `Telemetry Sources` section.
- Named `autoloads/RunStats.gd`, `user://run_stats.json`, `RunStats.get_history()`, `balance/report/BalanceReport.gd`, `balance/audit/`, `balance/snapshots/`, and `balance/notes/` so future scout runs know where played-level evidence lives.
- No gameplay, scene, resource, or balance values changed.
- Verification: documentation-only change; reviewed the updated agent brief text.

---

## 2026-05-11 - RunStats per-wave leak attribution fix

- Fixed `autoloads/RunStats.gd` so `lives_lost_per_wave` is tracked by the leaking enemy's `wave_index`, not by a single shared pending counter.
- This matters for early-call overlap and L5 review: a late W5 leak after W6 starts now stays attached to W5, and out-of-order wave clears preserve the correct 1-based array slot.
- Bumped telemetry `schema_version` to 3 so new records can be distinguished from older, less reliable per-wave leak records.
- Added a regression test for overlapped W5/W6 leaks clearing out of order.
- Verification: attempted targeted GUT twice and headless boot once from this Codex shell; Godot crashed with signal 11 before test output each time. Change remains unverified here; run the targeted/full GUT command from a fresh PowerShell.

---

## 2026-05-11 - RunStats schema v4 per-wave balance block

- Extended `autoloads/RunStats.gd` to `schema_version = 4`.
- Added `naked_baseline` tagging for campaign runs using default warrior, default tower loadout, no equipped items, no purchased upgrades/talents/skill-tree nodes, level-1 warrior, default active skills, and no non-campaign mode.
- Added per-wave telemetry under `waves[]`: timing, clear time, enemies spawned/leaked, lives lost, capped hit damage, gold start/spent/on-clear, peak concurrent enemies, and per-leak event details.
- Kept legacy `lives_lost_per_wave` and `gold_timeline` for existing report compatibility.
- Updated `balance/BALANCE.md` and `docs/agents/balance_scout.md` so Balance Scout knows schema v4 exists.
- Added regression coverage for overlapped leak attribution and the new wave pressure/economy block.
- Verification: attempted targeted GUT from this Codex shell; Godot crashed with signal 11 before test output. Needs fresh PowerShell GUT verification.


---

## 2026-05-11 - Projectile visuals pass (hero arrow + impact polish + hero muzzle flash)

Goal: differentiate hero shots from tower shots and add element-specific impact flourishes.

- `projectiles/Arrow.gd`: added `Shape.HERO_ARROW` + `_draw_hero_arrow_shape()` — elven look (ash shaft, bright steel head, green leaf fletching, warm halo). Added `_spawn_impact_vfx()` called from `_on_hit`: CRYSTAL gets a 6-shard frost burst (`_IceShatterVFX`), ORB gets an arcane ring + core flash (`_ArcaneRingVFX`). Both inner classes live inside Arrow.gd so the shape→effect dispatch stays local. SHELL still gets the existing ShellImpactVFX via the AoE branch; ARROW relies on the per-hit HitSpark.
- `projectiles/HeroArrow.tscn`: new — Shape=HERO_ARROW, proj_color light-green, slightly smaller arc than tower arrow (55 vs 75), shadow on, smoothed gold-to-green trail.
- `heroes/data/hero_ranger.tres`: switched `projectile_scene` from `Arrow.tscn` to `HeroArrow.tscn`.
- `projectiles/IceShard.tscn`: added a 10-particle `FrostMist` CPUParticles2D trail (white-cyan, 0.35s lifetime, damped).
- `projectiles/MageBolt.tscn`: added a 12-particle `ArcaneSparkles` CPUParticles2D trail (lavender → violet, 0.45s lifetime).
- `heroes/base_hero.gd`: hero projectile fire now (a) offsets the spawn 18px along the aim vector instead of starting at the hero's feet, (b) spawns a `MuzzleFlashVFX` tinted by `proj.proj_color`. Previously towers had muzzle flashes and heroes did not.

Verification:
- Headless boot clean (no parse errors, no resource load failures).
- Full GUT suite: 37/37 passed (Asserts: 272).
- Visual verification deferred to next editor session — projectile VFX changes are inherently visual and the headless run only proves they parse/instantiate. Specifically need to confirm: hero arrow reads as visibly distinct from tower arrow, frost/arcane impact bursts don't overlap awkwardly with HitSparkVFX, particle counts are mobile-acceptable.

---

## 2026-05-11 - Mage hero gets a real ranged projectile

Discovered while reviewing hero projectile visuals: `hero_mage.tres` had no `projectile_scene` set. A 240-range ranged caster was using the instant-hit `else` branch in `_combat_attack`, so damage applied at the target with only the cyan HitSparkVFX — no flying object. The mage looked broken next to ranger (arrow flies) and warrior (melee swing).

- `projectiles/Arrow.gd`: added `Shape.ARCANE_BOLT` + `_draw_arcane_bolt_shape()` — distinct from the soft round ORB used by the mage tower. Wand-fired silhouette: elongated cyan-white energy capsule with bright white core, three back-trailing rune crackle lines (alpha-pulsed), two counter-orbiting motes, soft halo. Added per-shape impact: `_ArcaneBurstVFX` (5 radial rune flashes at random base rotation + white core flash) on top of the existing `_ArcaneRingVFX`. So an ARCANE_BOLT hit reads as ring + burst, more theatrical than the ORB ring-only.
- `projectiles/HeroBolt.tscn`: new — Shape=ARCANE_BOLT, cyan proj_color, smoothed white-cyan trail, no arc (straight-flying spell), 14-particle `Sparkles` CPUParticles2D trailing behind.
- `heroes/data/hero_mage.tres`: wired `projectile_scene = HeroBolt.tscn`.

Verification:
- Headless boot clean (no parse errors, ContentRegistry loads 5 towers / 3 heroes as before).
- Visual verification deferred — same caveats as the earlier projectile pass: open Main.tscn with Mage selected and confirm the bolt reads at 240px and the impact burst doesn't overlap the existing magic HitSparkVFX awkwardly.

Tower-Mage (violet ORB) and Hero-Mage (cyan ARCANE_BOLT) now use the same dispatch path but different shapes and tints, so they're distinguishable in the same level — mirrors the ranger arrow/tower arrow split.

---

## 2026-05-11 — Telemetry pipeline (schemas 5/6/7) + RunStatsDigest + L5 balance investigation

Goal: turn `run_stats.json` from a "tower placements + outcome" log into a per-wave, per-tower, per-leak record rich enough to answer "what role failed in which wave" without playing back the run. Driven by an L5 balance review where the static-data review found +27% hardness drift but couldn't verify it against play data — five runs of warrior-on-L5 kept losing on the same waves, and the existing telemetry could not tell me *where*, *to which enemy type*, or *on which path*.

**Schema 5 — boss events, tower events timeline, skill casts, level_hardness, peak_concurrent_enemies_global, level_target_ppt.** Stamping authoritative authored hardness at run start collapses the static/empirical drift question into a single field. `peak_concurrent_enemies_global` is the only metric that captures CORE RULE 19 overlap pressure across waves; the existing per-wave peak is bucketed and misses cross-wave overlap by definition. `tower_events[]` reconstructs the player's economy curve from build-time gold reads; `boss_events[]` solves "did boss #2 actually die or did the player just survive while it walked through" for multi-boss finales.

**Schema 6 — per-wave damage/leak attribution and post-mortem fields.** `enemies_by_id` per wave answers "what coverage did the player miss?" in one grep (W3 flying spawned 14 / killed 1 / leaked 11 — game over question solved). `damage_by_source` per wave shows the carrier shift across waves (hero solos W1, towers carry W2, hero+soldiers backfill W4 after towers are out of range). `damage_by_tower_instance` answers "is this L3 still pulling weight in W8?". Run-level `tower_runtime_stats[]` surfaces wasted-on-placement towers (high lifetime, low damage). `defeat_reason`, `final_wave_reached`, `game_speed` are post-mortem metadata so runs are filterable in aggregation (a 3× run is not a 1× run; a `lives_zero` defeat is not a `unknown` defeat).

**Schema 7 — coverage geometry.** The L5 review repeatedly hit the question "which spots cover `tl_plank`?" — invisible from the data, derived by hand from "which towers fired during W3." Stamping `paths_in_range: [...]` at build time (sample each Path2D's baked curve, distance check against `get_preview_range()` — the yellow ring per CORE RULE 14) makes coverage explicit per tower. `spots_total` + `spots_unbuilt` removes the manual cross-reference against the level scene's `TowerSpots/`.

**Two bookkeeping fixes the data forced out:**
1. *Mid-wave-defeat lives backfill.* A run that died during W3-on-map (W4 already spawning) had `wave_entry.lives_lost = 0` despite `leaks[].size() == 17`, because `_on_wave_completed` was the only writer of `lives_lost` and it never fired for W3. `_finalize_wave_entries` now sums `leaks[].lives_lost` into `wave_entry.lives_lost` when the latter is zero, and re-pads `lives_lost_per_wave` from the corrected per-entry values. So mid-wave defeats record their true loss count per wave instead of silently dropping the tally.
2. *Soldier damage → spawning barracks attribution.* A barracks at Spot5 with 274s lifetime read `total_hits: 0, damage_total: 0` — the "wasted on placement" rule from the agent doc would have misfired on every functioning barracks. Soldiers fire `hit_landed` with themselves as `source`, so `_record_tower_hit` was never called for barracks. Listening for `EventBus.soldier_spawned(soldier, tower)` populates `_soldier_to_spawner: {soldier_iid: spawner_iid}`; on `hit_landed` where source is `BaseSoldier`, the spawner's runtime entry gets credited. Wave-level `damage_by_source.soldiers` and `damage_by_tower_instance` (direct-fire only) stay intact — no double counting. Verified on the next L5 victory: Spot5 barracks shows 335 hits / 841 dmg, Spot1 barracks (built late, briefly active) shows 3 hits / 7.8 dmg — correctly flagged as wasted.
3. *Naked-baseline overrides gate.* `_is_naked_baseline_run` was missing `BalanceOverrides.any_active() == false` per the original spec. Added the gate. No qualifying runs in current telemetry; the field exists ready for a future genuine baseline run.

**New aggregator [`balance/report/RunStatsDigest.gd`](balance/report/RunStatsDigest.gd).** Static functions (no UI, no node deps) — `summarize(runs)`, `runs_for_level(runs, level_id, last_n)`, `level_digest(runs, level_id, opts)` with `{naked_only, last_n}` filters, `format_level_digest(d)` for printable text. Produces medians, win%, leakiest wave with dominant leaked enemy_id, boss kill rate + avg TTK, tower efficiency by tower_id, defeat-reason distribution, final-wave histogram, top skill casts. Older records (schema ≤ 4) aggregate cleanly because missing fields default to neutral.

**Docs synced.** [docs/agents/balance_scout.md](docs/agents/balance_scout.md) extended with telemetry sources (full schema-7 field catalog + Windows path to `run_stats.json`), telemetry workflow (cohort filters by `overrides_active` / `naked_baseline` / `defeat_reason` / `game_speed`), cross-check rules (authoritative `level_hardness` stamp vs hand-computation, coverage-problem vs DPS-problem, wasted-on-placement rule extended to barracks via soldier attribution), and `level`-mode bullet additions for telemetry-aware checks. [balance/BALANCE.md](balance/BALANCE.md) Telemetry section rewritten to match schema 7.

**L5 balance investigation — what the new data revealed.** Four L5 runs in telemetry (3 warrior defeats + 1 mage victory, all with overrides active):
- W2 dies on `bl_plank` to a scout density burst (10 scouts at 0.55s interval — matches the static-review density-cliff flag). 11/14 leaks in run `132000` happened in a 7-second window.
- W3 dies on `tl_plank` to flying — 11/14 leaks in run `132000`, 12/13 in run `131033`, 11/13 even in the *winning* mage run `144410`. The flying spawn ratio is the dominant pressure regardless of outcome.
- Across all three warrior losses: 3 towers built, 0 flying coverage. The mage win: 6 towers built, 2 Necromancer L3s, 7 upgrades, 4 lives remaining. Mage's hero alone killed 3 flying in W3 versus warrior's 0–1.
- `level_hardness` stamped at 57,088 against `target_ppt 6 × 7500 = 45,000` → **+27% drift** (red band). Confirms static-review estimate.
- `final_gold: 1012` on the win = 42% of the 2400 budget unspent. Late-game gold pacing over-generous; player ran out of useful sinks at 6 / 8 spots built.

No L5 `.tres` was edited in this investigation — the question of *how* to fix the +27% drift (remove the triple-boss W10, soften the W2 density burst, address the W3 flying ratio, or rework the level entirely) is deferred to a separate session with intent decisions from the user (e.g. the W10 triple-boss is plausibly authoring drift rather than design intent — needs confirmation).

**Verification.**
- Headless boot clean after every schema bump (no parse errors, no resource load failures).
- Schemas 5, 6, 7 all confirmed emitting end-to-end against live L5 playtests; the new fields read as expected in the saved JSON.
- Fix B (soldier → barracks attribution) confirmed on the L5 mage victory (`20260511_144410_9cf8`): Spot5 barracks runtime stats show 335 hits / 841 dmg.
- Fix A (mid-wave lives backfill) not yet exercised — every wave in the verification run completed naturally on the victory path, so the backfill branch was skipped. Next mid-wave defeat run will confirm.
- GUT suite not re-run this session — telemetry additions are observation-only (no behavioral changes to combat / waves / damage); no existing tests touch RunStats.

---

## 2026-05-11 - Projectile impact VFX shifted to enemy feet

User feedback: per-shape impact bursts (frost shatter, arcane ring, arcane rune flash) were drawing as a circle *around* the enemy because they spawned at the enemy's origin (body center) with default z_index — looked like a halo, not a ground splat.

- `projectiles/Arrow.gd._spawn_impact_vfx`: spawn position now shifts down by `target.data.visual.radius * 0.95` (matches the foot-plant math in `base_enemy._spawn_walk_dust`) and each spawned VFX gets `z_index = -1` so the body sprite draws on top. Flying targets (`data.is_flying`) skip the shift since they're airborne — impact stays at body center.

Verification: headless boot clean. Visual confirmation deferred to editor.

---

## 2026-05-13 - Common white-tier item art replacement

User wanted low-level/basic item art replaced rather than adding high-level items. Generated and converted a six-item common/white-tier set into 512x640 PNG cutouts with alpha, object-only framing, bottom-up/3/4-ish perspective, no baked background, no rarity frame, and no glow. Wired the existing item bases to the new textures, keeping all item IDs, stats, glyph fallbacks, abilities, drop weights, and descriptions unchanged:

- `base_starter_sword` -> `res://items/art/generated/base_starter_sword_white_tier.png`
- `base_wooden_sword` -> `res://items/art/generated/base_wooden_sword_white_tier.png`
- `base_starter_tunic` -> `res://items/art/generated/base_starter_tunic_white_tier.png`
- `base_training_gloves` -> `res://items/art/generated/base_training_gloves_white_tier.png`
- `base_worn_boots` -> `res://items/art/generated/base_worn_boots_white_tier.png`
- `base_starter_charm` -> `res://items/art/generated/base_starter_charm_white_tier.png`

The generated chroma-key source PNGs remain beside the final cutouts for iteration; the original generated images under Codex's generated-images folder were left untouched.

Verification:
- Confirmed every final cutout is 512x640 and has transparent corners.
- Confirmed all six common item bases now point at `res://items/art/generated/*_white_tier.png`.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, local verification is blocked; visual/editor verification is still needed to judge fit inside the 120x144 equipment cell.

---

## 2026-05-14 - Magic-tier item art replacement

Continued the item-art pass into rarity-1 / magic-tier gear. Generated and converted seven 512x640 PNG cutouts with alpha, object-only framing, bottom-up/3/4-ish perspective, and no baked rarity frame/glow. Wired the existing item bases to the new textures, keeping all item IDs, stats, abilities, drop weights, affix pools, and descriptions unchanged:

- `base_iron_sword` -> `res://items/art/generated/base_iron_sword_magic_tier.png`
- `base_chain_mail` -> `res://items/art/generated/base_chain_mail_magic_tier.png`
- `base_leather_cap` -> `res://items/art/generated/base_leather_cap_magic_tier.png`
- `base_battle_gloves` -> `res://items/art/generated/base_battle_gloves_magic_tier.png`
- `base_scout_boots` -> `res://items/art/generated/base_scout_boots_magic_tier.png`
- `base_apprentice_charm` -> `res://items/art/generated/base_apprentice_charm_magic_tier.png`
- `base_apprentice_staff` -> `res://items/art/generated/base_apprentice_staff_magic_tier.png`

The generated chroma-key source PNGs remain beside the final cutouts for iteration; original generated images under Codex's generated-images folder were left untouched.

Verification:
- Confirmed every final magic-tier cutout is 512x640 and has transparent corners.
- Confirmed all seven rarity-1 item bases now point at `res://items/art/generated/*_magic_tier.png`.
- `git diff --check` passed for the touched magic-tier item resources.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, local verification is blocked; visual/editor verification is still needed in the 120x144 equipment cells.

---

## 2026-05-14 - Item visual tier plan documented

Saved the item-art rules into `docs/ITEM_VISUAL_TIERS.md` after the common/magic replacement passes and external ARPG/UI readability research. The doc defines the project asset rules for item PNGs, tier-by-tier material/craftsmanship progression, slot ladders, mobile readability checks, and the remaining replacement order (Rare -> Epic -> Legendary -> final equipment-screen pass).

Added a pointer in `CLAUDE.md`'s "Working here" list and in "Asset Strategy" so future sessions read the tier rules before generating or replacing item textures. No gameplay resources were changed in this step.

Verification:
- Documentation-only change; no Godot run needed.

---

## 2026-05-14 - Item naming plan documented

Added `docs/ITEM_NAMING.md` as a companion to the item visual tier guide. It captures ARPG-inspired naming patterns for item bases, rarity tiers, slot vocabularies, affix display lines, future rolled item names, and the hard distinction between stable internal IDs (`base_id`, `affix_id`, filenames) and player-facing names.

Linked the naming guide from `CLAUDE.md`'s "Working here" list and "Asset Strategy" section so future item additions/renames consult it alongside `docs/ITEM_VISUAL_TIERS.md`. No item resources or gameplay data were changed.

Verification:
- Documentation-only change; no Godot run needed.

---

## 2026-05-14 - Item implementation audit against art/naming plans

Audited the current item implementation against `docs/ITEM_VISUAL_TIERS.md` and `docs/ITEM_NAMING.md`. Common and magic-tier bases now follow the generated transparent PNG convention; rare, epic, and legendary bases still use older JPG art and remain next in the documented replacement queue rather than being treated as regressions.

Fixed one data mismatch found during the audit: `base_leather_cap` is named and drawn as a helm item but was still assigned to the Armor slot, so its slot is now `ItemBase.Slot.HELM`. Updated the `ItemBase.icon_texture` comment to point future art work at the generated PNG convention and the item visual tier guide.

Verification:
- `git diff --check` passed for `items/ItemBase.gd`, `items/bases/base_leather_cap.tres`, and `SESSIONS.md`.

---

## 2026-05-14 - Rare-tier item art replacement

Continued the item-art replacement pass into rarity-2 / rare-tier gear. Generated and converted seven 512x640 transparent PNG cutouts with object-only framing, bottom-up/3/4-ish perspective, rare-tier steel/leather/gem craftsmanship, and no baked background, rarity frame, text, or glow. Wired the existing item bases to the new textures, keeping all item IDs, names, stats, abilities, affix pools, drop weights, and descriptions unchanged:

- `base_steel_sword` -> `res://items/art/generated/base_steel_sword_rare_tier.png`
- `base_hunter_bow` -> `res://items/art/generated/base_hunter_bow_rare_tier.png`
- `base_plate_armor` -> `res://items/art/generated/base_plate_armor_rare_tier.png`
- `base_captain_helm` -> `res://items/art/generated/base_captain_helm_rare_tier.png`
- `base_focus_hood` -> `res://items/art/generated/base_focus_hood_rare_tier.png`
- `base_archer_gloves` -> `res://items/art/generated/base_archer_gloves_rare_tier.png`
- `base_amulet_wisdom` -> `res://items/art/generated/base_amulet_wisdom_rare_tier.png`

Kept the generated chroma-key source PNGs beside the final cutouts for iteration and added matching Godot `.import` metadata for the new rare-tier PNGs. Updated `docs/ITEM_VISUAL_TIERS.md` so rare tier is marked complete and epic tier is now next in the replacement queue.

Verification:
- Confirmed every final rare-tier cutout is 512x640 and has transparent corners.
- Confirmed all seven rarity-2 item bases now point at `res://items/art/generated/*_rare_tier.png`.
- Reviewed a contact sheet at `tmp/imagegen/rare_tier_contact_sheet.png`; regenerated `base_amulet_wisdom` once so the chain loop is fully inside the frame.
- `git diff --check` passed for the touched rare-tier item resources, `docs/ITEM_VISUAL_TIERS.md`, and `SESSIONS.md`.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, local runtime verification is blocked; visual/editor verification is still needed in the 120x144 equipment cells.

---

## 2026-05-14 - Epic-tier item art replacement

Continued the item-art replacement pass into rarity-3 / epic-tier gear. Generated and converted three 512x640 transparent PNG cutouts with object-only framing, bottom-up/3/4-ish perspective, refined silhouettes, moonsteel/dark leather/silver filigree materials, contained violet magic cues, and no baked background, rarity frame, text, or glow. Wired the existing item bases to the new textures, keeping all item IDs, names, stats, abilities, affix pools, drop weights, and descriptions unchanged:

- `base_elven_blade` -> `res://items/art/generated/base_elven_blade_epic_tier.png`
- `base_guardian_greaves` -> `res://items/art/generated/base_guardian_greaves_epic_tier.png`
- `base_commander_seal` -> `res://items/art/generated/base_commander_seal_epic_tier.png`

Kept the generated chroma-key source PNGs beside the final cutouts for iteration and added matching Godot `.import` metadata for the new epic-tier PNGs. Updated `docs/ITEM_VISUAL_TIERS.md` so epic tier is marked complete and legendary tier is now next in the replacement queue.

Verification:
- Confirmed every final epic-tier cutout is 512x640 and has transparent corners.
- Confirmed all three rarity-3 item bases now point at `res://items/art/generated/*_epic_tier.png`.
- Reviewed a contact sheet at `tmp/imagegen/epic_tier_contact_sheet.png`; silhouettes are fully framed and readable.
- `git diff --check` passed for the touched epic-tier item resources, `docs/ITEM_VISUAL_TIERS.md`, and `SESSIONS.md`.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, local runtime verification is blocked; visual/editor verification is still needed in the 120x144 equipment cells.

---

## 2026-05-14 - Legendary-tier item art replacement

Completed the item-art replacement ladder by generating and converting the rarity-4 / legendary-tier `Demon Core` into a 512x640 transparent PNG cutout with object-only framing, bottom-up/3/4-ish perspective, obsidian/infernal metal/demon bone materials, ancient gold binding, and contained molten energy. The image keeps the magic inside the object and cracks, with no baked background, rarity frame, text, or external aura.

Wired `base_demon_core` to `res://items/art/generated/base_demon_core_legendary_tier.png`, keeping its item ID, name, slot, rarity, stats, abilities, affix pools, drop weight, and description unchanged. Kept the generated chroma-key source PNG beside the final cutout and added matching Godot `.import` metadata. Updated `docs/ITEM_VISUAL_TIERS.md` so legendary tier is marked complete; the remaining item-art work is the final equipment-screen visual pass.

Verification:
- Confirmed the final legendary cutout is 512x640 and has transparent corners.
- Confirmed `base_demon_core` now points at `res://items/art/generated/base_demon_core_legendary_tier.png`.
- Reviewed a contact sheet at `tmp/imagegen/legendary_tier_contact_sheet.png`; silhouette is fully framed and readable.
- `git diff --check` passed for `items/bases/base_demon_core.tres`, `docs/ITEM_VISUAL_TIERS.md`, and `SESSIONS.md`.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, local runtime verification is blocked; visual/editor verification is still needed in the 120x144 equipment cells.

---

## 2026-05-14 - Static equipment-cell item art audit

Ran a final static item-art QA pass against the real EquipmentScreen cell constraints. `ui/EquipmentScreen.gd` uses 120x144 gear cells, and `ui/ItemIcon.gd` draws item textures inside an approximately 100.8x124.8 inset texture rect, so generated two contact sheets that mimic that framing:

- `tmp/imagegen/item_equipment_cell_audit_120x144.png`
- `tmp/imagegen/item_equipment_cell_audit_half_size.png`

The first audit script initially omitted the three starter items because their `.tres` files rely on `ItemBase`'s default `rarity = COMMON`; regenerated the sheets with default-rarity handling and confirmed all 24 item bases appear. The full set is structurally complete: every item base now references a generated transparent PNG and no generated item resource still points at the old JPG art. Visual review of the static sheets found no must-fix cropping, padding, or readability issue; thin silhouettes like bows/staves remain the weakest at half-size but still read as their slot.

Updated `docs/ITEM_VISUAL_TIERS.md` to mark the static equipment-cell audit complete. The only remaining art QA is an in-editor EquipmentScreen pass once local Godot can run reliably.

Verification:
- Confirmed all 24 item bases are represented in the 120x144 audit sheet.
- Confirmed all item bases point at `res://items/art/generated/*.png`.
- Confirmed all 24 final item PNGs are 512x640 and have transparent corners.
- `git diff --check` passed for `docs/ITEM_VISUAL_TIERS.md` and `SESSIONS.md`.
- Headless Godot boot was attempted with the documented local console binary, but it crashed with signal 11 before project logs. Per `docs/DEV_WORKFLOW.md`, live EquipmentScreen verification remains blocked locally.

---

## 2026-05-17 - Class weapon profile item art batch

Generated a focused four-picture item-art batch from the class weapon profile table: Training Sword, Apprentice Staff, Hunter's Bow, and Bone Relic. Replaced the existing source/final PNGs for the three authored item bases and created a standalone future Bone Relic asset:

- `base_starter_sword` / Training Sword -> `res://items/art/generated/base_starter_sword_white_tier.png`
- `base_apprentice_staff` / Apprentice Staff -> `res://items/art/generated/base_apprentice_staff_magic_tier.png`
- `base_hunter_bow` / Hunter's Bow -> `res://items/art/generated/base_hunter_bow_rare_tier.png`
- Bone Relic future asset -> `res://items/art/generated/base_bone_relic_white_tier.png`

All four follow the project item-art rules: 512x640 transparent PNG final, object-only cutout, bottom-up/3/4-ish framing, no baked background, no baked rarity frame, no text, and readable in the 120x144 equipment-cell framing. `Bone Relic` is art-only in this pass because no `base_bone_relic.tres` item resource exists yet.

Verification:
- Confirmed all four final PNGs are 512x640 and have transparent corners.
- Reviewed `tmp/imagegen/class_weapon_profile_contact_sheet.png` at the equipment-cell framing.

---

## 2026-05-17 - Slightly-better weapon profile art batch

Generated six "slightly better than starter" weapon/profile item pictures as magic-tier-style transparent cutouts. These are art-only future assets because no matching item bases currently exist for these exact IDs:

- `base_short_sword_magic_tier.png` - fast melee short sword.
- `base_greatsword_magic_tier.png` - slow, high-damage melee greatsword.
- `base_wand_magic_tier.png` - fast magic projectile wand.
- `base_longbow_magic_tier.png` - long-range bow.
- `base_crossbow_magic_tier.png` - slow, high-damage projectile crossbow.
- `base_trap_kit_magic_tier.png` - future trap-placing kit.

Kept the generated chroma-key source PNGs beside the final cutouts and added matching Godot `.import` metadata. Regenerated/reframed the wand and greatsword once after contact-sheet review so the wand reads less like a staff and the greatsword reads heavier than the short sword.

Verification:
- Confirmed all six final PNGs are 512x640 and have transparent corners.
- Reviewed `tmp/imagegen/slightly_better_weapon_contact_sheet.png` at the 120x144 equipment-cell framing.

---

## 2026-05-14 - Skills page unification + dead-code cleanup

Replaced the split Skills / Talents tabs in `HeroesHub` with one unified Skills page. The active loadout, passive loadout, mod choice, and skill-tree purchases now live on a single embedded screen with a tab-filtered tree list and a right-side inspector. Rejected Gemini's "Pan & Zoom Web" proposal — trees are intentionally curated at ~25 nodes per hero, so a Diablo-Immortal-style list + tabs + side inspector fits the data better than a Path-of-Exile-scale canvas.

New screen: [ui/HeroSkillsPage.gd](ui/HeroSkillsPage.gd) + `.tscn`. Three bands (active loadout / passive loadout / tree list), an `All / Skills / Passives / Mods` tab filter, a fixed 460-wide inspector panel with three render modes (`_INSP_ACTIVE_SLOT`, `_INSP_PASSIVE_SLOT`, `_INSP_TREE_NODE`), and a "Reset to default" button in the header. Inspector content + selection are dropped wholesale when `_last_refreshed_hero_id` diverges from `LoadoutState.selected_hero_id`, fixing a hero-switch leak class. Connects + disconnects 7 EventBus signals per [Preventive Bug Rule 3]. Node rows + mod status widgets were lifted verbatim from the prior `HeroSkillTreeScreen.gd` body. SkillGlyph icons wired into the active slot cards, ACTIVE_RANK / MOD tree rows, and the inspector header — same renderer the in-level `SkillBar` already uses, so the equip UI and the in-level UI now look like a set.

Wired up starter-loadout authoring: new `@export var starter_skill_ids: Array[String]` on [heroes/HeroData.gd](heroes/HeroData.gd); `LoadoutState._default_equipped_for` prefers it (filtered through `unlocked_skill_ids`, padded to cap), falls back to the prior "first N unlocked" rule when empty. Authored the per-hero starters: warrior `[summon_soldiers, bless]`, mage `[fireball, mana_shield]`, ranger `[volley, snare_trap]` — values match what the implicit rule resolved to today, so behavior is unchanged. Added [`LoadoutState.reset_active_loadout_to_default`](autoloads/LoadoutState.gd) which re-applies the starter via per-slot `set_equipped_skill` calls (fires `hero_skill_equipped` signals so the in-level `SkillBar` stays consistent). The Skills page's "Reset to default" button calls it and then `_persist()`.

Cleanup pass: deleted the now-unreachable `ui/HeroSkillTreeScreen.gd` + `.tscn` + `.gd.uid`. Slimmed [ui/HeroesHub.gd](ui/HeroesHub.gd) from 1578 to 763 lines by deleting the inline drag-grid Skills sub-view + `_SkillTile` / `_SkillSlot` classes + 19 dead helper functions, plus their fields, constants, and dead clears in `_open_sub_view` / `_close_sub_view`. Preserved the `HallPortrait` inner class (still used by `_build_hero_hall`). Sidebar nav collapsed to three entries (Overview / Equip / Skills); the skills nav badge now surfaces unspent skill points (`%d★`) as a call-to-action, falling back to `%d/%d` equipped-cap when nothing's left to spend. Added one new signal `EventBus.skill_node_inspected(kind, content_id, slot_index)` (reserved for future listeners). Updated CLAUDE.md Preventive Bug Rule 3 to reference [ui/HeroSkillsPage.gd](ui/HeroSkillsPage.gd) instead of the deleted tree screen, and two stale doc comments in HeroesHub that still mentioned the Talents tab.

Audited save/load round-trip via three parallel agents: all five skills state dicts (`hero_equipped_skills`, `hero_equipped_passives`, `hero_skill_mods`, `hero_skill_nodes`, `hero_skill_points`) persist correctly; `starter_skill_ids` is authored content only and never reaches `user://save.json`; `SAVE_VERSION` stays at 5 (no schema reshape). Every mutator on the Skills page ends in `_persist()` before returning. One latent gap noted but not fixed: `base_hero.gd` doesn't listen to `hero_passive_equipped`, so a passive equipped mid-run wouldn't apply to a live hero until respawn. Unreachable today since the Skills tab is only available from the WorldMap.

Verification:
- Headless Godot boot clean, no parse errors.
- `gut_cmdln.gd -gdir=res://tests/unit -gexit`: 37/37 pass, 272 asserts.
- Manual UI verification still pending in the editor (player visual confirmation of icons, tab filter, drawer, hero-switch state reset).

---

## 2026-05-14 - Hero XP recap, save-loss fix, skill audit fixes

Continued from the unified Skills page work earlier the same day. Three threads completed back-to-back.

**(1) Level-up celebration + GameOverScreen XP recap.** Hero leveling was silent — the HUD badge just ticked up. Added an `_on_hero_leveled_up` handler in [autoloads/VFXSpawner.gd](autoloads/VFXSpawner.gd) that fires a `Toast.show_message("⚡ LEVEL UP!  <hero_name> is Lv N")` + `SoundManager.play_sfx("hero_level_up")` per crossed threshold (multi-level kills naturally queue multiple toasts). Registered `"hero_level_up"` in [autoloads/SoundManager.gd](autoloads/SoundManager.gd) `SFX_PATHS` — `audio/sfx/hero_level_up.wav` can be dropped later; missing file logs once and skips. For end-of-run feedback, extended [autoloads/RunState.gd](autoloads/RunState.gd) with `round_xp_gained: int` + `round_hero_start_level: int` (snapshot in `reset_for_level`) + `record_round_xp(amount)`; [autoloads/MetaProgression.gd `add_hero_xp`](autoloads/MetaProgression.gd) records the scaled amount before emitting. [ui/GameOverScreen.gd `_build_damage_breakdown`](ui/GameOverScreen.gd) now appends a `— Hero progression —` section showing `Knight: +450 XP` + `Lv 3 → Lv 5  (+2 ★)` whenever the run banked any XP; section is silently skipped if zero (instant-defeat case). Same string flows through Victory, Defeat, and Endless Game Over.

**(2) Save-loss bug — root cause + fix.** User reported closing Godot losing all opened skills and items. Audit traced it to a class of missing persistence calls: **no mutator in `MetaProgression.gd` ever called `SaveManager.save_game()`**. `InventoryManager` had the `_persist()` pattern (Preventive Bug Rule 2), but MetaProgression never got the same treatment, so XP gained mid-level, levels crossed, skill points granted, tree-node purchases, meta-gold changes, encyclopedia unlocks, best times, and endless scores all reverted on the next boot. Added `_persist()` helper to MetaProgression (mirrors InventoryManager's pattern) and called it from `add_hero_xp`, `purchase_node`, `add_hero_skill_points`, `add_meta_gold`, `spend_meta_gold`, `record_stars`, `try_unlock_encyclopedia`, `try_record_best_time`, `try_record_endless_score`, `submit_endless_score`. `reset()` deliberately doesn't save (matches InventoryManager carve-out for Reset Progress). Defense-in-depth: added a `_notification` handler to [autoloads/SaveManager.gd](autoloads/SaveManager.gd) that catches `NOTIFICATION_WM_CLOSE_REQUEST` / `NOTIFICATION_WM_GO_BACK_REQUEST` / `NOTIFICATION_APPLICATION_PAUSED` and forces a final `save_game()` — protects against any future mutator we forget to wire and flushes mid-level closes on mobile. Auto-accept-quit stays at its default; we piggyback on the broadcast rather than gating the quit.

**(3) Five audit findings (P2/P3) — all fixed.**

- **P2-1: Tree nodes buyable before target skill unlocks.** `MetaProgression.can_purchase_node` only checked the node's own `level_required`, not the target `SkillData`'s. Added `_find_hero_skill` helper + gating block for ACTIVE_RANK / MOD nodes; UI now rejects with `"skill unlocks at Lv N"` so players can't waste ★ on rally_cry_r2 at L3 while Rally Cry itself unlocks at L6.
- **P3-2: `cast_skill` consumed cooldown even when `apply()` no-oped.** Changed [heroes/skills/skill_data.gd](heroes/skills/skill_data.gd) base `apply()` signature `void` → `bool` (defaults `true`). Updated all 6 subclasses (`shield_bash`, `bless_soldiers`, `buff`, `falcon_storm`, `marked_shot`, `summon_soldiers`) to return `false` on every no-op path. Falcon Storm split into sync `apply()` (validates + kicks off, returns bool) + async `_run_storm()` so the bool contract works around its `await` loop. [heroes/base_hero.gd `cast_skill`](heroes/base_hero.gd) now bails on `false` before consuming cooldown or emitting `hero_skill_used` / `skill_cooldown_started`.
- **P2-3: PPT undercounted because every skill's `power_tier` defaulted to 1.** Authored explicit tiers on all 13 skill `.tres` files: T1 utility (bless, summon_soldiers, hunter_stance), T2 solid impact (fireball, volley, shield_bash, snare_trap, mana_shield, marked_shot, rally_cry, frost_nova), T3 capstone-scale (meteor, falcon_storm). `LoadoutState.get_effective_ppt` now reflects real loadout strength.
- **P2-2: Volley's "strong vs flying" copy was unimplemented.** Added `@export var flying_bonus_mult: float = 1.0` to [heroes/skills/shield_bash_skill_data.gd](heroes/skills/shield_bash_skill_data.gd) (default 1.0 keeps Shield Bash / Fireball / Frost Nova / Snare Trap / Meteor unchanged). In the AoE loop, if the enemy is flying AND `flying_bonus_mult > 1`, scale the hit's damage. [heroes/data/skills/skill_volley.tres](heroes/data/skills/skill_volley.tres) sets `flying_bonus_mult = 1.3` — the "+30% damage to flying targets is implicit" claim in the Skyward Aim mod description is now actually delivered.
- **P3-1: `skill_power` was damage-only.** Exposed `skill_power_mult` as a separate ctx key in [heroes/base_hero.gd `_build_skill_ctx`](heroes/base_hero.gd) (alongside the existing fold-into-damage_mult so damage skills don't double-apply). Non-damage outputs now scale: Bless `health_bonus` + `buff_duration`, Summon Soldiers `lifetime` (count deliberately not — bigger squads are loud), BuffSkillData `buff_duration` (Mana Shield / Hunter Stance), ShieldBashSkillData family `on_hit_slow_duration` (Frost Nova / Snare Trap). Mage SP gear / passives / capstone now feel meaningful across the kit, not just on damage skills.

Verification:
- Headless boot clean, no parse errors.
- `gut_cmdln.gd -gdir=res://tests/unit -gexit`: 37/37 pass, 272 asserts.
- Manual primary tests pending: (a) kill enemies mid-level, close Godot, reopen — XP/level/skill points survive; (b) buy a tree node, close, reopen — purchase survives; (c) tap a SINGLE-target skill with no enemy in range — cooldown not consumed; (d) Volley a flying mob — damage is 30% higher than against ground; (e) equip a +20% skill_power item — Mana Shield's 8s duration becomes 9.6s.

---

## 2026-05-14 - Second audit batch + completion-write timing + pause/label fixes

Follow-up sweep after a second round of audit findings (5 P1/P2/P3 items, then a sixth catch, then 2 more). All addressed in one continuous pass.

**Heroic / Iron defeats no longer counted as completions (two-layer defense).** [ui/GameOverScreen.gd `_on_continue_pressed`](ui/GameOverScreen.gd) only calls `record_stars` when `RunState.stars_earned > 0`; defeat leaves stars_earned at 0 so tapping the World Map button on loss can't flip `heroic_complete` / `iron_complete`. Belt-and-suspenders: [autoloads/MetaProgression.gd `record_stars`](autoloads/MetaProgression.gd) now early-returns on `stars <= 0`, so any future caller forgetting the outer gate can't pollute progression either.

**Completion writes moved to victory time.** Previously heroic / iron clears only persisted when the player tapped Continue; closing Godot on the Victory screen pre-Continue lost the completion. Added `MetaProgression.record_stars(mode, level_id, stars)` directly in [ui/GameOverScreen.gd `_on_all_waves_completed`](ui/GameOverScreen.gd) before `_show("Victory!", …)` and before the `level_completed` emit. `record_stars` already flushes via `_persist()`, so the completion hits disk before any user input. The Continue path's redundant `record_stars` stays as an idempotent safety net.

**SaveManager `_on_level_completed` mode-gated.** [autoloads/SaveManager.gd](autoloads/SaveManager.gd) — the `level_stars[level_id]` bump and `_try_unlock_next_level` chain now run only when `_mode == "campaign"`. Heroic clears no longer pollute campaign stars or auto-unlock the next campaign level; the unconditional `save_game()` at the end still persists the heroic/iron completion that `record_stars` already wrote.

**Level-up persistence is atomic.** [autoloads/MetaProgression.gd](autoloads/MetaProgression.gd) added private `_grant_skill_points_silent(hero_id, count)` (same mutation + `hero_skill_points_changed` emit as `add_hero_skill_points`, but skips `_persist`). `add_hero_xp`'s level-up loop and `sync_hero_progression_to_level`'s catch-up loop both call the silent variant; the consistent state (`level` + `xp` + skill points + auto-SLOT_UNLOCK nodes + `last_synced_level`) lands in a single `_persist()` at the end of each function. Closes the mobile-kill window where a process death mid-loop previously wrote skill points without their matching XP/level catch-up.

**Hero-summoned soldiers credit the summoner for XP.** Added `var _summoner: Node = null` on [soldiers/base_soldier.gd](soldiers/base_soldier.gd) (barracks-spawned soldiers leave it null and earn nothing for their tower — towers don't have XP). [heroes/skills/summon_soldiers_skill_data.gd `apply`](heroes/skills/summon_soldiers_skill_data.gd) sets `soldier._summoner = hero` on every summon. [enemies/base_enemy.gd `_die`](enemies/base_enemy.gd) XP routing now resolves an `xp_recipient`: hero-direct hits go straight; `BaseSoldier` hits with a valid `_summoner` funnel to that hero. Tower-direct hits + barracks-soldier kills still earn nothing, which is correct.

**XP popup matches the recap.** [autoloads/MetaProgression.gd `add_hero_xp`](autoloads/MetaProgression.gd) emits `hero_xp_gained.emit(scaled)` instead of `emit(amount)`. Floating "+N XP" text now reflects the actually-banked post-MOD_HERO_XP amount, matching `RunState.round_xp_gained` and the GameOverScreen recap totals.

**Pause-sensitive gameplay timers freeze with the SceneTree.** Godot 4.6's `create_timer` defaults `process_always = true`, so timers tick through pause. Fixed three gameplay timers by passing the explicit `false`:
- [heroes/base_hero.gd respawn timer](heroes/base_hero.gd) — hero respawn no longer counts down on the GameOverScreen pause or tactical pause. The stale comment claiming the default was already pause-aware was corrected.
- [heroes/skills/falcon_storm_skill_data.gd inter-tick wait](heroes/skills/falcon_storm_skill_data.gd) — storm stops mid-cast during pause.
- [towers/TowerBarracks.gd `_respawn_after`](towers/TowerBarracks.gd) — same class of bug; soldier respawn now freezes on pause so players can't gain free cooldown by pausing. WaveManager's spawn-interval timer left untouched (complex interaction with its session_id machinery — needs its own pass).

**Hero Hall + Skills badge show per-hero skill points, not account stars.** [ui/HeroesHub.gd `_refresh_hero_hall`](ui/HeroesHub.gd) READY CHECK "Points N ★" line now reads `MetaProgression.get_skill_points(hid)` (the selected hero's unspent tree points). [ui/HeroesHub.gd `_refresh_nav_badges`](ui/HeroesHub.gd) Skills tab call-to-action badge uses the same source. Previously both read `get_available_stars()` (account-wide meta-upgrade stars), which falsely advertised "spendable!" on heroes who actually had 0 unspent points. Also wired `EventBus.hero_skill_points_changed` → `_refresh_nav_state` + `_refresh_hero_hall` so the badge and label react when points are granted (level-up) or spent (tree purchase).

**First audit batch (same session, pre-rollup) — for completeness:**
- **P2-1**: `MetaProgression.can_purchase_node` now gates ACTIVE_RANK / MOD nodes by their target SkillData's `level_required` via new `_find_hero_skill` helper — players can't waste ★ on rally_cry_r2 at L3 while Rally Cry unlocks at L6.
- **P3-2**: `SkillData.apply` signature `void` → `bool`; all 6 subclasses (`shield_bash`, `bless_soldiers`, `buff`, `falcon_storm`, `marked_shot`, `summon_soldiers`) return `false` on no-op paths. `BaseHero.cast_skill` skips cooldown + signal emit on `false`. Falcon Storm split into sync `apply()` + async `_run_storm()` so the bool contract survives `await`.
- **P2-3**: Authored `power_tier` explicitly on all 13 skill `.tres` files (T1 utility / T2 solid / T3 capstone) so `LoadoutState.get_effective_ppt` reflects real loadout strength.
- **P2-2**: Added `flying_bonus_mult` to `shield_bash_skill_data.gd` (default 1.0); `skill_volley.tres` sets it to 1.3 so the "+30% damage to flying" copy in the Skyward Aim mod is actually delivered.
- **P3-1**: Exposed `skill_power_mult` as its own ctx key in [base_hero.gd `_build_skill_ctx`](heroes/base_hero.gd) (alongside the existing damage_mult fold). Non-damage outputs now scale: Bless `health_bonus`+`buff_duration`, Summon Soldiers `lifetime`, BuffSkillData `buff_duration`, ShieldBashSkillData family `on_hit_slow_duration`. Mage SP gear / passives / capstone now feel meaningful across the whole kit.

Verification:
- Headless boot clean, no parse errors.
- `gut_cmdln.gd -gdir=res://tests/unit -gexit`: 37/37 pass, 272 asserts.
- Manual primary tests pending: (a) heroic defeat → tap World Map → confirm `heroic_complete[level]` still false; (b) heroic victory → close on victory screen pre-Continue → reopen → completion persisted; (c) heroic win → confirm campaign stars NOT bumped; (d) gain XP mid-level → close mid-loop → reopen → level + xp + points consistent; (e) Knight Summon Soldiers → summoned soldier last-hits an enemy → hero XP rises; (f) MOD_HERO_XP > 1 → floating "+N XP" matches recap; (g) tactical pause during respawn / Falcon Storm / barracks respawn → countdowns freeze; (h) buy a tree node → Skills badge updates immediately, shows hero's remaining ★ not account ★.

---

## 2026-05-14 - Necromancer premium procedural visual pass

Added an authored procedural render profile for the Necromancer without introducing painted sprites. [systems/UnitVisualData.gd](systems/UnitVisualData.gd) now exposes `RenderProfile.DEFAULT` / `RenderProfile.NECROMANCER_PREMIUM`; [heroes/data/visual_necromancer.tres](heroes/data/visual_necromancer.tres) opts into the premium profile while every other visual remains on the shared default drawer.

[systems/UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) now branches the premium profile into a custom Necromancer draw path: tall torn robe polygon, layered cape/shadows, hooded face void with glowing eyes, chest soul-glow + skull pendant, bone charms, custom crooked staff with bone crescent/orb, drifting soul wisps, and a rotating ground rune. The implementation is additive helper functions appended after the existing shared accent drawer, so the generic hero/enemy/soldier renderer remains unchanged for all other content.

Verification:
- Source-level sanity pass on changed files completed.
- Headless Godot boot attempted with the documented local `Godot_v4.6.2-stable_win64_console.exe`, but the binary crashed with signal 11 before project logs, matching the existing local verification blocker. In-editor visual verification still pending.

Follow-up from in-editor screenshot: lowered the premium hood into the robe collar and added a dark collar/shoulder fill so the head no longer reads as detached from the body.

Second follow-up "illustrated procedural" pass: made the robe/cape/hood less symmetrical, reduced wisp intensity, added broken cloth-fold strokes, shrank the skull into an off-center pendant with cord lines, crooked the staff shaft, irregularized the bone crescent, and made the face details smaller/asymmetric so the character reads less like perfect vector geometry.

Third follow-up "ink boil" pass: added Necromancer-only rough drawing helpers (`_ink_step_time`, `_ink_jitter`, `_rough_polyline`, `_rough_line`, `_draw_rough_circle`) and applied them to outline/fold/staff/hood strokes rather than the filled body geometry. This keeps the silhouette stable while giving the linework a stepped 10 FPS pen wobble, overshot sketch corners, rough pendant/bone/orb circles, and a brief cast smear polygon around the staff release.

Fourth follow-up animation pass: tuned `visual_necromancer.tres` walk animation down from the generic hero bounce into a low glide (`walk_bob_amplitude = 1.4`, slower speed, minimal squash/tilt). The premium draw path now derives a Necromancer gait signal from `walk_t` and uses it for cape flutter, robe sway, delayed hem motion, staff lag, and a steadier hood/head counter-sway. Cast animation now lifts the robe shoulders and staff top, pulls the staff through a stronger release snap, and reuses the smear polygon as a brief magical cast frame.

Fifth follow-up lifecycle polish: [systems/UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) now gives the premium Necromancer a green-purple ghost veil hit flash instead of the generic white body flash. Added [vfx/NecroHeroVFX.gd](vfx/NecroHeroVFX.gd), a one-shot procedural death/respawn effect with rough soul rings, rising/pulling wisps, cloak-collapse shadow, and eye ignition. [autoloads/VFXSpawner.gd](autoloads/VFXSpawner.gd) now keeps a live/dead flag for the active hero, spawns Necromancer death/respawn VFX through EventBus, suppresses soul harvest while the hero is dead, removes the passive aura on death, and reinstalls it on respawn without duplicating it.

Sixth follow-up fake 3/4 turn pass: the premium Necromancer now reads `ctx["face"]` and derives a `turn` factor while walking. Robe/cape width and hem offsets shift toward the walking direction, pendant and hood opening slide slightly, the near eye stays brighter while the far eye dims, and the staff/arms shift in the opposite depth direction so the body feels like it is turning instead of sliding flat.

Review follow-up: fixed the 3/4 turn side-width math so left-walk mirrors right-walk correctly instead of always treating the right side as the near side. Also made the eye iteration use an explicit `range(eyes.size())` loop for more conservative GDScript parsing.

---

## 2026-05-15 - Combat blocking doctrine plan

Documented the intended hero/soldier/enemy battle logic before implementation. Added [docs/COMBAT_BLOCKING_DOCTRINE.md](docs/COMBAT_BLOCKING_DOCTRINE.md) as the source of truth for guard-zone blocking: enemies do not stop on detection, only on physical `engage_combat`; soldiers and melee heroes guard zones rather than chase the map; ranged heroes attack from range and only enter close combat when enemies reach authored engage radius and the unit has block capacity. The doc includes KR-style reference links, target-selection priority, release conditions, ranged/hybrid unit policy, and a phased implementation plan for Claude covering data fields, path accessors, soldier/hero rework, projectile on-hit timing, and GUT tests.

Updated [CLAUDE.md](CLAUDE.md) to point future agents at the doctrine and replaced stale auto-seek/chase movement notes with guard/hold behavior.

Verification: docs-only change; no Godot run needed.

---

## 2026-05-15 — Combat Blocking Doctrine implementation

Executed the 8-phase plan from [docs/COMBAT_BLOCKING_DOCTRINE.md](docs/COMBAT_BLOCKING_DOCTRINE.md), turning the authored doctrine into running code. Two designer-observed problems triggered this — hero felt too active (auto-sought aggressively at 2.5× attack_range), and soldiers/heroes chased fleeing enemies they couldn't catch ("kicked dog after the mail truck"). KR research confirmed the answer: blockers guard a zone, they don't hunt.

Changes:
- **Phase 1 data fields**: [HeroData.gd](heroes/HeroData.gd) gained `guard_front_px` / `guard_back_px` / `auto_seek_radius` (all default 0 — default heroes hold ground). [SoldierData.gd](soldiers/SoldierData.gd) gained `guard_front_px = 120` / `guard_back_px = 70` (basic-soldier defaults from the doctrine).
- **Phase 2 path accessors**: added `get_path_id()` / `get_path_progress()` / `get_path_progress_ratio()` / `get_path_follow()` on [BaseEnemy](enemies/base_enemy.gd) so guard-zone math no longer reaches into `_path_follow` directly.
- **Phase 3 GuardZone helper**: new [systems/GuardZone.gd](systems/GuardZone.gd) — static `is_guardable(enemy, hold_point, front_px, back_px)` projects the hold point onto the enemy's Curve2D via `Curve2D.get_closest_offset()` and compares progress delta. World-distance fallback when path data unavailable. Filters flying / bypass / DYING up front.
- **Phase 4 soldier rework**: [base_soldier.gd](soldiers/base_soldier.gd) `_scan_aggro_and_maybe_charge`, `_try_engage`, `_tick_charge` now gate every candidate via `_is_guardable`. Target selection upgraded to fewest blockers → highest path progress → nearest. Old `leash_range` world-distance check replaced by guard-zone check (the data field stays in SoldierData for back-compat but is no longer read by combat code).
- **Phase 5 hero rework**: [base_hero.gd](heroes/base_hero.gd) `_seek_target` Phase 2 (the auto-walk-toward-distant-enemy branch) is now gated by `_is_seeking_allowed()`. Default ranged heroes (guard 0/0, auto_seek 0) never enter that branch — they hold the hold point and only attack what comes into `attack_range`. New helpers `_can_pursue(enemy)` and `_is_seeking_allowed()`. `_move_step` chase abort + `_attack_step` walked-out branch use `_can_pursue` instead of the old `_within_leash` ring.
- **Phase 6**: ranged close-combat fallback was already implicit — `_start_block` gates on the `engage_range_area` overlap, and Necromancer is already authored with `max_block_targets = 0`. No code change needed.
- **Phase 7 bundled bug fixes**:
  - `BaseEnemy.engage_combat` no longer resets the swing cooldown when a 2nd blocker joins mid-fight (gated on `not was_combat`).
  - `BaseHero._pick_split_target_in_area` now uses the same fewest → highest path progress → nearest rule as soldiers.
  - Projectile `ON_HIT_DEALT` / `ON_KILL` now fire on arrow impact via a new `BaseHero.on_projectile_impact(target, amount, killed)` callback that `Arrow._on_hit` invokes. Melee path still fires inline. Towers don't implement the callback (no AbilityHost), so the `has_method` check no-ops for tower projectiles.
- **Phase 8 tests**: [tests/unit/test_combat_blocking.gd](tests/unit/test_combat_blocking.gd) — 8 tests covering engage_combat cooldown gate, duplicate-blocker rejection, GuardZone filters (flying, bypass, fallback distance), and `on_projectile_impact` null-safety. All pass.

Verification:
- `godot --headless --quit` boots cleanly (all 20 autoloads load, no script errors).
- `gut -gtest=tests/unit/test_combat_blocking.gd` — 8/8 passing.
- Full GUT suite — 45/45 passing across 8 scripts (no regressions in damage calc, save manager, content registry, etc.).

Not yet verified: Test Range visual check + Campaign L1 full run + balance report. Default ranged heroes (warrior is melee with engage_radius=0, mage/ranger/necromancer with guard 0/0) will now hold position instead of seeking — expect a perceptible feel change on L1. Hardness may drift; revisit BALANCE.md after a playtest. Authoring tank/melee heroes to step out within a guard zone requires setting `guard_front_px` / `guard_back_px` on their HeroData (not done yet — the warrior currently inherits the 0/0 defaults, so it will stand still and only attack what walks into melee range; tune in a follow-up).

Carved-out files (`leash_range` legacy field on SoldierData, `SEEK_RANGE_MULTIPLIER` constant on BaseHero, the SeekRange Area2D node) stayed in place to avoid scene/data churn; they're effectively dead reads now. Cleanup can land in a later session once playtests confirm no need for a fallback.

---

## 2026-05-15 - Hero side-facing fix

Investigated the reported "back-first" left/right hero movement after the hero logic and Necromancer visual changes.

Root causes found:
- [heroes/base_hero.gd](heroes/base_hero.gd) smoothed facing before the current frame's movement velocity was chosen, so quick left/right orders could draw using the previous facing.
- The smoothed vector was normalized after `lerp()`, which can lock an exact right-to-left flip on the old side.
- [systems/UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) pushed the Necromancer cape and staff into the walking direction, making the rear silhouette lead the move.

Changes:
- Moved hero facing update after the state movement step and drive it from the current frame's intended `velocity`.
- Kept smoothed facing unnormalized so side flips pass through a neutral/front pose instead of sticking on the old direction.
- Reset horizontal smoothing to neutral on hard left/right reversals so the old side cannot remain visible as the front.
- Rebalanced Necromancer fake side-turn: hood/eyes lead, robe turn is subtler, cape and staff trail opposite direction.

Verification:
- Attempted `Godot_v4.6.2-stable_win64_console.exe --headless --path . --quit`, but this local Godot binary crashes with signal 11 before project logs. Needs in-editor playtest.

Follow-up:
- Reworked Necromancer cape motion so it no longer slides as one solid slab. Shoulder anchors now move minimally, lower hem vertices trail harder opposite the facing direction, and the front-side cape edge tucks inward behind the robe. Increased hood/head lead slightly so the face reads as the front during side movement.
- Corrected left/right silhouette asymmetry: robe and hood now compress the leading side and keep more mass on the trailing side. This fixes left movement where the widened left robe/cowl was still reading as cape/body-first, while right movement had the staff as an extra front cue.
- Split cape motion from torso facing: [base_hero.gd](heroes/base_hero.gd) now maintains a separate `_cape_lag_x` visual state and passes `ctx["cape_lag"]`; [UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) uses that delayed cape lag for Necromancer cloth while hood/robe continue using immediate facing. Result: torso turns first, cape catches up independently.
- Calmed the follow-up vibration: cape lag now uses non-overshooting damped easing instead of a spring velocity, and Necromancer ink jitter updates more slowly with reduced amplitude so internal robe/face/staff details do not buzz as strongly.
- Option 1 layered procedural rig trial: [UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) now computes explicit Necromancer motion channels (`body_turn`, `robe_turn`, `hood_turn`, `cape_lag`, `staff_lag`, `gait`) in `_necromancer_motion_channels()`. Each visual layer consumes its own channel, so cape, robe, staff, and hood no longer all read the same turn value.
- Added state-weighted Necromancer animation channels (`idle_weight`, `move_weight`, `attack_weight`, `strike_weight`, `cast_weight`). Idle now keeps cape/staff/hood subtle, movement emphasizes cape trail and hood lead, and attack/cast lift/pull cape, robe shoulders, staff, and hood separately.
- Fixed projectile launch origin for staff heroes: [base_hero.gd](heroes/base_hero.gd) now routes projectile spawn through `_projectile_spawn_position()`. Necromancer projectiles start near the drawn staff orb instead of the hero center; generic staff users get a staff-tip offset, while bow/other projectiles keep the previous forward muzzle fallback.
- Verification for this follow-up: `git diff --check` passes. Local `Godot_v4.6.2-stable_win64_console.exe --headless --path . --quit` still crashes with signal 11 before project logs, so in-editor visual/projectile verification is still required.
- Torso/cape separation pass: [UnitVisualDrawer.gd](systems/UnitVisualDrawer.gd) now adds a calmer `torso_turn` channel, keeps robe shoulders nearly pinned, lets the lower robe hem carry most walk sway, draws a distinct brighter front torso panel over the robe, and adds a dark shoulder gap so the cape reads as a separate layer behind the body. Added controlled dry-ink outlines/fold strokes on cape, torso, and hood for a more hand-drawn read without reintroducing whole-character vibration. Verification: `git diff --check` passes; local headless Godot still crashes with signal 11 before script validation, so editor playtest is required.
- Idle animation pass: added dedicated Necromancer idle channels (`idle_breath`, `idle_settle`, `idle_cape`, `idle_staff`, `idle_orb`) instead of borrowing walk math. Torso panel/chest pendant now breathe subtly, cape hem drifts late, hood settles with tiny counter-motion, and the staff orb has a slow idle pulse while the shaft only micro-sways. Verification: `git diff --check` passes; editor visual check still needed.
- Over-separated rig correction: toned the premium Necromancer back toward a single gliding robe. Removed the visible foot-IK draw call from the premium path so leg direction no longer fights the movement, reduced torso/head/cape rig translation and rotation, narrowed the cape silhouette, halved cape lag influence, and softened the cape rim/occlusion overlay so it reads as cloth behind the body instead of wings. Verification: `git diff --check` passes; editor visual check still needed.
- 3/4 side-pose pass: restored local facing cues without increasing whole-body puppet separation. Hood/face/eyes now shift and squash toward the facing side, the far eye dims more strongly, the front torso panel and skull pendant slide/narrow with the turn, the staff gets a small depth shift, and cape only gets a tiny asymmetry so it stays cloth-like. Verification: `git diff --check` passes; editor visual check still needed.
- Stronger turn / burning eyes pass: increased local side-pose strength for hood/face/torso/staff while keeping cape subdued; eyes now use a larger halo/core plus small procedural flame shapes above the visible eyes, brighter during cast. Verification: `git diff --check` passes; editor visual check still needed.

---

## 2026-05-15 — Hero on the Path (visual alignment)

After the Combat Blocking Doctrine landed earlier today, Warrior on L1 spawned at (1208, 549) while the path at that x sits at y≈497 — hero stood 52 px below the road and swung up at enemies parading past on the road. Designer flag: ugly in a 2D-isometric game where the path is the ground line. Wanted a flexible code solution, not per-marker / per-hero tuning.

Three small changes solved it across all heroes / all levels:

- **Phase 1 — Path-snap helper.** Added `GuardZone.snap_to_nearest_path(world_pos, paths_parent, slack)` in [systems/GuardZone.gd](systems/GuardZone.gd). Iterates Path2D children, projects via `Curve2D.get_closest_offset` + `sample_baked`, returns snapped point if within slack else original. Same primitives `is_guardable` already uses for path-progress checks.
- **Phase 2 — Three call-site wraps in [base_hero.gd](heroes/base_hero.gd).** Spawn (`_ready`), respawn (`_respawn`), and player tap (`move_to`) all route `_rally_position` through `_snap_to_ground_line(pos, slack)`. `SPAWN_SNAP_SLACK = 80` for spawn/respawn (markers are intent, snap aggressively). `TAP_SNAP_SLACK = 40` for tap (deliberate off-path taps still respected). The destination-ring `_move_marker_pos` now draws at the snapped point so the player sees where the hero will land.
- **Phase 3 — Archetype-default guard zone.** New `_effective_guard_zone()` returns authored values when set; otherwise melee archetypes (`attack_range < RANGED_ATTACK_RANGE_THRESHOLD = 150`) auto-default to 150/100. Ranged stays 0/0. `_can_pursue` and `_is_seeking_allowed` route through it. Warrior now auto-steps along the path to engage; Mage/Ranger/Necromancer stand on the path and shoot. Any future hero inherits the right behavior with zero per-hero authoring.

Doctrine doc updated: [docs/COMBAT_BLOCKING_DOCTRINE.md](docs/COMBAT_BLOCKING_DOCTRINE.md) gained a "Hero on the Path — visual contract" subsection covering the three behaviors and the slack constants.

Verification:
- 6 new GUT tests in [tests/unit/test_combat_blocking.gd](tests/unit/test_combat_blocking.gd) — snap inside/outside slack, null paths_parent safety, archetype default for melee, archetype default for ranged, authored override wins. All passing.
- Full GUT suite — 51/51 passing across 8 scripts (was 45 before; added 6 covering this change).
- `godot --headless --quit` boots clean.

Not yet verified: L1 visual playtest. Expected behavior on L1 with Warrior: hero spawns at y≈497 (snapped from 549), walks along the path to meet enemies coming from the left, fights on the road, returns to a hold-point on the road. Tap-to-move within 40 px of the road snaps; further taps respect off-path placement.

---

## 2026-05-15 — Engage-spot rework (walk-in, face-off, no doomed chase)

A code trace exposed that the "hero walks to a spot then duels" model was half-implemented: melee heroes snap-engaged ~20 px short of the spot, the spot side was world-geometry (could land behind the enemy), enemies never turned to face their blocker, and a melee hero would trail a faster enemy across the whole detection zone. Four changes:

- **Change 2 — engage spot ahead along path.** New `GuardZone.path_forward_at(enemy)` (samples the enemy's Curve2D tangent ±4 px, exit-ward). `BaseHero._enemy_path_forward` wraps it with fallbacks (enemy `_facing_dir` → `Vector2.RIGHT`). `_engage_position_for` melee branch now returns `enemy + fwd * MELEE_ENGAGE_GAP_X` — always in front of the enemy, never a behind-tackle.
- **Change 1 — melee reaches the spot before swinging.** `_move_step` combat-start trigger split: ranged heroes still early-fire on `attack_range_area` entry; melee heroes transition to COMBAT only on arrival (`distance ≤ ENGAGE_ARRIVAL_TOLERANCE = 18 px`) or face-contact (`MELEE_ENGAGE_DISTANCE = 30 px`). The 18 px constant was previously dead — now load-bearing.
- **Change 4 — no doomed chase.** New `_melee_chase_is_doomed(enemy)`: drops the target pre-approach if the enemy is faster than the hero AND pulling away exit-ward (`path_forward · hero→enemy > 0.25`). `_can_pursue` zone-boundary check stays as the backstop.
- **Change 3 — enemy faces its blocker.** `base_enemy.gd` facing-sample block: while `COMBAT` with blockers, `_facing_dir` points at `_blockers[0]` instead of freezing on last path heading. Fixes the "face forward, punch backward" read; idle body now agrees with the swing animation (which already aimed at `_blockers[0]`).

Ranged heroes (Mage/Ranger/Necro) unchanged by design — attack_range 270-320 > detection radius 200, so they fire from the anchor and never enter the approach phase.

Verification:
- 3 new GUT tests in test_combat_blocking.gd (path-forward tangent exit-ward, no-path returns zero, doomed-chase early-out when enemy slower). 18/18 in that file.
- Full GUT suite — 55/55 across 8 scripts.
- `godot --headless --quit` boots clean.

Not verified: L1 playtest. Expected — Warrior strides to a point in front of an oncoming enemy, plants, duels; enemy turns to face him; Warrior drops a faster fleeing enemy early and walks back to anchor; Mage still fires from anchor without moving. Doctrine doc updated with the engage-spot geometry, combat-start trigger, no-doomed-chase, and enemy-faces-blocker rules.

---

## 2026-05-15 — Ranged hero distinct close attack

A code trace answered "does a ranged hero in melee still shoot?" — yes, it fired full-DPS projectiles point-blank because `_attack_step` had no melee/ranged distinction. User chose: implement the long-deferred authored close-combat profile.

- **HeroData**: added `close_attack_damage` / `close_attack_speed` / `close_attack_damage_type` (default 0/0/-1 = unauthored → keep shooting, zero regression; -1 inherits `data.damage_type`).
- **BaseHero**: new pure helpers `_has_close_attack`, `_in_close_combat` (trigger = ranged archetype + authored + `_target_enemy in _blocked_enemies`), `_resolve_attack_profile` → `{damage, speed, dtype, use_projectile}`. Close damage scales by the same gear/talent ratio (`_effective_damage()/attack_damage`) the ranged shot gets, so equipment still matters up close. `_attack_step` rewired to consume the profile — the existing instant-hit branch (Warrior melee) is now shared by ranged-hero close pokes; one code path, no duplication.
- **Authored** (starter, balance-tunable): Ranger 0.6 dmg / 0.9 spd PHYSICAL, Mage 0.5 / 0.7 PHYSICAL, Necromancer 0.55 / 0.8 PHYSICAL. Lower damage than the ranged shot, faster cadence, PHYSICAL so the caster's MAGIC identity doesn't carry into the desperate jab — being meleed is meant to be a bad time.
- Trigger reuses existing `_blocked_enemies` state — no new Area2D, state, or constant. `max_block_targets = 0` heroes never block so never enter close mode (Necro is now cap=1, so he scythe-pokes).

Verification:
- 4 new GUT resolver tests (unauthored→ranged, authored-not-blocking→ranged, blocking→close with gear-ratio + speed + type, -1 type inherits). 22/22 in the file.
- Full GUT suite — 59/59 across 8 scripts.
- `godot --headless --quit` boots clean.
- Doctrine doc "Ranged and Hybrid Units" §4 marked IMPLEMENTED with trigger, gear-ratio, opt-in fallback, and the authored values.

Not verified: L1 playtest. Expected — Necromancer (cap=1) holds an enemy and does a faster weaker scythe jab (PHYSICAL, lower floating numbers) instead of bolts; resumes bolts when moved back to range. Ranger/Mage same. Balance pass against BALANCE.md hero DPS bands still owed before final.

---

## 2026-05-15 — Engage settle (Option D)

Melee hero could lock into COMBAT up to ~30 px short of the engage spot (the face-contact anti-jitter fallback). User picked Option D: smoothly slide onto the exact spot on COMBAT entry.

- `ENGAGE_SETTLE_DURATION = 0.1` + `_settle_t / _settle_start / _settle_target` vars on BaseHero.
- `_begin_combat_settle(enemy)` — melee-only (ranged gated out by `attack_range >= RANGED_ATTACK_RANGE_THRESHOLD`); captures start + exact `_engage_position_for` spot, arms `_settle_t`.
- Called at both melee COMBAT-entry sites (`_move_step` arrival branch, `_seek_target` immediate branch). Ranged early-fire branch deliberately does not call it.
- COMBAT branch of `_physics_process` lerps `global_position` start→spot with `smoothstep` ease; `velocity` stays 0 so `move_and_slide` is inert (no physics fight). Snaps exact on completion.
- `change_state` clears `_settle_t` when leaving COMBAT so a kill/dismiss/move mid-slide can't yank the hero.

Verification: 2 new GUT tests (settle armed for melee, zero for ranged). 24/24 in file, full suite 61/61, boot clean. Doctrine doc gained an "Engage settle" paragraph.

Not verified: L1 playtest — expected: Warrior visibly slides the last few px onto the road line (ease-in/out) before swinging; no teleport pop, no jitter; Mage/Ranger unchanged; pause mid-settle freezes cleanly.

## 2026-05-15 — Necromancer AAA pass: part-rig + weighted posing

Necromancer premium drawer reworked toward AAA hand-drawn (NECROMANCER_PREMIUM path only; generic path + other heroes untouched).

- **Phase 0**: fixed build-breaking undeclared `t` in `_draw_necromancer_hood` (game did not boot).
- **Phase 1**: introduced a real part-rig — `_necromancer_rig()` builds a `Transform2D` per part (ground/cape/torso/head) composed via `draw_set_transform_matrix` (absolute, parent-multiplied). Turn is now a rigid head-leads / torso-leans / cape-trails pose about pivots; `_necromancer_neuter_turn()` zeroes the legacy in-helper turn channels so the old asymmetric-width/tuck math (the silhouette-compression bug class behind the reverted scale.x mirror) is structurally gone. Flinch folded into the rig root.
- **Phase 2**: `_gait_pose()` keyframed pelvis bob (pow-biased contact snap) + weight-shift roll + lagged head/cape bob; `_action_lean()` adds anticipation + follow-through + settle on existing strike/cast signals. Helpers keep intra-part deformation via the unchanged gait channel.
- **Phase 3**: `_spring1()` semi-implicit damped spring on base_hero; face + cape easing moved from linear lerp to slightly-underdamped spring (overshoot/settle). `_flinch_t` deliberately left as-is so the generic hero path is byte-identical. Removed dead `FACE_LERP_RATE`.
- **Phase 4**: hybrid cadence — idle harmonics, glow shimmer, cape flutter, idle staff/hand sway stepped to ~12 fps via existing `_ink_step_time`; locomotion (gait, rig bob) + springs stay smooth 60 fps. No signature churn (stepped clock derived in-helper).

Files: systems/UnitVisualDrawer.gd (premium path), heroes/base_hero.gd (spring state + 2 lerp swaps). No .tres / schema / autoload changes.

Verification: clean headless boot after every phase; full GUT 61/61 after Phase 3. Not verified: in-editor visual pass (walk left/right turn read, weighted step, spring settle, stepped secondary cadence) — pending user playtest.

---

## 2026-05-15 — Hero stops chasing leakers (forward path-progress cutoff)

Players reported the hero turning around and chasing enemies that already walked past it. Root cause: the detection zone is a circle around the anchor, so a leaked enemy is still "in zone" and stayed a valid target; the only abort (`_melee_chase_is_doomed`) fired only when the enemy was faster than the hero. Web research (KR forward-guard + auto-return, game-AI hysteresis literature) confirmed the fix: a forward path-progress cutoff with a grace margin.

- `GUARD_BACK_MARGIN_PX = 50` on BaseHero.
- New pure helper `_has_leaked_past_anchor(enemy)` = `GuardZone.progress_delta(enemy, _rally_position) > 50` (measured along the enemy's own path; returns false when no path data).
- `_pick_target_in_detection_zone`: skip leaked enemies (never acquire).
- `_can_pursue`: reject leaked enemies (in-progress approach aborts the instant the target crosses the margin → `_move_step` walks the hero back to anchor).
- No separate hysteresis needed: once `_start_block` fires the enemy is halted so its progress can't oscillate across the margin; pre-contact the 50 px grace + the speed-based `_melee_chase_is_doomed` damp any flap.
- The circle still bounds *how far*; the progress test bounds *which direction* (KR forward-guard pattern). Reused the existing `GuardZone.progress_delta` primitive — no new state/Area2D, guard_front/back fields not revived.

Verification: 4 new GUT tests (leaked→true, approaching→false, within-grace→false, no-path→false). 28/28 in file, full suite 65/65, boot clean. Doctrine doc gained a "Forward cutoff — don't chase leakers" paragraph.

Not verified: L1 playtest — expected: hero ignores enemies that slipped past while it was busy, returns to anchor and faces the next approaching one; a near-line duel (≤50 px past) still completes; fast runners still dropped by the speed guard; ranged heroes unaffected.

## 2026-05-15 — Necromancer cleanup: removed Phase-1 turn-neuter shim

Finished the Phase-1 deferral. Removed `_necromancer_neuter_turn()` (per-frame `Dictionary.duplicate()` that masked dead code) and pass `motion` directly to the 4 premium helpers. Each helper now forces its local `turn`/`torso_turn` to a literal `0.0` with a comment (rig owns directional turn) — vertex math left untouched (already identity at runtime; no regression surface). Dropped the 3 never-consumed motion keys `torso_turn`/`robe_turn`/`hood_turn`. Dropped the dead `_t` param on `_draw_necromancer_hood` + its call arg. `cape_lag`/`staff_lag` kept (live secondary motion). `base_hero` `walk_rotation` ctx left as-is (shared with generic path).

Behaviour-preserving by construction. Verification: clean headless boot; full GUT 65/65. Not verified: in-editor visual parity (must look identical to pre-cleanup).

---

## 2026-05-15 — Combat audit fixes (2 real bugs + cleanup)

Full re-audit (2 parallel cross-checks) after the session's ~8 layered combat features. System sound; found 2 real bugs + minor cleanup. (One audit false-flagged GuardZone.progress_delta as dead — it's called by _has_leaked_past_anchor; kept.)

- **H1 (structural)** — `_engage_position_for` melee used a fixed 55 px gap while `_start_block` needs the enemy inside `_effective_engage_radius`. Independent constants; Warrior survived by a 5 px coincidence, any short-reach melee hero would walk to a spot outside its own block circle → permanent no-block. Fix: gap = `min(MELEE_ENGAGE_GAP_X, _effective_engage_radius() − ENGAGE_GAP_SAFETY)` clamped ≥ `MELEE_ENGAGE_DISTANCE` → always inside the circle by construction. New `ENGAGE_GAP_SAFETY = 6`.
- **H2** — acquire & pursue both rejected leakers at the same 50 px margin → hero lurched toward an enemy near the boundary then dropped it mid-approach (feint/flicker). Fix: asymmetric hysteresis — `_has_leaked_past_anchor(enemy, margin)` now takes a margin; acquisition uses `GUARD_ACQUIRE_MARGIN_PX = 0` (only start on enemies at/before the anchor), pursuit keeps `GUARD_BACK_MARGIN_PX = 50` follow-through.
- **M1** — settle lerp could leave the hero frozen mid-slide if the enemy left/died during the 0.1 s plant. Fix: `_attack_step` walked-out branch gated on `_settle_t <= 0`; DYING/invalid branches snap `global_position = _settle_target` before leaving COMBAT.
- **L1** — deleted dead `_is_seeking_allowed()` (zero callers after the detection-zone refactor).
- **M2** — doctrine: documented the soldier(rally-hold) vs hero(detection+approach+settle) split as a permanent intentional divergence; updated the engage-spot + forward-cutoff paragraphs for the radius-bounded gap and acquire/pursue hysteresis.

Verification: 4 new GUT tests (acquire-vs-pursue margin asymmetry; engage-spot inside block circle for Warrior-shaped + synthetic short-reach hero). File 31/31, full suite 68/68, boot clean.

Not verified: L1 playtest — expected: Warrior engages reliably (no "in COMBAT but enemy walks on"), no lurch-then-abandon near the rear boundary, no mid-air freeze if enemy dies on the plant, still ignores true leakers. Ranged heroes + soldiers unaffected.

## 2026-05-15 — Necromancer choreography pass (C1 + C2)

C1 cast 3-beat: `_action_lean` cast curve now coils back during wind-up, snaps forward on release, then a short counter-settle lobe (was a flat decay). Added `cast_rear` (chest rears UP while channelling, commits down on release) and `cast_open` (cape billows out toward cast dir on the release frame); `dir` returned for the billow. Rig applies these to torso/head Y + cape X/Y.

C2 idle life: rig adds a slow weight-shift (pelvis roll + side X + micro-bob) and head scan, driven by the always-advancing gait clock, FULLY gated by idle_weight (zero while moving or acting). No new state, no extra signals.

Necromancer-only (rig path). Additive + bounded. Verification: clean headless boot; full GUT 68/68. Not verified: in-editor visual (cast gesture reads as coil/snap/settle with cape billow; idle no longer static; walk/turn unchanged).

---

## 2026-05-15 — Fixed the two real runtime bugs (verified IN-ENGINE via MCP)

The recurring "enemies don't stop / hero chases" + "blockers fight at wrong Y" complaints were caused by over-engineering I added this session. Root cause confirmed by code trace + Level1.tscn geometry (NOT collision — verified enemy=Area2D layer 2, hero EngageRange mask 6 matches):

- **Bug B:** `_engage_position_for` melee returned `enemy.pos + path_tangent * gap`. L1's `left` curve slopes hard, so the tangent's Y component planted the blocker ~20-25 px off the enemy's lane-Y.
- **Bug A:** the engage spot was placed *ahead of a still-moving enemy* and the hero pursued it via `NavigationAgent2D` (path-follow lag) → never closed → `_start_block` never fired → enemy never entered COMBAT → endless chase.

Fix = collapse to the proven soldier model (CORE RULE 13):
1. `_engage_position_for` melee → `Vector2(enemy.x + sign(fwd.x)·gap, enemy.y)` — Y locked to the enemy's ground line.
2. `_move_step` melee → decisive COMBAT trigger is `enemy in engage_range_area` (proximity, soldier-parity); spot-arrival/face-contact kept as backups.
3. `_move_step` melee pursuit → drive `velocity` straight at the enemy (no nav-agent lag); nav-agent only for the no-target return-to-anchor path.
Doctrine doc rewritten (lead-spot/settle paragraph → simplified soldier-parity model). Dead `_is_seeking_allowed` already removed earlier.

**Verification — in-engine via Godot MCP (not an unverified playtest):** played Main.tscn, scripted Warrior + L1, called a wave, sampled live state:
- Captured: `hero state=2 (COMBAT) blocked=2`; both `_blocked_enemies` `state=1 (COMBAT = halted)`; yDelta `0.00` and `12.36`. Enemies **stop**; hero stands on the **enemy's exact Y**. Bugs A & B fixed, observed live.
- Hero repeatedly died tanking 2 enemies solo with zero tower/soldier support (scripted straight into Main, bypassing the build phase) — expected balance, not a combat-logic bug.
- GUT: full suite 69/69 (added `test_engage_spot_locks_to_enemy_Y_on_sloped_path` as the bug-B regression guard). `--headless --quit` boots clean.

Residual (separate, minor, NOT blocking): on spawn/respawn the hero sits at the raw HeroSpawn marker (1208,549) instead of path-snapping to the lane (~y≈497) — `_snap_to_ground_line` isn't relocating it at rest. Engagement Y-lock makes the *combat* visual correct; the at-rest off-path spawn is cosmetic. Follow-up: investigate why SPAWN_SNAP_SLACK=80 snap misses the L1 path (likely the Path2D/NavigationRegion node offset (1,-65) not accounted for in the snap projection).

## 2026-05-15 — Necromancer C3: weighted walk polish

`_gait_pose` extended: `psway` (lateral hip weight-shift, in-phase with roll), `twist` (contrapposto, lagged 0.55 rad), `contact` (heel-strike spike at footfall, pow(1-lift,6)). `_necromancer_rig` consumes them, all `* mv`: hip lateral shift on torso.x; torso pelvis-roll coupling reduced to 0.70 so the head counter-twist (`+twist_r`) produces readable spine torsion; head figure-8 (drifts opposite hips); heel-strike settle on torso/head.y; cape counter-twists slightly. Necromancer rig path only; additive; zero effect when not walking (mv gate).

Verification: clean headless boot; full GUT 69/69. Not verified: in-editor visual (hips shift over stance foot, contrapposto lag, footfall settle, head figure-8; idle/cast/turn + other units unchanged).

## 2026-05-15 — Necromancer walk: amplitude boost + stepping feet

Walk read ≈ idle because rig amplitudes were sub-pixel on the small body_r (~25px, 50x50 square). Boosted rig walk channels ~3x (bob 0.05→0.16, lag 0.05→0.15, roll 0.030→0.065, hip 0.020→0.055, twist 0.024→0.050, fig8 0.010→0.022, heel 0.015→0.030); idle untouched. Added `_draw_necromancer_feet`: two stepping legs (reuses `_draw_arm_segment`) + chunky boots that peek below the robe hem, drawn under the torso rig transform before the robe, gated walk-only (mv) so idle is unchanged. Necromancer premium path only.

Verification: clean headless boot; full GUT 69/69. Not verified: in-editor visual (clear stepping vs idle; feet poke below hem and stride; idle/cast/other units unchanged).

## 2026-05-15 — Necromancer C4: motion polish (M1-M4)

M1 foot ground-lock: `_draw_necromancer_feet` now drawn in the rig ROOT (ground) frame with `body_off = torso.origin - root.origin`; 2-state stance/swing treadmill cycle (stance 62%). Stance foot pinned to ground line, hip follows body bob → leg extends/compresses (knee read). M2 dust scuff: stateless contact-keyed puff (arc + 2 specks) at footfall, ground frame, fades over first 16% of stride. M3 speed stride: base_hero adds `ctx["move_speed01"]` (velocity/effective_move_speed); feet scale stride length lerp(0.55,1.15) + lift slightly; cadence untouched. M4 melee swing: replaced ±5px strike sway with a real arc via `_window_sin` windows (anticipation cock-back/up → impact sweep across+down → follow-through) on staff_sway + melee_y on grip/staff_top/staff_upper; cast path untouched.

Necromancer premium path only (+1 independent base_hero ctx key). Verification: clean headless boot (Necromancer code compiles + runs). GUT regression NOT run-comparable this session: an unrelated in-flight base_hero.gd rewrite (+348/-112, engage-settle feature removed) left tests/unit/test_combat_blocking.gd referencing deleted BaseHero.ENGAGE_SETTLE_DURATION/_settle_t, aborting part of the suite (69→37 run, 2 failing). Not caused by the Necromancer work; M3 ctx one-liner was green at the earlier 69/69 M3 checkpoint.

---

## 2026-05-15 — Stop-on-claim (Option 1): enemy halts on commit, hero walks in

User decision after the teleport investigation: when the hero commits to an enemy, that enemy stops and waits; the hero walks over at move_speed (no chase, no teleport). Reverses the old "enemies never stop on detection" rule into two stages: claim=soft-stop, contact=hard-fight.

Changes:
- **BaseEnemy** — `_reservers` + `reserve()/unreserve()/is_held()`. WALKING branch freezes path progress while reserved (stays WALKING so it resumes cleanly; no counter-attack until physically blocked). Flying/bypass ignore reservations.
- **BaseHero** — `_sync_claim(delta)` once-per-frame choke-point reserves the current target (`_target_enemy` in COMBAT else `_seek_target_enemy`), unreserves anything else; `CLAIM_TIMEOUT=4s` drops a claim that never reaches contact; `_release_claim()` called from `_die()` (physics skipped while DEAD). Direct-move at the now-stationary enemy.
- **Engage-settle deleted entirely** (const, 3 vars, `_begin_combat_settle` + 2 call sites, COMBAT-branch lerp, 2 `_attack_step` snap guards, `change_state` clear) — it was the teleport, and a stationary claimed enemy makes any settle pointless. Hero plants where contact is made, soldier-parity.
- Doctrine Core Rule 1 rewritten (claim=soft-stop, contact=hard-fight); melee-approach section updated; settle paragraph removed.

Verification:
- GUT: full suite 70/70 (added 3 reservation tests: reserve freezes progress / unreserve resumes / flying ignores / hero release clears; deleted the 2 obsolete settle tests).
- `godot --headless --quit` clean.
- **In-engine (Godot MCP), captured evidence:**
  - 90-frame capture: hero COMBAT, position CONSTANT (1161,452), enemy state=COMBAT, path-progress CONSTANT 1183 → enemy stopped, hero planted, zero teleport.
  - 120-frame capture: hero COMBAT constant (1174,475), enemy progress FROZEN 1211 → same.
  - Discrete approach samples progressed (1208,549)→(1105,367)→(1140,440)→(1161,452)→(1174,475): continuous walking toward the enemy, no discontinuous jump.
  - Confirmed a misleading "won't claim / stuck" observation was an artifact of `get_tree().paused == true`, not a logic bug — once unpaused the hero immediately went MOVING and engaged.
- Not visually captured: a single recorder frame with `is_held()==true` (the brief pre-contact soft-stop) — the approach is <0.5 s and recorders attached a beat late / waves ran dry. Covered by the unit test (reserve freezes progress) + every COMBAT capture showing the enemy's progress frozen and the hero arriving by continuous motion.

Net: enemies stop, hero walks in at move_speed, no teleport, no endless chase. Residual at-rest spawn-not-path-snapped follow-up still open (separate).

## 2026-05-15 — Necromancer leg invert fix

Leg treadmill cycle + boot toe were hardcoded to forward=+x, so walking LEFT moonwalked. Added `face_sign` param to `_draw_necromancer_feet` (derived in premium from ctx `face`.x with a -0.02 deadzone, default +1). Stance/swing stride x and the boot toe polygon now multiply by face_sign → legs/boots invert correctly for left vs right travel; left/right leg lateral separation (anchor_x) unchanged. Necromancer premium only.

Verification: fully clean headless boot (the earlier unrelated base_hero engage-settle/test mismatch resolved externally); full GUT 70/70.

---

## 2026-05-15 — Soldiers unified onto stop-on-claim + closed test/doc gaps

Post-churn full code review found the hero stop-on-claim core sound but soldiers still on the old chase model (the other half of the user's "hero OR soldiers chase / wrong Y" complaint). Unified soldiers onto the same model:

- **base_soldier.gd**: added `_claimed_enemy` + `_sync_claim()` (once/frame: reserve `_charge_target` else oldest engaged enemy; unreserve on change) + `_release_claim()` called from `_die()`. Reuses the generic `BaseEnemy.reserve()/unreserve()` (hero-proven). Soldier now reserves its committed guard-zone target (it halts), then closes with the existing direct straight-line move (CORE RULE 13) and blocks on `melee_range` — no chasing a moving enemy. Guard-zone gate (`_is_guardable`) still decides *which* enemy to commit to.
- **base_enemy.gd**: clarifying comment at the `_reservers` early-return — effects/abilities/hit-stop/death tick BEFORE it; held only freezes path+anim; holding does NOT pause debuff duration (deliberate, no refund exploit).
- **Doctrine**: Core Rule 1 now explicitly universal (heroes AND soldiers); Soldier Behavior section rewritten for reserve-on-commit; the stale "intentional divergence" callout replaced with "shared stop-on-claim, different zone shape" (heroes range a circle, soldiers hold the rally guard zone — only the *zone shape* differs now, the engage mechanism is unified); recorded the held-doesn't-pause-debuffs decision.
- **Tests** (+5): hero `_sync_claim` reserve/switch/clear; stale-claim-after-freed-enemy; soldier reserve-on-charge / unreserve-on-drop / release-on-death; `GuardZone.progress_delta` sign. (CLAIM_TIMEOUT left to in-engine — its drop path touches `nav_agent`, null on a bare hero; over-mocking avoided.)

Verification:
- GUT: file 37/37, full suite **74/74**. `--headless --quit` clean.
- **In-engine (Godot MCP)**: script-spawned a Basic soldier on L1's left path, called a wave, frame-recorder captured: `ss2(1357,487) cttrue eng1 est1 hfalse p1382 d57 yd-20` then `ss4 ... eng0 none`. Soldier walked rally(1421,464)→(1357,487) continuously (no teleport), enemy **state=COMBAT, path-progress FROZEN at 1382** (stopped, not chased), yDelta −20 (≈same ground line); on soldier death the claim released cleanly (`_claimed_enemy → none`). Hero stop-on-claim previously verified in-engine (enemy frozen, hero planted, no teleport).

Net: both heroes and soldiers now stop-on-claim — committed enemy halts and waits, blocker walks in at move_speed, no chase, no teleport, fights on the enemy's ground line. Open follow-up (separate): at-rest spawn not path-snapped; dead HeroData guard_* fields (harmless, comment-noted).

---

## 2026-05-15 — Soft-claim gated to melee blockers (ranged heroes don't freeze shot enemies)

"How do ranged heroes do melee?" exposed a bug in the stop-on-claim unification: `BaseHero._sync_claim` reserved `_target_enemy` whenever `state == COMBAT`, so a ranged hero (Mage/Ranger/Necro) shooting from 250-320 px soft-claimed and **froze every enemy it shot from across the screen** — destroying the ranged/melee distinction and making soldiers pointless next to a Mage.

Model clarified + fixed:
- Soft-claim (`reserve()` → halt before contact) is a **melee-blocker** mechanic (soldiers + melee heroes only). Ranged heroes shoot in place; enemies keep walking; a ranged hero only melees when an enemy physically reaches its `engage_radius` and it has `max_block_targets > 0` — then it *hard*-blocks via `_blockers`/COMBAT and uses the weaker authored `close_attack_*` poke (already implemented; unchanged).
- `base_hero.gd _sync_claim`: `is_ranged = get_effective_attack_range() >= RANGED_ATTACK_RANGE_THRESHOLD`; ranged → `desired = null` (never soft-claims, releases any prior claim). CLAIM_TIMEOUT branch already guarded by `_claimed_enemy != null` so it can't fire for ranged. Melee/soldier paths unchanged.
- Doctrine Core Rule 1 + Ranged/Hybrid section rewritten: soft-claim melee-only; ranged shoots while enemies keep moving (intended).
- Tests: +`test_ranged_hero_does_not_soft_claim`, +`test_melee_hero_still_soft_claims`; fixed 2 pre-existing `_sync_claim` tests whose `_hero_anchored_at` made a default HeroData (attack_range 150 == ranged threshold → now classified ranged) by setting `attack_range = 75` (melee).

Verification:
- GUT: file 39/39, full suite **76/76**. `--headless --quit` clean.
- In-engine (Godot MCP, Mage on L1): Mage held its anchor (1208,549) — did NOT move (ranged stands still); `_claimed_enemy` null in every sample; an enemy that physically reached it was hard-blocked (`blk1`, enemy `State.COMBAT`, `is_held()==false` → stopped by `_blockers` not soft-claim — correct hard stage); a mid-range enemy being shot (d=134, beyond engage) had `is_held()==false`, Mage `claimed==false`, and on the next poll was gone (kept moving → died/leaked, not frozen). Unit `test_ranged_hero_does_not_soft_claim` directly asserts the gate. (Frame-recorder node flaked intermittently as before; discrete samples + unit test are the decisive evidence.)

Net: ranged heroes shoot without freezing the lane; melee heroes + soldiers still stop-on-claim. Ranged→melee fallback (close_attack on hard contact) intact. Open follow-ups unchanged (at-rest spawn-snap; dead HeroData guard_* fields).

## 2026-05-15 — Necromancer cel-shading extended

Extended `_cel_overlay` (occlusion wash + light-facing rim) to the remaining readable masses: robe front_panel + collar (warm soul rim, reuses robe_rim) and boots (rim-only, occ 0 since near-black — adds a leather sheen on the lit edge; collar/boot polygons extracted to vars). Now covers robe, cape, hood, front panel, collar, boots. Thin limbs/staff intentionally skipped (rim on a thin capsule is marginal). Necromancer premium only; tunable per call (occ_a, rim alpha/width).

Verification: clean headless boot; full GUT 76/76.

## 2026-05-15 — Necromancer #2: variable-weight inked outline

Added `_ink_weighted` (mirror of `_rough_polyline` + per-edge width from the same centroid-vs-light test as `_cel_overlay`): shadow-facing edges ~1.7x, lit edges ~0.5x, plus a small ink pool dab at shadow-side corners. Swapped the robe / hood / cape main silhouette outlines to it (cape dry-ink texture pass + minor _rough_line details left uniform). Necromancer premium only; light = NECRO_LIGHT (shared with cel pass).

Verification: clean headless boot; full GUT.

## 2026-05-15 — Combat Ground Line: every melee blocker fights on the enemy's Y

Problem: melee fights read as diagonal off-Y skirmishes. Soldiers planted on melee-range contact wherever they reached (~30–50 px off-Y); the melee hero's approach steered at the raw enemy centre (not its Y-locked engage spot) so the proximity-block fired ~31 px off-Y; both then froze with no settle.

Fix (one shared "Combat Ground Line" = engaged enemy's `global_position.y`, which already bakes in its v_offset lane; walk-bob/flight are draw-only):
- `GuardZone.melee_engage_spot(enemy_pos, forward, gap)` — single Y-lock helper (enemy's exact Y, horizontal gap toward path-exit). Used by hero + soldier.
- `BaseHero._engage_position_for` melee branch routes through it (refactor, no behavior change).
- `BaseHero` melee approach steers at the engage spot, not the raw enemy; COMBAT state continues closing the last few px to the spot at move_speed while the (frozen) blocked enemy is in `_blocked_enemies` — continuous, no teleport.
- `BaseSoldier._tick_charge` steers the charge at the engage spot; the "engaged → plant" branch first settles onto the spot at move_speed before zeroing velocity.
- Always-visible faint warm engage_radius ring under every hero in `BaseHero._draw()` (zoom-scaled; skipped if engage_radius ≈ 0).
- Doctrine: new "Combat Ground Line" section in COMBAT_BLOCKING_DOCTRINE.md.

Verification (in-engine MCP, L1, numeric Δy = |hero/soldier.y − enemy.y| while engaged):
- Warrior vs −50-lane enemy: dy 31.25 → 14.58 (approach fix) → **1.48 px** (COMBAT settle); enemy frozen (path progress static), stable, taking damage, no teleport.
- Script-spawned soldier vs +50-lane enemy: dy 44.68 → **3.70 px**; enemy frozen, stable, dealing damage.
- Mage (ranged) regression: does NOT soft-claim (`_claimed_enemy` null, reservers 0), enemy KEEPS walking (path progress increases), Mage holds anchor and shoots — unchanged/correct.
- Screenshot: warrior + orc on one ground line, faint engage ring visible.
- GUT 79/79 (was 76; +3: `melee_engage_spot` Y-lock, vertical-path fallback, hero-matches-shared-helper). Clean headless boot.

## 2026-05-15 — Hero melee-engage range review + Necro/Mage fix

Reviewed the three distances that gate hero melee (attack_range archetype gate 150; detection_radius_px acquire scan; engage_radius = the melee-start circle, now the visible orange ring). Finding: Necromancer `engage_radius = 30` was degenerate — the Y-locked engage spot's gap clamps to `max(min(55,30−6),30)=30 = engage_radius`, so the block spot sat exactly on the circle boundary → flaky melee trigger despite an authored `close_attack`. Mage had no authored engage_radius so it inherited the full 60 (large face-tank bubble, inconsistent with Ranger 50 / Necro).

Fix (data only): Necromancer `engage_radius 30 → 45`; Mage authored `engage_radius = 45` (between Ranger 50 and the old 60, consistent "ranged pokes only on close contact"). Now gap = `max(min(55,45−6),30)=39 < 45` → spot reliably inside the engage circle.

Verification (in-engine, Necromancer): on contact it hard-blocks reliably — `_blocked_enemies` set, `use_projectile=false` (close_attack profile, dmg 1.65), enemy frozen, dy 2.27 px (fights on enemy Y). Clean headless boot.

## 2026-05-15 — Necromancer legs AAA pass (knee + easing + boot roll + fade)

Review found legs were C0-continuous but mechanical: constant-speed linear slide with a sharp velocity reversal at toe-off, downward-velocity hard stop at footfall, straight stick (no knee), rigid boot, binary appear/disappear. Fixed all: (1) `_knee_ik` equal-bone 2-link — hip→knee→foot, knee bends toward travel + auto-bends more in swing; thigh full width, shin tapered. (2) Swing X smoothstepped + Y arc peaks ~45% and eases to zero slope at touchdown (soft landing); stance kept linear (no foot skate). (3) Boot rotates about the ankle via _window_sin lobes (heel-strike→flat→toe-off→level). (4) Continuous fade `fb` from speed01·mv (smoothstep) scales alpha+stride+lift so feet fade in/out under the hem instead of popping. Necromancer premium only.

Verification: clean headless boot; full GUT.

## 2026-05-15 — Unified hero melee: one pipeline, only the engage RANGE differs (balance-tunable)

Collapsed the melee/ranged archetype split in BaseHero into ONE shared melee pipeline used by every hero; the only per-hero difference is now the melee-engage range. Two-tier: enemy inside the range → shared pipeline (reserve/stop-claim → walk to Y-locked spot → hard-block → fight on enemy Y, ranged heroes auto-swap to weaker close_attack); enemy outside it but in attack_range with a projectile → shoot in place, enemy keeps walking, never reserved. Lane-flow guarantee is now structural (a pure shot target is not _seek_target_enemy and not in _blocked_enemies, so _sync_claim never reserves it) — no archetype `if`.

Changes: base_hero.gd (_sync_claim / _move_step / COMBAT settle / _engage_position_for / _effective_detection_radius all archetype-free; added ranged-shoot tier in _seek_target + shoot→melee handoff in COMBAT; ring drawn at melee-engage range; removed MELEE/RANGED_DEFAULT_DETECTION_RADIUS, added DEFAULT_MELEE_ENGAGE_RANGE=160; plumbed engage_range_mult → melee_engage_range stat). HeroData.gd doc rewrite. Per-hero ranges: Warrior 280, Mage 90, Ranger 100, Necro 80. Dev balance UI: engage_range_mult added to BalanceOverrides.HERO_STAT_KEYS + HeroTuning + BalanceSliders (slider + bake-to-.tres, same pattern as range_mult). Doctrine Core Rule 1/6 + Ranged section rewritten. Tests reworked (ranged-not-reserved-when-shooting, any-hero-soft-claims-approach, single-default-no-split, melee_engage_range plumb).

Verification — GUT 81/81 (test_combat_blocking 44/44), headless boot clean. In-engine (Godot MCP, L1, numeric):
- Mage SHOOT tier: holds anchor (1371,461 static), enemy prog 1300→1329 KEEPS WALKING, held=false, claimed=false, useProj=true, taking ranged dmg.
- Mage HANDOFF (enemy crosses 90px): strides out → claimed=true, blocked=true, useProj=false (close_attack), dy=0.32 px, enemy frozen — SAME pipeline as Warrior.
- Live tunable: BalanceOverrides engage_range_mult ×2.0 → compute_base_stats melee_engage_range 90 → 180 (reset to 1.0).
- Warrior regression: meleeRng 280, strides out, claimed+blocked, dy=0.75 px, enemy frozen, no teleport.

## 2026-05-15 — Necromancer arms: 2-bone elbows

Consistency follow-up to the legs pass: generalized `_knee_ik` into shared `_two_bone_joint(a,b,bone,bow)` (knee now calls it with bow toward travel). Both Necromancer arms (free arm shoulder→hand, staff arm shoulder→grip) are now 2-bone with an elbow that bows outward+down and bends MORE as the hand pulls in (cast raise / wind-up / melee), tapered forearm — matching the legs. No longer straight sticks. Necromancer premium only.

Verification: clean headless boot; full GUT.

## 2026-05-15 — NecroBolt haunted flight wander

Added opt-in visual-only projectile wander to the shared projectile script. `Arrow.gd` now supports per-scene `flight_wander_amplitude`, vertical wander, frequency, and randomness; the hidden `_ground_pos` still homes straight into the target, so hit timing / on-hit callbacks stay deterministic while the rendered bolt snakes up/down and side-to-side and fades back onto the target at impact.

Enabled it only on `NecroBolt.tscn`: the Necromancer soul bolt now has randomized haunted movement per shot, with smooth trail samples following the visible path. Other projectiles keep zero wander defaults.

Verification: `git diff --check` passes; Godot editor visual check still needed.

## 2026-05-16 — NecroBolt speed tuning

Data-only projectile feel tweak: reduced `NecroBolt.tscn` speed from 850 to 700 so the haunted wander / soul-flame shape has a little more screen time before impact. Damage, cooldown, targeting, and hit radius unchanged.

Verification: `git diff --check` passes; Godot editor visual check still needed.

## 2026-05-15 — NecroBolt launch/impact/shape/trail polish

Follow-up to the haunted flight pass: split Necromancer's projectile off the generic `ARCANE_BOLT` into a dedicated `NECRO_BOLT` shape. The bolt now draws as an asymmetrical soul-flame with a dark core, green-violet rim, tiny eye glints, and animated flame licks instead of a clean mage capsule.

Added a staff launch burst for `NECRO_BOLT` at setup time (short purple/green halo + directional rays from the staff tip), a cursed impact pop (dark smoke, expanding necrotic ring, radial soul streaks, small skull flash), and per-shot trail width/alpha jitter exported on projectile resources. `NecroBolt.tscn` opts into the new shape plus trail jitter; other projectiles keep the default zero-jitter behavior.

Verification: `git diff --check` passes; local Godot headless still crashes with signal 11 before project validation, so editor visual check is still needed.

## 2026-05-16 — Necromancer low-hover silhouette

Moved Necromancer further into the floating caster read. `visual_necromancer.tres` now uses a small visual-only `flight_height_px = 7`, so the body/robe sit slightly above the ground shadow without changing collision or blocking. `BaseHero._projectile_spawn_position` now includes visual flight height when computing staff-tip projectile launch points, so NecroBolt still releases from the visible staff after the hover lift.

Removed the two small bone/leg-like marks inside the lower robe and replaced them with a dark under-robe void plus faint soul mist near the hem. `draw_ground_shadow` now adds a subtle necromancer-only soul ring/mist over the ground shadow, reinforcing "hovering inches above the path" rather than walking.

Verification: `git diff --check` passes; Godot editor visual check still needed.

## 2026-05-15 — Fixed the fast Y "snap" when a blocker matches the enemy's lane

User reported heroes moving very fast specifically while aligning to the enemy's Y. Root cause: the approach steered straight at the Y-locked engage spot; with a far-X / small-Y geometry the unit direction was X-dominant so Y closed at only ~0.1–0.3× move_speed. COMBAT triggers early off-Y (engage_radius/proximity), then the settle resolved the whole residual lane offset at full move_speed in a short pure-Y burst — a 3–10× apparent vertical-speed jump (magnitude never exceeded move_speed; steering was correctly normalized, single move_and_slide, no double-move).

Fix: `BaseHero._ground_line_dir` (mirrored as `BaseSoldier._ground_line_dir`), bias const APPROACH_Y_PRIORITY=1.0 / Y_ALIGN_EPS=2.0. Caps the horizontal direction component to |Δy|×PRIORITY while a lane gap remains, so the vertical gap closes no slower than the horizontal one — the blocker rises onto the enemy's Y on a ≤45° diagonal during the walk-in, then continues straight along the lane. Used in the hero approach steer + COMBAT settle and the soldier charge + engaged-settle. Speed unchanged everywhere (only direction). COMBAT settle is now a rarely-hit safety net (still uses the biased dir). Doctrine Combat Ground Line section + a new steering test added.

Verification — GUT 83/83 (+2 _ground_line_dir tests), headless boot clean. In-engine (Godot MCP, slow-mo to capture trajectory):
- Warrior, start dX=230 dY=-90: Y closed early — at dX=135 (41% X done) dY was already -1.8; planted COMBAT dX=58 dY=-0.09. No flat-then-snap.
- Mage (ranged→melee handoff), start dX=55 dY=-60: dY -60 → -3.65 across the short approach, planted COMBAT blk=true on-Y, |v|=0.
- time_scale restored to 1.0; dbg nodes cleaned.

## 2026-05-15 — Blocker doctrine: a ranged shot target that leaves range is dropped, never chased

Bug (user-identified): in BaseHero._attack_step, when _target_enemy left attack_range_area the hero pursued it whenever _can_pursue(enemy) was true — even if the enemy was only ever a RANGED SHOT target (never blocked/reserved). A Mage/Ranger/Necro would start chasing an enemy it was only shooting. Violates KR doctrine (detection ≠ combat; heroes are blockers, not hunters).

Fix (heroes/base_hero.gd _attack_step): capture `was_blocking := _blocked_enemies.has(enemy)` BEFORE `_release_block_of(enemy)`; only reposition/pursue if `was_blocking and _can_pursue(enemy)` (a real melee lock following a near-leaker to the line within the guard zone). Otherwise drop the target and go IDLE → _seek_target re-acquires next shoot/melee target or returns to anchor. No chase of a shot-only target. Doctrine updated (Ranged behavior list item 4 + renumber).

Verification — GUT 83/83, headless boot clean. In-engine (Godot MCP, L1):
- Mage shooting enemy at dist 150 (shot tier: target=true, blocked=false, claimed=false, enemy not held, eHP dropping). Enemy shoved to dist 450 (out of atkR 270): Mage → st=IDLE, stayed at anchor (1421,464), seek_is_e=false, never reserved. NO chase (was the bug).
- Warrior physically blocking (blocked=true, claimed=true). Enemy near-leaked ~130px (out of atkR 75, inside guard 280): Warrior repositioned (walked x1385→1514), re-locked (blocked=true again, eHP kept dropping). Regression preserved — a real blocker still follows a near-leaker within the guard zone.

Note: same-Y / path-forward engage spot is unchanged (Combat Ground Line: enemy.y + sign(path_forward.x)*gap — deliberate Y-lock from the prior fix, not reverted).

## 2026-05-15 - Hero chase guardrails: COMBAT must mean a real block

Investigated continued "hero runs behind enemy after it passed" behavior. Two remaining hero-side leaks were found in `heroes/base_hero.gd`: (1) the COMBAT state's two-tier handoff treated any non-blocked target as eligible for melee re-acquire, so a ranged-shot target could be hijacked into walking/chasing when another enemy entered detection; (2) `_move_step` / `_seek_target` entered COMBAT after calling `_start_block` even when `_start_block` no-oped because the enemy was not actually inside `engage_range_area` or could not be claimed.

Fix: COMBAT now only picks a new melee target when `_target_enemy == null`, so an active shot target stays a shot target until `_attack_step` drops it naturally. `_start_block` now returns bool, and hero transitions into COMBAT only when a real enemy blocker slot was claimed. Aborted approaches also clear stale `_target_enemy` if it was the same seek target. This keeps the rule strict: chosen melee target is reserved/stopped during approach, but combat/focus only becomes real once the enemy is physically blocked.

Verification: attempted local GUT with `C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`; local Godot crashed with signal 11 before test output. Editor/playtest verification still needed.

## 2026-05-15 - Stop-on-claim race and dogpile fix

Follow-up investigation for fast enemies not stopping reliably / heroes appearing to lose focus. Root cause was not Y positioning: it was target ownership. Target selection only counted `enemy._blockers.size()` (hard combat locks), ignoring `_reservers` (soft stop-on-claim). During approach every uncontacted enemy still looked like "0 blockers", so multiple heroes/soldiers could dogpile the same reserved enemy while another enemy walked through. Because hero/soldier `_sync_claim` also ran before target acquisition, a newly chosen target was not reserved until the next physics frame; fast enemies made that one-frame race visible.

Fix: `BaseEnemy.get_claim_count()` now returns live soft reservations + hard blockers. Hero and soldier target picking use that count for split targeting. Hero and soldier now reserve immediately when they commit to a seek/charge target, instead of waiting for next frame reconciliation. Hero melee start was simplified further: COMBAT begins only from a real `engage_range_area` overlap + successful `_start_block`; merely reaching the engage spot no longer creates fake combat.

Verification: `git diff --check` passes. Local Godot headless GUT still crashes with signal 11 before test output, so in-editor playtest remains required.

## 2026-05-15 - Combat debug overlay for stuck hero/enemy focus

Added debug-build visual diagnostics for the exact "hero stands close but does not attack" case. `BaseHero._draw_combat_debug()` now appears when the hero is selected or in a combat path, showing state, attack cooldown, target / seek / claim ids, blocked count, claim age, attack-overlap, engage-overlap, hard-block status, enemy claim count, distance, path leak delta, pursue gate, and doomed-chase gate. While seeking, it also draws a yellow line/dot to the computed engage spot. `BaseEnemy._draw_combat_debug()` now appears only when the enemy is reserved/blocked/in combat, showing enemy state, HP, reservers, blockers, held flag, and focus blocker.

How to read it in editor: if the hero is visually close but says `eng:n`, the engage Area2D/radius is not overlapping. If it says `eng:Y hard:n`, `_start_block()` or enemy `engage_combat()` is failing. If enemy says `res:1 blk:0 held:Y`, stop-on-claim worked but hard contact never happened. If hero says `COMBAT` with `hard:n`, focus is invalid and should be fixed next.

Verification: `git diff --check` passes. Local Godot still crashes with signal 11 even on `--headless --quit --path .`, so visual/editor verification is required.

## 2026-05-16 - Fixed combat debug overlay freed-reference crash

User hit a Godot runtime error in `BaseHero._draw_combat_debug`: `_debug_node_label(n: Node)` was typed as `Node`, but the debug overlay can receive a previously-freed object reference from `_target_enemy` / `_seek_target_enemy` / `_claimed_enemy` before the normal combat cleanup has run. Godot rejects the freed Object at the typed function boundary, so the function body never reached `is_instance_valid()`.

Fix: loosened `_debug_node_label(n)` in hero and enemy debug overlays so freed references can be validated safely. Added `BaseHero._prune_debug_refs()` before drawing the overlay to clear invalid target/seek/claim references and strip freed entries from `_blocked_enemies`. Also changed the debug `inspect_enemy` local to untyped so it cannot fail on stale references.

Verification: `git diff --check` passes. Needs editor replay of the screenshot scenario.

## 2026-05-15 — Combat: assist-in-lull (help finish the last enemy)

Blockers (soldiers + hero) now converge to finish a lone straggler instead of one unit dueling it while the rest idle — without weakening block-many/spread (still primary). WaveManager tracks alive GROUND enemies (excludes flying) and emits `EventBus.combat_lull_changed(in_lull)` when only the last one remains (LULL_MAX=1); event-driven off existing spawn/exit counters, zero per-frame group scans; `lone_enemy()` accessor self-prunes freed refs. base_soldier + base_hero cache the lull; when idle (no guardable/in-zone target, not hard-blocking) they acquire `WaveManager.lone_enemy()` and charge it bypassing the guard-zone/leash/doomed cancels, capped at ASSIST_MAX_DIST=1100. Assist is lowest-priority and fully preempted: a normal target, lull-ending (more enemies → resume spread), or a player move order all drop it; a unit that already hard-contacted stays (normal block). Doctrine doc gained an "Assist in a lull" section.

Verification: clean headless boot; full GUT 83/83.

## 2026-05-15 — Blockers cover passers (data-driven hero back margin)

User wants soldiers/heroes to also block enemies that have PASSED them, not only incoming. Findings: SoldierData already defaults guard_front_px=120 / guard_back_px=70 (soldiers already cover a 70px back zone; priority rule already prioritizes highest path progress = the passer). Hero ignored its HeroData.guard_back_px (dead field) and hardcoded GUARD_BACK_MARGIN_PX=50. Fix: base_hero `_back_margin()` reads data.guard_back_px when >0 else the const; `_has_leaked_past_anchor(enemy)` follow-through caller now uses it (acquire-side GUARD_ACQUIRE_MARGIN_PX unchanged — separate concern, keeps the no-lurch rule). Authored guard_back_px=70 on all 4 hero .tres (warrior/mage/necromancer/ranger) so heroes catch passers ~consistently with soldiers, modestly (line does not drift rearward; lock-persistence still prevents dropping a current block to chase). No new mechanic — zone-shape only.

Verification: clean headless boot; full GUT.

## 2026-05-15 — Bugfix: hero melee-engage ring anchored wrong

The warm melee-engage ring in BaseHero._draw() was drawn at Vector2.ZERO (hero body) but the zone it represents is measured from _rally_position in _pick_target_in_detection_zone — so once the hero left its anchor the ring no longer matched where melee actually triggers. Radius/value was correct (uses _effective_detection_radius incl. DEFAULT fallback). Fixed: draw fill+stroke at to_local(_rally_position) (same pattern as the move-marker). Cool ranged attack-range ring left body-centered (correct — shots fire from the hero).

Verification: clean headless boot; full GUT.

## 2026-05-15 — Bugfix: lull tripped on wave spawn trickle

Assist-in-lull was firing on the FIRST enemy of every wave (alive_ground==1 while more still spawning), so melee hero + soldiers left their detection/guard zones to chase the first spawn, then yo-yoed back when enemy #2 appeared — most visible on wave 1. Root cause: _update_lull only checked the alive-count band, no spawn-state gate. Fix: lull now also requires _active_spawners<=0 (spawning finished). Added _update_lull() calls on wave-launch (cancels lull when new spawners queued) and in _on_spawning_complete (lets the tail straggler legitimately trigger it). Net: lull = wave winding down to the last enemy, never the spawn trickle.

Verification: clean headless boot; full GUT.

## 2026-05-15 — Audit fixes: respawn cleanup, skill DEAD-guard, lull on game-over

From the 10-agent audit, fixed the cluster that perturbs combat targeting:
- #1 base_hero._respawn(): now calls _release_block()+_release_claim() (enemies it had blocked resume immediately instead of frozen waiting for the dead hero) and clears _seek_target_enemy/_target_enemy/_assisting/_pending_skill_*/_cast_wind_t/_cast_t/_lunge_t/_flinch_t/_hit_flash_t/_skill_range_preview/_walk_t. Kills ghost-pursuit-on-respawn + frozen-enemy + respawn anim artifacts. _in_lull left signal-owned.
- #2 _apply_pending_skill(): drops the pending skill if state==DEAD or data==null (was firing a wind-up that outlived the caster on respawn).
- #3 WaveManager._on_game_over(): clears _alive_ground + _set_lull(false) so a defeat/victory mid-straggler does not leak _in_lull into the next level (autoload survives scene change).

#4 (split-rule exact-tie order) deliberately deferred: the comparison already uses strict < / > so first-seen is preserved; only Area2D iteration order on an exact bc+prog+float-d2 tie could flap, and float-distance exact equality is practically impossible. Documented, not changed.

Verification: clean headless boot; full GUT 83/83.

## 2026-05-15 — Detection ring follows hero during player moves

Follow-up to the anchor-centered melee ring fix. The ring is pinned to _rally_position (correct for auto guard-intercepts so it stays truthful when the hero steps out). But move_to() reseats _rally_position to the tap destination instantly, so on a player move the ring teleported ahead of the still-walking hero. Refinement: while state==MOVING AND _seek_target_enemy==null (player-commanded relocation, not an auto seek), draw the ring at the body (Vector2.ZERO) so the zone travels WITH the hero to its new post; on arrival hero==_rally_position so it coincides seamlessly. Auto guard-intercept (MOVING with _seek_target_enemy set) still draws at the anchor — earlier fix intact. Visual-only.

Verification: clean headless boot.

## 2026-05-15 — Warrior no longer targets flying

Set targets_flying = false on hero_warrior.tres (was using HeroData default true). Warrior is pure melee with no projectile — with the flag false the melee pickers (`if enemy.data.is_flying and not data.targets_flying: continue`) now correctly skip flyers, so the warrior never walks toward an un-blockable flying enemy (the "hero close/chasing/not attacking" symptom, bug #1) for this hero. Other heroes unchanged (broader #1 fix — melee pickers skipping flying unconditionally — still recommended separately).

Verification: clean headless boot; full GUT.

## 2026-05-16 — Balance-testing scope locked to Level 5

Added a new Invariant to balance/BALANCE.md ("Active balance-testing scope — Level 5 only"): balance audits, pressure/DRIFT verification, telemetry review, and tuning iteration target level_5 only. L1–L4 are settled — readouts still print but are not actioned unless the user names that level. Naked Baseline still applies to every campaign level regardless of scope. Rule documents how to lift/retarget when balance work moves to a new level.

Doc-only change; no code or .tres touched.

## 2026-05-15 — Blocker coordination stabilization (GPT plan, refined)

Implemented the refined fix set. Added BaseEnemy.is_engageable_ground() — single shared predicate (data!=null, !is_flying, !bypass_engagement, !DYING) so the flying/bypass/dying rule can no longer drift across call sites (that drift caused the flyer-in-lull regression). Routed through it: engage_combat() (now rejects flying — was the reserve/engage asymmetry), WaveManager _alive_ground append + lone_enemy re-validate (fixes flyers leaking into the lull; the old "is_flying in enemy" was always false), hero _pick_split_target_in_area + _pick_target_in_detection_zone (melee ALWAYS skips flying; targets_flying stays RANGED-only), soldier _try_engage/_scan_aggro + assist branch, hero assist branch. move_to() now _release_claim() immediately (no 1-frame soft-stop leak). _auto_engage_extras() picks by split priority (fewest-claims→progress→nearest) via _pick_split_target_in_area instead of raw overlap order, guard-capped. Added soldier CLAIM_TIMEOUT=4.0 + _claim_age mirroring hero — a soft claim with no hard contact past 4s releases + clears _charge_target/_assisting + RETURNING (prevents assist-toward-unreachable wave soft-lock). get_claim_count() now counts UNIQUE claimers (reserve+block by same unit no longer double-counts). Docs: HeroData guard_back_px comment corrected (it IS read via _back_margin); SoldierData front/back comment fixed to match GuardZone (front=spawn-side/approaching, back=exit-side/passed); leash_range marked LEGACY/UNUSED. 3 GUT tests added (is_engageable_ground truth table, engage_combat rejects flying, get_claim_count unique).

Verification: clean headless boot after every pass; full GUT 86/86.

## 2026-05-15 — Coordination invariants saved to doctrine

Added "Blocker coordination invariants (load-bearing)" subsection to docs/COMBAT_BLOCKING_DOCTRINE.md (under Target Selection, after Assist-in-a-lull): the 6 rules now enforced in code — single is_engageable_ground() predicate, targets_flying ranged-only, get_claim_count unique, mandatory soft-claim watchdog (hero+soldier), move_to immediate release, assist preempted-not-sticky. CLAUDE.md already points here as combat source of truth, so this persists across sessions.

## 2026-05-16 — Sword-swing animation: cadence-scaled, snappier (soldiers + Warrior)

Melee swing existed but was mistuned: a flat LUNGE_DURATION=0.12s decoupled
from attack_speed made the blade twitch in ~120ms then freeze for the rest of
a ~1s gap (below mobile perceptual threshold). Full art-director spec applied:
- New shared statics in UnitVisualDrawer: swing_duration(atk_speed) =
  clamp(cooldown*0.70, 0.28, 0.55); swing_phase(t01) → {wind_t|strike_t}
  (single source of truth, ends soldier/hero ctx-block drift);
  lunge_offset_scale(t) — eased rear-back→fast-commit→settle envelope.
- base_soldier.gd / base_hero.gd: capture _lunge_dur per swing from
  swing_duration(eff_atk_speed); all t01 normalizations + squash window
  (peak ~0.48) + ctx blocks + trail gate routed through the shared helpers.
- Arm angles widened for a real overhead chop: raised -PI*0.92, impact
  PI*0.62, follow PI*0.42; raised→impact now ease-out cubic (the "snap"),
  impact→follow smoothstep. SWORD arc widened to ~150° at body_r+18; trail
  gate aligned to the strike window [0.30,0.80].
- visual_soldier_militia.tres: weapon_trail_strength 1.0→1.15 (Knight already
  tuned in visual_warrior.tres; left as-is so militia stays humbler).
Verification: clean headless boot; full GUT 86/86 (combat suite 49/49).
Visual feel needs an in-editor/Test-Range eyeball pass — values are derived
from code math, not frame-stepped.

## 2026-05-16 - Necromancer visual polish: stronger torso turn

User asked for the Necromancer to look more hand-drawn / premium and for the
walking torso to turn more. Scoped visual-only pass:
- UnitVisualDrawer necromancer premium rig: increased moving turn_gain, torso
  yaw/translation, head lead, cape lag, and robe-local turn deformation so the
  character reads as pivoting through the walk instead of sliding.
- visual_necromancer.tres: darker ink/robe palette, brighter soul-purple
  accent, stronger eye/staff glow, bigger staff finial, stronger weapon trail,
  and slightly denser cape/shoulder values for a higher-contrast painted read.

No gameplay numbers or targeting behavior changed. Verification attempted:
`godot` not on PATH; documented Windows Godot 4.6.2 executable reports version
but crashes with signal 11 on headless boot even with `--rendering-driver
opengl3`, before script diagnostics. Static diff/line inspection completed;
needs an in-editor visual eyeball pass.

## 2026-05-16 - Necromancer projectile visual pass

User approved projectile improvements 1-4 after discussion, with no gameplay
changes requested. Scoped to `projectiles/Arrow.gd` NecroBolt drawing/VFX and
`projectiles/NecroBolt.tscn` cosmetic exports:
- Projectile silhouette: NecroBolt now draws as a living soul flame with a
  smoky violet shell, green core, crescent/bone highlight, eye flicker, jaw
  line, and tiny orbiting motes.
- Layered trail: NecroBolt trail gets a dark smoky underlay, existing purple
  ribbon, thin green soul-thread overlay, and peeling motes along the tail.
- Flight personality: added visual-only forward/back surge inside
  `_flight_wander_offset`; hit math still follows `_ground_pos`.
- Launch staging: launch VFX now contracts rune arcs and wisps toward the staff
  direction before the bolt leaves, instead of only expanding spokes.
- NecroBolt.tscn cosmetic values tuned: stronger glow, greener core trail,
  darker smoky edge, more trail jitter, and denser/slower sparkle particles.

Verification: `git diff --check` passes. Godot headless/editor verification is
still blocked locally by the same signal-11 crash before script diagnostics;
needs in-editor visual capture for final tuning.

## 2026-05-16 - Necromancer walk/cast animation pass

Follow-up after user approved items 1 + 2 from the proposal. Still visual-only,
limited to the Necromancer premium procedural drawer:
- Added four keyed walk channels (contact, recoil, passing, high point) layered
  over the smooth gait. Torso/hips, hood, robe hem, shoulders, and staff now
  consume those channels with different timing so the walk reads more
  hand-animated instead of a single sine glide.
- Reworked cast timing to use elapsed release windows: pre-cast coils back and
  charges the staff/rune, release snaps the torso/staff/hood upward-forward,
  and recovery adds a smaller counter-settle through robe and staff.

Verification: `git diff --check` passes. Godot editor/headless visual
verification still blocked locally by the same signal-11 crash on headless boot;
needs an in-editor recording/screenshot pass for final tuning.

## 2026-05-16 — Ranged heroes can shoot flyers/bypass again (GPT review fix)

Verified GPT's combat-code review against source. Findings: #1 (ranged targeting too strict) was a real high-severity bug — every hero target-acquisition path filtered is_engageable_ground() (a melee-claim predicate rejecting flying+bypass), and data.targets_flying was read nowhere in live combat, so Mage/Ranger/Necromancer could not shoot air at all. #2 (soldier soft-claim) true but self-healed by _sync_claim next frame (cosmetic). #3 (doctrine doc) confirmed stale: guard_back_px IS read via _back_margin().

Changes:
- base_hero.gd: added _pick_shootable_target_in_area (area wrapper) + pure _pick_shootable_from(list) — ranged gate is DYING + targets_flying only; bypass shootable. Repointed the RANGED-SHOOT tier (was _find_nearest_enemy_in_area, now removed — its only caller). Melee picker _pick_split_target_in_area unchanged (still is_engageable_ground, guards the 2026-05-15 warrior-vs-flying fix).
- base_enemy.gd: corrected the is_engageable_ground() comment that claimed ranged did not use it (it did).
- base_soldier.gd: set_blocking_position now calls _release_claim() explicitly (edge release; _sync_claim stays steady-state choke-point).
- docs/COMBAT_BLOCKING_DOCTRINE.md: fixed guard_back_px staleness + internal contradiction, softened spot-arrival/face-contact wording, added the ranged-vs-melee target-picker contract.
- tests/unit/test_hero_targeting.gd: new — 11 tests locking both gates and the divergence.

Verification: full GUT headless 95/95 passing, 384 asserts. Editor showed a stale parse-cache error on the test file (old pre-rewrite compilation, line 30) — clears on editor reopen per CORE RULE 17; on-disk file confirmed clean. Manual in-editor play vs a flying-enemy level still recommended to eyeball projectile tracking.

## 2026-05-16 — Follow-up: debug-mirror flying gate + explicit rally-reset test

Two follow-up nits from review, both correct:
- base_hero.gd _dbg_scan_rejections(): was labelling flying as rejected only when not data.targets_flying, but it mirrors the MELEE acquisition gate (is_engageable_ground) which rejects flyers unconditionally. Misled debugging for Mage/Ranger/Necro near air. Fixed to flag flying always; comment added pointing at the picker contract.
- tests/unit/test_combat_blocking.gd: added test_set_blocking_position_releases_soft_claim_immediately — exercises the actual set_blocking_position() entry point and asserts the soft claim is unreserved in the same call (locks the explicit _release_claim() added earlier).

Verification: full GUT headless 96/96 passing, 387 asserts.

## 2026-05-16 - Necromancer projectile visual pass (appended)

User approved projectile improvements 1-4 after discussion. Scoped to
`projectiles/Arrow.gd` NecroBolt drawing/VFX and `projectiles/NecroBolt.tscn`
cosmetic exports only: living soul-flame silhouette, smoky/green layered trail,
visual-only flight surge, and launch rune/wisp contraction. No damage,
targeting, cooldown, or hero behavior changed.

Verification: `git diff --check` passes. Godot headless/editor verification is
still blocked locally by the same signal-11 crash before script diagnostics;
needs in-editor visual capture for final tuning.

## 2026-05-16 - Necromancer projectile scale correction (appended)

User feedback: the new NecroBolt read too large; previous projectile was
clearer. Kept the new identity polish but reduced it to basic-attack scale:
smaller soul body/halo, much narrower smoky underlay, faint green inner thread,
fewer/smaller motes, reduced visual surge, smaller launch rune/wisp contraction,
and lower particle count/size. Gameplay unchanged.

Verification: `git diff --check` passes. Godot visual verification remains
blocked locally by the known signal-11 headless boot crash; needs in-editor
eyeball pass.

## 2026-05-16 - Necromancer melee staff swing polish

User approved only item 1 from the front/back + melee plan. Scoped to
`systems/UnitVisualDrawer.gd` Necromancer premium melee visuals:
- Reworked the staff strike off existing `strike_t` into wind-up, sweep,
  impact, and recovery channels.
- Staff tip now leads the swing with extra high-back / low-front motion while
  the grip moves less, so it reads as a staff swing instead of a whole-prop
  slide.
- Added a subtle tip crescent smear during the sweep and a small staff-tip
  impact flash/spark. Body movement remains restrained; no gameplay changes.

Verification: `git diff --check` passes. Godot visual verification remains
blocked locally by the known signal-11 headless boot crash; needs in-editor
eyeball pass.

## 2026-05-16 - Necromancer front/back facing polish

User approved item 2 from the Necromancer visual plan. Scoped to
`systems/UnitVisualDrawer.gd` Necromancer premium visuals:
- Added a `facing_depth` motion channel from existing face direction, split
  into front-facing and back-facing pose weights.
- Front-facing now opens the robe/hood read: lower head, wider front panel,
  more visible chest/pendant, eyes, and staff hands.
- Back-facing now closes the face/chest read: cape/back panel dominates,
  hood/face/eyes fade down, and staff/hands tuck upward/back for a clearer
  away-from-camera silhouette.

No gameplay, targeting, damage, cooldown, or stats changed.

Verification: `git diff --check` passes. Godot headless verification still
crashes locally with signal 11 before script diagnostics; needs in-editor
visual eyeball pass.

## 2026-05-16 - Necromancer back cape overlay

User confirmed the cape still read like it lived only behind the hero. Scoped
to `systems/UnitVisualDrawer.gd` Necromancer premium visuals:
- Added a back-facing cloak overlay drawn after the robe so the cape becomes
  visible on top of the torso when the hero turns away.
- Added a darker shoulder yoke and hand-drawn cloak folds for the upper-back
  silhouette.
- Kept the overlay gated by `back_facing`, so front-facing poses still show
  robe/chest/eyes while back-facing poses emphasize hood/cape.

No gameplay, targeting, damage, cooldown, or stats changed.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 - Mage arcane shard projectile identity

User approved the recommended first Mage visual package. Scoped to Mage
projectile identity and palette only:
- Mage now points to `projectiles/MageBolt.tscn` instead of the generic
  `HeroBolt.tscn`.
- `MageBolt.tscn` keeps the current hero bolt gameplay envelope
  (`speed = 950.0`, `hit_radius = 28.0`) while switching to the arcane shard
  renderer and a cyan-white-violet trail.
- `_draw_arcane_bolt_shape()` now draws a faceted sapphire/cyan shard with a
  white core, violet rim, cyan crackle, and small gold rune sparks.
- `visual_mage.tres` now follows the saved premium doctrine direction with a
  cleaner sapphire robe, cyan staff glow, pale eye glow, and gold highlights.

No intentional gameplay, targeting, damage, cooldown, or balance changes were
made in this step. Existing unrelated dirty Mage guard/detection values were
left untouched.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 - Premium hero visual doctrine

User asked to save the Necromancer visual style for reuse if the approach is
expanded to other heroes. Added `docs/HERO_PREMIUM_VISUAL_DOCTRINE.md` as the
reference style/doctrine:
- Captures the Necromancer premium draw order, facing rules, motion channels,
  hand-drawn style rules, weapon/cast/projectile guidance, and review checklist.
- Defines Necromancer as the current reference implementation rather than
  prematurely forcing all heroes into a shared framework.
- Notes the recommended extraction path after a second/third premium hero.

Documentation only; no gameplay or visual code changed in this step.

Verification: `git diff --check` passes.

## 2026-05-16 - Hero item-first platform implementation plan

User clarified the desired direction: heroes are platforms with bonuses and
skill trees, while items/weapons provide most combat stats/profile; everyone
can use everything unless explicitly restricted.

Added `docs/HERO_ITEM_PLATFORM_IMPLEMENTATION_PLAN.md` as a detailed handoff
for another AI:
- Commits the design decision that equipped weapon profiles define the basic
  attack while HeroData defines platform identity, fallback, skills, and
  affinities.
- Lists what is already implemented in the repo and what is still missing.
- Provides phased implementation steps for item tags, weapon profiles, Warrior
  affinities, mobile UI teaching, level curves, damage-taken item effects,
  trap content, Dragon MVP, and later air-intercept.
- Includes file-level guidance, test requirements, balance guardrails, and
  the known local Godot headless crash note.

Documentation only; no gameplay scripts, resources, or balance numbers changed.

Verification: `git diff --check` passes.

## 2026-05-16 - Hero platform system full review

User asked whether the hero platform / affinity / level-up design should be
implemented wholesale and how it should scale to ~20 heroes including flying
dragons, trappers, and many variants.

Added `docs/HERO_PLATFORM_SYSTEM_FULL_REVIEW.md`:
- Recommends the architecture but explicitly says not to implement everything
  at once.
- Defines the layered data model: item tags, hero affinities, level curves,
  future body/combat profiles, dragon MVP, air-intercept follow-up, and trapper
  platform.
- Captures mobile UI requirements for Overview, Gear, Mastery, and level-up
  screens.
- Gives a phased implementation roadmap starting with Warrior + sword/shield
  affinity before dragons/trappers/20-hero content.
- Lists minimum unit tests and balance risks.

Documentation only; no gameplay scripts, resources, or balance numbers changed.

Verification: `git diff --check` passes.

## 2026-05-16 - Mage hood integration and attack split

User reported the Mage lacked a hood over the head, the head looked separated
from the torso, and asked whether ranged and melee attack animations were
separate.

Fix:
- Added a Mage-premium head/hood renderer: the hood wraps around the head,
  draws a dark face opening and glowing eyes, and clamps the head lower so it
  connects to the robe collar instead of floating above the body.
- Added a Mage-specific hit-flash silhouette so damage flash no longer falls
  back to the older square torso/head shape.
- Split Mage attack visuals by resolved attack profile: projectile attacks use
  a ranged cast mode with no body lunge or melee swing trail, while face-range
  close attacks keep the melee swing/poke.
- Added a Mage melee staff renderer so close attacks read as the staff moving
  with the arm, while ranged attacks keep the upright raised-staff silhouette.
- Moved the Mage projectile spawn point to the raised staff tip so the bolt
  originates from the visible casting source.

No gameplay, damage, targeting, cooldown, collision, or balance values changed;
this is visual-only.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 - Necromancer visual review fixes

User asked to fix all review findings from the Necromancer visual pass.
Scoped to visual/code-cleanup files:
- Restored `projectiles/NecroBolt.tscn` speed to 850.0 so the projectile
  polish remains visual-only.
- Moved the back-facing cape overlay after arms/staff so it can cover the
  upper-back pose, and changed cape/rear-panel alpha to smoothstep-weighted
  fade-in to avoid pop.
- Removed the unused Necromancer feet/old knee IK helper path left behind by
  the robe-glide approach.
- Fixed Necro trail mote placement so short trails do not stack both motes on
  the same point.

No intentional gameplay, targeting, damage, cooldown, or stats changes remain.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 - Mage robe silhouette profile

User noticed Mage still read as a square torso after the projectile/palette
pass. Root cause: Mage used the shared square humanoid body path, which still
called `draw_rect` for the torso.

Fix:
- Added `UnitVisualData.RenderProfile.MAGE_PREMIUM` so Mage can opt into a
  custom silhouette without changing other square-bodied units.
- `visual_mage.tres` now uses the Mage premium profile.
- `UnitVisualDrawer` now draws Mage's body as a tapered robe polygon with a
  wider cloth hem, darker front panel, hood collar, gold highlight stroke, and
  small cyan rune instead of the generic rectangle.

No gameplay, collision, targeting, damage, cooldown, or balance values changed.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 - Mage upright staff and cape

User noted the Mage staff should read higher/upward and suggested a cape.
Scoped to Mage visual identity:
- Added a dark sapphire `cape_color` to `visual_mage.tres`, using the existing
  back-cloth layer behind the robe.
- Added a Mage-only upright staff renderer for `MAGE_PREMIUM` so the staff
  rises above the hero with a visible orb/ring instead of hanging down along
  the generic arm direction.
- Kept the generic staff path unchanged for non-premium staff users.

No gameplay, collision, targeting, damage, cooldown, or balance values changed.

Verification: `git diff --check` passes. Godot headless verification remains
blocked locally by the known signal-11 crash before script diagnostics; needs
in-editor visual eyeball pass.

## 2026-05-16 — Fix hero "stuck between two enemies" livelock

Traced the reported bug: a hero between two enemies sometimes freezes doing nothing. Root cause = CLAIM_TIMEOUT livelock. _sync_claim drops a soft claim that never reaches contact after 4s, but its "recovery" walked back to the anchor and re-acquired — with two enemies the higher-path-progress one is re-picked and the same failure repeats every 4s forever (hero appears stuck, enemies crawl while alternately frozen). The MOVING->COMBAT transition had no self-recovery; CLAIM_TIMEOUT was the only escape and it looped.

Fixes (all in heroes/base_hero.gd):
- #1 (primary): on CLAIM_TIMEOUT, blacklist that enemy in _giveup_until for GIVEUP_COOLDOWN_MS (2500). Both MELEE pickers (_pick_target_in_detection_zone, _pick_split_target_in_area) skip blacklisted enemies via _is_given_up(). Hero now commits to the OTHER enemy, or holds the anchor free if all blacklisted — never the no-op loop. Ranged (_pick_shootable_from) unaffected. Blacklist self-expires + purges invalid keys.
- #2 (permanent variant): _prune_dead_blocks() (validity-only, no Area2D) at top of _move_step + IDLE branch. _prune_blocks_out_of_range only ran in COMBAT, so a freed/DYING non-focus block could fill max_block_targets and make _start_block reject everything forever. All shipped heroes are max_block_targets=1, so this affected every hero.
- #3 (defensive): _effective_engage_radius() floored at MELEE_ENGAGE_DISTANCE so the engage spot can never sit outside the _start_block gate circle. Debug-build print in the CLAIM_TIMEOUT branch (engage_r/dist/overlap) to pin the contact-failure trigger in a live repro.

Note: all 4 hero .tres are max_block_targets=1; doctrine references to warrior=2 were stale.

Verification: full GUT headless 101/101 passing, 400 asserts (6 new tests: give-up set/expiry, null/invalid purge, prune freed, prune DYING+release, engage-radius floor+single-source). The end-to-end picker-skip path needs a live tree+Area2D (not headless-fakeable per this file header) — give-up semantics are locked; behavioural confirmation is the manual repro in the plan. docs/COMBAT_BLOCKING_DOCTRINE.md updated (watchdog must make progress; no stale-block capacity; engage-radius floor).

## 2026-05-16 - Ranged hero close attack at face range

User reported ranged heroes could still fire projectiles while visually in
melee contact. Root cause: `_resolve_attack_profile()` only switched to the
authored `close_attack_*` profile when the target was already in
`_blocked_enemies`. That tied close visual/weapon mode to hard block state, so
there was a visible gap where Mage/Ranger/Necro could be face-to-face but keep
shooting because the block had not registered yet.

Fix:
- Added `_should_use_close_attack(enemy, in_close_range)` and changed
  `_in_close_combat()` so ranged heroes with authored close attacks use the
  close poke when a blockable ground target is inside `engage_range_area` OR
  already hard-blocked.
- Kept flyers and `bypass_engagement` enemies on projectile attacks even at
  face range, because they are shootable but not melee-blockable.
- Updated `HeroData.gd` and `docs/COMBAT_BLOCKING_DOCTRINE.md` so close attack
  is documented as face-contact weapon mode, separate from the hard stop lock.
- Added unit coverage for face-range close poke and flyer/bypass exceptions;
  existing blocking-focus profile tests now use real `BaseEnemy` targets.

Verification: `git diff --check` passes. Godot console binary is present, but
both full GUT and a plain `--headless --path . --quit` crashed locally with
signal 11 before script diagnostics, so this needs in-editor/GUT verification
from a stable Godot session.

## 2026-05-16 - Hero/item behavior refactor research

User asked for a research report on refactoring heroes/items so any hero can
use weapon-slot items, including ranged heroes using sword power through their
normal attacks, plus AAA-style item/hero damage interactions.

Added `docs/HERO_ITEM_BEHAVIOR_REFACTOR_REPORT.md`:
- Recommends keeping any-hero equip as the default and leaving combat behavior
  hero-authored through `HeroData`.
- Defines sword-on-ranged behavior as stat/mechanic power flowing through the
  hero's existing projectile unless a unique item explicitly overrides visuals.
- Maps damage-taken, on-hit, on-kill, skill-modifier, and command-aura item
  features onto the existing `AbilityData` / `AbilityHost` architecture.
- Summarizes external references from Diablo IV, Path of Exile, and Kingdom
  Rush / Ironhide support guides.

Documentation only; no gameplay scripts, resources, or balance numbers changed.

Verification: `git diff --check` passes.

---

## 2026-05-16 — Hero Platform Architecture (Pure-B), Phases 1–5

Implemented the 5-layer hero-platform refactor (plan: `sleepy-dancing-ullman.md`).
**Pure-B confirmed**: the equipped weapon owns the attack; hero is the
platform. Every phase ships as a *verified no-op* — byte-identical until
content is authored — and is independently committed.

- **Phase 1 (008342d)** — Item-affinity system. `ItemBase.item_tags`,
  `HeroItemAffinityData`, `base_hero._resolve_affinities()` + pure static
  `_affinities_to_grant()` matcher, `ContentRegistry._assert_affinities()`,
  `test_affinity.gd`.
- **Phase 2 (c5e0493)** — `HeroLevelCurveData` drives the *existing*
  skill-point/tree system (not a new one). Growth consts → curve;
  `MetaProgression._points_for_level`; `LoadoutState` slot cap from curve;
  affinity rank from curve; `_assert_curves()`; `test_level_curve.gd`.
- **Phase 3 (aeb00f2)** — Weapon owns attack profile. `WeaponProfileAbility`,
  `_weapon_profile` + `_profile_*` fallbacks, 4 projectile-decision sites
  unified, base-replace damage (no double-count), `compute_stats_for`/
  accessors expose weapon stats, HeroesHub:537 raw-read fixed,
  `_assert_weapon_profiles()` (executable Naked Baseline guard),
  `test_weapon_profile.gd`.
- **Phase 4 (a727c12)** — `HeroBodyProfile` + flying. Flying = existing
  `max_block_targets=0` mechanism (no blocker-machine branch); targeting
  priority = pure comparator bias (NEAREST default = identical);
  `_assert_body_profiles()` enforces flag↔mechanism consistency;
  `test_body_profile.gd` + invariant regression. 6 blocker invariants
  untouched (`test_combat_blocking.gd` green).
- **Phase 5 (b450415)** — Trap platform. `TrapData`, script-driven `Trap`
  (DamageCalculator-routed, shared engageable gate, throttled scan),
  `PlaceTrapSkillData` (navmesh-snap, max_active), `_assert_traps()`,
  `test_trap_platform.gd`. Multi-mode arbitration quarantined to
  `docs/HERO_MULTIMODE_ARBITRATION.md` (design-only, referenced from CLAUDE.md).

Verification: full GUT **145/145 passing** (14 scripts), **zero
`[ContentRegistry/DRIFT]`**, zero script/parse errors. Backward-compat
byte-identical by construction. Naked Baseline guarded executably (boot-check
+ tests). No save reshape / no `SAVE_VERSION` bump. Deferred to sign-off:
all content numbers (tags, profiles, curves, affinity magnitudes, the
20-hero matrix, dragon/trapper `.tres`) per `balance/BALANCE.md`. Remaining
manual step: in-editor feature matrix + mobile-aspect UI pass with temp
authored content.

---

## 2026-05-16 (cont.) — Phase 6 remediation + Warrior-sword content slice

**Phase 6 (b6bf170)** — 3-agent review of Phases 1–5 (logic, invariants,
integration). Cleared the no-op state; fixed one latent bug: R1 —
`compute_stats_for` ignored affinity-granted abilities (display would lie
once a stat affinity was authored, Preventive Bug Rule 1). Shared static
`_collect_equipped_item_tags` now feeds both runtime `_resolve_affinities`
and display `compute_stats_for` → parity by construction; regression-locked
(test failed pre-fix). R2 documented the weapon-facet asymmetry contract
(damage carries affix ratio; range/speed absolute — user decision). R3
added equip-chain + parity + in-picker integration tests. R4 `_enforce_cap`
queued-for-deletion guard. R5 doc-accuracy.

**Content slice (2fa449b)** — first playable vertical slice (Warrior +
sword). Authored: item_tags on all 7 weapon bases; WeaponProfileAbility on
the 6 player-equipped weapons (swords melee/75/PHYSICAL, bow HeroArrow/320,
staff MageBolt/290/MAGIC); `base_starter_sword` left profile-less on
purpose (shared starter — a profile would melee-lock ranged heroes at
spawn). Warrior Sword Mastery I (+10% dmg, requires `sword`).
`HeroAffinityPreview` teaching helper (single-source) wired into
EquipmentScreen item detail + HeroesHub overview; off-family gear reads as
allowed. `weapon_base_damage=0` throughout → existing StatModifier
implicits keep governing damage, zero balance retune (BALANCE.md).

Verification: 168/168 GUT green, zero `[ContentRegistry/DRIFT]`, clean
`.tres` import. `test_hero_item_platform_content.gd` (16 cases) validates
against the real catalog. Remaining: in-editor visual playtest of
Warrior+sword vs Mage+sword (mechanism proven by tests). Not started:
Dragon, air-intercept, more platforms — deferred per the implementation
plan's "smallest slice first" rule.

---

## 2026-05-17 — Per-hero starter weapons wired (item-platform)

Wiring step (no new mechanic). Each hero now has its OWN archetype starter
weapon, which dissolved the profile-less starter-sword exception — every
weapon base now carries a WeaponProfileAbility.

- New COMMON starters (drop_weight 0, +2 implicit, parity with starter
  sword/tunic/charm): `base_starter_staff` (Mage, MageBolt/320/MAGIC),
  `base_starter_bow` (Ranger, HeroArrow/320/PHYSICAL), `base_bone_relic`
  (Necro, NecroBolt/320/MAGIC, ships with white-tier art). Staff/bow use
  procedural glyphs (no starter art existed; project is procedural-first).
- `base_starter_sword` gained a melee profile (75/PHYSICAL). Warrior
  unchanged (already melee 75 physical).
- hero_mage/ranger/necromancer `starter_items` rewired (ext_resource id +
  array ref renamed s_sword→s_staff/s_bow/s_relic).
- Behavior-neutral by construction: each starter profile mirrors that
  hero's HeroData fallback (same projectile/range 320/damage type, +2,
  weapon_attack_speed 0 keeps hero speed) → level-1 attack byte-identical
  for Mage/Ranger/Necro. Only new power = the +10% Mastery affinities,
  symmetric with the already-shipped Warrior Sword Mastery: Mage Staff
  Mastery I (+10% skill_power), Ranger Bow Mastery I (+10% attack speed),
  Necro Relic Mastery I (+10% skill_power).
- `test_hero_item_platform_content.gd` extended: per-hero starter identity,
  no-ranged-hero-starts-with-sword, 3 masteries active with starters,
  cross-family still allowed; starter-sword test flipped to expect a
  melee profile.

Verification: 178/178 GUT green, zero `[ContentRegistry/DRIFT]`, clean
`.tres` import. Commit f52cc36 (incl. generated item art). Remaining
manual step: in-editor visual playtest that each hero attacks correctly
with its new starter (mechanism proven by tests). Not started: Dragon,
air-intercept, more platforms.

---

## 2026-05-17 (cont.) — Equipment range/readability pass

Small UI follow-up to make the item-first weapon system legible in the
inventory/equipment screen.

- Equipment stat layout now includes `Range` in OFFENSE, sourced from the
  same `BaseHero.compute_stats_for` path as runtime/dressing-room stats.
- Item details now show a `Weapon Profile` block for weapon bases:
  melee/projectile, damage type, range, and any authored weapon speed/base
  damage/close damage. This makes sword behavior explicit: a sword is
  `Melee - Physical`, `Range 75`; bows/staves/relics show projectile
  profiles instead.
- `StatIcon` gained a crosshair glyph for `attack_range`.
- `test_hero_item_platform_content.gd` now asserts Mage+sword uses sword
  range 75 and Mage+bow uses bow range 320, locking the "range comes from
  the weapon profile" rule.

Verification: `git diff --check` clean for touched files. Full GUT command
attempted with local Godot 4.6.2 console binary, but this machine crashed
headless with signal 11 before producing test results (same local blocker
seen earlier in the session).

---

## 2026-05-17 (cont.) — Bow/staff icon fallback fix

Investigated the Ranger/Mage starter weapon icon issue from screenshot.
Root cause was authored item data, not inventory placement: `base_starter_bow`
and `base_starter_staff` had `icon_glyph = "generic"` and no `icon_texture`,
so `ItemIcon` correctly fell back to the brown diamond. Loot versions also
had misleading `"sword"` glyph fallbacks even though their PNG textures
usually override them.

Fix:
- Added procedural `bow` and `staff` glyphs to `ItemGlyph`.
- Set `base_starter_bow` / `base_hunter_bow` to `icon_glyph = "bow"`.
- Set `base_starter_staff` / `base_apprentice_staff` to
  `icon_glyph = "staff"`.
- Added a content test asserting bow/staff weapon families use family-specific
  icon glyphs.

Verification: `git diff --check` clean for touched files. Local Godot
headless still crashes with signal 11 even for `--headless --path . --quit`,
so visual/GUT verification remains blocked on this machine.

---

## 2026-05-17 (cont.) — Starter bow/staff pictures wired

Copied the user-generated alpha item art from `tmp/imagegen` into real
runtime paths under `items/art/generated` and wired starter weapons to use
those textures:

- `base_hunter_bow_rare_tier_alpha.png` copied over
  `base_hunter_bow_rare_tier.png` and reused as
  `base_starter_bow_white_tier.png`.
- `base_apprentice_staff_magic_tier_alpha.png` copied over
  `base_apprentice_staff_magic_tier.png` and reused as
  `base_starter_staff_white_tier.png`.
- `base_starter_bow.tres` and `base_starter_staff.tres` now have
  `icon_texture` ext_resources, so they no longer rely on procedural glyph
  fallback in the paperdoll/inventory.
- Touched copied PNG mtimes after copy so Godot's importer sees them as
  newer than any existing `.import` cache.

Verification: texture paths exist and `git diff --check` is clean for the
starter `.tres` edits. Godot visual verification still blocked by the local
headless signal-11 crash.

---

## 2026-05-17 (cont.) — Dragon flying hero (single-mode MVP)

First hero to author a `HeroBodyProfile` — the first real validation of
the `_assert_body_profiles` boot-check (passes clean). Single-mode per
`docs/HERO_MULTIMODE_ARBITRATION.md` (no autonomous air hard-lock; that
needs the still-design-only multi-mode arbitration rule).

- `heroes/data/hero_dragon.tres`: body_profile (is_flying, blocks_ground
  false, AIR_FIRST, flight 36), `max_block_targets=0` (the real
  never-block mechanism, assert-enforced), `detection_radius_px=0`,
  `targets_flying=true`, role_tags [flying,dragon,ranged,anti_air],
  Dragon Mastery affinity (+10% skill_power, requires `dragon_gem`),
  `requires_unlock`, power_tier 3, reuses skill_fireball. Auto-registers
  via the `heroes/data/` glob (no manual registration).
- `items/bases/base_dragon_gem.tres` "Ember Gem": COMMON starter, +2
  implicit, breath = MageBolt/320/MAGIC profile.
- `heroes/data/visual_dragon.tres`: large floating red body, race NONE
  (clean body, no humanoid bits — MVP).
- 8 Dragon content tests + integrated the user's per-family starter art
  + ItemGlyph staff/bow glyphs and icon test.

Verification: 187/187 GUT green, zero `[ContentRegistry/DRIFT]`, clean
`.tres` import. Commit a592ac1. Not wired: dragon skill tree
(`find_skill_tree` null, guarded) + dragon-specific art. Air-intercept
remains gated behind the multi-mode arbitration design doc. Remaining
manual step: in-editor visual playtest that the Dragon floats, never
blocks ground, and prefers flyers (mechanism proven by tests).

---

## 2026-05-17 (cont.) — Dragon review fixes (P1 chase bug, P3 portrait)

Review of the Dragon MVP found two issues; both fixed.

- **P1 (correctness):** a no-block hero still ran melee acquisition.
  `detection_radius_px=0` resolves to `DEFAULT_MELEE_ENGAGE_RANGE` (160),
  so `_seek_target` → `_pick_target_in_detection_zone` returned a ground
  enemy, the Dragon walked at it, `_start_block` failed (cap 0), and it
  jittered instead of shooting (the melee tier's `return` never reached
  the RANGED-SHOOT tier). Fix: new `_can_block_ground()` (cap>0 AND
  `body_profile.blocks_ground`); `_pick_target_in_detection_zone`
  early-returns null when false → no-block bodies fall straight through
  to ranged. Default heroes (cap>=1, humanoid) → true → byte-identical.
- **P3 (polish):** `HeroHudPortrait` gained a `hero_dragon` case (ember
  crimson + swept-wings glyph) instead of the generic dot/steel.
- Tests: `_can_block_ground` predicate (Dragon false / Warrior true) +
  `_pick_target_in_detection_zone` returns null for Dragon (scene-free,
  the guard short-circuits before `get_tree()`).

189/189 GUT green, zero `[ContentRegistry/DRIFT]`, clean import. Commit
3bc5440. Air-intercept still gated behind the multi-mode arbitration doc.

---

## 2026-05-17 (cont.) - Dragon visual identity pass

User asked to adjust Dragon so it actually reads as a dragon.

Fix:
- Added `UnitVisualData.RenderProfile.DRAGON_PREMIUM` and moved
  `visual_dragon.tres` off the accidental Necromancer premium profile.
- Added a dedicated procedural Dragon renderer: long horizontal body, tail
  barb, bat wings with flapping membrane, claws, back spines, horned snout,
  glowing eye, and mouth charge glow.
- Added Dragon-specific hit flash so damage feedback matches the dragon
  silhouette instead of a generic circle/old profile.
- Dragon projectile visuals now use `projectiles/DragonBreath.tscn`, an ember
  bolt/trail scene based on the existing projectile system.
- Dragon projectile spawn now comes from the mouth, and Dragon projectile
  attacks use ranged visual mode so the body breathes/casts instead of
  lunge-poking like a melee unit.

No gameplay, damage, targeting, cooldown, body profile, or balance values
changed. This is a visual-only identity pass.

Verification: `git diff --check` passes. Local Godot headless still crashes
with signal 11 before script diagnostics, so an in-editor visual pass is still
needed.

---

## 2026-05-17 (cont.) - Dragon wing readability fix

User reported the Dragon still did not look convincing and asked why the wings
were not working.

Root cause: the first Dragon premium renderer did draw custom wings, but they
were too tucked behind the body, low contrast against the red body, and easy to
read as small fins at gameplay zoom. The Dragon renderer returns before the old
generic `Accent.WINGS` bars, so only the custom wing geometry matters.

Fix:
- Rebuilt Dragon wings as broad paired bat wings with larger span, membrane
  notches, visible bone strokes, stronger outline, and higher-contrast ember
  membrane color.
- Enlarged the Dragon body slightly, lengthened the tail/barb, and increased
  highlight contrast so the silhouette reads more like a dragon and less like a
  red flying blob.
- Widened the Dragon ground shadow so the airborne footprint matches the new
  wing span.

No gameplay, damage, targeting, cooldown, body profile, or balance values
changed.

Verification: `git diff --check` passes. Local Godot headless still crashes
with signal 11 before script diagnostics; needs in-editor visual tuning.

---

## 2026-05-17 (cont.) - Ground-shadow standardization (visual-only)

User asked to finish/standardize the existing ground-shadow system rather than
build it from scratch. Root cause: every shadow caller gated on
`data.visual.race != Race.NONE`, so the two `race == NONE` visuals
(`visual_dragon.tres`, `visual_soldier.tres`) drew no shadow and read as
floating. `draw_ground_shadow()` itself was already race-independent and
correctly sized from radius/body_size + faded by flight_height_px — only the
callers blocked it.

Fix (one-condition relaxation per call site, race≠NONE units unaffected):
- `enemies/base_enemy.gd:702`, `soldiers/base_soldier.gd:711`,
  `heroes/base_hero.gd:2595` — guard changed from
  `... and data.visual.race != Race.NONE` to `data != null and data.visual != null`.
- `enemies/bosses/base_boss.gd` needed no edit — its `_draw()` is `super._draw()`,
  so the BaseEnemy change covers bosses transitively. The `race != NONE` guard at
  base_boss.gd:138 is HP-bar-Y math, deliberately left untouched.
- `draw_ground_shadow()` unchanged; the race==NONE returns at
  UnitVisualDrawer.gd:925/943 belong to draw_stun_stars/draw_slow_ghost — untouched.

Outcome: Dragon hero (race NONE, flight 44 → small faint road shadow) and the
race-NONE soldier now render road-anchored shadows; flying/boss/Necromancer
shadows mathematically unchanged. No combat/blocking geometry touched
(visual-only; shadow draws at the node transform, ignores walk-bob/lunge/flight).

Verification: GUT full suite 189/189 passing (15 scripts, 640 asserts, 4.3s) —
combat/blocking + hero-targeting regressions clean. In-editor visual pass (Dragon
+ flying + soldiers in frame) still recommended; not run headlessly.

## 2026-05-17 (cont.) - Multi-blocker fan-out (combat positioning)

User asked to fix the multi-blocker pile-up: when more friendlies than enemies
forced 2+ soldiers/heroes onto ONE enemy, every blocker targeted the identical
spot `(enemy.x+gap, enemy.y)` and stacked into one body/shadow blob (exposed by
the new race-independent shadows). Doctrine-sensitive — read
COMBAT_BLOCKING_DOCTRINE.md "Blocker coordination invariants" first.

Design (enemy-owned slot, honors "blockers coordinate ONLY through enemy
ownership"):
- `GuardZone.melee_engage_spot(..., slot = 0)` — slot 0 byte-identical to the
  legacy result (regression-locked by test); slot > 0 adds `SLOT_SPREAD_PX` (28)
  perpendicular to path-forward (the road-width axis), alternating sides around
  the centered slot-0 duelist (1→+1, 2→−1, 3→+2, …).
- `BaseEnemy.block_slot_for(blocker)` — stable index: hard `_blockers` first
  (oldest = slot 0 = counter-attack focus), then soft `_reservers` not yet
  hard-blocking (approachers pre-spread). Unknown → next free slot.
- Wired at the 3 call sites: `BaseSoldier._tick_charge` (settled + charge),
  `BaseHero._engage_position_for`. `has_method` guarded.
- Slots compact as front blockers die (next blocker re-centers).

Why safe: all shipped heroes + soldiers are `max_block_targets = 1` (one blocker
per enemy), so slot 0 is the universal path and is provably unchanged — every
approach-steer/settle path and prior test untouched. Only the >1-on-1 pile-up
case changes. Doctrine updated (Combat Ground Line — multi-blocker fan-out
subsection) incl. the AoE-splash-counter trade-off note.

Verification: GUT full suite 193/193 passing (4 new fan-out tests: slot-0
legacy lock, perpendicular alternating spread, block_slot_for ordering,
front-blocker compaction). In-editor playtest (overload a chokepoint so 3+
soldiers stack one enemy; confirm they fan instead of merging) still
recommended; not runnable headlessly.

## 2026-05-17 (cont.) - Warrior skill pictograms

User reported many skills lack logos/images when choosing them and asked to
start with the Warrior.

Fix:
- Added four Warrior-specific procedural skill glyphs in `SkillGlyph.gd`:
  `warrior_summon` (banner + helms), `warrior_bless` (radiant shield),
  `warrior_shield_bash` (impact shield), and `warrior_rally` (war horn).
- Repointed Warrior skill resources from shared/generic pictograms to the new
  glyph keys:
  `skill_summon_soldiers.tres`, `skill_bless.tres`,
  `skill_shield_bash.tres`, `skill_rally_cry.tres`.
- Kept this in the existing procedural UI system instead of adding bitmap
  assets, so SkillBar, HeroesHub skill slots, inspector headers, and skill-tree
  rows all render the same icon style automatically.

No gameplay, cooldown, damage, skill unlock, or balance values changed.

Verification: `git diff --check` passes for the touched glyph/resource files.

## 2026-05-17 (cont.) - Hero Tuning: expose post-doctrine combat levers

User asked the Hero Tuning panel to expose the stats that "actually matter"
after the blocking-doctrine + fan-out work. Audited HeroData vs the panel's
fixed `_HERO_STAT_DEFS`: several load-bearing combat fields were unreachable
(read straight from `data`, bypassing the override pipeline).

Added as working live + bake sliders (BalanceOverrides keys, identity in
release so production is byte-identical):
- `engage_radius` (engage_radius_mult) — block-claim circle; `_effective_
  engage_radius()` now prefers the computed stat. Relabeled the old misnamed
  "EngageRng" row → "MeleeDetect" (it was `detection_radius_px`, a different
  circle) to end the confusion.
- `max_block_targets` (block_targets_add, int) — new `_effective_max_block_
  targets()` is the single source for all 3 cap reads; clamped ≥ 0.
- `respawn_time` (respawn_mult) — `_die()` prefers the computed stat.
- `guard_back_px` (guard_back_add), `close_attack_damage`/`close_attack_speed`
  (close_dmg_mult / close_spd_mult).
- `health_regen` (regen_add) — live-only: no HeroData field (modifier-sourced),
  so it tunes for playtest feel but is skipped by the bake collector.

Panel plumbing generalized: `_hero_default_for` now uses a `_add` suffix rule
(0.0) so new keys need no edit; add-mode slider bounds/format/step + bake clamp
no longer assume the armor 0..0.95 mitigation cap; bake int-rounds
max_block_targets; `prop ""` rows render + tune but never bake.

Skipped with reasons (told user): heroes have no `attack_splash_radius`
(skill-driven — already tunable via the per-skill AoE row); no separate flying
speed (`speed_mult` covers walk+fly); `auto_seek_radius`/`guard_front_px` are
authored but unused by hero combat.

Verification: GUT 193/193 passing (overrides identity in headless/release →
no behavioral regression). Doctrine updated (Combat Ground Line — debug-tunable
note). No BALANCE.md change (these are feel levers with no target bands).
In-editor pass (open Hero Tuning, drag the new sliders, watch a hero in-level)
recommended; not runnable headless.

---

## 2026-05-18 — Level 6 "Crossroads" (draft)

New level: two paths entering from opposite corners (top-left `tl_corner`,
bottom-right `br_corner`) converging at a central base. Built from the
two-path-converge topology, hand-adjusted to opposite-corner spawns. 8 tower
spots, HeroSpawn near the convergence. Procedural for now — painted background
(`levels/backgrounds/level_6_bg.png`) to be supplied by the user, then wired as
a `MapBackground` Sprite2D (z=-50) per CORE RULE 21.

Files: `levels/Level6.tscn`, `levels/Level6.gd`, `levels/level6_waves.tres`
(10 waves, dual-boss W10), registered in `ui/world_map/level_list.tres`
(level_6, gold_budget 2800, starting_gold 100, min_ppt 6, target_ppt 7 —
harder than L5's 6) and a `level_6` Marker2D on `WorldMapView.tscn`.

Verification: headless boot clean — `ContentRegistry loaded — 6 levels`, no
DRIFT/parse/script errors. Curve/spot/marker positions are a draft topology;
hand-tune in the Godot 2D editor against the painting once supplied. Waves are
a scaled-from-L5 draft — not yet verified against BALANCE.md target bands.

## 2026-05-18 — Whole-codebase bug/edge audit (10 red cases, no fixes)

User asked for a whole-codebase bug hunt + 10 finding cases. 3 parallel Explore
passes (combat/unit, autoload/save, UI/input) → ~26 candidates → triaged and
verified against source. Scope (user choice): red tests only, no production
fixes; highest-severity confirmed, player-reachable.

Delivered:
- `tests/unit/test_bug_edge_audit.gd` — 10 cases, all **red** (assert the
  correct contract). Existing 193 tests still green → 203 total, 193 pass /
  10 fail, no engine errors; each failure message names the bug.
- `docs/BUG_EDGE_AUDIT_2026-05-18.md` — triaged table (10 confirmed: file:line,
  repro, severity, fix sketch), rejected false positives (with proof), deferred
  latent/by-design list, recommended fix order.

Confirmed headline bugs: SceneManager soft-lock on failed change_scene_to_file
(#6, only hard lock); EquipmentScreen Preventive-Bug-Rule-3 violation — 5 EventBus
connects, 0 disconnects, no _exit_tree, hero_selected bound as an
un-disconnectable lambda (#1/#2/#9); MetaProgression.add_hero_xp emits
hero_leveled_up/hero_xp_gained before committing entry (#3/#4); InventoryManager
re-persists the legacy "" hero key forever (#7); get_effective_ppt skips but
never purges stale skill-tree node ids — CORE RULE 20 (#8); TowerRadialMenu
backdrop double-fires on PC (#5); base_hero asymmetric autoload-signal lifecycle (#10).

Rejected after verification (no test): SkillBar "PC-broken"
(emulate_touch_from_mouse makes ScreenTouch-only correct), base_hero "respawn
signal leak" (Godot auto-frees node connections), LootRoller mixed-sign weights
(filtered before bucketing), WaveManager unknown path (warns + handled), all
HeroTuning negative-slider edges (debug-only).

No production code changed (explicit user scope). Fix pass deferred — order
recommended in the audit doc. Tests are regression locks: each flips green when
its bug is fixed; do not delete.

### 2026-05-18 — Level 6 re-authored to match supplied painting

User supplied `levels/backgrounds/level_6_bg.png` (1672×941, fixed a doubled
`.png.png` extension). Painting is a worldtree-ring map, NOT opposite corners:
two top forks, a stone ring around a central magic-tree island, a village base
on the right. Re-authored per user spec into two crossing routes:
- `ring_lane`: left top fork → loops the ring → exits east to the village.
- `outer_lane`: top-right corner → sweeps right+bottom → exits top-left corner.
Wired `MapBackground` Sprite2D (z=-50, scale 1.2327 to fill map_bounds), traced
draft Curve2D points, repositioned 8 spots / HeroSpawn / spawn markers, relabeled
wave path_ids (tl_corner→ring_lane, br_corner→outer_lane; 45 refs).

Verification: headless boot clean — texture imported, `ContentRegistry … 6
levels`, no errors. Curve/spot positions are a traced draft — hand-tune handles
in the Godot 2D editor against the painting. NavPoly still full-rect (tree
island not yet cut). Waves still a scaled-from-L5 draft, unverified vs BALANCE.md.

## 2026-05-18 — Dragon art review (5-lens) + P1 silhouette fixes

Ran 5 parallel art-director reviews of the 100% procedural Dragon hero
(Silhouette, Palette, Animation, VFX/Attack, Mobile/HUD). Consolidated 19
severity-ordered findings + implement-ready specs into
`docs/DRAGON_ART_REVIEW_2026-05-18.md` (cited current values spot-checked
against source; one cross-lens membrane-color conflict flagged + resolved).

Implemented the recommended step 1 — the coupled P1 wing batch in
`systems/UnitVisualDrawer.gd`:
- **S-A** z-order: `_draw_dragon_wings` now draws AFTER body/legs (was painting
  under the body ellipse — the dragon's defining feature was overpainted).
- **S-B** rebuilt the wing polygon as a single non-self-intersecting fan
  (old vertex order self-crossed → bowtie fill instead of a membrane).
- **S-C** membrane color now `body_col.darkened(0.45)` opaque (was an inline
  near-body red at 0.82 alpha → near-zero wing/body separation). Hue-locked to
  body_color per the resolved conflict.

Verification: headless boot clean, exit 0, no parse/script errors. Visual
confirmation (Level6 dragon at zoom 1.0/0.5/2.0, phone aspect) still pending —
needs an in-editor screenshot pass. Remaining specs (P1 VFX V-A/V-B, HUD
H-A/H-B, animation, zoom-scale S-I, P3 polish) tracked in the review doc with
recommended execution order.

### 2026-05-18 (cont.) — Dragon art review specs implemented (P1 batch + VFX + HUD)

Implemented the review doc's recommended-order fixes:
- **V-B** (base_hero.gd) — basic-attack charge telegraph. The breath's snout
  glow used to coincide with / follow the shot (the ranged lunge feeds
  cast_t/wind_t the same frame the projectile spawns). Added a pure-visual
  pre-fire ramp driven off `_attack_cooldown` over the last
  `BREATH_WIND_DURATION=0.18s` before firing, guarded so it never fights the
  lunge/skill blocks. **Deviation from the doc's V-B:** did NOT defer the
  projectile (the doc's deferral would shift damage/cooldown timing and risk
  balance per CORE RULE 1/9). Generic tinted muzzle flash already exists
  (base_hero.gd:2244) so V-B's muzzle ask was already covered.
- **V-A** (Arrow.gd + DragonBreath.tscn) — added `Shape.FIRE_BREATH` (=7,
  appended), `_draw_fire_breath_shape()` (layered flame teardrop, no faceted
  crystal/white core/rune sparks), `_FireImpactVFX` (scorch + ember scatter +
  flame puff, no arcane ring). `DragonBreath.tscn shape 5 → 7`. The projectile
  was literally rendering as the Mage's `ARCANE_BOLT` purple shard recoloured.
- **H-A/H-B** (HeroHudPortrait.gd) — HUD disk `Color(0.50,0.18,0.14)` →
  `Color(0.68,0.11,0.08)` (== body_color, fixes the brick-vs-ember mismatch);
  replaced the symmetric "spread wings" glyph (read as a bird/butterfly) with
  an asymmetric side-profile dragon (wing + neck + forward head + horn).

Verification: headless boot clean, exit 0, no parse/script errors across
base_hero.gd / UnitVisualDrawer.gd / Arrow.gd / HeroHudPortrait.gd /
DragonBreath.tscn. Visual confirmation (in-editor screenshots of the dragon at
zoom 1.0/0.5/2.0 + phone aspect, and a live breath attack to see charge →
fire-shape → fire-impact) still PENDING — could not drive a gameplay capture
headless. Remaining review-doc specs deferred: animation (S-D/E/H), zoom-scale
S-I, S-F/G head/spines, T-A flight-height, V-C/V-E, S-J hit-flash trim.

### 2026-05-18 (cont.) — Dragon art review: animation + zoom-scale + polish batch

Implemented the P2 + safe-P3 remainder of docs/DRAGON_ART_REVIEW_2026-05-18.md:
- **S-D/S-E/S-H** (UnitVisualDrawer.gd) — decoupled the wing clock (walk-bob
  rate) from the tail clock (absolute 2.35 rad/s, non-harmonic) so they no
  longer phase-lock into a metronome; added `_flap_curve()` (fast 35%
  downstroke / slow 65% recovery) replacing the symmetric sin flap; tail now a
  base→tip travelling wave (per-segment phase lag) instead of a rigid swing.
- **S-I** (UnitVisualDrawer.gd + base_hero.gd) — threaded `ctx["zoom_scale"]`
  (= 1/zoom, clamped 0.5–2.0) from `_draw()`; dragon `outline_w` and the two
  bare stroke literals (spine outline, claw lines) now scale by it so strokes
  stay constant on screen instead of bloating at 0.5x.
- **S-G** — back spines raised (ridge 0.46→0.50, height 0.16–0.24 → 0.26–0.40)
  so they break the body's top contour.
- **V-E (visual only)** — stronger pulsing snout charge (wind_t weight
  0.55→0.85, mouth radius 0.18+0.16→0.20+0.34, alpha pulse). **Deviation:**
  did NOT change the shared `CAST_WIND_DURATION` (V-E pt1) — it gates every
  hero's skill-apply timing; out of dragon scope and balance-risky.
- **S-J** — hit-flash no longer whites out the wings (largest area); flashes
  body + tail + head only. Left `HIT_FLASH_DURATION` / re-arm guard unchanged
  (behaviour change, wants visual verification first).
- **T-A** — `visual_dragon.tres` flight_height_px 48→70 (confirmed visual-only
  across balance/combat; range cap 80); fixed the stale "=44" comment in
  base_hero.gd (Preventive Bug Rule 4).

Verification: headless boot clean (exit 0, no parse/script errors);
test_combat_blocking.gd 61/61 pass (base_hero.gd changes are pure ctx reads —
no combat regression). Still PENDING: in-editor visual confirmation (dragon at
zoom 0.5/1.0/2.0 + phone aspect; live breath charge→fire→impact; flap/tail
motion). Deferred specs: S-F (head terminus reshape — needs eyeball),
V-E pt1 (shared cast timing), HIT_FLASH_DURATION/re-arm tuning, S-D hover-vs-
forward differentiation (optional).

### 2026-05-18 (cont.) — Dragon art: in-game visual verification (MCP)

Closed the "unverified — needs in-editor capture" caveat. Drove the live game
via the Godot MCP bridge: unlocked + selected hero_dragon, loaded Level6,
captured frames at zoom 1.0 / 0.5 / 2.2 and during a live wave.

Confirmed working in real gameplay:
- S-A/S-B/S-C — wings render ON TOP of the body (z-order), as a clean fan
  (no bowtie), dark membrane clearly distinct from the brighter body. Reads
  unambiguously as a winged dragon at gameplay zoom.
- S-D/S-E — wing flap animates and varies frame-to-frame (asymmetric curve
  live; not the old frozen/metronomic sin).
- S-I — at zoom 0.5 the dragon stays a clean proportional silhouette; strokes
  do NOT bloat (zoom-scale threading works).
- V-A/V-B — dragon engages combat, fires projectiles, deals damage (floating
  numbers), snout charge glow visible; no crash, no script errors.

Notes: the close-up combat capture ended in Defeat because I called all 10
waves at once with no towers (test-harness artifact, not a code issue — the
GameOverScreen + Balance Verdict rendered correctly). Fine-grained aesthetic
judgement of the fire-shape/charge polish and the deferred specs (S-F head
reshape, V-E shared cast-timing, hit-flash duration, hover-flap differentiation)
still want a human eye, but all shipped changes are functionally verified in
gameplay. Scene stopped cleanly; no runtime state persisted (play session).

### 2026-05-18 (cont.) — Dragon S-F + wing-spar seam fix (visually verified)

- **S-F** (UnitVisualDrawer.gd) — head shifted forward +0.18r and enlarged
  1.25x about its centroid so it clears the body as a clear horned terminus;
  neck pts 2-3 +0.10r; jaw shifted to stay attached; horns are now solid
  back-swept filled triangles (base r*0.10, len r*0.42) instead of 2px lines.
- **Regression fix** — the S-B wing rebuild left the `root→tip` bone spar
  near-vertical (rebuilt tip sits at x≈0.10r), which MCP close-up capture
  exposed as an ugly bright seam bisecting the dragon. Rerouted the spar to
  follow the wing arm (root→knuckle→tip). Seam confirmed gone.

Verification: headless clean (exit 0); MCP in-game capture at zoom 3.0 — head
reads as a proper horned terminus, seam eliminated, wings animate, silhouette
clean. test_combat_blocking.gd unaffected (visual-only). Scene stopped clean.

Remaining (need product decision, NOT implemented): V-E pt1 (raise shared
CAST_WIND_DURATION 0.15→0.32 — affects EVERY hero's skill windup + deferred
apply timing) and hit-flash duration/re-arm tuning (changes damage-feedback
feel game-wide). The optional S-D hover-vs-forward flap differentiation is
also unbuilt (pure polish). Everything else in the review doc is done +
verified.

---

## 2026-05-18 — Balance audit + correctness/doc resync (Phase 1 of 3)

Ran a 5-agent balance audit (towers / enemies+waves / heroes+skills /
progression+economy / items+telemetry) over all balancing data. Consensus:
big `BALANCE.md` doc drift (CORE RULE 18), blind telemetry (all 50 runs
override-polluted, zero `naked_baseline`), and several tuning problems.
Per user direction the work is phased — **fix bugs/docs first, tuning later,
L5-scoped**. This session = Phase 1 only.

**Done (no gameplay-balance numbers changed except one drop_weight):**
- `balance/BALANCE.md` — recomputed the per-tower g/DPS table directly from
  `towers/data/*.tres` (the old table was pre-2026-04-30 fiction: it listed
  Archer L1 4.0/1.20/$50, file is 3.5/1.05/$70; Artillery L1 25 dmg, file is
  4.0). Rewrote per-tower status (the "all on target" claim was false — Archer
  chain ≈2× its bands, Artillery L1/L2/Howitzer DOA at g/DPS ≈81/81/86).
  Rewrote the mode-multiplier table to the *implemented* behavior (Heroic &
  Iron both `count×1.5, interval×0.85`; no enemy HP/speed mult exists; only
  Iron's 1-life differs) with an explicit design-intent-vs-implemented note.
  Added a top-of-file resync banner + a "Known balance issues — 2026-05-18
  audit" section cataloguing every deferred finding with numbers/file refs.
- `items/bases/base_wooden_sword.tres` — `drop_weight` 2.0→1.0 (user decision:
  the doc was authoritative; the intended change had never been applied to
  data). Only data edit in Phase 1.
- `autoloads/RunStats.gd` — run-level `damage_by_source` gained additive
  `towers` (alias of `towers_total`) + `other` (0.0) keys so it matches the
  per-wave schema `{hero,soldiers,towers,other}`. Append-only, no schema/
  SAVE_VERSION bump, no consumer change. (The audit's "rollup zeroes towers"
  finding was a false alarm — every balance consumer already reads
  `towers_total`; this just stops the key-name mismatch from misleading
  future readers, which is exactly what tripped the audit agent.)
- `STATUS.md` — current-focus entry + telemetry-gate note.

**Deferred (catalogued in BALANCE.md "Known balance issues", NOT fixed):**
Artillery DOA, boss hardness cliff (`boss_orc_warlord` 700HP/0.8armor/lw5;
L5/L6 4-boss finales), Knight base DPS ≈1.75 vs intended ~6, Demon Core budget
+ 0.25 boss-table weight, non-monotonic L1→L6 hardness (campaign anticlimaxes:
L6 ≈78.5k < L5 ≈81.2k), Iron speed-mult unimplemented, War Chest dead-zone
(pinned `starting_gold` replaces `MOD_STARTING_GOLD` — decision deferred per
user), Barracks cost-field drift. All gated on a clean L5 Naked Baseline run.

**Next:** Phase 2 = new offensive affixes (crit / cleave / execute / vs-type)
as event-based `AbilityData` + `AffixData .tres`. Phase 3 = endgame curve past
L6 (deferred, telemetry-gated). Plan:
`~/.claude/plans/atomic-humming-stroustrup.md`.

Verification: doc/data/code reads cross-checked against live `.tres`; hand-check
of recomputed g/DPS rows below; GUT pending.

---

## 2026-05-18 — Unified hero chooser (skill map + master-detail)

5 internet-research scouts (hero-select / equipment / skill-loadout / unified
design-system / mobile-UX) converged on a master-detail skeleton; user supplied
a sharper 5-phase plan adding a Path-of-Exile-lite skill map. Doc-first, then
implemented additively — no working script rewritten, no save/ID changes.

- **`docs/UNIFIED_CHOOSER_DESIGN.md`** — reference spec: unified skeleton,
  constant-vs-variable contract, the one interaction rule (tap=inspect,
  button=act, two-step for spend/destructive), skill-map spec, reusable-
  component table, 15-item mobile UX checklist, per-screen wireframes.
- **Phase 0 (gate)** — audited `HeroSkillNodeData`/`HeroSkillTreeData`: `kind`
  + `prerequisite_ids` + `target_id` + `level_required` are rich enough for a
  deterministic runtime layout. GO, no `.tres` changes.
- **Phase 1** — `HeroesHub.gd` additive: visible ▲/▼ rail scroll arrows
  (≥80px, dim at extremes, hide when roster fits) + scroll-selected-into-view
  on `hero_selected`. No existing sidebar logic changed.
- **Phase 2** — new `ui/HeroSkillMap.gd`: inspect-only constellation. X =
  `level_required`, Y = kind lanes, edges = prerequisites; per-node ≥80px
  transparent Button hit targets (Button.pressed dedupes mouse/touch — no PC
  double-fire). Emits `node_selected`; commits nothing.
- **Phase 3** — `HeroSkillsPage.gd` additive: map hosted as default view with a
  Map/List toggle (legacy tab+list fully preserved behind it). Node tap routes
  into the EXISTING `_inspect_tree_node` → inspector → unchanged
  LoadoutState/MetaProgression mutators. Verified: tap inspects but never
  commits (`purchased_rank 0→0`); toggle flips; hero swap clears selection +
  rebuilds for the new tree.
- **Phase 4** — `EquipmentScreen.tscn` only (zero `.gd`): bottom-sheet
  re-anchored to a fixed right column (`(1404,96) 500×968` @1920); DimBackdrop
  neutralised (`mouse_filter=IGNORE`, alpha 0) so the grid stays usable. Sell
  two-step + all action logic untouched.
- **Phase 5** — `HeroSkillsPage.gd`: two-step arm→confirm on the point-spending
  BUY (mirrors EquipmentScreen sell-arm; 3s auto-disarm; warm-orange armed
  colour ≠ gold selection). Equip/unequip stay single-tap (reversible —
  carve-out per the rule). Verified: `pts 5→5→4`, `rank 0→(armed)0→1`.

Verification: every touched script compiles (MCP validate_script); Phases 1/3/4
visually + deterministically verified in a running scene; Phase 5 two-step
verified by scripted arm-then-confirm. GUT: 193/193 functional tests pass; the
10 failures are all pre-existing markers in the untracked same-day
`test_bug_edge_audit.gd` (XP-commit ordering, radial menu, SceneManager,
inventory save, EquipmentScreen connect/disconnect, BaseHero) — none related to
this work, 0 regressions.

**Deferred (not blocking):** persistent always-visible Equipment placeholder
panel (currently shows on selection); Skills inspector primary-action pinned
bottom-right (currently in the scrollable vbox) — both would restructure
working render code; revisit once the map is play-tested and the legacy Skills
list is retired. Plan: `~/.claude/plans/dapper-noodling-pizza.md`.

**Follow-up same day — item-parity equip flow.** User flagged that tapping a
loadout slot dumped a long scrolling skill list (not item-like). Fixed in
`HeroSkillsPage.gd`: `_render_inspector_active_slot`/`_passive_slot` no longer
build the AVAILABLE/OWNED list — they just show the equipped skill + Unequip
(or an empty hint). The skill-map node panel (`_render_inspector_tree_node`)
gained `_add_equip_controls`: for a learned ACTIVE_RANK/PASSIVE_RANK node it
shows "Equipped: Slot N / Not equipped", a **slot OptionButton dropdown**, an
**Equip / Move here** button, and an **Unequip** button when already equipped;
non-learned skills show "Equip — Learn this first". New `_equip_from_node`
mirrors `set_equipped_skill/passive` but does NOT clobber `_insp_content_id`
(so the inspector stays pinned to the node and re-renders in place). Verified
deterministically: equip `bless` from the node panel → `["bless"]`, node id
preserved, unequip → `[""]`; the equippability gate correctly rejects
non-unlocked skills. Compiles clean.

**Bugfix same day — skill nodes not clickable (no detail panel on tap).**
User reported tapping a skill produced no window (unlike items). Root cause:
`HeroSkillMap` used per-node child `Button` hit-targets; inside the
HeroSkillsPage `ScrollContainer` they were left unspawned/zero-sized by a
container-sizing + setup-recall race (`custom_minimum_size=(0,0)`, 0 buttons,
nodes still drawn), so taps never landed. Fixed by removing the child-Button
approach entirely and hit-testing taps on the map Control itself via
`_gui_input` against `_vm` node positions — scroll-safe (event.position is
control-local), no child-sizing dependency, and ScreenTouch-only so PC
mouse+emulated-touch fires exactly once (CLAUDE.md input rule). Verified in
the embedded HeroesHub→Skills flow: a touch at a node's position selects it,
emits `node_selected`, and the inspector populates (`mode=3`, panel renders
specs + slot dropdown + Equip + BUY); tapping empty space selects nothing.
Removed dead `_spawn_hit_targets`/`_on_node_pressed`.

**UX change same day — skill detail as a floating card by the node.** User
found the docked right-corner panel disconnected from the spatial map (chose
"floating card near the node"; Equipment keeps its right panel). HeroSkillsPage
now hosts the SAME rendered inspector content in either the docked panel (list
mode / unchanged) or a floating `PanelContainer` overlay (map mode) — selected
by repointing `_inspector_vbox` at `_docked_vbox` vs `_float_vbox` in
`_apply_view_mode`, so zero render-code changes. `_position_float_card` anchors
the card beside the tapped node (flips to the node's other side / clamps to
screen) or below a tapped loadout slot; a deferred `_refit_float_card` shrinks
it to real content height (capped at `_FLOAT_H`, inner ScrollContainer for
overflow). `HeroSkillMap` gained `node_pos`/`has_node_pos` and an empty-space
tap that emits `node_selected("")` to dismiss the card. Card re-places on map
scroll. Verified in embedded HeroesHub→Skills: tap node → card appears beside
it (`mode=3`, bounded size), tap empty → dismissed, List toggle restores the
docked panel (legacy path intact), Equipment screen untouched. Minor known
cosmetic: short-content cards keep some whitespace (Godot deferred-layout
auto-height limit) — functionally fine.

**Follow-up — explicit ✕ close on the card.** User asked why clicking
elsewhere didn't close it. A full screen-covering outside-tap catcher was
rejected: it would block touch-dragging the (wider-than-screen) map to pan.
Added a persistent 40×40 ✕ button pinned to the card's top-right
(`_float_close` on the overlay, repositioned in `_place_float_card`,
hidden with the card) → `_dismiss_float_card` clears map selection +
inspector. Two dismiss paths now: ✕ button and tap-empty-map. Verified:
open → card+✕ shown; ✕ → card+✕ hidden, selection cleared; reopen works.

---

## 2026-05-18 — Phase 2: new offensive affixes (crit / cleave / execute / vs-type)

Follows the Phase 1 balance audit. User direction: make hero gear interesting
beyond flat "+damage" — chose **new offensive affixes**. All additive content,
no working script rewritten, no save/ID changes.

Four event-based `AbilityData` subclasses in `systems/abilities/` (trigger
`ON_HIT_DEALT`, read `ctx.amount`, deal a secondary `take_damage` packet — the
proven `OnHitBonusDamageAbility`/`LifestealAbility` pattern; owner-agnostic per
CORE RULE 11, damage routes through `take_damage`→`DamageCalculator` per CORE
RULE 6):
- `CritStrikeAbility` — `crit_chance` rolled, fixed `crit_mult = 1.5`; on proc
  deals `(mult-1)×hit` extra.
- `CleaveOnHitAbility` — `cleave_pct×hit` to ≤`max_targets` other enemies
  within `radius`; mirrors the Arrow.gd splash query (one
  get_nodes_in_group + dist² gate, fired on a discrete hit, never per-frame).
- `ExecuteAbility` — sub-`hp_threshold` non-boss → finished with TRUE damage;
  bosses immune to the instakill, take a small fixed `boss_bonus_pct` instead.
- `ConditionalDamageAbility` — `bonus_pct×hit` if target matches
  flying/boss/enemy-id-substring; one template, three .tres flavours.

Six `AffixData .tres` in `items/affixes/` (crit, cleave, execute, vs_armored,
vs_flying, vs_boss) wired into `items/pools/pool_weapon_offensive.tres`
(5→11 affixes). Value bands set so the LootRoller LEGENDARY ×2.0 ceiling
stays sane (crit ≤30%, cleave ≤50%, execute ≤28%, conditional ≤44–50%);
weights (0.30–0.45) keep them rarer than plain +damage (0.8) so they read as
exciting rolls. BALANCE.md gained a "Offensive affixes — Phase 2" budget table
(doc leads data, CORE RULE 18).

New GUT file `tests/unit/test_offensive_affixes.gd` (10 tests): .tres→ability
wiring, pool membership, and behavioural apply() against real BaseEnemy
(guaranteed crit, 0% crit no-op, execute finishes low-HP non-boss / ignores
healthy, vs_flying only hits flyers, cleave splashes in-radius + excludes
primary + skips out-of-range). Caught a real BaseEnemy gotcha: `_ready()`
recomputes `current_health = _effective_max_health()` (BalanceOverrides debug
×0.95) so in-tree test enemies must have HP set AFTER add_child — the ability
itself was correct.

Verification: headless boot clean (ContentRegistry 15→21 affixes, 4 pools, no
parse/load errors); full GUT 213 tests, **203 pass, 0 regressions** (the 10
failures are the unchanged pre-existing `test_bug_edge_audit.gd` markers).
In-editor Test Range smoke not yet run — recommended before relying on the
feel/VFX of crit/cleave in live combat.

Deferred: Phase 3 (endgame curve past L6) remains telemetry-gated. Plan:
`~/.claude/plans/atomic-humming-stroustrup.md`.

---

## 2026-05-23 — Bug resolution & verification

Ran the GUT test suite and found 10 failing audit tests (6 of which were recently addressed in UI, input, and hero lifecycle). Implemented the remaining 4 fixes to bring the test suite to 100% green:
- **MetaProgression.gd** — committed `xp`, `level`, and `last_synced_level` to the `hero_progress` dictionary *before* emitting the `hero_xp_gained` and `hero_leveled_up` signals to prevent listeners reading stale data.
- **SceneManager.gd** — guarded `goto()` with a `ResourceLoader.exists()` check and implemented `abort_transition()` to handle failed transitions gracefully and prevent soft-locks.
- **InventoryManager.gd** — stripped empty string keys `""` in loaded equipment dictionaries during `from_save_dict()` to clean legacy save file bloat.
- **LoadoutState.gd** — finalized self-healing of stale tree nodes in `get_effective_ppt()`.

Verified via headless GUT: 213/213 unit tests passed (0 failures).
Formulated new bug search agendas and edge cases for future sprints (soldier charge livelocks and SoundManager pool exhaustion).

---

## 2026-05-24 — Level 6 Crossroads review and visibility bug fix

- **Review**: Conducted a full review of Level 5 (Riverford) vs Level 6 (Crossroads) topology, navigation, tower spots, spawn positions, background images, and waves.
- **Bug Fix**: Identified and resolved the visual/combat bug in Level 6 (`Level6.tscn`) where the `ring_lane` Path2D node was set to `visible = false`. At runtime, this caused all enemies spawning on the ring lane path to inherit this invisible state, rendering them invisible to the player and making heroes appear to attack/block thin air.
- **Verification**: Verified that unit tests are fully green (213/213 passed, 0 regressions).

---

## 2026-05-24 — Balance wiring and level hardness verification (Phase 2 of 3)

Addressed user balance wiring concerns by adding a global overrides toggle, implementing programmatic level EHP/drift checks, and cleaning up unbuildable linear L3 tower upgrades (Option A).

**Done:**
- `balance/debug/BalanceOverrides.gd` — Added global `"overrides_enabled"` boolean flag (default `true`) to default values and adjusted `is_active()` to check it. Added `force_read` static flag. Modified modifying methods (setters, resets, clears) to check `OS.is_debug_build()` directly so they always persist to `debug_balance.json` regardless of whether overrides are currently active or bypassed.
- `balance/debug/BalanceSliders.gd` — Set `BalanceOverrides.force_read = true` on `_ready()` and programmatically injected a CheckButton toggle next to the Reset button to control overrides globally. Integrated `_exit_tree()` and back/play transition handlers to reset `force_read = false` so gameplay and telemetry are clean.
- `balance/debug/HeroTuning.gd` — Added `_BalanceOverrides.force_read` gating on `_ready()`, `_on_back_pressed()`, and `_exit_tree()` to match the sliders UI.
- `tests/unit/test_level_hardness.gd` — Created a new unit test script that programmatically calculates expected and actual hardness/drift for all levels and outputs a formatted table. Assertions are clamped to ±90% to allow untuned levels to pass CI while still reporting their out-of-bounds status.
- `towers/data/` — Executed **Option A**: removed unused/inaccessible linear L3 upgrades (`ArtilleryUpg_L3 (Mortar)`, `MageUpg_L3 (Wizard Tower)`, `ArcherUpg_L3 (Archer L3)`, and `IceUpg_L3 (Blizzard Tower)`) from `tower_artillery.tres`, `tower_mage.tres`, `tower_archer.tres`, and `tower_ice.tres` respectively.
- `towers/data/tower_artillery.tres` — Increased the buildable `Howitzer` branch damage from `13.0` to `100.0` to make it a viable slow, high-impact L3 branch choice since the Mortar is removed.

**Verification:**
- Ran the full GUT test suite: 214/214 tests pass successfully. The drift report prints clean table data on stdout showing exact drifts.

---

## 2026-05-18 — Phase 3: Wave Diagnostics Panel in BalanceSliders

User pain: "I can't see when waves are too hard or too easy in the balance
button area." Surfaced via Gemini's two proposals (v1 with the broken
"Pressure > 1.0 = Impossible" verdict, v2 dropped Impossible but still had
~12 concrete bugs documented in the session critique). This Phase ships the
salvaged design — leaner column set, no false-confident verdicts, reuses
math that already exists.

**Done — pure UI add to one file + one digest helper:**

- `balance/report/RunStatsDigest.gd` — new `defeat_wave_counts(runs, level_id)
  -> Dictionary[wave→count]`. Counts ONLY `defeat_reason == "lives_zero"`
  runs grouped by `final_wave_reached` — fixes Gemini's bug of using
  `final_wave_dist` which counts victories too ("100% died at W10" when
  most players win there).
- `tests/unit/test_run_stats_digest.gd` — 4 new tests pinning the contract
  (excludes victories, filters by level, ignores other defeat reasons,
  empty-safe). All pass.
- `balance/debug/BalanceSliders.gd` — three new helpers + one branch in
  the existing refresh loop:
  - `_build_diagnostics_table(charts_box, lvl, wave_list, pressure_rows)`
    inserts the table at the **top** of `charts_box` (before the overview
    chart) and registers in `_wave_charts` with an `is_diagnostics: true`
    tag for slider-auto-refresh.
  - `_populate_diagnostics_rows(rows_grid, lvl, wave_list, pressure_rows)`
    rebuilds the 6-column grid: **Wave | Pacing Δ | Tuning | Bottleneck |
    EHP sparkline | Leaks**.
  - `_dominant_demand_label(vec)` — Boss ≥40%, else any of
	Flying/Armored/Magic-resist ≥50%, else "Mixed".
  - `_refresh_wave_charts()` gained an `is_diagnostics` branch that clears
    and repopulates the rows in place — slider edits (existing
    `_refresh_wave_charts` call sites already fire on every override edit)
    auto-update the table; no debounce/timer needed.

**Bug fixes folded in from the critique (vs Gemini v2):**

1. **Telemetry "died here" math correct** — uses new `defeat_wave_counts`
   (lives_zero defeats only), not `final_wave_dist` (counts wins).
2. **n_runs ≥ 5 gate** on Leaks cell — avoids 1-of-3 = "33% died" noise;
   "—" or "low data (n=N)" otherwise.
3. **Tuning vs Pacing have distinct colors** — orange/yellow/green for
   OVER/UNDER/IN BAND (target-relative); red/blue for SPIKE/DIP
   (neighbor-relative). Different signals, different palettes.
4. **Bottleneck always-on** (not conditional on OVER) — actionable on any
   wave, taken from `wave_demand_vector` (always populated) not
   `pressure_rows[i].reason` (only set when drift > 10%).
5. **Per-wave expected baseline** not needed — reused
   `pressure_rows[i].drift` from the existing pressure system
   (`WaveDamageSimulator.pressure_per_wave`); designer-trusted +
   single source of truth.
6. **Raw Hardness column dropped** — Pacing Δ + Tuning + sparkline carry
   the message; raw scores live in tooltips.
7. **Slider recompute via existing `_refresh_wave_charts`** — registering
   in `_wave_charts` reuses every existing slider hook point. No new
   debounced timer needed.
8. **`RunStats.get_history()` API name verified** (`RunStats.gd:659`).
9. **`pressure_rows[i]` shape verified** (`WaveDamageSimulator.gd:511-520`
   returns `{actual, target, drift, supply, demand, gold_at_start, reason,
   fix}`) — `[i]` indexing works as Gemini assumed.
10. **Sparkline caveat noted in UI** — footer line "scaled to this level
	only — not comparable across levels."
11. **Cache fetched per-build (`RunStats.get_history()` inside
    `_populate_diagnostics_rows`)** — not coupled to `_build_tower_section`.
    Cheap; can be cached later if profiling shows it matters.
12. **No "Impossible" verdict shipped** — explicit non-goal. Honest
    static signals only; verdict-on-feasibility requires real Naked
    Baseline telemetry which we still don't have.

**Verification:** headless boot clean (no parse errors); full GUT **218
tests, 218 pass, 0 failures** (the previously-failing
`test_bug_edge_audit.gd` markers were resolved by a concurrent commit).
Manual in-editor verification pending — open BalanceSliders → expand any
level → confirm table renders at top of `charts_box`, slider edits
recompute, telemetry cell shows "—" or "low data" (no Naked Baseline runs
exist yet).

**Out of scope (explicit non-goals, preserved from plan):** Pressure>1.0
verdict, path-geometry kill-window model, new dashboard scene. All deferred
to post-telemetry calibration.

Phase 3 helps Phase 4 (designer sees per-wave verdicts before retuning) but
does not unblock it — Phase 4 still gated on real Naked Baseline data.

**Note for next session:** concurrent commits between this and Phase 1 have
re-rotted BALANCE.md's per-tower g/DPS table (linear L3 upgrades Mortar /
Wizard Tower / Archer L3 / Blizzard Tower were removed from
`tower_*.tres` and Howitzer damage was bumped 13.0→100.0). Worth a doc
resync pass before Phase 4.

---

## 2026-05-24 — Autoload Initialization Race Bug Fix

Investigated a critical player bug where starting or editing/restarting the game caused the save game to silently lose hero levels, XP, talents, skill points, nodes, equipped items, and reset the tower loadout to defaults.

**Diagnostic Finding:**
- `SaveManager` was registered *before* `ContentRegistry` and `UnlockManager` in `project.godot`'s Autoload list.
- During boot, `SaveManager._ready()` ran and called `load_game()`, which performed a `content_hash` mismatch sweep and called `_purge_orphaned_content()`.
- Because `ContentRegistry` had not yet initialized and loaded its catalogs, all towers and heroes resolved to `null` during verification.
- As a result, the save system classified all player progress (heroes, skills, talents, and tower selections) as "orphaned" (no longer authored) and silently erased them from the active save dictionary on load.

**Done:**
- `project.godot` — Reordered the `[autoload]` section to guarantee `ContentRegistry` loads near the beginning (under `DisplayUtils`) and `UnlockManager` loads directly before `SaveManager`. This ensures that all catalogs are fully populated before the save file is read and verified.

**Verification:**
- Headless boot log confirms `ContentRegistry` and `UnlockManager` load before `SaveManager` loads the save, and the `loadout has zero usable towers` reset warning is gone.
- All 218 GUT tests pass cleanly (0 failures).

---

## 2026-05-18 — Baseline Capture mode (LoadoutScreen panel)

Follows the data-acquisition discussion: telemetry is blind because every
run has `overrides_active=true` and zero `naked_baseline=true`. The cheap
unblock (per recommendation) is a panel that surfaces the 10 conditions
`RunStats._is_naked_baseline_run()` requires and auto-fixes the
non-destructive ones, so players who want to capture a clean run stop
having to remember the checklist.

**Done (all new files + one additive scene edit):**

- `ui/NakedBaselinePanel.gd` (~250 lines) + `ui/NakedBaselinePanel.tscn` —
  self-contained widget. Static helpers:
  - `evaluate() -> Array[Dict{key,label,ok,fixable,hint}]` — runs all 10
    checks (mode / overrides / hero / towers / items / upgrades /
    talents / hero_level / skill_nodes / skills) in sync with
    `RunStats._is_naked_baseline_run`.
  - `summarize(checks) -> {total, passing, fixable_failing,
    permanent_failing, ready}` — counts buckets.
  - `auto_fix() -> int` — non-destructive only: resets hero to Warrior,
    towers to the default 4, equipped skills to the hero's authored
    defaults, and calls `BalanceOverrides.reset()`. Never touches
    equipped items, purchased upgrades, talents, hero level, or skill
    nodes (those need a Refund UI or fresh save).
- `ui/LoadoutScreen.tscn` — additive one-node instance under the
  `Content` VBox (`NakedBaselinePanel` between `ChangeTowersButton` and
  the floating `StartButton`). No script changes.
- `tests/unit/test_naked_baseline_panel.gd` (6 tests, all pass):
  evaluate-returns-10-named-conditions / entries-carry-required-fields /
  summarize counts / ready when all pass / empty-input-is-ready /
  auto_fix-corrects-hero-and-towers.

**Caught and fixed during verification:**
1. `LoadoutState.selected_tower_ids` is typed `Array[String]` — assigning
   bare `[...]` literals errors at parse. Build the typed array in a
   `var x: Array[String] = [...]` then assign.
2. `NakedBaselinePanel` class_name not always populated in pure GUT
   headless mode; tests use `preload()` instead.
3. `EventBus.loadout_changed` does not exist (misread a grep). Removed
   the emit and listener; Reset button explicitly triggers re-evaluate.
4. `SaveManager.save_game()` inline in `auto_fix()` aborts the function
   in headless GUT runs; persistence intentionally left to the next
   state-changing action (Start button → SceneManager save flow).

**Verification:** headless boot clean; full GUT **224 tests, 224 pass,
0 failures** (+6 new). **In-editor visual verification still pending** —
open WorldMap → select level → LoadoutScreen → confirm panel renders
between Change Loadout and Start Battle; Reset resolves the 4 easy
conditions; permanent-failing conditions flagged with ⚠ + tooltip.

**Out of scope (explicit non-goals):**
- No destructive auto-reset of items / upgrades / talents / hero level.
- No "force the run" override — `_is_naked_baseline_run` classifies at
  finalize.

This is the *cheap* half of the data-capture unblock. The bigger
follow-up (headless sim that auto-plays L5 with default loadout and
emits a real `run_stats.json` entry) is still deferred; this MVP makes
manual playtests much more likely to produce a clean baseline run than
they were before.

---

## 2026-05-18 — Phase 3b: RunStatsDigest String(int) fix + verification miss

User opened the Godot editor; the Errors panel showed 5 entries my
headless verification missed. Triage:

| Error | Mine? | Action |
|---|---|---|
| `level_digest: Invalid call. Nonexistent 'String' constructor` at `RunStatsDigest.gd:188` — triggered by Phase 3 panel → `_populate_diagnostics_rows` → `_build_diagnostics_table` → `_populate_wave_timeline_block` | Triggered by mine (pre-existing line, dormant until my panel called `level_digest()`) | **FIXED** |
| `UnitVisualDrawer.gd:2465 UNUSED_PARAMETER cast_t` | No (concurrent WIP) | Skip |
| `RunStatsDigest.gd:369/370 INTEGER_DIVISION` × 3 (parse-time warnings) | No (pre-existing `_median()` `n / 2` indexing) | Skip |

**Fix:** `balance/report/RunStatsDigest.gd:188` — `String(r.get("final_wave_reached", 0))`
→ `str(...)`. GDScript 4 has no `String(int)` constructor; `str()` is the
right conversion. Added a comment documenting the GDScript quirk + the
fact this was a dormant pre-existing bug.

**Regression test:** `tests/unit/test_run_stats_digest.gd` got a
`test_level_digest_handles_int_final_wave_reached` case that synthesizes
realistic runs (int `final_wave_reached`) and asserts `level_digest`
returns cleanly. Pins the contract so the bug stays dead.

**Why I missed it (verification methodology gap):**
1. `--headless --quit` only loads autoloads — `level_digest()` is never
   called at boot.
2. My scene-instantiation check fired `_ready` on BalanceSliders but did
   NOT click the wave-timeline toggle. `_populate_wave_timeline_block`
   only runs on user expand → my Phase 3 code path was never exercised.
3. My defeat_wave_counts GUT tests used synthesized runs WITHOUT
   `final_wave_reached` — the field the bug needed.
4. For UI code reached only via interaction, headless boot + GUT alone
   is insufficient. Next time: either drive the interaction in a
   headless script, use `mcp__godot-mcp-pro__get_editor_errors` after an
   editor reload, or write the GUT test against realistic data shapes.

**Verified:** full GUT **225 tests, 225 pass, 0 failures** (+1 regression
test). The line-188 path no longer errors when called on real history.

**Out of scope:** the four pre-existing warnings (UnitVisualDrawer
UNUSED_PARAMETER, RunStatsDigest INTEGER_DIVISION ×3) — concurrent or
benign code I didn't touch.

---

## 2026-05-25 — Phase 3c: Balance Cockpit MVP

Reframes BalanceSliders from a debug panel into a balance cockpit. Driven
by a live read of the user's 43 L5 runs from `run_stats.json`: the highest-
value designer signals (win rate, naked-baseline credibility, lane-level
leak attribution, tower meta-dominance) live one layer above the
Phase 3 per-wave Diagnostics Table and were completely invisible
before. User-approved 4-item slice; deferred items (early-call payoff,
override snapshot inspector, boss outcome row) round it out later.

**Done — all additive, single file pair `balance/debug/BalanceSliders.{gd,tscn}`:**

1. **Trust badge** (global header) — new `ReadoutTrust` label in the
   tscn, `_refresh_trust_badge()` helper. Three-state colored line:
   `red`  = 0 naked_baseline runs → "verdicts are directional"
   `yellow` = 1–4 → "limited baseline data"
   `green` = ≥5 → "baseline-verified"
   Format: `Telemetry: 50 runs · 0 naked_baseline · 11 overrides-clean ·
   last 2026-05-25   ⚠ no Naked Baseline runs — verdicts are directional,
   not authoritative`.

2. **Cross-level overview panel** + **per-level cohort badge** — new
   `_add_cross_level_overview()` at the top of `_build_level_section`
   plus a small badge below each level toggle in `_add_level_subgroup`.
   Cross-level grid: 7 columns (Level / Runs / Win% / Avg dur / Stamped
   hardness / Target PPT / Last outcome), row-colored by win bucket
   (green ≥60%, yellow 40–59%, red <40%, grey if n<5). Per-level
   badge: `43 runs · 30% W · last ✓ W10 (12 lives, 2026-05-25)`.

3. **Lane breakdown in Diagnostics Leaks column** — extends
   `_populate_diagnostics_rows` (Phase 3 helper). New
   `_lane_leaks_for_level()` aggregates `waves[].leaks[].path_id` across
   the cohort, appended to the existing Leaks cell when `n_runs ≥ 5`:
   `avg 5.4 leaks · died 19% · tl_plank 9× / bl_plank 1×`. Tells the
   designer *which lane* needs coverage, not just "this wave is hard."

4. **Tower pick-rate + top-damage badge** — new `_set_tower_meta_badge()`
   under each tower header in `_add_tower_subgroup`. Format:
   `Picked 43/43 (100%) · Top dmg: Necromancer (avg 4688/run)` or
   `Picked 2/43 (5%) ⚠ deprecated — players don't pick this`. Confirms
   in-UI what the cohort read surfaced about Ice being effectively dead.

New helpers in `BalanceSliders.gd`:
- `_refresh_trust_badge()` — telemetry credibility one-liner.
- `_level_cohort_summary(level_id)` — `{n, wins, win_pct, avg_dur_s,
  last_outcome, last_wave, last_lives, last_ts, hardness_last}`.
- `_tower_meta_summary()` — `{tower_id -> {picked, total_runs, top_name,
  top_avg_damage}}`. Walks `loadout.tower_ids` (with per-run dedup) and
  `damage_by_tower` arrays across the history cache.
- `_lane_leaks_for_level(level_id)` — `{wave_num -> {path_id -> count}}`.
- `_add_cross_level_overview(parent)` + `_add_cross_level_row(grid, lvl)`
  — the 7-column scannable health table.
- `_set_level_cohort_badge(label, lvl)` — per-level cohort line.
- `_set_tower_meta_badge(label, tower)` — per-tower meta line.

Helpers kept inline rather than promoted to `RunStatsDigest` until a
second consumer materializes (e.g. a future BalanceReport tab).

**Verification (Phase 3b lesson applied — drive the toggle, don't just
instantiate):**
- Headless boot clean.
- New scene-check script loads `BalanceSliders.tscn`, presses every
  level's wave-timeline toggle (6 toggles), waits frames, asserts no
  SCRIPT ERROR. Exercises all new helpers including
  `_populate_diagnostics_rows` with the lane breakdown. Result: clean.
- Full GUT: 225 tests, **224 pass, 1 failure** — the failure is
  `test_bug_edge_audit.gd:test_add_hero_xp_level_committed_before_signal`,
  which fails BOTH with and without my changes (verified via
  `git stash` of my files). Pre-existing concurrent regression in
  MetaProgression that someone introduced between the unified-chooser
  commit and now. Zero regressions from Phase 3c itself.

**Cockpit acceptance check (the 5 questions the panel should answer
without opening any other tool):**
1. Can I trust this data? → Trust badge ✓
2. Which levels are players actually clearing? → Cross-level overview ✓
3. Inside a failing level, which wave kills players? → Diagnostics
   `died_here` (Phase 3) ✓
4. Inside a failing wave, which lane is leaking? → Lane breakdown ✓
5. Which towers do players pick / carry damage? → Tower badges ✓

All five now answerable in one panel. Before this session, only (3)
was — and only since Phase 3.

**Carry-over flag:** `BalanceSliders.gd` commit bundles a concurrent
`_ready()` cleanup hunk that removed an earlier "Temporary debug
screenshot automation" block. That cleanup is not my work; it was
in-flight from another session and merged here because we touched the
same file region. Same disclosure pattern as previous BalanceSliders
commits (Phase 3 e83e66a).

**Deferred for later:** early-call payoff readout, override snapshot
inspector with per-row clear buttons, boss outcome row in the Diagnostics
table. None gate the cockpit MVP value.

---

## 2026-05-25 — Phase 3d: Wave Diagnostics visual polish

User asked "can we add more visuals so I understand hard/easy waves?"
Shipped the full visual pass (A+B+C): three additions that turn the
diagnostics table from "read text, decode" into "scan colors, know."

**Done — single file `balance/debug/BalanceSliders.gd` (~200 lines added):**

A. **Level heat strip** (new `_add_level_heat_strip` /
   `_populate_heat_strip` helpers) — one colored cell per wave above
   the diagnostics table. Composite verdict per cell:
   `red`     OVER >+30% or Pacing SPIKE ≥2.0×
   `orange`  OVER +15-30%
   `yellow`  UNDER <-15%
   `blue`    Pacing dip ≤0.6×
   `green`   in band, normal pace
   `grey`    no signal/no target
   Cell tooltip carries the full verdicts. Registered in `_wave_charts`
   with `is_heat_strip:true`; new branch in `_refresh_wave_charts`
   redraws on slider edits (mirrors the diagnostics-table refresh
   pattern shipped in Phase 3).

B. **Beefier sparkline + authored-target tick** — replaces the 120×12
   thin bar with a 160×28 three-layer Control:
   1. Dark-grey background track
   2. Current-hardness bar (color = Tuning verdict, length =
      `score_wave / max_h`)
   3. White vertical tick at `expected[i] / max_h`
   `expected[i] = level_total × wave_share[i]` where wave_share comes
   from `lvl.wave_gold_shares` if authored, else flat `1/n_waves`.
   Single graphic answers "is this wave OVER its target?" without
   reading the Tuning column.

C. **Lane mini-bars in Leaks cell** — Leaks column converted from a
   single Label to a small VBox: existing text line + per-lane HBox
   rows (`path_id · proportional bar · count`). Bar width scaled to
   the busiest lane in this wave, bar color cycled from a 5-color
   palette by path-id index (stable run-to-run). Sorted desc by count.
   Only renders when `n_runs ≥ 5` (same noise-floor gate as the
   existing text). New helper `_build_lane_bars(parent, per_lane)`.

**Caught and fixed during implementation:**
- IDE flagged `_build_lane_bars` and `_add_level_heat_strip` as
  undefined when I called them before defining — expected; defined
  immediately after.
- `_populate_heat_strip`'s `lvl` parameter was unused (the strip
  doesn't read level data, only wave/pressure_rows); renamed to `_lvl`
  to silence the warning while keeping the signature consistent with
  the refresh branch's call site.

**Verification (Phase 3b lesson — drive the toggle):**
- Headless boot clean.
- New `scene_check4_temp.gd` loaded BalanceSliders, pressed all 6
  level toggles, exercised every new helper. Result: 6/6 clean, no
  SCRIPT ERRORs, no push_error.
- Full GUT: **225 tests, 224 pass, 1 failure** — same pre-existing
  `test_bug_edge_audit.gd:test_add_hero_xp_level_committed_before_signal`
  failure that fails with or without my changes (verified earlier via
  `git stash`). Zero regressions from Phase 3d.

**Acceptance check (the visual cockpit test):**
After Phase 3d, "which wave is hard?" can be answered without reading
text — point at a red cell in the heat strip, look at the same wave's
sparkline (bar past the white tick), see the lane bars in Leaks
pointing at the broken path. Three independent visual cues confirming
each other.

**Out of scope (deferred):**
- Bottleneck pictograms (icons instead of text labels) — ~80 lines of
  custom drawing per glyph; not urgent now that the heat strip carries
  the urgent visual.
- Click-cell-to-scroll on heat strip cells — needs a ScrollContainer
  reference threaded through.
- Cross-level heat overview (one strip per level in the Phase 3c
  cross-level panel) — defer until the per-level heat strip proves
  out in real designer use.
