extends Node

const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")

# Per-run volatile state. Wiped by reset_for_level() on every level entry
# and by SaveManager.delete_save() on Reset Progress.
#
# Holds: in-level economy (gold/lives/score), wave counter, run identity
# (current_mode/level_id), per-run damage attribution. All UI hooks for these
# go through EventBus signals, not direct reads.
#
# Cross-domain reads:
#   - reset_for_level() reads MetaProgression.get_upgrade_bonus(MOD_STARTING_GOLD)
#     to apply the meta-upgrade gold bonus on level start.
#   - compute_endless_score() is read by GameOverScreen which then passes the
#     result to MetaProgression.submit_endless_score (no MetaProgression read
#     here).

const STARTING_GOLD: int = 100
const STARTING_LIVES: int = 20

var gold: int = 0
var lives: int = 0
var score: int = 0
var wave_number: int = 0
var current_mode: String = "campaign"  # "campaign" / "heroic" / "iron" / "endless" / "test_range"
var current_level_id: String = "level_1"
var stars_earned: int = 0  # set on victory, 0 otherwise

# Phase 46 — per-run damage attribution for the Victory/GameOver screen.
# Cleared on reset_for_level() so restarts start fresh. Tower entries are
# keyed by instance_id so sold towers still contribute to the leaderboard.
var round_damage_towers: Dictionary = {}  # int(instance_id) → {"name": String, "total": float}
var round_damage_hero: float = 0.0
var round_damage_soldiers: float = 0.0

# Per-run hero progression recap — drives the GameOverScreen "Hero progression"
# section. `round_xp_gained` is the total scaled XP credited this run (post
# MOD_HERO_XP). `round_hero_start_level` is the hero's level at level-entry,
# so the screen can show "Lv 3 → Lv 5" deltas. Both reset in reset_for_level.
var round_xp_gained: int = 0
var round_hero_start_level: int = 1


func _ready() -> void:
	reset_for_level()
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	print("[RunState] loaded — gold=%d lives=%d" % [gold, lives])


func reset_for_level() -> void:
	# Resets per-level volatile state (gold/lives/wave) while preserving
	# cross-level progression (stars, unlocks, level_id, mode). Use this
	# when restarting a level or transitioning from WorldMap to gameplay.
	gold = STARTING_GOLD + int(MetaProgression.get_upgrade_bonus(MetaProgression.MOD_STARTING_GOLD))
	# Debug-only balance override (BalanceOverrides). No-op in production.
	gold += BalanceOverrides.get_starting_gold_add()
	lives = 1 if current_mode == "iron" else STARTING_LIVES
	# Authored per-level starting gold — REPLACES the computed value when
	# the level designer pinned a specific number via Bake. Resolution chain:
	#   debug slider override > LevelNodeData.starting_gold > baseline above.
	if current_level_id != "":
		var lvl_data: Resource = ContentRegistry.find_level(current_level_id)
		if lvl_data != null and "starting_gold" in lvl_data and int(lvl_data.starting_gold) >= 0:
			gold = int(lvl_data.starting_gold)
	# Debug-only per-level overrides — REPLACE the computed values when
	# present (sentinel -1 means "no override"). No-op in production.
	if current_level_id != "":
		var lvl_gold: int = BalanceOverrides.get_level_int(current_level_id, "starting_gold", -1)
		if lvl_gold >= 0:
			gold = lvl_gold
		var lvl_lives: int = BalanceOverrides.get_level_int(current_level_id, "starting_lives", -1)
		if lvl_lives >= 0:
			lives = lvl_lives
	score = 0
	wave_number = 0
	stars_earned = 0
	round_damage_towers.clear()
	round_damage_hero = 0.0
	round_damage_soldiers = 0.0
	round_xp_gained = 0
	# Snapshot the selected hero's level at level-entry so the GameOverScreen
	# recap can render "Lv 3 → Lv 5". Falls back to 1 if MetaProgression /
	# LoadoutState aren't ready yet (early-boot reset).
	round_hero_start_level = 1
	if has_node("/root/MetaProgression") and has_node("/root/LoadoutState"):
		var hid: String = LoadoutState.selected_hero_id
		if hid != "":
			round_hero_start_level = MetaProgression.get_hero_level(hid)


func reset() -> void:
	# Full wipe — called from Reset Progress. Restores to "campaign / level_1"
	# default identity AND clears volatile vars.
	current_mode = "campaign"
	current_level_id = "level_1"
	reset_for_level()


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


func record_round_xp(amount: int) -> void:
	# Called by MetaProgression.add_hero_xp after scaling. Tracks the per-run
	# total so the GameOverScreen can render "+450 XP earned" alongside the
	# damage breakdown. Reset to 0 in reset_for_level so a restart counts fresh.
	if amount <= 0:
		return
	round_xp_gained += amount


func record_round_damage(source: Node, amount: float) -> void:
	# is_instance_valid guards against a freed source — happens when a tower
	# is sold while one of its projectiles is still mid-flight.
	if source == null or not is_instance_valid(source) or amount <= 0.0:
		return
	if source is BaseTower:
		var key: int = source.get_instance_id()
		var entry: Dictionary = round_damage_towers.get(key, {
			"name": "", "tower_id": "", "level": 1, "branch_idx": -1, "total": 0.0,
		})
		# Refresh per-hit so upgrade / branch choice mid-run is reflected. Branch
		# towers display under their branch upgrade_name (e.g. "Archmage") so the
		# Mage L3 Archmage / Necromancer split is preserved in run_stats.json.
		if source.data != null:
			entry["tower_id"] = source.data.tower_id
			entry["level"] = source.level
			entry["branch_idx"] = source.branch_idx
			var display_name: String = "%s L%d" % [source.data.tower_name, source.level]
			if source.branch_idx >= 0 \
					and source.data.level_3_branches != null \
					and source.branch_idx < source.data.level_3_branches.size():
				var branch: Resource = source.data.level_3_branches[source.branch_idx]
				if branch != null and "upgrade_name" in branch and String(branch.upgrade_name) != "":
					display_name = String(branch.upgrade_name)
			entry["name"] = display_name
		entry["total"] = float(entry.get("total", 0.0)) + amount
		round_damage_towers[key] = entry
	elif source is BaseHero:
		round_damage_hero += amount
	elif source is BaseSoldier:
		round_damage_soldiers += amount
	# Environmental damage (none today) would fall through without tallying.


func compute_endless_score() -> int:
	# Per CLAUDE.md: wave_number × gold × lives multiplier.
	return wave_number * gold * maxi(lives, 1)


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


func _on_enemy_died(_enemy: Node, gold_value: int) -> void:
	add_gold(gold_value)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	lose_lives(lives_lost)
