extends Node2D

# Test Range — dev-only sandbox for measuring tower DPS / kit behavior in
# isolation. Mirrors Main.gd's structure (hero spawn, tower system wiring)
# but skips WaveManager.start. Spawns enemies on demand via DevPanel.
#
# Sits under balance/test_range/ — the entire balance/ folder is stripped
# via export-preset filter before shipping. See BALANCE.md.

const HERO_TEMPLATE: PackedScene = preload("res://heroes/HeroWarrior.tscn")
const ENEMY_BASIC: PackedScene = preload("res://enemies/EnemyBasic.tscn")
const ENEMY_FLYING: PackedScene = preload("res://enemies/EnemyFlying.tscn")
const ENEMY_ARMORED: PackedScene = preload("res://enemies/EnemyArmored.tscn")
const ENEMY_SCOUT: PackedScene = preload("res://enemies/EnemyScout.tscn")
const ENEMY_HEALER: PackedScene = preload("res://enemies/EnemyHealer.tscn")
const ENEMY_BOSS: PackedScene = preload("res://enemies/bosses/Boss1.tscn")

const STREAM_INTERVAL: float = 0.4

@onready var level: Node2D = $TestRangeMap
@onready var hero_input: Node = $HeroInputManager
@onready var enemy_dropdown: OptionButton = $DevPanel/Margin/VBox/EnemyDropdown
@onready var stream_check: CheckBox = $DevPanel/Margin/VBox/StreamCheck
@onready var stats_label: Label = $DevPanel/Margin/VBox/StatsLabel
@onready var spawn_one_btn: Button = $DevPanel/Margin/VBox/SpawnOneBtn
@onready var spawn_pack_btn: Button = $DevPanel/Margin/VBox/SpawnPackBtn
@onready var reset_stats_btn: Button = $DevPanel/Margin/VBox/ResetStatsBtn

var _stream_timer: Timer
var _refresh_timer: Timer

# 2026-04-29 audit fix — capture-and-restore for the LoadoutState/RunState fields this
# scene mutates. Without this, exiting Test Range left the player with
# tower_slot_cap = 6 and a 5-tower loadout permanently leaked into their
# save (any subsequent save_game() call would persist it). See _exit_tree.
var _saved_tower_slot_cap: int = 4
var _saved_selected_tower_ids: Array[String] = []
var _saved_current_mode: String = "campaign"
var _saved_current_level_id: String = "level_1"


func _ready() -> void:
	# Snapshot whatever the player had before we trash LoadoutState/RunState for sandbox
	# convenience. _exit_tree restores; sandbox state never reaches the save.
	_saved_tower_slot_cap = LoadoutState.tower_slot_cap
	_saved_selected_tower_ids = LoadoutState.selected_tower_ids.duplicate()
	_saved_current_mode = RunState.current_mode
	_saved_current_level_id = RunState.current_level_id

	# Signal current_mode so other systems (RunStats, GameOverScreen) don't
	# treat this run as a campaign attempt.
	RunState.current_mode = "test_range"
	RunState.current_level_id = "test_range"
	RunState.gold = 9999
	RunState.lives = 999
	EventBus.gold_changed.emit(RunState.gold)
	EventBus.lives_changed.emit(RunState.lives)
	# Round-damage tally is the source of truth for the stats overlay.
	RunState.round_damage_towers.clear()
	RunState.round_damage_hero = 0.0
	RunState.round_damage_soldiers = 0.0
	# Test Range gets all 5 towers in the build ring so the tester can probe
	# any combination. Restored by _exit_tree on scene exit.
	LoadoutState.tower_slot_cap = 6
	LoadoutState.selected_tower_ids = [
		"tower_archer", "tower_barracks", "tower_mage",
		"tower_artillery", "tower_ice", "",
	]


func _exit_tree() -> void:
	# Restore everything we mutated in _ready. Any save_game() called after
	# this point sees the original loadout, so the sandbox never leaks.
	LoadoutState.tower_slot_cap = _saved_tower_slot_cap
	LoadoutState.selected_tower_ids = _saved_selected_tower_ids
	RunState.current_mode = _saved_current_mode
	RunState.current_level_id = _saved_current_level_id

	_spawn_hero()
	_setup_dev_panel()

	_stream_timer = Timer.new()
	_stream_timer.wait_time = STREAM_INTERVAL
	_stream_timer.timeout.connect(_on_stream_tick)
	add_child(_stream_timer)

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.25
	_refresh_timer.timeout.connect(_refresh_stats)
	_refresh_timer.autostart = true
	add_child(_refresh_timer)


func _spawn_hero() -> void:
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null and ContentRegistry.heroes.size() > 0:
		hero_data = ContentRegistry.heroes[0]
	if hero_data == null:
		push_warning("[TestRange] no hero data found")
		return
	InventoryManager.ensure_starter_gear(hero_data.hero_id)
	var hero: Node = HERO_TEMPLATE.instantiate()
	hero.data = hero_data
	hero.position = level.get_hero_spawn_position() if level != null else Vector2(960, 540)
	add_child(hero)
	move_child(hero, hero_input.get_index())
	hero_input._hero = hero


func _setup_dev_panel() -> void:
	enemy_dropdown.clear()
	enemy_dropdown.add_item("Basic Orc")
	enemy_dropdown.add_item("Flying Harpy")
	enemy_dropdown.add_item("Armored Orc")
	enemy_dropdown.add_item("Goblin Scout")
	enemy_dropdown.add_item("Healer Shaman")
	enemy_dropdown.add_item("Boss")
	spawn_one_btn.pressed.connect(_on_spawn_one)
	spawn_pack_btn.pressed.connect(_on_spawn_pack)
	reset_stats_btn.pressed.connect(_on_reset_stats)
	stream_check.toggled.connect(_on_stream_toggled)


func _selected_enemy_scene() -> PackedScene:
	match enemy_dropdown.selected:
		0: return ENEMY_BASIC
		1: return ENEMY_FLYING
		2: return ENEMY_ARMORED
		3: return ENEMY_SCOUT
		4: return ENEMY_HEALER
		5: return ENEMY_BOSS
		_: return ENEMY_BASIC


func _spawn_one() -> void:
	var path: Path2D = level.get_default_spawn_path()
	if path == null:
		push_warning("[TestRange] no spawn path")
		return
	WaveManager.spawn_enemy(path, "left", _selected_enemy_scene())


func _on_spawn_one() -> void:
	_spawn_one()


func _on_spawn_pack() -> void:
	# Five staggered spawns over ~1.25s to mimic a clump.
	for i in 5:
		_spawn_one()
		await get_tree().create_timer(0.25).timeout


func _on_stream_toggled(on: bool) -> void:
	if on:
		_stream_timer.start()
	else:
		_stream_timer.stop()


func _on_stream_tick() -> void:
	_spawn_one()


func _on_reset_stats() -> void:
	RunState.round_damage_towers.clear()
	RunState.round_damage_hero = 0.0
	RunState.round_damage_soldiers = 0.0
	_refresh_stats()


func _refresh_stats() -> void:
	if stats_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[per-tower damage]")
	if RunState.round_damage_towers.is_empty():
		lines.append("  (none yet — place a tower & spawn enemies)")
	else:
		for key in RunState.round_damage_towers:
			var e: Dictionary = RunState.round_damage_towers[key]
			lines.append("  %s: %d" % [e.get("name", "?"), int(e.get("total", 0.0))])
	if RunState.round_damage_hero > 0.0:
		lines.append("  Hero: %d" % int(RunState.round_damage_hero))
	if RunState.round_damage_soldiers > 0.0:
		lines.append("  Soldiers: %d" % int(RunState.round_damage_soldiers))
	stats_label.text = "\n".join(lines)
