extends Node2D

# Test Range — dev-only sandbox for measuring tower DPS / kit behavior in
# isolation. Mirrors Main.gd's structure (hero spawn, tower system wiring)
# but skips WaveManager.start. Spawns enemies on demand via DevPanel.
#
# Sits under balance/test_range/ — the entire balance/ folder is stripped
# via export-preset filter before shipping. See BALANCE.md.

const HERO_TEMPLATE: PackedScene = preload("res://heroes/HeroWarrior.tscn")

const STREAM_INTERVAL: float = 0.4

# Dev-panel registry — populated at _ready by scanning res://enemies/ for
# .tscn files and reading each instance's data.enemy_id. Mirrors the
# "everything flexible" CORE RULE 22 spirit: a new enemy authored as a
# .tres + .tscn appears in the Test Range dropdown automatically with zero
# code edits to this file. Was previously hardcoded (5 enemies + boss),
# which silently hid every new enemy from the sandbox (Brute, Goblin
# Archer + the 4 new ranged variants all missed the dropdown).
const _EnemyClassRegistry := preload("res://enemies/EnemyClassRegistry.gd")
var _enemy_entries: Array = []   # [{id, name, scene, rank}, ...] in dropdown order

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


func _exit_tree() -> void:
	# Restore everything we mutated in _ready. Any save_game() called after
	# this point sees the original loadout, so the sandbox never leaks.
	LoadoutState.tower_slot_cap = _saved_tower_slot_cap
	LoadoutState.selected_tower_ids = _saved_selected_tower_ids
	RunState.current_mode = _saved_current_mode
	RunState.current_level_id = _saved_current_level_id


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
	_discover_enemy_scenes()
	enemy_dropdown.clear()
	for entry in _enemy_entries:
		enemy_dropdown.add_item(String(entry.name))
	spawn_one_btn.pressed.connect(_on_spawn_one)
	spawn_pack_btn.pressed.connect(_on_spawn_pack)
	reset_stats_btn.pressed.connect(_on_reset_stats)
	stream_check.toggled.connect(_on_stream_toggled)


# Scan res://enemies/ (and res://enemies/bosses/) for .tscn files, peek at
# each instance's `data.enemy_id` + `data.enemy_name`, and build the
# dropdown registry sorted by EnemyClassRegistry progression order so basics
# come first and bosses last. Heavy-ish — one brief instantiate per .tscn —
# but only runs once per Test Range entry and the dev panel is the only
# consumer. Drop a new enemy .tscn into res://enemies/ and it shows up
# automatically on the next Test Range open.
func _discover_enemy_scenes() -> void:
	_enemy_entries.clear()
	for dir_path in ["res://enemies/", "res://enemies/bosses/"]:
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".tscn"):
				continue
			var ps: PackedScene = load(dir_path + f)
			if ps == null:
				continue
			var inst: Node = ps.instantiate()
			var ed: Resource = inst.get("data") if "data" in inst else null
			var eid: String = String(ed.enemy_id) if ed != null and "enemy_id" in ed else ""
			var ename: String = String(ed.enemy_name) if ed != null and "enemy_name" in ed and String(ed.enemy_name) != "" else f.get_basename()
			inst.queue_free()
			if eid == "":
				continue
			var class_key: String = _EnemyClassRegistry.class_key_for_safe(eid)
			_enemy_entries.append({
				"id": eid,
				"name": ename,
				"scene": ps,
				"rank": _EnemyClassRegistry.progression_rank(class_key),
			})
	# Sort by progression rank (basics first, boss last); ties keep load order.
	_enemy_entries.sort_custom(func(a, b): return int(a.rank) < int(b.rank))


func _selected_enemy_scene() -> PackedScene:
	if _enemy_entries.is_empty():
		return null
	var idx: int = clampi(enemy_dropdown.selected, 0, _enemy_entries.size() - 1)
	return _enemy_entries[idx].scene


func _spawn_one() -> void:
	var path: Path2D = level.get_default_spawn_path()
	if path == null:
		push_warning("[TestRange] no spawn path")
		return
	var scene: PackedScene = _selected_enemy_scene()
	if scene == null:
		push_warning("[TestRange] no enemy scene selected")
		return
	WaveManager.spawn_enemy(path, "left", scene)


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
