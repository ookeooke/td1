# Hero Item-First Platform Implementation Plan

Date: 2026-05-16

Audience: AI coding agents implementing the next phase.

## Goal

Move the game toward an ARPG-style hero platform system:

- Heroes are platforms with body type, skill tree, role tags, and item-family bonuses.
- Items provide most combat numbers and build direction.
- Every hero can use every normal item unless an item explicitly restricts itself.
- A hero can use off-family gear, but only matching families activate mastery / affinity bonuses.
- Legendary / unique items may break rules intentionally.

The intended fantasy:

- Warrior can equip a bow and shoot, but Warrior's tree mostly supports swords/shields.
- Mage can equip a sword and melee, but Mage gets no sword mastery unless explicitly authored.
- Dragon can equip dragon gems/scales/claws and prefers flying enemies, but still has item-driven builds.
- Trapper can use normal weapons, but trap items and trap skills are its main identity.

This is "freedom inside authored lanes."

## Core Design Decision

Commit to this rule:

> Equipped weapon profile defines the hero's basic attack, while HeroData defines body/platform identity, fallback behavior, skill tree, and item-family affinities.

That means:

- Normal weapon-slot items may carry `WeaponProfileAbility`.
- If a sword has a melee profile, any hero equipping that sword uses that melee profile.
- If a bow has a projectile profile, any hero equipping that bow uses that projectile profile.
- If no weapon profile is equipped, the hero falls back to `HeroData` attack fields.
- Hero affinities decide what the hero is especially good with.

This is different from the earlier "hero always keeps attack style" proposal. The user now prefers the more Diablo-like "heroes are platforms, item owns most stats/profile" approach.

## Current State In Repo

Already implemented framework:

- `items/ItemBase.gd`
  - Has `item_tags: Array[String]`.
  - Has `hero_restriction: Array[String]`, empty means any hero.

- `systems/HeroItemAffinityData.gd`
  - Defines required item tags and granted abilities.
  - Supports `min_affinity_rank`.

- `heroes/HeroLevelCurveData.gd`
  - Defines per-level growth, skill-point schedule, active slot unlocks, affinity ranks.

- `systems/HeroBodyProfile.gd`
  - Defines body flags and targeting priority.
  - Currently declarative; flying/no-ground-block is achieved with authored hero fields such as `max_block_targets = 0`.

- `systems/abilities/WeaponProfileAbility.gd`
  - Equipped weapon can own projectile/melee, range, damage type, base damage, attack speed, close attack values.

- `heroes/base_hero.gd`
  - Resolves item affinities at spawn.
  - Computes stats including affinity bonuses for display.
  - Has weapon profile lifecycle and profile-aware attack resolution.

- `systems/TrapData.gd`, `systems/Trap.gd`, `heroes/skills/place_trap_skill_data.gd`
  - Trap platform foundation exists.

- `autoloads/ContentRegistry.gd`
  - Has drift checks for affinities, curves, weapon profiles, body profiles, and traps.

- Tests exist:
  - `tests/unit/test_affinity.gd`
  - `tests/unit/test_level_curve.gd`
  - `tests/unit/test_weapon_profile.gd`
  - `tests/unit/test_body_profile.gd`
  - `tests/unit/test_trap_platform.gd`

Missing or incomplete:

- Existing item `.tres` files do not appear to have authored `item_tags`.
- Existing weapon `.tres` files do not appear to have authored `WeaponProfileAbility`.
- Existing hero `.tres` files do not appear to have authored `item_affinities`.
- Existing hero `.tres` files do not appear to have authored `level_curve`.
- No authored dragon hero.
- No authored trap skill using `PlaceTrapSkillData` in live hero content.
- No mobile UI for "Affinity Active" / "No Affinity" / "Best With" / Mastery.
- No real air-intercept system. `docs/HERO_MULTIMODE_ARBITRATION.md` says multi-mode is design-only.
- GUT could not be verified locally in this session because Godot headless crashes with signal 11.

## Implementation Philosophy

Make the smallest playable vertical slice first.

Do not build all 20 heroes now.
Do not implement air hard-lock now.
Do not implement complex legendary behavior now.

The next shippable goal is:

> Warrior equips tagged sword/shield items, gets visible affinity bonuses, and the mobile Gear UI clearly explains why.

After that:

> Mage/Ranger can equip the same items and still get item stats/profile, but no Warrior mastery.

Then:

> Add level-gated affinity ranks.

Then:

> Add Dragon MVP.

## Phase 1 - Author Item Tags And Weapon Profiles

### Files

- `items/bases/base_starter_sword.tres`
- `items/bases/base_wooden_sword.tres`
- `items/bases/base_iron_sword.tres`
- `items/bases/base_steel_sword.tres`
- `items/bases/base_elven_blade.tres`
- `items/bases/base_hunter_bow.tres`
- `items/bases/base_apprentice_staff.tres`
- Other weapon-like bases as needed.

### Work

Add item tags:

```gdscript
item_tags = Array[String](["weapon", "sword"])
```

Examples:

- Swords: `["weapon", "sword", "melee"]`
- Bow: `["weapon", "bow", "ranged", "physical"]`
- Staff: `["weapon", "staff", "ranged", "magic"]`
- Relic / charm: `["relic", "magic"]` or `["trinket", "relic"]`
- Armor: `["armor", "heavy"]`, `["armor", "light"]`
- Boots: `["boots"]`
- Future dragon gem: `["weapon", "dragon_gem", "ranged", "magic"]`

Add `WeaponProfileAbility` to weapon bases' `implicit_abilities`.

Sword profile:

- `projectile_scene = null`
- `weapon_attack_range = 75`
- `weapon_damage_type = PHYSICAL`
- `weapon_base_damage` roughly equal to current item implicit damage fantasy.
- `weapon_attack_speed` 0 if keeping hero speed, or set explicit if item should own speed.

Bow profile:

- `projectile_scene = res://projectiles/HeroArrow.tscn` or relevant arrow.
- `weapon_attack_range = 320`
- `weapon_damage_type = PHYSICAL`
- `weapon_attack_speed` explicit if desired.

Staff profile:

- `projectile_scene = res://projectiles/HeroBolt.tscn` or mage bolt.
- `weapon_attack_range = 270-320`
- `weapon_damage_type = MAGIC`

Important:

- Keep existing `StatModifierAbility` implicits unless intentionally replacing them.
- Avoid double-counting damage. `WeaponProfileAbility.weapon_base_damage` base-replaces, then affix ratio scales it.
- If a weapon sets `weapon_attack_speed` or `weapon_attack_range`, those are absolute final values per the current `WeaponProfileAbility` contract.

### Tests

Add/update tests:

- Every weapon base has at least `weapon` tag.
- Every sword base has `sword` tag.
- Every weapon base with `WeaponProfileAbility` is attack-viable.
- Mage + sword uses sword melee profile.
- Warrior + bow uses bow projectile profile.
- Unarmed fallback still works for Naked Baseline.

## Phase 2 - Author Warrior Affinities

### Files

- `heroes/data/hero_warrior.tres`
- Maybe new reusable affinity ability resources if not embedded as subresources.

### Work

Add `item_affinities` to Warrior.

Minimum Rank 1 affinities:

1. Sword Mastery I
   - `required_item_tags = ["sword"]`
   - `min_affinity_rank = 1`
   - Bonus: `StatModifierAbility.damage_pct = 0.10`
   - Text: "Swords deal 10% more damage."

2. Shield Mastery I
   - If shield slot/item exists: `required_item_tags = ["shield"]`
   - Bonus: armor or thorns.
   - If no shield item exists yet, delay shield until Phase 2b.

Optional Rank 2/3, but do not ship until Level Curve UI exists:

- Sword Mastery II: sword attacks cleave.
- Sword Mastery III: cleave triggers on-hit effects.
- Shield Mastery II: taking damage grants Guard.
- Shield Mastery III: Guard break retaliates.

### If Cleave Is Implemented

Prefer a new `AbilityData` subclass:

- `systems/abilities/CleaveOnHitAbility.gd`

Trigger:

- `ON_HIT_DEALT`

Behavior:

- Requires target is `BaseEnemy`.
- Finds nearby ground enemies around original target.
- Applies a percent of the original amount.
- Uses `enemy.take_damage(raw_amount, dtype, owner)` so `BaseEnemy` handles `DamageCalculator`.
- Does not hit the same target twice.
- Has a maximum target count.

For Phase 2, stat bonus is enough. Cleave can wait.

### Tests

- Warrior + sword tag grants Sword Mastery.
- Warrior without sword does not grant it.
- Mage + sword does not grant Warrior mastery.
- Affinity bonus appears in `BaseHero.compute_stats_for`.
- If shield added, Warrior + shield grants Shield Mastery.

## Phase 3 - Mobile UI Teaching Layer

### Files To Inspect

- `ui/EquipmentScreen.gd`
- `ui/HeroesHub.gd`
- Item tooltip / bottom sheet classes used by the equipment screen.
- Any item detail card / stats card helpers.

### Work

Create display helper functions, preferably not ad hoc UI logic.

Suggested new helper:

- `heroes/HeroAffinityPreview.gd` or static functions on an existing UI helper.

Inputs:

- `hero_id`
- `ItemInstance`
- optionally current equipped set.

Output dictionary:

```gdscript
{
  "active": true,
  "title": "Affinity Active",
  "lines": ["Sword Mastery I", "+10% sword damage"],
}
```

For no match:

```gdscript
{
  "active": false,
  "title": "No Mage Affinity",
  "lines": ["Stats still apply."],
}
```

Gear item detail should show:

```text
Affinity Active
Sword Mastery I
+10% sword damage
```

or:

```text
No Mage Affinity
Stats still apply.
```

Hero Overview should show:

```text
Best With: Swords, Shields
Active: Sword Mastery I
Next: Sword Mastery II at Lv 5
```

If a full Mastery tab is too large, add a compact Mastery panel first.

### Mobile UI Rules

- Do not show long formulas in the main panel.
- Use badges and 1-line descriptions.
- Put exact numbers in tap detail / bottom sheet.
- Always make off-family gear feel allowed, not broken.

### Tests

If UI helpers are pure enough:

- Preview says active for Warrior + sword.
- Preview says inactive for Mage + sword.
- Preview still says stats apply.

## Phase 4 - Author Level Curves

### Files

- `heroes/data/hero_warrior.tres`
- Later other hero `.tres` files.

### Work

Add `HeroLevelCurveData` as subresource or separate resource.

Recommended Warrior curve:

```gdscript
health_pct_per_level = 0.07
damage_pct_per_level = 0.05
attack_speed_pct_per_level = 0.0
active_slot_unlock_levels = [1, 8]
affinity_rank_by_level = {1: 1, 5: 2, 10: 3}
```

Be careful: Godot dictionary keys must behave as integers. The existing comment warns float keys can silently miss.

Use this cadence:

- Level 1: affinity rank 1.
- Level 5: affinity rank 2.
- Level 10: affinity rank 3 / capstone.

Do not make level stats too high. Items should still matter.

### Tests

- Warrior level 1 affinity rank = 1.
- Warrior level 5 affinity rank = 2.
- Warrior level 10 affinity rank = 3.
- Level 1 base stats remain playable.
- `HeroStats.effective_for` agrees with runtime compute path.

## Phase 5 - Add First Damage-Taken Item Feature

This closes the user's "what if heroes take damage and items do things" question.

### Suggested Ability

`systems/abilities/ThornsOnHitTakenAbility.gd`

Fields:

- `return_damage: float`
- `return_damage_type: int`
- `cooldown: float`
- `source_tag: String = "thorns"` if needed later to prevent recursion.

Trigger:

- `ON_HIT_TAKEN`

Behavior:

- If source is valid and has `take_damage`, damage source.
- Use raw damage into `take_damage`; target handles `DamageCalculator`.
- Add cooldown so dense melee does not explode balance.

### Authoring

Use it on Shield Mastery or a shield item:

- Shield item implicit: small thorns.
- Warrior Shield Mastery: thorns stronger.

### Tests

- Taking damage triggers thorns once.
- Cooldown prevents immediate second proc.
- Null source is safe.
- Does not crash on non-enemy source.

## Phase 6 - Trap Slice

Only after Phases 1-4 are visible.

### Files

- `heroes/data/skills/skill_snare_trap.tres`
- `heroes/data/hero_ranger.tres`
- `heroes/skills/place_trap_skill_data.gd`
- `systems/TrapData.gd`
- `systems/Trap.gd`

### Work

Convert or author one trap skill with `PlaceTrapSkillData`.

Trap MVP:

- Radius: 80-100 px.
- Damage: low.
- Slow effect optional, but can come later.
- Arm time: 0.5-0.8s.
- Lifetime: 10-15s.
- Max active: 2-3.

Add item tags:

- Trap gear: `["trap"]`
- Ranger/trapper affinity: `required_item_tags = ["trap"]`

First affinity:

- +trap radius or +1 max active.

### Tests

Existing trap tests cover base behavior. Add content tests:

- `skill_snare_trap.tres` uses `PlaceTrapSkillData`.
- trap_data is valid.
- Ranger has a trap affinity only if trap content is meant to be live.

## Phase 7 - Dragon MVP

Do not implement air hard-lock yet.

### Files

- New `heroes/data/hero_dragon.tres`
- New `heroes/data/visual_dragon.tres`
- New projectile scene if needed.
- `ContentRegistry` hero registration if catalog does not auto-glob.

### Dragon Data

Recommended:

- `body_profile.is_flying = true`
- `body_profile.blocks_ground = false`
- `body_profile.targeting_priority = AIR_FIRST`
- `max_block_targets = 0`
- `detection_radius_px = 0`
- `targets_flying = true`
- Weapon / breath profile handles attack.
- Visual has `flight_height_px > 0`.
- `role_tags = ["flying", "dragon", "ranged", "anti_air"]`

Dragon item families:

- `dragon_gem`
- `scale`
- `claw`

Dragon affinity Rank 1:

- `required_item_tags = ["dragon_gem"]`
- `damage_pct` or skill power bonus.

### Tests

- Dragon body profile does not block ground.
- Dragon targeting priority prefers flyers.
- Dragon can still shoot ground if no flyers.
- Ground blockers still ignore flyers.
- ContentRegistry drift checks pass.

## Phase 8 - Air Intercept, Later Only

Read first:

- `docs/HERO_MULTIMODE_ARBITRATION.md`

Do not implement air-intercept until mode arbitration exists.

Reason:

- A dragon that both intercepts flyers and breathes at ground has two autonomous attack modes.
- Current blocker state machine assumes one target owner per frame.
- Without arbitration, target/claim oscillation is likely.

When ready:

1. Implement mode priority on body/combat profile.
2. Add hysteresis/debounce.
3. Release claims on mode switch.
4. Add GUT tests for no oscillation.
5. Only then add air hard-lock.

## Phase 9 - 20 Hero Content Sprint

Only after Warrior, trapper, and Dragon MVP are stable.

Create heroes as combinations of existing platforms:

- Knight: sword/shield/blocker.
- Paladin: shield/heal/commander.
- Ranger: bow/trap/anti-air.
- Mage: staff/relic/magic.
- Necromancer: relic/summon/on-death.
- Dragon: dragon_gem/scale/flying.
- Beast: claw/fast melee/bleed.
- Engineer: trap/commander/bomb.

Do not create 20 custom scripts.

Each new hero should add:

- One `.tres` hero data file.
- One visual data file.
- One skill tree.
- Optional level curve.
- Optional item affinities.
- Tests only if it adds a new platform behavior.

## Balance Guardrails

### Naked Baseline

Every hero must function with no equipped item:

- Attack-viable fallback.
- Enough HP / movement to not break level start.
- No required gear for one-star campaign progression.

### Power Distribution Target

Use this as design guidance, not hard code:

- Hero platform/fallback: 25-35%
- Items/weapon profile: 35-45%
- Skills/tree: 15-25%
- Affinities/masteries: 10-20%

Affinities should reward matching gear, not make off-family gear fake.

### Avoid Hero-Solo Problem

If items make heroes too strong:

- Move late-game item power into command/tower/soldier auras.
- Cap personal damage percent stacking.
- Use cooldowns on reactive effects.
- Watch `RunStats.damage_by_source.hero`.

## Acceptance Checklist For Next Vertical Slice

The first slice is done when:

- At least one sword item has `item_tags`.
- At least one sword item has `WeaponProfileAbility`.
- Warrior has one authored sword affinity.
- Mage/Ranger can equip same sword and get item behavior without Warrior mastery.
- Gear UI tells player whether affinity is active.
- `HeroStats.effective_for` includes affinity bonus.
- GUT affinity/weapon tests pass in a stable Godot session.
- In-editor playtest confirms Warrior + sword and Mage + sword are understandable.

## Known Local Verification Issue

In this session:

- `godot` was not on PATH.
- Fallback Godot console at `C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe` crashed with signal 11 during headless GUT.

Future agents should try:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --quit
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

If still crashing, verify in the Godot editor and record that tests are locally blocked.

## Recommended Next Task

Implement Phases 1-3 for Warrior + sword only.

Do not start Dragon yet.
Do not start air-intercept yet.
Do not add more hero platforms until the mobile UI explains the first one clearly.
