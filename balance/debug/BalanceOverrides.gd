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


# Convenience — true if any override is non-default.
static func any_active() -> bool:
	if not is_active():
		return false
	_ensure_loaded()
	var d := _defaults()
	for k in d.keys():
		if _cached.get(k, d[k]) != d[k]:
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

const LEVEL_KEYS_INT: Array[String] = ["starting_gold", "starting_lives"]
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
