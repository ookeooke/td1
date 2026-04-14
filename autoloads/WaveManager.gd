extends Node

# Phase 4: minimal spawn_enemy() helper used for manual test.
# Phase 11 expands into full wave data + multi-path spawning.

const ENEMY_BASIC_SCENE: PackedScene = preload("res://enemies/EnemyBasic.tscn")


func _ready() -> void:
	print("[WaveManager] loaded")


func spawn_enemy(path: Path2D, path_id: String, scene: PackedScene = ENEMY_BASIC_SCENE) -> Node:
	if path == null:
		push_warning("[WaveManager] spawn_enemy got null path for id '%s'" % path_id)
		return null
	var follow := PathFollow2D.new()
	follow.loop = false
	follow.rotates = false
	path.add_child(follow)
	var enemy: Node = scene.instantiate()
	follow.add_child(enemy)
	if enemy.has_method("setup"):
		enemy.setup(follow, path_id)
	EventBus.enemy_spawned.emit(enemy, path_id)
	return enemy
