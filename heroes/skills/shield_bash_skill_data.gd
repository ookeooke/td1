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
# Optional: scene to spawn at the impact point (e.g. FireballVFX). The scene
# is instantiated as a child of the current level, positioned at `target`,
# and `setup(aoe_radius)` is called if the scene defines that method.
@export var vfx_scene: PackedScene


func apply(hero: Node, target, ctx: Dictionary = {}) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if target == null or not (target is Vector2):
		return
	var center: Vector2 = target
	# Phase 2B/2C — rank + mod ctx multipliers. damage_mult / aoe_radius_mult
	# arrive pre-merged from BaseHero._build_skill_ctx; subclass just folds
	# them into the locals it actually uses.
	var radius: float = aoe_radius * float(ctx.get("aoe_radius_mult", 1.0))
	var r2: float = radius * radius
	var dmg: float = damage * float(ctx.get("damage_mult", 1.0))
	for enemy in hero.get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy):
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if center.distance_squared_to(enemy.global_position) <= r2:
			enemy.take_damage(dmg, damage_type, hero)
			if on_hit_slow_factor > 0.0 and on_hit_slow_duration > 0.0:
				enemy.apply_status_effect(_SlowEffectScript.new(on_hit_slow_factor, on_hit_slow_duration))
	# VFX — optional. Spawned after the damage pass so the visual impact
	# always plays even if no enemy was hit (a designed miss is the player's
	# problem; the cast still "fired").
	if vfx_scene != null:
		var vfx: Node = vfx_scene.instantiate()
		hero.get_tree().current_scene.add_child(vfx)
		if vfx is Node2D:
			(vfx as Node2D).global_position = center
		if vfx.has_method("setup"):
			vfx.setup(radius)
