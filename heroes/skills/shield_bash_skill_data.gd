extends SkillData
class_name ShieldBashSkillData

# Phase 21 skill #2: AoE around a tapped point. Tap a spot within skill
# range of the hero → every non-dying enemy inside `aoe_radius` of that
# point takes `damage` physical damage.
#
# Proves the TargetType.AREA flow: SkillBar passes a Vector2 world-pos
# as `target`, not a Node.

const _SlowEffectScript: Script = preload("res://systems/SlowEffect.gd")

@export var aoe_radius: float = 175.0
# Optional: apply a slow to each enemy hit. Leave at 0 for pure-damage AoE.
@export_range(0.0, 1.0) var on_hit_slow_factor: float = 0.0
@export var on_hit_slow_duration: float = 0.0


func apply(hero: Node, target) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if target == null or not (target is Vector2):
		return
	var center: Vector2 = target
	var r2: float = aoe_radius * aoe_radius
	for enemy in hero.get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy):
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if center.distance_squared_to(enemy.global_position) <= r2:
			enemy.take_damage(damage, damage_type, hero)
			if on_hit_slow_factor > 0.0 and on_hit_slow_duration > 0.0:
				enemy.apply_status_effect(_SlowEffectScript.new(on_hit_slow_factor, on_hit_slow_duration))
