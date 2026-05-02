extends Resource
class_name UpgradeData

# One node in the permanent upgrade tree. Each upgrade grants a global
# multiplier/bonus identified by `effect_type`. Game systems query
# GameState.get_upgrade_multiplier(type) at the relevant moment
# (tower creation, hero spawn, level start).

# Position 5 (`_RETIRED_SPELL_COOLDOWN`) is a legacy slot — was
# `SPELL_COOLDOWN_MULT` until the 2026-05-01 spell-system retirement.
# Kept as a placeholder so STARTING_GOLD_BONUS and SOLDIER_HEALTH_MULT
# stay at integer values 6 and 7 — existing UpgradeData .tres serialize
# `effect_type` as an int and would shift if we removed the slot.
enum EffectType {
	ARCHER_DAMAGE_MULT,      # × damage on attack towers
	ALL_TOWER_RANGE_MULT,    # × range on all towers
	HERO_MAX_HEALTH_MULT,    # × max HP on hero
	HERO_DAMAGE_MULT,        # × attack damage on hero
	HERO_XP_MULT,            # × XP gained per kill
	_RETIRED_SPELL_COOLDOWN, # was SPELL_COOLDOWN_MULT — slot kept for stable indexing
	STARTING_GOLD_BONUS,     # + flat gold at level start
	SOLDIER_HEALTH_MULT,     # × max HP on soldiers
}

@export var upgrade_id: String = ""
@export var upgrade_name: String = ""
@export_multiline var description: String = ""
@export var star_cost: int = 1
# Empty = no prerequisite. Otherwise the upgrade_id of the required node.
@export var prerequisite_id: String = ""
@export var effect_type: int = EffectType.ARCHER_DAMAGE_MULT
# Interpretation depends on type:
#   MULT types: 1.2 = +20%. Stacks multiplicatively with other upgrades.
#   BONUS types: 25 = +25 flat. Stacks additively.
@export var effect_value: float = 1.0
@export var icon: Texture2D
