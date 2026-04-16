extends "res://systems/AbilityData.gd"
class_name HealAuraAbility

# First real port onto the ability system: Phase 15's healer shaman aura.
# Previously this was four flat fields on EnemyData + a dedicated
# HealArea Area2D + a HealTimer node in the scene. Now it's one Resource
# with three fields, no scene structure needed. Same visible gameplay.
#
# Set trigger = ON_INTERVAL and interval = 2.0 in the .tres.

@export var heal_range: float = 325.0
@export var heal_amount: float = 3.0


func apply(owner: Node, _ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	# Owner-agnostic contract, but this specific ability only makes sense
	# on an enemy (heals other enemies in range). Skip gracefully if an
	# ally-less subject somehow owns it.
	if not (owner is BaseEnemy):
		return
	var caster: BaseEnemy = owner
	if caster.state == BaseEnemy.State.DYING:
		return
	var r2: float = heal_range * heal_range
	var origin: Vector2 = caster.global_position
	for node in caster.get_tree().get_nodes_in_group("enemies"):
		if node == caster:
			continue
		if not (node is BaseEnemy):
			continue
		var ally: BaseEnemy = node
		if ally.state == BaseEnemy.State.DYING:
			continue
		if origin.distance_squared_to(ally.global_position) <= r2:
			ally.heal(heal_amount)
