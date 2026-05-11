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
var _latest_wave_num: int = 0
var _last_gold: int = 0
var _pre_wave_gold_spent: int = 0


func _ready() -> void:
	print("[RunStats] loaded — telemetry → %s" % STATS_PATH)
	# Start the run as soon as ANY level activity begins — pre-wave tower
	# placements would otherwise be dropped (they happen before wave 1).
	EventBus.hero_spawned.connect(_on_any_level_start)
	# Overlap-only redesign: there is no inter-wave countdown anymore.
	# Hook into wave_started — fires when a wave's spawners launch.
	# _ensure_run is idempotent so re-firing every wave is harmless.
	EventBus.wave_started.connect(_on_wave_started_for_run)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.tower_upgraded.connect(_on_tower_upgraded)
	EventBus.tower_branch_chosen.connect(_on_tower_branch_chosen)
	EventBus.tower_sold.connect(_on_tower_sold)
	EventBus.hero_died.connect(_on_hero_died)
	EventBus.early_wave_triggered.connect(_on_early_wave_triggered)
	EventBus.hero_skill_used.connect(_on_hero_skill_used)
	EventBus.soldier_spawned.connect(_on_soldier_spawned)
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


func _on_wave_started_for_run(_wave_number: int, _path_ids: Array) -> void:
	_ensure_run()


func _start_new_run() -> void:
	_start_time_msec = Time.get_ticks_msec()
	# schema_version=2 added the loadout / overrides_snapshot fields below.
	# schema_version=3 fixes lives_lost_per_wave attribution for overlapped
	# waves by keying leaks to each enemy's spawned wave_index.
	# schema_version=4 adds per-wave balance telemetry + naked_baseline tag.
	# schema_version=5 adds boss_events, tower_events timeline, skill_casts,
	# peak_concurrent_enemies_global, level_hardness, level_target_ppt.
	# schema_version=6 adds per-wave enemies_by_id, damage_by_source,
	# damage_by_tower_instance; run-level tower_runtime_stats, defeat_reason,
	# final_wave_reached, game_speed.
	# schema_version=7 adds paths_in_range stamping on tower_events/runtime,
	# run-level spots_total + spots_unbuilt. Also: _is_naked_baseline_run now
	# rejects runs with BalanceOverrides active (spec fix).
	# Records without it (loaded from older run_stats.json) implicitly = 1 and
	# the new fields read as absent. Bump on any future shape change.
	const SCHEMA_VERSION: int = 7
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	_latest_wave_num = 0
	_last_gold = RunState.gold
	_pre_wave_gold_spent = 0
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
		"naked_baseline": _is_naked_baseline_run(),
		"lives_lost_per_wave": [],
		"waves": [],
		"_pending_wave_leak_by_wave": {},
		"tower_placements": [],
		"tower_upgrades": 0,
		"tower_sells": 0,
		"hero_deaths": 0,
		"gold_timeline": [],   # one entry per wave: start/end gold + duration
		"early_call_count": 0,
		"early_call_gold_earned": 0,
		"outcome": "in_progress",
		"peak_concurrent_enemies_global": 0,
		"_active_enemies_global": 0,
		"boss_events": [],
		"_boss_runtime": {},
		"tower_events": [],
		"skill_casts": {},
		"level_hardness": -1.0,
		"level_target_ppt": -1,
		"_tower_runtime": {},
		"_soldier_to_spawner": {},
		"tower_runtime_stats": [],
		"defeat_reason": "",
		"final_wave_reached": 0,
		"game_speed": 1.0,
	}
	_stamp_level_hardness()


func _on_wave_started(wave_num: int, _path_ids) -> void:
	# Run is already started by hero_spawned / wave_started — this
	# just opens the per-wave leak bucket and snapshots wave-start gold.
	_ensure_run()
	if _current.is_empty():
		return
	_latest_wave_num = wave_num
	var leaks_by_wave: Dictionary = _current.get("_pending_wave_leak_by_wave", {})
	if not leaks_by_wave.has(wave_num):
		leaks_by_wave[wave_num] = 0
	_current["_pending_wave_leak_by_wave"] = leaks_by_wave
	var wave_entry: Dictionary = _wave_entry(wave_num)
	wave_entry["start_ms"] = Time.get_ticks_msec() - _start_time_msec
	wave_entry["gold_start"] = RunState.gold
	if wave_num == 1 and _pre_wave_gold_spent > 0:
		wave_entry["gold_spent"] = int(wave_entry.get("gold_spent", 0)) + _pre_wave_gold_spent
		_pre_wave_gold_spent = 0
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
	var leaks_by_wave: Dictionary = _current.get("_pending_wave_leak_by_wave", {})
	var leak: int = int(leaks_by_wave.get(wave_num, 0))
	_set_wave_leak(arr, wave_num, leak)
	_current["lives_lost_per_wave"] = arr
	var wave_entry: Dictionary = _wave_entry(wave_num)
	wave_entry["lives_lost"] = leak
	wave_entry["gold_on_clear"] = RunState.gold
	wave_entry["clear_time_s"] = _clear_time_s(wave_entry)
	leaks_by_wave.erase(wave_num)
	_current["_pending_wave_leak_by_wave"] = leaks_by_wave
	# Patch the matching gold_timeline entry with end-of-wave state.
	var timeline: Array = _current["gold_timeline"]
	for entry in timeline:
		if int(entry.get("wave", -1)) == wave_num:
			entry["end_gold"] = RunState.gold
			entry["end_ms"] = Time.get_ticks_msec() - _start_time_msec
			entry["leak"] = leak
			break


func _on_enemy_reached_end(enemy, lives_lost: int) -> void:
	if _current.is_empty():
		return
	var wave_num: int = _wave_num_for_enemy(enemy)
	var leaks_by_wave: Dictionary = _current.get("_pending_wave_leak_by_wave", {})
	leaks_by_wave[wave_num] = int(leaks_by_wave.get(wave_num, 0)) + lives_lost
	_current["_pending_wave_leak_by_wave"] = leaks_by_wave
	var wave_entry: Dictionary = _wave_entry(wave_num)
	wave_entry["enemies_leaked"] = int(wave_entry.get("enemies_leaked", 0)) + 1
	var leaks: Array = wave_entry.get("leaks", [])
	leaks.append({
		"wave": wave_num,
		"t_ms": Time.get_ticks_msec() - _start_time_msec,
		"enemy_id": _enemy_id(enemy),
		"path_id": _path_id_for_enemy(enemy),
		"distance_along_path_pct": _path_progress_pct(enemy),
		"lives_lost": lives_lost,
	})
	wave_entry["leaks"] = leaks
	_bump_enemies_by_id(wave_entry, _enemy_id(enemy), "leaked")
	if _is_boss(enemy):
		_close_boss_event(enemy, "leaked")
	_record_enemy_exit(enemy)


func _on_enemy_spawned(enemy, path_id: String) -> void:
	if _current.is_empty():
		return
	if enemy != null:
		enemy.set_meta("_runstats_path_id", path_id)
	var wave_num: int = _wave_num_for_enemy(enemy)
	var wave_entry: Dictionary = _wave_entry(wave_num)
	var now_ms: int = Time.get_ticks_msec() - _start_time_msec
	if int(wave_entry.get("first_spawn_ms", -1)) < 0:
		wave_entry["first_spawn_ms"] = now_ms
	wave_entry["enemies_spawned"] = int(wave_entry.get("enemies_spawned", 0)) + 1
	_bump_enemies_by_id(wave_entry, _enemy_id(enemy), "spawned")
	# Per-wave concurrent counter — enemies bucketed to the wave they spawned in.
	# Cross-wave overlap pressure (CORE RULE 19) is captured by
	# peak_concurrent_enemies_global below.
	var active: int = int(wave_entry.get("_active_enemies", 0)) + 1
	wave_entry["_active_enemies"] = active
	wave_entry["peak_concurrent_enemies"] = maxi(int(wave_entry.get("peak_concurrent_enemies", 0)), active)
	# Global concurrent counter — actual on-screen pressure across all waves.
	var active_global: int = int(_current.get("_active_enemies_global", 0)) + 1
	_current["_active_enemies_global"] = active_global
	_current["peak_concurrent_enemies_global"] = maxi(int(_current.get("peak_concurrent_enemies_global", 0)), active_global)
	# Boss tracking — record spawn so we can finalize on death/leak.
	if _is_boss(enemy):
		_open_boss_event(enemy, wave_num, path_id, now_ms)


func _on_enemy_died(enemy, _gold_value: int) -> void:
	if _current.is_empty():
		return
	var wave_entry: Dictionary = _wave_entry(_wave_num_for_enemy(enemy))
	_bump_enemies_by_id(wave_entry, _enemy_id(enemy), "killed")
	if _is_boss(enemy):
		_close_boss_event(enemy, "killed")
	_record_enemy_exit(enemy)


func _on_hit_landed(target, _source, amount: float, _dmg_type: int) -> void:
	if _current.is_empty() or target == null or amount <= 0.0:
		return
	if not target.has_meta("wave_index"):
		return
	var capped: float = _capped_hit_amount(target, amount)
	var wave_entry: Dictionary = _wave_entry(_wave_num_for_enemy(target))
	wave_entry["damage_total"] = float(wave_entry.get("damage_total", 0.0)) + capped
	var cat: String = _source_category(_source)
	var dbs: Dictionary = wave_entry.get("damage_by_source", {})
	dbs[cat] = float(dbs.get(cat, 0.0)) + capped
	wave_entry["damage_by_source"] = dbs
	if cat == "towers" and _source != null:
		var iid_key: String = str(_source.get_instance_id())
		var dbi: Dictionary = wave_entry.get("damage_by_tower_instance", {})
		dbi[iid_key] = float(dbi.get(iid_key, 0.0)) + capped
		wave_entry["damage_by_tower_instance"] = dbi
		_record_tower_hit(_source, capped)
	elif cat == "soldiers" and _source != null:
		# Attribute soldier damage back to its spawning barracks's runtime entry
		# so barracks don't read as zero-damage "wasted on placement." Wave-level
		# damage_by_source.soldiers stays intact; per-tower-instance fields
		# (damage_by_tower_instance) are NOT touched — those mean "tower fired
		# directly." See balance_scout.md telemetry workflow.
		_record_barracks_hit_via_soldier(_source, capped)
	if _is_boss(target):
		_accumulate_boss_damage(target, _source, capped)


func _on_gold_changed(new_amount: int) -> void:
	if _current.is_empty():
		_last_gold = new_amount
		return
	var delta: int = new_amount - _last_gold
	_last_gold = new_amount
	if delta >= 0:
		return
	var spent: int = -delta
	if _latest_wave_num <= 0:
		_pre_wave_gold_spent += spent
		return
	var wave_entry: Dictionary = _wave_entry(_latest_wave_num)
	wave_entry["gold_spent"] = int(wave_entry.get("gold_spent", 0)) + spent


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
	var paths_covered: Array = _paths_in_range_of(tower)
	_push_tower_event("built", tower, {"spot_id": String(spot_id), "level": 1, "paths_in_range": paths_covered})
	_open_tower_runtime(tower, String(spot_id), paths_covered)


func _on_tower_upgraded(tower, new_level: int) -> void:
	if _current.is_empty() or tower == null or tower.data == null:
		return
	_current["tower_upgrades"] = int(_current.get("tower_upgrades", 0)) + 1
	_push_tower_event("upgraded", tower, {"level": new_level})
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
	_push_tower_event("branch", tower, {"branch": branch_idx})
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


func _on_tower_sold(tower, refund: int) -> void:
	if _current.is_empty():
		return
	_current["tower_sells"] = int(_current.get("tower_sells", 0)) + 1
	_push_tower_event("sold", tower, {"refund": refund})
	_close_tower_runtime(tower)


func _on_hero_skill_used(skill_name: String) -> void:
	if _current.is_empty():
		return
	var casts: Dictionary = _current.get("skill_casts", {})
	var key: String = String(skill_name)
	casts[key] = int(casts.get(key, 0)) + 1
	_current["skill_casts"] = casts


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


func _compute_defeat_reason(outcome: String) -> String:
	if outcome == "victory":
		return "victory"
	if int(RunState.lives) <= 0:
		return "lives_zero"
	return "unknown"


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
	_current["defeat_reason"] = _compute_defeat_reason(outcome)
	_current["final_wave_reached"] = _latest_wave_num
	_current["game_speed"] = float(Engine.time_scale)
	_finalize_tower_runtime_stats()
	_finalize_spot_coverage()
	_current.erase("_pending_wave_leak_by_wave")
	_current.erase("_boss_runtime")
	_current.erase("_active_enemies_global")
	_current.erase("_tower_runtime")
	_current.erase("_soldier_to_spawner")
	_finalize_wave_entries()
	_append_to_history(_current)
	_current = {}
	_latest_wave_num = 0


func _set_wave_leak(arr: Array, wave_num: int, leak: int) -> void:
	var idx: int = maxi(0, wave_num - 1)
	while arr.size() <= idx:
		arr.append(0)
	arr[idx] = leak


func _wave_num_for_enemy(enemy) -> int:
	if enemy != null and enemy.has_meta("wave_index"):
		var idx: int = int(enemy.get_meta("wave_index"))
		if idx >= 0:
			return idx + 1
	var timeline: Array = _current.get("gold_timeline", [])
	if not timeline.is_empty():
		return int(timeline[timeline.size() - 1].get("wave", 1))
	return 1


func _wave_entry(wave_num: int) -> Dictionary:
	var waves: Array = _current.get("waves", [])
	for entry in waves:
		if int(entry.get("wave", -1)) == wave_num:
			return entry
	var entry: Dictionary = {
		"wave": wave_num,
		"start_ms": -1,
		"first_spawn_ms": -1,
		"last_exit_ms": -1,
		"clear_time_s": -1.0,
		"enemies_spawned": 0,
		"enemies_leaked": 0,
		"lives_lost": 0,
		"damage_total": 0.0,
		"gold_start": RunState.gold,
		"gold_on_clear": -1,
		"gold_spent": 0,
		"peak_concurrent_enemies": 0,
		"leaks": [],
		"_active_enemies": 0,
		"enemies_by_id": {},
		"damage_by_source": {"hero": 0.0, "soldiers": 0.0, "towers": 0.0, "other": 0.0},
		"damage_by_tower_instance": {},
	}
	waves.append(entry)
	_current["waves"] = waves
	return entry


func _record_enemy_exit(enemy) -> void:
	if enemy == null:
		return
	if enemy.get_meta("_runstats_counted_exit", false):
		return
	enemy.set_meta("_runstats_counted_exit", true)
	var wave_entry: Dictionary = _wave_entry(_wave_num_for_enemy(enemy))
	wave_entry["last_exit_ms"] = Time.get_ticks_msec() - _start_time_msec
	wave_entry["_active_enemies"] = maxi(0, int(wave_entry.get("_active_enemies", 0)) - 1)
	_current["_active_enemies_global"] = maxi(0, int(_current.get("_active_enemies_global", 0)) - 1)


func _clear_time_s(wave_entry: Dictionary) -> float:
	var first_ms: int = int(wave_entry.get("first_spawn_ms", -1))
	var last_ms: int = int(wave_entry.get("last_exit_ms", -1))
	if first_ms < 0 or last_ms < first_ms:
		return -1.0
	return float(last_ms - first_ms) / 1000.0


func _finalize_wave_entries() -> void:
	var waves: Array = _current.get("waves", [])
	waves.sort_custom(func(a, b): return int(a.get("wave", 0)) < int(b.get("wave", 0)))
	# Backfill lives_lost from leaks[] for any wave whose `wave_completed` signal
	# never fired (e.g. game ended mid-wave). `_on_wave_completed` is the only
	# writer of wave_entry.lives_lost, and `lives_lost_per_wave` is only padded
	# there too — so a mid-wave defeat used to leave the wave's loss count at
	# zero despite leaks[] holding the truth.
	var lives_arr: Array = _current.get("lives_lost_per_wave", [])
	for entry in waves:
		entry["clear_time_s"] = _clear_time_s(entry)
		entry.erase("_active_enemies")
		if int(entry.get("lives_lost", 0)) == 0:
			var sum_leaks: int = 0
			for leak_evt in entry.get("leaks", []):
				sum_leaks += int(leak_evt.get("lives_lost", 0))
			if sum_leaks > 0:
				entry["lives_lost"] = sum_leaks
		_set_wave_leak(lives_arr, int(entry.get("wave", 0)), int(entry.get("lives_lost", 0)))
	_current["waves"] = waves
	_current["lives_lost_per_wave"] = lives_arr


func _enemy_id(enemy) -> String:
	if enemy != null and "data" in enemy and enemy.data != null and "enemy_id" in enemy.data:
		return String(enemy.data.enemy_id)
	return ""


func _path_id_for_enemy(enemy) -> String:
	if enemy == null:
		return ""
	if enemy.has_meta("_runstats_path_id"):
		return String(enemy.get_meta("_runstats_path_id"))
	if "_path_id" in enemy:
		return String(enemy._path_id)
	return ""


func _path_progress_pct(enemy) -> float:
	if enemy != null and "_path_follow" in enemy and is_instance_valid(enemy._path_follow):
		return clampf(float(enemy._path_follow.progress_ratio) * 100.0, 0.0, 100.0)
	return -1.0


func _capped_hit_amount(target, amount: float) -> float:
	if target != null and "current_health" in target:
		var before_hit: float = float(target.current_health + int(ceil(amount)))
		return clampf(minf(amount, before_hit), 0.0, amount)
	return amount


func _is_naked_baseline_run() -> bool:
	if RunState.current_mode != "campaign":
		return false
	# A run with BalanceOverrides active is an easy-mode playtest, not baseline.
	# Missing earlier — the four "naked_baseline: true" runs that would have
	# slipped through never materialized in practice, but the gate has to be here.
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	if BO != null and BO.has_method("any_active") and BO.any_active():
		return false
	if LoadoutState.selected_hero_id != "hero_warrior":
		return false
	# Compare as sets — drag-reordering the four default towers in the loadout
	# UI must not flip the run out of Naked Baseline classification.
	var picked: Array = LoadoutState.selected_tower_ids.duplicate()
	picked.sort()
	var expected: Array = ["tower_archer", "tower_artillery", "tower_barracks", "tower_mage"]
	if picked != expected:
		return false
	if not InventoryManager.get_all_equipped("hero_warrior").is_empty():
		return false
	if not MetaProgression.purchased_upgrades.is_empty():
		return false
	if not MetaProgression.hero_talents.get("hero_warrior", []).is_empty():
		return false
	if int(MetaProgression.get_hero_level("hero_warrior")) != 1:
		return false
	var nodes: Dictionary = MetaProgression.hero_skill_nodes.get("hero_warrior", {})
	if not nodes.is_empty():
		return false
	if LoadoutState.get_equipped_skills("hero_warrior") != _default_skill_loadout("hero_warrior"):
		return false
	return true


func _default_skill_loadout(hero_id: String) -> Array[String]:
	var unlocked: Array[String] = LoadoutState.get_unlocked_skill_ids(hero_id)
	var cap: int = LoadoutState.get_active_slot_cap(hero_id)
	var out: Array[String] = []
	for i in cap:
		out.append(unlocked[i] if i < unlocked.size() else "")
	return out


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


# ---------- schema-5 helpers ----------

func _is_boss(enemy) -> bool:
	if enemy == null:
		return false
	if not "data" in enemy or enemy.data == null:
		return false
	if not "is_boss" in enemy.data:
		return false
	return bool(enemy.data.is_boss)


func _open_boss_event(enemy, wave_num: int, path_id: String, spawn_ms: int) -> void:
	var runtime: Dictionary = _current.get("_boss_runtime", {})
	var iid: int = enemy.get_instance_id()
	runtime[iid] = {
		"wave": wave_num,
		"boss_id": _enemy_id(enemy),
		"spawn_t_ms": spawn_ms,
		"path_id": path_id,
		"damage_breakdown": {"hero": 0.0, "soldiers": 0.0, "towers": 0.0, "other": 0.0},
	}
	_current["_boss_runtime"] = runtime


func _close_boss_event(enemy, ended: String) -> void:
	var runtime: Dictionary = _current.get("_boss_runtime", {})
	var iid: int = enemy.get_instance_id()
	if not runtime.has(iid):
		return
	var entry: Dictionary = runtime[iid]
	var events: Array = _current.get("boss_events", [])
	events.append({
		"wave": entry.get("wave", -1),
		"boss_id": entry.get("boss_id", ""),
		"spawn_t_ms": entry.get("spawn_t_ms", -1),
		"end_t_ms": Time.get_ticks_msec() - _start_time_msec,
		"ended": ended,
		"path_id": entry.get("path_id", ""),
		"path_progress_pct_at_end": _path_progress_pct(enemy),
		"damage_breakdown": entry.get("damage_breakdown", {}),
	})
	_current["boss_events"] = events
	runtime.erase(iid)
	_current["_boss_runtime"] = runtime


func _accumulate_boss_damage(target, source, amount: float) -> void:
	var runtime: Dictionary = _current.get("_boss_runtime", {})
	var iid: int = target.get_instance_id()
	if not runtime.has(iid):
		return
	var entry: Dictionary = runtime[iid]
	var bd: Dictionary = entry.get("damage_breakdown", {})
	var key: String = _source_category(source)
	bd[key] = float(bd.get(key, 0.0)) + amount
	entry["damage_breakdown"] = bd
	runtime[iid] = entry
	_current["_boss_runtime"] = runtime


func _source_category(source) -> String:
	if source == null:
		return "other"
	if source is BaseTower:
		return "towers"
	if source is BaseHero:
		return "hero"
	if source is BaseSoldier:
		return "soldiers"
	return "other"


func _push_tower_event(kind: String, tower, extra: Dictionary) -> void:
	if tower == null or tower.data == null:
		return
	var ev: Dictionary = {
		"t_ms": Time.get_ticks_msec() - _start_time_msec,
		"type": kind,
		"tower_id": String(tower.data.tower_id),
		"instance_id": tower.get_instance_id(),
		"gold_at": RunState.gold,
		"wave": _latest_wave_num,
	}
	for k in extra.keys():
		ev[k] = extra[k]
	var arr: Array = _current.get("tower_events", [])
	arr.append(ev)
	_current["tower_events"] = arr


func _paths_in_range_of(tower) -> Array:
	# Sample each Path2D in the active level and return the names of those any
	# point of which falls inside the tower's preview range. Run once at build
	# time so the level digest can answer "which spots cover which path?" without
	# replaying geometry. Cheap: ~50 samples × N paths × O(1) distance.
	var out: Array = []
	if tower == null:
		return out
	var r: float = 0.0
	if tower.has_method("get_preview_range"):
		r = float(tower.get_preview_range())
	if r <= 0.0:
		return out
	var range_sq: float = r * r
	var scene = get_tree().current_scene
	if scene == null:
		return out
	var paths_node = scene.get_node_or_null("Paths")
	if paths_node == null:
		return out
	var tpos: Vector2 = tower.global_position
	for path in paths_node.get_children():
		if not path is Path2D:
			continue
		var curve: Curve2D = path.curve
		if curve == null:
			continue
		var baked_len: float = curve.get_baked_length()
		if baked_len <= 0.0:
			continue
		var step: float = max(20.0, baked_len / 50.0)
		var d: float = 0.0
		var hit: bool = false
		while d <= baked_len:
			var p: Vector2 = path.global_transform * curve.sample_baked(d)
			if tpos.distance_squared_to(p) <= range_sq:
				hit = true
				break
			d += step
		if hit:
			out.append(String(path.name))
	return out


func _finalize_spot_coverage() -> void:
	# Stamp spots_total + spots_unbuilt so the digest can show "5 of 8 spots
	# unbuilt" without cross-referencing the level scene.
	var scene = get_tree().current_scene
	if scene == null:
		return
	var spots_node = scene.get_node_or_null("TowerSpots")
	if spots_node == null:
		return
	var all_spots: Array = []
	for c in spots_node.get_children():
		all_spots.append(String(c.name))
	var built_set: Dictionary = {}
	for p in _current.get("tower_placements", []):
		built_set[String(p.get("spot_id", ""))] = true
	var unbuilt: Array = []
	for s in all_spots:
		if not built_set.has(s):
			unbuilt.append(s)
	_current["spots_total"] = all_spots.size()
	_current["spots_unbuilt"] = unbuilt


func _on_soldier_spawned(soldier, tower) -> void:
	if _current.is_empty() or soldier == null or tower == null:
		return
	var s2s: Dictionary = _current.get("_soldier_to_spawner", {})
	s2s[soldier.get_instance_id()] = tower.get_instance_id()
	_current["_soldier_to_spawner"] = s2s


func _record_barracks_hit_via_soldier(soldier, amount: float) -> void:
	if soldier == null:
		return
	var s2s: Dictionary = _current.get("_soldier_to_spawner", {})
	if not s2s.has(soldier.get_instance_id()):
		return
	var spawner_iid: int = int(s2s[soldier.get_instance_id()])
	var rt: Dictionary = _current.get("_tower_runtime", {})
	var iid_key: String = str(spawner_iid)
	if not rt.has(iid_key):
		return
	var now_ms: int = Time.get_ticks_msec() - _start_time_msec
	var entry: Dictionary = rt[iid_key]
	entry.total_hits = int(entry.get("total_hits", 0)) + 1
	if int(entry.get("first_hit_ms", -1)) < 0:
		entry.first_hit_ms = now_ms
	entry.last_hit_ms = now_ms
	entry.damage_total = float(entry.get("damage_total", 0.0)) + amount
	rt[iid_key] = entry
	_current["_tower_runtime"] = rt


func _bump_enemies_by_id(wave_entry: Dictionary, enemy_id: String, kind: String) -> void:
	if enemy_id.is_empty():
		return
	var ebi: Dictionary = wave_entry.get("enemies_by_id", {})
	var entry: Dictionary = ebi.get(enemy_id, {"spawned": 0, "killed": 0, "leaked": 0})
	entry[kind] = int(entry.get(kind, 0)) + 1
	ebi[enemy_id] = entry
	wave_entry["enemies_by_id"] = ebi


func _open_tower_runtime(tower, spot_id: String, paths_in_range: Array = []) -> void:
	if tower == null or tower.data == null:
		return
	var rt: Dictionary = _current.get("_tower_runtime", {})
	var iid_key: String = str(tower.get_instance_id())
	if rt.has(iid_key):
		return
	rt[iid_key] = {
		"tower_id": String(tower.data.tower_id),
		"spot_id": spot_id,
		"built_ms": Time.get_ticks_msec() - _start_time_msec,
		"sold_ms": -1,
		"total_hits": 0,
		"first_hit_ms": -1,
		"last_hit_ms": -1,
		"damage_total": 0.0,
		"paths_in_range": paths_in_range,
	}
	_current["_tower_runtime"] = rt


func _close_tower_runtime(tower) -> void:
	if tower == null:
		return
	var rt: Dictionary = _current.get("_tower_runtime", {})
	var iid_key: String = str(tower.get_instance_id())
	if not rt.has(iid_key):
		return
	rt[iid_key]["sold_ms"] = Time.get_ticks_msec() - _start_time_msec
	_current["_tower_runtime"] = rt


func _record_tower_hit(source, amount: float) -> void:
	if source == null:
		return
	var rt: Dictionary = _current.get("_tower_runtime", {})
	var iid_key: String = str(source.get_instance_id())
	if not rt.has(iid_key):
		# Tower built before run started (pre-W1) or signal-order edge — open lazily.
		rt[iid_key] = {
			"tower_id": "",
			"spot_id": "",
			"built_ms": Time.get_ticks_msec() - _start_time_msec,
			"sold_ms": -1,
			"total_hits": 0,
			"first_hit_ms": -1,
			"last_hit_ms": -1,
			"damage_total": 0.0,
		}
	var now_ms: int = Time.get_ticks_msec() - _start_time_msec
	var entry: Dictionary = rt[iid_key]
	entry.total_hits = int(entry.get("total_hits", 0)) + 1
	if int(entry.get("first_hit_ms", -1)) < 0:
		entry.first_hit_ms = now_ms
	entry.last_hit_ms = now_ms
	entry.damage_total = float(entry.get("damage_total", 0.0)) + amount
	rt[iid_key] = entry
	_current["_tower_runtime"] = rt


func _finalize_tower_runtime_stats() -> void:
	# Snapshot internal _tower_runtime into a public array. Active towers
	# (sold_ms < 0) get end_ms stamped as run duration.
	var end_ms: int = Time.get_ticks_msec() - _start_time_msec
	var rt: Dictionary = _current.get("_tower_runtime", {})
	var out: Array = []
	for iid_key in rt.keys():
		var entry: Dictionary = rt[iid_key]
		var sold_ms: int = int(entry.get("sold_ms", -1))
		var lifetime_ms: int = (sold_ms if sold_ms >= 0 else end_ms) - int(entry.get("built_ms", 0))
		out.append({
			"instance_id": iid_key,
			"tower_id": String(entry.get("tower_id", "")),
			"spot_id": String(entry.get("spot_id", "")),
			"built_ms": int(entry.get("built_ms", 0)),
			"sold_ms": sold_ms,
			"lifetime_s": float(maxi(0, lifetime_ms)) / 1000.0,
			"total_hits": int(entry.get("total_hits", 0)),
			"first_hit_ms": int(entry.get("first_hit_ms", -1)),
			"last_hit_ms": int(entry.get("last_hit_ms", -1)),
			"damage_total": float(entry.get("damage_total", 0.0)),
			"paths_in_range": entry.get("paths_in_range", []),
		})
	_current["tower_runtime_stats"] = out


func _stamp_level_hardness() -> void:
	var lvl_id: String = String(RunState.current_level_id)
	if lvl_id.is_empty():
		return
	var node = ContentRegistry.find_level(lvl_id)
	if node == null:
		return
	if "target_ppt" in node:
		_current["level_target_ppt"] = int(node.target_ppt)
	var wl_path: String = String(node.wave_list_path) if "wave_list_path" in node else ""
	if wl_path.is_empty():
		return
	var wl = load(wl_path)
	if wl == null:
		return
	var BalanceCalc = load("res://balance/BalanceCalculator.gd")
	if BalanceCalc == null or not BalanceCalc.has_method("score_level"):
		return
	var starting_gold: int = int(RunState.gold)
	_current["level_hardness"] = float(BalanceCalc.score_level(wl, starting_gold))
