extends Node2D
class_name TowerBarracks

# Phase 16: spawns soldiers up to data.soldier_data.max_count and keeps
# them respawned. Kingdom-Rush-style draggable flag controls where the
# squad rallies — touch the flag, drag, release; the three soldiers
# fan around the new rally point (using data.soldier_spread for the
# triangle shape). Soldiers are parented to the barracks so selling
# cleans them up automatically.

@export var data: TowerData

var level: int = 1

var _active_soldiers: Array[Node] = []
var _slot_positions: Array[Vector2] = []
var _flag_offset: Vector2 = Vector2.ZERO
var _dragging_flag: bool = false
# Tap-to-place mode entered from the TowerSpotMenu's "Move Rally" button.
# While true the range circle is shown and the next InputEventScreenTouch
# either places the rally point (if inside the circle) or cancels.
var _placement_mode: bool = false

@onready var flag_area: Area2D = $FlagArea
@onready var flag_shape: CollisionShape2D = $FlagArea/CollisionShape2D


func _ready() -> void:
	if data == null or data.soldier_scene == null or data.soldier_data == null:
		push_warning("[TowerBarracks] missing data / soldier_scene / soldier_data")
		return
	_flag_offset = data.soldier_blocking_offset
	var circle := CircleShape2D.new()
	circle.radius = 55.0
	flag_shape.shape = circle
	flag_area.position = _flag_offset
	flag_area.input_event.connect(_on_flag_input)
	_slot_positions = _build_slot_positions(_flag_offset)
	EventBus.soldier_died.connect(_on_soldier_died)
	EventBus.barracks_rally_move_requested.connect(_on_rally_move_requested)
	for i in data.soldier_data.max_count:
		_spawn_soldier(i)


func begin_rally_placement() -> void:
	if _placement_mode:
		return
	_placement_mode = true
	# Suppress flag drag during tap-to-place so a tap that happens to land on
	# the flag area isn't interpreted as the start of a drag.
	flag_area.input_pickable = false
	queue_redraw()


func _end_rally_placement() -> void:
	if not _placement_mode:
		return
	_placement_mode = false
	flag_area.input_pickable = true
	queue_redraw()


func _on_rally_move_requested(barracks: Node) -> void:
	if barracks == self:
		begin_rally_placement()


func _build_slot_positions(local_offset: Vector2) -> Array[Vector2]:
	var base: Vector2 = global_position + local_offset
	var sx: float = data.soldier_spread.x
	var sy: float = data.soldier_spread.y
	var positions: Array[Vector2] = []
	positions.append(base + Vector2(-sx, -sy))
	positions.append(base + Vector2(0, sy))
	positions.append(base + Vector2(sx, -sy))
	return positions


func _spawn_soldier(slot_index: int) -> void:
	if slot_index >= _slot_positions.size():
		return
	var soldier: CharacterBody2D = data.soldier_scene.instantiate()
	add_child(soldier)
	soldier.global_position = global_position
	if soldier.has_method("setup"):
		soldier.setup(_slot_positions[slot_index])
	soldier.set_meta("slot_index", slot_index)
	_active_soldiers.append(soldier)
	EventBus.soldier_spawned.emit(soldier, self)


func _on_soldier_died(soldier: Node) -> void:
	var idx: int = _active_soldiers.find(soldier)
	if idx < 0:
		return
	_active_soldiers.remove_at(idx)
	var slot: int = int(soldier.get_meta("slot_index", 0))
	var respawn_time: float = 4.0
	if data.soldier_data != null and "respawn_time" in data.soldier_data:
		respawn_time = data.soldier_data.respawn_time
	_respawn_after(respawn_time, slot)


func _respawn_after(seconds: float, slot: int) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree():
		return
	_spawn_soldier(slot)


func _input(event: InputEvent) -> void:
	# Runs before _unhandled_input, so the placement tap is consumed before
	# SpotInputManager can reopen TowerSpotMenu on the barracks' own spot.
	if not _placement_mode:
		return
	if event is InputEventScreenTouch and event.pressed:
		var local_pos: Vector2 = _screen_to_local(event.position)
		var max_r: float = data.soldier_rally_range if data != null else 0.0
		if max_r <= 0.0 or local_pos.length() <= max_r:
			_flag_offset = _clamp_to_rally_range(local_pos)
			flag_area.position = _flag_offset
			_recall_soldiers()
		_end_rally_placement()
		get_viewport().set_input_as_handled()


func _on_flag_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dragging_flag = true
		queue_redraw()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _dragging_flag:
		return
	if event is InputEventScreenDrag:
		_flag_offset = _clamp_to_rally_range(_screen_to_local(event.position))
		flag_area.position = _flag_offset
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		_dragging_flag = false
		_recall_soldiers()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _clamp_to_rally_range(local_pos: Vector2) -> Vector2:
	if data == null or data.soldier_rally_range <= 0.0:
		return local_pos
	var max_r: float = data.soldier_rally_range
	if local_pos.length() > max_r:
		return local_pos.normalized() * max_r
	return local_pos


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _recall_soldiers() -> void:
	_slot_positions = _build_slot_positions(_flag_offset)
	for soldier in _active_soldiers:
		if soldier == null or not is_instance_valid(soldier):
			continue
		var slot_i: int = int(soldier.get_meta("slot_index", 0))
		if slot_i < _slot_positions.size() and soldier.has_method("set_blocking_position"):
			soldier.set_blocking_position(_slot_positions[slot_i])


func _draw() -> void:
	# Rally range preview — shown while dragging the flag OR while the
	# player is in tap-to-place mode (entered via TowerSpotMenu's "Move
	# Rally" button). Drawn before the tower body so the body sits on
	# top of the fill.
	if (_dragging_flag or _placement_mode) and data != null and data.soldier_rally_range > 0.0:
		draw_circle(Vector2.ZERO, data.soldier_rally_range, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, data.soldier_rally_range, 0, TAU, 48, Color(1.0, 0.9, 0.3, 0.75), 5.0)
	# Tower body
	draw_rect(Rect2(-50, -50, 100, 100), Color(0.55, 0.35, 0.2))
	draw_rect(Rect2(-50, -50, 100, 100), Color(0.2, 0.1, 0.05), false, 6.25)
	draw_line(Vector2(-50, -20), Vector2(50, -20), Color(0.2, 0.1, 0.05), 3.75)
	# Rally flag at _flag_offset (pole + cloth)
	var pole_top: Vector2 = _flag_offset + Vector2(0, -55)
	draw_line(_flag_offset, pole_top, Color(0.25, 0.18, 0.08), 5.0)
	draw_colored_polygon(
		PackedVector2Array([
			pole_top,
			pole_top + Vector2(35, 10),
			pole_top + Vector2(0, 25),
		]),
		Color(0.85, 0.2, 0.2)
	)
