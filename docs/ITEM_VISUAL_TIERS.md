# Item Visual Tier Plan

This document defines the visual rules for generated or texture-based item art.
It is for item pictures only. Stats, rarity, affixes, drop rules, and item IDs
still live in `.tres` resources.

## Goal

Better items should look better through material quality, craftsmanship,
silhouette, and identity. The item PNG shows what the item is; `ItemIcon.gd`
shows rarity treatment such as borders, glow, pips, and UI effects.

Do not make higher-tier items better only by changing color.

## Project Asset Rules

All item texture assets should be:

- `512x640` PNG source/final size unless a specific item needs an exception.
- Transparent alpha.
- Object-only cutout.
- Bottom-up / 3/4 isometric-ish view.
- No baked background.
- No baked UI frame.
- No baked rarity border.
- No text, logo, watermark, or label.
- No character, mannequin, hand, arm, leg, or face wearing/holding the item.
- Readable inside the `120x144` equipment cells.

Generated chroma-key sources may be kept beside the final cutouts for iteration,
but item resources should reference the transparent final PNG.

Naming convention:

```text
base_<item_id>_<tier>_tier.png
base_<item_id>_<tier>_tier_source.png
```

Examples:

```text
base_iron_sword_magic_tier.png
base_steel_sword_rare_tier.png
base_demon_core_legendary_tier.png
```

## Style Direction

Use broad dark gothic ARPG traits without copying any named game asset:

- Grounded materials.
- Strong edge lighting.
- Worn surfaces.
- Muted palette.
- Realistic metal, leather, cloth, bone, crystal, and wood.
- High-detail object render.
- Clear mobile-sized silhouettes.

External research takeaway: AAA ARPG item art succeeds when the icon remains
readable in a dense inventory grid. More detail is useful only when it supports
the silhouette and material read.

## Tier Rules

### Common / White

Rough survival gear.

- Materials: rough wood, padded cloth, cracked leather, dull iron, bone, rope.
- Shape: simple, chunky, readable.
- Wear: heavy scratches, frayed seams, patches, chipped edges.
- Decoration: almost none.
- Magic: none.
- Feeling: found in a training yard or roadside kit.

### Magic / Blue

Competent crafted gear.

- Materials: forged iron, chain mail, hardened leather, copper, tarnished silver,
  small crystals.
- Shape: cleaner proportions than common.
- Wear: used, but maintained.
- Decoration: rivets, stitching, straps, small plates, simple wraps.
- Magic: tiny crystal or subtle material cue only.
- Feeling: made by a real blacksmith or apprentice enchanter.

### Rare / Yellow

Hero-ready gear.

- Materials: steel, polished leather, reinforced plates, carved wood, cut gems.
- Shape: more distinctive and heroic.
- Wear: battle-used but cared for.
- Decoration: engraved trim, heraldic marks, reinforced edges.
- Magic: faint inset gem, restrained rune carving.
- Feeling: a serious adventurer would keep this.

### Epic / Purple

Specialized, elegant gear.

- Materials: moonsteel, dark lacquered wood, enchanted leather, silver filigree,
  rare gems.
- Shape: iconic, asymmetric, refined.
- Wear: minimal or artful battle wear.
- Decoration: fine etching, layered construction, unique accents.
- Magic: subtle internal light or object-contained rune glow.
- Feeling: crafted for a specific hero fantasy.

### Legendary / Orange

One-of-a-kind artifact.

- Materials: infernal metal, obsidian, ancient gold, demon bone, angelic silver,
  living crystal.
- Shape: instantly recognizable.
- Wear: ancient, cracked, cursed, blessed, or historically marked.
- Decoration: sculptural detail and symbolic identity.
- Magic: stronger object-contained energy is allowed.
- Feeling: this item has a name and a story.

## Slot Ladders

Weapons:
Crude wood / chipped iron -> forged iron -> refined steel -> elegant enchanted
weapon -> impossible relic weapon.

Armor:
Padded cloth -> leather or chain -> reinforced plate -> ornate enchanted armor
-> relic armor.

Helms:
Leather cap -> metal-reinforced cap -> captain helm -> enchanted hood/helm ->
named crown or war mask.

Gloves:
Soft leather -> reinforced battle gloves -> plated gauntlets -> enchanted
grip/command gloves -> artifact handguards.

Boots:
Worn leather -> scout boots -> greaves -> enchanted stride boots -> relic boots.

Trinkets:
Bone charm -> crystal charm -> polished amulet/seal -> engraved relic ->
dangerous artifact core.

## Readability Rules

Every icon must work at mobile size. Check each item at `120x144`:

- Can the slot type be recognized in one glance?
- Does the silhouette differ from nearby items?
- Does it still read without zooming?
- Does detail support the shape instead of muddying it?
- Does it avoid looking like a full character, card, background, or scene?

If an item fails readability, simplify the silhouette before adding detail.

## Replacement Plan

Completed:

- Common / White tier.
- Magic / Blue tier.
- Rare / Yellow tier.
- Epic / Purple tier.
- Legendary / Orange tier.
- Static equipment-cell audit sheet at `tmp/imagegen/item_equipment_cell_audit_120x144.png`.

Next:

1. In-editor equipment-screen pass:
   Compare all tiers together inside the live EquipmentScreen `120x144` cells
   and adjust anything too noisy, too flat, too bright, or too similar after
   Godot can run locally.
