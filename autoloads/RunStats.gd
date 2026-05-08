extends Node

# Per-run telemetry. Listens to EventBus signals during a level, finalizes
# on victory/defeat, appends a JSON record to user://run_stats.json (capped
# at MAX_HISTORY entries). Useful for two things:
#   1) Authoring guardrail — after 10 playtests, see which towers carry,
#      which sit unbuilt, where lives leak.
#   2) Future replays / leaderboards — record format intentionally generic.
#
# Privacy: writes only to user:// (per-machine, not synced). No network.
# Future opt-in upload would gate via a Settings toggle.

const STATS_PATH: String = "user://run_stats.json"
const MAX_HISTORY: int = 50

var _current: Dictionary = {}
var _start_time_msec: int = 0


func _ready() -> void:
	print("[RunStats] loaded — telemetry → %s" % STATS_PATH)
	# Start the run as soon as ANY level activity begins — pre-wave tower
	# placements would otherwise be dropped (they happen before wave 1).
	EventBus.hero_spawned.connect(_on_any_level_start)
	EventBus.wave_countdown_started.connect(_on_wave_countdown_started)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.tower_upgraded.connect(_on_tower_upgraded)
	EventBus.tower_branch_chosen.connect(_on_tower_branch_chosen)
	EventBus.tower_sold.connect(_on_tower_sold)
	EventBus.hero_died.connect(_on_hero_died)
	EventBus.early_wave_triggered.connect(_on_early_wave_triggered)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.game_over.connect(_on_game_over)


func _ensure_run() -> void:
	# Idempotent — first signal of any kind in a level kicks off the run.
	# Test Range sets current_mode = "test_range" so we skip there.
	if not _current.is_empty():
		return
	if RunState.current_mode == "test_range":
		return
	_start_new_run()


func _on_any_level_start(_hero) -> void:
	_ensure_run()


func _on_wave_countdown_started(_duration: float) -> void:
	_ensure_run()


func _start_new_run() -> void:
	_start_time_msec = Time.get_ticks_msec()
	# schema_version=2 added the loadout / overrides_snapshot fields below.
	# Records without it (loaded from older run_stats.json) implicitly = 1 and
	# the new fields read as absent. Bump on any future shape change.
	const SCHEMA_VERSION: int = 2
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	_current = {
		"schema_version": SCHEMA_VERSION,
		"run_id": _make_id(),
		"timestamp": Time.get_datetime_string_from_system(),
		"level_id": RunState.current_level_id,
		"mode": RunState.current_mode,
		"hero_id": LoadoutState.selected_hero_id,
		"starting_gold": RunState.gold,
		"starting_lives": RunState.lives,
		"loadout": {
			"hero_id": LoadoutState.selected_hero_id,
			"tower_ids": LoadoutState.selected_tower_ids.duplicate(),
			"equipped_skills": LoadoutState.get_equipped_skills(LoadoutState.selected_hero_id).duplicate(),
			"effective_ppt": LoadoutState.get_effective_ppt(),
		},
		"overrides_active": BO.any_active(),
		"overrides_snapshot": BO.get_snapshot(),
		"lives_lost_per_wave": [],
		"_pending_wave_leak": 0,
		"tower_placements": [],
		"tower_upgrades": 0,
		"tower_sells": 0,
		"hero_deaths": 0,
		"gold_timeline": [],   # one entry per wave: start/end gold + duration
		"early_call_count": 0,
		"early_call_gold_earned": 0,
		"outcome": "in_progress",
	}


func _on_wave_started(wave_num: int, _path_ids) -> void:
	# Run is already started by hero_spawned / wave_countdown_started — this
	# just resets the per-wave leak counter and snapshots wave-start gold.
	_ensure_run()
	if _current.is_empty():
		return
	_current["_pending_wave_leak"] = 0
	# Gold timeline: snapshot start_gold + start_ms. Patched on wave_completed
	# so per-wave spend = (start_gold + earned) - end_gold can be derived later.
	var timeline: Array = _current["gold_timeline"]
	timeline.append({
		"wave": wave_num,
		"start_gold": RunState.gold,
		"start_ms": Time.get_ticks_msec() - _start_time_msec,
	})
	_current["gold_timeline"] = timeline


func _on_wave_completed(wave_num: int) -> void:
	if _current.is_empty():
		return
	var arr: Array = _current["lives_lost_per_wave"]
	var leak: int = int(_current.get("_pending_wave_leak", 0))
	arr.append(leak)
	_current["lives_lost_per_wave"] = arr
	# Patch the matching gold_timeline entry with end-of-wave state.
	var timeline: Array = _current["gold_timeline"]
	for entry in timeline:
		if int(entry.get("wave", -1)) == wave_num:
			entry["end_gold"] = RunState.gold
			entry["end_ms"] = Time.get_ticks_msec() - _start_time_msec
			entry["leak"] = leak
			break


func _on_enemy_reached_end(_enemy, lives_lost: int) -> void:
	if _current.is_empty():
		return
	_current["_pending_wave_leak"] = int(_current.get("_pending_wave_leak", 0)) + lives_lost


func _on_tower_built(tower, spot_id) -> void:
	if _current.is_empty() or tower == null or tower.data == null:
		return
	var arr: Array = _current["tower_placements"]
	# Stamp the live tower's instance_id on the placement so subsequent
	# upgrade / branch events update THIS entry, not every placement that
	# happens to share the tower_id. Two archers no longer move in lockstep.
	arr.append({
		"id": String(tower.data.tower_id),
		"spot_id": String(spot_id),
		"instance_id": tower.get_instance_id(),
		"max_level": 1,
		"branch": -1,
	})
	_current["tower_placements"] = arr


func _on_tower_upgraded(tower, new_level: int) -> void:
	if _current.is_empty() or tower == null or tower.data == null:
		return
	_current["tower_upgrades"] = int(_current.get("tower_upgrades", 0)) + 1
	# Match by instance_id so duplicate-tower-id placements update independently.
	# instance_id-on-Node is monotonic in Godot 4.x, no recycling risk.
	var iid: int = tower.get_instance_id()
	var arr: Array = _current["tower_placements"]
	for entry in arr:
		if int(entry.get("instance_id", -1)) == iid:
			entry["max_level"] = max(int(entry.get("max_level", 1)), new_level)
			return
	# Fallback for a placement record from before instance_id was tracked
	# (e.g. an in-progress run that loaded a save predating this change).
	# Falls back to the old by-id match — last-write-wins.
	for entry in arr:
		if String(entry["id"]) == String(tower.data.tower_id):
			entry["max_level"] = max(int(entry.get("max_level", 1)), new_level)


func _on_tower_branch_chosen(tower, branch_idx: int) -> void:
	if _current.is_empty() or tower == null or tower.data == null:
		return
	var iid: int = tower.get_instance_id()
	var arr: Array = _current["tower_placements"]
	for entry in arr:
		if int(entry.get("instance_id", -1)) == iid:
			entry["branch"] = branch_idx
			return
	# Same legacy fallback as _on_tower_upgraded.
	for entry in arr:
		if String(entry["id"]) == String(tower.data.tower_id):
			entry["branch"] = branch_idx


func _on_tower_sold(_tower, _refund: int) -> void:
	if _current.is_empty():
		return
	_current["tower_sells"] = int(_current.get("tower_sells", 0)) + 1


func _on_hero_died() -> void:
	if _current.is_empty():
		return
	_current["hero_deaths"] = int(_current.get("hero_deaths", 0)) + 1


# Early-call attribution. KR-overlap mechanic (CORE RULE 19) trades bonus
# gold for concurrent-wave pressure. Tracking the bonus separately lets us
# answer "are players using the mechanic?" — without this, kill gold and
# early-call gold are indistinguishable in the post-run economy roll-up.
func _on_early_wave_triggered(bonus_gold: int) -> void:
	if _current.is_empty():
		return
	_current["early_call_count"] = int(_current.get("early_call_count", 0)) + 1
	_current["early_call_gold_earned"] = int(_current.get("early_call_gold_earned", 0)) + maxi(0, bonus_gold)


func _on_level_completed(_level_id: String, stars_earned: int, _mode: String) -> void:
	_finalize("victory", stars_earned)


func _on_game_over() -> void:
	_finalize("defeat", 0)


func _finalize(outcome: String, stars: int) -> void:
	if _current.is_empty():
		return
	_current["outcome"] = outcome
	_current["stars_earned"] = stars
	_current["lives_remaining"] = RunState.lives
	_current["duration_s"] = (Time.get_ticks_msec() - _start_time_msec) / 1000.0
	_current["final_gold"] = RunState.gold
	# Damage attribution snapshot — sourced from RunState.round_damage_*
	# which is populated by BaseEnemy.take_damage routing. See CLAUDE.md
	# "Damage attribution". Tower entries keyed by run-scoped damage_key so
	# sold-and-rebuilt towers don't double-merge.
	var towers_total: float = 0.0
	var per_tower: Array = []
	for key in RunState.round_damage_towers.keys():
		var ent: Dictionary = RunState.round_damage_towers[key]
		var tot: float = float(ent.get("total", 0.0))
		towers_total += tot
		per_tower.append({
			"name": String(ent.get("name", "")),
			"tower_id": String(ent.get("tower_id", "")),
			"level": int(ent.get("level", 1)),
			"branch_idx": int(ent.get("branch_idx", -1)),
			"damage": tot,
		})
	per_tower.sort_custom(func(a, b): return float(a.damage) > float(b.damage))
	_current["damage_by_source"] = {
		"hero": RunState.round_damage_hero,
		"soldiers": RunState.round_damage_soldiers,
		"towers_total": towers_total,
	}
	_current["damage_by_tower"] = per_tower
	# Hero progression at end of run — XP earned this run + level achieved.
	_current["hero_level_end"] = MetaProgression.get_hero_level(LoadoutState.selected_hero_id)
	_current["hero_xp_end"] = MetaProgression.get_hero_xp(LoadoutState.selected_hero_id)
	_current.erase("_pending_wave_leak")
	_append_to_history(_current)
	_current = {}


func _append_to_history(record: Dictionary) -> void:
	var history: Array = _load_history()
	history.append(record)
	while history.size() > MAX_HISTORY:
		history.remove_at(0)
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[RunStats] failed to open %s for write" % STATS_PATH)
		return
	f.store_string(JSON.stringify(history, "  "))
	f.close()


func _load_history() -> Array:
	if not FileAccess.file_exists(STATS_PATH):
		return []
	var f := FileAccess.open(STATS_PATH, FileAccess.READ)
	if f == null:
		return []
	var txt: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Array:
		return parsed
	return []


func _make_id() -> String:
	var t: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%04x" % [
		t.year, t.month, t.day, t.hour, t.minute, t.second, randi() & 0xFFFF
	]


# Public read API — let UI surface (post-run summary, codex stats screen) display history.
func get_history() -> Array:
	return _load_history()
