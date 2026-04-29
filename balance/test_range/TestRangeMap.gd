@tool
extends Node2D

# Test Range map — single straight path running across the screen with
# tower spots above and below. Mirrors the Level1.gd public API (get_path_by_id,
# get_hero_spawn_position) so HeroInputManager / GameCamera / TowerPlacer
# all work without modification. Lives in balance/test_range/ so export
# presets can exclude the whole balance/ folder from production builds.

const PATH_COLOR: Color = Color(0.50, 0.45, 0.35)
const PATH_WIDTH: float = 170.0
const BG_COLOR: Color = Color(0.18, 0.20, 0.22)  # darker "dev mode" tint
const SPOT_FILL: Color = Color(0.85, 0.75, 0.35, 0.85)
const SPOT_OUTLINE: Color = Color(0.25, 0.18, 0.08)
const SPOT_RADIUS: float = 65.0

@export var map_bounds: Rect2 = Rect2(0, 0, 1920, 1080)

@onready var paths_node: Node2D = $Paths
@onready var tower_spots_node: Node2D = $TowerSpots
@onready var grid_manager: Node = $GridManager

var _paths_by_id: Dictionary = {}


func _ready() -> void:
	_cache_paths()
	queue_redraw()
	if Engine.is_editor_hint():
		if not child_order_changed.is_connected(_on_editor_tree_changed):
			child_order_changed.connect(_on_editor_tree_changed)
		return
	_register_tower_spots()
	_configure_camera()


func _on_editor_tree_changed() -> void:
	_cache_paths()
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _configure_camera() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null and "map_bounds" in cam:
		cam.map_bounds = map_bounds
		if cam.has_method("configure_bounds"):
			cam.configure_bounds(map_bounds)


func _cache_paths() -> void:
	_paths_by_id.clear()
	if paths_node == null:
		return
	for child in paths_node.get_children():
		if child is Path2D:
			_paths_by_id[String(child.name)] = child


func _register_tower_spots() -> void:
	if grid_manager == null or tower_spots_node == null:
		return
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


# Public — same surface as Level1.gd so existing systems plug in unchanged.
func get_path_by_id(path_id: String) -> Path2D:
	return _paths_by_id.get(path_id)


func get_hero_spawn_position() -> Vector2:
	var m: Marker2D = get_node_or_null("HeroSpawn")
	if m != null:
		return m.position
	return Vector2(1750, 540)


# Test-Range-only — DevPanel uses this to spawn enemies on the canonical lane.
func get_default_spawn_path() -> Path2D:
	return _paths_by_id.get("left")


func _draw() -> void:
	draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), BG_COLOR)
	if paths_node == null:
		return
	for child in paths_node.get_children():
		if child is Path2D:
			_draw_path(child)
	if tower_spots_node != null:
		for child in tower_spots_node.get_children():
			if child is Marker2D:
				draw_circle(child.position, SPOT_RADIUS, SPOT_FILL)
				draw_arc(child.position, SPOT_RADIUS, 0.0, TAU, 32, SPOT_OUTLINE, 4.0)


func _draw_path(p: Path2D) -> void:
	if p.curve == null or p.curve.point_count < 2:
		return
	var pts: PackedVector2Array = p.curve.get_baked_points()
	for i in range(pts.size() - 1):
		draw_line(pts[i] + p.position, pts[i + 1] + p.position, PATH_COLOR, PATH_WIDTH)
