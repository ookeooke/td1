extends Node2D

# Phase 10: hollow ring that flashes on top of a tapped tower for DURATION
# seconds, showing its attack radius. One instance lives in Main.tscn;
# listens to EventBus.tower_spot_tapped and resolves the tower via
# GridManager. Re-tap resets the timer.

const DURATION: float = 2.0
const RING_COLOR := Color(1.0, 0.95, 0.4, 0.9)
const FILL_COLOR := Color(1.0, 0.95, 0.4, 0.08)
const RING_WIDTH: float = 3.0
# Ghost ring (post-upgrade reach) — shown on upgrade-slot hover.
# Green when upgrade reach is LARGER than current (drawn outside yellow).
# Red when upgrade reach is SMALLER than current (drawn inside yellow).
const UPGRADE_RING_COLOR := Color(0.35, 0.95, 0.4, 0.75)
const UPGRADE_FILL_COLOR := Color(0.35, 0.95, 0.4, 0.10)
const UPGRADE_SHRINK_RING_COLOR := Color(0.95, 0.35, 0.35, 0.75)
const UPGRADE_SHRINK_FILL_COLOR := Color(0.95, 0.35, 0.35, 0.12)
const UPGRADE_RING_WIDTH: float = 2.0

var _radius: float = 0.0
var _upgrade_radius: float = 0.0
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
	# CORE RULE 14 — every tower implements get_preview_range() (attack
	# reach for combat towers; rally reach for barracks).
	_radius = float(tower.get_preview_range())
	global_position = tower.global_position
	visible = true
	_upgrade_radius = 0.0
	queue_redraw()
	_timer.start()


func _on_tower_sold(_tower: Node, _refund: int) -> void:
	_hide()


func _hide() -> void:
	visible = false
	_upgrade_radius = 0.0
	_timer.stop()


# Phase 45a: used by TowerRadialMenu to preview a buildable tower's range
# while the player hovers its radial icon. Caller owns show/hide (no timer).
func show_preview(world_pos: Vector2, radius: float) -> void:
	_radius = radius
	global_position = world_pos
	visible = true
	_upgrade_radius = 0.0
	_timer.stop()
	queue_redraw()


func hide_preview() -> void:
	_hide()


# Green "ghost ring" drawn over the existing yellow ring to show how much
# extra reach a paid upgrade would grant. Caller owns show/hide.
func show_upgrade_preview(radius: float) -> void:
	_upgrade_radius = radius
	queue_redraw()


func hide_upgrade_preview() -> void:
	_upgrade_radius = 0.0
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	var zs: float = _get_zoom_scale()
	# Snap stroke widths so the ring doesn't shimmy under fractional zoom
	# now that anti-aliasing is off globally. maxf(1.0,...) prevents 0-px.
	var stroke_main: float = maxf(1.0, roundf(RING_WIDTH * zs))
	var stroke_up: float = maxf(1.0, roundf(UPGRADE_RING_WIDTH * zs))
	draw_circle(Vector2.ZERO, _radius, FILL_COLOR)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 24, RING_COLOR, stroke_main)
	# Ghost ring — green outside when reach grows, red inside when it shrinks.
	if _upgrade_radius <= 0.0 or is_equal_approx(_upgrade_radius, _radius):
		return
	if _upgrade_radius > _radius:
		draw_circle(Vector2.ZERO, _upgrade_radius, UPGRADE_FILL_COLOR)
		draw_arc(Vector2.ZERO, _upgrade_radius, 0.0, TAU, 24,
				UPGRADE_RING_COLOR, stroke_up)
	else:
		draw_circle(Vector2.ZERO, _upgrade_radius, UPGRADE_SHRINK_FILL_COLOR)
		draw_arc(Vector2.ZERO, _upgrade_radius, 0.0, TAU, 24,
				UPGRADE_SHRINK_RING_COLOR, stroke_up)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
