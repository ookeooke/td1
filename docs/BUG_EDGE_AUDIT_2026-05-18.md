# Bug & Edge Audit — 2026-05-18

Whole-codebase hunt: 3 parallel exploration passes (combat/unit, autoload/save,
UI/input) → ~26 raw candidates → triaged + verified against source. Scope chosen
by user: **red tests only, no fixes; highest-severity confirmed, player-reachable.**

Regression suite: [tests/unit/test_bug_edge_audit.gd](../tests/unit/test_bug_edge_audit.gd)
— 10 cases, all currently **red**. Existing 193 tests stay green. Each test
asserts the *correct* contract; when a bug is fixed its test flips green and
becomes the regression lock — do not delete.

## Confirmed findings (the 10 red cases)

| # | Area | File:line | Severity | Repro | Fix sketch |
|---|---|---|---|---|---|
| 1 | UI lifecycle | [EquipmentScreen.gd:176-222](../ui/EquipmentScreen.gd#L176) | High (invariant) | Open HeroesHub→Equip, leave to Overview (hub `queue_free`s it); screen never disconnected its EventBus subs | Add `func _exit_tree()` disconnecting all 5 signals (mirror [HeroSkillsPage.gd:113-127](../ui/HeroSkillsPage.gd#L113)) |
| 2 | UI lifecycle | [EquipmentScreen.gd:191](../ui/EquipmentScreen.gd#L191) | High | `hero_selected` bound as an inline lambda — no stable Callable to disconnect even once #1 is fixed | Promote closure to a named method `_on_hero_selected(new_id)` |
| 3 | Progression | [MetaProgression.gd:648](../autoloads/MetaProgression.gd#L648) vs [:664](../autoloads/MetaProgression.gd#L664) | Wrong-behavior | Any mid-run level-up: a `hero_leveled_up` listener calling `get_hero_level()` sees the OLD level | Write `entry["level"]/["xp"]` before the emits, or emit after `_persist()` |
| 4 | Progression | [MetaProgression.gd:638](../autoloads/MetaProgression.gd#L638) | Wrong-behavior | Same root: `get_hero_xp()` during `hero_xp_gained` is pre-gain | Commit `entry["xp"]` before emit |
| 5 | Input (PC) | [TowerRadialMenu.gd:565-574](../ui/TowerRadialMenu.gd#L565) | Wrong-behavior | PC: `emulate_touch_from_mouse` makes one click fire mouse+touch; backdrop handles both → double `_dismiss()` | Handle `InputEventScreenTouch` only (CLAUDE.md input rule) |
| 6 | Navigation | [SceneManager.gd:29-50](../autoloads/SceneManager.gd#L29) | High (soft-lock) | `goto()` to a missing/typo'd path: `change_scene_to_file` fails, `_transitioning`+black STOP rect never reset, all later `goto()` early-return | `ResourceLoader.exists()` guard before transition, or timeout/abort that restores `_transitioning` + rect |
| 7 | Save | [InventoryManager.gd:113](../autoloads/InventoryManager.gd#L113) | Save-bloat | Load a pre-2026-04-29 save with `hero_equipment:{"":{…}}`; it's deep-duped verbatim and re-saved forever | Strip `""` key in `from_save_dict` (one-line guard) |
| 8 | State (CORE RULE 20) | [LoadoutState.gd:616-622](../autoloads/LoadoutState.gd#L616) | Latent (rule violation) | Purchased skill-tree node later removed from tree → `get_effective_ppt` skips it but never purges `MetaProgression.hero_skill_nodes` | Purge + persist on null `find_node` (mirror `get_equipped_skills` self-heal) |
| 9 | UI lifecycle | [EquipmentScreen.gd](../ui/EquipmentScreen.gd) | High | Quantified core of #1/#2: 5 `EventBus.*.connect`, 0 `.disconnect`, no `_exit_tree` | Same as #1 |
| 10 | Combat lifecycle | [base_hero.gd:373-375](../heroes/base_hero.gd#L373) | Latent (asymmetry) | `map_tap_confirmed.connect` has no `is_connected` guard while `combat_lull_changed` does; no `_exit_tree` | Guard symmetrically; document why node-bound autoload subs are safe if intentional |

Root-cause note: #3 & #4 are one defect (emit-before-commit) with two observable
symptoms; #1, #2, #9 triangulate one Preventive-Bug-Rule-3 violation from three
angles (method presence / handler shape / connect-count).

## Rejected — false positives (verified against source, NO test written)

- **SkillBar casting "broken on PC" (claimed CRASH).** `project.godot:65 emulate_touch_from_mouse=true` ⇒ PC clicks DO emit `InputEventScreenTouch`; [SkillBar.gd:218](../ui/SkillBar.gd#L218) handling only that is the *correct* documented pattern.
- **base_hero "signal reconnection leak on respawn".** [`_respawn()`](../heroes/base_hero.gd#L2372) reconnects nothing; Godot auto-frees a freed node's connections.
- **LootRoller mixed-sign-weight wrong affix.** [LootRoller.gd:82](../autoloads/LootRoller.gd#L82) `if a.weight <= 0.0: continue` filters non-positive weights *before* bucketing — the scenario can't occur; `candidates[-1]` is a benign float-rounding fallback.
- **WaveManager unknown `path_id` "silent" no-op.** [WaveManager.gd:503-505](../autoloads/WaveManager.gd#L503) `push_warning` + `_spawner_done` — handled with a warning, bounty consistency intact.
- **All HeroTuning negative-slider "inversion" findings.** Debug-only tool, clamped, excluded per scope.

## Deferred — latent / by-design (no test this pass; recorded for completeness)

- WaveManager `_alive_per_wave` orphan keys from corrupted enemy `wave_index` meta — defensive `.erase` already safe; memory only.
- SaveManager v1→v3/v4 migration *log messages* without executable migration fns — intentional (work is implicit in InventoryManager), comments explain it; cosmetic-log only.
- LoadoutState `get_equipped_skills` skips purge when ContentRegistry cold — by design (boot guard); stale survives exactly one read then self-heals.
- UnlockManager type-scoped checks have no runtime assert preventing a future generic `find_by_id` regression — design hardening, not a live bug.
- RunState `reset_for_level` reads MetaProgression before the `has_node` guard — autoload order in project.godot prevents it today.
- EquipmentScreen hero-swap lambda ordering (stale `_cached_hero_id` before paperdoll rebuild) — cosmetic, only non-humanoid (Dragon) on embedded swap; folded conceptually into #1/#2.

## Recommended fix order (when a fix pass is authorized)

1. **#6 SceneManager** — only true hard soft-lock.
2. **#1/#2/#9 EquipmentScreen** — one `_exit_tree` + named handler clears three tests; documented invariant.
3. **#3/#4 add_hero_xp** — move the two emits after the entry writes.
4. **#7 InventoryManager** — one-line `""` strip; protects every migrating save.
5. **#8 ppt self-heal**, **#5 radial backdrop**, **#10 base_hero symmetry** — lower urgency.
