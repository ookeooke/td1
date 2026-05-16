# Hero Multi-Mode Arbitration (design doc — read before any multi-mode hero)

Status: **DESIGN ONLY. Not implemented.** No multi-mode hero may be authored
until this rule is implemented + tested. Quarantined here on purpose (Phase 5,
plan step S5.4) so the open problem is not hand-waved into trap/dragon code.

## The problem

The Pure-B architecture (Phases 1–5) keeps each hero **single-mode** by
construction:

- Attack mode is owned by the equipped weapon (Phase 3). One weapon at a
  time ⇒ one attack mode.
- Body profile (Phase 4) sets targeting *priority*, not a second attack loop.
- A trap skill (Phase 5) is an *active skill cast*, orthogonal to the basic
  attack — it does not compete for the per-frame target.

So today there is exactly one target-selection owner per frame: the
weapon-driven basic attack pipeline (`_resolve_attack_profile` →
`_pick_*` → `_start_block` / shoot). Skills are player-triggered and
preempt nothing automatically.

A genuine **multi-mode** hero — one that *autonomously* switches between two
basic-attack behaviors (e.g. a dragon that melee-intercepts flyers in air
AND auto-breathes at ground; a trapper that also melees) — would have **two
systems wanting to own `_target_enemy` / the state machine in the same
frame**. The 6 Blocker invariants assume a single engagement owner. Naive
"whichever picked last wins" causes per-frame oscillation (the same class of
bug the 3-site `_profile_uses_projectile()` unification fixed in Phase 3).

## The rule (to implement before the first multi-mode hero)

1. **Modes are ranked, not concurrent.** A multi-mode hero declares an
   ordered `mode_priority: Array` on its body profile. Each frame, exactly
   one mode is *active*; lower-priority modes are fully dormant (no claim,
   no target write).
2. **Hysteresis on switch.** A mode change requires the higher-priority
   mode to have a valid target for ≥ `MODE_SWITCH_DEBOUNCE` (~0.4 s) before
   it preempts the active one — never per-frame. Mirrors the assist
   preempt-not-sticky discipline (invariant #6).
3. **Switching releases like a player move.** On mode switch the outgoing
   mode calls `_release_block()` THEN `_release_claim()` in the same frame
   (invariant #5) — no one-frame soft-stop leak, no double-claim
   (invariant #3).
4. **One engageability gate still.** Every mode's picker routes through the
   same `BaseEnemy.is_engageable_ground()` / `targets_flying`-ranged-only
   gates (invariants #1, #2). A new mode never re-derives them.
5. **Each claim-holding mode keeps its own watchdog** (invariant #4):
   a mode that holds a soft claim must time out + blacklist on no-progress,
   independently, so a dormant-then-reactivated mode can't resurrect a
   stale claim.
6. **Executable or it doesn't ship.** The switch rule lands with a GUT
   test asserting: no oscillation across a contrived two-target frame
   sequence; release-on-switch leaves zero stale `_blockers`/`_reservers`;
   `test_combat_blocking.gd` stays green with a multi-mode hero in-scene.

## Until then

Dragon (Phase 4) ships **single-mode**: flying body, `max_block_targets=0`,
weapon-driven ranged attack, `AIR_FIRST` targeting priority. It never
melee-intercepts — it only shoots, preferring flyers. Trapper (Phase 5)
ships single-mode: a normal (weak) weapon-driven basic attack plus the
trap *skill*. Neither needs arbitration. Anything that would needs this
rule first.
