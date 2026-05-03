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
	score = 0
	wave_number = 0
	stars_earned = 0
	round_damage_towers.clear()
	round_damage_hero = 0.0
	round_damage_soldiers = 0.0


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
