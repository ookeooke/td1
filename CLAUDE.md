# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fantasy Tower Defense (Kingdom Rush Style)
> Godot 4.6.2 | GDScript | Android + iOS + PC | Touch + Mouse

---

## Working here

- [STATUS.md](STATUS.md) — current focus, in-flight work, next steps. Read first.
- [SESSIONS.md](SESSIONS.md) — chronological log of what's been done and why. Append a dated entry at the end of every working session.
- **This file (CLAUDE.md)** — invariants only (rules, interfaces, contracts). Do not log session notes here.
- [balance/BALANCE.md](balance/BALANCE.md) — design intent for tuning: target g/DPS curves, hardness baselines, the Naked Baseline invariant. Read before any balance change. Folder is dev-only (stripped from production exports).
- `git log` — diffs and short commit messages.

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
7. **All IAP-locked content checked through UnlockManager's type-specific methods.** `is_tower_unlocked(tid)` / `is_hero_unlocked(hid)`. No global `is_unlocked(id)` — type-scoped only. Never hardcode unlock states. (See SESSIONS.md Phase 46c for the collision bug that forced this.)
8. **All save/load through SaveManager only.** No other script touches the save file.
9. **Before changing anything working, explain why the change is needed.** Then wait for approval.
10. **New content is authored as data, not code.** Every new hero / soldier / enemy / skill / ability / item is a `.tres` resource composed from existing base classes + AbilityData components. Only subclass when the variant needs genuinely new *structural* behavior (collision layer, multi-phase state machine, projectile vs. melee).
11. **One primitive for mechanics: AbilityData.** Every "verb on a unit" — passives, on-hit effects, auras, items, talents, endless modifiers, status effects — is an `AbilityData` Resource with a `Trigger` and an `apply(owner, ctx)` override. `AbilityHost` dispatcher is owner-agnostic.
12. **Stable content IDs, scoped by type, matching filename.** Every Resource has a `*_id: String` field. IDs are keys in save files, unlock checks, leaderboard payloads. **Never rename an ID after first release.** Convention: `snake_case`, scoped by type (`hero_warrior`, `tower_archer`, `enemy_basic`), and **must equal the filename basename** (`tower_archer.tres` holds `tower_id = "tower_archer"`). Enforced at boot by `ContentRegistry._validate_ids()` — any drift prints `[ContentRegistry/DRIFT]` lines in the output panel.
13. **Soldier rally positions are navmesh-snapped; soldier movement is direct straight-line.** Rally flag and every derived slot snapped via `NavigationServer2D.map_get_closest_point`. Movement is `velocity = (target - pos).normalized() * speed` — no `NavigationAgent2D`. Navmesh constrains **placement**, not **pathing**.
14. **Tower UI reads accessors, never `tower.data.*`.** All range/stats/sell/upgrade display goes through the Tower Indicator Interface (below). No `has_method` fallbacks, no per-class branches. Each tower owns its own `get_stats_line()`. Carve-outs: static display strings like `tower.data.tower_name`; build-ring UI operating on `TowerData` before any tower instance exists. Reading `.data.attack_range` on an upgraded tower silently shows the L1 stat — the interface prevents that class of bug.
15. **Tower scenes are bare chassis — never bake `data` into a tower `.tscn`.** Combat towers share `res://towers/TowerCombat.tscn`; Barracks use `res://towers/TowerBarracks.tscn`. `TowerData.tower_scene` references the chassis; `TowerPlacer._on_build_requested` assigns `tower.data = entry.data` after `instantiate()` and before `add_child()`. Baking `data = ExtResource(...)` creates a tres↔tscn circular reference that leaves `tower.data = null` at runtime. One chassis backs N towers. (See SESSIONS.md Phase 47d-7.)
16. **Content catalogs use `load()` at `_ready()`, not `preload()` at class body.** Arrays of cross-file content (`.tres` / `.tscn`) in autoloads like `ContentRegistry` must be populated via `load()` inside `_ready()`, never `preload()` at class scope. Godot 4.4+ has a shared-script race ([issue #105021](https://github.com/godotengine/godot/issues/105021)) that corrupts the first item in any preload array whose resources share a `class_name`-registered script (e.g. `TowerData.gd` shared across all 5 tower .tres files). `load()` runs after every autoload script has compiled, so no race is possible. Boot cost ≈10 ms, imperceptible. Revert this rule only when Godot's release notes mark #105021 fixed. (See SESSIONS.md Phase 48 abandoned attempt for the full diagnostic trail.)
17. **Never purge `.godot/` while debugging.** The cache holds import metadata that Godot self-heals between boots — closing and reopening the editor a second time is the documented fix for transient loader races ([issue #97684](https://github.com/godotengine/godot/issues/97684)). Purging forces every boot to be a cold start, which re-triggers any races the cache was masking. Only purge when (1) migrating Godot versions, (2) `.godot/` is visibly corrupted (zero-size files, missing `uid_cache.bin`), or (3) working code is already committed so the nuke is reversible. Never purge as a debugging reflex.
18. **Balance numbers reference [BALANCE.md](balance/BALANCE.md), not intuition.** All tuning targets (g/DPS bands, hardness curves, mode multipliers, the Naked Baseline floor) live in `balance/BALANCE.md`. Read targets before editing `.tres` files; update BALANCE.md after editing so the doc never lags the data. Verify changes via the Test Range (live damage tally) and Balance Report (cross-run aggregates) — both under `balance/`. Never invent a number from intuition — every change must reference a target band. The original audit-by-LLM produced phantom values (Archer L2 damage, Ice L2 damage); always read `.tres` files directly, never paraphrase them.
19. **Early-call advances waves with overlap, not just gold.** Calling the next wave early starts it while the previous wave's enemies are still on the map. Bonus gold is the reward; concurrent-wave pressure is the cost. Send-Wave button is visible the *entire* countdown (KR-canonical) — bonus = `min(seconds_remaining, early_call_window_sec)` so unlimited gold isn't possible from long countdowns. The window caps *bonus magnitude*, NOT *button availability* — gating button visibility creates dead-time ("where's the button?") which is what we explicitly want to avoid. [WaveManager.gd](autoloads/WaveManager.gd) decouples *spawning complete* (triggers `_on_spawning_complete`, starts next countdown) from *wave cleared* (triggers `_maybe_pay_bounty`, fires `wave_completed`). Per-wave alive counts live in `_alive_per_wave: Dictionary` so the right bounty pays at the right moment when waves overlap. Each spawned enemy is meta-tagged with `wave_index` at spawn time. Never collapse the two gates back into one — overlap pressure is what makes the early-call decision interesting. Without it, calling early is free money and players cheese it every time.
20. **Per-content-type state lives keyed by `<content>_id`, never one var per content instance.** Adding a 10th hero or 6th tower must require zero autoload changes — only a new `.tres` + `ContentRegistry` registration. State that varies by content (hero XP, hero talents, equipped skills, level stars, best times, encyclopedia discovery) lives in a `Dictionary` keyed by `hero_id` / `tower_id` / `level_id` / `content_id` on the appropriate state autoload. Subrules:
    - **Per-content-id dicts, not per-content vars.** `MetaProgression.hero_progress: Dictionary[hero_id → {...}]`, never `warrior_xp: int`.
    - **Self-healing reads.** Any read that resolves a content_id MUST drop entries pointing at content the catalog no longer authors (rename / removal). Pattern: `LoadoutState.get_equipped_skills` purges stale skill_ids on read AND persists the cleaned form so the dict converges. Skip the purge if `ContentRegistry` returns empty (early boot guard).
    - **Defaults from `ContentRegistry`, not hardcoded.** `_default_equipped_for(hero_id)` reads the hero's authored skills. New defaults follow the same pattern — never enumerate hero_ids in code.
    - **Save format additions append; never reshape.** A new content type → a new top-level key in the save JSON. Never restructure existing keys (that breaks saves and forces a `SAVE_VERSION` bump). Missing keys default at load time.
    - **One EventBus signal per state change.** `hero_skill_equipped`, `gold_changed`, `meta_gold_changed`, etc. UI listens; UI doesn't poll. New state → new signal. Cheap to add, expensive to retrofit.

    **State assignment table** (where to put what):

    | Content type | State location | Key |
    |---|---|---|
    | Hero (XP, level) | `MetaProgression.hero_progress` | `hero_id` |
    | Hero (equipped skills) | `LoadoutState.hero_equipped_skills` | `hero_id` |
    | Hero (purchased talents) | `MetaProgression.hero_talents` | `hero_id` |
    | Tower (loadout pick) | `LoadoutState.selected_tower_ids` | order-positional |
    | Tower (unlocked) | `UnlockManager` (already type-scoped) | `tower_id` |
    | Level (stars / best time / endless score) | `MetaProgression.{level_stars, level_best_times, level_endless_best_scores}` | `level_id` |
    | Encyclopedia (discovered) | `MetaProgression.encyclopedia_unlocked` | `content_id` array |
    | Item (instances in bag) | `InventoryManager` (already separate) | `ItemInstance.uid` |

	Adding a new content type (pets, mounts, world-map flags) = one new dict on the appropriate autoload, three helpers (`get_*`, `set_*`, `_default_*_for`), one EventBus signal. Mirrors `LoadoutState.hero_equipped_skills` end-to-end. (See SESSIONS.md "2026-05-01 — GameState split" for the rationale.)
21. **Painted backgrounds are L5+ only, opt-in via a `MapBackground` Sprite2D child.** When a level scene has a `MapBackground` Sprite2D under its root, BaseLevel auto-suppresses the procedural BG fill, decorations (trees/bushes/flowers), and path strokes — the painting owns those layers. (BG fill must be suppressed because BaseLevel's `_draw()` runs at root z_index=0 and would overdraw any Sprite2D child regardless of the sprite's negative z_index.) Procedural borders stay by default so zoom-out past the painting still looks framed. Adding a `MapBackgroundOverflow` Node sibling also suppresses borders, for paintings that include their own framing past `map_bounds`. Tower spots always render (interactive build cue). **Never retrofit painted backgrounds onto L1–L4** — they stay 100% procedural forever. Reasoning: (a) shipped/balanced levels shouldn't be reskinned without scoped re-verification, (b) the procedural look is the deliberate art direction for early game, (c) keeping the procedural draw branches load-bearing on multiple shipped levels prevents bit-rot. Image lives at `levels/backgrounds/level_<N>_bg.<ext>`; native size 2000×1160 for 1:1 placement against the default `map_bounds`. Set `MapBackground.z_index = -50` so it draws beneath spots.

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
| Genre | Tower defense + hero unit + active per-hero skills |
| Platform | Android, iOS (primary) + PC (secondary) |
| Input | Touch + Mouse via "Emulate Touch From Mouse" |
| Tower placement | Fixed pre-defined spots only, branching upgrade at level 3 |
| Heroes | One at a time, chosen before level, gains XP from kills |
| Soldiers | Barracks spawn soldiers that block ground enemies |
| Hero skills | Per-hero loadout (2 active slots) chosen on WorldMap, cast via the in-level portrait cluster |
| Game modes | Campaign, Heroic, Iron (per level), Endless |
| Progression | Stars, permanent upgrades, hero unlocks, tower unlocks, talent tree |
| Monetization | Heroes and towers as IAP (PurchaseManager is a stub) |
| Save system | Full JSON persistence via SaveManager |

---

## Autoloads (20)

| Name | Purpose |
|---|---|
| EventBus | Signals only, zero logic |
| DisplayUtils | Mobile screen safe-area math (`get_safe_insets()`) |
| MetaProgression | Cross-run state — stars, upgrades, talents, hero XP, leaderboard, meta_gold, encyclopedia |
| RunState | Per-run volatile — gold, lives, score, wave, current_mode/level_id, damage attribution |
| LoadoutState | Pre-level picks — selected hero, tower loadout (4-of-6), per-hero equipped skills |
| WaveManager | Multi-path spawn + endless generation |
| DamageCalculator | All damage math: PHYSICAL (armor), MAGIC (magic_resist), TRUE |
| InventoryManager | Equipped + unequipped items per hero, starter-gear bootstrap |
| SaveManager | All persistence (JSON) |
| UnlockManager | IAP + unlock state |
| SceneManager | Scene transitions with fade |
| ContentRegistry | Master index of all content .tres |
| LootRoller | Affix rolling + rarity tier resolution for new item drops |
| LootDropper | Per-enemy + boss drop tables, dispatched on enemy_died |
| ItemPickupManager | World-space item-on-ground state, magnet pickup |
| PurchaseManager | IAP client stub (auto-succeeds) |
| VFXSpawner | FloatingText + DeathVFX on EventBus signals |
| SoundManager | SFX pool + music player (graceful missing files) |
| Toast | Transient on-screen messages (`Toast.show_message("…")`) |
| RunStats | Per-run telemetry → `user://run_stats.json` (last 50 runs, opt-in via Settings later) |

**State autoloads — which holds what** (split from the old `GameState` on 2026-05-01 — see SESSIONS.md):

- **`RunState`** is volatile and cleared by `reset_for_level()`. Holds gold/lives/score/wave/stars_earned, current_mode, current_level_id, round_damage_*. Reads `MetaProgression.get_upgrade_bonus(MOD_STARTING_GOLD)` to apply meta-upgrade gold on level start.
- **`LoadoutState`** is the player's pre-level picks. Persisted, but distinct from progression. Holds selected_hero_id, selected_tower_ids, tower_slot_cap, hero_equipped_skills. Reads `MetaProgression.get_hero_level()` to filter level-gated skills.
- **`MetaProgression`** is everything that survives a run: stars, mode-completion, purchased upgrades + cached modifiers, hero talents, hero XP/level, best times, endless leaderboards, meta_gold, encyclopedia, unlocked_content.
- **`DisplayUtils`** is layout helpers — has nothing to do with game state.

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

**Unlock API** — `UnlockManager` type-scoped only: `is_hero_unlocked` / `is_tower_unlocked`, plus type-agnostic `unlock(id)`. `ProductData.unlock_type` dispatches in ShopScreen. Three unlock paths: explicit (IAP → `MetaProgression.unlocked_content`), free (`requires_unlock == false`), star-threshold (`UnlockManager._star_thresholds`).

**Damage attribution** — `BaseEnemy.take_damage(amount, type, source)` routes the overkill-capped `actual` into `RunState.record_round_damage(source, amount)`. Dispatched by `source is BaseTower / BaseHero / BaseSoldier` into `round_damage_towers` (keyed by stable run-scoped `_damage_key`, survives sell) + `round_damage_hero` / `_soldiers`. Cleared in `RunState.reset_for_level()`. `GameOverScreen` renders the top-5 tower leaderboard + aggregate rows on victory, defeat, and endless Game Over.

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
   └── SkillBar._input        — consumes if skill targeting armed

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
- Phases 1–3: `set_input_as_handled()` to claim.
- Phase 4 (map taps): connect to `EventBus.map_tap_confirmed`, check `claim.claimed`.
- Never add new `_unhandled_input` handlers for touch — they conflict with the camera.
- **Touch-only gotcha:** `emulate_touch_from_mouse=true` in project.godot means every PC click fires BOTH `InputEventMouseButton` AND `InputEventScreenTouch`. Handle `InputEventScreenTouch` / `InputEventScreenDrag` only, never both — otherwise stateful flows (two-step commits, toggles) double-fire on PC.

---

## UI on CanvasLayers

All UI is on CanvasLayers, independent of Camera2D. **Must set `follow_viewport_enabled = false`** on every UI CanvasLayer to prevent camera zoom from distorting Control layout.

| Layer | UI |
|---|---|
| 0 | HUD (gold, lives, wave, speed, pause) |
| 6 | SpawnIndicator (screen-edge spawn arrows) |
| 8 | SkillBar (bottom-right portrait cluster + 2 skill slots) |
| 10 | TowerRadialMenu (radial ring at spot: build / upgrade / sell / target / rally) |
| 20 | PauseMenu, GameOverScreen |

**Safe area:** `SafeAreaMargin.gd` (extends MarginContainer) sits at the root of HUD and SkillBar CanvasLayers. Sets `theme_override_constants/margin_*` from `DisplayUtils.get_safe_insets()` — Godot's layout engine pushes all children inward. Recalculates on window resize. Safe area math uses `DisplayServer.screen_get_size()` (NOT `window_get_size()`) because `get_display_safe_area()` returns screen-space coordinates.

**SpawnIndicator:** Replaces world-space SpawnMarkers. Projects spawn world positions to screen coordinates via `get_canvas_transform()`, draws arrows at screen edges when off-screen.

---

## Radial Menu Interaction — Two-Step Commit

`TowerRadialMenu` uses a **peek-then-confirm** flow so mobile players can compare options before spending gold. Same UX on touch and mouse (no hover previews — would be ambiguous on touch).

**Rules:**
- First tap on a slot **arms** (highlights + previews stats + range rings).
- Second tap on the **same** armed slot commits (build / upgrade / branch-pick / sell).
- Tap a **different** slot → re-arms.
- Tap the backdrop → dismisses, no commit.
- **Dismiss-on-commit:** build/upgrade/branch/sell dismiss the menu; player re-taps spot for next action (prevents chained upgrades from a lingering finger).
- **Single-tap carve-outs:** `target` (cycles FIRST → STRONG → WEAK, non-destructive) and `rally` (enters flag-placement mode) fire on one tap.

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

- **Capacity on blocker data**: `SoldierData.max_block_targets` (default 1), `HeroData.max_block_targets` (default 2; mage overrides to 1).
- **Enemies allow any number of blockers**: `BaseEnemy._blockers: Array[Node]`; COMBAT iff non-empty. Counter-attacks focus `_blockers[0]` (oldest engager, stable telegraph).
- **Split rule**: `BaseSoldier._try_engage` + `BaseHero._pick_split_target_in_area` prefer FEWEST current blockers (ties broken by distance). Friendlies spread across threats; pile on a lone target.
- **Hero auto-claims extras** up to capacity while in COMBAT; releases via `_prune_blocks_out_of_range`.
- **Release points**: death, rally-move (soldier), tap-to-move (hero), target loss.
- **Hero engage radius is decoupled from attack_range**: `HeroData.engage_radius` controls the *block-claim* circle (where enemies halt and engage as melee); `HeroData.attack_range` controls *weapon reach* (projectile spawn, AoE pivot, when COMBAT state triggers). Two numbers because the jobs are independent: a Mage at attack_range=350 with engage_radius=55 shoots from far but only locks enemies that walk into face contact; a Knight at 75/55 walks up and swings. Default when unset (0): `min(attack_range, BaseHero.DEFAULT_ENGAGE_RADIUS=60)`. Override only when the archetype needs a divergent value (sniper = 0 to never block, tank = 90 for bigger presence, dragon = 110 for a large body). Mirrors the `SoldierData.melee_range` ≠ weapon-reach pattern.

---

## Hero Spawn Marker

Each level scene must include a `Marker2D` named `HeroSpawn` as a direct child of the level root. `Level1.gd.get_hero_spawn_position()` reads it; `Main.gd._spawn_hero()` queries the level for the position. Drag the marker in the 2D editor to change where the hero appears at game start AND after every respawn. Missing marker → `BaseHero._respawn()` falls back to `Vector2(960, 540)`.

---

## Hero Death and Respawn

- **Damage**: in `COMBAT`, engaged enemy counter-attacks on its `attack_speed` cadence via `BaseHero._tick_incoming_attack`. Flying enemies skip. Strike range: `ENEMY_STRIKE_DISTANCE = 60px`.
- **Death**: `_die` sets DEAD, hides hero, emits `hero_died`, schedules `create_timer(respawn_time) → _respawn()` (pause honored).
- **Respawn**: teleports to `HeroSpawn` marker, restores full HP, emits `hero_respawned`. HUD shows "Respawn: %.1fs".

---

## Adding New Content — Checklist

**New enemy:**
1. Create `enemies/data/enemy_foo.tres` (EnemyData) + `visual_foo.tres` (UnitVisualData)
2. Set `enemy_id = "enemy_foo"` (stable, never rename)
3. Add abilities as sub-resources if needed (e.g. RegenAbility, explode-on-death)
4. For flying: set `is_flying = true` (uses EnemyFlying scene). For boss: use BaseBoss + BossPhaseData
5. Register in `ContentRegistry.gd` → `enemies` array
6. Reference `enemy_id` in wave `.tres` files

**New tower (one-file add since Phase 47d-1):**
1. `towers/data/tower_foo.tres` (TowerData) with `tower_id = "tower_foo"` (must match filename), `tower_scene = res://towers/TowerCombat.tscn`, `pictogram` (glyph key into `TowerIconButton._draw_glyph`: `"bow"`, `"star"`, `"cannon"`, `"shield"`, `"snowflake"`, `"generic"`).
2. `level_upgrades` (L2, L3) and optional `level_3_branches` (A, B).
3. Barracks also: `soldier_scene`, `soldier_data`; upgrades may override via `TowerUpgradeData.soldier_data_override` / `soldier_rally_range`.
4. Register in `ContentRegistry.gd` → `towers` array. Done.
5. New glyph? Add one `"foo":` case to `ui/TowerIconButton.gd::_draw_glyph()`. Otherwise falls back to generic circle.

**Tower-add pitfalls** (see SESSIONS.md Phase 47d-6 / 47d-7):
- No per-tower `.tscn` — always use the shared `TowerCombat.tscn` chassis (CORE RULE 15).
- Status effects (slow/stun) live on BOTH `TowerData` and `TowerUpgradeData` — upgrade fields at 0 fall back to base.
- `TowerIconButton.setup()` is build-ring only. Use `setup_pool()` for loadout picker, `setup_display()` for read-only.
- Don't hand-write `uid://...` strings.

Every new tower class MUST implement the full Tower Indicator Interface (CORE RULE 14 + table above). Once implemented, all UI works without modification.

**New ability:**
1. Create `systems/abilities/MyAbility.gd` extending `AbilityData`
2. Override `apply(owner, ctx)`
3. Add as sub-resource in any unit's `.tres` → `abilities` array

**New hero skill:**
1. Create `heroes/skills/my_skill_data.gd` extending `SkillData`
2. Override `apply(hero, target)`
3. Create `heroes/data/skills/skill_foo.tres` and reference in hero `.tres` → `skills` array

**New level (template-based, since Phase 48):**

Levels stay as editor-visible `.tscn` files (CORE RULE: human drags Curve2D handles + Marker2D positions in the Godot 2D editor). Generation produces a draft from a topology template; the human hand-tunes everything else.

1. **User specs the level in chat** — minimal: number of spawn points, number of paths, approximate spot count, optional topology hint, target hardness. Example: *"Generate L3 — 1 spawn, 1 path with central ring detour, 8 spots, target_ppt 4."*

2. **Pick the closest template** in `res://levels/templates/`:
    | Template | Topology |
    |---|---|
	| `template_single_serpentine.tscn` | 1 spawn, 1 path "main" with 4 S-curves, 6 spots — focused gauntlet |
	| `template_two_path_converge.tscn` | 2 spawns, 2 paths "north"/"south" converging at the right base, 8 spots |
	| `template_three_path_classic.tscn` | 3 spawns, 3 paths "left"/"top"/"bottom", 8 spots — Kingdom Rush three-front |
	| `template_ring_detour.tscn` | 1 spawn, 1 path "main" with 3/4 ring around map center, 8 spots |

3. **Copy and rename:**
    - `template_*.tscn` → `levels/Level<N>.tscn` — change root node name, change script ext_resource path from `BaseLevel.gd` to the new `Level<N>.gd`
    - `template_*_waves.tres` → `levels/level<N>_waves.tres`
    - Create `levels/Level<N>.gd` (4-line subclass — `extends BaseLevel` + override `_level_id()` and `_wave_list_path()`)

4. **Adjust the spec parameters** — curve waypoints, spot positions, hero spawn, spot count. Edit waypoint coordinates directly in the `.tscn`'s `Curve2D` `_data.points` array, OR open the scene in Godot and drag handles visually.

5. **Register in `ui/world_map/level_list.tres`** — add a `level_<N>` entry pointing at the new `scene_path`, `wave_list_path`, with `min_ppt`, `target_ppt` matching the user's hardness target.

6. **Place the marker on the WorldMap** — open `ui/world_map/WorldMapView.tscn`, add a `Marker2D` named exactly `level_<N>` (must match the `level_id` from step 5) under the `LevelMarkers` Node2D, and drag it to the desired position. Mirrors the `TowerSpots → Spot1` pattern: node name == content_id, position lives in the scene. WorldMapView reads it at runtime; missing marker = `push_warning` and the level is skipped.

7. **Author the wave file** — replace the placeholder waves with real content. Use the existing wave files (`level1_waves.tres`, `level2_waves.tres`) as references.

8. **(Optional, L5+) Painted background.** Drop the source image into `levels/backgrounds/level_<N>_bg.png` (or `.webp`). Open `Level<N>.tscn`, add a `Sprite2D` child named exactly `MapBackground` directly under the root, set its `texture` to the image, `z_index = -50`, drag/scale to align with your authored paths. BaseLevel auto-suppresses procedural decorations + path strokes (CORE RULE 21). Add a sibling `MapBackgroundOverflow` Node if the painting extends past `map_bounds` and supplies its own framing. **L1–L4 stay procedural — do not retrofit.**

**Template invariants** — every template `.tscn` MUST have:
- Root node attached to `res://levels/BaseLevel.gd` (no per-template script)
- `Paths` Node2D parent with named Path2D children (the names become wave `path_id` strings)
- `TowerSpots` Node2D parent with Marker2D children (names = spot_ids)
- `HeroSpawn` Marker2D directly under root
- `SpawnMarkers` Node2D parent with `SpawnMarker.tscn` instances, each `path_id` matching a Path2D node name
- `GridManager` Node + `SpotInputManager` Node — the runtime systems Main.tscn wires up
- A NavigationPolygon covering `map_bounds`

**Don't propose data-driven `.tres` levels (LevelBuilder + LevelData schema).** That refactor was explicitly rejected — it would take levels away from the visual editor, which is non-negotiable. Templates + BaseLevel + per-level subclass is the chosen path.

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
One Path2D per direction (`left` / `right` / `top`). `WaveManager.spawn_enemy` picks one of 3 lanes for non-boss enemies via `PathFollow2D.v_offset ∈ {-LANE_SPACING, 0, +LANE_SPACING}` (±50px). `rotates = false` so v_offset shifts world Y (reads as above/on/below the road for horizontal paths). **Bosses ride centered.** Vertical-running paths on future levels will need `rotates = true`.

- **Spawn timing jitter** — ±0.25s per interval in WaveManager.
- **Boss detection** — `WaveManager._BOSS_SCENES` single source of truth.
- **Visual editing** — Level1.gd is `@tool`; paths render as brown polylines in the editor.

**Adding a direction to a new level:** create one Path2D under `Paths/` named with the base id (e.g. `east`). Reference the id in wave `.tres` spawns.

### NavigationPolygon per level
`Level1.tscn` has a `NavigationRegion2D` with a `NavigationPolygon` covering `map_bounds`. Future levels cut holes for terrain obstacles (rocks, rivers).

---

## Project history

Chronological phase-log is in [SESSIONS.md](SESSIONS.md) — what was built, why, and what broke. Current focus is in [STATUS.md](STATUS.md).
