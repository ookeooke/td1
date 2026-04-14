extends Node2D

@onready var map: Node2D = $Map


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = map.get_node("GridManager")
	print("[Main] Map loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.enemy_died.connect(_on_enemy_died)

	_phase4_test_spawn()


func _phase4_test_spawn() -> void:
	await get_tree().create_timer(1.0).timeout
	var left_path: Path2D = map.get_path_by_id("left")
	var enemy: Node = WaveManager.spawn_enemy(left_path, "left")
	_phase5_test_damage(enemy)


func _phase5_test_damage(enemy: Node) -> void:
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(enemy):
		print("[Main] applying test TRUE damage to enemy...")
		enemy.take_damage(999.0, DamageCalculator.DamageType.TRUE)


func _on_enemy_spawned(_enemy: Node, path_id: String) -> void:
	print("[Main] enemy spawned on path '%s'" % path_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] enemy reached end — lives lost: %d" % lives_lost)


func _on_enemy_died(_enemy: Node, gold: int) -> void:
	print("[Main] enemy died — +%d gold" % gold)
