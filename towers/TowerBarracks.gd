extends Node2D
class_name TowerBarracks

# Phase 16: spawns soldiers up to data.soldier_data.max_count and
# keeps them respawned. Does not shoot — blocking is the job.
# Soldiers are parented to the barracks so selling (queue_free) cleans
# them up automatically. Blocking positions fan around
# global_position + data.soldier_blocking_offset with soldier_spread.

@export var data: TowerData

var level: int = 1

var _active_soldiers: Array[Node] = []
var _slot_positions: Array[Vector2] = []


func _ready() -> void:
	if data == null or data.soldier_scene == null or data.soldier_data == null:
		push_warning("[TowerBarracks] missing data / soldier_scene / soldier_data")
		return
	_slot_positions = _build_slot_positions()
	EventBus.soldier_died.connect(_on_soldier_died)
	for i in data.soldier_data.max_count:
		_spawn_soldier(i)


func _build_slot_positions() -> Array[Vector2]:
	var base: Vector2 = global_position + data.soldier_blocking_offset
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


func _draw() -> void:
	draw_rect(Rect2(-20, -20, 40, 40), Color(0.55, 0.35, 0.2))
	draw_rect(Rect2(-20, -20, 40, 40), Color(0.2, 0.1, 0.05), false, 2.5)
	draw_line(Vector2(-20, -8), Vector2(20, -8), Color(0.2, 0.1, 0.05), 1.5)
