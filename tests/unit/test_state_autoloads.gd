extends GutTest

# RunState + LoadoutState core surface. These pin invariants the GameState
# split established (2026-05-01): per-level volatile state cleared by
# reset_for_level(), damage attribution routes by source class, freed
# sources don't crash the tally, and the tower-loadout swap rule.

var _saved_gold: int
var _saved_lives: int
var _saved_wave: int
var _saved_mode: String
var _saved_round_damage_towers: Dictionary
var _saved_round_damage_hero: float
var _saved_round_damage_soldiers: float
var _saved_selected_tower_ids: Array[String]
var _saved_tower_slot_cap: int
var _spawned: Array[Node] = []


func before_each() -> void:
	_saved_gold = RunState.gold
	_saved_lives = RunState.lives
	_saved_wave = RunState.wave_number
	_saved_mode = RunState.current_mode
	_saved_round_damage_towers = RunState.round_damage_towers.duplicate(true)
	_saved_round_damage_hero = RunState.round_damage_hero
	_saved_round_damage_soldiers = RunState.round_damage_soldiers
	_saved_selected_tower_ids = LoadoutState.selected_tower_ids.duplicate()
	_saved_tower_slot_cap = LoadoutState.tower_slot_cap


func after_each() -> void:
	RunState.gold = _saved_gold
	RunState.lives = _saved_lives
	RunState.wave_number = _saved_wave
	RunState.current_mode = _saved_mode
	RunState.round_damage_towers = _saved_round_damage_towers
	RunState.round_damage_hero = _saved_round_damage_hero
	RunState.round_damage_soldiers = _saved_round_damage_soldiers
	LoadoutState.selected_tower_ids = _saved_selected_tower_ids
	LoadoutState.tower_slot_cap = _saved_tower_slot_cap
	# Synchronous free — these nodes aren't parented to any tree, and
	# queue_free defers past GUT's orphan check.
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _track(n: Node) -> Node:
	_spawned.append(n)
	return n


func test_runstate_reset_for_level_clears_volatile() -> void:
	RunState.current_mode = "campaign"
	RunState.gold = 5
	RunState.lives = 3
	RunState.wave_number = 7
	RunState.stars_earned = 2
	RunState.round_damage_hero = 100.0
	RunState.round_damage_soldiers = 50.0
	RunState.round_damage_towers = {123: {"name": "x", "total": 1.0}}

	RunState.reset_for_level()

	# campaign mode → STARTING_LIVES (20) before any upgrade bonus.
	assert_eq(RunState.lives, RunState.STARTING_LIVES)
	# gold = STARTING_GOLD + meta-upgrade bonus (0 in tests since no upgrades purchased).
	assert_true(RunState.gold >= RunState.STARTING_GOLD,
		"gold must be at least STARTING_GOLD after reset")
	assert_eq(RunState.wave_number, 0)
	assert_eq(RunState.stars_earned, 0)
	assert_eq(RunState.round_damage_hero, 0.0)
	assert_eq(RunState.round_damage_soldiers, 0.0)
	assert_true(RunState.round_damage_towers.is_empty())


func test_runstate_record_round_damage_routes_by_source_class() -> void:
	RunState.round_damage_towers = {}
	RunState.round_damage_hero = 0.0
	RunState.round_damage_soldiers = 0.0

	var tower: BaseTower = _track(BaseTower.new())
	var hero: BaseHero = _track(BaseHero.new())
	var sold: BaseSoldier = _track(BaseSoldier.new())

	RunState.record_round_damage(tower, 25.0)
	RunState.record_round_damage(hero, 7.0)
	RunState.record_round_damage(sold, 13.0)

	assert_eq(RunState.round_damage_hero, 7.0, "hero damage routed")
	assert_eq(RunState.round_damage_soldiers, 13.0, "soldier damage routed")
	assert_eq(RunState.round_damage_towers.size(), 1, "tower entry created")
	var entry: Dictionary = RunState.round_damage_towers[tower.get_instance_id()]
	assert_almost_eq(float(entry["total"]), 25.0, 0.001)


func test_runstate_null_source_safely_ignored() -> void:
	# Null source short-circuits without crashing or adding a tally.
	# (Freed-but-non-null sources are caught at Godot's typed-parameter
	# boundary before reaching the function body, so the in-function
	# `is_instance_valid` is purely defensive — null is the testable path.)
	RunState.round_damage_towers = {}
	RunState.round_damage_hero = 0.0
	RunState.record_round_damage(null, 100.0)
	assert_true(RunState.round_damage_towers.is_empty(),
		"null source must not produce a tally entry")
	assert_eq(RunState.round_damage_hero, 0.0)
	# Zero / negative amounts also short-circuit.
	var tower: BaseTower = _track(BaseTower.new())
	RunState.record_round_damage(tower, 0.0)
	RunState.record_round_damage(tower, -10.0)
	assert_true(RunState.round_damage_towers.is_empty(),
		"zero / negative amounts must not produce a tally entry")


func test_loadoutstate_set_loadout_slot_swaps_to_avoid_duplicates() -> void:
	# Setup: cap=4, ids = [archer, mage, barracks, artillery]. Putting "mage"
	# into slot 0 must SWAP slot 0 ↔ slot 1 instead of creating a duplicate
	# (which would make slot 1 invisibly identical to slot 0).
	LoadoutState.tower_slot_cap = 4
	LoadoutState.selected_tower_ids = ["tower_archer", "tower_mage", "tower_barracks", "tower_artillery"]

	var changed: bool = LoadoutState.set_loadout_slot(0, "tower_mage")

	assert_true(changed, "swap must report state changed")
	assert_eq(LoadoutState.selected_tower_ids[0], "tower_mage")
	assert_eq(LoadoutState.selected_tower_ids[1], "tower_archer", "swap-from must hold the displaced id")
	assert_eq(LoadoutState.selected_tower_ids[2], "tower_barracks")
	# No-op when target slot already holds the same id.
	assert_false(LoadoutState.set_loadout_slot(0, "tower_mage"),
		"setting a slot to its current value reports no change")


func test_loadoutstate_get_loadout_towers_respects_cap() -> void:
	# Cap of 2 should return at most 2 towers. Empty entries skipped.
	LoadoutState.tower_slot_cap = 2
	LoadoutState.selected_tower_ids = ["tower_archer", "tower_mage", "tower_barracks", "tower_artillery"]
	var loadout: Array = LoadoutState.get_loadout_towers()
	assert_eq(loadout.size(), 2, "cap=2 returns exactly 2 entries")
	# Cap of 4 with one empty slot returns 3.
	LoadoutState.tower_slot_cap = 4
	LoadoutState.selected_tower_ids = ["tower_archer", "", "tower_barracks", "tower_artillery"]
	loadout = LoadoutState.get_loadout_towers()
	assert_eq(loadout.size(), 3, "empty slots are skipped, not nullified")
