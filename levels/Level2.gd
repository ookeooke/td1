@tool
extends Node2D

# Level2: second campaign map — same engine bones as Level1, more curves
# in the path geometry so it visually escalates over L1. Wave content,
# tower spots, hero spawn all level-specific. Uses the same procedural
# decoration pipeline (rocks/grass/trees) until art direction differentiates.
#
# This is a near-clone of Level1.gd. When a third level lands and the
# duplication is undeniable, extract a BaseLevel.gd parent and have L1/L2/L3
# subclass it. Today the simpler-but-duplicated copy reads cleaner.

const MAP_SIZE := Vector2(1920, 1080)
const BG_COLOR := Color(0.32, 0.52, 0.28, 1.0)
const PATH_COLOR := Color(0.55, 0.40, 0.25)
const PATH_WIDTH := 170.0
const SPOT_FILL := Color(0.78, 0.72, 0.55, 0.95)
const SPOT_OUTLINE := Color(0.20, 0.15, 0.08)
const SPOT_RADIUS := 65.0
const SPOT_COBBLE_COLOR := Color(0.50, 0.42, 0.32)
const SPOT_COBBLE_HIGHLIGHT := Color(0.65, 0.58, 0.45)
const SPOT_PLANK_COLOR := Color(0.55, 0.38, 0.20)
const SPOT_PLANK_OUTLINE := Color(0.22, 0.14, 0.06)

const BORDER_WIDTH := 200.0
const MOUNTAIN_COLOR := Color(0.35, 0.28, 0.20)
const MOUNTAIN_PEAK_COLOR := Color(0.55, 0.48, 0.40)
const CLIFF_COLOR := Color(0.40, 0.32, 0.22)
const CLIFF_DARK := Color(0.30, 0.22, 0.14)
const WATER_COLOR := Color(0.20, 0.35, 0.55)
const WATER_LIGHT := Color(0.30, 0.50, 0.70)

@export var map_bounds: Rect2 = Rect2(-40, -40, 2000, 1160)

@onready var paths_node: Node2D = $Paths
@onready var tower_spots_node: Node2D = $TowerSpots
@onready var spawn_markers_node: Node2D = $SpawnMarkers
@onready var grid_manager: Node = $GridManager

var _paths_by_id: Dictionary = {}
var _decorations: Array = []
const _EnvironmentScatterScript := preload("res://systems/EnvironmentScatter.gd")


func _ready() -> void:
	_cache_paths()
	queue_redraw()
	if Engine.is_editor_hint():
		if not child_order_changed.is_connected(_on_editor_tree_changed):
			child_order_changed.connect(_on_editor_tree_changed)
		_print_hardness_readout()
		return
	_register_tower_spots()
	_configure_camera()
	_generate_decorations()
	print("[Level2] ready — %d paths, %d spots, %d spawn markers" % [
		_paths_by_id.size(),
		grid_manager.get_spot_count(),
		spawn_markers_node.get_child_count()
	])
	_print_hardness_readout()


func _print_hardness_readout() -> void:
	if not OS.is_debug_build():
		return
	var wl: WaveList = load("res://levels/level2_waves.tres")
	if wl == null:
		return
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return
	var b: Dictionary = bc.score_level_breakdown(wl, RunState.STARTING_GOLD)
	var per: String = ""
	var pw: Array = b.per_wave
	var pg: Array = b.per_wave_gold
	var pd: Array = b.per_wave_density
	for i in range(pw.size()):
		per += "  W%d=%d (%dg, %.1fe/s)" % [i + 1, int(pw[i]), int(pg[i]), float(pd[i])]
	print("[Level2/Balance] %s net=%d (waves=%d, start=%dg)%s" % [
		String(b.tier), int(b.net_score), int(b.wave_total), int(b.starting_gold), per
	])
	var ld: LevelNodeData = _find_level_data("level_2")
	if ld == null:
		return
	var rep: Dictionary = bc.level_pressure_report(wl, ld, RunState.STARTING_GOLD)
	var line: String = ""
	for entry in rep.per_wave:
		line += "  W%d g=%d/%d p=%.2f/%.2f" % [
			entry.wave, int(entry.actual_gold), int(entry.target_gold),
			entry.actual_pressure, entry.target_pressure,
		]
	print("[Level2/Pressure] total=%d/%dg (%+.0f%%)%s" % [
		int(rep.total_actual_gold), int(rep.total_target_gold),
		rep.total_drift_pct, line,
	])
	for w in rep.warnings:
		print("[Level2/DRIFT] WARN %s" % String(w))


func _find_level_data(level_id: String) -> LevelNodeData:
	return ContentRegistry.find_level(level_id)


func _configure_camera() -> void:
	var cam: Camera2D = get_tree().root.find_child("GameCamera", true, false) as Camera2D
	if cam == null:
		return
	if cam.has_method("set_map_bounds"):
		cam.set_map_bounds(map_bounds)
	elif "map_bounds" in cam:
		cam.map_bounds = map_bounds


func _on_editor_tree_changed() -> void:
	_cache_paths()
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _cache_paths() -> void:
	_paths_by_id.clear()
	if paths_node == null:
		paths_node = $Paths if has_node("Paths") else null
	if paths_node == null:
		return
	for child in paths_node.get_children():
		if child is Path2D:
			_paths_by_id[child.name] = child


func get_path_by_id(path_id: String) -> Path2D:
	if _paths_by_id.is_empty():
		_cache_paths()
	return _paths_by_id.get(path_id, null)


func get_hero_spawn_position() -> Vector2:
	var marker: Node = get_node_or_null("HeroSpawn")
	if marker is Marker2D:
		return marker.global_position
	return Vector2(960, 540)


func _register_tower_spots() -> void:
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


func _generate_decorations() -> void:
	var scatter = _EnvironmentScatterScript.new()
	_decorations = scatter.generate(map_bounds, _paths_by_id, tower_spots_node, 1234)


func _draw() -> void:
	_draw_borders()
	_draw_paths()
	_draw_decorations()
	_draw_tower_spots()


func _draw_paths() -> void:
	if _paths_by_id.is_empty():
		_cache_paths()
	for path in _paths_by_id.values():
		if path == null or path.curve == null:
			continue
		var pts: PackedVector2Array = path.curve.get_baked_points()
		if pts.size() < 2:
			continue
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in pts:
			transformed.append(path.position + p)
		# Outline (slightly darker, slightly wider) under the road for contrast.
		draw_polyline(transformed, Color(0.35, 0.25, 0.15), PATH_WIDTH + 8.0)
		draw_polyline(transformed, PATH_COLOR, PATH_WIDTH)


func _draw_decorations() -> void:
	if _decorations.is_empty():
		return
	for d in _decorations:
		if d == null:
			continue
		if d.has("kind") and d.kind == "tree":
			draw_circle(d.pos + Vector2(0, 6), d.radius * 0.55, Color(0.18, 0.32, 0.16))
			draw_circle(d.pos, d.radius, Color(0.30, 0.55, 0.28))
			draw_circle(d.pos - Vector2(d.radius * 0.4, d.radius * 0.4), d.radius * 0.35, Color(0.45, 0.70, 0.40))
		elif d.has("kind") and d.kind == "rock":
			draw_circle(d.pos, d.radius, Color(0.45, 0.42, 0.38))
			draw_circle(d.pos - Vector2(d.radius * 0.3, d.radius * 0.3), d.radius * 0.4, Color(0.62, 0.58, 0.52))
		elif d.has("kind") and d.kind == "grass":
			draw_line(d.pos, d.pos + Vector2(0, -d.radius * 0.7), Color(0.30, 0.50, 0.25), 2.0)
			draw_line(d.pos + Vector2(2, 0), d.pos + Vector2(2, -d.radius * 0.5), Color(0.30, 0.50, 0.25), 2.0)
			draw_line(d.pos + Vector2(-2, 0), d.pos + Vector2(-2, -d.radius * 0.5), Color(0.30, 0.50, 0.25), 2.0)


func _draw_tower_spots() -> void:
	var pulse_t: float = (Time.get_ticks_msec() % 1500) / 1500.0
	if tower_spots_node == null:
		return
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			_draw_tower_spot(child.position, child.name, pulse_t)


func _draw_tower_spot(pos: Vector2, spot_id: String, pulse_t: float) -> void:
	# Foundation circle.
	draw_circle(pos, SPOT_RADIUS, SPOT_FILL)
	# Cobbles.
	for i in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.20
		var p: Vector2 = pos + Vector2(cos(ang), sin(ang)) * (SPOT_RADIUS - 7.0)
		draw_circle(p, 7.0, SPOT_COBBLE_COLOR)
		draw_circle(p + Vector2(-1.5, -1.5), 2.5, SPOT_COBBLE_HIGHLIGHT)
	draw_arc(pos, SPOT_RADIUS, 0.0, TAU, 32, SPOT_OUTLINE, 3.0)

	# Build-ready marker — only on empty spots. Editor mode treats every spot
	# as empty (no game running) to dodge GridManager placeholder errors.
	var occupied: bool = false
	if not Engine.is_editor_hint() and grid_manager != null:
		occupied = grid_manager.is_occupied(spot_id)
	if occupied:
		return
	var pulse_scale: float = 0.92 + pulse_t * 0.10
	var arm: float = 18.0 * pulse_scale
	draw_line(pos + Vector2(-arm, -arm), pos + Vector2(arm, arm), SPOT_PLANK_OUTLINE, 9.0, true)
	draw_line(pos + Vector2(-arm, -arm), pos + Vector2(arm, arm), SPOT_PLANK_COLOR, 6.0, true)
	draw_line(pos + Vector2(arm, -arm), pos + Vector2(-arm, arm), SPOT_PLANK_OUTLINE, 9.0, true)
	draw_line(pos + Vector2(arm, -arm), pos + Vector2(-arm, arm), SPOT_PLANK_COLOR, 6.0, true)
	draw_circle(pos, 4.0 * pulse_scale, SPOT_COBBLE_COLOR)
	draw_circle(pos, 2.0 * pulse_scale, Color(0.85, 0.78, 0.55))


func _draw_borders() -> void:
	var top := map_bounds.position.y
	var left := map_bounds.position.x
	var right := map_bounds.position.x + map_bounds.size.x
	var bottom := map_bounds.position.y + map_bounds.size.y
	draw_rect(Rect2(left - BORDER_WIDTH * 8, top - BORDER_WIDTH * 8,
		map_bounds.size.x + BORDER_WIDTH * 16, BORDER_WIDTH * 8 + 4), MOUNTAIN_COLOR)
	draw_rect(Rect2(left - BORDER_WIDTH * 8, bottom - 4,
		map_bounds.size.x + BORDER_WIDTH * 16, BORDER_WIDTH * 8), WATER_COLOR)
	draw_rect(Rect2(left - BORDER_WIDTH * 8, top - 4,
		BORDER_WIDTH * 8, map_bounds.size.y + 8), CLIFF_COLOR)
	draw_rect(Rect2(right - 4, top - 4,
		BORDER_WIDTH * 8, map_bounds.size.y + 8), CLIFF_COLOR)
