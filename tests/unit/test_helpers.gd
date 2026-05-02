extends RefCounted

# Shared utilities for the unit-test suite. Tests reference this script via
# direct preload (not class_name) so the suite is loadable in a headless
# CI run before Godot has indexed the global class cache:
#
#     const TestHelpers = preload("res://tests/unit/test_helpers.gd")
#
# All methods are stateless — no setup/teardown needed.


# Minimal stub matching DamageCalculator's expectation: a Node with `.data`
# carrying `armor` and `magic_resist`. Pure script, no scene tree needed.
static func make_fake_target(armor: float, magic_resist: float) -> Node:
	var data := RefCounted.new()
	data.set_script(_FakeTargetData)
	data.armor = armor
	data.magic_resist = magic_resist
	var target := Node.new()
	target.set_script(_FakeTarget)
	target.data = data
	return target


# Returns user://test_save_<suffix>.json. Deterministic per-suffix so tests
# can clean up specific fixtures without a glob.
static func temp_save_path(suffix: String) -> String:
	return "user://test_save_%s.json" % suffix


# Removes any user://test_save_*.json. Call in after_all() to keep the
# user data dir clean across runs.
static func cleanup_temp_saves() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("test_save_") and name.ends_with(".json"):
			DirAccess.remove_absolute("user://%s" % name)
		name = dir.get_next()
	dir.list_dir_end()


# ── Inline scripts so the helpers compile without separate files ────────

# Fake target/data scripts use GDScript's inline-script-resource pattern so
# the helper file stays self-contained. The fields match what the production
# code reads (armor, magic_resist on data; data on target).
const _FakeTargetData: GDScript = preload("res://tests/unit/_fake_target_data.gd")
const _FakeTarget: GDScript = preload("res://tests/unit/_fake_target.gd")
