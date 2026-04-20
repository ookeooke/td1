# STATUS

**Last shipped**: Phase 48d complete + 2026-04-20 interaction/game-over audit pass (see [SESSIONS.md](SESSIONS.md)).

**Currently working on**:
- Doc hygiene — this file + CLAUDE.md compaction (in progress).

**Next up** (in priority order):
1. **Playtest the vertical slice.** Export Android APK, put Level 1 in front of 3–5 humans. Watch them play silently. Record the first 5 things that confused or bored them.
2. **Content sprint** (4–8 weeks target): 4 more levels, 2 more heroes (ranger / paladin), 2 more towers (support or AoE-slow variant), 4 more enemies (shielded, fast-swarm, self-heal, boss #2), 1 more spell. Architecture already supports one-file adds.
3. **Production hardening** (only after content is in): tests for DamageCalculator / SaveManager / UnlockManager, i18n wrap (`tr()`), real IAP SDK, Amplitude/GameAnalytics hooks, accessibility pass (font scaler, color-blind palette, 80px min touch targets).

## Known issues / rough edges
- `autoloads/GameState.gd` is ~500 lines and god-object-shaped. Refactor deferred — not painful yet.
- No test suite. All validation is manual via Godot editor.
- [heroes/base_hero.gd:627](heroes/base_hero.gd) `_die()` connects `create_timer().timeout` without an `is_connected` guard — double-die in one frame could double-respawn. Low risk; fix next time you touch the file.
- Soldier CHARGING→RETURNING state-machine loop risk with stacked enemies — needs live repro before touching.
- `_sum_aura` is called from `get_effective_damage/range/attack_speed` getters — verify call frequency in a profiler before the next aura-heavy content push.

## Open design questions
- Spell `cast_range > 0` semantics: measured from hero? tower? map center? Current code toasts "not wired up" when encountered. Needs decision before authoring a ranged spell.
- Tower slot cap progression (`GameState.tower_slot_cap`) — what gates slots 5 and 6? Star threshold? IAP? Quest? Wired up but not triggered.
- Save-file migration framework — deferred since Phase 46c/46d. Next content rename that changes an `*_id` should ship with the migration scaffold.

## Deferred from prior audits (not scheduled, but noted)
- SoundManager 8-player pool exhaustion silently drops SFX in dense combat. Grow pool or preempt oldest.
- PurchaseManager stub accepts empty `unlock_id`. Fine while stubbed; real SDK will need validation.
- `TowerRadialMenu._next_upgrade_data` reads `_current_tower.data` directly — mild CORE RULE 14 nit. Route through an accessor next time menu code changes.

---

*Update this when starting or ending a working session. Not append-only — overwrite freely. Use SESSIONS.md for the log.*
