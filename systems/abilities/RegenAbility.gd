extends "res://systems/AbilityData.gd"
class_name RegenAbility

# ON_INTERVAL: heals the owner by heal_amount each tick. Used for Mana
# Shield buff, enemy regen, healing items, shrine effects, etc.

@export var heal_amount: float = 3.0


func apply(owner: Node, _ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if owner.has_method("heal"):
		owner.heal(heal_amount)
	elif "current_health" in owner and "data" in owner and owner.data != null:
		var max_hp: int = owner.data.max_health
		if owner.has_method("_effective_max_health"):
			max_hp = owner._effective_max_health()
		owner.current_health = mini(max_hp, owner.current_health + int(ceil(heal_amount)))
		owner.queue_redraw()
