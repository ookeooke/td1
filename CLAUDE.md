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

Entry point: `res://ui/MainMenu.tscn`. Viewport: 375x812 (portrait). Renderer: GL Compatibility (mobile-first). No build system, linter, or test suite — validate by running in the Godot editor.

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

## Input Pipeline — Consumption Chain

Touch events flow in this order. Each layer either consumes (`set_input_as_handled()`) or passes through. Getting this wrong causes double-fires or stolen taps.

```
1. _input (top-down)
   ├── TowerBarracks._input   — consumes if rally-placement active
   ├── TowerSpotMenu._input   — swallows release after menu opened
   ├── SkillBar._input        — consumes if skill targeting armed
   └── SpellPanel._input      — consumes if spell targeting armed

2. GUI phase (Control._gui_input)
   ├── TowerSpotMenu Backdrop — consumes when menu visible
   └── CooldownButton._gui_input — fires triggered(idx)

3. Area2D picking
   └── TowerBarracks FlagArea — consumes on flag drag

4. _unhandled_input
   ├── SpotInputManager        — tower_spot_tapped + CONSUMES
   ├── BaseHero._unhandled_input — toggles selection
   └── HeroInputManager        — hero.move_to (if selected)
```

**Rules for new input handlers:**
- Declare which phase (1-4) it runs in.
- Always `set_input_as_handled()` when claiming an event.
- Always check `is_input_handled()` in `_input` if competing with same-phase handlers.

---

## Asset Strategy

Procedural `_draw()` shapes for all visuals. Data-driven via `UnitVisualData` resources.

- Free art when ready: kenney.nl
- Free SFX: freesound.org
- File naming: `entity_animation_00.png` (e.g. `enemy_orc_walk_00.png`)
- Drop `.wav` files into `audio/sfx/` — SoundManager auto-detects by event name.

---

## Current Status

All 41 build phases complete. QoL features added: tactical pause (build while paused), tower damage tracking, upgrade stat deltas, targeting modes (FIRST/STRONG/WEAK), early wave call with bonus gold, clean view toggle, floating damage numbers.

Known bugs: none
