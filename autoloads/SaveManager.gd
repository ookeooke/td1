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
const SAVE_VERSION: int = 1


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
		# Future phases extend here:
		# "total_stars": computed from level_stars
		# "endless_best_score": int
		# "unlocked_heroes": Array[String]
		# "unlocked_towers": Array[String]
		# "permanent_upgrades": Array[String]
		# "skill_points_spent": Dictionary
		# "encyclopedia_unlocked": Array[String]
		# "iap_purchases": Array[String]
		# "hero_equipment": Dictionary
		# "inventory": Array
	}
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
	var version: int = int(data.get("version", 0))
	if version < 1:
		push_warning("[SaveManager] unknown save version %d — ignoring" % version)
		return
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
	if data.has("encyclopedia_unlocked") and data.encyclopedia_unlocked is Array:
		GameState.encyclopedia_unlocked.clear()
		for id in data.encyclopedia_unlocked:
			GameState.encyclopedia_unlocked.append(str(id))
	if data.has("purchased_upgrades") and data.purchased_upgrades is Array:
		GameState.purchased_upgrades.clear()
		for id in data.purchased_upgrades:
			GameState.purchased_upgrades.append(str(id))
	print("[SaveManager] loaded save v%d — stars=%s upgrades=%d" % [
		version, str(GameState.level_stars), GameState.purchased_upgrades.size(),
	])


func delete_save() -> void:
	# For debug / reset-all. Not exposed to the player yet.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] save file deleted")
	GameState.reset()
