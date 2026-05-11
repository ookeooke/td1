extends Node

# Debug-only override surface — applied to per-level early-call window etc.
# `is_active()` short-circuits to identity returns in non-debug builds, so
# preload + read paths are zero-cost in production.
const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")

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
var _wave_active: bool = false # true while spawners running for current wave
var _running: bool = false
var _endless: bool = false
# Monotonic session id — bumped on every start() / start_endless(). Each
# _run_spawner coroutine captures the id at launch as `session_id` and bails
# on resume if it no longer matches `_session_id`. Without this, a stale
# spawner parked on `await create_timer().timeout` from a PRIOR run can wake
# up AFTER PauseMenu's restart flow has already torn down (`stop()`) and
# restarted (`start()` from the new Main scene), and clobber the fresh run's
# state — most visibly by re-setting `_running = false` in the defensive
# `is_instance_valid(_level/path)` branches, which is the bug that hid the
# Send-Wave badge after Level 5 restart.
var _session_id: int = 0
# Per-wave alive counts and pending bounties. Enables overlap: wave N+1 can be
# running while wave N's stragglers still die. Keys are 0-based wave indices.
var _alive_per_wave: Dictionary = {} # wave_index → int
var _pending_bounties: Dictionary = {} # wave_index → int (bounty paid when alive→0)
# Per-wave spawner-pending count. Bounty for wave N waits until both
# alive[N] == 0 AND pending_spawners[N] == 0. Without this, a wave with a
# late-spawning emitter (e.g. boss with start_delay) would pay bounty as soon
# as the early enemies died, leaving the boss as a "ghost" with no payout.
# Also load-bearing for mid-spawn early-call (Stage E): wave N+1 can launch
# while wave N's spawners are still queued, and the per-wave gate keeps each
# wave's bounty correct.
var _pending_spawners_per_wave: Dictionary = {} # wave_index → int
var _all_waves_launched: bool = false # true after the last campaign wave begins spawning
# Per-instance HP multiplier applied to enemies spawned during endless mode.
# 8% additive per wave: scale = 1 + 0.08 × wave_num (W10 = 1.8×, W30 = 3.4×).
# Linear was a deliberate choice — exponential makes leaderboard scores
# incomparable across runs and rebalances every endless session. See
# BALANCE.md "Mode multipliers" → Endless. Reset to 1.0 in start() / start_endless().
var _endless_hp_scale: float = 1.0
# Countdown state was removed in the overlap-only redesign. Spawn-window
# tracking lives in _current_spawn_window_sec / _current_spawn_start_msec
# below, populated by _launch_wave.
# Early-call window — Send-Wave button is only available in the last N
# seconds of countdown. Caps the early-call gold bonus per wave at this
# value (1 sec = 1 gold per KR convention). 0 = legacy behavior (button
# available for full countdown). Set by start() from LevelNodeData.
var _early_call_window: float = 0.0
# Per-level default gold-per-second for early-call bonus (set in start()
# from LevelNodeData.early_call_gold_per_sec). Per-wave authored values +
# debug overrides can replace via the resolution chain.
var _default_gold_per_sec: float = 1.0
# Spawn-window tracking — set when each wave launches so early-call gating
# can read "how many seconds left in the current spawn?". Replaces the
# old countdown-based _in_countdown / _countdown_remaining state.
# `_spawn_elapsed_game` accumulates `delta` from `_process`, which is scaled
# by Engine.time_scale and zero during pause — same frame of reference as
# the spawner's `await create_timer(...).timeout`. Wall-clock-based
# tracking (Time.get_ticks_msec) was diverging from spawner timing under
# 2x/3x speed and during pause, breaking the early-call gate.
var _current_spawn_window_sec: float = 0.0
var _spawn_elapsed_game: float = 0.0
# Pre-W1 grace state — campaign mode only. After start(), the wave loop
# parks in this state until the player presses Send Wave ("Start Wave 1").
# Gives unlimited initial setup time at level load. Doesn't apply to
# subsequent waves (back-to-back per overlap-only redesign) or to endless
# mode (start_endless launches immediately).
var _pre_w1_pending: bool = false
var _pre_w1_pending_wave: Resource = null
var _pre_w1_pending_path_ids: Array = []

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
# Endless mode discovers the active level's path_ids via _level.get_path_ids()
# at wave-generation time — no global path-id list, so any level topology
# (1 path, 3 paths, ring, etc.) works without WaveManager edits.
const _ENDLESS_PATH_FALLBACK: Array[String] = ["left"]
const LANE_SPACING: float = 50.0 # ± pixels between adjacent lanes (v_offset on horizontal paths)


func _ready() -> void:
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.game_over.connect(_on_game_over)
	print("[WaveManager] loaded")


func start(wave_list: Resource, level: Node, early_call_window: float = 0.0,
		early_call_gold_per_sec: float = 1.0) -> void:
	if wave_list == null or wave_list.waves.is_empty():
		push_error("[WaveManager] start: wave_list is empty or null")
		return
	# Bump session before any state clearing so stale spawners parked on
	# await from the previous run bail on resume via the session_id guard.
	_session_id += 1
	_wave_list = wave_list
	_level = level
	_wave_index = -1
	_active_spawners = 0
	_wave_active = false
	_running = true
	_endless = false
	_endless_hp_scale = 1.0 # reset — campaign uses authored HP
	_early_call_window = early_call_window
	_default_gold_per_sec = early_call_gold_per_sec
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_pending_spawners_per_wave.clear()
	_all_waves_launched = false
	_current_spawn_window_sec = 0.0
	_spawn_elapsed_game = 0.0
	_pre_w1_pending = false
	_pre_w1_pending_wave = null
	_pre_w1_pending_path_ids = []
	RunState.wave_number = 0
	_begin_next_wave()


# True if the Send-Wave button should be active right now. Strict
# "last N seconds" gate: button visible during the LAST N seconds of the
# current wave's spawn, where N = early_call_window_sec for the next
# wave (resolved via the standard chain). Driven by balance data — author
# tunes the window per-wave or per-level; runtime honors it directly.
# Bonus = seconds_remaining × gold_per_sec, computed in
# current_early_call_bonus().
#
# Critical: depends on _seconds_left_in_current_spawn returning game-time
# elapsed (not wall-clock). That's tracked via delta accumulation in
# _process so 2x/3x speed and pause behave correctly.
#
# A next-wave window of 0 still hides the button (no early-call mechanic
# for that wave).
func early_call_available() -> bool:
	if not _running:
		return false
	# Pre-W1 grace: button is the level-start trigger.
	if _pre_w1_pending:
		return true
	if not _wave_active or _all_waves_launched:
		return false
	var target_wave_idx: int = _wave_index + 1
	var window: float = _effective_early_call_window(target_wave_idx)
	if window <= 0.0:
		return false
	# Empty-wave / last-frame guard: spawning_complete fires the same frame
	# when remaining hits zero, so don't surface the button for an already-
	# finished wave.
	var remaining: float = _seconds_left_in_current_spawn()
	if remaining <= 0.0:
		return false
	return remaining <= window


# True while the wave loop is parked at level start waiting for Send Wave.
# HUD reads this to swap the button label to "Start Wave 1".
func is_pre_w1_pending() -> bool:
	return _pre_w1_pending


# Seconds remaining in the current wave's spawn (0 when not active). Drives
# both the early-call gate and the bonus formula. `_spawn_elapsed_game`
# accumulates from `_process(delta)` — same time-scaled, pause-aware frame
# of reference the spawner's timers use.
func _seconds_left_in_current_spawn() -> float:
	if not _wave_active or _current_spawn_window_sec <= 0.0:
		return 0.0
	return max(0.0, _current_spawn_window_sec - _spawn_elapsed_game)


# State accessors retained for HUD compatibility. After the redesign, the
# HUD reads `early_call_available()` and `current_early_call_bonus()` plus
# this seconds-left helper for the "Ys saved" label.
func seconds_left_in_current_spawn() -> float:
	return _seconds_left_in_current_spawn()


func countdown_total() -> float:
	# Compat shim — total = effective early-call window of the next wave.
	if _all_waves_launched:
		return 0.0
	return _effective_early_call_window(_wave_index + 1)


func countdown_remaining() -> float:
	# Compat shim — remaining seconds within the early-call window. Equals
	# the overlap that pressing right now would create.
	var target_wave_idx: int = _wave_index + 1
	var window: float = _effective_early_call_window(target_wave_idx)
	return clampf(_seconds_left_in_current_spawn(), 0.0, window)


# Bonus gold the player would earn if they pressed Send Wave RIGHT NOW.
# Formula: overlap_seconds × gold_per_sec, capped at the early-call window.
# Press at window start → max bonus + max overlap. Press near current wave's
# spawn end → small bonus, small overlap.
func current_early_call_bonus() -> int:
	if not _running:
		return 0
	# Pre-W1 grace: pressing Send Wave just starts the level. No bonus,
	# no overlap — there's no previous wave to overlap with.
	if _pre_w1_pending:
		return 0
	if not _wave_active or _all_waves_launched:
		return 0
	var target_wave_idx: int = _wave_index + 1
	var window: float = _effective_early_call_window(target_wave_idx)
	var rate: float = _effective_gold_per_sec(target_wave_idx)
	var remaining: float = _seconds_left_in_current_spawn()
	var overlap: float = clampf(remaining, 0.0, window)
	return int(ceil(overlap * rate))


# Resolve effective gold-per-second for early-call bonus. Same 4-step chain
# pattern as _effective_early_call_window. Identity in production via the
# BalanceOverrides.is_active() short-circuit.
func _effective_gold_per_sec(target_wave_idx: int) -> float:
	var lvl_id: String = RunState.current_level_id
	if target_wave_idx >= 0:
		var w_dbg: float = BalanceOverrides.get_wave_gold_per_sec(lvl_id, target_wave_idx)
		if w_dbg >= 0.0:
			return w_dbg
	if _wave_list != null and target_wave_idx >= 0 and target_wave_idx < _wave_list.waves.size():
		var w: WaveData = _wave_list.waves[target_wave_idx]
		if w != null and "early_call_gold_per_sec" in w and w.early_call_gold_per_sec >= 0.0:
			return float(w.early_call_gold_per_sec)
	return _default_gold_per_sec


# Total spawn-window duration for a wave = max over emitters of
# (effective_start_delay + (effective_count - 1) * effective_interval).
# Reads through BalanceOverrides so the runtime gate matches the chart's
# rendering exactly. Identity in production via is_active() short-circuit.
func _compute_effective_spawn_window(wave: Resource, wave_idx: int) -> float:
	if wave == null or wave.spawns.is_empty():
		return 0.0
	var lvl_id: String = RunState.current_level_id
	var window: float = 0.0
	for si in range(wave.spawns.size()):
		var spawn: Resource = wave.spawns[si]
		if spawn == null:
			continue
		# Effective count
		var count_mult: float = BalanceOverrides.get_wave_count_mult(lvl_id, wave_idx, si)
		var count: int = max(0, int(round(float(spawn.count) * count_mult)))
		if count <= 0:
			continue
		# Effective interval
		var int_ov: float = BalanceOverrides.get_wave_interval(lvl_id, wave_idx, si)
		var interval: float = float(spawn.interval) if int_ov < 0.0 else int_ov
		# Effective start_delay
		var dly_ov: float = BalanceOverrides.get_wave_delay(lvl_id, wave_idx, si)
		var start_t: float = float(spawn.start_delay) if dly_ov < 0.0 else dly_ov
		var end_t: float = start_t + float(max(count - 1, 0)) * interval
		if end_t > window:
			window = end_t
	return window


# Resolve the effective early-call window for a target wave index. Checks
# (top wins):
#   1. Per-wave debug override (BalanceSliders slider, sentinel -1 = inherit).
#   2. Per-wave authored value (WaveData.early_call_window_sec, -1 = inherit).
#   3. Per-level debug override (BalanceSliders level slider, sentinel -1).
#   4. Per-level authored value (LevelNodeData.early_call_window_sec, cached
#      in _early_call_window at start()).
# Identity in production (BalanceOverrides.is_active() short-circuits).
func _effective_early_call_window(target_wave_idx: int) -> float:
	var lvl_id: String = RunState.current_level_id
	# 1. Per-wave debug override.
	if target_wave_idx >= 0:
		var w_dbg: float = BalanceOverrides.get_wave_early_call_window(lvl_id, target_wave_idx)
		if w_dbg >= 0.0:
			return w_dbg
	# 2. Per-wave authored value.
	if _wave_list != null and target_wave_idx >= 0 and target_wave_idx < _wave_list.waves.size():
		var w: WaveData = _wave_list.waves[target_wave_idx]
		if w != null and "early_call_window_sec" in w and w.early_call_window_sec >= 0.0:
			return w.early_call_window_sec
	# 3. Per-level debug override.
	var lvl_ov: int = BalanceOverrides.get_level_int(lvl_id, "early_call_window", -1)
	if lvl_ov >= 0:
		return float(lvl_ov)
	# 4. Per-level authored value (cached).
	return _early_call_window


func start_endless(level: Node) -> void:
	# Bump session before any state clearing — same rationale as start().
	_session_id += 1
	_level = level
	_wave_index = -1
	_active_spawners = 0
	_wave_active = false
	_endless = true
	_running = true
	_endless_hp_scale = 1.0 # set per-wave by _generate_endless_wave
	_default_gold_per_sec = 1.0
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_pending_spawners_per_wave.clear()
	_all_waves_launched = false
	_current_spawn_window_sec = 0.0
	_spawn_elapsed_game = 0.0
	_pre_w1_pending = false
	_pre_w1_pending_wave = null
	_pre_w1_pending_path_ids = []
	RunState.wave_number = 0
	_begin_next_wave()


func wave_count() -> int:
	if _endless:
		return 0 # infinite — HUD shows "Wave: N" without a total
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
	RunState.wave_number = _wave_index + 1
	for pid in path_ids:
		EventBus.spawn_direction_changed.emit(pid, Vector2.ZERO)
	# Pre-W1 grace: campaign mode parks before W1 launches so the player has
	# unlimited setup time. Send Wave button shows "Start Wave 1" — pressing
	# it kicks off W1 (no bonus, no overlap; it's just the start trigger).
	# Endless mode skips this and launches immediately (start_endless flow).
	if _wave_index == 0 and not _endless:
		_pre_w1_pending = true
		_pre_w1_pending_wave = wave
		_pre_w1_pending_path_ids = path_ids
		EventBus.pre_first_wave_ready.emit()
		print("[WaveManager] pre-W1 grace — waiting for Send Wave press")
		return
	_launch_wave(wave, path_ids)


func _process(delta: float) -> void:
	# Accumulate game-time elapsed since the current wave launched. `delta`
	# is automatically scaled by Engine.time_scale and zero during pause —
	# matches the spawner's `await create_timer(...).timeout` frame of
	# reference, so _seconds_left_in_current_spawn agrees with reality at
	# any speed and across pauses.
	if _wave_active:
		_spawn_elapsed_game += delta


func call_early_wave() -> void:
	# Overlap-only redesign: button is active in the LAST N seconds of the
	# current wave's spawn (gated by early_call_available). Pressing →
	# next wave begins immediately, parallel to the still-running current
	# spawners. Bonus = overlap_seconds × gold_per_sec. CORE RULE 19's
	# overlap invariant kept: the current wave's spawners continue tagging
	# their enemies to the current wave_index via captured wave_idx_for_spawns.
	#
	# Pre-W1 grace: same button doubles as "Start Wave 1" — kicks off the
	# parked W1 with no bonus and no overlap.
	if not early_call_available():
		return
	if _pre_w1_pending:
		var w: Resource = _pre_w1_pending_wave
		var p: Array = _pre_w1_pending_path_ids
		_pre_w1_pending = false
		_pre_w1_pending_wave = null
		_pre_w1_pending_path_ids = []
		EventBus.early_wave_triggered.emit(0)
		_launch_wave(w, p)
		return
	var bonus: int = current_early_call_bonus()
	if bonus > 0:
		RunState.add_gold(bonus)
	EventBus.early_wave_triggered.emit(bonus)
	_begin_next_wave()


func _launch_wave(wave: Resource, path_ids: Array) -> void:
	# `+=`, not `=`. Spawners from a prior wave that are still mid-`await`
	# (start_delay or interval) when this wave launches MUST stay tracked,
	# otherwise the new wave's `_active_spawners` overwrites the count and
	# the prior wave's coroutines decrement a counter that has lost their
	# contribution. Cumulative count + per-spawner -1 keeps the math honest
	# across overlapping waves.
	_active_spawners += wave.spawns.size()
	_wave_active = true
	# Initialize per-wave tracking. Bounty is queued here, paid later when
	# this wave's last enemy dies AND all of this wave's spawners have run.
	_alive_per_wave[_wave_index] = 0
	_pending_bounties[_wave_index] = wave.bounty if wave != null else 0
	_pending_spawners_per_wave[_wave_index] = wave.spawns.size()
	# Spawn-window tracking — drives early_call_available + bonus formula.
	# Window = max effective end-time across emitters. Effective values
	# resolve through BalanceOverrides (count_mult / interval / start_delay)
	# so the runtime gating matches what the chart shows.
	_current_spawn_window_sec = _compute_effective_spawn_window(wave, _wave_index)
	_spawn_elapsed_game = 0.0
	EventBus.wave_started.emit(_wave_index + 1, path_ids)
	# Edge case: a wave with zero spawners would never complete. Fire the
	# spawning-complete path immediately so the state machine doesn't hang.
	if wave.spawns.size() <= 0:
		_on_spawning_complete()
		return
	# Pass wave_index as a parameter, NOT captured inside _run_spawner after
	# the start_delay await. If the player early-calls during the await,
	# `_wave_index` would advance and the spawner would tag its enemies to
	# the WRONG wave on resume — silently breaking the per-wave alive count
	# (this wave's count never increments → never decrements to 0 → bounty
	# never pays → all_waves_completed never fires).
	#
	# spawn_idx is also captured here so per-emitter count overrides
	# (BalanceOverrides.wave_overrides) can be applied inside _run_spawner.
	for i in wave.spawns.size():
		_run_spawner(wave.spawns[i], _wave_index, i, _session_id)


func _run_spawner(spawn: Resource, wave_idx_for_spawns: int, spawn_idx: int,
		session_id: int) -> void:
	# Resolve override-aware start_delay (sentinel -1 = use authored).
	# Mirrors the count override: identity in production via is_active().
	var effective_delay: float = spawn.start_delay
	var delay_ov: float = BalanceOverrides.get_wave_delay(
		RunState.current_level_id, wave_idx_for_spawns, spawn_idx
	)
	if delay_ov >= 0.0:
		effective_delay = delay_ov
	if effective_delay > 0.0:
		await get_tree().create_timer(effective_delay).timeout
	# Session guard — bail if this coroutine outlived its run (stop() →
	# start() happened during the await). Without this, the writes below
	# would corrupt the fresh run's state. See _session_id declaration.
	if session_id != _session_id:
		return
	if not _running:
		return
	# Defensive: the level (and its Path2D children) may have been freed
	# during the start_delay await — scene change, level restart, quit-to-
	# menu. WaveManager is an autoload and survives, but its cached _level
	# pointer becomes a freed reference. Use is_instance_valid here, not
	# `!= null`, because Godot 4 doesn't auto-null vars to freed objects.
	# We do NOT clear _running here — the session guard above already
	# rejected stale-coroutine resumes; if we're past that gate and _level
	# is freed mid-current-run, the bookkeeping unwind happens via stop()
	# from whoever triggered the scene change.
	if not is_instance_valid(_level):
		_spawner_done(wave_idx_for_spawns)
		return
	var path: Path2D = _level.get_path_by_id(spawn.path_id)
	if path == null:
		push_warning("[WaveManager] unknown path_id '%s'" % spawn.path_id)
		_spawner_done(wave_idx_for_spawns)
		return
	# Phase 31: Heroic + Iron scale enemy count up and interval down.
	var count: int = spawn.count
	var interval: float = spawn.interval
	# Per-emitter interval override BEFORE Heroic/Iron scaling so the
	# slider expresses absolute "campaign-mode interval" — modes still
	# scale on top, matching authored behavior.
	var interval_ov: float = BalanceOverrides.get_wave_interval(
		RunState.current_level_id, wave_idx_for_spawns, spawn_idx
	)
	if interval_ov >= 0.0:
		interval = interval_ov
	if RunState.current_mode == "heroic" or RunState.current_mode == "iron":
		count = int(ceil(count * 1.5))
		interval *= 0.85
	# Debug-only per-emitter count override (BalanceSliders Edit emitters).
	# Mult of 0 disables the emitter entirely; 0.5 halves; 2.0 doubles.
	# is_active() short-circuit returns 1.0 in production = no perf cost.
	var BO = preload("res://balance/debug/BalanceOverrides.gd")
	var count_mult: float = BO.get_wave_count_mult(
		RunState.current_level_id, wave_idx_for_spawns, spawn_idx
	)
	if absf(count_mult - 1.0) > 0.0001:
		count = max(0, int(round(float(count) * count_mult)))
	# wave_idx_for_spawns is now a parameter captured at LAUNCH (pre-await),
	# not after the start_delay sleep. This makes early-call timing safe:
	# even if `_wave_index` advances while this spawner is sleeping, it tags
	# enemies to the wave it was AUTHORED for, keeping per-wave alive counts
	# accurate. (Was a soft-lock vector — see Phase 56b notes.)
	for i in count:
		# Session guard runs FIRST so a stale coroutine never touches
		# `path` / `_level` / RunState belonging to a fresh run. Mirrors
		# the post-start_delay guard above.
		if session_id != _session_id:
			return
		if not _running:
			break
		# Same teardown race as above: the inter-spawn `await` below can
		# survive a level free, leaving `path` (and `_level`) as freed
		# references. Bail out before spawn_enemy crashes on the freed
		# Path2D — abort the whole loop since further spawns are pointless.
		# We do NOT clear _running here (the session guard already caught
		# the stale-coroutine case; a mid-current-run level-free is handled
		# by whoever triggered the scene change calling stop()).
		if not is_instance_valid(path) or not is_instance_valid(_level):
			break
		spawn_enemy(path, spawn.path_id, spawn.enemy_scene, wave_idx_for_spawns)
		if i < count - 1:
			# Phase 42: spawn jitter breaks uniform spacing.
			var jitter: float = randf_range(-0.25, 0.25)
			await get_tree().create_timer(maxf(0.1, interval + jitter)).timeout
	_spawner_done(wave_idx_for_spawns)


# Centralized spawner-exit bookkeeping. Decrements the global active counter
# AND the per-wave pending counter, then re-evaluates the per-wave bounty
# (now that this wave is one spawner closer to "all spawners done"). When
# the global counter hits zero, the legacy spawning_complete event fires
# (drives next-wave countdown). Used by every exit path in _run_spawner.
func _spawner_done(wave_idx: int) -> void:
	_active_spawners = max(0, _active_spawners - 1)
	var pending: int = max(0, int(_pending_spawners_per_wave.get(wave_idx, 0)) - 1)
	_pending_spawners_per_wave[wave_idx] = pending
	# Bounty for wave_idx may now be eligible (alive could already be 0).
	# Idempotent — _maybe_pay_bounty checks both gates.
	_maybe_pay_bounty(wave_idx)
	_on_spawner_finished()


# Called every time a spawner exits. When the LAST spawner across all waves
# finishes, the next wave's countdown begins (NOT after kills) — this is the
# overlap mechanic, see CORE RULE 19.
func _on_spawner_finished() -> void:
	if _active_spawners > 0:
		return
	_on_spawning_complete()


func _on_spawning_complete() -> void:
	if not _wave_active:
		return
	_wave_active = false
	var completed_wave_idx: int = _wave_index
	EventBus.wave_spawning_complete.emit(completed_wave_idx + 1)
	print("[WaveManager] wave %d spawning done (alive=%d)" % [
		completed_wave_idx + 1, _alive_per_wave.get(completed_wave_idx, 0)
	])
	# Pay bounty immediately if this wave's enemies are all already gone (or
	# if no enemies spawned at all, e.g. every emitter disabled via the
	# debug count-override sliders). Without this, a wave with all spawns
	# count_mult=0 would leave _pending_bounties stuck forever — soft-locking
	# all_waves_completed. _maybe_pay_bounty is idempotent so this is safe
	# in the normal case where enemies are still alive.
	_maybe_pay_bounty(completed_wave_idx)
	if _running:
		_begin_next_wave()


# Called when an enemy of `wave_index` dies/leaks. If that wave's alive
# count drops to zero AND its bounty hasn't been paid yet, pay it now.
# Decoupled from spawning so a wave's bounty pays as soon as its last
# enemy dies, even if the next wave is already running (overlap).
func _maybe_pay_bounty(wave_index: int) -> void:
	if _alive_per_wave.get(wave_index, 0) > 0:
		return
	# Wave's own spawners must all have finished before bounty pays.
	# Without this, a wave with a late-spawning emitter (e.g. boss with
	# start_delay) pays bounty as soon as the early enemies die, leaving the
	# boss as a "ghost" — visible in W10's console log on Riverford.
	if int(_pending_spawners_per_wave.get(wave_index, 0)) > 0:
		return
	if not _pending_bounties.has(wave_index):
		return # already paid or never queued
	var bounty: int = int(_pending_bounties[wave_index])
	if bounty > 0:
		RunState.add_gold(bounty)
	EventBus.wave_completed.emit(wave_index + 1)
	print("[WaveManager] wave %d cleared (+%dg)" % [wave_index + 1, bounty])
	_pending_bounties.erase(wave_index)
	_alive_per_wave.erase(wave_index)
	_pending_spawners_per_wave.erase(wave_index)
	_maybe_all_waves_complete()


# All-waves-complete fires only after every authored wave has both
# (a) finished spawning AND (b) been fully cleared. Otherwise the level
# would end while wave 5's stragglers are still walking.
func _maybe_all_waves_complete() -> void:
	if not _all_waves_launched:
		return
	if _pending_bounties.size() > 0:
		# Diagnostic — when victory is blocked, surface WHICH wave is stuck
		# and what its alive count is, so the next regression is one print
		# away instead of a multi-session debugging session.
		var nonzero: PackedStringArray = []
		for k in _alive_per_wave.keys():
			var n: int = int(_alive_per_wave[k])
			if n > 0:
				nonzero.append("W%d=%d" % [int(k) + 1, n])
		var pending_keys: PackedStringArray = []
		for k in _pending_bounties.keys():
			pending_keys.append("W%d" % (int(k) + 1))
		print("[WaveManager/Stuck] all_waves_launched=true but pending bounties: %s; alive: %s" % [
			", ".join(pending_keys),
			", ".join(nonzero) if not nonzero.is_empty() else "(none)",
		])
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


# Path_ids of the wave that call_early_wave() would launch RIGHT NOW.
# Pre-W1 → wave 1's authored paths. During wave N's spawn → wave N+1.
# Empty when no callable next wave exists.
#
# Filters out emitters whose EFFECTIVE count is 0 (authored count × debug
# count_mult). A path_id only surfaces if at least one emitter on that path
# will actually spawn enemies — otherwise the badge would point at an
# entrance no enemies use.
func get_next_wave_path_ids() -> Array:
	var wave: Resource = null
	var wave_idx: int = -1
	if _pre_w1_pending:
		wave = _pre_w1_pending_wave
		wave_idx = 0
	else:
		if _all_waves_launched or _wave_list == null:
			return []
		var nxt: int = _wave_index + 1
		if nxt < 0 or nxt >= _wave_list.waves.size():
			return []
		wave = _wave_list.waves[nxt]
		wave_idx = nxt
	if wave == null:
		return []
	var lvl_id: String = RunState.current_level_id
	var ids: Array = []
	for si in range(wave.spawns.size()):
		var spawn: Resource = wave.spawns[si]
		if spawn == null:
			continue
		var mult: float = BalanceOverrides.get_wave_count_mult(lvl_id, wave_idx, si)
		var effective_count: int = max(0, int(round(float(spawn.count) * mult)))
		if effective_count <= 0:
			continue
		var pid: String = String(spawn.path_id)
		if not ids.has(pid):
			ids.append(pid)
	return ids


func _on_enemy_spawned(enemy: Node, _path_id: String) -> void:
	# Per-wave count uses the wave_index meta tagged at spawn time. Default
	# to current _wave_index for ad-hoc spawns (Test Range, debug commands).
	var wi: int = enemy.get_meta("wave_index", _wave_index) if enemy != null else _wave_index
	_alive_per_wave[wi] = int(_alive_per_wave.get(wi, 0)) + 1


func _on_enemy_died(enemy: Node, _gold: int) -> void:
	_count_enemy_exit(enemy)


func _on_enemy_reached_end(enemy: Node, _lives: int) -> void:
	_count_enemy_exit(enemy)


# Defensive backstop: fires whenever an enemy leaves the scene tree, even
# when neither enemy_died nor enemy_reached_end was emitted. Without this,
# a stray queue_free() (future spell effect, debug nuke, scene reload race)
# would leave _alive_per_wave above zero and the wave would never clear,
# soft-locking the level. _count_enemy_exit is idempotent via meta so the
# normal die/leak path still pays bounty exactly once.
func _on_enemy_tree_exiting(enemy: Node) -> void:
	_count_enemy_exit(enemy)


func _count_enemy_exit(enemy: Node) -> void:
	if enemy == null:
		return
	if enemy.get_meta("_wave_counted_exit", false):
		return
	enemy.set_meta("_wave_counted_exit", true)
	var wi: int = enemy.get_meta("wave_index", -1)
	if wi < 0:
		return # untracked spawn (Test Range, etc.) — no bounty owed
	_alive_per_wave[wi] = maxi(0, int(_alive_per_wave.get(wi, 0)) - 1)
	_maybe_pay_bounty(wi)


func _on_game_over() -> void:
	_running = false
	_wave_active = false
	# Defeat → no more bounties pay. Clear so straggler-deaths don't trigger
	# all_waves_completed after game_over.
	_pending_bounties.clear()
	_pending_spawners_per_wave.clear()
	_alive_per_wave.clear()


func stop() -> void:
	# Called before scene reload / restart. In-flight `await` spawner coroutines
	# check _running on resume and bail, so they exit cleanly without spawning.
	_running = false
	_wave_active = false
	_endless = false
	_wave_list = null
	_level = null
	_wave_index = -1
	_active_spawners = 0
	_alive_per_wave.clear()
	_pending_bounties.clear()
	_pending_spawners_per_wave.clear()
	_all_waves_launched = false
	# Spawn-window tracking — reset so a fresh start() doesn't read stale
	# state from a previous run (would yield wrong remaining time until the
	# next wave actually launches).
	_current_spawn_window_sec = 0.0
	_spawn_elapsed_game = 0.0
	# Pre-W1 grace state — clear so a new level start doesn't think it's
	# already past the parked state from a prior run.
	_pre_w1_pending = false
	_pre_w1_pending_wave = null
	_pre_w1_pending_path_ids = []


# Phase 32: procedural wave generation for endless mode.
# Difficulty ramps: more enemies, faster spawns, more paths, mixed types.
func _generate_endless_wave(wave_num: int) -> Resource:
	var wave_data := preload("res://waves/WaveData.gd").new()
	var spawn_script := preload("res://waves/WaveSpawn.gd")
	wave_data.countdown = maxf(1.5, 3.0 - wave_num * 0.1)
	wave_data.bounty = 10 + wave_num * 5
	# 8% additive HP per wave — reapplied every wave so the value stays
	# fresh as _wave_index advances. See BALANCE.md endless multiplier.
	_endless_hp_scale = 1.0 + 0.08 * float(wave_num)

	# Base enemy count scales with wave number.
	var base_count: int = 4 + wave_num * 2
	# Discover the level's actual path_ids — works on L1 (3 paths), L2 (1 path),
	# and any future level with arbitrary topology. Fallback to ["left"] only
	# if the level doesn't implement get_path_ids() (legacy / partial).
	var level_path_ids: Array[String] = _ENDLESS_PATH_FALLBACK
	if _level != null and _level.has_method("get_path_ids"):
		var queried: Array[String] = _level.get_path_ids()
		if queried.size() > 0:
			level_path_ids = queried
	# Pick paths — early waves use 1-2 paths, later use all available.
	@warning_ignore("integer_division")
	var num_paths: int = mini(1 + wave_num / 3, level_path_ids.size())
	var active_paths: Array[String] = []
	for i in num_paths:
		active_paths.append(level_path_ids[i % level_path_ids.size()])

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
	enemy.set_meta("_wave_counted_exit", false)
	# Endless-mode HP scaling — set BEFORE add_child so base_enemy._ready()
	# initializes current_health from the scaled max. Skip in campaign /
	# heroic / iron / Test Range — those keep authored values (scale = 1.0).
	if _endless and "_hp_scale" in enemy:
		enemy._hp_scale = _endless_hp_scale
	follow.add_child(enemy)
	if enemy.has_method("setup"):
		enemy.setup(follow, path_id)
	# Backstop against soft-lock: any path that frees the enemy without
	# emitting enemy_died / enemy_reached_end still hits _on_enemy_tree_exiting.
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	EventBus.enemy_spawned.emit(enemy, path_id)
	return enemy
