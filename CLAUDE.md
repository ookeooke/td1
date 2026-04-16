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

**Targeting modes** — per-tower `TargetingMode { FIRST, STRONG, WEAK }`, cycled via TowerSpotMenu.

**Tactical pause** — TowerSpotMenu, TowerPlacer, SpotInputManager, HUD all use `PROCESS_MODE_ALWAYS`. Players can build/upgrade/sell while paused.

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
   ├── TowerSpotMenu Backdrop — consumes when menu visible
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

---

## UI on CanvasLayers

All UI is on CanvasLayers, independent of Camera2D. **Must set `follow_viewport_enabled = false`** on every UI CanvasLayer to prevent camera zoom from distorting Control layout.

| Layer | UI |
|---|---|
| 0 | HUD (gold, lives, wave, speed, pause) |
| 6 | SpawnIndicator (screen-edge spawn arrows) |
| 7 | SpellPanel (bottom-left) |
| 8 | SkillBar (bottom-right) |
| 10 | TowerSpotMenu (bottom slide-up) |
| 20 | PauseMenu, GameOverScreen |

**Safe area:** `SafeAreaMargin.gd` (extends MarginContainer) sits at the root of HUD, SkillBar, and SpellPanel CanvasLayers. Sets `theme_override_constants/margin_*` from `GameState.get_safe_insets()` — Godot's layout engine pushes all children inward. Recalculates on window resize. Safe area math uses `DisplayServer.screen_get_size()` (NOT `window_get_size()`) because `get_display_safe_area()` returns screen-space coordinates.

**SpawnIndicator:** Replaces world-space SpawnMarkers. Projects spawn world positions to screen coordinates via `get_canvas_transform()`, draws arrows at screen edges when off-screen.

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
4. For barracks: set `soldier_scene` + `soldier_data` (uses TowerBarracks scene)
5. Register in `ContentRegistry.gd` → `towers` array

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

## Current Status

All 41 build phases complete. Resolution: 1920x1080 landscape, `keep_height`. Camera system (pan, zoom, gesture classifier, map borders, zoom-scaled drawing). Safe area via MarginContainer + `GameState.get_safe_insets()`. QoL features: tactical pause, tower damage tracking, upgrade stat deltas, targeting modes, early wave call, clean view toggle, floating damage numbers.

Known bugs: none
