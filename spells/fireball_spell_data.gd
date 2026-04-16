extends SpellData
class_name FireballSpellData

# Phase 22 spell #1: AoE magic burst at a tapped location. All non-dying
# enemies within `radius` take `damage` magic damage. Flies nothing and
# hits nothing mid-air — it's an instant ground-strike, matching KR's
# "Rain of Fire" feel. A proper arcing projectile can land at Phase 41.
#
# Spawns a small placeholder VFX at the impact point if vfx_scene is set.
# Source for take_damage is the caster node (SpellPanel) so enemy XP does
# NOT go to the hero — spell kills credit nobody, which is the intended
# Kingdom Rush rule (spells don't level up your hero).

func apply(world_pos: Vector2, caster: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	# Damage enemies in the radius.
	var r2: float = radius * radius
	for node in caster.get_tree().get_nodes_in_group("enemies"):
		if not (node is BaseEnemy):
			continue
		var enemy: BaseEnemy = node
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if world_pos.distance_squared_to(enemy.global_position) <= r2:
			enemy.take_damage(damage, damage_type, caster)
	# VFX — optional; if no scene assigned, spell fires silently for now.
	if vfx_scene != null:
		var vfx: Node = vfx_scene.instantiate()
		caster.get_tree().current_scene.add_child(vfx)
		if vfx is Node2D:
			(vfx as Node2D).global_position = world_pos
		if vfx.has_method("setup"):
			vfx.setup(radius)
