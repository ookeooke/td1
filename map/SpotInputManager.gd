extends Node

# Listens to EventBus.map_tap_confirmed (dispatched by GameCamera after
# classifying a touch as a tap) and emits tower_spot_tapped when the tap
# falls inside the tap-radius of a registered GridManager spot.
#
# Previously used _unhandled_input directly; now receives confirmed taps
# from the camera's gesture classifier so pan/zoom gestures aren't
# misinterpreted as tower-spot taps.

const TAP_RADIUS: float = 90.0

@export var grid_manager_path: NodePath
@export var map_path: NodePath  # Node2D whose transform maps screen -> world

var _grid: Node
var _map: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if grid_manager_path.is_empty():
		_grid = get_parent().get_node_or_null("GridManager")
	else:
		_grid = get_node_or_null(grid_manager_path)
	if map_path.is_empty():
		_map = get_parent() as Node2D
	else:
		_map = get_node_or_null(map_path) as Node2D
	if _grid == null:
		push_error("[SpotInputManager] GridManager not found")
	if _map == null:
		push_error("[SpotInputManager] Map node not found")
	# Connect first so SpotInputManager has highest priority in the tap chain.
	EventBus.map_tap_confirmed.connect(_on_map_tap)


func _on_map_tap(screen_pos: Vector2, claim: RefCounted) -> void:
	if claim.claimed:
		return
	if _grid == null or _map == null:
		return
	var world_pos: Vector2 = _map.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var zoom_scale: float = _get_zoom_scale()
	var spot_id: String = _grid.find_nearest_spot(world_pos, TAP_RADIUS * zoom_scale)
	if spot_id == "":
		return
	EventBus.tower_spot_tapped.emit(spot_id)
	claim.claimed = true


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
