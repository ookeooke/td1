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
	# Merge — unknown keys ignored, missing keys keep defaults
	for k in _cached.keys():
		if (parsed as Dictionary).has(k):
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
