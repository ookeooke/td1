extends Node

# Phase 18: routes tap-to-move commands to the active hero. Sits in
# _unhandled_input so:
#   - A press inside a UI Backdrop (TowerSpotMenu open) is consumed first
#     and never reaches us — menu interactions don't move the hero.
#   - A press intercepted by TowerBarracks rally-placement (_input) is
#     consumed first as well.
# We then explicitly skip taps that fall inside any tower spot's tap
# radius, so opening the build menu doesn't double as a move command.

const SPOT_TAP_RADIUS: float = 36.0

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


func _unhandled_input(event: InputEvent) -> void:
	if _hero == null or _map == null:
		return
	if not (event is InputEventScreenTouch):
		return
	if not event.pressed:
		return
	# Option B: map taps only move when the hero is armed. Tap on the hero
	# body is consumed by BaseHero._input before reaching here, so we never
	# see (de)select presses — only true map taps.
	if "is_selected" in _hero and not _hero.is_selected:
		return
	var world_pos: Vector2 = _map.get_global_transform_with_canvas().affine_inverse() * event.position
	# Skip taps that fall inside a tower spot — those are handled by
	# SpotInputManager / TowerSpotMenu, not as a move command.
	if _grid != null:
		var spot_id: String = _grid.find_nearest_spot(world_pos, SPOT_TAP_RADIUS)
		if spot_id != "":
			return
	if _hero.has_method("move_to"):
		_hero.move_to(world_pos)
		get_viewport().set_input_as_handled()
