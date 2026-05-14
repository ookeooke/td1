# Item Naming Plan

This document defines player-facing naming rules for item bases, rolled item
instances, affixes, and unique/legendary-style items. It does not change the
stable internal ID rules: `base_id`, `affix_id`, and filenames remain
snake_case, stable, and save-safe.

Read this with `docs/ITEM_VISUAL_TIERS.md`. Item visuals and item names should
escalate together: better gear should look better and sound more important.

## Research Notes

ARPG naming patterns worth borrowing in broad terms:

- Diablo-style magic items historically use readable prefix/suffix language,
  while rare/legendary items rely more on memorable fantasy names and affix
  lines than on every stat appearing in the item name.
- Path of Exile documents that Magic item names expose a prefix/suffix around
  the base name, while Rare items can have more modifiers and generated rare
  names. This is good for at-a-glance tier identity.
- Last Epoch-style itemization emphasizes affix tiers, item type, uniques, and
  build identity. The useful lesson is that names should help players sort
  "what kind of chase is this?" without making every item name too long.
- Player-facing feedback across ARPGs tends to favor clarity: names should be
  readable quickly, distinguish important items, and avoid becoming stat soup.

## Current Project Model

Current code displays:

- `ItemBase.base_name` as the item name.
- Each rolled affix as a separate line via `AffixData.display_template`.
- Rarity through UI color/border, not through the item name itself.

That is a good mobile-first baseline. Do not rush into generated rare names
until the equipment UI has room for them.

## Hard Rules

- Never change `base_id`, `affix_id`, or filenames after release.
- Player-facing names may be polished before release, but avoid casual churn
  after screenshots, saves, or guides depend on them.
- Keep names short enough for the equipment bottom sheet and mobile cards.
- A base item name should identify the object, not list stats.
- Affix display lines should explain stats clearly.
- Unique/legendary names should imply identity, origin, or fantasy role.
- Avoid joke names, meme names, modern slang, and direct references to other
  games.
- Avoid overusing apostrophes. Use them only when ownership matters.

## Name Length Targets

Base item names:

- Ideal: 2 words.
- Acceptable: 1 to 3 words.
- Avoid: 4+ words unless the item is unique/legendary.

Affix display lines:

- Ideal: one compact stat line.
- Example: `+12% Damage`
- Avoid: long prose inside affix lines.

Unique/legendary names:

- Ideal: 2 to 4 words.
- Can be poetic, but must remain pronounceable.

## Rarity Naming Rules

### Common / White

Plain object names. Practical and humble.

Patterns:

- Material + item: `Wooden Sword`, `Leather Cap`
- Condition + item: `Worn Boots`, `Padded Tunic`
- Training role + item: `Training Gloves`, `Training Sword`

Avoid:

- Grand titles.
- Magic words.
- Named ownership.

Good examples:

- `Wooden Sword`
- `Training Sword`
- `Padded Tunic`
- `Worn Boots`
- `Lucky Charm`

### Magic / Blue

Crafted or lightly enchanted names. Still object-forward.

Patterns:

- Craft/material + item: `Iron Sword`, `Chain Mail`
- Role + item: `Scout Boots`, `Battle Gloves`
- Apprentice/caster cue + item: `Apprentice Staff`, `Apprentice Charm`

Avoid:

- Too much mystery.
- Legendary-sounding titles.
- Names that imply rare/epic power.

Good examples:

- `Iron Sword`
- `Chain Mail`
- `Leather Cap`
- `Battle Gloves`
- `Scout Boots`
- `Apprentice Charm`

### Rare / Yellow

Hero-ready names. More specific, but still readable.

Patterns:

- Refined material + item: `Steel Sword`
- Role/owner type + item: `Captain's Helm`, `Archer Gloves`
- Virtue/concept + item: `Amulet of Wisdom`
- Culture/faction hint + item: `Hunter's Bow`, `Focus Hood`

Avoid:

- Full legendary identity.
- Too many proper nouns.
- Names that sound generic after the first word is removed.

Example direction:

- `Steel Sword`
- `Hunter's Bow`
- `Captain's Helm`
- `Amulet of Wisdom`

### Epic / Purple

Specialized, elegant, and slightly mythic. These names can imply origin or
craft tradition.

Patterns:

- Culture/fantasy lineage + item: `Elven Blade`
- Role/title + symbol: `Commander's Seal`
- Guardian/protector + item: `Guardian Greaves`
- Evocative material + item, if the material exists in the setting.

Avoid:

- Overlong lore sentences.
- Random fantasy syllables without meaning.

Example direction:

- `Elven Blade`
- `Guardian Greaves`
- `Commander's Seal`

### Legendary / Orange

One-of-a-kind artifact names. These should sound named, not merely described.

Patterns:

- Threat/source + object: `Demon Core`
- Proper name + object: `Varkul's Heart`, only when the lore exists.
- Object + of + strong concept: `Crown of Ash`, `Bell of the Grave`.

Avoid:

- Naming every legendary after an unknown person.
- Generic adjectives like `Ultimate`, `Supreme`, `Ancient` unless backed by
  art/lore.
- Long names that will not fit mobile UI.

Example direction:

- `Demon Core`
- `Crown of Ash`
- `Grave Bell`
- `Saintbone Key`

## Slot Naming Vocabulary

Weapons:

- Common: wooden, training, worn, chipped.
- Magic: iron, forged, apprentice, militia.
- Rare: steel, hunter, captain, veteran.
- Epic: elven, moonlit, guardian, command.
- Legendary: demon, saintbone, infernal, oathbound, ash.

Armor:

- Common: padded, worn, patched.
- Magic: chain, leather, reinforced.
- Rare: plate, captain, warded.
- Epic: guardian, runed, oathbound.
- Legendary: relic, saint, grave, infernal.

Helms:

- Common: cap, hood.
- Magic: leather cap, scout hood.
- Rare: helm, captain's helm, focus hood.
- Epic: war mask, guardian helm, runed hood.
- Legendary: crown, deathmask, saint helm.

Gloves:

- Common: gloves, wraps.
- Magic: battle gloves, bracers.
- Rare: archer gloves, plated gloves.
- Epic: command grips, runed gauntlets.
- Legendary: relic gauntlets, demon grips.

Boots:

- Common: worn boots.
- Magic: scout boots.
- Rare: greaves, stride boots.
- Epic: guardian greaves, windstep boots.
- Legendary: relic boots, ashwalkers.

Trinkets:

- Common: charm, token.
- Magic: apprentice charm, focus stone.
- Rare: amulet, seal, talisman.
- Epic: commander's seal, relic charm.
- Legendary: core, crown, bell, key, heart.

## Affix Naming Rules

Internal affix IDs stay mechanical:

```text
affix_damage_pct
affix_hp_flat
affix_cooldown_reduction_flat
```

Display templates should be clear and stat-forward:

```text
+{value}% Damage
+{value} Health
+{value}% Attack Speed
+{value}s Cooldown Reduction
```

Use fantasy-flavored affix names only if the UI later supports separate
affix titles. Until then, stat clarity wins.

Future optional affix title pattern:

- Offensive prefix titles: `Keen`, `Savage`, `Merciless`, `Hunter's`.
- Defensive prefix titles: `Stalwart`, `Reinforced`, `Warded`, `Ironbound`.
- Skill prefix titles: `Focused`, `Arcane`, `Blessed`, `Runed`.
- Mobility prefix titles: `Swift`, `Fleet`, `Scout's`, `Wind-touched`.

Do not display both a poetic affix title and an unclear stat. If space is
limited, show the stat.

## Future Rolled Item Name Pattern

Do not implement this until the UI has been designed for it.

Potential pattern:

- Common: `Base Name`
- Magic: `Prefix Base Name` or `Base Name of Suffix`
- Rare: generated fantasy name + base type subtitle
- Epic: authored base name, maybe with a subtitle
- Legendary: authored unique name only

Examples:

```text
Common: Wooden Sword
Magic: Keen Iron Sword
Magic: Chain Mail of Mending
Rare: Ashen Brand
      Steel Sword
Epic: Elven Blade
Legendary: Demon Core
```

Mobile warning: this pattern needs careful UI layout. Current UI should keep
using `base_name` plus affix lines.

## Naming Checklist

Before adding or renaming an item:

- Does `base_id` match the filename basename?
- Is the player-facing name short?
- Does the name match the visual tier in `ITEM_VISUAL_TIERS.md`?
- Does it identify the slot/type quickly?
- Does it avoid promising mechanics the item does not have?
- Is the name distinct from existing items in the same slot?
- Would it still make sense if the item rolled different affixes?

