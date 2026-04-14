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
