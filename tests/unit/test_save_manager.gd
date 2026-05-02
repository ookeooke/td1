extends GutTest

const TestHelpers = preload("res://tests/unit/test_helpers.gd")

# SaveManager round-trip + failure-path coverage. These tests exercise the
# path-parameterized primitives `_save_to_path(path)` / `_load_from_path(path)`
# with a temp file under user://, so the player's real save is never touched.
#
# Each test snapshots the relevant autoload state at start, mutates it,
# round-trips, asserts, and restores defaults so subsequent tests start clean.

var _temp_path: String = ""
var _saved_level_stars: Dictionary = {}
var _saved_hero_talents: Dictionary = {}
var _saved_selected_hero: String = ""
var _saved_meta_gold: int = 0


func before_each() -> void:
	_temp_path = TestHelpers.temp_save_path("save_manager")
	# Snapshot what we may mutate so after_each can restore exactly.
	_saved_level_stars = MetaProgression.level_stars.duplicate(true)
	_saved_hero_talents = MetaProgression.hero_talents.duplicate(true)
	_saved_selected_hero = LoadoutState.selected_hero_id
	_saved_meta_gold = MetaProgression.meta_gold


func after_each() -> void:
	# Restore autoloads so a failed test doesn't pollute the next.
	MetaProgression.level_stars = _saved_level_stars
	MetaProgression.hero_talents = _saved_hero_talents
	LoadoutState.selected_hero_id = _saved_selected_hero
	MetaProgression.meta_gold = _saved_meta_gold


func after_all() -> void:
	TestHelpers.cleanup_temp_saves()


func test_round_trip_preserves_state() -> void:
	# Set a recognizable fixture across all three state autoloads.
	MetaProgression.level_stars = {"level_1": 3, "level_2": 1}
	MetaProgression.meta_gold = 1234
	LoadoutState.selected_hero_id = "hero_mage"

	SaveManager._save_to_path(_temp_path)

	# Mutate in memory so the load has something to overwrite.
	MetaProgression.level_stars = {}
	MetaProgression.meta_gold = 0
	LoadoutState.selected_hero_id = ""

	SaveManager._load_from_path(_temp_path)

	assert_eq(MetaProgression.level_stars.get("level_1", -1), 3)
	assert_eq(MetaProgression.level_stars.get("level_2", -1), 1)
	assert_eq(MetaProgression.meta_gold, 1234)
	assert_eq(LoadoutState.selected_hero_id, "hero_mage")


func test_missing_file_uses_defaults() -> void:
	# Path that definitely doesn't exist. Production-equivalent of a fresh boot.
	var missing: String = TestHelpers.temp_save_path("does_not_exist")
	if FileAccess.file_exists(missing):
		DirAccess.remove_absolute(missing)
	# Set a known value; load should NOT touch it (the loader returns early
	# on missing file rather than zeroing state).
	MetaProgression.meta_gold = 42
	SaveManager._load_from_path(missing)
	assert_eq(MetaProgression.meta_gold, 42, "missing file should leave state untouched")


func test_corrupted_json_is_skipped() -> void:
	# Write garbage to the temp path; loader should warn and bail without
	# crashing or touching state.
	var f: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	f.store_string("{ this is not [valid] json")
	f.close()
	MetaProgression.meta_gold = 99
	SaveManager._load_from_path(_temp_path)
	assert_eq(MetaProgression.meta_gold, 99, "corrupt file should leave state untouched")


func test_unknown_version_is_ignored() -> void:
	# Version 0 is the "unknown / pre-versioning" sentinel — loader returns early.
	var f: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	f.store_string('{"version": 0, "meta_gold": 555}')
	f.close()
	MetaProgression.meta_gold = 1
	SaveManager._load_from_path(_temp_path)
	assert_eq(MetaProgression.meta_gold, 1, "version=0 should not populate state")


func test_hero_talents_round_trip() -> void:
	# Talents dict is the hero-keyed-array shape; the loader has special
	# coercion that previously dropped types. Regression-locks the fix.
	MetaProgression.hero_talents = {
		"hero_warrior": ["talent_strength", "talent_block"],
		"hero_mage": ["talent_arcane"],
	}
	SaveManager._save_to_path(_temp_path)
	MetaProgression.hero_talents = {}
	SaveManager._load_from_path(_temp_path)

	assert_eq(MetaProgression.hero_talents.size(), 2)
	var warrior: Array = MetaProgression.hero_talents.get("hero_warrior", [])
	assert_eq(warrior.size(), 2)
	assert_true("talent_strength" in warrior and "talent_block" in warrior)
	var mage: Array = MetaProgression.hero_talents.get("hero_mage", [])
	assert_eq(mage, ["talent_arcane"])
