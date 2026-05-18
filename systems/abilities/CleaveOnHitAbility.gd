extends "res://systems/AbilityData.gd"
class_name CleaveOnHitAbility

# Phase 2 offensive affix. ON_HIT_DEALT: deals `cleave_pct × hit_amount` to up
# to `max_targets` OTHER enemies within `radius` of the struck target. Turns a
# single-target weapon into a soft AoE.
#
# Mirrors the canonical splash query in projectiles/Arrow.gd (one
# get_nodes_in_group("enemies") scan + distance_squared_to gate) — fired on a
# discrete hit event, never per-frame, so it respects the mobile perf rule.
# Owner-agnostic; secondary-take_damage pattern. `cleave_pct` is rolled by the
# affix; `radius` / `max_targets` / type are fixed on the template.

@export var cleave_pct: float = 0.0           # fraction of the hit, rolled
@export var radius: float = 85.0
@export var max_targets: int = 2
@export var bonus_damage_type: int = 0        # DamageCalculator.DamageType.PHYSICAL


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
	if cleave_pct <= 0.0 or max_targets <= 0:
		return
	var hit_amount: float = float(ctx.get("amount", 0.0))
	if hit_amount <= 0.0:
		return
	var splash: float = cleave_pct * hit_amount
	var origin: Vector2 = enemy.global_position
	var r2: float = radius * radius
	var struck: int = 0
	for other in owner.get_tree().get_nodes_in_group("enemies"):
		if struck >= max_targets:
			break
		if other == enemy or not (other is BaseEnemy):
			continue
		if other.state == BaseEnemy.State.DYING:
			continue
		if origin.distance_squared_to(other.global_position) <= r2:
			other.take_damage(splash, bonus_damage_type, owner)
			struck += 1
