extends Node

# Phase 36: content unlock gate. Every system that shows/hides/enables
# locked content calls one of the type-specific is_*_unlocked methods below —
# heroes, towers, etc.
#
# Rule #7: all IAP-locked content checked through UnlockManager before
# loading. Never hardcode unlock states.
#
# Phase 46c: the old `is_unlocked(id)` did a global-namespace search
# which silently returned the first match. When hero "mage"
# (requires_unlock=true) and tower "mage" (requires_unlock=false) shared an
# id, the tower query hit the hero resource and locked the tower from the
# build ring. Type-specific methods below eliminate that class of bug.
#
# Three unlock paths (identical across types):
#   1. Free content — `requires_unlock == false` on the Data → always available.
#   2. Explicitly unlocked — ID in MetaProgression.unlocked_content (IAP / star / event).
#   3. Star-threshold auto-unlock — defined in _star_thresholds. Checked on
#      every call so progress auto-grants access.

# Star thresholds for auto-unlocking content. Add hero/tower IDs here with
# the total-star count needed to unlock. Players don't "spend" stars on
# these — reaching the threshold is enough (stars are spent on upgrades).
var _star_thresholds: Dictionary = {
	# "hero_mage": 5,  # uncomment to gate Mage behind 5 total campaign stars
}


func _ready() -> void:
	print("[UnlockManager] loaded — %d explicit unlocks" % MetaProgression.unlocked_content.size())


func is_hero_unlocked(hero_id: String) -> bool:
	return _is_unlocked_in(hero_id, ContentRegistry.find_hero(hero_id))


func is_tower_unlocked(tower_id: String) -> bool:
	return _is_unlocked_in(tower_id, ContentRegistry.find_tower(tower_id))


# Shared three-path check used by every type-specific method.
func _is_unlocked_in(id: String, data: Resource) -> bool:
	if id == "":
		return true
	# 1. Explicitly unlocked (IAP, event, etc.)
	if id in MetaProgression.unlocked_content:
		return true
	# 2. Free content — the Data's requires_unlock says it's always available.
	#    Enemies don't have requires_unlock today; a missing field means
	#    "not lockable" → treat as free.
	if data != null:
		if "requires_unlock" in data and not data.requires_unlock:
			return true
		elif not "requires_unlock" in data:
			return true
	# 3. Star-threshold auto-unlock.
	if id in _star_thresholds:
		return MetaProgression.get_total_stars() >= _star_thresholds[id]
	return false


# Explicit unlock — called by PurchaseManager on IAP success, and by
# progression events that unlock content outside the star-threshold path.
# Type-agnostic because `unlocked_content` is a flat list and IDs are
# scoped (hero_*, tower_*) so collisions can't happen.
func unlock(id: String) -> void:
	if id in MetaProgression.unlocked_content:
		return
	MetaProgression.unlocked_content.append(id)
	SaveManager.save_game()
	print("[UnlockManager] unlocked '%s'" % id)
