extends Node2D

# Phase 10: hollow ring that flashes on top of a tapped tower for DURATION
# seconds, showing its attack radius. One instance lives in Main.tscn;
# listens to EventBus.tower_spot_tapped and resolves the tower via
# GridManager. Re-tap resets the timer.

const DURATION: float = 2.0
const RING_COLOR := Color(1.0, 0.95, 0.4, 0.9)
const FILL_COLOR := Color(1.0, 0.95, 0.4, 0.08)
const RING_WIDTH: float = 3.0

var _radius: float = 0.0
var _timer: Timer
var _grid: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 5
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DURATION
	_timer.timeout.connect(_hide)
	add_child(_timer)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)
	EventBus.tower_sold.connect(_on_tower_sold)


func _on_spot_tapped(spot_id: String) -> void:
	if _grid == null:
		_grid = get_tree().root.find_child("GridManager", true, false)
	if _grid == null or not _grid.is_occupied(spot_id):
		return
	var tower: Node = _grid.get_tower_at(spot_id)
	if tower == null:
		return
	# Use level-aware effective range when available (Phase 24 upgrades),
	# fall back to data.attack_range for towers that don't level.
	if tower.has_method("get_effective_range"):
		_radius = float(tower.get_effective_range())
	elif "data" in tower and tower.data != null:
		_radius = float(tower.data.attack_range)
	else:
		return
	global_position = tower.global_position
	visible = true
	queue_redraw()
	_timer.start()


func _on_tower_sold(_tower: Node, _refund: int) -> void:
	_hide()


func _hide() -> void:
	visible = false
	_timer.stop()


func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius, FILL_COLOR)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, RING_COLOR, RING_WIDTH)
