# Hero Platform System Full Review

Date: 2026-05-16

## Verdict

Do not implement the entire 20-hero system in one pass.

The design direction is strong and scalable, but the professional way to ship it is in layers:

1. Prove the rule with one existing hero and one existing item family.
2. Add the data model and tests.
3. Add mobile UI that teaches the rule.
4. Add one special platform, such as Dragon / Flying Hero.
5. Add trapper / commander / exotic heroes after the core survives playtesting.

The system should be built as a data-driven hero platform architecture, not 20 custom hero scripts.

## Product Goal

Heroes are platforms. Items are build tools.

Player-facing rule:

> Any hero can use most items. The item stats work for everyone, but each hero has special mastery bonuses for certain item families.

Examples:

- Warrior can equip a staff and get stats, but gets special bonuses from swords and shields.
- Mage can equip a sword and get damage, but gets special bonuses from staffs and relics.
- Dragon can equip dragon gems / scales / claws and gets flying/breath bonuses.
- Trap hero gets special effects from trap kits, tools, and gloves.

This gives both freedom and identity.

## What Should Not Happen

Do not make item type hard-switch the hero's entire combat behavior.

Bad rule:

- "Sword means every hero now becomes melee."
- "Bow means every hero shoots arrows."
- "Staff means every hero becomes a caster."

That becomes unreadable fast and fights the existing Combat Blocking Doctrine.

Good rule:

- Hero behavior comes from `HeroData` / platform data.
- Item stats always apply when legal.
- Item affinity adds extra effects when the hero and item tags match.
- Unique items can author special visual or mechanical exceptions.

## Current Architecture Fit

The repo already supports most of the foundation:

- `ItemBase.hero_restriction` already allows "any hero" by default.
- `ItemBase.implicit_abilities` already attaches item power.
- `ItemInstance.build_runtime_abilities()` already builds live abilities from base + affixes.
- `AbilityData` / `AbilityHost` already support stat modifiers and event triggers.
- `BaseHero.compute_stats_for()` already computes effective stats from item abilities.
- `HeroStats.effective_for()` already prevents UI from reading naked base stats.
- `BaseHero._resolve_attack_profile()` already keeps ranged/projectile behavior hero-authored.
- `BaseHero.take_damage()` already fires `ON_HIT_TAKEN`.

So this is not a rewrite. It is a controlled extension.

## Recommended Final System

### 1. Hero Platform

Each hero gets platform data:

- Body platform: humanoid, flying, beast, large, tiny, mounted.
- Combat platform: blocker, ranged, flying interceptor, trapper, summoner, commander.
- Item affinities: sword, shield, staff, bow, trap, relic, dragon gem, scale, claw.
- Level curve: stat growth, skill points, passive slots, mastery unlocks.

Suggested future resources:

- `HeroBodyProfileData`
- `HeroCombatProfileData`
- `HeroLevelCurveData`
- `HeroItemAffinityData`

Do not create all four immediately unless needed. Start with affinity and level curve, because those are the smallest useful slices.

### 2. Item Tags

Add tags to `ItemBase`:

- `item_tags: Array[String]`

Example tags:

- `weapon`
- `sword`
- `shield`
- `bow`
- `staff`
- `relic`
- `trap`
- `dragon_gem`
- `scale`
- `claw`
- `commander`
- `skill`

Use tags for affinity matching, UI badges, loot filters, and affix pools.

### 3. Hero Affinities

Add `HeroItemAffinityData`:

- `affinity_id`
- `display_name`
- `required_item_tags`
- `rank_required`
- `bonus_abilities`
- `short_description`

Example:

Warrior + Sword:

- Rank 1: sword stats are 10% stronger.
- Rank 2: basic attacks cleave one nearby enemy.
- Rank 3: cleave can trigger on-hit effects.

Warrior + Shield:

- Rank 1: +armor from shields.
- Rank 2: taking damage grants Guard.
- Rank 3: Guard break retaliates.

Mage + Staff:

- Rank 1: +skill power.
- Rank 2: cooldown reduction.
- Rank 3: basic attacks apply elemental mark.

Dragon + Dragon Gem:

- Rank 1: breath damage.
- Rank 2: ground breath splashes.
- Rank 3: flying enemies burn longer.

### 4. Level Curve

Hero level-ups should give three reward types:

- Small stat growth.
- Skill / passive progression.
- Affinity / mastery progression.

Recommended stat growth:

| Stat | Default Growth |
|---|---:|
| Max HP | 5-8% per level |
| Damage | 4-6% per level |
| Skill Power | 2-4% per level |
| Move Speed | Usually none |
| Attack Range | Usually none |
| Armor / Magic Resist | Milestone only |

Recommended unlock cadence:

| Level | Reward |
|---:|---|
| 2 | +1 skill point |
| 3 | passive slot 1 |
| 4 | +1 skill point |
| 5 | affinity rank 1 |
| 6 | passive slot 2 |
| 7 | +1 skill point |
| 8 | affinity rank 2 |
| 9 | passive slot 3 or skill mod |
| 10 | capstone / affinity rank 3 |

This makes level-up more exciting than stat bumps alone.

### 5. Flying Heroes / Dragons

Dragon should not be a normal ground blocker.

Recommended dragon behavior:

- Body is flying, with ground shadow.
- Prioritizes flying enemies.
- Can intercept or duel flying enemies.
- Shoots/breathes projectiles at ground enemies.
- Does not stop ground enemies by default.
- May have a special dive / land skill that temporarily interacts with ground enemies.

Important: ground blocking and air interception should be separate rules.

Current `COMBAT_BLOCKING_DOCTRINE.md` is ground-blocker focused. A flying hero needs an additive "air combat" doctrine instead of being shoved into ground blocker logic.

Suggested dragon MVP:

- Dragon stays airborne.
- Dragon basic attack targets flying enemies first.
- If no flyers, dragon attacks ground enemies with a ranged breath projectile.
- No ground block.
- No air hard-lock in phase 1.

Later:

- Air intercept profile: dragon can hold one flying enemy in air combat.
- Flying enemies get a separate "air_blockers" or air reservation path.

### 6. Trapper Heroes

Trapper should also be a platform, not a one-off script.

Recommended trap behavior:

- Hero has normal weak ranged attack.
- Skills place traps on road.
- Trap items modify trap charges, radius, slow, damage, reset chance.
- Trap affinity makes trap items much better for trap heroes.

MVP:

- Active skill places a trap at tap point.
- Trap is an Area2D with one trigger effect.
- Trap item affinity gives +1 charge or +radius.

Do this after affinity and level curve are stable.

## Mobile UI Recommendation

Use four hero tabs:

- Overview
- Gear
- Skills
- Mastery

### Overview

Show identity, not spreadsheets:

- Hero name and level.
- Role tags.
- Power.
- Best item families.
- Current active affinity.
- Next level reward.

Example:

```text
Lv 7 Warrior
Ground • Blocker • Sword / Shield

Best With: Swords, Shields, Heavy Armor
Active: Sword Mastery I
Next Level: Shield Mastery I
```

### Gear

When selecting an item, show:

- Base stats.
- Affixes.
- Whether affinity is active.

Example for Warrior:

```text
Iron Sword
+5 Damage
+8% Attack Speed

Affinity Active:
Sword Mastery I
Basic attacks cleave nearby enemies.
```

Example for Mage:

```text
Iron Sword
+5 Damage
+8% Attack Speed

No Mage Affinity
Stats still apply.
```

This teaches the whole system in one screen.

### Mastery

Show hero-specific item masteries:

```text
Sword Mastery
I   +10% sword damage
II  Sword attacks cleave
III Cleave triggers on-hit effects

Shield Mastery
I   +8% armor from shields
II  Taking damage grants Guard
III Guard break retaliates
```

Rows should be tappable and open bottom-sheet details.

### Level-Up Popup

Keep it short:

```text
LEVEL 8

+22 HP
+3 Damage
+1 Skill Point

Unlocked:
Sword Mastery II
Sword attacks now cleave 2 enemies.
```

Do not show a full stat table on level-up unless the player taps details.

## Implementation Roadmap

### Phase 1 - MVP Affinity Slice

Goal: prove the core rule with existing Warrior + sword/shield.

Files likely touched:

- `items/ItemBase.gd`
- New `heroes/HeroItemAffinityData.gd`
- `heroes/HeroData.gd`
- `heroes/base_hero.gd`
- Selected `.tres` files for Warrior and sword/shield items
- Tests

Work:

1. Add `item_tags` to `ItemBase`.
2. Add `item_affinities` to `HeroData`.
3. Create `HeroItemAffinityData`.
4. When hero spawns, scan equipped items and attach matching affinity abilities.
5. Add tests:
   - Warrior + sword gets sword affinity.
   - Mage + sword gets sword stats but not sword affinity.
   - Empty `hero_restriction` still means any hero.

Ship only one visible effect first, likely Warrior sword cleave or shield thorns.

### Phase 2 - Mobile UI Teaching Pass

Goal: make the system understandable.

Work:

1. Gear tooltip shows "Affinity Active" / "No Affinity."
2. Overview shows best item families.
3. Add Mastery tab or compact mastery panel.
4. Level-up popup shows next unlock.

Do not proceed to dragons until this is clear on a phone screen.

### Phase 3 - Level Curve Resource

Goal: move level growth out of hardcoded constants.

Work:

1. Add `HeroLevelCurveData`.
2. Move default HP/damage growth there.
3. Add unlock rows for skill points, passive slots, affinity rank.
4. Keep old behavior as default fallback.
5. Add tests for level 1, 5, 10 stat outputs.

### Phase 4 - Dragon MVP

Goal: add one flying hero platform safely.

Work:

1. Add visual/body support if current `UnitVisualData.flight_height_px` is enough.
2. Author dragon HeroData as ranged, flying visual, no ground block.
3. Target flying enemies first.
4. Breath projectile at ground enemies.
5. Dragon-specific item tags: `dragon_gem`, `scale`, `claw`.
6. Add dragon affinity.

Avoid air hard-lock at first.

### Phase 5 - Air Intercept System

Goal: let dragons fight flying enemies in a special way.

Only implement if MVP dragon needs it.

Work:

1. Define air-combat doctrine.
2. Add air reservation / air engagement separate from ground blockers.
3. Keep flyers out of ground blocker code.
4. Add tests for "dragon can intercept flyer but cannot stop ground enemy."

### Phase 6 - Trapper Platform

Goal: add a non-standard hero without breaking combat code.

Work:

1. Build reusable trap scene/data.
2. Add trap placement skill.
3. Add trap item tags and affinity.
4. Add tests for charge count, trigger once, slow/damage application.

### Phase 7 - 20-Hero Content Sprint

Only after platforms are stable.

Use a small set of reusable platforms:

- Knight / blocker
- Ranger / anti-air
- Mage / caster
- Necromancer / summoner
- Dragon / flying
- Trapper / control
- Commander / tower aura
- Beast / fast melee

20 heroes should be combinations and `.tres` content, not custom scripts.

## Testing Requirements

Minimum tests before shipping Phase 1:

- Any-hero item equip still works.
- Restricted item declines wrong hero.
- Affinity activates only when tags match.
- Affinity ability is duplicated, not shared.
- Effective stats include normal item stats for non-affinity heroes.
- `HeroStats.effective_for()` includes affinity/stat effects if affinity is meant to affect display.
- `ON_HIT_TAKEN` item effect fires once and does not loop.

For dragon phase:

- Dragon targets flyers first.
- Dragon can damage ground enemies with projectile.
- Dragon does not ground-block by accident.
- Ground blockers still ignore flying enemies.

For trapper phase:

- Trap placement respects map/tap rules.
- Trap triggers exactly once or per authored trigger count.
- Trap effects route damage through `DamageCalculator`.

## Balance Rules

Keep Naked Baseline intact.

Hero levels and item affinities must not make gear mandatory for campaign progression. They should improve scores, survivability, and build expression.

Recommended power split:

- Hero base: 35%
- Hero level: 15%
- Items: 35%
- Skills / affinities: 15%

This is not a formula to hardcode; it is a design target. It prevents the worst failure modes:

- If hero base is too low, unequipped heroes feel broken.
- If items are too high, towers become irrelevant.
- If affinities are too high, off-theme builds become fake choices.
- If levels are too high, new players feel punished for not grinding.

## Main Risks

### Risk 1: Overengineering

If every possible platform is built now, the project will slow down.

Mitigation: ship Warrior affinity first.

### Risk 2: Hidden complexity on mobile

If players cannot see why an item is good, the system feels random.

Mitigation: show "Affinity Active" directly on item cards.

### Risk 3: Combat doctrine regression

Flying heroes and trapper heroes may accidentally break blocker behavior.

Mitigation: keep ground blocking, air combat, and trap placement separate.

### Risk 4: Hero damage dominates towers

Affinities and items can make heroes solo waves.

Mitigation: cap personal scaling and move late power into command / tower / control mechanics.

### Risk 5: 20 heroes become 20 scripts

Mitigation: every new hero must first try to fit an existing platform profile.

## Final Recommendation

Yes, this is the right professional direction, but no, do not implement everything at once.

Recommended next implementation:

1. Add item tags.
2. Add hero affinity data.
3. Make Warrior + sword/shield affinity work.
4. Show affinity status in Gear UI.
5. Add unit tests.

After that vertical slice feels good on mobile, add level curve data, then Dragon MVP.
