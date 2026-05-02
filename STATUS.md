# STATUS

**Last shipped**: CI workflow (Thu of engineering hardening week). Added `.github/workflows/ci.yml` using `barichello/godot-ci:4.6` — runs the 33-test GUT suite headless on every push and PR, then (on test pass) exports a debug Android APK as a build artifact retained for 14 days. Promoted `export_presets.cfg` from gitignored to tracked so CI can read the Android preset; tightened `.gitignore` to still exclude keystore / signing-key siblings. See SESSIONS.md "2026-05-01 — CI workflow (Thu)".

**Currently working on**:
- WorldMap UI overhaul series (research doc: `~/.claude/plans/lets-make-deep-research-robust-sunbeam.md`). Phase A shipped; Phases B–F queued.

**Next up** (in priority order):

0. **WorldMap UI overhaul — DONE.** All six phases (A–F) shipped. Optional cleanup later: retire the now-orphaned standalone meta scenes that the hubs embed (EquipmentScreen / TalentScreen / LoadoutPickerScreen / UpgradeTree / EncyclopediaScreen / LeaderboardScreen) once it's clear no other code paths still reach them directly.

0a. **Town/City — Sell phase (T1) shipped.** Future Town phases queued in research doc (`~/.claude/plans/lets-make-deep-research-robust-sunbeam.md` "DEFERRED" section): T2 Buy + Town hub, T3 Disenchant + Scrap, T4 Affix Reroll, T5 Rarity Bump, T6 Polish. Each shippable independently.

1. **Engineering hardening week** (~10–12h total — do this BEFORE the content sprint; bugs in untested code compound fast):
   - ~~**Mon–Tue (~4h)** — Install [GUT](https://github.com/bitwes/Gut), write ~30 unit tests.~~ **Shipped 2026-05-01.** 30/30 passing in 1.4s headless. See SESSIONS.md.
   - ~~**Wed (~3h)** — Save migration scaffold + content_hash orphan tolerance.~~ **Shipped 2026-05-01.** Framework + 3 tests, 33/33 total. See SESSIONS.md.
   - ~~**Thu (~1h)** — `.github/workflows/ci.yml` using `barichello/godot-ci:4.6`. Runs GUT headless + exports Android APK as artifact on every push.~~ **Shipped 2026-05-01.** First push will validate the image tag + Android export pipeline; iterate from the run output if either step needs adjustment.
   - **Fri (~2–4h)** — Playtest the APK CI built. Put it in front of 3–5 humans. Watch silently, don't explain. Write the first 5 things that confused or bored them into this file.

2. **Content sprint** (4–8 weeks, after hardening): 4 more levels, 2 more heroes (ranger / paladin), 2 more towers (support or AoE-slow variant), 4 more enemies (shielded, fast-swarm, self-heal, boss #2), 1 more spell. Architecture already supports one-file adds.

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
- PurchaseManager stub accepts empty `unlock_id`. Fine while stubbed; real SDK will need validation.
- `TowerRadialMenu._next_upgrade_data` reads `_current_tower.data` directly — mild CORE RULE 14 nit. Route through an accessor next time menu code changes.

---

*Update this when starting or ending a working session. Not append-only — overwrite freely. Use SESSIONS.md for the log.*
