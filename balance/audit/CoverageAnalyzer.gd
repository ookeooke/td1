class_name CoverageAnalyzer
extends RefCounted

# Coverage analyzer — Phase 1 of the coverage-weighted balance plan.
#
# Walks a level scene to extract its geometry (paths, tower spots, hero spawn,
# spawn markers, map_bounds) and computes per-spot/per-range coverage along
# every path. Coverage is in PIXELS, not seconds — seconds depend on enemy
# move_speed and belong in WaveDamageSimulator.
#
# Static API. Caches:
#   _level_cache:    scene_path -> structure dict
#   _coverage_cache: "scene|spot|range" -> coverage dict
#   _enemy_data_cache: enemy_scene.resource_path -> EnemyData

const PATH_SAMPLE_STEP_PX: float = 8.0

static var _level_cache: Dictionary = {}
static var _coverage_cache: Dictionary = {}
static var _enemy_data_cache: Dictionary = {}


# ── Level parsing ────────────────────────────────────────────────────────

# Instantiate a level scene without adding to the tree, walk the standard
# child layout (Paths/, TowerSpots/, HeroSpawn, SpawnMarkers/), free the
# instance. Returns a Dictionary; empty on load failure.
static func parse_level(scene_path: String) -> Dictionary:
	if _level_cache.has(scene_path):
		return _level_cache[scene_path]

	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("[CoverageAnalyzer] failed to load level scene: %s" % scene_path)
		return {}

	var instance: Node = packed.instantiate()
	var paths: Dictionary = {}
	var spots: Dictionary = {}
	var hero_spawn: Vector2 = Vector2.ZERO
	var spawn_markers: Array = []
	var map_bounds: Rect2 = Rect2()

	if "map_bounds" in instance:
		var mb: Variant = instance.get("map_bounds")
		if mb is Rect2:
			map_bounds = mb

	var paths_node: Node = instance.get_node_or_null("Paths")
	if paths_node != null:
		for child in paths_node.get_children():
			if child is Path2D and (child as Path2D).curve != null:
				var path := child as Path2D
				var baked: PackedVector2Array = path.curve.get_baked_points()
				var world_points := PackedVector2Array()
				for p in baked:
					world_points.append(path.global_transform * p)
				paths[String(child.name)] = world_points

	var spots_node: Node = instance.get_node_or_null("TowerSpots")
	if spots_node != null:
		for child in spots_node.get_children():
			if child is Marker2D:
				spots[String(child.name)] = (child as Marker2D).global_position

	var hs: Node = instance.get_node_or_null("HeroSpawn")
	if hs != null and hs is Marker2D:
		hero_spawn = (hs as Marker2D).global_position

	var sm_node: Node = instance.get_node_or_null("SpawnMarkers")
	if sm_node != null:
		for child in sm_node.get_children():
			var pid: String = ""
			if "path_id" in child:
				pid = String(child.get("path_id"))
			var pos: Vector2 = Vector2.ZERO
			if child is Node2D:
				pos = (child as Node2D).global_position
			spawn_markers.append({
				"name": String(child.name),
				"pos": pos,
				"path_id": pid,
			})

	# Standalone instance, never entered the tree → _ready did not run.
	# free() is immediate; queue_free would defer until tree poll.
	instance.free()

	var level_id: String = scene_path.get_file().get_basename().to_lower()
	var result: Dictionary = {
		"scene_path": scene_path,
		"level_id": level_id,
		"paths": paths,
		"spots": spots,
		"hero_spawn": hero_spawn,
		"spawn_markers": spawn_markers,
		"map_bounds": map_bounds,
	}
	_level_cache[scene_path] = result
	return result


# ── Coverage math ────────────────────────────────────────────────────────

# Returns:
#   {
#     "covered_length_px": float,
#     "total_length_px":   float,
#     "coverage_pct":      float in [0, 1],
#     "segments":          [ {start_px, end_px} ] continuous covered ranges
#   }
static func spot_path_coverage(spot_pos: Vector2, path_points: PackedVector2Array, tower_range: float) -> Dictionary:
	var total: float = _path_length(path_points)
	if path_points.size() < 2 or tower_range <= 0.0:
		return {
			"covered_length_px": 0.0,
			"total_length_px": total,
			"coverage_pct": 0.0,
			"segments": [],
		}

	var range_sq: float = tower_range * tower_range
	var covered: float = 0.0
	var segments: Array = []
	var cumulative: float = 0.0

	for i in range(path_points.size() - 1):
		var a: Vector2 = path_points[i]
		var b: Vector2 = path_points[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0001:
			continue
		var a_in: bool = a.distance_squared_to(spot_pos) <= range_sq
		var b_in: bool = b.distance_squared_to(spot_pos) <= range_sq
		var added_start_t: float = -1.0
		var added_end_t: float = -1.0

		if a_in and b_in:
			covered += seg_len
			added_start_t = 0.0
			added_end_t = 1.0
		elif a_in or b_in:
			var clip_t: float = _line_circle_clip(a, b, spot_pos, tower_range)
			if a_in:
				covered += seg_len * clip_t
				added_start_t = 0.0
				added_end_t = clip_t
			else:
				covered += seg_len * (1.0 - clip_t)
				added_start_t = clip_t
				added_end_t = 1.0
		else:
			var pierce: Vector2 = _segment_circle_pierce(a, b, spot_pos, tower_range)
			if pierce.x >= 0.0:
				covered += seg_len * (pierce.y - pierce.x)
				added_start_t = pierce.x
				added_end_t = pierce.y

		if added_start_t >= 0.0:
			var add_start_px: float = cumulative + seg_len * added_start_t
			var add_end_px: float = cumulative + seg_len * added_end_t
			# Stitch onto previous open segment if continuous.
			if not segments.is_empty() and abs(add_start_px - segments[-1]["end_px"]) < 0.5:
				segments[-1]["end_px"] = add_end_px
			else:
				segments.append({"start_px": add_start_px, "end_px": add_end_px})

		cumulative += seg_len

	var coverage_pct: float = (covered / total) if total > 0.0 else 0.0
	return {
		"covered_length_px": covered,
		"total_length_px": total,
		"coverage_pct": coverage_pct,
		"segments": segments,
	}


# Build a coverage matrix for a level × array of {tower_id, tier_key, range}.
# Returned shape:
#   {
#     "level_id":   String,
#     "scene_path": String,
#     "spots": {
#       <spot_id>: {
#         "position": Vector2,
#         "<tower_id>:<tier_key>": {
#            <path_id>: { coverage dict from spot_path_coverage }
#         }
#       }
#     }
#   }
static func build_coverage_matrix(scene_path: String, towers: Array) -> Dictionary:
	var level: Dictionary = parse_level(scene_path)
	if level.is_empty():
		return {}

	var spots: Dictionary = level["spots"]
	var paths: Dictionary = level["paths"]

	var result: Dictionary = {
		"level_id": level["level_id"],
		"scene_path": scene_path,
		"spots": {},
	}

	for spot_id in spots:
		var spot_pos: Vector2 = spots[spot_id]
		var spot_entry: Dictionary = {"position": spot_pos}

		for tower in towers:
			var tower_id: String = String(tower.get("tower_id", ""))
			var tier_key: String = String(tower.get("tier_key", ""))
			var rng: float = float(tower.get("range", 0.0))
			if tower_id == "" or tier_key == "" or rng <= 0.0:
				continue
			var key: String = "%s:%s" % [tower_id, tier_key]
			var per_path: Dictionary = {}
			for path_id in paths:
				per_path[path_id] = _cached_coverage(
					scene_path, String(spot_id), String(path_id), spot_pos, paths[path_id], rng)
			spot_entry[key] = per_path
		result["spots"][spot_id] = spot_entry

	return result


# ── Enemy data lookup ─────────────────────────────────────────────────────

# WaveSpawn references enemy_scene: PackedScene, not EnemyData. Instance
# briefly (no tree → no _ready) and read the `data` export off BaseEnemy.
# Cached by scene resource_path.
static func enemy_data_for(enemy_scene: PackedScene) -> Resource:
	if enemy_scene == null:
		return null
	var key: String = enemy_scene.resource_path
	if _enemy_data_cache.has(key):
		return _enemy_data_cache[key]
	var inst: Node = enemy_scene.instantiate()
	var data: Resource = null
	if "data" in inst:
		data = inst.get("data") as Resource
	inst.free()
	if data != null:
		_enemy_data_cache[key] = data
	return data


# ── Cache / utilities ─────────────────────────────────────────────────────

static func clear_cache() -> void:
	_level_cache.clear()
	_coverage_cache.clear()
	_enemy_data_cache.clear()


static func _cached_coverage(scene_path: String, spot_id: String, path_id: String, spot_pos: Vector2, path_points: PackedVector2Array, tower_range: float) -> Dictionary:
	var key: String = "%s|%s|%s|%.2f" % [scene_path, spot_id, path_id, tower_range]
	if _coverage_cache.has(key):
		return _coverage_cache[key]
	var cov: Dictionary = spot_path_coverage(spot_pos, path_points, tower_range)
	_coverage_cache[key] = cov
	return cov


static func _path_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


# Returns t in [0,1] along segment a→b where the line crosses the circle of
# radius r around c. Assumes exactly one of (a, b) lies inside the circle.
static func _line_circle_clip(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d: Vector2 = b - a
	var f: Vector2 = a - c
	var aa: float = d.dot(d)
	var bb: float = 2.0 * f.dot(d)
	var cc: float = f.dot(f) - r * r
	var disc: float = bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return 0.5
	var sqrt_disc: float = sqrt(disc)
	var t1: float = (-bb - sqrt_disc) / (2.0 * aa)
	var t2: float = (-bb + sqrt_disc) / (2.0 * aa)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if t2 >= 0.0 and t2 <= 1.0:
		return t2
	return 0.5


# Returns Vector2(t_enter, t_exit) for a segment that pierces the circle from
# outside. Returns Vector2(-1,-1) if no intersection.
static func _segment_circle_pierce(a: Vector2, b: Vector2, c: Vector2, r: float) -> Vector2:
	var d: Vector2 = b - a
	var f: Vector2 = a - c
	var aa: float = d.dot(d)
	if aa <= 0.0:
		return Vector2(-1.0, -1.0)
	var bb: float = 2.0 * f.dot(d)
	var cc: float = f.dot(f) - r * r
	var disc: float = bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return Vector2(-1.0, -1.0)
	var sqrt_disc: float = sqrt(disc)
	var t1: float = (-bb - sqrt_disc) / (2.0 * aa)
	var t2: float = (-bb + sqrt_disc) / (2.0 * aa)
	if t1 > 1.0 or t2 < 0.0:
		return Vector2(-1.0, -1.0)
	var t_enter: float = clamp(t1, 0.0, 1.0)
	var t_exit: float = clamp(t2, 0.0, 1.0)
	if t_enter >= t_exit:
		return Vector2(-1.0, -1.0)
	return Vector2(t_enter, t_exit)
