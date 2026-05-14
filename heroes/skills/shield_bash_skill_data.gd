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
# Damage multiplier applied to flying enemies hit by this skill. 1.0 = no
# special treatment (default). Authored at >1 on anti-air skills like
# Volley (skill_volley.tres → 1.3) so the description's "strong vs flying"
# is actually delivered. Stacks multiplicatively with damage_mult / ranks.
@export var flying_bonus_mult: float = 1.0
# Optional: scene to spawn at the impact point (e.g. FireballVFX). The scene
# is instantiated as a child of the current level, positioned at `target`,
# and `setup(aoe_radius)` is called if the scene defines that method.
@export var vfx_scene: PackedScene


func apply(hero: Node, target, ctx: Dictionary = {}) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	if target == null or not (target is Vector2):
		return false
	var center: Vector2 = target
	# Phase 2B/2C — rank + mod ctx multipliers. damage_mult / aoe_radius_mult
	# arrive pre-merged from BaseHero._build_skill_ctx; subclass just folds
	# them into the locals it actually uses.
	# 2026-05-14 — skill_power_mult also stretches the slow duration so SP
	# gear makes Frost Nova / Snare Trap roots last longer. Damage already
	# scales via damage_mult (skill_power baked in upstream).
	var sp_mult: float = float(ctx.get("skill_power_mult", 1.0))
	var radius: float = aoe_radius * float(ctx.get("aoe_radius_mult", 1.0))
	var r2: float = radius * radius
	var dmg: float = damage * float(ctx.get("damage_mult", 1.0))
	var eff_slow_duration: float = on_hit_slow_duration * sp_mult
	for enemy in hero.get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy):
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if center.distance_squared_to(enemy.global_position) <= r2:
			# Anti-air bonus — only applied to flying enemies, only when the
			# skill authored flying_bonus_mult > 1. Keeps the default path
			# (Shield Bash / Fireball / etc.) unchanged.
			var hit_dmg: float = dmg
			if flying_bonus_mult > 1.0 and enemy.data != null and enemy.data.is_flying:
				hit_dmg *= flying_bonus_mult
			enemy.take_damage(hit_dmg, damage_type, hero)
			if on_hit_slow_factor > 0.0 and eff_slow_duration > 0.0:
				enemy.apply_status_effect(_SlowEffectScript.new(on_hit_slow_factor, eff_slow_duration))
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
	return true
