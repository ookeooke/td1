extends GutTest

# UnlockManager — three unlock paths (explicit, free, star-threshold) and the
# type-scoped find_*_unlocked dispatch. The type-scoping was the Phase 46c
# fix: previously is_unlocked() did a flat ID search and the hero/tower "mage"
# id collision silently locked the tower from the build ring.

var _saved_unlocked_content: Array[String] = []
var _saved_level_stars: Dictionary = {}
var _saved_thresholds: Dictionary = {}


func before_each() -> void:
	_saved_unlocked_content = MetaProgression.unlocked_content.duplicate()
	_saved_level_stars = MetaProgression.level_stars.duplicate(true)
	_saved_thresholds = UnlockManager._star_thresholds.duplicate(true)


func after_each() -> void:
	MetaProgression.unlocked_content = _saved_unlocked_content
	MetaProgression.level_stars = _saved_level_stars
	UnlockManager._star_thresholds = _saved_thresholds


func test_type_scoped_dispatch_returns_false_for_wrong_type() -> void:
	# tower_archer is a tower_id, never a hero_id. Querying it through
	# is_hero_unlocked must return false (find_hero returns null, no other
	# path applies). This is the regression-lock for the Phase 46c fix.
	MetaProgression.unlocked_content = []
	assert_false(UnlockManager.is_hero_unlocked("tower_archer"),
		"tower_id queried as hero must not unlock")


func test_empty_id_treated_as_unlockable() -> void:
	# Defensive: empty id returns true (callers shouldn't pass it, but the
	# guard prevents accidental gating when an id slips through unset).
	assert_true(UnlockManager.is_tower_unlocked(""), "empty id is defensively unlocked")
	assert_true(UnlockManager.is_hero_unlocked(""), "empty id is defensively unlocked")


func test_star_threshold_unlocks_when_reached() -> void:
	# Inject a synthetic threshold so the test doesn't depend on whatever
	# _star_thresholds contains in production (currently empty).
	UnlockManager._star_thresholds = {"hero_test_threshold": 2}
	# Total stars = sum of (campaign_stars + heroic_bonus + iron_bonus) per level.
	# Setting level_stars[level] = 3 contributes 3 campaign stars.
	MetaProgression.level_stars = {"level_1": 3}
	assert_true(UnlockManager.is_hero_unlocked("hero_test_threshold"),
		"threshold met → unlocked")
	# Raise the threshold above current stars; same id should now be locked.
	UnlockManager._star_thresholds = {"hero_test_threshold": 99}
	assert_false(UnlockManager.is_hero_unlocked("hero_test_threshold"),
		"threshold not met → locked")


func test_explicit_unlock_via_unlocked_content() -> void:
	# Add a not-yet-authored hero_id to unlocked_content. is_hero_unlocked
	# should return true via path 1 (explicit unlock) even though
	# ContentRegistry.find_hero returns null. This is the IAP path: the
	# server can grant unlock for content that ships in a future content
	# pack without the client having to re-validate against the catalog.
	MetaProgression.unlocked_content = []
	assert_false(UnlockManager.is_hero_unlocked("hero_paladin"))
	UnlockManager.unlock("hero_paladin")
	assert_true(UnlockManager.is_hero_unlocked("hero_paladin"))
	assert_true("hero_paladin" in MetaProgression.unlocked_content)


func test_free_content_unlocked_without_unlocked_content_entry() -> void:
	# hero_warrior ships with no `requires_unlock` field → "not lockable" →
	# free. Must return true even with empty unlocked_content + empty
	# star thresholds.
	MetaProgression.unlocked_content = []
	UnlockManager._star_thresholds = {}
	assert_true(UnlockManager.is_hero_unlocked("hero_warrior"),
		"hero_warrior is free; no explicit unlock needed")
	# tower_archer is also free by absence of requires_unlock.
	assert_true(UnlockManager.is_tower_unlocked("tower_archer"))
