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
7. **All IAP-locked content checked through UnlockManager's type-specific methods before loading.** Call `is_tower_unlocked(tid)` / `is_hero_unlocked(hid)` / `is_spell_unlocked(sid)` — the global `is_unlocked(id)` no longer exists (it searched heroes→towers→spells and silently returned the first hit, which shadowed towers when IDs collided). Never hardcode unlock states.
8. **All save/load through SaveManager only.** No other script touches the save file.
9. **Before changing anything working, explain why the change is needed.** Then wait for approval.
10. **New content is authored as data, not code.** Every new hero / soldier / enemy / skill / spell / ability / item is a `.tres` resource composed from existing base classes + AbilityData components. Only subclass when the variant needs genuinely new *structural* behavior (collision layer, multi-phase state machine, projectile vs. melee).
11. **One primitive for mechanics: AbilityData.** Every "verb on a unit" — passives, on-hit effects, auras, items, talents, endless modifiers, status effects — is an `AbilityData` Resource with a `Trigger` and an `apply(owner, ctx)` override. `AbilityHost` dispatcher is owner-agnostic.
12. **Stable content IDs, scoped by type, matching filename.** Every Resource has a `*_id: String` field. IDs are keys in save files, unlock checks, leaderboard payloads. **Never rename an ID after first release.** Convention: `snake_case`, scoped by type (`hero_warrior`, `tower_archer`, `spell_fireball`, `enemy_basic`), and **must equal the filename basename** (`tower_archer.tres` holds `tower_id = "tower_archer"`). Enforced at boot by `ContentRegistry._validate_ids()` — any drift prints `[ContentRegistry/DRIFT]` lines in the output panel.
13. **Soldier rally positions are constrained to the navmesh; soldier movement is direct.** For soldier-spawning blocker buildings (barracks today; future siege camps, summoning towers, patrol posts), both the rally **flag** and every derived rally **slot** must be snapped to the navmesh via `NavigationServer2D.map_get_closest_point` — guaranteeing soldiers always stand on walkable terrain. Soldier movement between positions is always a direct straight line (`velocity = (target - pos).normalized() * speed`), on spawn and on flag moves alike. No `NavigationAgent2D` routing. The navmesh constrains **placement**, not **pathing**.
14. **Tower indicators read through accessors, never `tower.data.*` fields.** All UI that displays a tower's range, stats, sell value, or upgrade cost MUST go through the Tower Indicator Interface (see below). No `has_method` fallbacks to `.data.*`. No per-class branches (`if tower is TowerBarracks`). Each tower owns its own stats-line formatting via `get_stats_line()` so the stats card stays tower-agnostic. Carve-outs: static display strings like `tower.data.tower_name` (never change on upgrade); build-ring UI operating on `TowerData` resources before any tower instance exists. *Why:* reading `tower.data.attack_range` silently shows the L1 base stat on an upgraded tower — a bug class the interface prevents. Adding a new tower type = implement the interface, zero UI changes.
15. **Tower scenes are bare chassis — never bake `data` into a tower `.tscn`.** Combat towers reuse `res://towers/TowerCombat.tscn`; Barracks use `res://towers/TowerBarracks.tscn`. The TowerData `.tres` references the chassis via `tower_scene`; `TowerPlacer._on_build_requested` assigns `tower.data = entry.data` after `instantiate()` and before `add_child()`. *Why:* baking `data = ExtResource("tower_foo.tres")` in a chassis creates a tres↔tscn circular reference that silently leaves `tower.data = null` at runtime and breaks data-driven modularity (Phase 47d-7 incident — Ice Tower rendered as Archer or didn't shoot at all). One chassis backs N towers; data drives everything.

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

## Autoloads (12)

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
| Toast | Transient on-screen messages (`Toast.show_message("…")`) |

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

**Unlock API** — `UnlockManager` exposes **type-scoped** methods only:
- `is_hero_unlocked(hero_id: String) -> bool`
- `is_tower_unlocked(tower_id: String) -> bool`
- `is_spell_unlocked(spell_id: String) -> bool`
- `unlock(id: String)` — type-agnostic (flat list + IDs are scoped so collisions can't happen)

Each `is_*_unlocked` searches only its own ContentRegistry (`find_hero` / `find_tower` / spells loop) — never the global namespace. `ProductData.unlock_type` (enum `{HERO, TOWER, SPELL}`) tells `ShopScreen` which method to dispatch. Three unlock paths apply uniformly: explicit (IAP via `GameState.unlocked_content`), free (`requires_unlock == false` on the Data), star-threshold (`UnlockManager._star_thresholds`).

**Damage attribution** — per-run tally of "who dealt what" for the end screen. `BaseEnemy.take_damage(amount, type, source)` routes the overkill-capped `actual` into `GameState.record_round_damage(source, amount)`, which dispatches by `source is BaseTower / BaseHero / BaseSoldier / SpellPanel` into four buckets:
- `round_damage_towers: Dictionary` — keyed by `source.get_instance_id()` so sold towers still contribute; values `{name, total}`
- `round_damage_hero: float`
- `round_damage_soldiers: float`
- `round_damage_spells: float`

All four cleared in `GameState.reset_for_level()`. `GameOverScreen._build_damage_breakdown()` reads them and renders a top-5 tower leaderboard + Hero/Soldiers/Spells rows on both victory and defeat (and on endless Game Over). `is_instance_valid(source)` guards against sold-tower projectiles hitting post-free.

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

## GDScript Conventions

- **Don't shadow built-ins.** No local `seed`, `hash`, `len`, `abs`, `clamp`, `rng`, `type`, `min`, `max`, etc. The parser warns `SHADOWED_GLOBAL_IDENTIFIER` and `_squad_color`'s `var seed: int = …` in TowerBarracks tripped this during 47d-7. Prefer short unambiguous names (`h`, `rng_seed`, `n`).

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

**New tower (Phase 47d-1 onward — one-file add):**
1. Create `towers/data/tower_foo.tres` (TowerData).
2. Set `tower_id = "tower_foo"` — must match the filename basename (validator enforces this at boot).
3. Set stats, `body_color`, `projectile_scene`, **and the new required fields**: `tower_scene: PackedScene` (use `res://towers/TowerCombat.tscn` for any combat tower — bare chassis, no baked data, data is set by TowerPlacer post-instantiate) and `pictogram: String` (key into `TowerIconButton._draw_glyph` — e.g. `"bow"`, `"star"`, `"cannon"`, `"shield"`, `"snowflake"`, `"generic"` for the fallback circle).
4. Add `level_upgrades` (L2, L3) and optionally `level_3_branches` (A, B).
5. For barracks: set `soldier_scene` + `soldier_data`. Barracks upgrades populate `level_upgrades` too — each `TowerUpgradeData` can set `soldier_data_override` (stronger SoldierData) and `soldier_rally_range` (larger placement radius). On upgrade the squad is despawned and respawned with the new `SoldierData`.
6. **Register in ONE place**: `ContentRegistry.gd` → `towers` array — add `preload("res://towers/data/tower_foo.tres")`. That's it.
7. **New glyph?** Only if you want a distinctive icon. Add one `"foo":` case to `ui/TowerIconButton.gd`'s `_draw_glyph()` match (shared across any tower that sets `pictogram = "foo"`). Skip this and the tower falls back to the generic circle — functional, reusable.

**⚠️ Common pitfalls when adding a tower** (lessons from Phases 47d-6/47d-7):

- **Don't create a new `.tscn` per tower.** Use `res://towers/TowerCombat.tscn` for any combat tower. Making `TowerFoo.tscn` with a baked `data = ExtResource(...)` reintroduces the tres↔tscn circular reference that leaves `tower.data = null` at runtime (CORE RULE 15).
- **Status effects (slow / stun) live on BOTH `TowerData` and `TowerUpgradeData`.** If your tower slows at L1, set `on_hit_slow_factor` / `on_hit_slow_duration` on the base `TowerData`. `_build_on_hit_effect()` and `get_preview_stats()` fall back from upgrade override → base data when the override is 0 — so upgrades that don't explicitly override still carry the base effect.
- **Don't use `TowerIconButton.setup()` outside the in-game build ring.** It runs `refresh_affordability()` against live `GameState.gold`, which silently swallows taps on towers you can't afford. The loadout picker uses `setup_pool(data)` (always affordable); read-only previews use `setup_display(data)` (no input). Calling `setup()` from LoadoutPickerScreen is what hid Artillery behind an invisible "you only have 100g" gate in 47d-6.
- **Don't hand-write `uid://...` strings in new `.tres` or `.tscn` files.** Let Godot auto-fill them via the Inspector. Hand-written UIDs drift when the linter or another tool regenerates the target scene (TowerCombat.tscn's UID changed twice during 47d-7 — every hand-written reference had to be chased down).

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

Phase 46 (content + attribution) complete. **Two new ground enemies** fill the tier-1→boss gap: Armored Orc (`enemy_armored`: HP 20 / 0.3 armor / speed 140 / dmg 4) and Goblin Scout (`enemy_scout`: HP 6 / speed 280 / dmg 2). Both are data-only additions — `.tres` + `UnitVisualData` + trivial scene binding `base_enemy.gd`. Registered in `ContentRegistry.enemies`. **Level 1 gets a Wave 5** final-push spec in `level1_waves.tres`: 12 basics + 4 armored on left, 8 scouts + 3 armored on right, 6 harpies on top, 2 shamans, 1 boss at +8s delay. Countdown 6s, bounty 120. **Victory-screen damage attribution** ("who won this for you"): `GameState.round_damage_towers` (dict keyed by instance_id so sold towers still count), `round_damage_hero`, `round_damage_soldiers`. `BaseEnemy.take_damage` routes each hit's `actual` (post-armor, overkill-capped) to `GameState.record_round_damage(source, amount)`, which inspects the source's class — `BaseTower` / `BaseHero` / `BaseSoldier` — and tallies. Spells and environmental damage are intentionally skipped. `GameOverScreen` renders top-5 towers sorted by damage + Hero + Soldiers lines on BOTH victory and defeat, skipping the section if nothing was recorded. Cleared by `GameState.reset_for_level()`.

Phase 46b (review hardening) complete. Four follow-up fixes on the damage-attribution pipeline: (1) `GameState.record_round_damage` now guards with `is_instance_valid(source)` to handle the sell-tower-while-projectile-in-flight case without crashing; (2) `GameOverScreen._build_damage_breakdown` falls back to the literal string "Tower" when an entry's display name is empty (edge case for towers with null `data`); (3) the endless-mode branch of `_on_game_over` now appends the damage breakdown to its "Wave reached / Score" summary so long endless runs see the leaderboard too; (4) spell damage is now tracked — added `GameState.round_damage_spells: float`, `SpellPanel` got `class_name SpellPanel` so `source is SpellPanel` works as the tag, and the breakdown renders a "Spells" row when > 0. All four clear in `reset_for_level()`.

Phase 46c (architectural hardening) complete. Two seams that caused the "Mage tower invisible" bug are now closed: (1) **Boot-time ID validation** — `ContentRegistry._ready()` now calls `_validate_ids()`, which asserts every loaded `.tres` has a `*_id` field matching its filename basename. Drift (e.g. `tower_archer.tres` holding `tower_id = "archer"`) prints `[ContentRegistry/DRIFT]` lines at project open instead of silently corrupting unlock checks months later. `print` was chosen over `push_warning` because standalone runs suppress warning output. (2) **Type-aware UnlockManager API** — the old global-namespace `is_unlocked(id)` (which searched heroes→towers→spells and returned the first hit) is replaced by `is_hero_unlocked`, `is_tower_unlocked`, `is_spell_unlocked`. Each routes through `ContentRegistry.find_<type>(id)` only, eliminating the class of bug where `hero.hero_id = "mage"` + `requires_unlock = true` shadowed `tower.tower_id = "mage"`. `ProductData` gained an `unlock_type: enum {HERO, TOWER, SPELL}` field so `ShopScreen` can dispatch to the right checker. All four callers (LoadoutScreen, TowerRadialMenu, ShopScreen, plus the shop's own new wrapper) migrated. Deferred: save-file migration framework + single-source tower registry (scene + pictogram folded into TowerData).

Phase 46d (ID cleanup) complete. With the validation from 46c naming every drift, all 7 non-scoped content IDs renamed to match their filenames: `archer` → `tower_archer`, `barracks` → `tower_barracks`, `artillery` → `tower_artillery`, `warrior` → `hero_warrior`, `mage` (hero) → `hero_mage`, `fireball` → `spell_fireball`, `reinforcements` → `spell_reinforcements`. Cascade updates: `TowerPlacer._SCENE_MAP` keys, `TowerIconButton._draw_pictogram` match cases, `GameState.selected_hero_id` default (2 sites), `ShopScreen.tscn` `unlock_id`. Save migration framework deferred — user's save was deleted during this change so no orphaned keys. Next rename should ship with the migration scaffold from Proposal 3 in the code-review plan.

Phase 47d-9 (code-review fixes) complete. Audit after 47d-8 found two real bugs. **Fix A — in-game build ring collapsed loadout gaps**: `GameState.get_loadout_towers()` skips empty entries (`""`), returning a compacted Array. `TowerRadialMenu._open_build_ring` indexed that array against ring slots — so clearing slot 1 in the picker pulled every subsequent tower one position forward in-game, misaligning the picker's "this is what you'll see" promise. Rewrote `_open_build_ring` to iterate `GameState.selected_tower_ids` positionally, same pattern as `LoadoutPickerScreen._rebuild_ring` — empty slots stay empty at their picker index. Also respects live `UnlockManager.is_tower_unlocked` so a tower that gets locked between picker and level renders as an empty slot, not a broken build icon. `get_loadout_towers()` unchanged (still correct for LoadoutScreen's compacted read-only row). **Fix B — on-hit slow gate was too strict**: `base_tower._build_on_hit_effect` fell back base→override *per-field* on the way in, but the final `if slow_f > 0.0 and slow_d > 0.0` silently dropped the effect when an upgrade set `on_hit_slow_factor = 0.5` and left `on_hit_slow_duration = 0` — a content-authoring footgun (upgrades that want to boost factor only and inherit base duration). Added a cross-fallback: `if slow_f > 0.0 and slow_d <= 0.0 and data != null: slow_d = data.on_hit_slow_duration`. Mirrored in `get_preview_stats` so the stats card reports the actual applied duration. `TowerUpgradeData.get_preview_stats` already had the right per-field logic and needed no change.

Phase 47d-8 (GameOverScreen dead-end fix) complete. Defeat screen previously hid the "Continue" button — the only action was "Restart", so players who wanted to bail to WorldMap had to quit the app. **Fix**: `GameOverScreen._on_game_over` (campaign/heroic/iron path) now sets `continue_button.visible = true` with text "World Map" AND `restart_button.visible = true` with text "Restart", giving both exits. The endless path already showed both but got explicit labels for consistency. Summary line gains a "Mode: X" prefix so the player sees which mode they just lost. Victory path sets both button labels too, so a fresh state is guaranteed regardless of which end-state fired last. **Styling polish**: `Card.custom_minimum_size.x` bumped 300→480 so summaries with damage breakdown don't wrap awkwardly. `_show()` now mode-codes the title color — green for "Victory", warm red for "Defeat"/"Game Over", theme default otherwise.

Phase 47d-7 (TowerCombat chassis + TowerPlacer data-override) complete. Fixes the "Ice Tower has data=null, doesn't shoot" bug introduced by 47d-1. **Root cause**: Phase 47d-1 added `tower_scene: PackedScene` to `TowerData`, so `tower_archer.tres` now references `TowerArcher.tscn` — but `TowerArcher.tscn` still bakes `data = ExtResource(tower_archer.tres)`. Circular reference. Godot's resource loader can leave one side as `null` during load, especially for a fresh tower that never pre-cached (Ice). Even when the cycle resolves, instantiating `TowerArcher.tscn` for the Ice Tower produced a tower with **Archer's data baked in** — data-driven modularity broken. **Fix (two parts)**: (1) new `towers/TowerCombat.tscn` — a bare combat chassis with `base_tower.gd` + a `RangeArea` and zero baked data. All four combat towers (`archer`/`mage`/`artillery`/`ice`) now point `tower_scene` at this one scene, eliminating every circular ref. The old per-tower scenes (`TowerArcher.tscn` / `TowerMage.tscn` / `TowerArtillery.tscn`) are unused vestiges now, safe to delete later. (2) `TowerPlacer._on_build_requested` now executes `tower.data = entry.data` AFTER `instantiate()` and BEFORE `add_child()`, so `base_tower._ready()` sees the right `data` regardless of what the scene hardcodes. This makes one chassis serve N data-driven towers — the correct modularity claim. **Barracks exempt**: `TowerBarracks.tscn` has its own structure (FlagArea + soldier plumbing), so `tower_barracks.tres` still references its own scene. Future non-combat towers will get a second bare chassis as needed.

Phase 47d-6 (Ice Tower + base-level status effects) complete. First tower added under the new Phase 47d-1 "single-file" contract, proving the modularity claim. **Two supporting changes** needed for a slow-at-L1 archetype: (1) `TowerData` gained `on_hit_slow_factor` / `on_hit_slow_duration` / `on_hit_stun_duration` fields that mirror `TowerUpgradeData`'s, so base-level towers can carry status effects without a dummy L1 upgrade; (2) `BaseTower._build_on_hit_effect()` and `get_preview_stats()` plus `TowerUpgradeData.get_preview_stats(base)` all fall back to `data.*` when the active upgrade override leaves a field at 0, so the Ice Tower's base slow still applies — and still renders in the stats card — after any upgrade that doesn't explicitly override it. **New content files**: `towers/data/tower_ice.tres` (MAGIC damage, flying-capable, 30% slow for 1.0s at L1, reuses `TowerArcher.tscn` since both are BaseTower instances), `projectiles/IceShard.tscn` (Arrow.gd + cyan tint — same pattern as `MageBolt.tscn`). **L2 upgrade "Frostbite Tower"** doubles damage to 6, bumps range 380→425, adds attack speed, strengthens slow to 50% for 1.5s. **Cosmetic**: new `"snowflake"` case added to `TowerIconButton._draw_glyph` (6-spoke snowflake with forked tips + center hub). **One-file add proven**: the tower required exactly one `preload` line added to `ContentRegistry.towers` — no `TowerPlacer` or other registration edits. The user needs to open the new Loadout picker to equip it since the default 4-tower loadout predates this addition.

Phase 47d (tower loadout system) complete. Players pick their towers pre-level; in-game build ring shows 6 evenly-angled slots (4 filled from loadout + 2 progression-locked padlocks). Adding a new tower is now a **one-file change**. Five sub-phases:

- **47d-1 — Data consolidation.** `TowerData.tower_scene: PackedScene` + `TowerData.pictogram: String` fields added. The four shipping `.tres` files populated. `TowerPlacer._SCENE_MAP` deleted — scene resolved via `entry.data.tower_scene` instead. `TowerIconButton._draw_pictogram` extracted a `_draw_glyph(glyph, white, dark)` helper that dispatches on the new `pictogram` string key ("bow", "star", "cannon", "shield", "padlock", "generic"). Match cases renamed from `tower_*` to glyph keys so multiple towers can share art.
- **47d-2 — GameState loadout state.** `const TOWER_SLOT_MAX = 6`, `var tower_slot_cap = 4`, `var selected_tower_ids: Array[String]` defaulting to the four launch towers. `get_loadout_towers() -> Array` filters by cap + unlock with an "all unlocked" fallback so a blank save never shows an empty ring. `set_loadout_slot(idx, tid)` handles the no-duplicates swap rule. `reset_loadout_to_default()` for the UI's reset button. SaveManager plumbs `selected_hero_id` / `selected_tower_ids` / `tower_slot_cap` save + load.
- **47d-3 — Build ring draws 6 slots, last ones locked.** `TowerRadialMenu._open_build_ring` now always creates `TOWER_SLOT_MAX` slots at `-PI/2 + (TAU/6) * i` angles. Slots `[0..cap-1]` use loadout towers; slots `[cap..MAX-1]` use `TowerIconButton.setup_locked()` which renders a padlock glyph on a dim body and emits `locked_pressed` on tap. Handler fires `Toast.show_message("Unlock through progression")`. Empty-but-unlocked slots (slot in cap range but no tower assigned) show the same padlock and hint "Set this slot in Loadout" so the player is pointed at the fix. 6 × 90px at 120px radius = ~35px edge-to-edge spacing, still readable.
- **47d-4 — `LoadoutPickerScreen.tscn` + `.gd`.** New screen reached from the WorldMap "Loadout" button. Top-half **ring** mirrors the in-game build ring's `RING_RADIUS = 120` + `ICON_SIZE = 90` for visual continuity (Kingdom Rush's "common fate across rings" principle). Bottom-half **pool** is an `HFlowContainer` of every unlocked tower, each a regular `TowerIconButton` with a new `set_equipped(bool)` state that dims the icon and paints a green ✓ badge. **Interaction**: tap a ring slot to arm it (yellow glow, same vocabulary as in-game armed state); tap a pool tower to place it in the armed slot (or auto-fill the first empty slot if none armed); tap an already-equipped pool tower with no slot armed to unequip; tap a locked slot for a toast. Placement respects the no-duplicates swap rule via `GameState.set_loadout_slot`. Every change calls `SaveManager.save_game()` — no explicit Save button, Back just goes home. "Reset to Default" restores the 4 launch towers.
- **47d-5 — WorldMap + LoadoutScreen integration.** New "Loadout" button added to the WorldMap BottomBar next to "Talents". `LoadoutScreen.tscn` replaces the old hardcoded "Towers: Archer, Barracks" label with a live `TowersRow` HBoxContainer populated at runtime from `GameState.get_loadout_towers()` using a new `TowerIconButton.setup_display(data)` (display-only — swallows taps, skips the cost badge). A "Change Loadout ►" button navigates to the picker. The Start flow unchanged.

**New autoload: `Toast`** — a minimal `CanvasLayer` at layer 99 with a single centered Label. `Toast.show_message("…")` fades in, holds 1.8s, fades out; kills any previous tween so rapid taps queue cleanly. Registered in `project.godot` autoloads (now 12).

**Modularity after 47d:** adding tower #5 = drop one `.tres` + one `preload` line in `ContentRegistry`. The `TowerPlacer._SCENE_MAP` and `TowerIconButton._draw_pictogram` tower-id sync traps are **gone**. Rolling out progression unlocks for slots 5/6 = `GameState.tower_slot_cap = 5` (or 6) wired to any trigger (star threshold, IAP, quest) — no UI changes needed.

Phase 47c (three-click root cause) complete. The Phase 47b "click-latency" fix treated a symptom, not the cause. Full audit revealed the real bug: `_rebuild_action_slots` calls `_clear_slots` which `queue_free`s every slot, but Godot defers `queue_free` to end-of-frame. For the rest of the current frame those old Controls stay in the tree and still receive `_gui_input`. If `gold_changed` fires from an enemy kill between the player's arm-tap and commit-tap, the rebuild creates fresh slots on top of the queued-for-free ones — and the commit tap's touch event can route to the **old** slot (still alive one more frame), where `_armed_slot != slot` → re-arms instead of commits. Next tap hits the new slot, arms it, then a third tap finally commits. 47b's `_capture_armed_key`/`_rearm_by_key` preserved armed state across rebuild but didn't fix the underlying zombie-slot race. **Proper fix**: action-ring gold changes now do an **in-place affordability refresh** via new `_refresh_action_affordability()` — iterates existing slots, computes each gold-gated action's cost from the tower (`get_upgrade_cost_to(level+1)` for `"upgrade"`, `get_branch_cost(idx)` for `"branch"`), calls `set_enabled()` + new `RadialActionButton.set_badge_color()` in place. No queue_free, no race, `_armed_slot` stays valid. Target/sell/rally are gold-independent so the match in `_gold_cost_for_slot()` returns 0 and the slot is skipped. If an armed slot drops below cost during refresh it disarms cleanly. Defense-in-depth: `_clear_slots` now sets `mouse_filter = MOUSE_FILTER_IGNORE` on slots before `queue_free`, so any other call site (target cycle, menu dismissal) can't leak zombie input for a frame either. 47b's dead helpers (`_capture_armed_key`, `_rearm_by_key`) removed. **Modularity note for future action types**: a new gold-gated action only needs to add its case to `_gold_cost_for_slot()`; a new non-gold action needs no changes at all. Action slots still must have stable `(action_id, payload)` values so multiple rebuilds don't shuffle identity.

Phase 47b (upgrade-preview hardening) complete. Two fixes to the tower radial menu's upgrade flow. **Click-latency bug ("three taps to commit")**: `TowerRadialMenu._on_gold_changed` was calling `_rebuild_action_slots()` — which wipes `_armed_slot = null` — whenever gold changed while the action ring was open. An enemy drop between the player's arm tap and commit tap would reset the armed state, so the second tap re-armed instead of committing (needed a third tap). Fix: new `_capture_armed_key()` / `_rearm_by_key()` pair remembers `(action_id, payload)` across the rebuild and re-arms the equivalent fresh slot if it still exists and is enabled (if gone / no longer affordable, falls through to the built-tower view — correct disarm behavior). Added `RadialActionButton.is_enabled()` as the public accessor. **Upgrade-preview stat coverage + color coding**: the diff card previously showed only `Dmg / Rng / Spd` in a single flat color, hiding major branch differences (Ranger's slow, Artillery's AoE radius). New structured `get_preview_stats() -> Array[Dictionary]` accessor on `BaseTower` / `TowerBarracks` / `TowerUpgradeData` returns `[{label, value, fmt}, ...]` rows, emitting extra columns (AoE / Slow % / Dur / Stun) only when nonzero so vanilla towers stay uncluttered. `TowerStatsCard.StatsLabel` converted from `Label` → `RichTextLabel` (bbcode_enabled, fit_content) so the new `_diff_bbcode()` can emit per-stat `[color=#5feb6f]`/`[color=#eb5f5f]` wrappers — green on improvements, red on regressions, default text color on unchanged, green label-only for newly gained abilities. Built-tower view and build-preview still use plain text via `_set_stats_plain()` → BBCode escape. `SlowT` shows as "Dur" to keep the column compact.

Phase 47 (combat visuals — Polish + Identity, Punchy KR intensity) complete. Procedural `_draw()` pass that targets the "combat feels quiet / all units swing identically / every hit looks the same" problem without changing art direction. **New EventBus signals:** `hit_landed(target, source, amount, dmg_type)`, `enemy_damaged(enemy, amount, dmg_type)`, `soldier_fell(soldier, facing_dir)`. Emitted inside each unit's `take_damage` / soldier `_die`, consumed by `VFXSpawner`. **New VFX scripts** (all plain `extends Node2D` with `class_name`, spawned via `ScriptName.new()` — no .tscn needed): `vfx/HitSparkVFX.gd` (radial spark burst styled by damage type: PHYSICAL yellow lines / MAGIC cyan lines + shockwave half-ring / TRUE 4-point gold star), `vfx/EnemyDeathDrift.gd` (snapshots `UnitVisualData`, drifts + rotates 0.35s along hit direction while fading), `vfx/SkillCastFlare.gd` (expanding ring under hero on skill cast, color keyed by skill_name in `VFXSpawner._SKILL_FLARE_COLORS` lookup). **Swing-arc upgrade:** `UnitVisualDrawer.draw_swing_arc_trail` replaces `draw_swing_arc` — 4 ghost copies angularly trailed behind the primary with descending alpha and radius. `_draw_weapon_shape` branches on new `UnitVisualData.weapon_type` enum (SWORD default / SPEAR two-point thrust / STAFF tight 30° flick / CLAWS three-rake); hero_mage updated to STAFF. **Status-ring polish:** `UnitVisualDrawer.draw_status_ring(radius, color, dashes, rotation_t, width)` replaces the static slow/stun arcs — 8-dash cyan spinning CW for slow, 6-dash yellow spinning CCW for stun. `_status_ring_t` accumulator in `BaseEnemy._physics_process` drives rotation while effects are active. **Telegraph inhale:** new `BaseEnemy._inhale_offset()` pulls the body `-dir * 4.0 * smoothstep(0.15, 0.0, _combat_cooldown)` during the last 150ms pre-strike; passed as `offset` into `draw_unit` / `draw_hit_flash` so the telegraph arc stays anchored while the body rears back. **Soldier fall-over death:** `BaseSoldier._die` replaces instant `queue_free` with a parallel tween (rotation → ±90°, modulate.a → 0 over 0.4s) then frees. **Squad-color bands:** `UnitVisualData.accent_band_color` (zero-alpha default preserves existing visuals); `UnitVisualDrawer.draw_unit` draws a 3px ring/rect just inside the outline when alpha > 0. `TowerBarracks._spawn_soldier` duplicates `SoldierData` + `UnitVisualData` per-soldier (`sd.duplicate(true)`) and stamps `accent_band_color = _squad_color()` — deterministic hash of `global_position` so it's stable across save/load. **Camera shake:** `GameCamera.add_shake(amount, duration)` applies a decaying `offset` perturbation in `_process`; `VFXSpawner._on_enemy_damaged` triggers `add_shake(2.0, 0.12)` on `enemy.data.is_boss`. All new VFX respect `VFXSpawner.clean_view`. All per-frame work is O(1) per instance — no `get_nodes_in_group` or distance loops added. Tactical pause freezes every new tween/process path (default `PROCESS_MODE_INHERIT`).

Known bugs: none
