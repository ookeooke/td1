extends Resource
class_name UpgradeData

# One node in the permanent upgrade tree. Each upgrade grants a global
# multiplier/bonus identified by `effect_type`. Game systems query
# GameState.get_upgrade_multiplier(type) at the relevant moment
# (tower creation, hero spawn, spell cast, level start).

enum EffectType {
	ARCHER_DAMAGE_MULT,      # × damage on attack towers
	ALL_TOWER_RANGE_MULT,    # × range on all towers
	HERO_MAX_HEALTH_MULT,    # × max HP on hero
	HERO_DAMAGE_MULT,        # × attack damage on hero
	HERO_XP_MULT,            # × XP gained per kill
	SPELL_COOLDOWN_MULT,     # × cooldown (< 1.0 = faster)
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
