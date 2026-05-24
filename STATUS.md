# STATUS

**Last shipped**: Unified hero chooser — Path-of-Exile-lite skill map + master-detail unification (2026-05-18). New [docs/UNIFIED_CHOOSER_DESIGN.md](docs/UNIFIED_CHOOSER_DESIGN.md) reference spec. New inspect-only [ui/HeroSkillMap.gd](ui/HeroSkillMap.gd) constellation hosted in [HeroSkillsPage.gd](ui/HeroSkillsPage.gd) as the default view (legacy tab+list preserved behind a Map/List toggle); node tap routes the EXISTING `_inspect_tree_node`/inspector/mutators unchanged. [HeroesHub.gd](ui/HeroesHub.gd) gained visible rail scroll arrows + scroll-selected-into-view. [EquipmentScreen.tscn](ui/EquipmentScreen.tscn) detail bottom-sheet re-docked to a fixed right column (zero `.gd` change). Two-step arm→confirm added to the point-spending Skills BUY (mirrors Equipment sell). All additive — no working script rewritten, no save/ID changes. GUT 213/213 functional pass (0 failures, all 10 pre-existing `test_bug_edge_audit.gd` failures fully resolved). Deferred: persistent Equipment placeholder panel; Skills inspector action pinned bottom-right. See SESSIONS.md "2026-05-18 — Unified hero chooser".

**Previously shipped**: RunStats telemetry pipeline (schema 4 → 7) + Balance Scout agent + RunStatsDigest aggregator (2026-05-11). Three additive schema bumps in one session: schema 5 added boss_events, tower_events timeline, skill_casts, peak_concurrent_enemies_global, level_hardness, level_target_ppt; schema 6 added per-wave `enemies_by_id` / `damage_by_source` / `damage_by_tower_instance`, run-level `tower_runtime_stats[]`, `defeat_reason`, `final_wave_reached`, `game_speed`; schema 7 stamped `paths_in_range` on tower events + runtime entries and added `spots_total` / `spots_unbuilt` at finalize. Bookkeeping fixes: mid-wave-defeat backfills `lives_lost` from `leaks[]`; soldier damage is attributed back to the spawning barracks; `naked_baseline` now rejects runs with `BalanceOverrides.any_active()`. New [balance/report/RunStatsDigest.gd](balance/report/RunStatsDigest.gd) is the static aggregator (`level_digest`, `format_level_digest`, cohort filters by `overrides_active` / `naked_baseline`). New [docs/agents/balance_scout.md](docs/agents/balance_scout.md) defines the Balance Scout role + telemetry workflow rules. [BALANCE.md](balance/BALANCE.md) and [docs/agents/balance_scout.md](docs/agents/balance_scout.md) schema docs are synced. See SESSIONS.md "2026-05-11 — Telemetry pipeline + Balance Scout".

**Also shipped (2026-05-11) — Projectile visuals pass + Mage hero projectile.** [projectiles/Arrow.gd](projectiles/Arrow.gd) gained `HERO_ARROW` and `ARCANE_BOLT` shapes with per-shape impact VFX (frost shatter, arcane burst); new [projectiles/HeroArrow.tscn](projectiles/HeroArrow.tscn) + [projectiles/HeroBolt.tscn](projectiles/HeroBolt.tscn); [heroes/base_hero.gd](heroes/base_hero.gd) spawns muzzle flashes tinted by projectile color and offsets spawn point along aim vector. Wired `projectile_scene` on [hero_ranger.tres](heroes/data/hero_ranger.tres) and [hero_mage.tres](heroes/data/hero_mage.tres) (mage was previously using the instant-hit else branch despite being a 240-range caster). See SESSIONS.md "2026-05-11 — Projectile visuals pass" and "Mage hero gets a real ranged projectile". **Visual verification still pending** — need an editor playtest to confirm hero arrow reads as distinct from tower arrow, impact bursts don't overlap awkwardly with HitSparkVFX, and particle counts are mobile-acceptable.

**Balance correctness + doc resync shipped (2026-05-18).** A 5-agent balance
audit drove a doc-only/correctness pass: [BALANCE.md](balance/BALANCE.md)
per-tower g/DPS table, per-tower status, and mode-multiplier table were stale
vs the authored `.tres`/code (CORE RULE 18) and have been recomputed from the
live files; `base_wooden_sword.tres` `drop_weight` 2.0→1.0 (applying a decision
the doc already recorded); `RunStats.gd` run-level `damage_by_source` gained
additive `towers`/`other` aliases so it matches the per-wave schema. **Tuning
is blocked until clean telemetry exists** — all 50 runs in `run_stats.json`
have `overrides_active=true`, zero `naked_baseline=true`, so the Naked Baseline
invariant is unverifiable. Deferred tuning findings (Artillery DOA, boss
hardness cliff, Knight base DPS, Demon Core, non-monotonic L1→L6, Iron speed
unimplemented, War Chest dead-zone) are catalogued in BALANCE.md "Known balance
issues — 2026-05-18 audit". See SESSIONS.md "2026-05-18 — Balance audit +
correctness/doc resync".

**Phase 2 — new offensive affixes shipped (2026-05-18).** Four event-based
`AbilityData` subclasses (`CritStrikeAbility`, `CleaveOnHitAbility`,
`ExecuteAbility`, `ConditionalDamageAbility`) + six `AffixData .tres`
(crit/cleave/execute/vs_armored/vs_flying/vs_boss) wired into
`pool_weapon_offensive` (5→11 affixes). All additive, owner-agnostic,
secondary-`take_damage` pattern; value bands sized for the LootRoller
LEGENDARY ×2 ceiling; weights keep them rarer than plain +damage. New
`tests/unit/test_offensive_affixes.gd` (10 tests, all pass); full GUT 203 pass
/ 0 regressions. **Test Range feel/VFX smoke still pending.** See SESSIONS.md
"2026-05-18 — Phase 2: new offensive affixes".

**Phase 3 — Wave Diagnostics Panel shipped (2026-05-18).** Per-wave hard/easy
verdict table embedded at the top of every level's wave-timeline block in
[balance/debug/BalanceSliders.gd](balance/debug/BalanceSliders.gd). Six
columns: Wave · Pacing Δ (score_wave ratio) · Tuning (drift vs authored
pressure target) · Bottleneck (dominant `wave_demand_vector` bucket) · EHP
sparkline · Leaks (telemetry, gated n_runs ≥ 5). Distinct color palettes
separate pacing (SPIKE/DIP, red/blue) from tuning (OVER/UNDER/IN BAND,
orange/yellow/green). Slider edits auto-refresh via existing
`_refresh_wave_charts` (new `is_diagnostics` branch). New
`RunStatsDigest.defeat_wave_counts()` helper (4 GUT tests, all pass) fixes
Gemini's bug of using `final_wave_dist` which counts victories. Folds in 12
critique fixes vs Gemini v2; explicitly drops the v1 "Impossible" verdict
(uncalibrated). Full GUT 218/218 pass. **In-editor visual verification still
pending.** Next: Phase 4 = endgame curve past L6 (deferred, telemetry-gated).
See SESSIONS.md "2026-05-18 — Phase 3: Wave Diagnostics Panel".

**Carry-over flag:** concurrent commits between Phase 1 and Phase 3 removed
linear L3 upgrades (Mortar / Wizard / Archer L3 / Blizzard) from the tower
`.tres` files and bumped Howitzer 13→100 damage — BALANCE.md's per-tower
g/DPS table is stale again and needs a follow-up doc resync before Phase 4.

**Previously**:
- **Preventive Bug Rules + `HeroStats` accessor + `InventoryManager._persist()` refactor (2026-05-11)** — Codified four CLAUDE.md rules each tied to a real shipped bug (UI reads hero stats via `HeroStats.effective_for`; every InventoryManager mutator ends with `_persist()`; embedded hero-scoped screens listen to `hero_selected`; load-bearing invariants must be executable). New [heroes/HeroStats.gd](heroes/HeroStats.gd) mirrors the Tower Indicator pattern; HeroesHub dogfoods it. Audit found two additional drift sites (grid-placement, `destroy()`) that also skipped saves — fixed. See SESSIONS.md "2026-05-11 — Preventive Bug Rules".
- **HeroesHub binding fixes (2026-05-11)** — Talents tab now refreshes on `hero_selected`; equip/unequip persist immediately; Hero Hall Overview shows effective stats with gear (was reading base HeroData fields).
- **Code-review punch list (2026-05-11)** — SkillBar level-agnostic (exported `map_path: NodePath`, drops Level1 hardcode); ContentRegistry directory-globs enemies / towers / heroes / skill_trees with foreign-sibling guard; PurchaseManager rejects empty unlock_id; CLAUDE.md test-suite line corrected.
- **Hero progression overhaul: Diablo-style skill tree (Phases 0 → 3R, 2026-05-10).** Per-hero `HeroSkillTreeData` with PASSIVE_RANK / ACTIVE_RANK / SLOT_UNLOCK / MOD / CAPSTONE nodes. Per-level point grants, level-gated equipped-skill / passive slot caps, in-tree mod picks. Save v4→v5 migration converts old talent purchases to skill-tree nodes.
- **Spawn-UI consolidation + path preview chevrons + single-tap Send-Wave badge (2026-05-10).** SpawnMarker children render in-editor only; WaveCallIndicator owns all runtime spawn-point UI. CORE RULE 19 finalized — Send-Wave button visible the entire countdown, bonus magnitude capped by `early_call_window_sec`.
- **WorldMap Kingdom Rush–style visual rework (2026-05-04).** Pannable procedural parchment map (2400×1400) with banner markers per level, Catmull-Rom dotted path, mountain glyphs + region labels. Marker positions are `Marker2D` children of `WorldMapView/LevelMarkers`. `LevelNodeData.map_position` retired.
- **Balance tooling — PPT framework + Slider debug panel + cross-level Audit screen (2026-05-03).** Player Power Tier scalar collapses loadout strength into one number; level-side `min_ppt`/`target_ppt` bands replace per-level multiplier targets. Slider panel writes runtime overrides via `balance/debug/BalanceOverrides.gd`.

**Currently working on**:
- Hand-authoring L2 onward against the new PPT-banded target curve (BALANCE.md). Wave generator deliberately skipped per Kingdom Rush precedent — hand-author + slider-validate is the workflow.
- **10-minute level duration rule shipped (2026-05-04, L4+ only).** `BalanceCalculator.level_floor_time`, `[LevelN/Duration]` readout line, `Avg dur` column + L4-only flag in BalanceReport, `LevelNodeData.target_duration_sec` default 360→600. L1-L3 grandfathered. See plan `~/.claude/plans/i-would-like-to-wobbly-thompson.md` and BALANCE.md "Level duration — 10-minute target".
- **Combat-text + HUD polish pass shipped (2026-05-07).** FloatingText is now style-driven (Kind enum + 9 presets, 8-direction outline, scale-pop + drift + late-fade), damage numbers route through `VFXSpawner` via `EventBus.hit_landed` with per-(target, source) merging, and the HUD switched to HudChip widgets with pulse-on-change + a centered "Wave N" banner. No new EventBus signals, no `.tres` changes. See SESSIONS.md "2026-05-07 — Combat-text + HUD polish pass". **In-editor playtest pending** — verify damage merging, big-hit detection, and HUD pulses on Level 1.
- **Phase 55 — Diablo-Immortal-style gear cells + Gear/Relics tab split shipped (2026-05-07).** EquipmentScreen now uses 120×144 (5:6) cells uniformly across paperdoll and stash, plus a two-tab filter (Gear holds slots 0–4, Relics holds Trinket). `ItemIcon.set_pixel_size(Vector2)` API added; `set_slot_footprint` legacy path preserved. Storage unchanged — single shared bag, tabs are pure display filter (DI-screenshot-driven design; D4-lesson-driven architecture). See SESSIONS.md "2026-05-07 — Phase 55: Diablo-Immortal-style gear cells".
- **Phase 55b — post-review fixes shipped (2026-05-07).** Hidden the redundant stats panel (already on Hero Hall Overview), paperdoll silhouette grows to fill the freed space; tab switch resets stash scroll; active tab uses Godot's built-in disabled-state styling for a clear "pressed-in" look; empty backdrop now reflects remaining shared bag capacity instead of always drawing 50 cells per tab. See SESSIONS.md "2026-05-07 — Phase 55b". **In-editor playtest pending** — verify all four behaviors.
- **Phase 55c — Equipment-screen polish from the bug review (2026-05-07).** Tab filter is now extensibility-safe (Gear = "everything except Relics" so unknown/corrupt slot indices fall through instead of vanishing); bottom-sheet no longer flickers on equip (dismiss runs before `equip()`); `set_pixel_size` guards zero-component vectors; reverted Phase 55b's vertical expand on `EquippedCard`/`EquipmentGrid` to protect the paperdoll silhouette layout (figure draw scale is constant — an over-tall box would have stranded it). See SESSIONS.md "2026-05-07 — Phase 55c". Plan / review at `~/.claude/plans/phase-55-bug-review.md`.
- **Phase 55d — Paperdoll layout fixes from in-editor screenshot (2026-05-07).** Screenshot showed HELM clipping above the grid edge, silhouette overlapping slots, and a dark gap below the card. Fixes: enlarged `EquipmentGrid` from `540×600` to `600×720` so all slots fit with margin; reduced `Paperdoll._DRAW_SCALE` from `4.5` to `3.5` and lowered `_ANCHOR_FRACTION` from `0.85` to `0.70` so the silhouette is right-sized and centered; re-added `EquippedCard.size_flags_vertical = 3` so the card fills LeftPanel height. No GDScript changes — normalized anchors handled the reflow. See SESSIONS.md "2026-05-07 — Phase 55d". **Pending playtest** — verify the new layout in editor.
- **Phase 55e — HeroesHub close button (2026-05-07).** Replaced the context-sensitive "← Back / ← Hero Hall" chip with a fixed large `✕` close button that always exits to WorldMap. Removes the redundancy where the back chip and sidebar Overview button did the exact same thing inside sub-views. Sub-view → hub-root navigation now flows exclusively through the Overview sidebar tab; corner ✕ is a single-purpose "close the hub" affordance (Diablo Immortal modal-close convention). See SESSIONS.md "2026-05-07 — Phase 55e".
- **Phase 55f — Paperdoll slots are Marker2D children (2026-05-07).** Slot positions converted from `const` Dictionary in `Paperdoll.gd` to `Slot0`..`Slot5` Marker2D children of `EquipmentGrid`. Drag in the 2D viewport with the W tool to reposition (mirrors the `TowerSpots → Spot1` pattern). Resolution order: `HeroData.slot_anchors` override → Marker2D child → const fallback. `_DRAW_SCALE` and `_ANCHOR_FRACTION` exported as `draw_scale` / `anchor_fraction` for inspector tweaking. See SESSIONS.md "2026-05-07 — Phase 55f".
- **Phase 55g — EquipmentGrid expands vertically (BOOTS clipping fix) (2026-05-07).** Added `size_flags_vertical = 3` to `EquipmentGrid`. Grid now fills the EquippedCard (~970 px tall) instead of staying at the 720 px floor. Fixes BOOTS being clipped at the bottom (user-authored at y=698, icon bottom at 770 was being chopped by `clip_contents = true`); also eliminates the dead dark space below the silhouette. Safe to do now because Phase 55d already right-sized the silhouette (`draw_scale = 3.5`, `anchor_fraction = 0.70`). See SESSIONS.md "2026-05-07 — Phase 55g".
- **Phase 55h — Tap-equipped is non-destructive (2026-05-07).** Removed the destructive instant-unequip on equipped-slot tap. Now opens the same bottom-sheet inventory items use; primary button reads `Unequip` (instead of `Equip`/`Replace`) when the selected item is currently equipped on the active hero, and Sell disables (must unequip first). Matches Diablo Immortal / D4 / PoE mobile convention. Swap-gear flow (tap new item → `Equip`) is unchanged. See SESSIONS.md "2026-05-07 — Phase 55h".
- **WorldMap polish — next-level pulse + hide-locked + unlock celebration shipped (2026-05-07).** LevelMarker pulses the recommended-next level (lowest unstarred unlocked); locked levels and their road segments are completely hidden; on level completion, `SaveManager` stores `pending_unlock_celebration_id` and on next WorldMap entry the road-reveal animation draws Catmull-Rom dots progressively from origin → destination over 1.5s, then the just-unlocked marker fades + scale-pops with `TRANS_BACK` overshoot, then pulse takes over. Persisted handoff field guarantees replay-on-force-quit. Editor live-drag (Marker2D `@tool` polling) also shipped same day. See SESSIONS.md "2026-05-07 — WorldMap polish". **In-editor playtest pending** — confirm reveal timing feels right and tune `road_tween` duration / pop overshoot if needed.
- **In-level hero HUD polish pass shipped (2026-05-07).** Portrait tap now selects-only (no camera pan); damage flash on `EventBus.hit_landed`; move-order marker (expanding green ring at destination) on `BaseHero`; off-navmesh tap rejection in HeroInputManager via `NavigationServer2D.map_get_closest_point` (150 px tolerance, mirrors CORE RULE 13's soldier-rally snap); portrait grown 120→140 + cluster widened 200→280 + skill slots fanned around the LEFT side of the portrait at radius 115 / angles −165° / −105°; round `CooldownButton` (`draw_circle` + `draw_arc`); cooldown reset to 0 on `_respawn` (was freezing during DEAD because `_physics_process` early-returns); fixed CooldownButton stuck-dark bug via `_last_is_ready` tracker (the `is_equal_approx` redraw gate was skipping the ready-transition redraw at sub-epsilon residuals). All additive — no new signals, no autoload changes. See SESSIONS.md "2026-05-07 — In-level hero HUD polish".

**Next content task — author L4 against the 10-min rule.** L4 in [level_list.tres:47-60](ui/world_map/level_list.tres) is currently a "test stub, under-tuned" reusing L1's scene. Replace with a real Level4.tscn (copy a template under `levels/templates/`), author 8-12 waves targeting ~600s actual play, verify `[Level4/Duration]` floor lands 800-900s, play 5+ runs to confirm `Avg dur` reads in the 480-720s band before shipping.

**Next up** (in priority order):

0. **WorldMap UI overhaul — DONE.** All six phases (A–F) shipped. Optional cleanup later: retire the now-orphaned standalone meta scenes that the hubs embed (EquipmentScreen / TalentScreen / LoadoutPickerScreen / UpgradeTree / EncyclopediaScreen / LeaderboardScreen) once it's clear no other code paths still reach them directly.

0a. **Town/City — Sell phase (T1) shipped.** Future Town phases queued in research doc (`~/.claude/plans/lets-make-deep-research-robust-sunbeam.md` "DEFERRED" section): T2 Buy + Town hub, T3 Disenchant + Scrap, T4 Affix Reroll, T5 Rarity Bump, T6 Polish. Each shippable independently.

1. **Engineering hardening week** (~10–12h total — do this BEFORE the content sprint; bugs in untested code compound fast):
   - ~~**Mon–Tue (~4h)** — Install [GUT](https://github.com/bitwes/Gut), write ~30 unit tests.~~ **Shipped 2026-05-01.** 30/30 passing in 1.4s headless. See SESSIONS.md.
   - ~~**Wed (~3h)** — Save migration scaffold + content_hash orphan tolerance.~~ **Shipped 2026-05-01.** Framework + 3 tests, 33/33 total. See SESSIONS.md.
   - ~~**Thu (~1h)** — `.github/workflows/ci.yml` using `barichello/godot-ci:4.6`. Runs GUT headless + exports Android APK as artifact on every push.~~ **Shipped 2026-05-01.** First push will validate the image tag + Android export pipeline; iterate from the run output if either step needs adjustment.
   - **Fri (~2–4h)** — Playtest the APK CI built. Put it in front of 3–5 humans. Watch silently, don't explain. Write the first 5 things that confused or bored them into this file.

2. **Content sprint** (4–8 weeks, after hardening): 4 more levels, 2 more heroes (ranger / paladin), 2 more towers (support or AoE-slow variant), 4 more enemies (shielded, fast-swarm, self-heal, boss #2), 1 more spell. Architecture already supports one-file adds.

   **BLOCKER for content sprint past ~10 levels — WorldMap chapter hub.** Current single 2400×1400 canvas with auto-scroll handles 4-5 levels comfortably; cramps badly past 12-15; unworkable at 40. Ship a `WorldChapters.tscn` hub (4-6 chapter cards → existing `WorldMap.tscn` filtered by chapter_id) BEFORE authoring level 11. Reuses existing `WorldMapView` + `LevelMarker` infrastructure ~95%. Migration steps:
   - Add `chapter_id: String` to `LevelNodeData` (`ui/world_map/LevelNodeData.gd`); tag L1-L4 retroactively via `level_list.tres`
   - Build `ui/WorldChapters.tscn` + `WorldChapters.gd` (banner cards reusing LevelMarker styling, `(complete/total)★` per region)
   - Filter `WorldMap._load_levels` by `LoadoutState.current_chapter_id`
   - Repoint MainMenu → WorldChapters (instead of MainMenu → WorldMap)
   - Estimated 2-3 dev sessions. Existing REGION_LABELS in `WorldMapView.gd:42` ("The Dunes" / "Iron Pass" / "Frostpeak" / "Foul Bay") are the natural 4 chapters.

   Pinch-zoom on WorldMap (port `GameCamera`'s pinch logic) is a deferred polish pass — only needed if a chapter exceeds ~12 levels OR if playtesters complain about scroll-bar friction. Do not pre-build.

3. **Production hardening round 2** (after content is authored): i18n via `tr()` wraps on every user-facing string, real IAP SDK (RevenueCat or Google Play Billing + receipt validation), analytics event bus (stub → Amplitude / GameAnalytics), crash reporting via [sentry-godot](https://github.com/getsentry/sentry-godot), accessibility (font scaler, color-blind palette, 80px min touch targets).

## Known issues / rough edges
- ~~`autoloads/GameState.gd` is ~500 lines and god-object-shaped. Refactor deferred — not painful yet.~~ Shipped 2026-05-01. Split into RunState / LoadoutState / MetaProgression / DisplayUtils.
- ~~No test suite. All validation is manual via Godot editor.~~ 30 unit tests shipped 2026-05-01 in `tests/unit/`. Run via `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`.
- [heroes/base_hero.gd:627](heroes/base_hero.gd) `_die()` connects `create_timer().timeout` without an `is_connected` guard — double-die in one frame could double-respawn. Low risk; fix next time you touch the file.
- Soldier CHARGING→RETURNING state-machine loop risk with stacked enemies — needs live repro before touching.
- `_sum_aura` is called from `get_effective_damage/range/attack_speed` getters — verify call frequency in a profiler before the next aura-heavy content push.

## Open design questions
- Spell `cast_range > 0` semantics: measured from hero? tower? map center? Current code toasts "not wired up" when encountered. Needs decision before authoring a ranged spell.
- Tower slot cap progression (`LoadoutState.tower_slot_cap`) — what gates slots 5 and 6? Star threshold? IAP? Quest? Wired up but not triggered.
- ~~Save-file migration framework — deferred since Phase 46c/46d. Next content rename that changes an `*_id` should ship with the migration scaffold.~~ Shipped 2026-05-01. `SaveManager._migrations: Array[Callable]` is the registration point; `content_hash` triggers orphan purge on mismatch.

## Deferred from prior audits (not scheduled, but noted)
- SoundManager 8-player pool exhaustion silently drops SFX in dense combat. Grow pool or preempt oldest.
- ~~PurchaseManager stub accepts empty `unlock_id`.~~ Shipped 2026-05-11 (cd502be) — empty `product_id` / `unlock_id` rejected with `push_error`. Real SDK swap still queued.
- `TowerRadialMenu._next_upgrade_data` reads `_current_tower.data` directly — mild CORE RULE 14 nit. Route through an accessor next time menu code changes.
- **Per-hero paperdoll scenes (Phase 55-Option-B).** Trigger: 3+ heroes with fully unique slot layouts (counting Dragon as #1; today's `slot_anchors` numeric override is fine for 1–2 exotic heroes). Promote layouts to `res://heroes/paperdolls/paperdoll_<hero_id>.tscn` PackedScenes referenced by a new `HeroData.paperdoll_layout` field; EquipmentScreen swaps Marker2D children at hero-switch time. Implementation sketch in `~/.claude/plans/what-do-you-think-shimmying-fern.md` "Deferred — Per-hero paperdoll scenes" section.

---

*Update this when starting or ending a working session. Not append-only — overwrite freely. Use SESSIONS.md for the log.*
