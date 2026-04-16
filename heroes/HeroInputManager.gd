extends Node

# Phase 18: routes tap-to-move commands to the active hero. Listens to
# EventBus.map_tap_confirmed (dispatched by GameCamera) instead of
# _unhandled_input, so pan/zoom gestures are never misread as move commands.
#
# Connected after SpotInputManager and BaseHero so tower spots and hero
# selection claim the tap first.

const SPOT_TAP_RADIUS: float = 90.0

@export var hero_path: NodePath
@export var grid_manager_path: NodePath
@export var map_path: NodePath  # Node2D whose transform maps screen → world

var _hero: Node
var _grid: Node
var _map: Node2D


func _ready() -> void:
	if hero_path != NodePath(""):
		_hero = get_node_or_null(hero_path)
	# _hero may also be set directly by Main.gd after dynamic hero spawn.
	_grid = get_node_or_null(grid_manager_path)
	_map = get_node_or_null(map_path) as Node2D
	if _grid == null:
		push_error("[HeroInputManager] GridManager not found at %s" % grid_manager_path)
	if _map == null:
		push_error("[HeroInputManager] map node not found at %s" % map_path)
	# Connect last so SpotInputManager and BaseHero get first chance.
	EventBus.map_tap_confirmed.connect(_on_map_tap)


func _on_map_tap(screen_pos: Vector2, claim: RefCounted) -> void:
	if claim.claimed:
		return
	if _hero == null or _map == null:
		return
	if "is_selected" in _hero and not _hero.is_selected:
		return
	var world_pos: Vector2 = _map.get_global_transform_with_canvas().affine_inverse() * screen_pos
	# Skip taps that fall inside a tower spot — those are handled by
	# SpotInputManager / TowerSpotMenu, not as a move command.
	if _grid != null:
		var zoom_scale: float = _get_zoom_scale()
		var spot_id: String = _grid.find_nearest_spot(world_pos, SPOT_TAP_RADIUS * zoom_scale)
		if spot_id != "":
			return
	if _hero.has_method("move_to"):
		_hero.move_to(world_pos)
		claim.claimed = true


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
