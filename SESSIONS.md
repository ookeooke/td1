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
