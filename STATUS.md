# STATUS

**Last shipped**: GameState split. The 673-LOC god-object autoload was decomposed into four focused autoloads — `RunState` (volatile per-level), `LoadoutState` (pre-level picks), `MetaProgression` (cross-run progression), `DisplayUtils` (safe-area orphan rescued). 245 references swept across 30 files; save format unchanged (keys stay flat at JSON top level); SaveManager now reads/writes from three sources instead of one. New CORE RULE 20 in CLAUDE.md locks in the per-content-id pattern so future heroes / towers / items / spells slot into existing dicts without growing autoloads. See SESSIONS.md "2026-05-01 — GameState split".

**Currently working on**:
- WorldMap UI overhaul series (research doc: `~/.claude/plans/lets-make-deep-research-robust-sunbeam.md`). Phase A shipped; Phases B–F queued.

**Next up** (in priority order):

0. **WorldMap UI overhaul — DONE.** All six phases (A–F) shipped. Optional cleanup later: retire the now-orphaned standalone meta scenes that the hubs embed (EquipmentScreen / TalentScreen / LoadoutPickerScreen / UpgradeTree / EncyclopediaScreen / LeaderboardScreen) once it's clear no other code paths still reach them directly.

0a. **Town/City — Sell phase (T1) shipped.** Future Town phases queued in research doc (`~/.claude/plans/lets-make-deep-research-robust-sunbeam.md` "DEFERRED" section): T2 Buy + Town hub, T3 Disenchant + Scrap, T4 Affix Reroll, T5 Rarity Bump, T6 Polish. Each shippable independently.

1. **Engineering hardening week** (~10–12h total — do this BEFORE the content sprint; bugs in untested code compound fast):
   - **Mon–Tue (~4h)** — Install [GUT](https://github.com/bitwes/Gut) (addon, enable plugin). Write ~30 unit tests:
     - DamageCalculator (5): PHYSICAL / MAGIC / TRUE, armor clamp, negative amounts, null target
     - SaveManager (5): round-trip, missing file, corrupted JSON, version rejection, `hero_talents` preserved
     - UnlockManager (5): type-scoped separation, empty id, star threshold, explicit unlock, `requires_unlock=false`
     - ContentRegistry (4): `find_tower` / `find_hero` / `find_enemy` found+missing, `_validate_ids` drift
     - State autoloads (5): `RunState.reset_for_level`, `RunState.record_round_damage` routing, `_next_damage_key` monotonic, `LoadoutState.set_loadout_slot` swap, `LoadoutState.get_loadout_towers` cap+lock
     - Regression locks (6): enemy double-emit guard (47d-20 fix), overkill cap, status-effect refresh, `TowerUpgradeData` cross-fallback (47d-9 fix), stats-card diff, unlock fallback
   - **Wed (~3h)** — Save migration scaffold in [autoloads/SaveManager.gd](autoloads/SaveManager.gd): `SAVE_VERSION` constant + `_MIGRATIONS: Array[Callable]` chain that runs per-version mutators forward until current. Add `content_hash` key for orphaned-content tolerance (unknown IDs in loadout → drop instead of crash). 3 migration tests in `tests/unit/test_save_migrations.gd`.
   - **Thu (~1h)** — `.github/workflows/ci.yml` using `barichello/godot-ci:4.6`. Runs GUT headless + exports Android APK as artifact on every push.
   - **Fri (~2–4h)** — Playtest the APK CI built. Put it in front of 3–5 humans. Watch silently, don't explain. Write the first 5 things that confused or bored them into this file.

2. **Content sprint** (4–8 weeks, after hardening): 4 more levels, 2 more heroes (ranger / paladin), 2 more towers (support or AoE-slow variant), 4 more enemies (shielded, fast-swarm, self-heal, boss #2), 1 more spell. Architecture already supports one-file adds.

3. **Production hardening round 2** (after content is authored): i18n via `tr()` wraps on every user-facing string, real IAP SDK (RevenueCat or Google Play Billing + receipt validation), analytics event bus (stub → Amplitude / GameAnalytics), crash reporting via [sentry-godot](https://github.com/getsentry/sentry-godot), accessibility (font scaler, color-blind palette, 80px min touch targets).

## Known issues / rough edges
- ~~`autoloads/GameState.gd` is ~500 lines and god-object-shaped. Refactor deferred — not painful yet.~~ Shipped 2026-05-01. Split into RunState / LoadoutState / MetaProgression / DisplayUtils.
- No test suite. All validation is manual via Godot editor.
- [heroes/base_hero.gd:627](heroes/base_hero.gd) `_die()` connects `create_timer().timeout` without an `is_connected` guard — double-die in one frame could double-respawn. Low risk; fix next time you touch the file.
- Soldier CHARGING→RETURNING state-machine loop risk with stacked enemies — needs live repro before touching.
- `_sum_aura` is called from `get_effective_damage/range/attack_speed` getters — verify call frequency in a profiler before the next aura-heavy content push.

## Open design questions
- Spell `cast_range > 0` semantics: measured from hero? tower? map center? Current code toasts "not wired up" when encountered. Needs decision before authoring a ranged spell.
- Tower slot cap progression (`LoadoutState.tower_slot_cap`) — what gates slots 5 and 6? Star threshold? IAP? Quest? Wired up but not triggered.
- Save-file migration framework — deferred since Phase 46c/46d. Next content rename that changes an `*_id` should ship with the migration scaffold.

## Deferred from prior audits (not scheduled, but noted)
- SoundManager 8-player pool exhaustion silently drops SFX in dense combat. Grow pool or preempt oldest.
- PurchaseManager stub accepts empty `unlock_id`. Fine while stubbed; real SDK will need validation.
- `TowerRadialMenu._next_upgrade_data` reads `_current_tower.data` directly — mild CORE RULE 14 nit. Route through an accessor next time menu code changes.

---

*Update this when starting or ending a working session. Not append-only — overwrite freely. Use SESSIONS.md for the log.*
