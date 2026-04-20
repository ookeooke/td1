extends Resource
class_name AffixData

# One rollable modifier line. Authored as .tres. At drop time the roller picks
# a uniform value in [value_min, value_max], duplicates ability_template, and
# injects that value into the duplicate. The duplicate is what gets attached
# to the ItemInstance — the template itself is never mutated (shared across
# instances, AbilityData discipline).

@export var affix_id: String = ""                       # stable; matches filename
@export var display_template: String = "+{value}"       # {value} substituted for UI
@export var value_min: float = 1.0
@export var value_max: float = 5.0
@export var value_is_int: bool = true
@export var ability_template: Resource                   # an AbilityData subclass (e.g. StatModifierAbility)
@export var ability_value_property: String = ""         # name of the numeric field on the template to inject into
@export var allowed_slots: Array[int] = []              # empty = any slot
@export var weight: float = 1.0


func roll_value(rng: RandomNumberGenerator = null) -> float:
	var v: float
	if rng != null:
		v = rng.randf_range(value_min, value_max)
	else:
		v = randf_range(value_min, value_max)
	if value_is_int:
		return float(roundi(v))
	return v


# Produce the live AbilityData for a given rolled value. The template is
# duplicated so multiple instances don't share mutable state.
func make_rolled_ability(rolled_value: float) -> Resource:
	if ability_template == null:
		push_warning("[AffixData] %s missing ability_template" % affix_id)
		return null
	var dup: Resource = ability_template.duplicate(true)
	if ability_value_property != "" and ability_value_property in dup:
		dup.set(ability_value_property, rolled_value)
	return dup


func format_display(rolled_value: float) -> String:
	var s: String
	if value_is_int:
		s = str(int(rolled_value))
	else:
		s = "%.1f" % rolled_value
	return display_template.replace("{value}", s)
