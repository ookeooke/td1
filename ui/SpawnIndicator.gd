extends CanvasLayer

# Screen-space spawn direction indicators. Replaces the world-space
# SpawnMarker arrows that break with camera pan/zoom.
#
# Reads spawn point data from Level1's SpawnMarkers node (kept as data
# containers) and draws arrows at the nearest screen edge when the spawn
# point is off-screen, or at the projected screen position when on-screen.
#
# Visibility controlled by wave events: arrows appear during wave countdown
# and hide after the wave starts.

const ARROW_SIZE: float = 50.0
const CIRCLE_RADIUS: float = 30.0
const ARROW_COLOR := Color(0.95, 0.85, 0.2)
const OUTLINE_COLOR := Color(0.25, 0.18, 0.05)
const ICON_COLOR := Color(0.55, 0.55, 0.65, 0.85)
const EDGE_MARGIN: float = 75.0   # px from screen edge

@onready var _draw_node: Control = $DrawLayer

# Cached spawn point data: [{world_pos, direction_degrees, path_id}]
var _spawn_points: Array = []
var _visible_path_ids: Array = []
var _showing: bool = false


func _ready() -> void:
	layer = 6  # Below SpellPanel (7), above world
	# Create a Control node to draw on (CanvasLayer needs a Control child).
	if _draw_node == null:
		var ctrl: Control = Control.new()
		ctrl.name = "DrawLayer"
		ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ctrl)
		_draw_node = ctrl
	_draw_node.draw.connect(_on_draw)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_countdown_started.connect(_on_wave_countdown)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	# Deferred so Level1 is ready when we cache spawn points.
	_cache_spawn_points.call_deferred()


func _cache_spawn_points() -> void:
	_spawn_points.clear()
	var level: Node = get_tree().root.find_child("Level1", true, false)
	if level == null:
		return
	var markers: Node = level.get_node_or_null("SpawnMarkers")
	if markers == null:
		return
	for child in markers.get_children():
		if "path_id" in child:
			_spawn_points.append({
				"world_pos": child.global_position,
				"direction_degrees": child.direction_degrees if "direction_degrees" in child else 0.0,
				"path_id": child.path_id,
			})


func _on_wave_countdown(_duration: float) -> void:
	_showing = true
	_draw_node.queue_redraw()


func _on_wave_started(_wave_number: int, path_ids: Array) -> void:
	_visible_path_ids = path_ids
	_showing = true
	_draw_node.queue_redraw()
	# Hide after 2 seconds.
	var tween: Tween = create_tween()
	tween.tween_callback(_hide_arrows).set_delay(2.0)


func _on_all_waves_completed() -> void:
	_hide_arrows()


func _hide_arrows() -> void:
	_showing = false
	_draw_node.queue_redraw()


func _process(_delta: float) -> void:
	if _showing:
		_draw_node.queue_redraw()


func _on_draw() -> void:
	if not _showing or _spawn_points.is_empty():
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var cam: Camera2D = get_viewport().get_camera_2d()

	for sp in _spawn_points:
		# Filter to active paths if we have that info.
		if _visible_path_ids.size() > 0 and sp.path_id not in _visible_path_ids:
			continue
		# Project world position to screen.
		var screen_pos: Vector2 = _world_to_screen(sp.world_pos, cam)
		# Check if on-screen.
		var margin: float = EDGE_MARGIN
		var on_screen: bool = (screen_pos.x >= margin and screen_pos.x <= vp_size.x - margin
			and screen_pos.y >= margin and screen_pos.y <= vp_size.y - margin)
		var draw_pos: Vector2
		var arrow_angle: float
		if on_screen:
			draw_pos = screen_pos
			arrow_angle = deg_to_rad(sp.direction_degrees)
		else:
			# Clamp to screen edge.
			draw_pos = Vector2(
				clampf(screen_pos.x, margin, vp_size.x - margin),
				clampf(screen_pos.y, margin, vp_size.y - margin),
			)
			# Arrow points toward the spawn point (off-screen direction).
			arrow_angle = draw_pos.angle_to_point(screen_pos) + PI
		_draw_arrow(_draw_node, draw_pos, arrow_angle)


func _draw_arrow(ctrl: Control, pos: Vector2, angle: float) -> void:
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = pos + dir * ARROW_SIZE
	var base_l: Vector2 = pos + dir * 10.0 + perp * 30.0
	var base_r: Vector2 = pos + dir * 10.0 - perp * 30.0
	ctrl.draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), ARROW_COLOR)
	ctrl.draw_line(base_l, tip, OUTLINE_COLOR, 5.0)
	ctrl.draw_line(base_r, tip, OUTLINE_COLOR, 5.0)
	ctrl.draw_line(base_l, base_r, OUTLINE_COLOR, 5.0)
	# Enemy icon circle behind arrow.
	var icon_pos: Vector2 = pos - dir * 35.0
	ctrl.draw_circle(icon_pos, CIRCLE_RADIUS, ICON_COLOR)
	ctrl.draw_arc(icon_pos, CIRCLE_RADIUS, 0, TAU, 20, OUTLINE_COLOR, 5.0)


func _world_to_screen(world_pos: Vector2, cam: Camera2D) -> Vector2:
	if cam == null:
		return world_pos
	# Canvas transform maps world → screen (accounts for camera pos + zoom).
	return cam.get_viewport().get_canvas_transform() * world_pos
