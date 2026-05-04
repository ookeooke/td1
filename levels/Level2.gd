@tool
extends Node2D

# Level2: second campaign map — more curves than Level1.
# Near-byte-for-byte copy of Level1.gd; only level-id-bearing strings
# differ. When L3 lands and the duplication is undeniable, extract a
# BaseLevel.gd parent and have L1/L2/L3 subclass it.
#
# Shared systems (GridManager, SpotInputManager, SpawnMarker) live under
# res://map/ and are instanced here.

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
	print("[Level2/Budget] natural=%dg  max_with_early_calls=%dg  swing=+%dg" % [
		int(b.gold_natural), int(b.gold_max_with_early_calls), int(b.early_call_swing)
	])
	var ratio_line: String = ""
	var total_req_dmg: float = 0.0
	for i in range(wl.waves.size()):
		var w: WaveData = wl.waves[i]
		var req_dmg: float = bc.wave_required_damage(w)
		var req_dps: float = bc.wave_required_dps(w)
		var gpd: float = bc.wave_gold_per_damage(w)
		ratio_line += "  W%d=%d req_dps=%.1f g/dmg=%.2f" % [i + 1, int(req_dmg), req_dps, gpd]
		total_req_dmg += req_dmg
	var level_gpd: float = 0.0
	if total_req_dmg > 0.0:
		level_gpd = float(b.gold_natural) / total_req_dmg
	print("[Level2/Ratios] req_dmg=%d  natural_g/dmg=%.2f%s" % [
		int(total_req_dmg), level_gpd, ratio_line
	])
	var towers: Array = ContentRegistry.towers if ContentRegistry != null else []
	var window_sec: float = 60.0
	print("[Level2/Towers] dmg per gold over %.0fs window:" % window_sec)
	var best_l1: float = 0.0
	for t in towers:
		if not (t is TowerData) or t.damage <= 0.0:
			continue
		var l1: float = bc.tower_damage_per_gold(t, 0, window_sec)
		var l2: float = bc.tower_damage_per_gold(t, 1, window_sec)
		var l3: float = bc.tower_damage_per_gold(t, 2, window_sec)
		print("  %s  L1=%.2f  L2=%.2f  L3=%.2f" % [String(t.tower_name), l1, l2, l3])
		if l1 > best_l1:
			best_l1 = l1
	if best_l1 > 0.0:
		var req_line: String = "  best_L1=%.2f dmg/g  →" % best_l1
		for i in range(wl.waves.size()):
			var w: WaveData = wl.waves[i]
			var rg: int = bc.wave_required_gold(w, best_l1)
			req_line += "  W%d_need=%dg/got=%dg" % [i + 1, rg, int(b.per_wave_gold[i])]
		print("[Level2/GoldVsNeed]%s" % req_line)
	var dead_line: String = ""
	for i in range(wl.waves.size()):
		var w: WaveData = wl.waves[i]
		var t: Dictionary = bc.wave_spawn_timeline(w)
		var flag: String = " ⚠" if float(t.max_gap) > 5.0 else ""
		dead_line += "  W%d max=%.1fs dead=%.1fs%s" % [
			i + 1, float(t.max_gap), float(t.dead_air), flag
		]
	print("[Level2/DeadAir]%s" % dead_line)
	var ld: LevelNodeData = _find_level_data("level_2")
	if ld == null:
		return
	var rep: Dictionary = bc.level_pressure_report(wl, ld, RunState.STARTING_GOLD)
	var pressure_line: String = ""
	for entry in rep.per_wave:
		pressure_line += "  W%d g=%d/%d p=%.2f/%.2f" % [
			int(entry.wave),
			int(entry.actual_gold), int(entry.target_gold),
			float(entry.actual_pressure), float(entry.target_pressure),
		]
	print("[Level2/Pressure] total=%d/%dg (%+.0f%%)%s" % [
		int(rep.total_actual_gold), int(rep.total_target_gold),
		float(rep.total_drift_pct), pressure_line
	])
	for w in rep.warnings:
		print("[Level2/DRIFT] WARN %s" % String(w))


func _find_level_data(level_id: String) -> LevelNodeData:
	var registry: Resource = load("res://ui/world_map/level_list.tres")
	if registry == null:
		return null
	var levels: Array = registry.levels
	for entry in levels:
		if entry is LevelNodeData and entry.level_id == level_id:
			return entry
	return null


func _configure_camera() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null and "map_bounds" in cam:
		cam.map_bounds = map_bounds
		if cam.has_method("configure_bounds"):
			cam.configure_bounds(map_bounds)


func _on_editor_tree_changed() -> void:
	_cache_paths()
	queue_redraw()


var _spot_pulse_accum: float = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_spot_pulse_accum += delta
	if _spot_pulse_accum >= 0.05:
		_spot_pulse_accum = 0.0
		queue_redraw()


func _cache_paths() -> void:
	_paths_by_id.clear()
	if paths_node == null:
		return
	for child in paths_node.get_children():
		if child is Path2D:
			_paths_by_id[String(child.name)] = child


func get_path_by_id(path_id: String) -> Path2D:
	return _paths_by_id.get(path_id)


func get_hero_spawn_position() -> Vector2:
	var m: Marker2D = get_node_or_null("HeroSpawn")
	if m != null:
		return m.position
	return Vector2(960, 540)


func _register_tower_spots() -> void:
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


func _generate_decorations() -> void:
	var path_pts: PackedVector2Array = PackedVector2Array()
	if paths_node != null:
		for child in paths_node.get_children():
			if child is Path2D and child.curve != null:
				path_pts.append_array(child.curve.get_baked_points())
	var spot_positions: Array = []
	if tower_spots_node != null:
		for child in tower_spots_node.get_children():
			if child is Marker2D:
				spot_positions.append(child.position)
	var hero_spawn: Vector2 = get_hero_spawn_position()
	_decorations = _EnvironmentScatterScript.generate(
		0xCAFEFACE, map_bounds, path_pts, spot_positions, hero_spawn, 80, 600
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), BG_COLOR)
	_draw_borders()
	for d in _decorations:
		_EnvironmentScatterScript.draw(self, d)
	var source := paths_node if paths_node != null else get_node_or_null("Paths")
	if source != null:
		for child in source.get_children():
			if child is Path2D and child.curve != null:
				var pts: PackedVector2Array = child.curve.get_baked_points()
				if pts.size() >= 2:
					draw_polyline(pts, PATH_COLOR, PATH_WIDTH)
	var spots := tower_spots_node if tower_spots_node != null else get_node_or_null("TowerSpots")
	if spots != null:
		var pulse_t: float = sin(Time.get_ticks_msec() / 480.0) * 0.5 + 0.5
		for child in spots.get_children():
			if not (child is Marker2D):
				continue
			_draw_tower_spot(child.position, child.name, pulse_t)


func _draw_tower_spot(pos: Vector2, spot_id: String, pulse_t: float) -> void:
	draw_circle(pos, SPOT_RADIUS, SPOT_FILL)
	for i in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.20
		var p: Vector2 = pos + Vector2(cos(ang), sin(ang)) * (SPOT_RADIUS - 7.0)
		draw_circle(p, 7.0, SPOT_COBBLE_COLOR)
		draw_circle(p + Vector2(-1.5, -1.5), 2.5, SPOT_COBBLE_HIGHLIGHT)
	draw_arc(pos, SPOT_RADIUS, 0.0, TAU, 32, SPOT_OUTLINE, 3.0)

	# In editor: skip the GridManager call — GridManager isn't @tool, so it
	# loads as a placeholder Node and method calls fail with thousands of
	# "Attempt to call a method on a placeholder instance" errors per second.
	# Every spot is empty in editor anyway (no game running), so always draw.
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
	var mb: Rect2 = map_bounds
	var bw: float = BORDER_WIDTH

	var mountain_base_y: float = mb.position.y
	var peak_count: int = int(mb.size.x / 30.0) + 2
	for i in peak_count:
		var x: float = mb.position.x - 20.0 + i * 32.0
		var peak_h: float = bw * 0.5 + fmod(float(i) * 17.3, bw * 0.6)
		var tri: PackedVector2Array = PackedVector2Array([
			Vector2(x - 18.0, mountain_base_y),
			Vector2(x, mountain_base_y - peak_h),
			Vector2(x + 18.0, mountain_base_y),
		])
		draw_colored_polygon(tri, MOUNTAIN_COLOR)
		if peak_h > bw * 0.7:
			var cap: PackedVector2Array = PackedVector2Array([
				Vector2(x - 6.0, mountain_base_y - peak_h + 10.0),
				Vector2(x, mountain_base_y - peak_h),
				Vector2(x + 6.0, mountain_base_y - peak_h + 10.0),
			])
			draw_colored_polygon(cap, MOUNTAIN_PEAK_COLOR)
	draw_rect(Rect2(mb.position.x - 100.0, mb.position.y - bw - 200.0, mb.size.x + 200.0, bw + 200.0), MOUNTAIN_COLOR)

	var water_top_y: float = mb.end.y
	draw_rect(Rect2(mb.position.x - 100.0, water_top_y, mb.size.x + 200.0, bw + 200.0), WATER_COLOR)
	var wave_pts: PackedVector2Array = PackedVector2Array()
	var wave_count: int = int(mb.size.x / 10.0) + 3
	for i in wave_count:
		var x: float = mb.position.x - 10.0 + i * 10.0
		var y_off: float = sin(float(i) * 0.8) * 4.0
		wave_pts.append(Vector2(x, water_top_y + y_off))
	if wave_pts.size() >= 2:
		draw_polyline(wave_pts, WATER_LIGHT, 3.0)

	var cliff_x: float = mb.position.x
	draw_rect(Rect2(cliff_x - bw - 100.0, mb.position.y - bw, bw + 100.0, mb.size.y + bw * 2.0), CLIFF_COLOR)
	draw_line(Vector2(cliff_x, mb.position.y - bw), Vector2(cliff_x, mb.end.y + bw), CLIFF_DARK, 3.0)

	var cliff_r: float = mb.end.x
	draw_rect(Rect2(cliff_r, mb.position.y - bw, bw + 100.0, mb.size.y + bw * 2.0), CLIFF_COLOR)
	draw_line(Vector2(cliff_r, mb.position.y - bw), Vector2(cliff_r, mb.end.y + bw), CLIFF_DARK, 3.0)
