extends Node2D

@onready var map: Node2D = $Map


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = map.get_node("GridManager")
	print("[Main] Map loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)

	_phase4_test_spawn()


func _phase4_test_spawn() -> void:
	await get_tree().create_timer(1.0).timeout
	var left_path: Path2D = map.get_path_by_id("left")
	WaveManager.spawn_enemy(left_path, "left")


func _on_enemy_spawned(_enemy: Node, path_id: String) -> void:
	print("[Main] enemy spawned on path '%s'" % path_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] enemy reached end — lives lost: %d" % lives_lost)
