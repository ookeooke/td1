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
