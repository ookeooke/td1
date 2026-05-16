# Hero / Item Behavior Refactor Research Report

Date: 2026-05-16

## Short Summary

Keep the goal: any hero can equip any weapon-slot item unless a specific item says otherwise. A sword on a Mage or Ranger should work, but it should not automatically turn that hero into a melee swordsman. The clean AAA-style rule is: hero data decides behavior; items add power, triggers, skill changes, and optional visuals.

For this project, the best direction is:

- A sword equipped by a ranged hero increases that hero's normal ranged attack unless the item has a special authored effect.
- Ranged heroes keep their projectile / caster identity from `HeroData.projectile_scene`, `attack_range`, `detection_radius_px`, and `close_attack_*`.
- Items should affect heroes through `AbilityData` and stat modifiers, including `ON_HIT_DEALT`, `ON_HIT_TAKEN`, `ON_KILL`, `ON_DEATH`, and future skill modifiers.
- High-tier gear should add mechanics, not only bigger numbers.
- Do not make the weapon base type hard-switch combat behavior for all heroes; that would fight the Combat Blocking Doctrine and make balance fragile.

## Current Local Findings

The existing architecture is already close to the recommended shape.

### What already works

- `ItemBase.hero_restriction` defaults to empty, and `InventoryManager.equip()` treats empty as "any hero." Current authored weapons such as `base_iron_sword`, `base_steel_sword`, `base_hunter_bow`, and `base_apprentice_staff` all have empty restrictions.
- Item power is already expressed through `implicit_abilities` and rolled affixes. `ItemInstance.build_runtime_abilities()` duplicates base implicit abilities and affix abilities into live `AbilityData` resources.
- Hero stats are already computed from hero data + level + equipped item abilities through `BaseHero.compute_stats_for()` and surfaced to UI through `HeroStats.effective_for()`.
- Ranged hero behavior is already separate from item type. `BaseHero._resolve_attack_profile()` uses `HeroData.projectile_scene` for ranged attacks and swaps to `close_attack_*` only at face-contact range.
- Hero damage intake already triggers `AbilityData.Trigger.ON_HIT_TAKEN`, so "items react when the hero takes damage" is an intended extension point.

### What this means for "sword on ranged hero"

Today, a sword's `damage_flat` is a stat modifier. If a Mage equips an Iron Sword, the sword increases the Mage's effective damage, and the Mage still fires the Mage projectile because the projectile comes from `HeroData`, not from the item base.

That is the correct default. Player-facing fantasy can be explained as "the hero channels the blade's power through their own fighting style." If a unique sword should literally fire spectral blades, author that as a special item effect, not as the rule for every sword.

## External Research Notes

### Diablo IV: items should change play, not just arithmetic

Blizzard's Diablo IV overview says players should think about stats that change how they play rather than only solving math, and it frames legendary powers as ability-changing effects. It also notes items can boost individual talents / skills.

Source: https://news.blizzard.com/en-us/article/23189677/diablo-iv-feature-overview

Diablo IV's Loot Reborn update reduced affix counts and made affixes clearer and stronger, with examples like Movement Speed, Max Life, and ranks to a Core Skill.

Source: https://news.blizzard.com/en-us/article/24077223/galvanize-your-legend-in-season-4-loot-reborn

Design takeaway: keep common item lines readable, and reserve complex behavior changes for rare / legendary effects.

### Path of Exile: skills and item modifiers are separate but deeply connected

Path of Exile describes skills as itemized gems socketed into equipment, with support gems modifying skill behavior. Its item page describes item mods as prefixes/suffixes and rare items as up to six mods.

Sources:

- https://www.pathofexile.com/game
- https://www.pathofexile.com/item-data

PoE balance manifestos also separate local weapon damage, added damage to spells, global gem levels, and support effects. In one caster weapon update, GGG moved toward global spell-gem modifiers on caster weapons rather than only socket-local effects.

Source: https://www.pathofexile.com/forum/view-thread/2627116

Design takeaway: an item can improve a skill without dictating the animation or archetype. A caster weapon can power spells; a sword can power a projectile if the character's authored kit is projectile-based.

### Kingdom Rush / Ironhide: hero role and positioning stay readable

Ironhide's Kingdom Rush Battles guide recommends placing ranged heroes behind barracks so they can deal ranged damage while protected. Their Vesper guide treats melee+ranged as a deliberate dual-role hero, not a default behavior every hero gets. Their Paladin Barracks guide frames blockers as chokepoint tools that soak damage and buy time for towers.

Sources:

- https://support.ironhidegames.com/support/solutions/articles/4000223620-kingdom-rush-battles-beginners-guide
- https://support.ironhidegames.com/support/solutions/articles/4000223683-vesper-hero-guide-melee-ranged-attacker-in-kingdom-rush-battles
- https://support.ironhidegames.com/support/solutions/articles/4000223657-paladin-barracks-skills-breakdown-defend-the-lines-in-kingdom-rush-battles

Design takeaway: keep role readability. Ranged heroes should not accidentally become frontliners just because they equip a sword.

## Recommended Product Rule

Weapon-slot items are "combat focuses," not hard animation classes.

Default behavior:

- Any hero can equip any weapon-slot item if `hero_restriction` is empty.
- The item modifies the hero's existing authored attack profile.
- The hero's `HeroData` decides whether the basic attack is melee, projectile, magic, flying-capable, blocking-capable, or hybrid.

Special behavior:

- Unique / legendary items may add mechanical effects.
- Unique / legendary items may override or decorate visuals.
- A special sword can fire spectral blades, but a normal Iron Sword should not rewrite a Mage into a sword-thrower.

## Recommended Technical Direction

### 1. Keep current item equip semantics

Do not add class-wide weapon restrictions. Keep `hero_restriction` as an opt-in whitelist for exceptional items only.

Good examples:

- `hero_restriction = []`: any hero can use it.
- `hero_restriction = ["hero_dragon"]`: special dragon-only relic.

Bad default:

- "Swords are only melee."
- "Bows are only ranged."
- "Staffs are only mages."

That would make loot less exciting and create extra UI dead ends.

### 2. Add optional item tags for presentation, not hard behavior

Add later, when needed:

- `weapon_family`: `blade`, `bow`, `staff`, `relic`, `charm`, `sigil`
- `visual_effect_tags`: `spectral_blade`, `ember`, `frost`, `shadow`
- `affix_tags`: `offense`, `defense`, `skill`, `command`, `reactive`

These tags should drive UI, item art, affix pools, and optional VFX. They should not decide the core hero state machine.

### 3. Expand item-granted `AbilityData`

The safest next mechanics are additive scripts under `systems/abilities/`:

- `ThornsOnHitTakenAbility`: when hero takes damage, deal damage back to the source.
- `ShieldOnHitTakenAbility`: gain a short shield or damage reduction after taking a hit.
- `HealOnKillAbility`: heal when killing an enemy.
- `ProcOnHitAbility`: chance to slow, burn, chain, stun, or mark on basic hit.
- `LowHealthTriggerAbility`: fire once below a health threshold.
- `SkillModifierAbility`: change one authored hero skill by id.
- `CommandAuraAbility`: buff nearby towers or soldiers, matching the Two-Brain direction in `BALANCE.md`.

All should remain owner-agnostic where possible and use `AbilityData.apply(owner, ctx)`.

### 4. Split item power into three layers

Layer A: Personal stats

- Damage, max health, armor, attack speed, move speed, cooldown reduction.
- Already supported by `StatModifierAbility`.

Layer B: Reactive / trigger mechanics

- On hit dealt, on damage taken, on kill, on death, on interval.
- Mostly supported by `AbilityHost`; needs more item ability subclasses.

Layer C: Command / tower-facing power

- Tower range aura.
- Soldier durability aura.
- Upgrade discount aura.
- Marked target takes more damage from towers.

This is the most important long-term layer because tower defense gear should not make the hero solo the whole map.

### 5. Treat skill changes as explicit authored effects

Do not let every item mutate every skill. Use explicit ids:

- `skill_id = "skill_fireball"`
- `effect = "adds_burn"`
- `value = 3.0`

Good item fantasy:

- "Fireball splits into 3 smaller meteors."
- "Rally Cry also grants armor."
- "Volley fires spectral blades when a blade item is equipped."

Avoid:

- Global hidden rules like "sword changes all projectiles into swords."

## Damage-Taken Item Features

Hero damage intake is a strong design space because it makes melee heroes and ranged heroes care about different items.

Recommended effects:

| Effect | Good for | Notes |
|---|---|---|
| Thorns / retaliation | Tanks | Use `ON_HIT_TAKEN`, all outgoing damage through `DamageCalculator`. |
| Damage shield | All heroes | Great mobile readability; visual bubble. |
| Emergency heal | Fragile casters | Cooldown-gated, not constant sustain. |
| Rage stack | Warriors / hybrids | Taking damage grants temporary damage or attack speed. |
| Focus stack | Mages | Taking damage reduces next spell cooldown, capped. |
| Guard command | Commander builds | Taking damage buffs nearby towers or soldiers briefly. |
| Cheat death | Legendary-only | One proc per level or long cooldown. |

Guardrails:

- Every reactive item needs a cooldown or cap.
- Damage-taken effects should use final mitigated damage from `take_damage`, not raw incoming damage, unless explicitly authored otherwise.
- Effects that return damage must avoid infinite loops if enemies later get their own thorns.

## Item-Driven Hero Behavior Examples

Common / Magic:

- Iron Sword: +damage; any hero uses it through their normal basic attack.
- Apprentice Staff: +damage and +skill power; Warrior can equip it, but it does not turn Shield Bash into magic unless an explicit effect says so.
- Hunter's Bow: +damage and +attack speed; Mage can equip it and cast faster if the stats say so.

Rare / Epic:

- Frost Ring: basic attacks slow enemies.
- Captain Helm: soldiers near the hero gain armor.
- Elven Blade: every third hit launches a spectral slash from the hero's current attack profile.

Legendary:

- Sword of Falling Stars: ranged heroes fire spectral blades; melee heroes cleave in an arc.
- Tactician's Banner: towers near the hero gain range and first-shot damage.
- Demon Core: taking lethal damage triggers a one-time nova, then leaves the hero at 1 HP.

## Refactor Plan

### Phase 0: Documentation and tests

- Keep this report as the design reference.
- Add unit tests that prove current any-hero weapon equip behavior.
- Add unit tests that prove sword damage affects ranged hero projectile damage through effective stats.
- Add unit tests that prove `ON_HIT_TAKEN` abilities fire from `BaseHero.take_damage`.

### Phase 1: Terminology cleanup

- Keep `ItemBase.Slot.WEAPON` internally for save compatibility.
- In UI copy, consider "Weapon" or "Focus" depending on fantasy direction.
- Add `weapon_family` only when a real feature needs it.

### Phase 2: Reactive item mechanics

- Add `ThornsOnHitTakenAbility`.
- Add `LowHealthTriggerAbility` or a specific first legendary effect.
- Add VFX / combat text routing through existing EventBus/VFX patterns.

### Phase 3: Skill/item bridge

- Add a small skill modifier contract keyed by `skill_id`.
- Skill scripts read relevant modifiers from the hero's ability host or a helper.
- Keep all modified skill behavior authored and visible in item text.

### Phase 4: Command stats

- Implement the `BALANCE.md` Two-Brain architecture:
  - Personal stats affect the hero.
  - Command stats affect towers / soldiers / map control.
- Update Equipment UI to split "Personal" and "Command."

### Phase 5: Unique item visuals

- Add optional item-driven projectile/impact visual tags.
- Do not replace `HeroData.projectile_scene` globally for normal items.
- For a legendary sword that should shoot, author a unique projectile visual effect.

## Main Risks

### Risk: heroes become too strong and towers stop mattering

Mitigation:

- Cap damage percent affixes per item tier.
- Move high-tier item excitement into command stats and mechanics.
- Track hero damage share in `RunStats`.

### Risk: item text becomes unreadable

Mitigation:

- Follow Diablo IV Loot Reborn's readability lesson: fewer, stronger affixes.
- Keep common items simple.
- Put big behavior changes on rare / legendary items.

### Risk: ranged heroes lose identity

Mitigation:

- HeroData remains the source of combat behavior.
- Item visuals decorate; they do not overwrite the state machine.
- Hybrid behavior remains explicitly authored like Vesper-style heroes.

### Risk: ability triggers loop

Mitigation:

- Add cooldowns to reactive abilities.
- Tag reflected damage sources so thorns cannot recursively trigger thorns.
- Unit-test every new trigger.

## Final Recommendation

Implement "any hero can use any weapon-slot item" as the default rule, and keep combat behavior hero-authored.

For the user's sword example:

- Yes: Mage can equip a sword.
- Yes: the sword's stats should increase Mage's projectile damage.
- Yes: a special sword can make Mage shoot spectral swords.
- No: every sword should not automatically replace every ranged hero's projectile or force melee behavior.

That gives the loot freedom the user wants without breaking hero readability, blocking doctrine, or tower-defense balance.
