extends Node

# Wave runner — supports KR-style overlap (CORE RULE 19).
#   start(wave_list, level) kicks off the wave loop.
#   Each wave's lifecycle has TWO completion gates:
#     1. spawning_complete — last enemy of wave N has spawned. Countdown for
#        wave N+1 starts here (NOT after kills). Player can call early during
#        this countdown; if they do, wave N+1 begins while N's enemies still
#        walk = overlap pressure. The bonus gold is the reward; the overlap
#        is the cost. Never collapse them back — see CORE RULE 19.
#     2. wave_cleared — every enemy of wave N is dead/leaked. Bounty pays here.
#        Per-wave alive counts are tracked in _alive_per_wave so the right
#        bounty pays at the right moment, even if wave N+1 is already running.
#   All waves cleared → all_waves_completed.
# Game-over stops the loop.

var _wave_list: Resource = null
var _level: Node = null
var _wave_index: int = -1
var _active_spawners: int = 0
var _alive_count: int = 0  # global counter, retained for backwards compat
var _wave_active: bool = false  # true while spawners running for current wave
var _running: bool = false
var _endless: bool = false
# Per-wave alive counts and pending bounties. Enables overlap: wave N+1 can be
# running while wave N's stragglers still die. Keys are 0-based wave indices.
var _alive_per_wave: Dictionary = {}    # wave_index → int
var _pending_bounties: Dictionary = {}  # wave_index → int (bounty paid when alive→0)
var _all_waves_launched: bool = false   # true after the last campaign wave begins spawning
# Per-instance HP multiplier applied to enemies spawned during endless mode.
# 8% compounding per wave (≈ 2× by wave 10, 10× by wave 30) — see BALANCE.md
# "Mode multipliers" → Endless. Reset to 1.0 in start() / start_endless().
var _endless_hp_scale: float = 1.0
# Tick-based countdown state (replaces await-based timer for interruptibility).
var _in_countdown: bool = false
var _countdown_remaining: float = 0.0
var _countdown_total: float = 0.0
var _pending_wave: Resource = null
var _pending_path_ids: Array = []
# Early-call window — Send-Wave button is only available in the last N
# seconds of countdown. Caps the early-call gold bonus per wave at this
# value (1 sec = 1 gold per KR convention). 0 = legacy behavior (button
# available for full countdown). Set by start() from LevelNodeData.
var _early_call_window: float = 0.0

# Enemy scenes for procedural endless wave generation.
const _EnemyBasicScene: PackedScene = preload("res://enemies/EnemyBasic.tscn")
const _EnemyFlyingScene: PackedScene = preload("res://enemies/EnemyFlying.tscn")
const _EnemyHealerScene: PackedScene = preload("res://enemies/EnemyHealer.tscn")
const _Boss1Scene: PackedScene = preload("res://enemies/bosses/Boss1.tscn")
# Boss scenes ride the centerline (v_offset = 0). Add new boss PackedScenes
# here — single source of truth for "is this a boss".
const _BOSS_SCENES: Array[PackedScene] = [
	preload("res://enemies/bosses/Boss1.tscn"),
]
# Phase 43: one Path2D per spawn direction. Non-boss enemies are assigned one
# of 3 discrete lanes via PathFollow2D.v_offset so the swarm occupies three
# visible tracks across horizontal paths. Bosses stay centered.
const _BASE_PATH_IDS: Array[String] = ["left", "right", "top"]
const LANE_SPACING: float = 50.0  # ± pixels between adjacent lanes (v_offset on horizontal paths)


func _ready() -> void:
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.game_over.connect(_on_game_over)
	print("[WaveManager] loaded")


func start(wave_list: Resource, level: Node, early_call_window: float = 0.0) -> void:
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
	_endless_hp_scale = 1.0  # reset — campaign uses authored HP
	_early_call_window = early_call_window
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_all_waves_launched = false
	GameState.wave_number = 0
	_begin_next_wave()


# True if the Send-Wave button should be active right now. KR-canonical:
# the button is available the *entire* countdown, not gated to a final
# window. The bonus magnitude is capped instead (see call_early_wave) so
# unlimited gold isn't possible from long countdowns. Eliminates the
# dead-time the window-gating used to cause.
func early_call_available() -> bool:
	return _in_countdown and _running


func start_endless(level: Node) -> void:
	_level = level
	_wave_index = -1
	_alive_count = 0
	_active_spawners = 0
	_wave_active = false
	_endless = true
	_running = true
	_endless_hp_scale = 1.0  # set per-wave by _generate_endless_wave
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_all_waves_launched = false
	GameState.wave_number = 0
	_begin_next_wave()


func wave_count() -> int:
	if _endless:
		return 0  # infinite — HUD shows "Wave: N" without a total
	return _wave_list.waves.size() if _wave_list != null else 0


func _begin_next_wave() -> void:
	_wave_index += 1
	var wave: Resource = null
	if _endless:
		wave = _generate_endless_wave(_wave_index + 1)
		EventBus.endless_wave_started.emit(_wave_index + 1)
	elif _wave_list != null and _wave_index < _wave_list.waves.size():
		wave = _wave_list.waves[_wave_index]
	else:
		# All campaign waves spawned. Don't fire all_waves_completed yet —
		# the last wave's enemies may still be alive (overlap mechanic).
		# _maybe_pay_bounty triggers all_waves_completed when the last
		# wave's last enemy dies and its bounty pays.
		_all_waves_launched = true
		_maybe_all_waves_complete()
		return
	var path_ids := _unique_path_ids(wave)
	GameState.wave_number = _wave_index + 1
	for pid in path_ids:
		EventBus.spawn_direction_changed.emit(pid, Vector2.ZERO)
	# Tick-based countdown — interruptible via call_early_wave().
	# wave.countdown is authoritative for every wave including W1; first-wave
	# grace is now expressed by authoring a longer countdown in the wave .tres.
	_pending_wave = wave
	_pending_path_ids = path_ids
	_countdown_total = wave.countdown
	_countdown_remaining = wave.countdown
	_in_countdown = true
	EventBus.wave_countdown_started.emit(_countdown_total)
	print("[WaveManager] wave %d countdown %.1fs paths=%s" % [_wave_index + 1, wave.countdown, path_ids])


func _process(delta: float) -> void:
	if not _in_countdown:
		return
	# countdown_total <= 0 = button-only mode. Never auto-launches; player
	# must press the Send Wave button to begin. Used for the very first
	# wave so the player has unbounded setup time.
	if _countdown_total <= 0.0:
		return
	_countdown_remaining -= delta
	if _countdown_remaining <= 0.0:
		_finish_countdown()


func _finish_countdown() -> void:
	_in_countdown = false
	if not _running:
		return
	_launch_wave(_pending_wave, _pending_path_ids)
	_pending_wave = null
	_pending_path_ids = []


func call_early_wave() -> void:
	# Button is available the whole countdown — no time gating, see
	# CORE RULE 19. Bonus = min(seconds_remaining, early_call_window) so
	# unlimited gold isn't possible from long countdowns. Click early =
	# max bonus + max overlap; click late = small bonus + small overlap;
	# wait full = 0 bonus + clean board. Three valid playstyles.
	# Button-only mode (countdown_total <= 0) gives no bonus — pressing
	# just starts the wave; W1 is the canonical use.
	if not early_call_available():
		return
	var bonus: int = 0
	if _countdown_total > 0.0:
		var raw: float = maxf(0.0, _countdown_remaining)
		bonus = int(ceil(minf(raw, _early_call_window)))
	if bonus > 0:
		GameState.add_gold(bonus)
	EventBus.early_wave_triggered.emit(bonus)
	_finish_countdown()


func _launch_wave(wave: Resource, path_ids: Array) -> void:
	_active_spawners = wave.spawns.size()
	_wave_active = true
	# Initialize per-wave tracking. Bounty is queued here, paid later when
	# this wave's last enemy dies (which may be after the next wave starts).
	_alive_per_wave[_wave_index] = 0
	_pending_bounties[_wave_index] = wave.bounty if wave != null else 0
	EventBus.wave_started.emit(_wave_index + 1, path_ids)
	# Edge case: a wave with zero spawners would never complete. Fire the
	# spawning-complete path immediately so the state machine doesn't hang.
	if _active_spawners <= 0:
		_on_spawning_complete()
		return
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
		_on_spawner_finished()
		return
	# Phase 31: Heroic + Iron scale enemy count up and interval down.
	var count: int = spawn.count
	var interval: float = spawn.interval
	if GameState.current_mode == "heroic" or GameState.current_mode == "iron":
		count = int(ceil(count * 1.5))
		interval *= 0.85
	# Capture wave_index at spawn-time. _wave_index advances when the next
	# wave begins; without capture, late spawns would tag with the wrong
	# wave (overlap mechanic relies on per-wave tagging being accurate).
	var wave_idx_for_spawns: int = _wave_index
	for i in count:
		if not _running:
			break
		spawn_enemy(path, spawn.path_id, spawn.enemy_scene, wave_idx_for_spawns)
		if i < count - 1:
			# Phase 42: spawn jitter breaks uniform spacing.
			var jitter: float = randf_range(-0.25, 0.25)
			await get_tree().create_timer(maxf(0.1, interval + jitter)).timeout
	_active_spawners -= 1
	_on_spawner_finished()


# Called every time a spawner exits. When the LAST spawner of the current
# wave finishes, the next wave's countdown begins (NOT after kills) — this
# is the overlap mechanic, see CORE RULE 19.
func _on_spawner_finished() -> void:
	if _active_spawners > 0:
		return
	_on_spawning_complete()


func _on_spawning_complete() -> void:
	if not _wave_active:
		return
	_wave_active = false
	EventBus.wave_spawning_complete.emit(_wave_index + 1)
	print("[WaveManager] wave %d spawning done (alive=%d)" % [
		_wave_index + 1, _alive_per_wave.get(_wave_index, 0)
	])
	if _running:
		_begin_next_wave()


# Called when an enemy of `wave_index` dies/leaks. If that wave's alive
# count drops to zero AND its bounty hasn't been paid yet, pay it now.
# Decoupled from spawning so a wave's bounty pays as soon as its last
# enemy dies, even if the next wave is already running (overlap).
func _maybe_pay_bounty(wave_index: int) -> void:
	if _alive_per_wave.get(wave_index, 0) > 0:
		return
	if not _pending_bounties.has(wave_index):
		return  # already paid or never queued
	var bounty: int = int(_pending_bounties[wave_index])
	if bounty > 0:
		GameState.add_gold(bounty)
	EventBus.wave_completed.emit(wave_index + 1)
	print("[WaveManager] wave %d cleared (+%dg)" % [wave_index + 1, bounty])
	_pending_bounties.erase(wave_index)
	_alive_per_wave.erase(wave_index)
	_maybe_all_waves_complete()


# All-waves-complete fires only after every authored wave has both
# (a) finished spawning AND (b) been fully cleared. Otherwise the level
# would end while wave 5's stragglers are still walking.
func _maybe_all_waves_complete() -> void:
	if not _all_waves_launched:
		return
	if _pending_bounties.size() > 0:
		return
	_running = false
	EventBus.all_waves_completed.emit()
	print("[WaveManager] all waves complete")


func _unique_path_ids(wave: Resource) -> Array:
	var ids: Array = []
	for spawn in wave.spawns:
		if not ids.has(spawn.path_id):
			ids.append(spawn.path_id)
	return ids


func _on_enemy_spawned(enemy: Node, _path_id: String) -> void:
	_alive_count += 1
	# Per-wave count uses the wave_index meta tagged at spawn time. Default
	# to current _wave_index for ad-hoc spawns (Test Range, debug commands).
	var wi: int = enemy.get_meta("wave_index", _wave_index) if enemy != null else _wave_index
	_alive_per_wave[wi] = int(_alive_per_wave.get(wi, 0)) + 1


func _on_enemy_died(enemy: Node, _gold: int) -> void:
	_alive_count = maxi(0, _alive_count - 1)
	_decrement_wave_alive(enemy)


func _on_enemy_reached_end(enemy: Node, _lives: int) -> void:
	_alive_count = maxi(0, _alive_count - 1)
	_decrement_wave_alive(enemy)


func _decrement_wave_alive(enemy: Node) -> void:
	if enemy == null:
		return
	var wi: int = enemy.get_meta("wave_index", -1)
	if wi < 0:
		return  # untracked spawn (Test Range, etc.) — no bounty owed
	_alive_per_wave[wi] = maxi(0, int(_alive_per_wave.get(wi, 0)) - 1)
	_maybe_pay_bounty(wi)


func _on_game_over() -> void:
	_running = false
	_wave_active = false
	_in_countdown = false
	# Defeat → no more bounties pay. Clear so straggler-deaths don't trigger
	# all_waves_completed after game_over.
	_pending_bounties.clear()
	_alive_per_wave.clear()


func stop() -> void:
	# Called before scene reload / restart. In-flight `await` spawner coroutines
	# check _running on resume and bail, so they exit cleanly without spawning.
	_running = false
	_wave_active = false
	_endless = false
	_in_countdown = false
	_pending_wave = null
	_pending_path_ids = []
	_wave_list = null
	_level = null
	_wave_index = -1
	_active_spawners = 0
	_alive_count = 0
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_all_waves_launched = false


# Phase 32: procedural wave generation for endless mode.
# Difficulty ramps: more enemies, faster spawns, more paths, mixed types.
func _generate_endless_wave(wave_num: int) -> Resource:
	var wave_data := preload("res://waves/WaveData.gd").new()
	var spawn_script := preload("res://waves/WaveSpawn.gd")
	wave_data.countdown = maxf(1.5, 3.0 - wave_num * 0.1)
	wave_data.bounty = 10 + wave_num * 5
	# 8% HP per wave compounding — reapplied here every wave so the value
	# stays fresh as _wave_index advances. See BALANCE.md endless multiplier.
	_endless_hp_scale = 1.0 + 0.08 * float(wave_num)

	# Base enemy count scales with wave number.
	var base_count: int = 4 + wave_num * 2
	# Pick paths — early waves use 1-2 paths, later use all 3.
	@warning_ignore("integer_division")
	var num_paths: int = mini(1 + wave_num / 3, _BASE_PATH_IDS.size())
	var active_paths: Array[String] = []
	for i in num_paths:
		active_paths.append(_BASE_PATH_IDS[i % _BASE_PATH_IDS.size()])

	# Distribute enemies across paths with type mixing.
	@warning_ignore("integer_division")
	var enemies_per_path: int = maxi(1, base_count / num_paths)
	var spawns: Array = []
	for pid in active_paths:
		var spawn := spawn_script.new()
		spawn.path_id = pid
		spawn.enemy_scene = _pick_enemy_for_wave(wave_num)
		spawn.count = enemies_per_path
		spawn.interval = maxf(0.4, 1.2 - wave_num * 0.03)
		spawn.start_delay = 0.0
		spawns.append(spawn)

	# Add a healer from wave 5+, flying from wave 3+.
	if wave_num >= 3:
		var fly_spawn := spawn_script.new()
		fly_spawn.path_id = active_paths[randi() % active_paths.size()]
		fly_spawn.enemy_scene = _EnemyFlyingScene
		@warning_ignore("integer_division")
		fly_spawn.count = maxi(1, wave_num / 3)
		fly_spawn.interval = 1.5
		fly_spawn.start_delay = 2.0
		spawns.append(fly_spawn)
	if wave_num >= 5:
		var heal_spawn := spawn_script.new()
		heal_spawn.path_id = active_paths[randi() % active_paths.size()]
		heal_spawn.enemy_scene = _EnemyHealerScene
		@warning_ignore("integer_division")
		heal_spawn.count = maxi(1, wave_num / 5)
		heal_spawn.interval = 3.0
		heal_spawn.start_delay = 3.0
		spawns.append(heal_spawn)
	# Boss every 10 waves in endless.
	if wave_num >= 10 and wave_num % 10 == 0:
		var boss_spawn := spawn_script.new()
		boss_spawn.path_id = active_paths[0]
		boss_spawn.enemy_scene = _Boss1Scene
		boss_spawn.count = 1
		boss_spawn.start_delay = 5.0
		spawns.append(boss_spawn)

	wave_data.spawns = spawns
	return wave_data


func _pick_enemy_for_wave(wave_num: int) -> PackedScene:
	# Weighted random: basics dominate early, harpies mix in later.
	if wave_num < 3 or randi() % 3 > 0:
		return _EnemyBasicScene
	return _EnemyFlyingScene


# Public helper (kept from Phase 4) for manual spawning + used internally above.
# Phase 43: enemies ride one Path2D per direction. Each non-boss picks one of
# 3 discrete lanes via v_offset so the swarm occupies above/main/below tracks.
# Boss scenes ride centered.
# wave_index: 0-based index of the wave this enemy belongs to. -1 = ad-hoc
# spawn (Test Range, debug). Tagged via meta so per-wave bounty pays correctly
# even when waves overlap (CORE RULE 19).
func spawn_enemy(path: Path2D, path_id: String, scene: PackedScene, wave_index: int = -1) -> Node:
	if path == null or scene == null:
		push_warning("[WaveManager] spawn_enemy: missing path or scene")
		return null
	var follow := PathFollow2D.new()
	follow.loop = false
	follow.rotates = false
	if scene in _BOSS_SCENES:
		follow.v_offset = 0.0
	else:
		# 3 discrete lanes: above / main / below the curve.
		# rotates=false + horizontal paths ⇒ v_offset shifts along world Y = perpendicular to travel.
		var lane_idx: int = randi() % 3
		follow.v_offset = float(lane_idx - 1) * LANE_SPACING
	path.add_child(follow)
	var enemy: Node = scene.instantiate()
	enemy.set_meta("wave_index", wave_index)
	# Endless-mode HP scaling — set BEFORE add_child so base_enemy._ready()
	# initializes current_health from the scaled max. Skip in campaign /
	# heroic / iron / Test Range — those keep authored values (scale = 1.0).
	if _endless and "_hp_scale" in enemy:
		enemy._hp_scale = _endless_hp_scale
	follow.add_child(enemy)
	if enemy.has_method("setup"):
		enemy.setup(follow, path_id)
	EventBus.enemy_spawned.emit(enemy, path_id)
	return enemy
