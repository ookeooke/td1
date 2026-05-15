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

1. **Stop-on-claim, two stages — ONE melee pipeline for EVERY hero + soldiers. The only per-hero difference is the melee-engage RANGE.** Every hero uses the identical melee pipeline: when it commits to an enemy inside its **melee-engage range** (`HeroData.detection_radius_px`, the single per-hero tunable — big for the Warrior, small for casters), it `reserve()`s that enemy → the enemy **soft-stops** (halts path progress, stands and waits, does NOT counter-attack) → the hero walks to the Y-locked spot → on contact `engage_combat`/`_blockers` begins the **hard fight** (mutual damage, telegraphs). Soldiers do the same on a charge. There is **no melee/ranged archetype branch** in this pipeline. *Ranged DPS is a second tier, not a different melee rule:* a hero with a `projectile_scene` also shoots any enemy that is inside `attack_range` but **outside** its melee-engage range — that enemy is **never reserved and keeps walking** (the lane is only ever stopped by a hero/soldier standing in it, never from afar; the guarantee is now structural — a pure shot target is not `_seek_target_enemy` and not in `_blocked_enemies`, so `_sync_claim` never reserves it). When a shot enemy crosses into the melee-engage range the same melee pipeline takes over, and `_resolve_attack_profile()` swaps the shot for the weaker authored `close_attack_*` poke (a hero with no `close_attack_*` keeps shooting point-blank). Soft-stop ≠ combat; only contact is combat. Flying / `bypass_engagement` enemies ignore reservations (never stop). **Holding does NOT pause status-effect duration:** a held enemy still takes damage and still burns slow/stun/poison timers (the early-return only freezes path progress + walk animation; effects/abilities/death tick before it). Deliberate — setting up a slow then holding the enemy is not a duration-refund exploit. The melee-engage range is exposed to the dev balance UI as `engage_range_mult` (`BalanceOverrides` → `HeroTuning`/`BalanceSliders`, bake-to-`.tres` supported) and drawn as the always-visible warm ring under every hero.
2. A reserved OR `_blockers`-non-empty enemy holds position; it resumes the instant both are clear.
3. A blocker may intercept only inside its guard zone.
4. Once physical engagement succeeds, the lock persists until enemy death, blocker death, player move/rally reset, bypass behavior, or an explicit authored escape mechanic.
5. Blockers choose targets by protecting the line, not by tunnel vision.
6. Ranged DPS is a *second tier on top of* the one shared melee pipeline, not a separate melee rule: a projectile hero shoots enemies inside `attack_range` but outside its (small) melee-engage range; enemies inside the melee-engage range are meleed by the exact same pipeline the Warrior uses.
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
2. Detect enemies inside the rally guard zone (`_is_guardable` → `GuardZone.is_guardable`).
3. Commit to the best in-guard-zone enemy → `reserve()` it (stop-on-claim, Core Rule 1): **the enemy halts and waits**. Soldier then closes via direct straight-line move (CORE RULE 13) at the now-stationary enemy — it does NOT chase a moving target.
4. When in `melee_range`, call `enemy.engage_combat(self)` (hard fight).
5. On success, stop moving and fight until one release condition occurs.
6. After release, scan again; if no guard-zone target exists, return to rally slot.

`_sync_claim()` reconciles the reservation every frame (reserve the charge target / oldest engaged enemy, unreserve anything else); `_release_claim()` clears it on death/despawn. No long chase — if a target leaves the guard zone before contact it is unreserved (resumes walking) and the soldier returns to rally. Same stop-on-claim model as the hero.

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
- **Detection zone + approach phase (current model).** Hero anchors at `_rally_position` (the last player tap, or HeroSpawn at start). A circle of radius `HeroData.detection_radius_px` around the anchor is the operating zone. When an enemy enters the zone, hero leaves the anchor, walks to the engage spot (approach phase = `State.MOVING`, target = `_engage_position_for(enemy)` which Y-aligns hero with enemy on the path), then enters `State.COMBAT` once within `ENGAGE_ARRIVAL_TOLERANCE = 18 px` of the spot. The duel starts only after the hero arrives — never snap-engaged from a standing position. After release (enemy dies / leaks the zone / player issues a new move command), hero walks back to the anchor.

  No archetype split: the melee-engage range is `HeroData.detection_radius_px` for every hero (one single `DEFAULT_MELEE_ENGAGE_RANGE = 160` when authored 0), passed through the stat dict as `melee_engage_range` so the dev `engage_range_mult` slider + bake apply. Authored values: Warrior 280 (strides out far), Mage 90 / Ranger 100 / Necromancer 80 (small — they mostly shoot). Implemented in `BaseHero._effective_detection_radius` (reads `current_stats`) and `_pick_target_in_detection_zone`; `_seek_target` and `_can_pursue` route through them. The legacy `guard_front_px / guard_back_px / auto_seek_radius` fields remain on `HeroData` for back-compat but are no longer read.

  When multiple enemies are inside the detection zone, the **split rule** picks: fewest current blockers → highest path progress → nearest. Once engaged, `_auto_engage_extras` may claim additional targets up to `max_block_targets`; the rest walk past unblocked.

  **Melee approach = stop-on-claim + soldier-model direct move.** When the hero commits to an enemy it `reserve()`s it (Core Rule 1): the enemy halts where it stands and waits. The hero then closes the gap mirroring `BaseSoldier` (CORE RULE 13):
  - **Hero claims, enemy freezes.** `_sync_claim` (once/frame) reserves the hero's current target (`_target_enemy` in COMBAT, else `_seek_target_enemy`) and unreserves anything else — one choke-point, covers every target change. A claim that never reaches contact within `CLAIM_TIMEOUT = 4 s` (pathing failure) is dropped so an enemy can't be frozen forever. `_die()` calls `_release_claim()` explicitly (physics is skipped while DEAD).
  - **Close directly on the (now stationary) enemy.** The hero drives `velocity` straight at the enemy's position — no nav-agent path-following lag, and the target isn't moving, so it closes cleanly. Nav-agent is used only for the no-target "walk back to anchor" path.
  - **Engage spot Y is locked to the enemy's Y.** `_engage_position_for` melee returns `Vector2(enemy.x + sign(path_forward.x)·gap, enemy.y)` — same ground line, horizontal offset only. `gap = min(MELEE_ENGAGE_GAP_X, _effective_engage_radius() − ENGAGE_GAP_SAFETY)` clamped ≥ `MELEE_ENGAGE_DISTANCE`, always inside the block circle.
  - **Block on proximity (hard fight).** The decisive COMBAT trigger is `enemy in engage_range_area` — on contact `_start_block`/`engage_combat` begins mutual damage. Spot-arrival / face-contact remain backups. The hero **plants exactly where contact is made — no settle, lerp, or snap** (an earlier 0.1 s settle was removed: combined with the proximity trigger it caused a visible teleport, and stop-on-claim makes any settle pointless since the enemy is stationary). Ranged heroes are unchanged — they fire from where they stand when the enemy enters `attack_range_area`; the reservation just stops it walking out of range.

  **No doomed chase.** Before a melee hero commits to an approach, `_melee_chase_is_doomed` drops the target if the enemy is *faster* than the hero AND pulling away exit-ward (`path_forward · hero→enemy > 0.25`). The hero returns to the anchor instead of trailing a target it can never catch. The `_can_pursue` detection-zone boundary check remains the backstop for every other "stop chasing" case.

  **Forward cutoff — don't chase leakers.** The detection zone is a *circle* (it bounds *how far* the hero ranges); a separate path-progress test bounds *which direction*. `_has_leaked_past_anchor(enemy)` is true when the enemy's progress along its own path exceeds the anchor's projection by more than `GUARD_BACK_MARGIN_PX = 50`. Such enemies are skipped in `_pick_target_in_detection_zone` (never acquired) and rejected by `_can_pursue` (an in-progress approach aborts the instant the target crosses the margin → hero walks back to the anchor). This is the KR forward-guard + grace-margin pattern: the circle says "near me," the progress test says "still *in front of* me." **Acquire vs pursue use asymmetric margins (hysteresis):** `_pick_target_in_detection_zone` only *starts* an approach on an enemy still at/before the anchor (`GUARD_ACQUIRE_MARGIN_PX = 0`); once committed, `_can_pursue` allows follow-through up to `GUARD_BACK_MARGIN_PX = 50`. Harder to start a chase than to continue one — the hero never lurches toward an enemy that's about to leak, and an enemy hovering at the boundary (e.g. slowed) can't cause acquire/drop flicker. Beyond the pursue margin the enemy has won the position and belongs to the towers. `progress_delta` returns 0 with no path data (flying / off-path) so those are never mis-flagged as leakers (flying is filtered upstream regardless).

  **Soldier vs hero — shared stop-on-claim, different zone shape.** Both reserve their committed target so it halts and both close by direct move (no chasing a moving enemy). They still differ in *which* enemy they commit to: heroes use a detection-radius **circle** around a player-placed anchor (+ leaker cutoff / acquire-hysteresis); soldiers use the rally **guard zone** (`GuardZone.is_guardable`). That zone-shape split is intentional (heroes range, soldiers hold a chokepoint) — the engage *mechanism* (stop-on-claim) is now unified.

  **Enemy faces its blocker.** While halted in `State.COMBAT`, the enemy turns `_facing_dir` toward `_blockers[0]` instead of freezing on its last path heading, so the idle body agrees with the swing animation (which already aims at `_blockers[0]`).

Net effect: the Warrior (`attack_range=75`) auto-gets a 150/100 guard zone and walks along the path to meet incoming enemies (via the existing `_engage_position_for` which already aligns hero Y to enemy Y on melee engagement). The Mage / Ranger / Necromancer stand on the path and shoot from there. Any future hero — melee or ranged — inherits the right behavior with zero per-hero authoring.

### Combat Ground Line — every melee blocker fights at the enemy's Y

There is no single map "ground line" — enemies march in 3 lanes (`PathFollow2D.v_offset ∈ {−LANE_SPACING, 0, +LANE_SPACING}`, ±50 px, randomized per non-boss in `WaveManager.spawn_enemy`). The **authoritative ground line for a given enemy is its own `global_position.y`** — `v_offset` is baked into it, while walk-bob and `flight_height_px` are *draw-only* (applied in `UnitVisualDrawer`, never in `global_position`; the shadow sits at the true origin). So a blocker that matches the engaged enemy's `global_position.y` shares that enemy's lane *and* its shadow line — the duel reads as one fight on the road.

**Invariant:** every melee blocker — soldier, melee hero, and a ranged hero dropped into close-combat — picks its blocking spot via the single shared helper `GuardZone.melee_engage_spot(enemy_pos, path_forward, gap)`, which returns `Vector2(enemy_pos.x + sign(path_forward.x)·gap, enemy_pos.y)`: enemy's exact Y, horizontal `gap` offset toward the path-exit side only.

- `BaseHero._engage_position_for` (melee branch) calls it directly.
- `BaseSoldier._tick_charge` steers the straight-line charge at it (`gap = max(melee_range·0.8, 12)` so the spot stays inside `melee_range` and the normal `_try_engage` still fires on arrival; path-forward via `GuardZone.path_forward_at`, falling back to the horizontal sign toward the enemy). CORE RULE 13 preserved — still a direct straight-line move, only the *target* Y is corrected. Previously the soldier planted on melee-range contact wherever it happened to be (~30–50 px off-Y diagonally).
- The committed target is reserved (stop-on-claim) and therefore frozen, so the spot is stable while the blocker walks in — no moving-target jitter.
- **Reach the lane *during* the walk-in, never snap to it at the end.** The approach/charge steer (`BaseHero._ground_line_dir` / `BaseSoldier._ground_line_dir`, bias `APPROACH_Y_PRIORITY`) caps the horizontal direction component so the vertical (lane) gap closes at least as fast as the horizontal one: the blocker rises onto the enemy's Y on a ≤45° diagonal early, then continues straight along the line to the gap-offset spot. Without this, a far-X / small-Y approach closed Y at only ~0.1–0.3× move_speed and COMBAT (which can trigger early off-Y via `engage_radius`/proximity) handed a full lane of residual Y to the settle, which resolved it at full move_speed — a fast vertical "snap". The COMBAT-state settle (`> 4 px` guard) is now only a rarely-hit safety net, and it uses the same Y-biased dir so even then it slides in rather than popping. Speed is unchanged everywhere — only the steering *direction* changed.
- **Never pull the enemy to the path centerline** — that would teleport it up to 50 px and break the swarm read. The blocker comes to the enemy's lane, not the reverse.
- **Ranged-while-shooting is the deliberate exception.** A ranged hero firing from `attack_range` stands at `enemy + dir·(attack_range·0.8)` (Y free, far away) — it is not duelling, so it does not share the enemy's Y.

The block-claim circle a melee hero detects fightable enemies in is `_effective_engage_radius()` (NOT the larger `detection_radius_px` acquire scan). It is drawn as an always-visible faint warm ring under every hero in `BaseHero._draw()` (zoom-scaled; suppressed when `engage_radius ≈ 0`, i.e. a pure-sniper archetype that never melees).

### Flying units — body lift, shadow as ground truth

Flying enemies (and future flying heroes) use `UnitVisualData.flight_height_px` to lift their body sprite while the ground shadow stays glued to the unit's true ground-Y. Universal AAA convention — Kingdom Rush, Bloons, PvZ, Brawl Stars all do this. Wired in [UnitVisualDrawer.draw_unit](../systems/UnitVisualDrawer.gd) (body offset) + [UnitVisualDrawer.draw_ground_shadow](../systems/UnitVisualDrawer.gd) (height-aware scale + alpha).

- **Body draws at `-flight_height_px`** above the unit's local origin. Walk-bob and other animation offsets compose on top.
- **Shadow stays at `torso_r * 0.95` below local origin** (true ground position).
- **Shadow scales `1.0 → 0.55`** and **alpha dims `0.28 → 0.16`** linearly as flight height approaches `_MAX_FLIGHT_HEIGHT = 80 px`.
- Ground units leave the field at 0 (default).

Suggested values: small flyers (bats / harpies) `35-45`, medium fliers (eagles, gargoyles) `45-55`, dragon-class bosses `60-75`. Engagement gating (`max_block_targets`, `guard_front_px`, `is_flying`, `bypass_engagement`) remains data-authored separately — `flight_height_px` is *purely visual* and doesn't change what blocks / aggros what.

## Ranged and Hybrid Units

Ranged DPS is a **second tier layered on the one shared melee pipeline**, not a different melee rule (Core Rule 1). The melee rules are identical for every hero; casters simply have a **small melee-engage range** so they mostly shoot and only melee when something gets close. The "enemy KEEPS WALKING while shot from afar" guarantee is now **structural**: a pure shot target is not the approach target (`_seek_target_enemy`) and not in `_blocked_enemies`, so `BaseHero._sync_claim` never `reserve()`s it — there is no archetype `if`. An enemy shot from 250–320 px is not frozen because it is *outside the melee-engage range*, not because the hero "is ranged".

Default ranged behavior:

1. Enemy inside `attack_range` but **outside** the melee-engage range → fire projectile; enemy keeps walking (never reserved).
2. Enemy crosses **into** the melee-engage range → the *same* melee pipeline every hero uses takes over: reserve (soft-stop) → walk to the Y-locked spot → hard-block.
3. While hard-blocking (`_target_enemy in _blocked_enemies`), `_resolve_attack_profile()` swaps the shot for the weaker authored `close_attack_*` poke (`max_block_targets` still caps how many it can hold; `close_attack_damage = 0` ⇒ keeps shooting point-blank).
4. **A shot target that leaves `attack_range` is DROPPED, never chased.** `_attack_step` only repositions after range-loss if the hero was *physically blocking* that enemy (`_blocked_enemies.has(enemy)` captured BEFORE the release) **and** it is still inside the guard zone (`_can_pursue`) — that is a real melee lock following a near-leaker to the line. A pure ranged-shot target (never blocked/reserved) that walks out → hero drops it and goes IDLE (re-seek next target or return to anchor). Detection ≠ combat; a hero is a blocker, not a hunter — it must not convert a shot target into a chase.
5. **Close-combat attack — IMPLEMENTED (authored).** When a ranged hero (`projectile_scene` set) is physically blocking its focus enemy (`_target_enemy in _blocked_enemies`), `_resolve_attack_profile()` swaps the ranged shot for an authored melee poke:
   - `HeroData.close_attack_damage` — base poke damage (0 = unauthored → keep shooting point-blank, zero regression)
   - `HeroData.close_attack_speed` — poke cadence (typically faster than the ranged shot — you're flailing, not aiming)
   - `HeroData.close_attack_damage_type` — `-1` inherits `data.damage_type`; authored heroes use `0` (PHYSICAL) so the caster's MAGIC identity doesn't carry into the desperate jab
   - Close damage scales by the same gear/talent multiplier the ranged shot gets (`_effective_damage() / data.attack_damage`), so equipment still matters in melee — no "gear does nothing up close" cliff.
   - Trigger reuses existing block state (`_blocked_enemies`), no new Area2D/state. The instant-hit branch of `_attack_step` is shared with the Warrior's melee — one code path, fires `ON_HIT_DEALT/ON_KILL` inline.
   - Authored values (starter, balance-tunable): Ranger 0.6 dmg / 0.9 spd, Mage 0.5 / 0.7, Necromancer 0.55 / 0.8 — all PHYSICAL.

Ranged units with `max_block_targets = 0` never stop enemies, so they never enter close mode. This is appropriate for fragile casters unless a skill/summon provides the blockers. (Necromancer is now `max_block_targets = 1` — he can hold one enemy and scythe-poke it.)

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
- ~~optional later~~ DONE: `HeroData.close_attack_damage`, `close_attack_speed`, `close_attack_damage_type` — see "Ranged and Hybrid Units" §4
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
