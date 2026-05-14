# Combat Blocking Doctrine

Fantasy Tower Defense uses fixed enemy paths. Heroes and soldiers are the only units that can change level position, so blocker behavior must be predictable, readable, and tactical.

This document is the source of truth for hero/soldier/enemy battle logic. Follow it before changing `heroes/base_hero.gd`, `soldiers/base_soldier.gd`, `enemies/base_enemy.gd`, `HeroData.gd`, `SoldierData.gd`, or any blocker-related ability.

## Design Goal

Blockers guard a zone. They do not hunt the map.

Enemies should stop because a friendly body physically holds them, not because they were detected. Detection is soft. Engagement is hard.

Player-facing rule:

> If a friendly blocker meets a ground enemy inside its guard zone, the enemy stops and fights. If the enemy gets past the zone before contact, it leaks unless the player reacts.

## Reference Notes

Kingdom Rush-style references consistently frame barracks as chokepoint tools:

- Ironhide describes Paladin Barracks as soldiers that block enemies and create chokepoints: https://support.ironhidegames.com/support/solutions/articles/4000223657-paladin-barracks-skills-breakdown-defend-the-lines-in-kingdom-rush-battles
- A GameDeveloper analysis notes that soldiers wait around a rally point, stop one enemy each, and melee lock is broken by soldier death, enemy death, or rally reset: https://www.gamedeveloper.com/design/kingdom-rush---the-wonderful-campaign-level-design
- Pocket Gamer summarizes barracks as slowing/stalling units by forcing them to fight: https://www.pocketgamer.com/kingdom-rush/basic-strategies/
- Ranged/hybrid hero references treat ranged output as a positioning advantage, while close contact can force melee risk. Ironhide's Vesper guide frames dual-role heroes as deliberately authored, not the default for every ranged unit: https://support.ironhidegames.com/support/solutions/articles/4000223683-vesper-hero-guide-melee-ranged-attacker-in-kingdom-rush-battles

## Core Rules

1. Enemies do not stop on detection.
2. Enemies stop only while `BaseEnemy._blockers` is non-empty.
3. A blocker may intercept only inside its guard zone.
4. Once physical engagement succeeds, the lock persists until enemy death, blocker death, player move/rally reset, bypass behavior, or an explicit authored escape mechanic.
5. Blockers choose targets by protecting the line, not by tunnel vision.
6. Ranged units use ranged weapons by default. They enter close combat only when an enemy reaches their authored close-engage radius and the unit has block capacity.
7. Flying and `bypass_engagement` enemies ignore normal blocker locks unless an enemy/resource explicitly opts into being blockable.

## Zones and Ranges

Use separate concepts. Do not collapse them into one `attack_range`.

| Concept | Meaning |
|---|---|
| `attack_range` | Weapon reach. Ranged heroes shoot from here. Melee heroes usually have a small value. |
| `engage_radius` / `melee_range` | Physical contact range where a blocker can claim an enemy and stop it. |
| `guard_front_px` | How far ahead of the hold/rally point the blocker may intercept an approaching enemy. |
| `guard_back_px` | How far behind the hold/rally point the blocker may clean up a recently passed enemy. |
| `auto_seek_radius` | Optional hero archetype behavior. Default `0`: no autonomous hunting beyond the guard zone. |

Suggested defaults:

| Unit | guard_front_px | guard_back_px | Notes |
|---|---:|---:|---|
| Basic soldier | 120 | 70 | Protects rally, small cleanup grace. |
| Tank/melee hero | 150 | 100 | Stronger guard area, still not a map hunter. |
| Ranged hero | 0-60 | 0-40 | Usually shoots only; close block is emergency/self-defense. |
| Hybrid hero | 120 | 80 | Only if the archetype is explicitly dual-role. |

Guard zones should be evaluated against path progress when possible: project the hold/rally point onto the relevant path and compare enemy path progress to `[center - guard_back_px, center + guard_front_px]`. Use world-distance fallback only when path projection data is unavailable.

## Target Selection

For any blocker that is free or has remaining capacity:

1. Only consider ground, non-bypass enemies inside guard zone.
2. Prefer enemies with the fewest current blockers.
3. Then prefer enemies closest to the exit / highest path progress.
4. Then prefer nearest by world distance.

This prevents the bad player-feel case where multiple blockers dogpile one enemy while another walks through the chokepoint.

## Soldier Behavior

Soldiers are primary blockers.

State flow:

1. Hold at rally slot.
2. Detect enemies inside the rally guard zone.
3. Step/charge only within guard zone.
4. When in `melee_range`, call `enemy.engage_combat(self)`.
5. On success, stop moving and fight until one release condition occurs.
6. After release, scan again; if no guard-zone target exists, return to rally slot.

No long chase. If a target leaves the guard zone before contact, drop it and return.

## Hero Behavior

Heroes guard the last player-issued hold point.

Default hero behavior:

1. Player taps a position.
2. Hero moves there and sets `_rally_position` / hold point.
3. Hero does not auto-seek beyond the authored guard zone.
4. Hero attacks enemies in `attack_range`.
5. If an enemy enters close `engage_radius` and the hero has block capacity, hero may engage and stop it.
6. After combat, hero returns to the hold point if displaced and no valid guard-zone target remains.

Optional archetype behavior:

- `auto_seek_radius > 0` may allow a special hunter/patrol hero to pursue targets beyond the normal guard zone.
- This must be opt-in per `HeroData`; default heroes should not inherit it.

### Hero on the Path — visual contract

Heroes share the path Y with enemies during idle, attack, and return-to-hold. Three automatic behaviors enforce this without per-level marker tuning or per-hero data busywork:

- **Spawn / respawn auto-snap.** The hero's spawn position (from the `HeroSpawn` Marker2D) is auto-snapped to the nearest level `Path2D` within `SPAWN_SNAP_SLACK = 80 px`. Outside the slack, the marker wins (deliberate off-path spawns are still possible). Implemented in `BaseHero._snap_to_ground_line` via `GuardZone.snap_to_nearest_path`.
- **Tap-to-move auto-snap.** Player taps within `TAP_SNAP_SLACK = 40 px` of a path snap to the path. Outside the slack the raw tap wins, so the player can still place the hero off-road tactically (e.g. on a side rock). The destination ring (`_move_marker_pos`) draws at the snapped point so the visual matches where the hero will land.
- **Archetype-default guard zone.** Heroes with `attack_range < RANGED_ATTACK_RANGE_THRESHOLD` (150 px) auto-default to `guard_front_px = 150`, `guard_back_px = 100` when both are 0. Ranged heroes stay 0/0 (hold, shoot, don't chase). Any non-zero authored value wins. Implemented in `BaseHero._effective_guard_zone`; `_can_pursue` and `_is_seeking_allowed` route through it.

Net effect: the Warrior (`attack_range=75`) auto-gets a 150/100 guard zone and walks along the path to meet incoming enemies (via the existing `_engage_position_for` which already aligns hero Y to enemy Y on melee engagement). The Mage / Ranger / Necromancer stand on the path and shoot from there. Any future hero — melee or ranged — inherits the right behavior with zero per-hero authoring.

## Ranged and Hybrid Units

Ranged units should not voluntarily walk into melee just because they detected a target.

Default ranged behavior:

1. If target is in `attack_range`, fire projectile/ranged attack.
2. Enemy keeps walking unless physically blocked by someone.
3. If enemy enters `engage_radius` and the ranged unit has `max_block_targets > 0`, switch to close-combat engagement.
4. Close engagement can use a simple fallback melee profile at first, but long term should be authored data:
   - `close_attack_damage`
   - `close_attack_speed`
   - `close_damage_type`
   - optional `can_block`

Ranged units with `max_block_targets = 0` never stop enemies. This is appropriate for fragile casters like Necromancer unless a skill/summon provides the blockers.

Hybrid heroes are allowed, but should be authored deliberately. They are not the default ranged behavior.

## Enemy Behavior

Enemy pathing remains simple:

1. `WALKING`: advance along `PathFollow2D`.
2. `COMBAT`: stop path progress while `_blockers` is non-empty.
3. Counterattack oldest blocker (`_blockers[0]`) for stable telegraphing.
4. Prune invalid/dead blockers.
5. Return to `WALKING` when no blockers remain.

Do not give enemies broad pathfinding or avoidance. Fixed-path clarity is part of the tower-defense contract.

## Release Conditions

Normal releases:

- Enemy dies.
- Blocker dies.
- Player moves hero.
- Player changes barracks rally.
- Enemy refuses engagement through `bypass_engagement`.
- Explicit authored escape/phase behavior fires.

Before physical contact, leaving the guard zone cancels intercept. After physical contact, do not release merely because the enemy's path progress changed; the enemy is stopped by the lock.

## Implementation Plan for Claude

### Phase 1 - Data Fields

Add conservative data fields:

- `HeroData.auto_seek_radius: float = 0.0`
- `HeroData.guard_front_px: float = 0.0`
- `HeroData.guard_back_px: float = 0.0`
- optional later: `HeroData.close_attack_damage`, `close_attack_speed`, `close_damage_type`
- `SoldierData.guard_front_px: float = 120.0`
- `SoldierData.guard_back_px: float = 70.0`

Keep existing `attack_range`, `engage_radius`, `melee_range`, and `max_block_targets`.

### Phase 2 - Enemy Path Accessors

Add public read helpers on `BaseEnemy`:

- `get_path_id() -> String`
- `get_path_progress() -> float`
- `get_path_progress_ratio() -> float`

Use these instead of reaching into `_path_follow` from hero/soldier code.

### Phase 3 - Shared Guard-Zone Helper

Add small helpers near existing combat logic. Avoid a new global system unless duplication becomes painful.

Needed behavior:

- Determine whether an enemy is guardable for a blocker.
- Prefer path-progress checks when path id/projection are available.
- Fall back to world distance around hold/rally position.

If path projection is not yet convenient, ship world-distance guard first, but keep the API shaped so path-progress replacement is straightforward.

### Phase 4 - Soldier Rework

In `soldiers/base_soldier.gd`:

- `_scan_aggro_and_maybe_charge()` only considers guard-zone enemies.
- `_try_engage()` still requires `melee_range`.
- `_tick_charge()` cancels and returns if target leaves guard zone before contact.
- Once engaged, keep the lock until death/rally reset/enemy death.
- Target selection uses fewest blockers, then highest path progress, then nearest.

### Phase 5 - Hero Rework

In `heroes/base_hero.gd`:

- Turn default auto-seek off.
- Keep player tap movement and hold-point behavior.
- Attack ranged targets in `attack_range` without stopping them.
- Only call `_start_block()` when enemy overlaps `engage_range_area`.
- For melee heroes, allow short guard-zone intercept from hold point.
- For ranged heroes, do not intercept unless `guard_front_px/back_px` or `auto_seek_radius` is authored.
- After combat, return to hold point if displaced and no valid guard-zone target exists.

### Phase 6 - Ranged Close Combat

Short-term implementation:

- Ranged hero projectile attacks continue at range.
- If a ranged hero is physically engaged, either:
  - keep current damage but deliver it instantly in close combat, or
  - use authored close-combat fields when present.

Long-term polish:

- Add distinct close-combat animation/readability for ranged heroes.
- Give fragile casters `max_block_targets = 0` unless their identity says otherwise.
- Add explicit hybrid hero data for units like Vesper-style dual-role heroes.

### Phase 7 - Fix Existing Review Bugs While Touching Combat

Bundle these with the combat pass or immediately after:

- Projectile hero `ON_HIT_DEALT` should fire on projectile impact, not launch.
- Projectile hero `ON_KILL` should fire on actual projectile kill.
- Hero extra-block selection must use the same split rule as soldiers.
- `BaseEnemy.engage_combat()` should not reset attack cooldown when a second blocker joins an already-engaged enemy.

### Phase 8 - Tests

Add focused GUT tests:

- Enemy does not stop on detection alone.
- Enemy stops only after `engage_combat()`.
- Soldier chooses unblocked/highest-progress enemy over already-blocked target.
- Soldier cancels pre-contact chase when target leaves guard zone.
- Engaged enemy stays stopped until blocker/enemy death or rally reset.
- Ranged hero fires at range without blocking.
- Ranged hero only blocks when enemy enters close engage radius and `max_block_targets > 0`.
- Projectile hero on-hit/on-kill passives fire on impact.

## Tuning Notes

Start forgiving, then tighten:

- Give back-guard enough grace that a hero can clean up an enemy that only barely slipped by.
- Do not let guard zones become so large that blockers feel like hunters.
- If players complain that soldiers stand near enemies and let them pass, increase `guard_back_px` or improve target selection before increasing raw soldier damage.
- If barracks trivialize waves, reduce block capacity/survivability or add authored bypass/cleave enemies rather than making blockers chase less reliably.
