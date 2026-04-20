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
