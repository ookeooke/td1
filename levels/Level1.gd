@tool
extends Node2D

# Level1: first campaign map.
# @tool so editor shows the same green background, brown roads, and
# yellow spot circles you'll see at runtime — drag Path2D points and
# Marker2D spots in the 2D view and the map updates live.
#
# Shared systems (GridManager, SpotInputManager, SpawnMarker) live under
# res://map/ and are instanced here. Future levels copy this scene.

const MAP_SIZE := Vector2(375, 812)
const BG_COLOR := Color(0.32, 0.52, 0.28, 1.0)
const PATH_COLOR := Color(0.55, 0.40, 0.25)
const PATH_WIDTH := 14.0
const SPOT_FILL := Color(0.85, 0.75, 0.35, 0.85)
const SPOT_OUTLINE := Color(0.25, 0.18, 0.08)
const SPOT_RADIUS := 26.0

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
		return
	_register_tower_spots()
	print("[Level1] ready — %d paths, %d spots, %d spawn markers" % [
		_paths_by_id.size(),
		grid_manager.get_spot_count(),
		spawn_markers_node.get_child_count()
	])


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


func _register_tower_spots() -> void:
	for child in tower_spots_node.get_children():
		if child is Marker2D:
			grid_manager.register_spot(child.name, child.position)


func _draw() -> void:
	# Bleed the background far beyond the design viewport so wider/taller
	# devices (iPad 4:3, Galaxy Fold) see grass instead of gray void.
	draw_rect(Rect2(Vector2(-1000, -1000), Vector2(3000, 3000)), BG_COLOR)

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
