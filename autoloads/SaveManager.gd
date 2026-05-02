extends Node

# Phase 27: the ONLY script that reads/writes the save file (Rule #8).
# JSON format at user://save.json. Schema versioned so future phases can
# migrate without breaking old saves.
#
# Initialization order: GameState._ready() runs first (resets to defaults),
# then SaveManager._ready() loads saved data on top. Autoload registration
# order in project.godot guarantees this.
#
# Save triggers:
#   - level_completed signal (auto-save best stars + unlock next level)
#   - Future phases: IAP purchase, upgrade purchase, encyclopedia unlock
# Never auto-saves mid-wave.

const SAVE_PATH: String = "user://save.json"
# v3 — IA-2 collapsed `hero_inventories` (per-hero silos) into a single
# `shared_inventory` array. Migration is implicit: `InventoryManager.from_save_dict`
# accepts either format, flattening v2's nested dict into the flat pool on
# load. No explicit migration step needed in this file.
# v4 — Phase 49 added grid placement (grid_row/col on ItemInstance, footprint
# on ItemBase). Migration is implicit: legacy items deserialize at -1/-1 and
# InventoryManager._reflow_unplaced() lays them onto the grid on load.
const SAVE_VERSION: int = 4

# Phase 48 — monotonic UID counter for ItemInstance. Issued only by
# issue_uid(); persisted in the save file so it survives restarts. Never
# decrement on delete — a sold/salvaged item's UID is retired forever so
# equipped-slot references can't alias to a re-issued id. Cheap either way
# (save size impact is one int).
var next_uid: int = 1


func _ready() -> void:
	load_game()
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.encyclopedia_entry_unlocked.connect(_on_encyclopedia_unlocked)
	print("[SaveManager] loaded — %d levels tracked" % GameState.level_stars.size())


func _on_encyclopedia_unlocked(_content_id: String) -> void:
	save_game()


func _on_level_completed(level_id: String, stars: int, _mode: String) -> void:
	# Record best stars (GameState already did this in record_stars, but
	# belt-and-suspenders — make sure the dictionary is current).
	var prev: int = GameState.level_stars.get(level_id, 0)
	GameState.level_stars[level_id] = maxi(prev, stars)
	# Unlock the next level if this one was cleared with at least 1 star.
	if stars >= 1:
		_try_unlock_next_level(level_id)
	save_game()


func _try_unlock_next_level(_completed_level_id: String) -> void:
	# Simple sequential unlock: find the level with the next unlock_order
	# and mark it unlocked. WorldMap's LevelNodeData carries unlock_order
	# but we don't have that data here at runtime. For now, do nothing
	# extra — only Level1 exists. Phase 29+ will implement the chain by
	# reading a level registry. The save file stores whatever is in
	# levels_unlocked so the data persists regardless.
	pass


func save_game() -> void:
	# 2026-04-29 audit fix — refuse to write while a Test Range run is active.
	# Test Range mutates GameState (tower_slot_cap = 6, 5-tower loadout, etc.)
	# for sandbox convenience; without this guard, any save trigger during
	# Test Range — e.g. encyclopedia_unlocked when a new enemy is first seen —
	# would persist the polluted state to disk. _exit_tree restores in-memory
	# state but can't undo a save that already wrote.
	if GameState.current_mode == "test_range":
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"level_stars": GameState.level_stars,
		"levels_unlocked": GameState.levels_unlocked,
		"purchased_upgrades": GameState.purchased_upgrades,
		"heroic_complete": GameState.heroic_complete,
		"iron_complete": GameState.iron_complete,
		"endless_best_score": GameState.endless_best_score,
		"endless_leaderboard": GameState.endless_leaderboard,
		"encyclopedia_unlocked": GameState.encyclopedia_unlocked,
		"unlocked_content": GameState.unlocked_content,
		"hero_talents": GameState.hero_talents,
		# Phase 47d-2: persisted loadout. Starts at four defaults on a fresh
		# save; survives across sessions so the player's picks stick.
		"selected_hero_id": GameState.selected_hero_id,
		"selected_tower_ids": GameState.selected_tower_ids,
		"tower_slot_cap": GameState.tower_slot_cap,
		# Phase 48 — persistent hero progression + loot.
		"hero_progress": GameState.hero_progress,
		"hero_equipped_skills": GameState.hero_equipped_skills,
		"next_uid": next_uid,
		# Phase 48 level metrics — per-level best time (seconds) + per-level
		# endless high score. Additive; missing keys default to empty dicts.
		"level_best_times": GameState.level_best_times,
		"level_endless_best_scores": GameState.level_endless_best_scores,
		# Persistent inventory-sell currency. Additive — older saves load it
		# as 0 by default. No SAVE_VERSION bump needed since the field is
		# pure-extension; existing keys are untouched.
		"meta_gold": GameState.meta_gold,
	}
	# Merge InventoryManager's own slice — keeps the save dict flat while
	# letting the manager own its shape (to_save_dict / from_save_dict).
	var inv_slice: Dictionary = InventoryManager.to_save_dict()
	for k in inv_slice.keys():
		data[k] = inv_slice[k]
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] cannot open save file for writing: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("[SaveManager] saved — stars=%s" % str(GameState.level_stars))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] no save file found — using defaults")
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[SaveManager] cannot open save file for reading")
		return
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_warning("[SaveManager] save file corrupt (line %d): %s" % [json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		push_warning("[SaveManager] save file root is not a Dictionary")
		return
	# Version check — future phases can branch on version for migration.
	# v1 → v2: additive (hero_progress, next_uid, inventory dicts default to
	#   empty/1). No destructive migration.
	# v2 → v3: hero_inventories silos collapsed into shared_inventory. Migration
	#   is implicit — InventoryManager.from_save_dict reads either shape and
	#   flattens. uid uniqueness is preserved by the monotonic next_uid counter
	#   so no collision risk.
	var version: int = int(data.get("version", 0))
	if version < 1:
		push_warning("[SaveManager] unknown save version %d — ignoring" % version)
		return
	if version > SAVE_VERSION:
		push_warning("[SaveManager] save version %d newer than code %d — continuing" % [version, SAVE_VERSION])
	if version < 3:
		print("[SaveManager] migrating save v%d → v3 (shared_inventory)" % version)
	if version < 4:
		print("[SaveManager] migrating save v%d → v4 (grid placement)" % version)
	# Populate GameState from save data.
	if data.has("level_stars") and data.level_stars is Dictionary:
		# JSON stores keys as strings, values as floats. Convert to int.
		for key in data.level_stars:
			GameState.level_stars[key] = int(data.level_stars[key])
	if data.has("levels_unlocked") and data.levels_unlocked is Dictionary:
		for key in data.levels_unlocked:
			GameState.levels_unlocked[key] = bool(data.levels_unlocked[key])
	if data.has("endless_best_score"):
		GameState.endless_best_score = int(data.endless_best_score)
	if data.has("endless_leaderboard") and data.endless_leaderboard is Array:
		GameState.endless_leaderboard = []
		for entry in data.endless_leaderboard:
			if entry is Dictionary:
				GameState.endless_leaderboard.append(entry)
	if data.has("heroic_complete") and data.heroic_complete is Dictionary:
		for key in data.heroic_complete:
			GameState.heroic_complete[key] = bool(data.heroic_complete[key])
	if data.has("iron_complete") and data.iron_complete is Dictionary:
		for key in data.iron_complete:
			GameState.iron_complete[key] = bool(data.iron_complete[key])
	if data.has("hero_talents") and data.hero_talents is Dictionary:
		GameState.hero_talents = {}
		for hero_id in data.hero_talents:
			var ids: Array = []
			if data.hero_talents[hero_id] is Array:
				for tid in data.hero_talents[hero_id]:
					ids.append(str(tid))
			GameState.hero_talents[hero_id] = ids
	if data.has("unlocked_content") and data.unlocked_content is Array:
		GameState.unlocked_content.clear()
		for id in data.unlocked_content:
			GameState.unlocked_content.append(str(id))
	if data.has("encyclopedia_unlocked") and data.encyclopedia_unlocked is Array:
		GameState.encyclopedia_unlocked.clear()
		for id in data.encyclopedia_unlocked:
			GameState.encyclopedia_unlocked.append(str(id))
	if data.has("purchased_upgrades") and data.purchased_upgrades is Array:
		GameState.purchased_upgrades.clear()
		for id in data.purchased_upgrades:
			GameState.purchased_upgrades.append(str(id))
		# 2026-05-01 spell purge — Spell Mastery upgrade was removed; any save
		# with "spell_mastery" in purchased_upgrades carries a dead string
		# that contributed nothing once the matching effect_type was retired.
		# Drop it on load so the dict converges. The player auto-refunds the
		# 3 stars they spent because rebuild_upgrade_cache no longer counts
		# the cost (matching UpgradeData is gone from the tree).
		if "spell_mastery" in GameState.purchased_upgrades:
			GameState.purchased_upgrades.erase("spell_mastery")
			print("[SaveManager] purged retired upgrade 'spell_mastery' (3★ refunded)")
	# Phase 47d-2: restore loadout state.
	if data.has("selected_hero_id"):
		GameState.selected_hero_id = str(data.selected_hero_id)
	if data.has("tower_slot_cap"):
		GameState.tower_slot_cap = int(data.tower_slot_cap)
	if data.has("selected_tower_ids") and data.selected_tower_ids is Array:
		var restored: Array[String] = []
		for tid in data.selected_tower_ids:
			restored.append(str(tid))
		GameState.selected_tower_ids = restored
	# 2026-04-29 audit fix — repair saves polluted by the prior TestRange leak
	# (cap=6 + 5-tower loadout). Slots 5–6 aren't unlocked through any
	# progression yet, so any cap > 4 is by definition stale state. Force back
	# to 4; the player keeps their 4 chosen towers (truncates extras silently).
	if GameState.tower_slot_cap > 4:
		print("[SaveManager] repairing polluted tower_slot_cap=%d → 4" % GameState.tower_slot_cap)
		GameState.tower_slot_cap = 4
		# Trim selected_tower_ids to the first 4 entries — the player's
		# original picks come back; tower_ice / placeholder entries leaked
		# from TestRange get dropped.
		if GameState.selected_tower_ids.size() > 4:
			GameState.selected_tower_ids = GameState.selected_tower_ids.slice(0, 4)
	# Phase 48 — hero_progress + inventory + UID counter.
	if data.has("hero_progress") and data.hero_progress is Dictionary:
		GameState.hero_progress = {}
		for hero_id in data.hero_progress:
			var entry_in: Variant = data.hero_progress[hero_id]
			if entry_in is Dictionary:
				GameState.hero_progress[hero_id] = {
					"level": int(entry_in.get("level", 1)),
					"xp": int(entry_in.get("xp", 0)),
				}
	if data.has("hero_equipped_skills") and data.hero_equipped_skills is Dictionary:
		GameState.hero_equipped_skills = {}
		for hero_id in data.hero_equipped_skills:
			var arr: Array = []
			if data.hero_equipped_skills[hero_id] is Array:
				for sid in data.hero_equipped_skills[hero_id]:
					arr.append(str(sid))
			GameState.hero_equipped_skills[hero_id] = arr
	if data.has("next_uid"):
		next_uid = int(data.next_uid)
	# Phase Sell — meta-gold (default 0 if save predates this field).
	GameState.meta_gold = int(data.get("meta_gold", 0))
	# Phase 48 — level metrics.
	if data.has("level_best_times") and data.level_best_times is Dictionary:
		GameState.level_best_times = {}
		for key in data.level_best_times:
			GameState.level_best_times[key] = float(data.level_best_times[key])
	if data.has("level_endless_best_scores") and data.level_endless_best_scores is Dictionary:
		GameState.level_endless_best_scores = {}
		for key in data.level_endless_best_scores:
			GameState.level_endless_best_scores[key] = int(data.level_endless_best_scores[key])
	# InventoryManager owns the shape of its fields.
	InventoryManager.from_save_dict(data)
	print("[SaveManager] loaded save v%d — stars=%s upgrades=%d" % [
		version, str(GameState.level_stars), GameState.purchased_upgrades.size(),
	])


# Phase 48 — monotonic UID issuer. Called by LootRoller and
# InventoryManager.ensure_starter_gear. Never decrements; retired UIDs are
# retired forever so equipment-slot strings can't alias.
func issue_uid() -> String:
	var v: int = next_uid
	next_uid += 1
	return "itm_%d" % v


func delete_save() -> void:
	# Player-facing "Reset Progress" path. Wipes the file AND the in-memory
	# state in every autoload that holds player progression — otherwise the
	# next save would re-persist whatever was in memory at delete time.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] save file deleted")
	GameState.reset()
	InventoryManager.reset()
	# Reset the monotonic UID counter so a fresh save starts at itm_1.
	# (UID uniqueness within a session is still preserved — the counter only
	# matters across sessions and it'll just count up again from 1.)
	next_uid = 1
