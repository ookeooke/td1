extends Node2D

const ARCHER_SCENE: PackedScene = preload("res://towers/TowerArcher.tscn")

@onready var map: Node2D = $Map


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = map.get_node("GridManager")
	print("[Main] Map loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.enemy_died.connect(_on_enemy_died)

	_phase6_test_tower_vs_enemy()


func _phase6_test_tower_vs_enemy() -> void:
	_place_archer_on_spot("Spot1")
	await get_tree().create_timer(1.0).timeout
	var left_path: Path2D = map.get_path_by_id("left")
	WaveManager.spawn_enemy(left_path, "left")


func _place_archer_on_spot(spot_id: String) -> void:
	var grid: Node = map.get_node("GridManager")
	var pos: Vector2 = grid.get_spot_position(spot_id)
	var archer: Node2D = ARCHER_SCENE.instantiate()
	archer.position = pos
	map.add_child(archer)
	print("[Main] placed archer at %s %s" % [spot_id, pos])


func _on_enemy_spawned(_enemy: Node, path_id: String) -> void:
	print("[Main] enemy spawned on path '%s'" % path_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] enemy reached end — lives lost: %d" % lives_lost)


func _on_enemy_died(_enemy: Node, gold: int) -> void:
	print("[Main] enemy died — +%d gold" % gold)
