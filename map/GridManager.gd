extends Node

# Tracks tower-spot occupancy.
# Phase 2 scope: registration + queries. Build/sell hooks wired in Phase 8/9.

var _spots: Dictionary = {}  # spot_id -> { position: Vector2, tower: Node }


func register_spot(spot_id: String, pos: Vector2) -> void:
	_spots[spot_id] = { "position": pos, "tower": null }


func is_occupied(spot_id: String) -> bool:
	return _spots.has(spot_id) and _spots[spot_id].tower != null


func get_spot_position(spot_id: String) -> Vector2:
	if not _spots.has(spot_id):
		return Vector2.ZERO
	return _spots[spot_id].position


func get_free_spot_ids() -> Array:
	var out: Array = []
	for id in _spots:
		if _spots[id].tower == null:
			out.append(id)
	return out


func get_spot_count() -> int:
	return _spots.size()


func set_tower_at(spot_id: String, tower: Node) -> void:
	if not _spots.has(spot_id):
		push_warning("[GridManager] set_tower_at: unknown spot '%s'" % spot_id)
		return
	_spots[spot_id].tower = tower


func clear_tower_at(spot_id: String) -> void:
	if not _spots.has(spot_id):
		return
	_spots[spot_id].tower = null


func get_tower_at(spot_id: String) -> Node:
	if not _spots.has(spot_id):
		return null
	return _spots[spot_id].tower


func find_nearest_spot(world_pos: Vector2, max_distance: float) -> String:
	var best_id := ""
	var best_d := max_distance
	for id in _spots:
		var d := world_pos.distance_to(_spots[id].position)
		if d <= best_d:
			best_d = d
			best_id = id
	return best_id
