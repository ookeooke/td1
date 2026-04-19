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
const MOD_SPELL_COOLDOWN: int = 5
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
var round_damage_spells: float = 0.0


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
	elif source is SpellPanel:
		round_damage_spells += amount
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
	round_damage_spells = 0.0


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
	encyclopedia_unlocked = []
	unlocked_content = []
	hero_talents = {}
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


# ── Safe area insets (shared by HUD, SkillBar, SpellPanel) ───────────────

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
