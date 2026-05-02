extends GutTest

const TestHelpers = preload("res://tests/unit/test_helpers.gd")

# Save migration scaffold + orphan-content purge. Tests overwrite
# SaveManager._migrations with synthetic Callables so the chain logic can
# be exercised without an actual schema bump.

var _temp_path: String = ""
var _saved_migrations: Array[Callable]
var _saved_meta_gold: int
var _saved_selected_hero: String
var _saved_selected_towers: Array[String]
var _saved_hero_progress: Dictionary


func before_each() -> void:
	_temp_path = TestHelpers.temp_save_path("save_migrations")
	_saved_migrations = SaveManager._migrations.duplicate()
	_saved_meta_gold = MetaProgression.meta_gold
	_saved_selected_hero = LoadoutState.selected_hero_id
	_saved_selected_towers = LoadoutState.selected_tower_ids.duplicate()
	_saved_hero_progress = MetaProgression.hero_progress.duplicate(true)


func after_each() -> void:
	SaveManager._migrations = _saved_migrations
	MetaProgression.meta_gold = _saved_meta_gold
	LoadoutState.selected_hero_id = _saved_selected_hero
	LoadoutState.selected_tower_ids = _saved_selected_towers
	MetaProgression.hero_progress = _saved_hero_progress


func after_all() -> void:
	TestHelpers.cleanup_temp_saves()


# Verifies the chain runs all migrations whose target version is > the
# loaded version, and applies them in order. We use mutable state via an
# Array cell because lambda captures are by-value.
func test_migration_chain_runs_in_forward_order() -> void:
	var trace: Array[String] = []
	# _migrations[0] handles v1→v2; _migrations[1] handles v2→v3.
	# With a save written at version=1, both must run, in order.
	SaveManager._migrations = [
		func(_d: Dictionary) -> void: trace.append("v1->v2"),
		func(_d: Dictionary) -> void: trace.append("v2->v3"),
	]

	# Write a fixture that pretends to be v1. Use the real save-game body's
	# minimal shape so the loader doesn't error before reaching the migration.
	var f: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	f.store_string('{"version": 1, "meta_gold": 7}')
	f.close()

	SaveManager._load_from_path(_temp_path)

	assert_eq(trace, ["v1->v2", "v2->v3"], "migrations run in registered order")
	# Sanity: meta_gold from the fixture still landed in MetaProgression.
	assert_eq(MetaProgression.meta_gold, 7,
		"state population still happens after migrations")


# Saves at SAVE_VERSION skip the migration chain — we only run forward.
# Mock migrations must NOT execute when no version gap exists.
func test_no_migrations_run_when_save_at_current_version() -> void:
	var trace: Array[int] = [0]
	SaveManager._migrations = [
		func(_d: Dictionary) -> void: trace[0] += 1,
	]

	# Write a v=SAVE_VERSION save so the loader sees no gap to migrate.
	var f: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	f.store_string('{"version": %d, "meta_gold": 1}' % SaveManager.SAVE_VERSION)
	f.close()

	SaveManager._load_from_path(_temp_path)

	assert_eq(trace[0], 0, "migrations skipped when save is already at SAVE_VERSION")


# When ContentRegistry no longer authors a saved content_id (rename or
# removal between game versions), the loader silently drops the orphaned
# reference rather than crashing. content_hash mismatch triggers the purge.
func test_orphaned_content_ids_purged_on_load() -> void:
	# Round-trip a save that also contains junk ids the registry doesn't
	# know about. Force the content_hash to mismatch by writing a different
	# value than _compute_content_hash() will return on read.
	var fixture: Dictionary = {
		"version": SaveManager.SAVE_VERSION,
		"selected_hero_id": "hero_does_not_exist_xyz",
		"selected_tower_ids": ["tower_archer", "tower_does_not_exist_abc", "tower_mage"],
		"hero_progress": {
			"hero_warrior": {"level": 5, "xp": 0},
			"hero_does_not_exist_xyz": {"level": 99, "xp": 0},
		},
		# Mismatched hash forces _purge_orphaned_content to run.
		"content_hash": "deliberately_wrong_hash",
	}
	var f: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(fixture))
	f.close()

	SaveManager._load_from_path(_temp_path)

	# Orphan hero_id cleared.
	assert_eq(LoadoutState.selected_hero_id, "",
		"orphaned selected_hero_id replaced with empty string")
	# Orphan tower_id replaced with "" (positional preserved).
	assert_eq(LoadoutState.selected_tower_ids[0], "tower_archer")
	assert_eq(LoadoutState.selected_tower_ids[1], "",
		"orphaned tower_id at slot 1 swept to empty (slot position kept)")
	assert_eq(LoadoutState.selected_tower_ids[2], "tower_mage")
	# Orphan hero_id key dropped from hero_progress; valid id retained.
	assert_true(MetaProgression.hero_progress.has("hero_warrior"))
	assert_false(MetaProgression.hero_progress.has("hero_does_not_exist_xyz"),
		"orphaned hero_id key dropped from hero_progress dict")
