@tool
class_name BaseLevel
extends Node2D

# Shared script for every campaign level scene.
# Subclasses override _level_id() and _wave_list_path() to declare which level
# they represent; everything else (drawing, decorations, hardness readout,
# spot registration, camera config) is identical and lives here.
#
# @tool so editor shows the same green background, brown roads, and
# yellow spot circles you'll see at runtime — drag Path2D points and
# Marker2D spots in the 2D view and the map updates live.
#
# Shared systems (GridManager, SpotInputManager, SpawnMarker) live under
# res://map/ and are instanced per-level scene.
#
# Adding a new level: copy a template under res://levels/templates/ to
# levels/Level<N>.tscn, write a 4-line Level<N>.gd that extends BaseLevel
# and overrides _level_id / _wave_list_path. Done.

const MAP_SIZE := Vector2(1920, 1080)
const BG_COLOR := Color(0.32, 0.52, 0.28, 1.0)
const PATH_COLOR := Color(0.55, 0.40, 0.25)
# Darker outer stroke drawn under the main road — gives the path a defined
# edge against the grass instead of a flat mud band that bleeds into BG.
const PATH_EDGE_COLOR := Color(0.32, 0.22, 0.12)
const PATH_EDGE_PADDING := 10.0
# Road visual must cover the 3-lane swarm band — non-boss enemies get a
# PathFollow2D v_offset picked from {-LANE_SPACING, 0, +LANE_SPACING} (50px),
# and their body draws at roughly ±35px around their center. So the road
# needs to be at least 2 * (50 + 35) = 170px wide to visually contain every
# enemy on the outer lanes. Keep in sync with WaveManager.LANE_SPACING.
const PATH_WIDTH := 170.0
const SPOT_FILL := Color(0.78, 0.72, 0.55, 0.95)
const SPOT_OUTLINE := Color(0.20, 0.15, 0.08)
const SPOT_RADIUS := 65.0
# Cobble ring + crossed-planks build marker — drawn for unoccupied spots so
# the player has a clear "build here" cue. Once a tower is placed on the
# spot, only the foundation circle remains (acts as a base under the tower).
const SPOT_COBBLE_COLOR := Color(0.50, 0.42, 0.32)
const SPOT_COBBLE_HIGHLIGHT := Color(0.65, 0.58, 0.45)
const SPOT_PLANK_COLOR := Color(0.55, 0.38, 0.20)
const SPOT_PLANK_OUTLINE := Color(0.22, 0.14, 0.06)

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
# (soldiers, hero VFX, enemy spawn points) isn't clipped.
@export var map_bounds: Rect2 = Rect2(-40, -40, 2000, 1160)

@onready var paths_node: Node2D = $Paths
@onready var tower_spots_node: Node2D = $TowerSpots
@onready var spawn_markers_node: Node2D = $SpawnMarkers
@onready var grid_manager: Node = $GridManager

var _paths_by_id: Dictionary = {}
# Procedural off-path scenery — trees, bushes, flowers, grass tufts. Generated
# once in _ready (deterministic seed) and drawn between borders and paths.
var _decorations: Array = []
const _EnvironmentScatterScript := preload("res://systems/EnvironmentScatter.gd")


# ============================================================================
# Subclass overrides — declare which level this script represents.
# Defaults are safe: hardness readout no-ops if _wave_list_path() returns "".
# ============================================================================

func _level_id() -> String:
	return "level_unknown"


func _wave_list_path() -> String:
	return ""


# Display tag for log lines. Default derives from _level_id():
# "level_1" → "Level1". Override only if you want something different.
func _display_tag() -> String:
	return _level_id().capitalize().replace(" ", "")


# ============================================================================
# Lifecycle
# ============================================================================

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
	_generate_decorations()
	print("[%s] ready — %d paths, %d spots, %d spawn markers" % [
		_display_tag(),
		_paths_by_id.size(),
		grid_manager.get_spot_count(),
		spawn_markers_node.get_child_count()
	])
	_print_hardness_readout()


# Editor + runtime readout. Delegates to balance/BalanceLogger.gd so the
# debug-print bulk doesn't live in this file. Logger is loaded dynamically
# (per CORE RULE 16) and gated to debug builds inside the logger itself.
func _print_hardness_readout() -> void:
	var logger: GDScript = load("res://balance/BalanceLogger.gd")
	if logger == null:
		return
	logger.print_hardness_readout(self, _level_id(), _wave_list_path(), _display_tag())


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


var _spot_pulse_accum: float = 0.0
# Editor-side accumulator. Marker2D position drags don't fire any tree
# signal, so we still need a polling redraw to keep the preview live —
# but at 60 FPS the full _draw (background + borders + paths + spot
# cobbles + planks) pinned a CPU core when multiple level scenes were
# open as tabs. 10 Hz feels indistinguishable while dragging and costs
# 6× less. Don't unthrottle this without measuring.
var _editor_redraw_accum: float = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_redraw_accum += delta
		if _editor_redraw_accum >= 0.1:
			_editor_redraw_accum = 0.0
			queue_redraw()
		return
	# Runtime: drive the empty-spot pulse at ~20 Hz so unoccupied build pads
	# breathe gently. Throttled so we don't redraw the whole level every
	# frame (paths + borders + spots all share this _draw).
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
			# Node name IS the path_id ("left", "right", "top", "main", ...).
			_paths_by_id[String(child.name)] = child


func get_path_by_id(path_id: String) -> Path2D:
	return _paths_by_id.get(path_id)


# All path_ids this level publishes. WaveManager queries this for endless
# generation so it cycles spawns across whatever paths the level actually
# has — no global hardcoded ["left","right","top"] list.
func get_path_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _paths_by_id.keys():
		ids.append(String(k))
	return ids


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


# Builds the off-path decoration list — deterministic per seed so the same
# map always lays out the same way. Called once at runtime in _ready.
func _generate_decorations() -> void:
	# Collect baked path points from every Path2D (uses the existing pattern
	# from _draw + _cache_paths). Flatten into a single PackedVector2Array.
	var path_pts: PackedVector2Array = PackedVector2Array()
	if paths_node != null:
		for child in paths_node.get_children():
			if child is Path2D and child.curve != null:
				path_pts.append_array(child.curve.get_baked_points())
	# Tower spot positions.
	var spot_positions: Array = []
	if tower_spots_node != null:
		for child in tower_spots_node.get_children():
			if child is Marker2D:
				spot_positions.append(child.position)
	# Hero spawn — defer to the existing helper so future levels with a
	# different marker layout still work.
	var hero_spawn: Vector2 = get_hero_spawn_position()
	_decorations = _EnvironmentScatterScript.generate(
		0xCAFEFACE, map_bounds, path_pts, spot_positions, hero_spawn, 80, 600
	)


func _draw() -> void:
	# Bleed the background far beyond the design viewport so wider/taller
	# devices and zoomed-out views see grass instead of gray void.
	draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), BG_COLOR)

	# Map border visuals — mountains (top), cliffs (sides), water (bottom).
	_draw_borders()

	# Off-path scenery — drawn after borders but before paths, so the road
	# cleanly overlays anything that grew right up to the edge. Trees / bushes
	# pre-sorted by Y inside generate() for a faux-isometric overlap.
	for d in _decorations:
		_EnvironmentScatterScript.draw(self, d)

	# Paths come from children so the Godot Path2D curve editor works.
	# Two-pass draw: a wider darker stroke beneath the main road gives the
	# path a defined edge against the grass instead of fading into the BG.
	var source := paths_node if paths_node != null else get_node_or_null("Paths")
	if source != null:
		for child in source.get_children():
			if child is Path2D and child.curve != null:
				var pts: PackedVector2Array = child.curve.get_baked_points()
				if pts.size() >= 2:
					draw_polyline(pts, PATH_EDGE_COLOR, PATH_WIDTH + PATH_EDGE_PADDING)
					draw_polyline(pts, PATH_COLOR, PATH_WIDTH)

	var spots := tower_spots_node if tower_spots_node != null else get_node_or_null("TowerSpots")
	if spots != null:
		# Pulse phase shared across all unoccupied spots — synchronized
		# breathing so empty spots read as one "ready to build" beat.
		var pulse_t: float = sin(Time.get_ticks_msec() / 480.0) * 0.5 + 0.5  # 0..1
		for child in spots.get_children():
			if not (child is Marker2D):
				continue
			_draw_tower_spot(child.position, child.name, pulse_t)


func _draw_tower_spot(pos: Vector2, spot_id: String, pulse_t: float) -> void:
	# 1. Stone foundation — sandy fill so it reads as a packed-earth pad.
	draw_circle(pos, SPOT_RADIUS, SPOT_FILL)
	# 2. Cobble ring around the perimeter — eight small darker stones with
	# a tiny lighter highlight on each so they read as 3D pebbles. Phase-
	# offset alpha pulse adds gentle life to the spot.
	for i in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.20
		var p: Vector2 = pos + Vector2(cos(ang), sin(ang)) * (SPOT_RADIUS - 7.0)
		draw_circle(p, 7.0, SPOT_COBBLE_COLOR)
		draw_circle(p + Vector2(-1.5, -1.5), 2.5, SPOT_COBBLE_HIGHLIGHT)
	# 3. Outline ring on top of the cobbles for a clean silhouette.
	draw_arc(pos, SPOT_RADIUS, 0.0, TAU, 32, SPOT_OUTLINE, 3.0)

	# 4. Build-ready marker — only shown when the spot is empty. Crossed
	# wooden planks (X shape) plus a small hammer-head dot, gently pulsing
	# in scale so the player's eye is drawn to buildable locations.
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
	# Plank 1 (top-left to bottom-right) — drawn as a thick rounded line.
	draw_line(pos + Vector2(-arm, -arm), pos + Vector2(arm, arm), SPOT_PLANK_OUTLINE, 9.0, true)
	draw_line(pos + Vector2(-arm, -arm), pos + Vector2(arm, arm), SPOT_PLANK_COLOR, 6.0, true)
	# Plank 2 (top-right to bottom-left).
	draw_line(pos + Vector2(arm, -arm), pos + Vector2(-arm, arm), SPOT_PLANK_OUTLINE, 9.0, true)
	draw_line(pos + Vector2(arm, -arm), pos + Vector2(-arm, arm), SPOT_PLANK_COLOR, 6.0, true)
	# Center nail / hammer-head dot.
	draw_circle(pos, 4.0 * pulse_scale, SPOT_COBBLE_COLOR)
	draw_circle(pos, 2.0 * pulse_scale, Color(0.85, 0.78, 0.55))


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
