extends Node

# Tactical-pause inspection — emits EventBus.enemy_inspected when the player
# taps an enemy WHILE the game is paused. Disabled outside pause to avoid
# colliding with the existing tap-to-move-hero flow (taps on empty space
# would otherwise compete between "inspect closest enemy" vs "move hero
# there"). Mirrors HeroInputManager's screen→world conversion + tap-claim
# pattern; connects last in the EventBus.map_tap_confirmed chain so tower
# spots still win during pause.
#
# Tap radius is constant-screen-px (scales with camera zoom) so a tap near
# an enemy at any zoom registers reliably.

const TAP_RADIUS: float = 40.0

@export var map_path: NodePath  # Node2D whose transform maps screen → world (same as HeroInputManager)

var _map: Node2D
var _enabled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map = get_node_or_null(map_path) as Node2D
	if _map == null:
		push_error("[EnemyInputManager] map node not found at %s" % map_path)
	# Connect AFTER SpotInputManager so tower spots still claim taps first
	# during pause (build/upgrade/sell ranks above inspect).
	EventBus.map_tap_confirmed.connect(_on_map_tap)
	EventBus.pause_state_changed.connect(_on_pause_state_changed)


func _on_pause_state_changed(paused: bool) -> void:
	_enabled = paused


func _on_map_tap(screen_pos: Vector2, claim: RefCounted) -> void:
	if not _enabled or claim.claimed:
		return
	if _map == null or not is_instance_valid(_map):
		return
	var world_pos: Vector2 = _map.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var radius: float = TAP_RADIUS * _get_zoom_scale()
	var hit: Node = _nearest_enemy(world_pos, radius)
	if hit == null:
		return
	EventBus.enemy_inspected.emit(hit)
	claim.claimed = true


# Linear scan over the "enemies" group. CORE PERF RULE forbids this in
# _physics_process; in a one-shot tap handler it's cheap (group sizes peak
# in the low hundreds even on hard waves).
func _nearest_enemy(world_pos: Vector2, radius: float) -> Node:
	var best: Node = null
	var best_d2: float = radius * radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if "state" in e and e.state == 3:  # BaseEnemy.State.DYING (WALKING=0, COMBAT=1, STEALTHED=2, DYING=3)
			continue
		var d2: float = (e.global_position - world_pos).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
