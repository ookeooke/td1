extends Node

# Phase 48 C3 — central tap dispatcher for ground item pickups. One manager
# tracks all active ItemPickup nodes; listens to EventBus.map_tap_confirmed
# once and does a spatial query on each tap. Picks the nearest pickup whose
# world-space distance to the tap is within its get_tap_radius(), then
# invokes collect() on it and sets the TapClaim.
#
# Priority in the tap chain:
#   SpotInputManager (tower spots)  ← registers first (scene-level, Main._ready)
#   ItemPickupManager (this)        ← registers via _ready (autoload order)
#   BaseHero / HeroInputManager     ← registers last (after hero spawns)
# This means: tap on a tower spot → tower wins; tap on a ground item with
# no tower nearby → pickup wins; tap on empty ground → hero moves.
#
# We do not iterate-and-emit per-pickup signals (CLAUDE.md lesson: "never
# rely on signal connection order for priority"). Central query is
# deterministic and cheap — N pickups at a time is rarely > 20.

var _active_pickups: Array = []


func _ready() -> void:
	EventBus.map_tap_confirmed.connect(_on_map_tap)
	print("[ItemPickupManager] loaded")


# Called by ItemPickup._ready(). Idempotent.
func register(pickup: Node) -> void:
	if pickup == null or pickup in _active_pickups:
		return
	_active_pickups.append(pickup)


# Called by ItemPickup._exit_tree() (or collect()). Idempotent.
func unregister(pickup: Node) -> void:
	_active_pickups.erase(pickup)


# Called externally (InventoryManager on level_completed) to force-collect
# every still-on-ground pickup. Prevents the "drop on wave 5, win 2 seconds
# later, item lost" edge case. Iterates a snapshot — collect() mutates.
func collect_all_pending() -> void:
	for p in _active_pickups.duplicate():
		if is_instance_valid(p) and p.has_method("_collect"):
			p._collect()


func _on_map_tap(screen_pos: Vector2, claim: RefCounted) -> void:
	if claim.claimed:
		return
	if _active_pickups.is_empty():
		return
	# Screen → world via the viewport's canvas transform. Camera2D's
	# translation/zoom are baked into this transform automatically.
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var world_pos: Vector2 = canvas.affine_inverse() * screen_pos
	var zs: float = _get_zoom_scale()
	var nearest: Node = null
	var best_d2: float = INF
	for p in _active_pickups:
		if p == null or not is_instance_valid(p):
			continue
		var r: float = p.get_tap_radius() * zs
		var d2: float = p.global_position.distance_squared_to(world_pos)
		if d2 > r * r:
			continue
		if d2 < best_d2:
			best_d2 = d2
			nearest = p
	if nearest == null:
		return
	claim.claimed = true
	nearest._collect()


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
