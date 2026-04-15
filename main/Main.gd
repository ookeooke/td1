extends Node2D

# Phase 11: real wave system. Main loads level1_waves.tres and hands it to
# WaveManager. Player places/sells archers while waves run. Phase 12 adds
# win/lose screens on all_waves_completed / game_over.

const LEVEL1_WAVES: Resource = preload("res://levels/level1_waves.tres")

@onready var level: Node2D = $Level1
@onready var towers: Node2D = $Towers


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = level.get_node("GridManager")
	print("[Main] Level1 loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.tower_built.connect(_on_tower_built)

	WaveManager.start(LEVEL1_WAVES, level)


func _on_wave_started(wave_number: int, path_ids: Array) -> void:
	print("[Main] wave %d started — paths=%s" % [wave_number, path_ids])


func _on_wave_completed(wave_number: int) -> void:
	print("[Main] wave %d cleared" % wave_number)


func _on_all_waves_completed() -> void:
	print("[Main] VICTORY — all waves cleared")


func _on_tower_built(_tower: Node, spot_id: String) -> void:
	print("[Main] tower built on %s" % spot_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] leak — lives -%d (remaining: %d)" % [lives_lost, GameState.lives])
