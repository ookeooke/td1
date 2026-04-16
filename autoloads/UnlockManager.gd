extends Node

# Phase 36: content unlock gate. Every system that shows/hides/enables
# locked content calls is_unlocked(id) — heroes, towers, spells, etc.
#
# Rule #7: all IAP-locked content checked through UnlockManager before
# loading. Never hardcode unlock states.
#
# Three unlock paths:
#   1. Free content — requires_unlock == false on the data Resource → always available.
#   2. Explicitly unlocked — ID in GameState.unlocked_content (set by IAP Phase 37,
#      star purchase, or progression event).
#   3. Star-threshold auto-unlock — defined in _star_thresholds below. Checked
#      on every is_unlocked call so progress auto-grants access.

# Star thresholds for auto-unlocking content. Add hero/tower/spell IDs here
# with the total-star count needed to unlock. Players don't "spend" stars
# on these — reaching the threshold is enough (stars are spent on upgrades).
var _star_thresholds: Dictionary = {
	# "hero_mage": 5,  # uncomment to gate Mage behind 5 total campaign stars
}


func _ready() -> void:
	print("[UnlockManager] loaded — %d explicit unlocks" % GameState.unlocked_content.size())


func is_unlocked(id: String) -> bool:
	if id == "":
		return true
	# 1. Explicitly unlocked (IAP, event, etc.)
	if id in GameState.unlocked_content:
		return true
	# 2. Free content — check the data Resource's requires_unlock field.
	var data: Resource = _find_content_data(id)
	if data != null and "requires_unlock" in data and not data.requires_unlock:
		return true
	# 3. Star-threshold auto-unlock.
	if id in _star_thresholds:
		return GameState.get_total_stars() >= _star_thresholds[id]
	return false


func unlock(id: String) -> void:
	if id in GameState.unlocked_content:
		return
	GameState.unlocked_content.append(id)
	SaveManager.save_game()
	print("[UnlockManager] unlocked '%s'" % id)


func _find_content_data(id: String) -> Resource:
	# Search ContentRegistry for the matching data Resource.
	var r: Resource = ContentRegistry.find_hero(id)
	if r != null:
		return r
	r = ContentRegistry.find_tower(id)
	if r != null:
		return r
	for s in ContentRegistry.spells:
		if s != null and "spell_id" in s and s.spell_id == id:
			return s
	return null
