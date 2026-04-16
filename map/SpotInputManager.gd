extends Node

# Captures screen touches and emits EventBus.tower_spot_tapped(spot_id)
# when the tap falls inside the tap-radius of a registered GridManager spot.
# Touch-only per CLAUDE.md: emulate_touch_from_mouse maps mouse clicks to
# InputEventScreenTouch, so we only handle the touch variant.

const TAP_RADIUS: float = 36.0

@export var grid_manager_path: NodePath
@export var map_path: NodePath  # Node2D whose transform maps screen -> world

var _grid: Node
var _map: Node2D


func _ready() -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed:
			return
		_handle_tap(event.position)


func _handle_tap(screen_pos: Vector2) -> void:
	if _grid == null or _map == null:
		return
	var world_pos: Vector2 = _map.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var spot_id: String = _grid.find_nearest_spot(world_pos, TAP_RADIUS)
	if spot_id == "":
		return
	EventBus.tower_spot_tapped.emit(spot_id)
	# Claim the tap for the tower flow — prevents later _unhandled_input
	# handlers (hero selection, hero move command) from also reacting to a
	# press that the player intended for the spot.
	get_viewport().set_input_as_handled()
