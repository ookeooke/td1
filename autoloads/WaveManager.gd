extends Node

# Phase 11: wave runner.
#   start(wave_list, level) kicks off the wave loop.
#   Each wave:
#     1. countdown seconds of grace (emits spawn_direction_changed for markers)
#     2. wave_started(wave_number, path_ids)
#     3. launches one async spawner per WaveSpawn (Timer-based via create_timer)
#     4. wave completes when every spawner finished AND zero alive enemies
#     5. bounty gold is awarded, wave_completed fires, next wave begins
#   All waves cleared → all_waves_completed.
# Game-over stops the loop.
#
# spawn_enemy() is kept as a public helper for ad-hoc spawns (e.g. tests).

var _wave_list: Resource = null
var _level: Node = null
var _wave_index: int = -1
var _active_spawners: int = 0
var _alive_count: int = 0
var _wave_active: bool = false
var _running: bool = false


func _ready() -> void:
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.game_over.connect(_on_game_over)
	print("[WaveManager] loaded")


func start(wave_list: Resource, level: Node) -> void:
	if wave_list == null or wave_list.waves.is_empty():
		push_error("[WaveManager] start: wave_list is empty or null")
		return
	_wave_list = wave_list
	_level = level
	_wave_index = -1
	_alive_count = 0
	_active_spawners = 0
	_wave_active = false
	_running = true
	GameState.wave_number = 0
	_begin_next_wave()


func wave_count() -> int:
	return _wave_list.waves.size() if _wave_list != null else 0


func _begin_next_wave() -> void:
	_wave_index += 1
	if _wave_index >= _wave_list.waves.size():
		_running = false
		EventBus.all_waves_completed.emit()
		print("[WaveManager] all waves complete")
		return
	var wave: Resource = _wave_list.waves[_wave_index]
	var path_ids := _unique_path_ids(wave)
	GameState.wave_number = _wave_index + 1
	for pid in path_ids:
		EventBus.spawn_direction_changed.emit(pid, Vector2.ZERO)
	print("[WaveManager] wave %d countdown %.1fs paths=%s" % [_wave_index + 1, wave.countdown, path_ids])
	await get_tree().create_timer(wave.countdown).timeout
	if not _running:
		return
	_launch_wave(wave, path_ids)


func _launch_wave(wave: Resource, path_ids: Array) -> void:
	_active_spawners = wave.spawns.size()
	_wave_active = true
	EventBus.wave_started.emit(_wave_index + 1, path_ids)
	for spawn in wave.spawns:
		_run_spawner(spawn)


func _run_spawner(spawn: Resource) -> void:
	if spawn.start_delay > 0.0:
		await get_tree().create_timer(spawn.start_delay).timeout
	if not _running:
		return
	var path: Path2D = _level.get_path_by_id(spawn.path_id) if _level != null else null
	if path == null:
		push_warning("[WaveManager] unknown path_id '%s'" % spawn.path_id)
		_active_spawners -= 1
		_maybe_wave_complete()
		return
	for i in spawn.count:
		if not _running:
			return
		spawn_enemy(path, spawn.path_id, spawn.enemy_scene)
		if i < spawn.count - 1:
			await get_tree().create_timer(spawn.interval).timeout
	_active_spawners -= 1
	_maybe_wave_complete()


func _maybe_wave_complete() -> void:
	if not _wave_active:
		return
	if _active_spawners > 0 or _alive_count > 0:
		return
	_wave_active = false
	var wave: Resource = _wave_list.waves[_wave_index]
	if wave.bounty > 0:
		GameState.add_gold(wave.bounty)
	EventBus.wave_completed.emit(_wave_index + 1)
	print("[WaveManager] wave %d complete (+%dg)" % [_wave_index + 1, wave.bounty])
	if _running:
		_begin_next_wave()


func _unique_path_ids(wave: Resource) -> Array:
	var ids: Array = []
	for spawn in wave.spawns:
		if not ids.has(spawn.path_id):
			ids.append(spawn.path_id)
	return ids


func _on_enemy_spawned(enemy: Node, path_id: String) -> void:
	_alive_count += 1
	_log_alive("spawn", enemy, path_id)


func _on_enemy_died(enemy: Node, _gold: int) -> void:
	_alive_count = maxi(0, _alive_count - 1)
	_log_alive("died", enemy, "")
	_maybe_wave_complete()


func _on_enemy_reached_end(enemy: Node, _lives: int) -> void:
	_alive_count = maxi(0, _alive_count - 1)
	_log_alive("leak", enemy, "")
	_maybe_wave_complete()


func _log_alive(tag: String, enemy: Node, path_id: String) -> void:
	var ename := "?"
	if enemy != null and "data" in enemy and enemy.data != null:
		ename = enemy.data.enemy_name
	var extras := ""
	if path_id != "":
		extras = " path=" + path_id
	print("[WaveManager/acct] %s %s%s  alive=%d  spawners=%d  wave_active=%s" % [
		tag, ename, extras, _alive_count, _active_spawners, str(_wave_active)
	])


func _on_game_over() -> void:
	_running = false
	_wave_active = false


func stop() -> void:
	# Called before scene reload / restart. In-flight `await` spawner coroutines
	# check _running on resume and bail, so they exit cleanly without spawning.
	_running = false
	_wave_active = false
	_wave_list = null
	_level = null
	_wave_index = -1
	_active_spawners = 0
	_alive_count = 0


# Public helper (kept from Phase 4) for manual spawning + used internally above.
func spawn_enemy(path: Path2D, path_id: String, scene: PackedScene) -> Node:
	if path == null or scene == null:
		push_warning("[WaveManager] spawn_enemy: missing path or scene")
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
