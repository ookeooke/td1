# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fantasy Tower Defense (Kingdom Rush Style)
> Godot 4.6.2 | GDScript | Android + iOS + PC | Touch + Mouse

---

## Development Commands

```bash
godot --path . --editor          # Open in editor
godot --path .                   # Run the game directly
```

Entry point: `res://ui/MainMenu.tscn`. Design viewport: 1920x1080 (landscape). Stretch: `canvas_items` + `keep_height`. Renderer: GL Compatibility (mobile-first). No build system, linter, or test suite — validate by running in the Godot editor.

---

## CORE RULES

1. **Never modify working scripts.** Append or add new scripts only.
2. **All cross-system communication via EventBus signals only.** No direct node references between unrelated systems.
3. **One script = one responsibility.** Never combine movement, combat, and UI logic in one file.
4. **All stats live in .tres Resource files.** Never hardcode stats inside scripts.
5. **State changes only through a change_state() function.** Never set state variables directly.
6. **All damage through DamageCalculator.calculate_damage().** Never calculate damage inline.
7. **All IAP-locked content checked through UnlockManager before loading.** Never hardcode unlock states.
8. **All save/load through SaveManager only.** No other script touches the save file.
9. **Before changing anything working, explain why the change is needed.** Then wait for approval.
10. **New content is authored as data, not code.** Every new hero / soldier / enemy / skill / spell / ability / item is a `.tres` resource composed from existing base classes + AbilityData components. Only subclass when the variant needs genuinely new *structural* behavior (collision layer, multi-phase state machine, projectile vs. melee).
11. **One primitive for mechanics: AbilityData.** Every "verb on a unit" — passives, on-hit effects, auras, items, talents, endless modifiers, status effects — is an `AbilityData` Resource with a `Trigger` and an `apply(owner, ctx)` override. `AbilityHost` dispatcher is owner-agnostic.
12. **Stable content IDs.** Every Resource has a `*_id: String` field. IDs are keys in save files, unlock checks, leaderboard payloads. **Never rename an ID after first release.** Convention: `snake_case`, scoped by type (e.g. `hero_warrior`, `tower_archer`).
13. **Soldier rally positions are constrained to the navmesh; soldier movement is direct.** For soldier-spawning blocker buildings (barracks today; future siege camps, summoning towers, patrol posts), both the rally **flag** and every derived rally **slot** must be snapped to the navmesh via `NavigationServer2D.map_get_closest_point` — guaranteeing soldiers always stand on walkable terrain. Soldier movement between positions is always a direct straight line (`velocity = (target - pos).normalized() * speed`), on spawn and on flag moves alike. No `NavigationAgent2D` routing. The navmesh constrains **placement**, not **pathing**.
14. **Tower indicators read through accessors, never `tower.data.*` fields.** All UI that displays a tower's range, stats, sell value, or upgrade cost MUST go through the Tower Indicator Interface (see below). No `has_method` fallbacks to `.data.*`. No per-class branches (`if tower is TowerBarracks`). Each tower owns its own stats-line formatting via `get_stats_line()` so the stats card stays tower-agnostic. Carve-outs: static display strings like `tower.data.tower_name` (never change on upgrade); build-ring UI operating on `TowerData` resources before any tower instance exists. *Why:* reading `tower.data.attack_range` silently shows the L1 base stat on an upgraded tower — a bug class the interface prevents. Adding a new tower type = implement the interface, zero UI changes.

---

## Tower Indicator Interface

Every tower class (BaseTower, TowerBarracks, and any future sibling) MUST implement this interface. UI code (RangePreview, TowerStatsCard, TowerRadialMenu, TowerPlacer) calls these methods uniformly — it never branches on tower type.

| Accessor | Returns | `0` / empty means |
|---|---|---|
| `get_preview_range() -> float` | Current ring radius (attack for combat towers, rally for barracks) | No ring (tower has no reach) |
| `get_upgrade_range() -> float` | Next-upgrade ring radius | No ghost ring (maxed, at branch, or unchanged) |
| `get_effective_damage() -> float` | Current effective damage | N/A (e.g. barracks) |
| `get_effective_attack_speed() -> float` | Current shots/sec | N/A |
| `get_sell_value() -> int` | Refund on sell | 0 refund |
| `get_upgrade_cost_to(next: int) -> int` | Gold cost to advance to `next` | 0 = can't upgrade to that level |
| `can_upgrade() -> bool` | Linear upgrade available | — |
| `has_branch_options() -> bool` | At a branch-pick moment | — |
| `get_stats_line() -> String` | Preformatted stats-card row (e.g. `"Dmg 7   Rng 437   Spd 1.4"` for combat; `"Rally 450   Squad 3   HP 34"` for barracks) | empty hides the row |

**Ring color semantics** (enforced by `RangePreview`):

| Color | Meaning | Where drawn |
|---|---|---|
| Yellow `(1.0, 0.95, 0.4)` | Current tower reach | Always at `get_preview_range()` |
| Green `(0.35, 0.95, 0.4)` | Upgrade reach **≥** current (gain) | Outside yellow, at `get_upgrade_range()` |
| Red `(0.95, 0.35, 0.35)` | Upgrade reach **<** current (loss) | Inside yellow, at `get_upgrade_range()` |
| Orange | Rally-flag drag (barracks-only) | At `_effective_rally_range()` during drag |

Only one ghost ring draws at a time — green for gains, red for losses, nothing when equal or `get_upgrade_range() == 0`.

All ring stroke widths multiply by `1.0 / camera.zoom.x` (zoom-scale rule) so rings stay readable at any zoom.

---

## Game Design Decisions

| Property | Decision |
|---|---|
| Style | Kingdom Rush series (Ironhide Game Studio) |
| Theme | Fantasy medieval — knights, mages, orcs, trolls |
| Genre | Tower defense + hero unit + active skills + global spells |
| Platform | Android, iOS (primary) + PC (secondary) |
| Input | Touch + Mouse via "Emulate Touch From Mouse" |
| Tower placement | Fixed pre-defined spots only, branching upgrade at level 3 |
| Heroes | One at a time, chosen before level, gains XP from kills |
| Soldiers | Barracks spawn soldiers that block ground enemies |
| Global spells | Two spells deployable anywhere on map |
| Game modes | Campaign, Heroic, Iron (per level), Endless |
| Progression | Stars, permanent upgrades, hero unlocks, tower unlocks, talent tree |
| Monetization | Heroes and towers as IAP (PurchaseManager is a stub) |
| Save system | Full JSON persistence via SaveManager |

---

## Autoloads (11)

| Name | Purpose |
|---|---|
| EventBus | Signals only, zero logic |
| GameState | Gold, lives, score, wave, progression |
| WaveManager | Multi-path spawn + endless generation |
| DamageCalculator | All damage math: PHYSICAL (armor), MAGIC (magic_resist), TRUE |
| SaveManager | All persistence (JSON) |
| UnlockManager | IAP + unlock state |
| SceneManager | Scene transitions with fade |
| ContentRegistry | Master index of all content .tres |
| PurchaseManager | IAP client stub (auto-succeeds) |
| VFXSpawner | FloatingText + DeathVFX on EventBus signals |
| SoundManager | SFX pool + music player (graceful missing files) |

---

## Key Design Contracts

**Damage types** — `DamageCalculator.calculate_damage(amount, type, target)`:
- PHYSICAL: `amount * (1.0 - target.armor)`
- MAGIC: `amount * (1.0 - target.magic_resist)`
- TRUE: `amount` (ignores all resistances)

**Tower upgrades** — L1 → L2 → L3 with permanent branch choice at L3:
```
Level 1 → Level 2 → Level 3: BRANCH CHOICE (A or B, permanent)
```
`TowerData.level_upgrades` = [L2, L3_linear], `TowerData.level_3_branches` = [A, B] overrides L3.

**Health bars** — visible when `current_health < max_health`, hidden at full HP. Boss bars always visible. Same rule in base_enemy, base_soldier, base_hero.

**Targeting modes** — per-tower `TargetingMode { FIRST, STRONG, WEAK }`, cycled via the action-ring's target slot.

**Tactical pause** — TowerRadialMenu, TowerPlacer, SpotInputManager, HUD all use `PROCESS_MODE_ALWAYS`. Players can build/upgrade/sell while paused.

---

## Ability System

Every mechanic on top of base stats is an `AbilityData` Resource. Triggers: `ON_SPAWN`, `ON_INTERVAL`, `ON_HIT_DEALT`, `ON_HIT_TAKEN`, `ON_KILL`, `ON_DEATH`, `WHILE_ALIVE`, `ON_EQUIP`, `ON_UNEQUIP`. `AbilityHost` is a per-unit RefCounted dispatcher populated from `data.abilities` in `_ready()`.

**Discipline:**
- Abilities are owner-agnostic. No `if owner is BaseHero` — split the ability instead.
- `AbilityData` Resources are shared across instances. State lives on the host, never on the data.
- Adding a new ability: `systems/abilities/MyAbility.gd` extends `AbilityData`, override `apply(owner, ctx)`, reference as sub-resource in any unit `.tres`.

---

## Performance Rules — Mobile Critical

- Hero navigation: max every 0.2s via Timer — never every frame
- Range detection: Area2D overlap only — never distance loops
- Never call `get_tree().get_nodes_in_group()` in `_physics_process`
- UI animations: Tween only
- All input via `InputEventScreenTouch` / `InputEventScreenDrag` only — no mouse handlers
- Minimum touch target: 80x80 pixels

---

## Camera System

`GameCamera.gd` (Camera2D) sits in Main.tscn with a gesture state machine:
- **Tap** (< 12px movement, < 300ms) → dispatched via `EventBus.map_tap_confirmed(screen_pos, claim)`
- **Pan** (single-finger drag > 12px) → camera moves, clamped to `map_bounds`
- **Pinch zoom** (two fingers) → zoom 0.5x–2.0x, centered on pinch midpoint
- **Mouse wheel zoom** (PC) → zoom centered on cursor
- **Double-tap** (two taps within 300ms) → reset zoom to fit full map

Each level sets `map_bounds: Rect2` (exported on Level1.gd). Maps smaller than viewport are centered at 1:1 zoom with no panning. Maps larger than viewport start at 1:1 zoom with panning enabled — player drags to scroll.

**Zoom-scale rule:** All `_draw()` sizes that should stay constant on screen (health bars, floating text, line widths, tap radii) must multiply by `1.0 / camera.zoom.x`. See `_get_zoom_scale()` helper on base_enemy, base_soldier, base_hero, FloatingText, RangePreview.

**Map borders:** Level1._draw() renders mountains (top), cliffs (sides), water (bottom) beyond map_bounds. Background bleeds 3000px in all directions.

---

## Input Pipeline — Consumption Chain

Touch events flow through the camera's gesture classifier. Phases 1–3 fire BEFORE the camera sees the event. Phase 4 is replaced by EventBus dispatch.

```
1. _input (top-down) — claims event before camera
   ├── TowerBarracks._input   — consumes if rally-placement active
   ├── SkillBar._input        — consumes if skill targeting armed
   └── SpellPanel._input      — consumes if spell targeting armed

2. GUI phase (Control._gui_input)
   ├── TowerRadialMenu Backdrop — consumes when menu visible
   └── CooldownButton._gui_input — fires triggered(idx)

3. Area2D picking
   └── TowerBarracks FlagArea — consumes on flag drag

4. _unhandled_input — GameCamera gesture classifier
   ├── Pan gesture  → camera pans, event consumed
   ├── Pinch gesture → camera zooms, event consumed
   └── Tap confirmed → EventBus.map_tap_confirmed(screen_pos, claim)
	   ├── SpotInputManager — checks tower spots, claims if hit
	   ├── BaseHero         — checks selection radius, claims if hit
	   └── HeroInputManager — hero.move_to (if selected), claims if hit
```

**Tap claim pattern:** `map_tap_confirmed` passes a `TapClaim` RefCounted. Handlers check `claim.claimed` and set it to `true` when claiming. Connection order = priority (SpotInputManager first).

**Rules for new input handlers:**
- Phases 1–3: same as before — `set_input_as_handled()` to claim.
- Phase 4 (map taps): connect to `EventBus.map_tap_confirmed`, check `claim.claimed`.
- Never add new `_unhandled_input` handlers for touch — they conflict with the camera.
- **Touch-only gotcha:** `project.godot` sets `pointing/emulate_touch_from_mouse=true`. Every physical mouse click arrives as BOTH an `InputEventMouseButton` AND an emulated `InputEventScreenTouch`. A `_gui_input` (or `_input`) handler that accepts both event types will fire TWICE per click on PC — breaks any stateful flow (two-step commits, toggles, tap-to-confirm). Handle `InputEventScreenTouch` / `InputEventScreenDrag` only, everywhere. Matches the existing rule in Performance Rules.

---

## UI on CanvasLayers

All UI is on CanvasLayers, independent of Camera2D. **Must set `follow_viewport_enabled = false`** on every UI CanvasLayer to prevent camera zoom from distorting Control layout.

| Layer | UI |
|---|---|
| 0 | HUD (gold, lives, wave, speed, pause) |
| 6 | SpawnIndicator (screen-edge spawn arrows) |
| 7 | SpellPanel (bottom-left) |
| 8 | SkillBar (bottom-right) |
| 10 | TowerRadialMenu (radial ring at spot: build / upgrade / sell / target / rally) |
| 20 | PauseMenu, GameOverScreen |

**Safe area:** `SafeAreaMargin.gd` (extends MarginContainer) sits at the root of HUD, SkillBar, and SpellPanel CanvasLayers. Sets `theme_override_constants/margin_*` from `GameState.get_safe_insets()` — Godot's layout engine pushes all children inward. Recalculates on window resize. Safe area math uses `DisplayServer.screen_get_size()` (NOT `window_get_size()`) because `get_display_safe_area()` returns screen-space coordinates.

**SpawnIndicator:** Replaces world-space SpawnMarkers. Projects spawn world positions to screen coordinates via `get_canvas_transform()`, draws arrows at screen edges when off-screen.

---

## Radial Menu Interaction — Two-Step Commit

`TowerRadialMenu` uses a **peek-then-confirm** flow so mobile players can compare options before spending gold. Same UX on touch and mouse (no hover previews — would be ambiguous on touch).

**Rules:**
- First tap on a slot **arms** it: highlights the slot, shows the relevant preview in `TowerStatsCard`, and draws range rings (yellow for current / green for larger upgrade / red for smaller upgrade).
- Second tap on the **same** armed slot commits the action (build / upgrade / branch-pick / sell).
- Tap a **different** slot → re-arms that one; prior preview disappears.
- Tap the backdrop → dismisses, no commit.
- **Dismiss-on-commit:** build, upgrade, branch, and sell all dismiss the menu after committing. Player sees the tower update and must re-tap the spot for any next action. Prevents accidental chained upgrades from a finger lingering near the top slot. Enforced via `_on_tower_upgraded → _dismiss()` for upgrade/branch and `_on_tower_sold → _dismiss()` for sell; build dismisses inline in `_on_build_slot_pressed`.
- **Single-tap carve-outs:** `target` (cycles FIRST → STRONG → WEAK, non-destructive) and `rally` (enters flag-placement mode, not a commit) fire immediately on one tap. Target stays in place; rally dismisses.

**Stats card modes** (`TowerStatsCard`):
- `show_for(tower, ...)` — built tower: name, level, `get_stats_line()`, targeting, damage dealt.
- `show_for_build_preview(data, ...)` — buildable tower: name, `TowerData.get_stats_line()`, cost, description.
- `show_for_upgrade_preview(current, upgrade, ...)` — upgrade diff: arrow format `"Dmg 4→7   Rng 400→437   Spd 1.2→1.35"` + cost.
- `show_for_sell_confirm(refund, ...)` — "Sell tower? Tap again to confirm · Refund +Ng".

**State invariants to preserve when editing the menu:**
- `_armed_slot` must be cleared whenever slots are freed (`_clear_slots`, `_dismiss`, `_rebuild_action_slots`).
- Whenever the action-ring rebuilds in place (gold change, target cycle), the stats card must be restored to `show_for(...)` built-tower mode. Preview modes leave `_tower = null` so `refresh()` is a no-op. Upgrade/branch commits skip this invariant because they dismiss instead of rebuilding.
- Build-ring `_armed_slot` becoming unaffordable must disarm and clear the preview (otherwise the icon glows but can't be tapped).

---

## Scene Navigation Graph

All transitions use `SceneManager.goto(path)` with fade. WorldMap is the central hub.

```
MainMenu → WorldMap (hub)
			   ├── LoadoutScreen → Main.tscn (gameplay)
			   │                      ├── PauseMenu → restart (Main.tscn) or quit (WorldMap)
			   │                      └── GameOverScreen → retry (Main.tscn) or continue (WorldMap)
			   ├── UpgradeTree
			   ├── TalentScreen
			   ├── EncyclopediaScreen
			   ├── LeaderboardScreen
			   ├── ShopScreen
			   └── ← back to MainMenu
```

---

## Status Effects on Enemies

Applied via `BaseEnemy.apply_effect(effect)`. Stored in `_effects: Dictionary` keyed by `effect.id`. Reapplying the same ID refreshes duration. Ticked in `_tick_effects(delta)` — auto-removed when `remaining_time <= 0`.

- **SlowEffect** — multiplies `move_speed` by `(1.0 - slow_factor)`. Stacks by replacement (strongest wins via reapply).
- **StunEffect** — blocks state changes (enemy stuck in current state). Walking and attacking halt.

Effects modify behavior in `_get_effective_speed()` and state gate checks. Tower upgrades can add on-hit effects via `TowerUpgradeData.on_hit_slow_factor/on_hit_slow_duration`.

---

## Blocking and Capacity

Soldiers AND heroes can lock ground enemies into `COMBAT` (enemy stops walking). Flying enemies skip engagement.

- **Capacity lives on the blocker's data.** `SoldierData.max_block_targets` (default `1`) and `HeroData.max_block_targets` (default `2`; mage overrides to `1`). Designer tweaks in the inspector — no hardcoded values in scripts.
- **Enemies allow any number of blockers.** `BaseEnemy._blockers: Array[Node]` holds every unit currently engaging. State is `COMBAT` iff the array is non-empty. Counter-attacks focus on `_blockers[0]` (oldest engager) — keeps the attack telegraph arc pointed at a stable target.
- **Split rule on target pick.** Both `BaseSoldier._try_engage` and `BaseHero._pick_split_target_in_area` prefer enemies with the FEWEST current blockers (ties broken by distance). Effect: with multiple enemies in range, friendlies spread across threats; with only one enemy, everyone piles on.
- **Hero auto-claims extras.** While in `COMBAT`, `BaseHero._auto_engage_extras` scans attack range every frame and claims additional blocks up to capacity. `_prune_blocks_out_of_range` releases blocks when targets die or leave range so enemies never stay frozen.
- **Release points.** Both units call release on death, on rally-flag move (soldier), on tap-to-move (hero), and on target loss.

---

## Hero Spawn Marker

Each level scene must include a `Marker2D` named `HeroSpawn` as a direct child of the level root. `Level1.gd.get_hero_spawn_position()` reads it; `Main.gd._spawn_hero()` queries the level for the position. Drag the marker in the 2D editor to change where the hero appears at game start AND after every respawn. Missing marker → `BaseHero._respawn()` falls back to `Vector2(960, 540)`.

---

## Hero Death and Respawn

- **Damage**: while in `COMBAT` state, the engaged enemy counter-attacks on its `attack_speed` cadence via `BaseHero._tick_incoming_attack`. Flying enemies skip (matches soldier engagement rule). Strike range: `ENEMY_STRIKE_DISTANCE = 60px`.
- **Death**: `BaseHero._die` sets DEAD, hides the hero, emits `EventBus.hero_died`, and schedules `get_tree().create_timer(HeroData.respawn_time)` → `_respawn()`. Timer honors pause, so tactical pause freezes the countdown.
- **Respawn**: teleports to the level's `HeroSpawn` marker, restores full HP (level-scaled via `_effective_max_health()`), emits `EventBus.hero_respawned`. HUD shows "Respawn: %.1fs" label while dead.

---

## Adding New Content — Checklist

**New enemy:**
1. Create `enemies/data/enemy_foo.tres` (EnemyData) + `visual_foo.tres` (UnitVisualData)
2. Set `enemy_id = "enemy_foo"` (stable, never rename)
3. Add abilities as sub-resources if needed (e.g. RegenAbility, explode-on-death)
4. For flying: set `is_flying = true` (uses EnemyFlying scene). For boss: use BaseBoss + BossPhaseData
5. Register in `ContentRegistry.gd` → `enemies` array
6. Reference `enemy_id` in wave `.tres` files

**New tower:**
1. Create `towers/data/tower_foo.tres` (TowerData)
2. Set `tower_id = "tower_foo"`, stats, `body_color`, projectile_scene
3. Add `level_upgrades` (L2, L3) and optionally `level_3_branches` (A, B)
4. For barracks: set `soldier_scene` + `soldier_data` (uses TowerBarracks scene). Barracks upgrades populate `level_upgrades` too — each `TowerUpgradeData` can set `soldier_data_override` (stronger SoldierData) and `soldier_rally_range` (larger placement radius). On upgrade the squad is despawned and respawned with the new `SoldierData`.
5. Register in `ContentRegistry.gd` → `towers` array

**Tower interface:** every tower class MUST implement the full Tower Indicator Interface (see the section above "Game Design Decisions" for the method table). This is CORE RULE 14. New tower classes implement `get_preview_range()`, `get_upgrade_range()`, `get_effective_damage()`, `get_effective_attack_speed()`, `get_sell_value()`, `get_upgrade_cost_to()`, `can_upgrade()`, `has_branch_options()`, and `get_stats_line()`. Once implemented, RangePreview / TowerStatsCard / TowerRadialMenu / TowerPlacer all work without modification — zero UI changes per new tower.

**New ability:**
1. Create `systems/abilities/MyAbility.gd` extending `AbilityData`
2. Override `apply(owner, ctx)`
3. Add as sub-resource in any unit's `.tres` → `abilities` array

**New hero skill:**
1. Create `heroes/skills/my_skill_data.gd` extending `SkillData`
2. Override `apply(hero, target)`
3. Create `heroes/data/skills/skill_foo.tres` and reference in hero `.tres` → `skills` array

---

## Asset Strategy

Procedural `_draw()` shapes for all visuals. Data-driven via `UnitVisualData` resources.

- Free art when ready: kenney.nl
- Free SFX: freesound.org
- File naming: `entity_animation_00.png` (e.g. `enemy_orc_walk_00.png`)
- Drop `.wav` files into `audio/sfx/` — SoundManager auto-detects by event name.

---

## Movement System — Golden Hybrid

**Hero & soldiers** use `NavigationAgent2D` for smart pathfinding (only ~10 agents). **Enemies** stay on `PathFollow2D` rails with swarm effects (zero nav CPU).

### Hero Movement (Kingdom Rush style)
- `SeekRange` Area2D (2.5x attack_range) detects enemies → hero auto-walks toward them via nav agent
- Melee heroes walk right up (within `MELEE_ENGAGE_DISTANCE = 30px`) for face-to-face combat
- Ranged heroes stop at attack_range edge
- Enemy leaves attack range → hero **chases** (instead of dropping target)
- Player tap always overrides auto-seek and combat
- Repathing throttled to every 0.5s (`NAV_REPATH_INTERVAL`) for mobile perf

### Soldier Movement
- Nav-paths to rally position (paths around obstacles instead of straight line)
- First-frame fallback: direct movement if nav_agent not ready yet
- BLOCKING + melee engagement unchanged

### Enemy Swarm — Single Path + 3-lane v_offset (no NavAgent)
Each spawn direction has **one Path2D** (`left`, `right`, `top`). At spawn, `WaveManager.spawn_enemy` picks one of **3 discrete lanes** for each non-boss enemy by setting `PathFollow2D.v_offset` to `{-LANE_SPACING, 0, +LANE_SPACING}` (currently ±50px). `rotates = false` is set on the PathFollow2D, so `v_offset` shifts along world Y — which reads as "above / on / below the road" on the horizontal paths used in Level1. The swarm occupies three visibly distinct tracks instead of a scattered continuous band. **Bosses ride centered (`v_offset = 0`).** If a future level uses a path running top-to-bottom instead of left-to-right, this property choice will need revisiting (or switch to `rotates = true` + `v_offset` for per-curve perpendicular).

- **Spawn timing jitter** — `±0.25s` variation on each spawn interval in WaveManager.
- **Boss detection** — `WaveManager._BOSS_SCENES` is the single source of truth. Add new boss PackedScenes there to have them auto-centered.
- **Visual editing** — Level1.gd is `@tool`: each path renders as a brown polyline in the editor. Click the `Path2D`, drag curve handles to reshape. One curve per direction — no rail-parallelism chore.

**Adding a direction to a new level:** create one Path2D under `Paths/` named with the base id (e.g. `east`). Reference the id in wave `.tres` spawns.

### NavigationPolygon per level
`Level1.tscn` has a `NavigationRegion2D` with a `NavigationPolygon` covering `map_bounds`. Future levels cut holes for terrain obstacles (rocks, rivers).

---

## Current Status

Phase 45b complete. Resolution: 1920x1080 landscape, `keep_height`. Camera system (pan, zoom, gesture classifier, map borders, zoom-scaled drawing). Safe area via MarginContainer + `GameState.get_safe_insets()`. NavigationAgent2D for hero/soldiers. Enemies ride a single Path2D per direction with a discrete 3-lane v_offset for lateral swarm spread, plus spawn-timing jitter. Boss detection unified on `EnemyData.is_boss` and `WaveManager._BOSS_SCENES`. Hero spawn via editor-adjustable `HeroSpawn` Marker2D; hero takes reciprocal damage from engaged enemies and respawns on a timer at the marker. Combat visuals: per-hit white flash (all units), 150ms red attack-telegraph arc on enemies, weapon swing arc on lunges, rear-back wind-up curve replacing the triangle-wave lunge. QoL features: tactical pause, tower damage tracking, upgrade stat deltas, targeting modes, early wave call, clean view toggle, floating damage numbers. Radial tower menu (Phase 45a + 45b): empty spots open a build ring of procedural-`_draw()` tower icons with cost badges and press-hover range preview; occupied spots open an action ring (green upgrade / red sell / blue target / orange rally, with two green branch cards at L3) plus a floating stats card above the ring showing name, level, effective stats, and total damage dealt. Shared screen-space anchoring with edge-clamping + safe-area insets, staggered pop-scale open animation, slot rebuilds on tower_upgraded / targeting cycle / gold_changed. Old bottom-sheet TowerSpotMenu retired.

Phase 45c complete. Barracks now upgrade L1→L2 via the same pipeline as attack towers (`can_upgrade()`/`upgrade()` on TowerBarracks, duck-typed by TowerPlacer). `TowerUpgradeData` gained `soldier_data_override` and `soldier_rally_range` fields so the Elite Barracks (L2) spawns tougher soldiers (soldier_elite.tres: 34 HP / 6 dmg / 0.15 armor) within a larger 450px rally radius. On upgrade the active squad is despawned and fresh soldiers spawn with the new SoldierData. Unified range-preview API: every tower implements `get_preview_range()` + `get_upgrade_range()`; RangePreview draws a yellow ring for current reach and a translucent green "ghost ring" on upgrade/branch slot hover, showing the exact reach the player would buy. Connected hover/unhover signals on RadialActionButton (already emitted, previously ignored by the menu).

Phase 45d complete. Radial menu restructured around **two-step commit** for mobile-first UX (see "Radial Menu Interaction" section). First tap on any build/upgrade/branch/sell slot arms it and shows a peek; second tap on the same slot commits. Target and rally stay single-tap. Hover previews removed entirely — same flow on touch and mouse. `TowerStatsCard` now has four modes (built tower / buildable preview / upgrade-diff preview with arrow format / sell confirmation), driven by new `TowerData.get_preview_range()` + `get_stats_line()` and `TowerUpgradeData.get_stats_line(base)` accessors. Red ghost ring added for decrease-range upgrades (inside yellow). Fixed double-event bug: `_gui_input` on radial buttons now handles `InputEventScreenTouch` only since `emulate_touch_from_mouse=true` would otherwise double-fire `pressed` per PC click.

Phase 45e (Kingdom-Rush charge fidelity) complete. Soldiers now **charge** enemies that enter their aggro sensor instead of standing idle at rally waiting for a 45px melee overlap. New `SoldierData.aggro_range` (default 130px) drives a second Area2D; state machine extended with `CHARGING` (chase a committed target, engage on melee contact) and `RETURNING` (walk back to rally slot after kill/disengage). Engagement pauses motion; losing the target mid-charge triggers return. `max_block_targets` cap still enforced — no chase while full. Rally-move (`set_blocking_position`) also drops `_charge_target`. Enables KR's canonical "stack two barracks' rally points on a boss → 6 soldiers gang up" surround tactic to actually land. Balance counter seeded: new `EnemyData.attack_splash_radius` (default 0 = single-target, preserves all existing enemies) makes `base_enemy._combat_tick` swing AoE against every blocker within radius of `_blockers[0]`, ready for Yeti/Magma-Elemental-style archetypes that punish stacking.

Phase 45f (charge leash + bypass archetype) complete. Anchors the charge to the barracks zone so faster-than-soldier enemies can't drag troops off-lane: new `SoldierData.leash_range` (default 200px) caps how far a soldier may drift from its rally slot mid-charge — cross it and the soldier drops `_charge_target` and transitions to RETURNING. Seeds the KR: Vengeance Rushing-Monkey archetype via `EnemyData.bypass_engagement: bool = false` — when true, `BaseEnemy.engage_combat` rejects every blocker, so the enemy walks through soldier and hero lines untouched. Defaults preserve every existing unit's behavior. Gemini's NavigationAgent2D "fix" for soldier charge deliberately rejected: violates CORE RULE 13 (soldier movement is direct straight-line, navmesh constrains placement not pathing).

Phase 45h (engagement zone anchored to the flag) complete. Fixes a charge-bug where soldiers finishing a kill would pick up an enemy already past the barracks and chase it down the lane, abandoning the rally. Root cause: the aggro Area2D rides the soldier, so after any drift the geometric scan centers on the soldier's current position instead of a static anchor. Fix reuses the existing `SoldierData.leash_range` (200px default) as a **static engagement zone** centered on the barracks's flag world position (shared across the whole squad, not per-slot). `BaseSoldier` gained `_flag_position` alongside `_blocking_position`; `TowerBarracks._spawn_soldier` and `_recall_soldiers` pass the flag world pos through `setup(slot, flag)` / `set_blocking_position(slot, flag)` (both args default to `Vector2.INF` for legacy callers). `_scan_aggro_and_maybe_charge` rejects candidates outside `leash_range` of the flag; `_tick_charge` drops the target and returns the moment it exits the zone — no path-progress tracking, no direction math. **Zone visualization:** `TowerBarracks._draw` now renders an always-visible subtle red ring around the flag at `leash_range` radius so the player can see each barracks's area of responsibility at a glance. First attempt also added proactive-engage at 90px + a distant-strike safeguard on `BaseEnemy._combat_tick` — ripped out after the user reported soldiers standing next to frozen enemies dealing no damage: proactive engage added the soldier to the enemy's `_blockers` but `_try_engage`'s later `engage_combat` call returned false (blocker already registered), leaving the soldier's `_engaged_enemies` empty so `_attack_cycle` never swung. Simpler design (zone-only, no proactive engage) preserved.

Known bugs: none
