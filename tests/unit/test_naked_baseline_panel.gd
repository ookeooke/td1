extends GutTest

# Coverage for NakedBaselinePanel's pure static helpers. The UI half (label
# painting, button enable) is left to manual editor verification.
#
# preload() instead of class_name access — the GUT cli headless runner
# doesn't always have the class_name registry populated when test scripts
# are parsed, so direct `NakedBaselinePanel.evaluate()` calls trip a parse
# error. preload sidesteps the registry entirely.

const _NBP := preload("res://ui/NakedBaselinePanel.gd")


func test_evaluate_returns_ten_named_conditions() -> void:
	# RunStats._is_naked_baseline_run checks ten conditions; the panel surfaces
	# every single one. If the underlying gate grows a new check this test
	# fails and forces the panel to stay in sync.
	var checks: Array = _NBP.evaluate()
	assert_eq(checks.size(), 10, "10 baseline conditions surfaced")
	var keys: Array = []
	for c in checks:
		keys.append(String(c.get("key", "")))
	for required in ["mode", "overrides", "hero", "towers", "items",
			"upgrades", "talents", "hero_level", "skill_nodes", "skills"]:
		assert_true(keys.has(required), "checklist includes '%s'" % required)


func test_evaluate_entries_carry_label_ok_fixable_hint() -> void:
	var checks: Array = _NBP.evaluate()
	for c in checks:
		assert_true(c.has("label") and String(c.get("label", "")) != "",
			"every check has a non-empty label")
		assert_true(c.has("ok"), "every check has an `ok` bool")
		assert_true(c.has("fixable"), "every check has a `fixable` bool")
		assert_true(c.has("hint"), "every check has a `hint` string")


func test_summarize_counts_passing_fixable_permanent_buckets() -> void:
	var checks := [
		{"ok": true,  "fixable": true},
		{"ok": true,  "fixable": false},
		{"ok": false, "fixable": true},
		{"ok": false, "fixable": true},
		{"ok": false, "fixable": false},
	]
	var s: Dictionary = _NBP.summarize(checks)
	assert_eq(int(s.total), 5, "total")
	assert_eq(int(s.passing), 2, "passing")
	assert_eq(int(s.fixable_failing), 2, "fixable failing")
	assert_eq(int(s.permanent_failing), 1, "permanent failing")
	assert_false(bool(s.ready), "not ready when any failing")


func test_summarize_ready_when_all_pass() -> void:
	var checks := [
		{"ok": true, "fixable": true},
		{"ok": true, "fixable": false},
	]
	var s: Dictionary = _NBP.summarize(checks)
	assert_true(bool(s.ready), "ready when every check passes")
	assert_eq(int(s.fixable_failing), 0, "nothing fixable still failing")


func test_summarize_empty_input_is_ready() -> void:
	var s: Dictionary = _NBP.summarize([])
	assert_eq(int(s.total), 0, "0 total")
	assert_true(bool(s.ready), "vacuously ready with no checks")


func test_auto_fix_corrects_hero_and_towers() -> void:
	# Stash + restore so we don't pollute the autoload across other tests.
	# LoadoutState.selected_tower_ids is Array[String] — preserve element type
	# by reconstructing typed arrays around the bare-Array literals.
	var prev_hero: String = LoadoutState.selected_hero_id
	var prev_towers: Array[String] = []
	for t in LoadoutState.selected_tower_ids:
		prev_towers.append(String(t))
	# Force off-baseline state.
	LoadoutState.selected_hero_id = "hero_mage"
	var bogus: Array[String] = [
		"tower_archer", "tower_archer", "tower_archer", "tower_archer",
	]
	LoadoutState.selected_tower_ids = bogus
	var fixed: int = _NBP.auto_fix()
	assert_gt(fixed, 0, "auto_fix resolved at least one condition")
	assert_eq(LoadoutState.selected_hero_id, "hero_warrior",
		"hero reset to warrior")
	var sorted_towers: Array = []
	for t in LoadoutState.selected_tower_ids:
		sorted_towers.append(String(t))
	sorted_towers.sort()
	var expected := ["tower_archer", "tower_artillery", "tower_barracks", "tower_mage"]
	assert_eq(sorted_towers, expected, "towers reset to the default 4 (as set)")
	# Restore prior state.
	LoadoutState.selected_hero_id = prev_hero
	LoadoutState.selected_tower_ids = prev_towers
