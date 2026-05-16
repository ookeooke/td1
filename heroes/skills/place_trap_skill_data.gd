extends SkillData
class_name PlaceTrapSkillData

# Phase 5 — trap-platform active skill. AREA-targeted exactly like
# SummonSoldiersSkillData: player taps the skill button (arms targeting via
# the existing SkillBar._input path — NO new input handler), then taps a
# ground spot; a Trap is placed there, navmesh-snapped (CORE RULE 13).
#
# Concurrency cap: traps join the per-hero "hero_traps" group; placing past
# TrapData.max_active frees the OLDEST first (defined behavior, tested).
# Lifetime/arming/detonation all live on the Trap entity.

const _TrapScript: Script = preload("res://systems/Trap.gd")

@export var trap_data: Resource  # TrapData


func apply(hero: Node, target, _ctx: Dictionary = {}) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	if trap_data == null:
		push_warning("[PlaceTrap] skill missing trap_data")
		return false
	var parent: Node = hero.get_tree().current_scene
	if parent == null:
		return false
	var pos: Vector2 = hero.global_position
	if target is Vector2:
		pos = target
	# Snap to navmesh (CORE RULE 13) so a trap tapped on water/off-map lands
	# on walkable ground. Graceful when no nav map (tests / bare scene).
	var world_2d: World2D = hero.get_world_2d()
	if world_2d != null:
		var nav_map: RID = world_2d.navigation_map
		if nav_map.is_valid():
			pos = NavigationServer2D.map_get_closest_point(nav_map, pos)
	# Enforce max_active — free oldest-first among this hero's traps.
	_enforce_cap(parent, hero)
	var trap: Node2D = _TrapScript.new()
	trap.add_to_group("hero_traps")
	parent.add_child(trap)
	trap.global_position = pos
	trap.setup(trap_data, hero)
	return true


# Pure helper (tested): among `parent`'s placed traps owned by `hero`, free
# the oldest ones until at most max_active-1 remain (so the new one fits).
func _enforce_cap(parent: Node, hero: Node) -> void:
	var cap: int = maxi(1, int(trap_data.max_active))
	var mine: Array = []
	for t in parent.get_tree().get_nodes_in_group("hero_traps"):
		# Skip traps already _die()'d this frame — queue_free is deferred so
		# they linger in the group until end-of-frame; counting them would
		# let a same-frame double-cast transiently exceed max_active (R4).
		if t != null and is_instance_valid(t) and not t.is_queued_for_deletion() \
				and t.get("_summoner") == hero:
			mine.append(t)
	# Group order is spawn order → oldest first. Free from the front until
	# there's room for one more.
	var to_free: int = mine.size() - (cap - 1)
	var i: int = 0
	while i < to_free and i < mine.size():
		if mine[i].has_method("_die"):
			mine[i]._die()
		i += 1
