extends Node

# Phase 27: the ONLY script that reads/writes the save file (Rule #8).
# JSON format at user://save.json. Schema versioned so future phases can
# migrate without breaking old saves.
#
# Initialization order: state autoloads (RunState, LoadoutState,
# MetaProgression) run first (init defaults), then SaveManager._ready()
# loads saved data on top. Autoload registration order in project.godot
# guarantees this.
#
# 2026-05-01 GameState split: state was previously on a single GameState
# autoload. Save format is unchanged — keys remain flat at the JSON top
# level. Only this file's read/write paths split across the three new
# state autoloads.
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

# Forward-only migration chain. Index N migrates v(N+1) → v(N+2). The chain
# is empty today because every prior version transition (v1→v2→v3→v4) was
# implicit-on-load (InventoryManager / spell-purge) — the framework is here
# so the NEXT schema shift is a one-liner: append a Callable that takes
# (data: Dictionary) and mutates in place, then bump SAVE_VERSION.
#
# Test seam: tests overwrite this array with synthetic mutators to exercise
# the chain logic without needing a real schema bump.
var _migrations: Array[Callable] = []

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
	print("[SaveManager] loaded — %d levels tracked" % MetaProgression.level_stars.size())


func _on_encyclopedia_unlocked(_content_id: String) -> void:
	save_game()


func _on_level_completed(level_id: String, stars: int, _mode: String) -> void:
	# Record best stars (MetaProgression already did this in record_stars,
	# but belt-and-suspenders — make sure the dictionary is current).
	var prev: int = MetaProgression.level_stars.get(level_id, 0)
	MetaProgression.level_stars[level_id] = maxi(prev, stars)
	# Unlock the next level if this one was cleared with at least 1 star.
	if stars >= 1:
		_try_unlock_next_level(level_id)
	save_game()


func _try_unlock_next_level(completed_level_id: String) -> void:
	# Sequential unlock by unlock_order: find the LevelNodeData whose order
	# is one higher than the completed level's, and flip its levels_unlocked
	# entry. ContentRegistry.levels is the registry the original stub was
	# waiting for — it carries unlock_order on every LevelNodeData.
	var completed: Resource = ContentRegistry.find_level(completed_level_id)
	if completed == null:
		return
	var next_order: int = int(completed.unlock_order) + 1
	for entry in ContentRegistry.levels:
		if entry == null:
			continue
		if int(entry.unlock_order) == next_order:
			MetaProgression.levels_unlocked[entry.level_id] = true
			# Hand off to WorldMap: it'll play the road-reveal + marker-pop
			# animation on next entry, then clear this field. Persisted so a
			# force-quit between unlock and the visit still triggers the show.
			MetaProgression.pending_unlock_celebration_id = entry.level_id
			return


func save_game() -> void:
	_save_to_path(SAVE_PATH)


# Internal — path-parameterized save primitive. save_game() is the production
# path (writes to user://save.json); tests call this directly with a temp
# path so they don't trample the player's real save. The Test Range guard
# stays here so neither path can persist sandbox state.
func _save_to_path(path: String) -> void:
	# 2026-04-29 audit fix — refuse to write while a Test Range run is active.
	# Test Range mutates LoadoutState (tower_slot_cap = 6, 5-tower loadout, etc.)
	# for sandbox convenience; without this guard, any save trigger during
	# Test Range — e.g. encyclopedia_unlocked when a new enemy is first seen —
	# would persist the polluted state to disk. _exit_tree restores in-memory
	# state but can't undo a save that already wrote.
	if RunState.current_mode == "test_range":
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		# MetaProgression — cross-run state.
		"level_stars": MetaProgression.level_stars,
		"levels_unlocked": MetaProgression.levels_unlocked,
		"purchased_upgrades": MetaProgression.purchased_upgrades,
		"heroic_complete": MetaProgression.heroic_complete,
		"iron_complete": MetaProgression.iron_complete,
		"endless_best_score": MetaProgression.endless_best_score,
		"endless_leaderboard": MetaProgression.endless_leaderboard,
		"encyclopedia_unlocked": MetaProgression.encyclopedia_unlocked,
		"unlocked_content": MetaProgression.unlocked_content,
		"hero_talents": MetaProgression.hero_talents,
		"hero_progress": MetaProgression.hero_progress,
		"level_best_times": MetaProgression.level_best_times,
		"level_endless_best_scores": MetaProgression.level_endless_best_scores,
		# Persistent inventory-sell currency. Additive — older saves load it
		# as 0 by default. No SAVE_VERSION bump needed since the field is
		# pure-extension; existing keys are untouched.
		"meta_gold": MetaProgression.meta_gold,
		"pending_unlock_celebration_id": MetaProgression.pending_unlock_celebration_id,
		# LoadoutState — pre-level picks, persisted across runs.
		"selected_hero_id": LoadoutState.selected_hero_id,
		"selected_tower_ids": LoadoutState.selected_tower_ids,
		"tower_slot_cap": LoadoutState.tower_slot_cap,
		"hero_equipped_skills": LoadoutState.hero_equipped_skills,
		# SaveManager-owned counter.
		"next_uid": next_uid,
		# Stable hash of the authored content set (hero/tower/enemy ids).
		# On load, a mismatch triggers _purge_orphaned_content to drop save
		# refs to content the catalog no longer authors (rename / removal).
		"content_hash": _compute_content_hash(),
	}
	# Merge InventoryManager's own slice — keeps the save dict flat while
	# letting the manager own its shape (to_save_dict / from_save_dict).
	var inv_slice: Dictionary = InventoryManager.to_save_dict()
	for k in inv_slice.keys():
		data[k] = inv_slice[k]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] cannot open save file for writing: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("[SaveManager] saved — stars=%s" % str(MetaProgression.level_stars))


func load_game() -> void:
	_load_from_path(SAVE_PATH)


# Internal — path-parameterized load primitive. load_game() is the production
# path (reads from user://save.json); tests call this directly with a temp
# path that holds whatever fixture they prepared.
func _load_from_path(path: String) -> void:
	if not FileAccess.file_exists(path):
		print("[SaveManager] no save file found — using defaults")
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
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
	# Run the executable migration chain. Today the chain is empty (every
	# prior version transition was implicit-on-load); future schema shifts
	# append a Callable to _migrations and bump SAVE_VERSION.
	if version < SAVE_VERSION:
		_run_migrations(data, version)
	# Drop save references to content the catalog no longer authors. Cheap
	# fast-path: skip when content_hash matches the current registry. Slow
	# path runs the purge explicitly so a removed hero / tower doesn't
	# crash the loader.
	var saved_hash: String = str(data.get("content_hash", ""))
	if saved_hash != _compute_content_hash():
		_purge_orphaned_content(data)
	# ── MetaProgression ───────────────────────────────────────────────
	if data.has("level_stars") and data.level_stars is Dictionary:
		# JSON stores keys as strings, values as floats. Convert to int.
		for key in data.level_stars:
			MetaProgression.level_stars[key] = int(data.level_stars[key])
	if data.has("levels_unlocked") and data.levels_unlocked is Dictionary:
		for key in data.levels_unlocked:
			MetaProgression.levels_unlocked[key] = bool(data.levels_unlocked[key])
	if data.has("endless_best_score"):
		MetaProgression.endless_best_score = int(data.endless_best_score)
	if data.has("endless_leaderboard") and data.endless_leaderboard is Array:
		MetaProgression.endless_leaderboard = []
		for entry in data.endless_leaderboard:
			if entry is Dictionary:
				MetaProgression.endless_leaderboard.append(entry)
	if data.has("heroic_complete") and data.heroic_complete is Dictionary:
		for key in data.heroic_complete:
			MetaProgression.heroic_complete[key] = bool(data.heroic_complete[key])
	if data.has("iron_complete") and data.iron_complete is Dictionary:
		for key in data.iron_complete:
			MetaProgression.iron_complete[key] = bool(data.iron_complete[key])
	if data.has("hero_talents") and data.hero_talents is Dictionary:
		MetaProgression.hero_talents = {}
		for hero_id in data.hero_talents:
			var ids: Array = []
			if data.hero_talents[hero_id] is Array:
				for tid in data.hero_talents[hero_id]:
					ids.append(str(tid))
			MetaProgression.hero_talents[hero_id] = ids
	if data.has("unlocked_content") and data.unlocked_content is Array:
		MetaProgression.unlocked_content.clear()
		for id in data.unlocked_content:
			MetaProgression.unlocked_content.append(str(id))
	if data.has("encyclopedia_unlocked") and data.encyclopedia_unlocked is Array:
		MetaProgression.encyclopedia_unlocked.clear()
		for id in data.encyclopedia_unlocked:
			MetaProgression.encyclopedia_unlocked.append(str(id))
	if data.has("purchased_upgrades") and data.purchased_upgrades is Array:
		MetaProgression.purchased_upgrades.clear()
		for id in data.purchased_upgrades:
			MetaProgression.purchased_upgrades.append(str(id))
		# 2026-05-01 spell purge — Spell Mastery upgrade was removed; any save
		# with "spell_mastery" in purchased_upgrades carries a dead string
		# that contributed nothing once the matching effect_type was retired.
		# Drop it on load so the dict converges. The player auto-refunds the
		# 3 stars they spent because rebuild_upgrade_cache no longer counts
		# the cost (matching UpgradeData is gone from the tree).
		if "spell_mastery" in MetaProgression.purchased_upgrades:
			MetaProgression.purchased_upgrades.erase("spell_mastery")
			print("[SaveManager] purged retired upgrade 'spell_mastery' (3★ refunded)")
	if data.has("hero_progress") and data.hero_progress is Dictionary:
		MetaProgression.hero_progress = {}
		for hero_id in data.hero_progress:
			var entry_in: Variant = data.hero_progress[hero_id]
			if entry_in is Dictionary:
				MetaProgression.hero_progress[hero_id] = {
					"level": int(entry_in.get("level", 1)),
					"xp": int(entry_in.get("xp", 0)),
				}
	# Phase Sell — meta-gold (default 0 if save predates this field).
	MetaProgression.meta_gold = int(data.get("meta_gold", 0))
	# WorldMap unlock celebration handoff (default "" for old saves).
	MetaProgression.pending_unlock_celebration_id = str(data.get("pending_unlock_celebration_id", ""))
	if data.has("level_best_times") and data.level_best_times is Dictionary:
		MetaProgression.level_best_times = {}
		for key in data.level_best_times:
			MetaProgression.level_best_times[key] = float(data.level_best_times[key])
	if data.has("level_endless_best_scores") and data.level_endless_best_scores is Dictionary:
		MetaProgression.level_endless_best_scores = {}
		for key in data.level_endless_best_scores:
			MetaProgression.level_endless_best_scores[key] = int(data.level_endless_best_scores[key])
	# ── LoadoutState ──────────────────────────────────────────────────
	if data.has("selected_hero_id"):
		LoadoutState.selected_hero_id = str(data.selected_hero_id)
	if data.has("tower_slot_cap"):
		LoadoutState.tower_slot_cap = int(data.tower_slot_cap)
	if data.has("selected_tower_ids") and data.selected_tower_ids is Array:
		var restored: Array[String] = []
		for tid in data.selected_tower_ids:
			restored.append(str(tid))
		LoadoutState.selected_tower_ids = restored
	# Self-heal: if every slot in the loaded loadout is empty/unresolvable,
	# restore the 4 default tower_ids. Prevents the build ring from rendering
	# all-padlocks (looks broken to the player) when the save was corrupted
	# by content_hash mismatch, manual edit, or prior TestRange pollution.
	# Conservative threshold — only reset when zero towers are usable; a
	# partial loadout (player intentionally cleared some slots) is preserved.
	var usable_towers: int = 0
	for tid in LoadoutState.selected_tower_ids:
		if tid != "" and ContentRegistry.find_tower(tid) != null and UnlockManager.is_tower_unlocked(tid):
			usable_towers += 1
			break
	if usable_towers == 0:
		print("[SaveManager] loadout has zero usable towers — restoring defaults")
		LoadoutState.reset_loadout_to_default()
	if data.has("hero_equipped_skills") and data.hero_equipped_skills is Dictionary:
		LoadoutState.hero_equipped_skills = {}
		for hero_id in data.hero_equipped_skills:
			var arr: Array = []
			if data.hero_equipped_skills[hero_id] is Array:
				for sid in data.hero_equipped_skills[hero_id]:
					arr.append(str(sid))
			LoadoutState.hero_equipped_skills[hero_id] = arr
	# ── SaveManager-owned ─────────────────────────────────────────────
	if data.has("next_uid"):
		next_uid = int(data.next_uid)
	# InventoryManager owns the shape of its fields.
	InventoryManager.from_save_dict(data)
	print("[SaveManager] loaded save v%d — stars=%s upgrades=%d" % [
		version, str(MetaProgression.level_stars), MetaProgression.purchased_upgrades.size(),
	])


# ── Migration scaffold ──────────────────────────────────────────────────

# Runs every registered migration whose target version is > `from_version`.
# Each Callable mutates `data` in place. Index N migrates v(N+1) → v(N+2),
# so to advance from v3 to current we run migrations starting at index 2.
# `from_version` is 1-based (the version stored in the save file).
func _run_migrations(data: Dictionary, from_version: int) -> void:
	# Start index in _migrations array: position of the first migration that
	# advances PAST the loaded version. _migrations[k] migrates v(k+1)→v(k+2),
	# so to migrate from v=N forward we start at index k=N-1.
	var start_idx: int = max(0, from_version - 1)
	for i in range(start_idx, _migrations.size()):
		var fn: Callable = _migrations[i]
		if not fn.is_valid():
			continue
		print("[SaveManager] migrating save v%d → v%d" % [i + 1, i + 2])
		fn.call(data)


# Stable hash of the content set the registry currently authors. Fast-path:
# if the saved hash matches, the loader skips the orphan purge entirely.
# When content is added/removed/renamed, the hash changes and the purge
# runs. Cheap to compute (~30 string concatenations + one hash).
func _compute_content_hash() -> String:
	var ids: PackedStringArray = PackedStringArray()
	for h in ContentRegistry.heroes:
		if h != null and "hero_id" in h:
			ids.append(h.hero_id)
	for t in ContentRegistry.towers:
		if t != null and "tower_id" in t:
			ids.append(t.tower_id)
	for e in ContentRegistry.enemies:
		if e != null and "enemy_id" in e:
			ids.append(e.enemy_id)
	ids.sort()
	return "|".join(ids).md5_text()


# Drops save-dict references to content_ids the catalog no longer authors.
# Run on load when content_hash mismatch indicates the registry has changed
# since the save was written. Quietly converges the dict — no crash, no
# user-visible warning. Keys we sweep:
#   - selected_hero_id  → "" if hero gone
#   - selected_tower_ids → entry replaced with "" if tower gone
#   - hero_progress / hero_equipped_skills / hero_talents → key removed if
#     the hero_id is gone
func _purge_orphaned_content(data: Dictionary) -> void:
	var hero_ok := func(id: String) -> bool:
		return id != "" and ContentRegistry.find_hero(id) != null
	var tower_ok := func(id: String) -> bool:
		return id != "" and ContentRegistry.find_tower(id) != null
	if data.has("selected_hero_id"):
		var sid: String = str(data.selected_hero_id)
		if sid != "" and not hero_ok.call(sid):
			data["selected_hero_id"] = ""
	if data.has("selected_tower_ids") and data.selected_tower_ids is Array:
		var swept: Array = []
		for tid in data.selected_tower_ids:
			swept.append(str(tid) if tower_ok.call(str(tid)) else "")
		data["selected_tower_ids"] = swept
	for hero_dict_key in ["hero_progress", "hero_equipped_skills", "hero_talents"]:
		if data.has(hero_dict_key) and data[hero_dict_key] is Dictionary:
			var d: Dictionary = data[hero_dict_key]
			for hid in d.keys():
				if not hero_ok.call(str(hid)):
					d.erase(hid)


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
	RunState.reset()
	LoadoutState.reset()
	MetaProgression.reset()
	InventoryManager.reset()
	# Reset the monotonic UID counter so a fresh save starts at itm_1.
	# (UID uniqueness within a session is still preserved — the counter only
	# matters across sessions and it'll just count up again from 1.)
	next_uid = 1
