extends Node2D

# Phase 8: interactive placement. User taps empty spots → TowerSpotMenu →
# Build Archer → TowerPlacer spends gold and spawns the tower.
# Test harness now loops enemies on rotating paths so players have targets
# before WaveManager comes online in Phase 11.

const ENEMY_BASIC_SCENE: PackedScene = preload("res://enemies/EnemyBasic.tscn")
const ENEMY_SPAWN_INTERVAL: float = 2.5
const ENEMY_PATHS: Array[String] = ["left", "right", "top"]

@onready var map: Node2D = $Map
@onready var towers: Node2D = $Towers

var _spawn_index: int = 0


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = map.get_node("GridManager")
	print("[Main] Map loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)

	_start_enemy_loop()


func _start_enemy_loop() -> void:
	var t := Timer.new()
	t.wait_time = ENEMY_SPAWN_INTERVAL
	t.autostart = true
	t.timeout.connect(_spawn_test_enemy)
	add_child(t)


func _spawn_test_enemy() -> void:
	var path_id: String = ENEMY_PATHS[_spawn_index % ENEMY_PATHS.size()]
	_spawn_index += 1
	var p: Path2D = map.get_path_by_id(path_id)
	if p == null:
		return
	WaveManager.spawn_enemy(p, path_id, ENEMY_BASIC_SCENE)


func _on_spot_tapped(spot_id: String) -> void:
	print("[Main] spot tapped: %s" % spot_id)


func _on_tower_built(_tower: Node, spot_id: String) -> void:
	print("[Main] tower built on %s" % spot_id)


func _on_enemy_spawned(_enemy: Node, path_id: String) -> void:
	print("[Main] enemy spawned on path '%s'" % path_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] enemy reached end — lives lost: %d" % lives_lost)


func _on_enemy_died(_enemy: Node, gold: int) -> void:
	print("[Main] enemy died — +%d gold" % gold)
