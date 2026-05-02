extends GutTest

# ContentRegistry — find_*() lookups and the _validate_ids drift check.
# These tests assert that the catalog populated at boot has every authored
# tower / hero / enemy reachable by its stable content_id, and that the
# CORE RULE 12 invariant (filename basename == content_id) holds across
# the entire registry.


func test_find_tower_returns_data_with_matching_id() -> void:
	var data: Resource = ContentRegistry.find_tower("tower_archer")
	assert_not_null(data, "tower_archer must be in registry")
	assert_eq(data.tower_id, "tower_archer", "find_tower must return data with matching tower_id")


func test_find_hero_missing_id_returns_null() -> void:
	# No crash, no fallback — null is the contract for unknown ids.
	var data: Resource = ContentRegistry.find_hero("hero_does_not_exist_xyz")
	assert_null(data, "find_hero on unknown id must return null")
	# Empty string is a separate edge case — also returns null.
	assert_null(ContentRegistry.find_hero(""))


func test_find_enemy_returns_data_with_matching_id() -> void:
	var data: Resource = ContentRegistry.find_enemy("enemy_basic")
	assert_not_null(data, "enemy_basic must be in registry")
	assert_eq(data.enemy_id, "enemy_basic")


func test_no_id_drift_in_current_registry() -> void:
	# Mirrors ContentRegistry._assert_ids logic but as a hard test assertion.
	# Catches future authoring mistakes where a .tres's *_id field doesn't
	# match its filename basename — e.g. tower_archer.tres holding
	# tower_id="archer". CORE RULE 12 enforcement.
	_assert_no_drift(ContentRegistry.towers, "tower_id")
	_assert_no_drift(ContentRegistry.heroes, "hero_id")
	_assert_no_drift(ContentRegistry.enemies, "enemy_id")
	_assert_no_drift(ContentRegistry.item_bases, "base_id")
	_assert_no_drift(ContentRegistry.affixes, "affix_id")
	_assert_no_drift(ContentRegistry.affix_pools, "pool_id")


func _assert_no_drift(arr: Array, field: String) -> void:
	for r in arr:
		if r == null:
			fail_test("registry has null entry — load failure")
			continue
		assert_true(field in r, "%s missing %s" % [r.resource_path, field])
		var id: String = r.get(field)
		var base: String = r.resource_path.get_file().get_basename()
		assert_ne(id, "", "%s has empty %s" % [r.resource_path, field])
		assert_eq(id, base,
			"%s: %s=%s should match filename basename %s" % [r.resource_path, field, id, base])
