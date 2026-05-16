# Hero Premium Visual Doctrine

This document saves the Necromancer premium visual style as the reference for
future hero upgrades. Use it as art/engineering guidance before expanding the
same drawing language to other heroes.

## Goal

Premium hero visuals should read like hand-drawn, high-polish game characters
inside the existing procedural drawing system. The goal is not more decoration.
The goal is clearer silhouette, stronger animation poses, better facing read,
and class identity without changing gameplay.

Necromancer is the current reference implementation in:

- `systems/UnitVisualDrawer.gd`
- `heroes/data/visual_necromancer.tres`
- `projectiles/Arrow.gd` for NecroBolt-specific projectile visuals
- `projectiles/NecroBolt.tscn` for cosmetic projectile exports

## Hard Rules

- Visual-only passes must not change damage, cooldown, targeting, speed,
  range, health, economy, or balance data.
- Stats stay in `.tres` Resources, never hardcoded in drawing scripts.
- Premium visuals must remain below gameplay UI: HP bars, selection rings,
  targeting UI, and status indicators stay readable.
- Avoid one-frame pop. New layers should be gated by eased pose weights such
  as `smoothstep(0.0, 1.0, weight)`.
- Do not mirror the whole character with scale hacks. Use pose offsets,
  width changes, layer visibility, and part transforms.
- Prefer adding one clear pose/layer rule over many tiny decorative effects.

## Reference Draw Order

Use a part-rig mindset. Each major body mass gets a transform or local pose
channel, then helpers draw simple local geometry.

Recommended order:

1. Ground effects: shadow, rune, wisps, foot dust if used.
2. Back layer: cape, cloak, back cloth, rear silhouette.
3. Torso layer: robe/body/chest panels.
4. Arms and weapon: hands, staff/sword/bow, swing smears, impact flashes.
5. Back-facing overlay when needed: cloak/yoke that covers upper torso/arms.
6. Head layer: hood/face/hair/eyes.
7. External UI remains outside this drawer.

Necromancer uses a back-facing cape overlay after arms/staff so the cloak can
visibly cover the upper-back pose when the hero turns away.

## Motion Channels

Premium hero drawers should consume a small shared motion vocabulary instead
of inventing ad hoc state per helper.

Core channels:

- `body_turn`: horizontal facing/torso yaw, usually from `ctx["face"].x`.
- `facing_depth`: vertical facing, usually from `ctx["face"].y`.
- `front_facing`: `max(facing_depth, 0.0)`; down/toward-camera pose.
- `back_facing`: `max(-facing_depth, 0.0)`; up/away-from-camera pose.
- `move_weight`: 1 while moving, 0 otherwise.
- `attack_weight`: wind-up or strike visibility.
- `cast_weight`: cast wind-up or cast release visibility.
- `cast_release`: short release beat after a spell fires.
- `cast_recover`: follow-through/settle after release.
- `key_recoil`, `key_passing`, `key_high`: keyed walk accents layered over
  smooth gait.

These channels should be computed once, then passed to body, cape, arms, and
head helpers. That keeps poses coherent.

## Facing Rules

Front-facing:

- Open the robe/chest read.
- Lower or tilt the head slightly toward camera.
- Show eyes/face/chest pendant/class icon more clearly.
- Let both hands read when the action needs it.
- Keep cape narrower and mostly behind the character.

Back-facing:

- Fade or hide face, eyes, mouth, pendant, and front trim.
- Emphasize hood back, cape, yoke, shoulder cloth, and rear silhouette.
- Let cloak/back overlay cover some arms or weapon pieces.
- Tuck staff/weapon upward/back so it feels behind the body.
- Use smooth fade-in, not a fixed base alpha that appears suddenly.

Side-facing:

- Keep the current readable class silhouette.
- Show one eye or one hand more strongly than the far side.
- Use torso/head/cape lag to imply turning, not full sprite mirroring.

## Hand-Drawn Style Rules

- Prefer uneven polygons, rough line helpers, and weighted ink over perfect
  vector symmetry.
- Use stepped secondary motion for cloth, idle hand jitter, and small magical
  flickers. Primary movement can stay smooth.
- Cel overlays should create mass: shadow-side wash plus lit rim.
- Effects should support the silhouette, not bury it. Projectile trails,
  smears, and glows should be smaller than the readable body/action shape.
- Strong action beats need anticipation, commit, impact, and recovery. A tiny
  single-frame twitch does not read well on mobile.

## Weapon And Attack Rules

Melee:

- Weapon tip should lead the strike more than the grip.
- Use separate wind-up, sweep, impact, and recovery windows.
- Add subtle crescent smear during sweep and small impact spark/flash at the
  weapon tip.
- Keep body motion restrained unless gameplay movement actually changes.

Casting:

- Pre-cast wind-up should charge the staff/orb/rune before the projectile
  appears.
- Release should snap forward, then recover. Avoid flat alpha decay only.
- Cast VFX should make timing clearer without changing actual ability logic.

Projectiles:

- Keep projectile gameplay exports stable unless the task is explicitly a
  balance/gameplay change.
- Shape should identify the class at small size: silhouette first, details
  second.
- Trails need underlay, core line, and optional motes, but avoid large blobs
  that make basic attacks look like ultimates.

## Expansion Plan

Do not immediately rewrite every hero into a large framework.

Recommended path:

1. Keep Necromancer as the reference implementation.
2. Use this doctrine for the next premium hero.
3. Extract only helpers that repeat across two heroes.
4. After three heroes, formalize a small premium hero visual API.

Likely reusable helpers later:

- Motion channel builder.
- Part rig builder.
- Front/back facing weights.
- Cape/cloak overlay helper.
- Rough ink and cel overlay utilities.
- Weapon swing phase and tip-led smear helpers.

## Review Checklist

Before finishing a premium hero visual pass:

- `git diff --check` passes.
- No gameplay exports changed unintentionally.
- Dead helper code was removed or clearly retained for a planned caller.
- Front, side, and back poses have distinct silhouettes.
- Cape/cloak/hair/weapon layer order supports the current facing.
- Effects read at mobile size and do not hide the character.
- Session notes were appended to `SESSIONS.md`.
