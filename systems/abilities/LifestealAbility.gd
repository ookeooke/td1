extends "res://systems/AbilityData.gd"
class_name LifestealAbility

# ON_HIT_DEALT: heals the owner by `heal_amount` each time they deal
# damage. Used for hero talents ("Vampiric Strike"), items, etc.

@export var heal_amount: float = 2.0


func apply(owner: Node, _ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if owner.has_method("heal"):
		owner.heal(heal_amount)
