class_name HeroStats
extends RefCounted

# Preventive Bug Rule (CLAUDE.md): UI never reads `hero_data.attack_damage`
# / `.max_health` etc. directly for display — always goes through here.
# Mirror of CORE RULE 14 (Tower Indicator Interface). Reading base HeroData
# stats for display silently ignores equipped-item modifiers and per-level
# growth — the exact bug the Hero Hall Overview shipped with until
# 2026-05-11. Routing through `effective_for(hero_id)` makes that class of
# bug structurally unrepresentable.
#
# This is a thin sugar wrapper over `BaseHero.compute_stats_for`. Callers
# pass a hero_id; we resolve hero_data + level + equipped items and return
# the same effective-stats Dictionary the in-level hero uses.
#
# Returned keys (see BaseHero.compute_base_stats line ~377):
#   max_health, damage, armor, magic_resist, attack_speed, move_speed,
#   attack_range, xp_gain_mult, skill_power, health_regen,
#   cooldown_reduction, dps (derived)
#
# Missing-data behavior: invalid hero_id returns an empty Dictionary so
# callers can short-circuit with a single `.is_empty()` check.

static func effective_for(hero_id: String) -> Dictionary:
	if hero_id == "":
		return {}
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null:
		return {}
	var level: int = MetaProgression.get_hero_level(hero_id)
	var equipped: Array = InventoryManager.get_all_equipped(hero_id)
	return BaseHero.compute_stats_for(hero_data, level, equipped)


# Base stats only — no equipped-item modifier stack. For UI that
# specifically wants to show the "naked" baseline (e.g. an item tooltip
# computing "+5 damage" relative to base). For everyday display use
# `effective_for`.
static func base_for(hero_id: String) -> Dictionary:
	if hero_id == "":
		return {}
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null:
		return {}
	var level: int = MetaProgression.get_hero_level(hero_id)
	return BaseHero.compute_base_stats(hero_data, level)
