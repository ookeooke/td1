@tool
extends Node2D

# Level1: first campaign map.
# @tool so editor shows the same green background, brown roads, and
# yellow spot circles you'll see at runtime — drag Path2D points and
# Marker2D spots in the 2D view and the map updates live.
#
# Shared systems (GridManager, SpotInputManager, SpawnMarker) live under
# res://map/ and are instanced here. Future levels copy this scene.

const MAP_SIZE := Vector2(1920, 1080)
const BG_COLOR := Color(0.32, 0.52, 0.28, 1.0)
const PATH_COLOR := Color(0.55, 0.40, 0.25)
# Road visual must cover the 3-lane swarm band — non-boss enemies get a
# PathFollow2D v_offset picked from {-LANE_SPACING, 0, +LANE_SPACING} (50px),
# and their body draws at roughly ±35px around their center. So the road
# needs to be at least 2 * (50 + 35) = 170px wide to visually contain every
# enemy on the outer lanes. Keep in sync with WaveManager.LANE_SPACING.
const PATH_WIDTH := 170.0
const SPOT_FILL := Color(0.85, 0.75, 0.35, 0.85)
const SPOT_OUTLINE := Color(0.25, 0.18, 0.08)
const SPOT_RADIUS := 65.0

# Map border visuals — drawn beyond map_bounds edges.
const BORDER_WIDTH := 200.0
const MOUNTAIN_COLOR := Color(0.35, 0.28, 0.20)
const MOUNTAIN_PEAK_COLOR := Color(0.55, 0.48, 0.40)
const CLIFF_COLOR := Color(0.40, 0.32, 0.22)
const CLIFF_DARK := Color(0.30, 0.22, 0.14)
const WATER_COLOR := Color(0.20, 0.35, 0.55)
const WATER_LIGHT := Color(0.30, 0.50, 0.70)

# Camera reads this to set pan/zoom bounds.
# Slightly larger than the actual content (375x812) so edge content
# (soldiers, spell effects, enemy spawn points) isn't clipped.
@export var map_bounds: Rect2 = Rect2(-40, -40, 2000, 1160)

@onready var paths_node: Node2D = $Paths
@onready var tower_spots_node: Node2D = $TowerSpots
@onready var spawn_markers_node: Node2D = $SpawnMarkers
@onready var grid_manager: Node = $GridManager

var _paths_by_id: Dictionary = {}


func _ready() -> void:
	_cache_paths()
	queue_redraw()
	if Engine.is_editor_hint():
		# Redraw when the scene tree shifts in the editor (spot/path drag).
		if not child_order_changed.is_connected(_on_editor_tree_changed):
			child_order_changed.connect(_on_editor_tree_changed)
		_print_hardness_readout()
		return
	_register_tower_spots()
	_configure_camera()
	print("[Level1] ready — %d paths, %d spots, %d spawn markers" % [
		_paths_by_id.size(),
		grid_manager.get_spot_count(),
		spawn_markers_node.get_child_count()
	])
	_print_hardness_readout()


# Editor + runtime readout. Prints the level's BalanceCalculator hardness
# score so authors can compare against the target curve in the balance plan.
# Uses load() per CORE-RULE-16 to avoid the class_name preload race.
func _print_hardness_readout() -> void:
	# Debug-only — BalanceCalculator lives under `balance/` which is excluded
	# from production exports. Skip in release builds so a stripped folder
	# doesn't trigger a load() warning at boot.
	if not OS.is_debug_build():
		return
	var wl: WaveList = load("res://levels/level1_waves.tres")
	if wl == null:
		return
	# load() the script rather than referencing class_name so this works even
	# before Godot's class index has rescanned the new BalanceCalculator file.
	# Static-method calls on a loaded GDScript are supported in Godot 4.
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return
	var b: Dictionary = bc.score_level_breakdown(wl, GameState.STARTING_GOLD)
	var per: String = ""
	var pw: Array = b.per_wave
	for i in range(pw.size()):
		per += "  W%d=%d" % [i + 1, int(pw[i])]
	print("[Level1/Balance] net=%d (waves=%d, gold=%d)%s" % [
		int(b.net_score), int(b.wave_total), int(b.starting_gold), per
	])


func _configure_camera() -> void:
	# Pass map_bounds to GameCamera so it can clamp pan/zoom.
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null and "map_bounds" in cam:
		cam.map_bounds = map_bounds
		if cam.has_method("configure_bounds"):
			cam.configure_bounds(map_bounds)


func _on_editor_tree_changed() -> void:
	_cache_paths()
	queue_redraw()


func _process(_delta: float) -> void:
	# Editor-only: keep the preview in sync with live Marker2D / Path2D drags.
	# Cheap — _draw() only re-runs when queue_redraw flags the node dirty.
	if Engine.is_editor_hint():
		queue_redraw()


func _cache_paths() -> void:
	_paths_by_id.clear()
	if paths_node == null:
		return
	for child in paths_node.get_children():
		if child is Path2D:
			# Node name IS the path_id ("left", "right", "top", ...).
			_paths_by_id[String(child.name)] = child


func get_path_by_id(path_id: String) -> Path2D:
	return _paths_by_id.get(path_id)


# Where the hero appears at level start (and after each respawn).
# Drag the "HeroSpawn" Marker2D in the editor to adjust. Missing marker
# falls back to the viewport center so old levels still boot.
func get_hero_spawn_position() -> Vector2:
	var m: Marker2D = get_node_or_null("HeroSpawn")
	if m != null:
		return m.position
	return Vector2(960, 540)


func _register_tower_spots() -> void:
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


func _draw() -> void:
	# Bleed the background far beyond the design viewport so wider/taller
	# devices and zoomed-out views see grass instead of gray void.
	draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), BG_COLOR)

	# Map border visuals — mountains (top), cliffs (sides), water (bottom).
	_draw_borders()

	# Paths come from children so the Godot Path2D curve editor works.
	var source := paths_node if paths_node != null else get_node_or_null("Paths")
	if source != null:
		for child in source.get_children():
			if child is Path2D and child.curve != null:
				var pts: PackedVector2Array = child.curve.get_baked_points()
				if pts.size() >= 2:
					draw_polyline(pts, PATH_COLOR, PATH_WIDTH)

	var spots := tower_spots_node if tower_spots_node != null else get_node_or_null("TowerSpots")
	if spots != null:
		for child in spots.get_children():
			if child is Marker2D:
				draw_circle(child.position, SPOT_RADIUS, SPOT_FILL)
				draw_arc(child.position, SPOT_RADIUS, 0.0, TAU, 32, SPOT_OUTLINE, 3.0)


func _draw_borders() -> void:
	var mb: Rect2 = map_bounds
	var bw: float = BORDER_WIDTH

	# Top — mountains (jagged triangles).
	var mountain_base_y: float = mb.position.y
	var peak_count: int = int(mb.size.x / 30.0) + 2
	# Use a seeded pattern so peaks are consistent between redraws.
	for i in peak_count:
		var x: float = mb.position.x - 20.0 + i * 32.0
		var peak_h: float = bw * 0.5 + fmod(float(i) * 17.3, bw * 0.6)
		var tri: PackedVector2Array = PackedVector2Array([
			Vector2(x - 18.0, mountain_base_y),
			Vector2(x, mountain_base_y - peak_h),
			Vector2(x + 18.0, mountain_base_y),
		])
		draw_colored_polygon(tri, MOUNTAIN_COLOR)
		# Snow cap on taller peaks.
		if peak_h > bw * 0.7:
			var cap: PackedVector2Array = PackedVector2Array([
				Vector2(x - 6.0, mountain_base_y - peak_h + 10.0),
				Vector2(x, mountain_base_y - peak_h),
				Vector2(x + 6.0, mountain_base_y - peak_h + 10.0),
			])
			draw_colored_polygon(cap, MOUNTAIN_PEAK_COLOR)
	# Solid fill behind mountains so no grass peeks through.
	draw_rect(Rect2(mb.position.x - 100.0, mb.position.y - bw - 200.0, mb.size.x + 200.0, bw + 200.0), MOUNTAIN_COLOR)

	# Bottom — water.
	var water_top_y: float = mb.end.y
	draw_rect(Rect2(mb.position.x - 100.0, water_top_y, mb.size.x + 200.0, bw + 200.0), WATER_COLOR)
	# Wavy shoreline.
	var wave_pts: PackedVector2Array = PackedVector2Array()
	var wave_count: int = int(mb.size.x / 10.0) + 3
	for i in wave_count:
		var x: float = mb.position.x - 10.0 + i * 10.0
		var y_off: float = sin(float(i) * 0.8) * 4.0
		wave_pts.append(Vector2(x, water_top_y + y_off))
	if wave_pts.size() >= 2:
		draw_polyline(wave_pts, WATER_LIGHT, 3.0)

	# Left — cliff wall.
	var cliff_x: float = mb.position.x
	draw_rect(Rect2(cliff_x - bw - 100.0, mb.position.y - bw, bw + 100.0, mb.size.y + bw * 2.0), CLIFF_COLOR)
	# Cliff face edge line.
	draw_line(Vector2(cliff_x, mb.position.y - bw), Vector2(cliff_x, mb.end.y + bw), CLIFF_DARK, 3.0)

	# Right — cliff wall.
	var cliff_r: float = mb.end.x
	draw_rect(Rect2(cliff_r, mb.position.y - bw, bw + 100.0, mb.size.y + bw * 2.0), CLIFF_COLOR)
	draw_line(Vector2(cliff_r, mb.position.y - bw), Vector2(cliff_r, mb.end.y + bw), CLIFF_DARK, 3.0)
