extends Node

const STARTING_GOLD: int = 100
const STARTING_LIVES: int = 20

# Mirrors UpgradeData.EffectType so call sites don't use magic ints.
# Values must match the enum in progression/UpgradeData.gd exactly.
const MOD_ARCHER_DAMAGE: int = 0
const MOD_TOWER_RANGE: int = 1
const MOD_HERO_HEALTH: int = 2
const MOD_HERO_DAMAGE: int = 3
const MOD_HERO_XP: int = 4
# 5 is `_RETIRED_SPELL_COOLDOWN` on UpgradeData.EffectType — slot kept so
# STARTING_GOLD = 6 and SOLDIER_HEALTH = 7 stay at the values existing
# .tres files serialize. Don't fill 5 with a new effect; pick the next
# free integer (8) for additions.
const MOD_STARTING_GOLD: int = 6
const MOD_SOLDIER_HEALTH: int = 7

var gold: int = 0
var lives: int = 0
var score: int = 0
var wave_number: int = 0
var current_mode: String = "campaign"  # "campaign" / "heroic" / "iron" / "endless"
var current_level_id: String = "level_1"
var selected_hero_id: String = "hero_warrior"
var stars_earned: int = 0  # set on victory, 0 otherwise

# Phase 47d-2: tower loadout. The build ring always renders TOWER_SLOT_MAX
# slots; slots beyond `tower_slot_cap` render locked (future progression).
# `selected_tower_ids` is the ORDERED list of up-to-cap tower_ids; missing
# entries = empty slots. Defaults to the four launch towers so an
# uninitialised save still plays correctly.
const TOWER_SLOT_MAX: int = 6
var tower_slot_cap: int = 4
var selected_tower_ids: Array[String] = [
	"tower_archer", "tower_barracks", "tower_mage", "tower_artillery",
]


# Returns the TowerData resources in loadout order for the unlocked slots.
# - Elements beyond `tower_slot_cap` are never returned (player can't use them).
# - Entries referencing a missing/locked tower are skipped (the slot will
#   render empty in the ring).
# - If the filtered list is empty (fresh save on a build with no defaults),
#   falls back to the full set of unlocked towers so the player isn't stuck
#   with a blank build ring.
func get_loadout_towers() -> Array:
	var out: Array = []
	var limit: int = mini(tower_slot_cap, selected_tower_ids.size())
	for i in range(limit):
		var tid: String = selected_tower_ids[i]
		if tid == "":
			continue
		var data: Resource = ContentRegistry.find_tower(tid)
		if data == null:
			continue
		if not UnlockManager.is_tower_unlocked(tid):
			continue
		out.append(data)
	if out.is_empty():
		for data in ContentRegistry.towers:
			if data != null and UnlockManager.is_tower_unlocked(data.tower_id):
				out.append(data)
	return out


# Set a single loadout slot (0 <= slot_idx < tower_slot_cap). If `tower_id`
# is already in another slot, those two slots SWAP to enforce the
# no-duplicates rule without making the player lose a pick. Empty tower_id
# clears the slot. Returns true when state actually changed (so the UI can
# persist / redraw).
func set_loadout_slot(slot_idx: int, tower_id: String) -> bool:
	if slot_idx < 0 or slot_idx >= tower_slot_cap:
		return false
	# Grow the array to cover the slot — preserves sparse positions.
	while selected_tower_ids.size() <= slot_idx:
		selected_tower_ids.append("")
	if tower_id != "":
		var existing: int = selected_tower_ids.find(tower_id)
		if existing == slot_idx:
			return false
		if existing >= 0:
			selected_tower_ids[existing] = selected_tower_ids[slot_idx]
	selected_tower_ids[slot_idx] = tower_id
	return true


func reset_loadout_to_default() -> void:
	selected_tower_ids = [
		"tower_archer", "tower_barracks", "tower_mage", "tower_artillery",
	]

# Progression state — survives level restarts and scene transitions. Only
# cleared by a full `reset()`. SaveManager (Phase 27) will read/write these
# dictionaries on boot / on level-complete.
var level_stars: Dictionary = {"level_1": 0}     # level_id → best campaign star count (0–3)
var levels_unlocked: Dictionary = {"level_1": true}  # level_id → true
# Phase 31: challenge mode completions (per level).
var heroic_complete: Dictionary = {}   # level_id → true
var iron_complete: Dictionary = {}     # level_id → true
var purchased_upgrades: Array[String] = []
var encyclopedia_unlocked: Array[String] = []  # content IDs unlocked by first encounter
var unlocked_content: Array[String] = []       # explicitly unlocked (IAP, star-gate, event)
# Per-hero purchased talents: hero_id → Array[String] of talent_ids.
var hero_talents: Dictionary = {}
var endless_best_score: int = 0
# Persistent meta-currency for the inventory sell loop. Earned by selling
# unwanted items; future Town phases (Buy / Smith) will spend it. Distinct
# from `gold`, which is per-run and resets every level.
var meta_gold: int = 0
# Per-level fastest completion time (campaign mode only). Seconds as float.
# Only wall-time spent in the level is counted; pause doesn't add (Main.gd
# accumulates process_delta which stops during PAUSE_MODE_STOP).
var level_best_times: Dictionary = {}    # level_id -> seconds (float)
# Per-level endless high score. Extension of the single endless_best_score
# so each map's endless mode can be compared independently.
var level_endless_best_scores: Dictionary = {}   # level_id -> int
# Phase 48 — persistent hero XP/level. Keyed by hero_id. Each entry:
# { "level": int, "xp": int }. Previously per-run on BaseHero — migrated here
# so progression survives runs. SaveManager persists the whole dict.
var hero_progress: Dictionary = {}
# Phase 48 — per-hero equipped-skill loadout. Keyed by hero_id; each value
# is Array[String] of length EQUIPPED_SKILL_SLOTS, with "" for empty slots.
# Missing keys fall through to _default_equipped_for() (first N unlocked).
const EQUIPPED_SKILL_SLOTS: int = 2
var hero_equipped_skills: Dictionary = {}
# Local leaderboard — top 20 entries, sorted descending. Each entry:
# { "name": String, "score": int, "wave": int }
# Phase 33 online: replace with HTTP fetch from a leaderboard service.
var endless_leaderboard: Array = []
const LEADERBOARD_MAX_ENTRIES: int = 20

# Phase 46: per-run damage attribution for the Victory/GameOver screen.
# Cleared on reset_for_level() so restarts start fresh. Tower entries are
# keyed by instance_id so sold towers still contribute to the leaderboard.
var round_damage_towers: Dictionary = {}  # int(instance_id) → {"name": String, "total": float}
var round_damage_hero: float = 0.0
var round_damage_soldiers: float = 0.0


func record_round_damage(source: Node, amount: float) -> void:
	# is_instance_valid guards against a freed source — happens when a tower
	# is sold while one of its projectiles is still mid-flight.
	if source == null or not is_instance_valid(source) or amount <= 0.0:
		return
	if source is BaseTower:
		var key: int = source.get_instance_id()
		var entry: Dictionary = round_damage_towers.get(key, {"name": "", "total": 0.0})
		# Refresh display name each hit — tower can upgrade/branch mid-run.
		if source.data != null:
			entry["name"] = "%s L%d" % [source.data.tower_name, source.level]
		entry["total"] = float(entry.get("total", 0.0)) + amount
		round_damage_towers[key] = entry
	elif source is BaseHero:
		round_damage_hero += amount
	elif source is BaseSoldier:
		round_damage_soldiers += amount
	# Environmental damage (none today) would fall through without tallying.


func try_unlock_encyclopedia(content_id: String) -> void:
	if content_id == "" or content_id in encyclopedia_unlocked:
		return
	encyclopedia_unlocked.append(content_id)
	EventBus.encyclopedia_entry_unlocked.emit(content_id)


func compute_endless_score() -> int:
	# Per CLAUDE.md: wave_number × gold × lives multiplier.
	return wave_number * gold * maxi(lives, 1)


func submit_endless_score(player_name: String, final_score: int) -> void:
	var entry: Dictionary = {
		"name": player_name,
		"score": final_score,
		"wave": wave_number,
	}
	endless_leaderboard.append(entry)
	endless_leaderboard.sort_custom(func(a, b): return a.score > b.score)
	if endless_leaderboard.size() > LEADERBOARD_MAX_ENTRIES:
		endless_leaderboard.resize(LEADERBOARD_MAX_ENTRIES)
	EventBus.leaderboard_score_submitted.emit(final_score)


# Phase 48 — best-time tracking. Returns true iff this was a new best
# (either the level had no prior time or the new time is faster).
func try_record_best_time(level_id: String, seconds: float) -> bool:
	if level_id == "" or seconds <= 0.0:
		return false
	var prev: float = float(level_best_times.get(level_id, -1.0))
	if prev < 0.0 or seconds < prev:
		level_best_times[level_id] = seconds
		return true
	return false


func get_best_time(level_id: String) -> float:
	return float(level_best_times.get(level_id, -1.0))


# Per-level endless high score. Returns true iff new best.
func try_record_endless_score(level_id: String, run_score: int) -> bool:
	if level_id == "" or run_score <= 0:
		return false
	var prev: int = int(level_endless_best_scores.get(level_id, 0))
	if run_score > prev:
		level_endless_best_scores[level_id] = run_score
		return true
	return false


func get_endless_best_score(level_id: String) -> int:
	return int(level_endless_best_scores.get(level_id, 0))


# Precomputed modifier cache — rebuilt by rebuild_upgrade_cache() after any
# purchase. Game systems call get_upgrade_multiplier() / get_upgrade_bonus().
var _upgrade_mult_cache: Dictionary = {}   # EffectType (int) → float product
var _upgrade_add_cache: Dictionary = {}    # EffectType (int) → float sum


# Campaign star thresholds per CLAUDE.md:
#   18-20 lives = 3 stars, 6-17 = 2, 1-5 = 1, 0 = defeat (no stars).
func calculate_stars() -> int:
	if lives >= 18:
		return 3
	if lives >= 6:
		return 2
	if lives >= 1:
		return 1
	return 0


func record_stars() -> void:
	# Persist the better of current run vs. previous best into the in-memory
	# progression dictionary. SaveManager will flush this to disk.
	if current_mode == "campaign":
		var prev: int = level_stars.get(current_level_id, 0)
		level_stars[current_level_id] = maxi(prev, stars_earned)
	elif current_mode == "heroic":
		heroic_complete[current_level_id] = true
	elif current_mode == "iron":
		iron_complete[current_level_id] = true


func is_heroic_unlocked(level_id: String) -> bool:
	return level_stars.get(level_id, 0) >= 3


func is_iron_unlocked(level_id: String) -> bool:
	return heroic_complete.get(level_id, false)


func calculate_total_stars_for_level(level_id: String) -> int:
	var total: int = level_stars.get(level_id, 0)  # 0–3 campaign
	if heroic_complete.get(level_id, false):
		total += 1
	if iron_complete.get(level_id, false):
		total += 1
	return total  # 0–5


func get_total_stars() -> int:
	var total: int = 0
	for id in level_stars.keys():
		total += calculate_total_stars_for_level(id)
	return total


func get_spent_stars() -> int:
	# Requires access to UpgradeData costs. Since GameState doesn't hold
	# the upgrade registry, the UpgradeTree scene passes the cost sum
	# here when it loads. For between-scene use, we cache the total cost.
	return _spent_stars_cache


func get_spent_talent_stars() -> int:
	# Caller must pass talent data to compute cost. For simplicity,
	# we iterate all heroes' talents via ContentRegistry.
	var total: int = 0
	for hero_data in ContentRegistry.heroes:
		if hero_data == null or not ("talents" in hero_data):
			continue
		var purchased: Array = hero_talents.get(hero_data.hero_id, [])
		for talent in hero_data.talents:
			if talent != null and talent.talent_id in purchased:
				total += int(talent.star_cost)
	return total


func get_available_stars() -> int:
	return get_total_stars() - get_spent_stars() - get_spent_talent_stars()


var _spent_stars_cache: int = 0


func set_spent_stars_cache(amount: int) -> void:
	_spent_stars_cache = amount


# Modifier API. UpgradeData.EffectType values are used as keys.
# MULT types: product of all purchased (default 1.0).
# BONUS types: sum of all purchased (default 0.0).
func get_upgrade_multiplier(effect_type: int) -> float:
	return _upgrade_mult_cache.get(effect_type, 1.0)


func get_upgrade_bonus(effect_type: int) -> float:
	return _upgrade_add_cache.get(effect_type, 0.0)


func rebuild_upgrade_cache(all_upgrades: Array) -> void:
	_upgrade_mult_cache.clear()
	_upgrade_add_cache.clear()
	var total_cost: int = 0
	for data in all_upgrades:
		if data == null or not (data.upgrade_id in purchased_upgrades):
			continue
		total_cost += int(data.star_cost)
		var etype: int = int(data.effect_type)
		# STARTING_GOLD_BONUS is additive; everything else multiplicative.
		if etype == MOD_STARTING_GOLD:
			_upgrade_add_cache[etype] = _upgrade_add_cache.get(etype, 0.0) + data.effect_value
		else:
			_upgrade_mult_cache[etype] = _upgrade_mult_cache.get(etype, 1.0) * data.effect_value
	_spent_stars_cache = total_cost


func reset_for_level() -> void:
	# Resets per-level volatile state (gold/lives/wave) while preserving
	# cross-level progression (stars, unlocks, level_id, mode). Use this
	# when restarting a level or transitioning from WorldMap to gameplay.
	gold = STARTING_GOLD + int(get_upgrade_bonus(MOD_STARTING_GOLD))
	lives = 1 if current_mode == "iron" else STARTING_LIVES
	score = 0
	wave_number = 0
	stars_earned = 0
	round_damage_towers.clear()
	round_damage_hero = 0.0
	round_damage_soldiers = 0.0


func _ready() -> void:
	reset()
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	# Phase 34: auto-unlock encyclopedia on first encounter.
	EventBus.enemy_spawned.connect(_on_enemy_spawned_for_encyclopedia)
	EventBus.tower_built.connect(_on_tower_built_for_encyclopedia)
	EventBus.hero_spawned.connect(_on_hero_spawned_for_encyclopedia)
	print("[GameState] loaded — gold=%d lives=%d" % [gold, lives])


func _on_enemy_spawned_for_encyclopedia(enemy: Node, _path_id: String) -> void:
	if enemy != null and "data" in enemy and enemy.data != null and "enemy_id" in enemy.data:
		try_unlock_encyclopedia(enemy.data.enemy_id)


func _on_tower_built_for_encyclopedia(tower: Node, _spot_id: String) -> void:
	if tower != null and "data" in tower and tower.data != null:
		try_unlock_encyclopedia(tower.data.tower_id)


func _on_hero_spawned_for_encyclopedia(hero: Node) -> void:
	if hero != null and "data" in hero and hero.data != null:
		try_unlock_encyclopedia(hero.data.hero_id)


func reset() -> void:
	# Clear caches + progression BEFORE reset_for_level() so the gold
	# bonus calc doesn't read stale upgrade data (was granting ghost
	# bonus gold from the prior save).
	current_mode = "campaign"
	current_level_id = "level_1"
	selected_hero_id = "hero_warrior"
	level_stars = {"level_1": 0}
	levels_unlocked = {"level_1": true}
	heroic_complete = {}
	iron_complete = {}
	purchased_upgrades = []
	_upgrade_mult_cache.clear()
	_upgrade_add_cache.clear()
	_spent_stars_cache = 0
	endless_best_score = 0
	endless_leaderboard = []
	meta_gold = 0
	encyclopedia_unlocked = []
	unlocked_content = []
	hero_talents = {}
	# 2026-04-29 audit fix — these were missing, leading to stale state
	# surviving Reset Progress + persisted leakage from TestRange's
	# tower_slot_cap = 6 / 5-tower override.
	tower_slot_cap = 4
	reset_loadout_to_default()  # selected_tower_ids back to the four launch towers
	hero_progress = {}
	hero_equipped_skills = {}
	level_best_times = {}
	level_endless_best_scores = {}
	reset_for_level()  # now reads zeroed caches → correct starting gold


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


func add_meta_gold(amount: int) -> void:
	if amount == 0:
		return
	meta_gold += amount
	EventBus.meta_gold_changed.emit(meta_gold)


func spend_meta_gold(amount: int) -> bool:
	if amount > meta_gold:
		return false
	meta_gold -= amount
	EventBus.meta_gold_changed.emit(meta_gold)
	return true


func lose_lives(amount: int) -> void:
	if amount <= 0:
		return
	lives = maxi(0, lives - amount)
	EventBus.lives_changed.emit(lives)
	if lives <= 0:
		EventBus.game_over.emit()


func _on_enemy_died(_enemy: Node, gold_value: int) -> void:
	add_gold(gold_value)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	lose_lives(lives_lost)


# ── Safe area insets (shared by HUD, SkillBar) ───────────────────────────

# Phase 48 — persistent hero progression helpers. Level-up math lives here
# (not on BaseHero) so XP survives runs. BaseHero reads level/XP on spawn
# and delegates gain_xp back into GameState.add_hero_xp.
func get_hero_level(hero_id: String) -> int:
	if not hero_progress.has(hero_id):
		return 1
	return int(hero_progress[hero_id].get("level", 1))


func get_hero_xp(hero_id: String) -> int:
	if not hero_progress.has(hero_id):
		return 0
	return int(hero_progress[hero_id].get("xp", 0))


func _ensure_hero_progress_entry(hero_id: String) -> void:
	if not hero_progress.has(hero_id):
		hero_progress[hero_id] = {"level": 1, "xp": 0}


func add_hero_xp(hero_id: String, amount: int) -> int:
	# Returns the new level (possibly unchanged). Caller reads hero_progress
	# afterward for the new xp value. Handles multi-level catch-up if amount
	# is huge.
	if hero_id == "" or amount <= 0:
		return get_hero_level(hero_id)
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null:
		return 1
	_ensure_hero_progress_entry(hero_id)
	var entry: Dictionary = hero_progress[hero_id]
	var lvl: int = int(entry.get("level", 1))
	var xp: int = int(entry.get("xp", 0))
	var scaled: int = int(ceil(float(amount) * get_upgrade_multiplier(MOD_HERO_XP)))
	xp += scaled
	EventBus.hero_xp_gained.emit(amount)
	while lvl < hero_data.max_level:
		var idx: int = lvl - 1
		if idx < 0 or idx >= hero_data.xp_per_level.size():
			break
		var needed: int = hero_data.xp_per_level[idx]
		if needed <= 0 or xp < needed:
			break
		xp -= needed
		lvl += 1
		EventBus.hero_leveled_up.emit(lvl)
	if lvl >= hero_data.max_level:
		xp = 0
	entry["level"] = lvl
	entry["xp"] = xp
	return lvl


# Phase 48 — equipped-skills loadout. Skills with level_required > current
# hero level are considered locked and never appear in the loadout.

# Returns the ordered Array[String] of skill_ids slotted for this hero.
# Length is always EQUIPPED_SKILL_SLOTS; "" entries mean empty slot.
# Defaults to the first N unlocked skills in author order on first read.
#
# Self-heals stale entries: any saved skill_id that the hero no longer
# authors (e.g. left over from before a skill rename / removal in a
# content update) is silently dropped to "" on read AND persisted back
# so the dict converges to a clean state. The previous version returned
# the stale string verbatim, which surfaced in HeroesHub's Skills tab as
# raw skill_id text ("rally", "shield_bash") for the equipped row.
func get_equipped_skills(hero_id: String) -> Array[String]:
	# Defense in depth — never cache a default for a malformed hero_id.
	# Without this guard, `WorldMap._refresh_heroes_button_dot` looping
	# over ContentRegistry.heroes could write a "" entry into the save
	# dict if a hero with empty id slipped through.
	if hero_id == "":
		var empty: Array[String] = []
		for _i in EQUIPPED_SKILL_SLOTS:
			empty.append("")
		return empty
	if not hero_equipped_skills.has(hero_id):
		hero_equipped_skills[hero_id] = _default_equipped_for(hero_id)
	var raw: Array = hero_equipped_skills[hero_id]
	var authored: Array[String] = _authored_skill_ids(hero_id)
	var out: Array[String] = []
	var any_purged: bool = false
	for i in EQUIPPED_SKILL_SLOTS:
		var sid: String = str(raw[i]) if i < raw.size() else ""
		# Drop sids the hero no longer authors. Empty authored = ContentRegistry
		# isn't ready yet (e.g. very early boot); skip the purge in that case
		# so we don't wipe a valid loadout while waiting for the registry.
		if sid != "" and not authored.is_empty() and not (sid in authored):
			sid = ""
			any_purged = true
		out.append(sid)
	# Persist the cleaned form so subsequent reads (and the next save)
	# see the converged state rather than re-purging on every call.
	if any_purged or raw.size() != EQUIPPED_SKILL_SLOTS:
		var stored: Array = []
		for s in out:
			stored.append(s)
		hero_equipped_skills[hero_id] = stored
	return out


# All skill_ids the hero authors today (regardless of level_required).
# Used by get_equipped_skills to drop stale entries pointing at skills
# that no longer exist on the hero.
func _authored_skill_ids(hero_id: String) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	for skill in hero_data.skills:
		if skill != null and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Returns all skill_ids on the hero with level_required <= current level.
# Order matches HeroData.skills (author order).
func get_unlocked_skill_ids(hero_id: String) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	var lvl: int = get_hero_level(hero_id)
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr <= lvl and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Same shape as get_unlocked_skill_ids but only the ones unlocked exactly
# at `level` — used by BaseHero._level_up_apply() to fire the unlock toast.
func get_skills_unlocked_at_level(hero_id: String, level: int) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr == level and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Set a single equipped slot. Mirrors set_loadout_slot's swap-on-duplicate
# rule: if `skill_id` is already in another slot, the two slots SWAP so the
# player doesn't lose a pick. Empty `skill_id` clears the slot. Returns
# true if state actually changed (so the UI persists / redraws).
func set_equipped_skill(hero_id: String, slot_idx: int, skill_id: String) -> bool:
	if hero_id == "" or slot_idx < 0 or slot_idx >= EQUIPPED_SKILL_SLOTS:
		return false
	# Reject locked skills — defense in depth; the UI should never offer them.
	if skill_id != "" and not (skill_id in get_unlocked_skill_ids(hero_id)):
		return false
	var current: Array[String] = get_equipped_skills(hero_id)
	# Track the swap source so we can emit a second signal for it. Listeners
	# that track per-slot state (vs full rebuilds) need to know BOTH slots
	# changed when a swap happens.
	var swap_from: int = -1
	if skill_id != "":
		var existing: int = current.find(skill_id)
		if existing == slot_idx:
			return false
		if existing >= 0:
			current[existing] = current[slot_idx]
			swap_from = existing
	current[slot_idx] = skill_id
	# Store back as untyped Array (Godot Dictionary loses Array[String] typing
	# on assignment anyway; get_equipped_skills coerces on read).
	var stored: Array = []
	for s in current:
		stored.append(s)
	hero_equipped_skills[hero_id] = stored
	EventBus.hero_skill_equipped.emit(hero_id, slot_idx, skill_id)
	if swap_from >= 0:
		EventBus.hero_skill_equipped.emit(hero_id, swap_from, current[swap_from])
	return true


# Returns true if the hero has any unlocked skill that isn't currently in
# their equipped loadout. Drives the WorldMap notification dot.
func has_unequipped_skills(hero_id: String) -> bool:
	var equipped: Array[String] = get_equipped_skills(hero_id)
	for sid in get_unlocked_skill_ids(hero_id):
		if not (sid in equipped):
			return true
	return false


func _default_equipped_for(hero_id: String) -> Array:
	# First EQUIPPED_SKILL_SLOTS unlocked skills (author order); pad with "".
	var unlocked: Array[String] = get_unlocked_skill_ids(hero_id)
	var out: Array = []
	for i in EQUIPPED_SKILL_SLOTS:
		out.append(unlocked[i] if i < unlocked.size() else "")
	return out


func get_safe_insets() -> Vector4:
	## Returns Vector4(top, bottom, left, right) in logical viewport pixels.
	## Safe area from DisplayServer is in screen coordinates; we convert to
	## viewport coordinates so UI Controls can use the values directly.
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return Vector4(0, 0, 0, 0)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var win_size: Vector2i = DisplayServer.window_get_size()
	var sx: float = vp_size.x / float(win_size.x) if win_size.x > 0 else 1.0
	var sy: float = vp_size.y / float(win_size.y) if win_size.y > 0 else 1.0
	return Vector4(
		float(safe_rect.position.y) * sy,
		float(screen_size.y - safe_rect.position.y - safe_rect.size.y) * sy,
		float(safe_rect.position.x) * sx,
		float(screen_size.x - safe_rect.position.x - safe_rect.size.x) * sx,
	)
