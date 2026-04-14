extends Node2D

# Phase 2: builds Path2D curves in code, registers tower spots with GridManager.
# Debug visuals via _draw() — placeholder per asset strategy (Phase 41 replaces).

const PATH_LEFT := "left"
const PATH_RIGHT := "right"
const PATH_TOP := "top"

@onready var paths_node: Node2D = $Paths
@onready var tower_spots_node: Node2D = $TowerSpots
@onready var grid_manager: Node = $GridManager

var _paths_by_id: Dictionary = {}


func _ready() -> void:
	_build_curves()
	_register_tower_spots()
	queue_redraw()
	print("[Map] ready — %d paths, %d spots" % [_paths_by_id.size(), grid_manager.get_spot_count()])


func _build_curves() -> void:
	_set_curve("PathLeft", PATH_LEFT, [
		Vector2(0, 420), Vector2(180, 420), Vector2(180, 680), Vector2(375, 680)
	])
	_set_curve("PathRight", PATH_RIGHT, [
		Vector2(375, 220), Vector2(220, 220), Vector2(220, 520), Vector2(0, 520)
	])
	_set_curve("PathTop", PATH_TOP, [
		Vector2(280, 0), Vector2(280, 140), Vector2(80, 140), Vector2(80, 300)
	])


func _set_curve(node_name: String, path_id: String, points: Array) -> void:
	var p: Path2D = paths_node.get_node(node_name)
	var c := Curve2D.new()
	for pt in points:
		c.add_point(pt)
	p.curve = c
	_paths_by_id[path_id] = p


func get_path_by_id(path_id: String) -> Path2D:
	return _paths_by_id.get(path_id)


func _register_tower_spots() -> void:
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


func _draw() -> void:
	# Background fill (placeholder — replaced by tilemap art in Phase 41).
	draw_rect(Rect2(Vector2.ZERO, Vector2(375, 812)), Color(0.32, 0.52, 0.28, 1))

	for path_id in _paths_by_id:
		var p: Path2D = _paths_by_id[path_id]
		if p.curve == null:
			continue
		var pts := p.curve.get_baked_points()
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.55, 0.4, 0.25), 14.0)

	for child in tower_spots_node.get_children():
		if child is Marker2D:
			draw_circle(child.position, 26.0, Color(0.85, 0.75, 0.35, 0.85))
			draw_arc(child.position, 26.0, 0, TAU, 32, Color(0.25, 0.18, 0.08), 3.0)
