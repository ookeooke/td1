extends "res://systems/AbilityData.gd"
class_name OnHitBonusDamageAbility

# Phase 21: while active, adds flat bonus physical damage on every attack
# the owner lands. Used as the buff payload of Rally — set trigger=ON_HIT_DEALT
# and duration>0 so AbilityHost auto-removes when the buff expires.
#
# Applies as a secondary take_damage call. The original hit is unchanged;
# this ability's damage is a separate event (matches how "Lifesteal" / "Thorns"
# / "Burn" will work in later phases).

@export var bonus_damage: float = 6.0
@export var bonus_damage_type: int = 0  # DamageCalculator.DamageType.PHYSICAL


func apply(owner: Node, ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if ctx == null or not ctx.has("target"):
		return
	var target = ctx.get("target")
	if target == null or not is_instance_valid(target):
		return
	if not (target is BaseEnemy):
		return
	var enemy: BaseEnemy = target
	if enemy.state == BaseEnemy.State.DYING:
		return
	enemy.take_damage(bonus_damage, bonus_damage_type, owner)
