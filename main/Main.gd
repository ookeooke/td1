extends Node2D

# Phase 11: real wave system. Main loads level1_waves.tres and hands it to
# WaveManager. Player places/sells archers while waves run. Phase 12 adds
# win/lose screens on all_waves_completed / game_over. Phase 13 adds a
# small test harness that slows + stuns the first enemy of the run so the
# status-effect system is visible before any tower/skill wires it up.

const LEVEL1_WAVES: Resource = preload("res://levels/level1_waves.tres")
const SlowEffectScript := preload("res://systems/SlowEffect.gd")
const StunEffectScript := preload("res://systems/StunEffect.gd")

@onready var level: Node2D = $Level1
@onready var towers: Node2D = $Towers

var _phase13_demo_used: bool = false


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = level.get_node("GridManager")
	print("[Main] Level1 loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)

	WaveManager.start(LEVEL1_WAVES, level)


func _on_enemy_spawned(enemy: Node, _path_id: String) -> void:
	# Phase 13 demo: apply slow (1.5 s) then stun (1.5 s) to the very first
	# spawn so the tint + speed change are visible on a fresh run.
	if _phase13_demo_used:
		return
	_phase13_demo_used = true
	_demo_status_effects(enemy)


func _demo_status_effects(enemy: Node) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(enemy) or not enemy.has_method("apply_status_effect"):
		return
	enemy.apply_status_effect(SlowEffectScript.new(0.5, 1.5))
	print("[Main] demo: applied SlowEffect to first enemy")
	await get_tree().create_timer(1.8).timeout
	if not is_instance_valid(enemy):
		return
	enemy.apply_status_effect(StunEffectScript.new(1.5))
	print("[Main] demo: applied StunEffect to first enemy")


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
