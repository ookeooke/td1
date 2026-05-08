extends RefCounted

# NOTE: no `class_name` — callers preload this script via a const, so the
# script doesn't pollute the editor's global class registry. Pattern:
#   const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")
#   BalanceOverrides.get_hp_mult()
#
# Volatile runtime overrides for balance testing — see balance/BALANCE.md
# "Player Power Tier" + active plan. Backs the BalanceSliders debug panel.
#
# All overrides are dev-only. Every reader MUST call `BalanceOverrides.is_active()`
# first; in non-debug builds the module short-circuits and returns identity
# values (1.0 / 0.0). No production code path depends on this file.
#
# Persisted to user://debug_balance.json so designer tweaks survive editor
# restarts. Cleared by reset(). The file is plain JSON — designers can edit
# by hand if the slider UI isn't enough.
#
# Usage:
#   var hp = data.max_health * BalanceOverrides.get_hp_mult()
#   var armor = clampf(data.armor + BalanceOverrides.get_armor_add(), 0, 0.95)
# etc.

const SAVE_PATH: String = "user://debug_balance.json"

# In-memory cache. Lazy-loaded on first read; rewritten on every save.
static var _cached: Dictionary = {}
static var _loaded: bool = false


# Default values returned when no override is active. Identity for mults,
# zero for additive, -1 sentinel for "no PPT override (use loadout PPT)".
static func _defaults() -> Dictionary:
	return {
		"hp_mult": 1.0,
		"armor_add": 0.0,
		"mag_res_add": 0.0,
		"speed_mult": 1.0,
		"damage_mult": 1.0,
		"starting_gold_add": 0,
		"ppt_override": -1,   # -1 = no override; >=1 = force this PPT for audit
	}


static func is_active() -> bool:
	# Debug builds only. Exported APKs / production never see overrides.
	return OS.is_debug_build()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cached = _defaults()
	if not is_active():
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Merge: copy every persisted key back over the defaults-seeded _cached.
	# Iterate parsed.keys (NOT _cached.keys) so non-default top-level keys
	# like "tower_overrides" and "level_overrides" — added lazily by
	# set_tower_mult / set_level_value, never present in _defaults() —
	# survive across restarts. Iterating _cached.keys silently dropped them.
	for k in (parsed as Dictionary).keys():
		_cached[k] = (parsed as Dictionary)[k]


static func _save() -> void:
	if not is_active():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cached, "  "))
	f.close()


# ── Read accessors (used by runtime systems) ───────────────────────────

static func get_hp_mult() -> float:
	if not is_active():
		return 1.0
	_ensure_loaded()
	return float(_cached.get("hp_mult", 1.0))


static func get_armor_add() -> float:
	if not is_active():
		return 0.0
	_ensure_loaded()
	return float(_cached.get("armor_add", 0.0))


static func get_mag_res_add() -> float:
	if not is_active():
		return 0.0
	_ensure_loaded()
	return float(_cached.get("mag_res_add", 0.0))


static func get_speed_mult() -> float:
	if not is_active():
		return 1.0
	_ensure_loaded()
	return float(_cached.get("speed_mult", 1.0))


static func get_damage_mult() -> float:
	if not is_active():
		return 1.0
	_ensure_loaded()
	return float(_cached.get("damage_mult", 1.0))


static func get_starting_gold_add() -> int:
	if not is_active():
		return 0
	_ensure_loaded()
	return int(_cached.get("starting_gold_add", 0))


# Returns the forced PPT override or -1 if no override active. Audit screen
# reads this to display "what would drift be at PPT N?" without needing to
# re-equip the loadout.
static func get_ppt_override() -> int:
	if not is_active():
		return -1
	_ensure_loaded()
	return int(_cached.get("ppt_override", -1))


# Deep-copy snapshot of every active override. Empty dict in non-debug builds.
# Used by RunStats to stamp each run record with the slider state at run start
# so post-mortem analysis can disambiguate "Wave 5 leaked at hp_mult=0.85"
# from "Wave 5 leaked at default values".
static func get_snapshot() -> Dictionary:
	if not is_active():
		return {}
	_ensure_loaded()
	return _cached.duplicate(true)


# Convenience — true if ANY override is non-default. Checks the global
# defaults dict AND every nested sub-dict (tower / enemy / level), since
# those keys are added lazily by setters and never appear in _defaults().
# Used by RunStats to stamp records with `overrides_active`; without the
# nested check, a run with only tower/enemy slider tweaks was recorded as
# false — telemetry lying about whether the run was a clean baseline.
static func any_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	# Top-level globals (hp_mult, damage_mult, etc.).
	var d := _defaults()
	for k in d.keys():
		if _cached.get(k, d[k]) != d[k]:
			return true
	# Nested per-content sub-dicts. Reuse the existing focused checks.
	var tower_dict: Dictionary = _cached.get("tower_overrides", {})
	for tid in tower_dict.keys():
		var per_tower: Dictionary = tower_dict[tid]
		for tier_key in per_tower.keys():
			var per_tier: Dictionary = per_tower[tier_key]
			for stat in per_tier.keys():
				if absf(float(per_tier[stat]) - 1.0) > 0.0001:
					return true
	if any_enemy_active():
		return true
	if any_wave_active():
		return true
	if any_wave_countdown_active():
		return true
	if any_wave_timing_active():
		return true
	if any_wave_early_call_active():
		return true
	var level_dict: Dictionary = _cached.get("level_overrides", {})
	for lid in level_dict.keys():
		var per_level: Dictionary = level_dict[lid]
		for k2 in per_level.keys():
			# starting_gold / starting_lives use sentinel -1 = no override.
			if k2 == "starting_gold" or k2 == "starting_lives":
				if int(per_level[k2]) >= 0:
					return true
			elif k2 == "hp_mult":
				if absf(float(per_level[k2]) - 1.0) > 0.0001:
					return true
	return false


# ── Write accessors (used by the slider UI) ────────────────────────────

static func set_value(key: String, value: Variant) -> void:
	if not is_active():
		return
	_ensure_loaded()
	if not _defaults().has(key):
		push_warning("[BalanceOverrides] unknown key: %s" % key)
		return
	_cached[key] = value
	_save()


static func get_value(key: String) -> Variant:
	if not is_active():
		return _defaults().get(key, null)
	_ensure_loaded()
	return _cached.get(key, _defaults().get(key, null))


static func reset() -> void:
	_cached = _defaults()
	_loaded = true
	if is_active() and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	# Some platforms can't delete user:// via globalize; rewrite defaults instead.
	_save()


# ============================================================================
# Per-tower overrides — tier-keyed multipliers for damage / range / speed /
# cost. tier_key ∈ {"l1", "l2", "l3_linear", "branch_a", "branch_b"}. Stored
# under the "tower_overrides" sub-dict; missing keys return identity (1.0).
#
# Read sites:
#   BaseTower.get_effective_damage / _range / _attack_speed (current tier)
#   BaseTower.get_upgrade_range / get_upgrade_cost_to (next tier)
#   BaseTower.get_branch_cost (branch tier)
#   TowerPlacer._on_build_requested (l1 cost)
#   TowerData.get_stats_line / TowerUpgradeData.get_preview_stats (display)
# ============================================================================

const TOWER_STAT_KEYS: Array[String] = ["damage_mult", "range_mult", "speed_mult", "cost_mult"]
const TOWER_TIER_KEYS: Array[String] = ["l1", "l2", "l3_linear", "branch_a", "branch_b"]


static func _ensure_tower_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("tower_overrides"):
		_cached["tower_overrides"] = {}
	return _cached["tower_overrides"]


static func get_tower_mult(tower_id: String, tier_key: String, stat: String) -> float:
	if not is_active() or tower_id == "" or tier_key == "":
		return 1.0
	_ensure_loaded()
	var t: Dictionary = _cached.get("tower_overrides", {})
	var per_tower: Dictionary = t.get(tower_id, {})
	var per_tier: Dictionary = per_tower.get(tier_key, {})
	return float(per_tier.get(stat, 1.0))


static func set_tower_mult(tower_id: String, tier_key: String, stat: String, value: float) -> void:
	if not is_active() or tower_id == "" or tier_key == "":
		return
	if not (stat in TOWER_STAT_KEYS):
		push_warning("[BalanceOverrides] unknown tower stat: %s" % stat)
		return
	if not (tier_key in TOWER_TIER_KEYS):
		push_warning("[BalanceOverrides] unknown tower tier: %s" % tier_key)
		return
	var t: Dictionary = _ensure_tower_dict()
	if not t.has(tower_id):
		t[tower_id] = {}
	if not t[tower_id].has(tier_key):
		t[tower_id][tier_key] = {}
	t[tower_id][tier_key][stat] = value
	_save()


static func reset_tower_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["tower_overrides"] = {}
	_save()


# ============================================================================
# Per-level overrides — keyed by level_id. Sentinel -1 for starting_gold /
# starting_lives means "no override, use computed default". hp_mult defaults
# to 1.0 (multiplied with global hp_mult, not replacing it).
#
# Read sites:
#   RunState.reset_for_level (starting_gold, starting_lives)
#   BaseEnemy._ready (hp_mult, on top of global)
# ============================================================================

const LEVEL_KEYS_INT: Array[String] = ["starting_gold", "starting_lives", "early_call_window"]
const LEVEL_KEYS_FLOAT: Array[String] = ["hp_mult"]


static func _ensure_level_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("level_overrides"):
		_cached["level_overrides"] = {}
	return _cached["level_overrides"]


static func get_level_int(level_id: String, key: String, fallback: int = -1) -> int:
	if not is_active() or level_id == "":
		return fallback
	_ensure_loaded()
	var l: Dictionary = _cached.get("level_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	return int(per_level.get(key, fallback))


static func get_level_float(level_id: String, key: String, fallback: float = 1.0) -> float:
	if not is_active() or level_id == "":
		return fallback
	_ensure_loaded()
	var l: Dictionary = _cached.get("level_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	return float(per_level.get(key, fallback))


static func set_level_value(level_id: String, key: String, value: Variant) -> void:
	if not is_active() or level_id == "":
		return
	if not (key in LEVEL_KEYS_INT) and not (key in LEVEL_KEYS_FLOAT):
		push_warning("[BalanceOverrides] unknown level key: %s" % key)
		return
	var l: Dictionary = _ensure_level_dict()
	if not l.has(level_id):
		l[level_id] = {}
	l[level_id][key] = value
	_save()


static func reset_level_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["level_overrides"] = {}
	_save()


# ============================================================================
# Per-enemy overrides — keyed by enemy_id. Stat keys mirror EnemyData fields:
#   hp_mult / speed_mult / damage_mult / gold_mult   → multiplicative
#   armor_add / mag_res_add                          → additive (clamped 0–0.95
#                                                     at the read site)
#
# Read sites (multiplied/added on top of the existing global enemy mults):
#   BaseEnemy._ready          — max_health (× hp_mult, after global hp_mult)
#   BaseEnemy._effective_speed — move_speed (× speed_mult, after global)
#   BaseEnemy.take_damage     — armor / magic_resist (+ adders, after global)
#   BaseEnemy._die / drop     — gold_worth (× gold_mult)
#   BaseSoldier / BaseHero hit-back path — uses data.attack_damage × damage_mult
# ============================================================================

const ENEMY_STAT_KEYS: Array[String] = [
	"hp_mult", "armor_add", "mag_res_add",
	"speed_mult", "damage_mult", "gold_mult",
]


static func _ensure_enemy_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("enemy_overrides"):
		_cached["enemy_overrides"] = {}
	return _cached["enemy_overrides"]


# Multiplier-style stat read. Default 1.0 for *_mult, 0.0 for *_add — chosen
# so a stat with no override is identity at the read site.
static func get_enemy_mult(enemy_id: String, stat: String) -> float:
	if not is_active() or enemy_id == "":
		return _enemy_default_for(stat)
	_ensure_loaded()
	var e: Dictionary = _cached.get("enemy_overrides", {})
	var per_enemy: Dictionary = e.get(enemy_id, {})
	return float(per_enemy.get(stat, _enemy_default_for(stat)))


static func _enemy_default_for(stat: String) -> float:
	if stat == "armor_add" or stat == "mag_res_add":
		return 0.0
	return 1.0


static func set_enemy_mult(enemy_id: String, stat: String, value: float) -> void:
	if not is_active() or enemy_id == "":
		return
	if not (stat in ENEMY_STAT_KEYS):
		push_warning("[BalanceOverrides] unknown enemy stat: %s" % stat)
		return
	var e: Dictionary = _ensure_enemy_dict()
	if not e.has(enemy_id):
		e[enemy_id] = {}
	e[enemy_id][stat] = value
	_save()


# Convenience: true if any enemy has a non-default override active. Used by
# the bake button to decide whether to walk enemies.
static func any_enemy_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	var e: Dictionary = _cached.get("enemy_overrides", {})
	for eid in e.keys():
		var per_enemy: Dictionary = e[eid]
		for stat in ENEMY_STAT_KEYS:
			if absf(float(per_enemy.get(stat, _enemy_default_for(stat))) - _enemy_default_for(stat)) > 0.0001:
				return true
	return false


static func reset_enemy_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["enemy_overrides"] = {}
	_save()


# ============================================================================
# Per-wave-spawn count overrides — keyed by (level_id → wave_idx → spawn_idx).
# Stored as multiplier vs the authored WaveSpawn.count. 1.0 = identity, 0.0 =
# emitter disabled, 2.0 = doubled. Applied at runtime by WaveManager._run_spawner
# and at chart-time by WaveTimelineChart / LevelOverviewChart so the per-wave
# EHP bars / gold curve track the slider live.
#
# Read sites:
#   WaveManager._run_spawner — multiplies authored count at spawn time
#   WaveTimelineChart._recompute — multiplies each emitter's contribution
#   LevelOverviewChart._recompute — same
# ============================================================================


static func _ensure_wave_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("wave_overrides"):
		_cached["wave_overrides"] = {}
	return _cached["wave_overrides"]


static func get_wave_count_mult(level_id: String, wave_idx: int, spawn_idx: int) -> float:
	if not is_active() or level_id == "":
		return 1.0
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	var per_wave: Dictionary = per_level.get(str(wave_idx), {})
	return float(per_wave.get(str(spawn_idx), 1.0))


static func set_wave_count_mult(level_id: String, wave_idx: int, spawn_idx: int, value: float) -> void:
	if not is_active() or level_id == "":
		return
	var l: Dictionary = _ensure_wave_dict()
	if not l.has(level_id):
		l[level_id] = {}
	var per_level: Dictionary = l[level_id]
	var wave_key: String = str(wave_idx)
	if not per_level.has(wave_key):
		per_level[wave_key] = {}
	per_level[wave_key][str(spawn_idx)] = value
	_save()


# True if any wave-spawn has a non-identity count multiplier active.
static func any_wave_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_overrides", {})
	for lid in l.keys():
		var per_level: Dictionary = l[lid]
		for wk in per_level.keys():
			var per_wave: Dictionary = per_level[wk]
			for sk in per_wave.keys():
				if absf(float(per_wave[sk]) - 1.0) > 0.0001:
					return true
	return false


static func reset_wave_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["wave_overrides"] = {}
	_save()


# ============================================================================
# Per-wave countdown overrides — keyed by (level_id → wave_idx → seconds).
# Stored as ABSOLUTE seconds (not multiplier), with sentinel -1 meaning "use
# authored". Multipliers are awkward for waves with countdown=0 (×N = still 0)
# and countdown is a human-friendly absolute time value.
#
# Read sites:
#   WaveManager — when reading wave.countdown for next-wave countdown timing
#   WaveTimelineChart._draw_header / _draw_prewave — chart pre-wave width
# ============================================================================


static func _ensure_wave_countdown_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("wave_countdown_overrides"):
		_cached["wave_countdown_overrides"] = {}
	return _cached["wave_countdown_overrides"]


# Returns -1 sentinel (use authored) when no override is active.
static func get_wave_countdown(level_id: String, wave_idx: int) -> int:
	if not is_active() or level_id == "":
		return -1
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_countdown_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	return int(per_level.get(str(wave_idx), -1))


static func set_wave_countdown(level_id: String, wave_idx: int, seconds: int) -> void:
	if not is_active() or level_id == "":
		return
	var l: Dictionary = _ensure_wave_countdown_dict()
	if not l.has(level_id):
		l[level_id] = {}
	l[level_id][str(wave_idx)] = seconds
	_save()


static func any_wave_countdown_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_countdown_overrides", {})
	for lid in l.keys():
		var per_level: Dictionary = l[lid]
		for wk in per_level.keys():
			if int(per_level[wk]) >= 0:
				return true
	return false


static func reset_wave_countdown_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["wave_countdown_overrides"] = {}
	_save()


# ============================================================================
# Per-emitter timing overrides — interval (seconds between spawns) and
# start_delay (seconds after wave-start before this emitter begins). Both
# stored as ABSOLUTE seconds, sentinel -1 = "use authored".
#
# Stored under separate sub-dicts (parallel to wave_overrides for counts) so
# the existing count-mult plumbing stays unchanged.
#
# Read sites:
#   WaveManager._run_spawner — replaces spawn.interval / spawn.start_delay
#   WaveTimelineChart._recompute — chart spawn timing math
# ============================================================================


static func _ensure_wave_interval_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("wave_interval_overrides"):
		_cached["wave_interval_overrides"] = {}
	return _cached["wave_interval_overrides"]


static func _ensure_wave_delay_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("wave_delay_overrides"):
		_cached["wave_delay_overrides"] = {}
	return _cached["wave_delay_overrides"]


# -1.0 sentinel = use authored.
static func get_wave_interval(level_id: String, wave_idx: int, spawn_idx: int) -> float:
	if not is_active() or level_id == "":
		return -1.0
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_interval_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	var per_wave: Dictionary = per_level.get(str(wave_idx), {})
	return float(per_wave.get(str(spawn_idx), -1.0))


static func set_wave_interval(level_id: String, wave_idx: int, spawn_idx: int, seconds: float) -> void:
	if not is_active() or level_id == "":
		return
	var l: Dictionary = _ensure_wave_interval_dict()
	if not l.has(level_id):
		l[level_id] = {}
	var wave_key: String = str(wave_idx)
	if not l[level_id].has(wave_key):
		l[level_id][wave_key] = {}
	l[level_id][wave_key][str(spawn_idx)] = seconds
	_save()


static func get_wave_delay(level_id: String, wave_idx: int, spawn_idx: int) -> float:
	if not is_active() or level_id == "":
		return -1.0
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_delay_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	var per_wave: Dictionary = per_level.get(str(wave_idx), {})
	return float(per_wave.get(str(spawn_idx), -1.0))


static func set_wave_delay(level_id: String, wave_idx: int, spawn_idx: int, seconds: float) -> void:
	if not is_active() or level_id == "":
		return
	var l: Dictionary = _ensure_wave_delay_dict()
	if not l.has(level_id):
		l[level_id] = {}
	var wave_key: String = str(wave_idx)
	if not l[level_id].has(wave_key):
		l[level_id][wave_key] = {}
	l[level_id][wave_key][str(spawn_idx)] = seconds
	_save()


static func any_wave_timing_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	for sub_key in ["wave_interval_overrides", "wave_delay_overrides"]:
		var l: Dictionary = _cached.get(sub_key, {})
		for lid in l.keys():
			var per_level: Dictionary = l[lid]
			for wk in per_level.keys():
				var per_wave: Dictionary = per_level[wk]
				for sk in per_wave.keys():
					if float(per_wave[sk]) >= 0.0:
						return true
	return false


static func reset_wave_timing_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["wave_interval_overrides"] = {}
	_cached["wave_delay_overrides"] = {}
	_save()


# ============================================================================
# Per-wave early-call window override — keyed by (level_id → wave_idx).
# Stored as ABSOLUTE seconds, sentinel -1 = use authored. Resolution chain
# (top wins): per-wave override > WaveData.early_call_window_sec > per-level
# override > LevelNodeData.early_call_window_sec.
#
# Read sites:
#   WaveManager._effective_early_call_window — resolves the chain
#   WaveTimelineChart._draw — chart pre-wave region width
# ============================================================================


static func _ensure_wave_early_call_dict() -> Dictionary:
	_ensure_loaded()
	if not _cached.has("wave_early_call_overrides"):
		_cached["wave_early_call_overrides"] = {}
	return _cached["wave_early_call_overrides"]


# Returns -1 sentinel (use authored chain) when no override is active.
static func get_wave_early_call_window(level_id: String, wave_idx: int) -> float:
	if not is_active() or level_id == "":
		return -1.0
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_early_call_overrides", {})
	var per_level: Dictionary = l.get(level_id, {})
	return float(per_level.get(str(wave_idx), -1.0))


static func set_wave_early_call_window(level_id: String, wave_idx: int, seconds: float) -> void:
	if not is_active() or level_id == "":
		return
	var l: Dictionary = _ensure_wave_early_call_dict()
	if not l.has(level_id):
		l[level_id] = {}
	l[level_id][str(wave_idx)] = seconds
	_save()


static func any_wave_early_call_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	var l: Dictionary = _cached.get("wave_early_call_overrides", {})
	for lid in l.keys():
		var per_level: Dictionary = l[lid]
		for wk in per_level.keys():
			if float(per_level[wk]) >= 0.0:
				return true
	return false


static func reset_wave_early_call_overrides() -> void:
	if not is_active():
		return
	_ensure_loaded()
	_cached["wave_early_call_overrides"] = {}
	_save()
