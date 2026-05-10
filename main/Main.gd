extends Node2D

# Gameplay scene. Spawns the hero dynamically from ContentRegistry +
# LoadoutState.selected_hero_id, then starts waves (campaign or endless).
# Level scene is instanced dynamically in _enter_tree from
# LevelNodeData.scene_path so multi-level support is one .tres edit.

const LEVEL1_WAVES: Resource = preload("res://levels/level1_waves.tres")
const _LEVEL1_SCENE: PackedScene = preload("res://levels/Level1.tscn")
const HERO_TEMPLATE: PackedScene = preload("res://heroes/HeroWarrior.tscn")

# `level` set in _enter_tree; nullable until then. Kept untyped so the
# Level1/Level2/Level3 root types can vary without rebinding.
var level: Node2D = null
@onready var towers: Node2D = $Towers
@onready var hero_input: Node = $HeroInputManager

# Wall-clock timer for best-completion tracking. Uses accumulated process
# delta so PAUSE_MODE_STOP (tactical pause) doesn't inflate the time.
var _level_elapsed: float = 0.0
var _level_done: bool = false


func _enter_tree() -> void:
	# Instance the level scene BEFORE children's _ready runs so TowerPlacer
	# and HeroInputManager resolve their grid_manager / map paths to the
	# right nodes on first lookup. Falls back to Level1.tscn if the
	# LevelNodeData entry is missing scene_path or its load fails — keeps
	# partially-authored stubs (L2/L3/L4) playable until their own .tscn ships.
	var entry: Resource = ContentRegistry.find_level(RunState.current_level_id)
	var scene_path: String = ""
	if entry != null and "scene_path" in entry:
		scene_path = entry.scene_path
	var scene: PackedScene = null
	if scene_path != "":
		scene = load(scene_path)
	if scene == null:
		if scene_path != "":
			push_warning("[Main] level scene_path %s failed to load — falling back to Level1" % scene_path)
		scene = _LEVEL1_SCENE
	level = scene.instantiate()
	add_child(level)
	# Level should be tree-order before TowerPlacer / HeroInputManager so
	# any code paths iterating children (e.g. WaveManager spawn lookups)
	# encounter the level first.
	move_child(level, 0)
	# Wire NodePath properties on TowerPlacer + HeroInputManager BEFORE
	# their _ready fires (children's _ready runs after _enter_tree returns).
	var grid_node: Node = level.get_node_or_null("GridManager")
	if grid_node != null:
		var placer: Node = $TowerPlacer
		var input_mgr: Node = $HeroInputManager
		placer.grid_manager_path = placer.get_path_to(grid_node)
		input_mgr.grid_manager_path = input_mgr.get_path_to(grid_node)
		input_mgr.map_path = input_mgr.get_path_to(level)
	else:
		push_error("[Main] level %s has no GridManager child" % level.name)


func _ready() -> void:
	# Defensive reset of tree-wide state that survives a scene change.
	# PauseMenu / GameOverScreen restart paths already unpause + normalise
	# time_scale before SceneManager.goto, but if any future entry point
	# forgets, the new level would start frozen with no Send-Wave button
	# (the pre-W1 polling depends on Engine.time_scale-aware deltas). These
	# two lines are idempotent on a fresh boot — costs nothing, closes the
	# class of bug.
	get_tree().paused = false
	Engine.time_scale = 1.0
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)

	_spawn_hero()

	if RunState.current_mode == "endless":
		WaveManager.start_endless(level)
	else:
		# Look up wave_list_path AND early_call_window for this level from
		# level_list.tres so the Send-Wave button is bounded per the level's
		# authored design and the right waves play.
		var entry: Resource = _resolve_level_entry()
		var wave_list: Resource = _resolve_wave_list(entry)
		var early_call: float = entry.early_call_window_sec if entry != null else 10.0
		var gold_per_sec: float = 1.0
		if entry != null and "early_call_gold_per_sec" in entry:
			gold_per_sec = float(entry.early_call_gold_per_sec)
		WaveManager.start(wave_list, level, early_call, gold_per_sec)


# Find the LevelNodeData matching RunState.current_level_id. Returns null
# if no entry matches. Routed through ContentRegistry — single source of
# truth, future-proof against per-world file splits.
func _resolve_level_entry() -> Resource:
	return ContentRegistry.find_level(RunState.current_level_id)


# Load the wave_list resource for the current level. Falls back to L1's
# baked-in waves if the entry has no wave_list_path or the load fails —
# keeps existing behavior unchanged when LevelNodeData is partially authored.
func _resolve_wave_list(entry: Resource) -> Resource:
	if entry == null or entry.wave_list_path == "":
		return LEVEL1_WAVES
	var loaded: Resource = load(entry.wave_list_path)
	if loaded == null:
		push_warning("[Main] wave_list_path %s failed to load — falling back to L1" % entry.wave_list_path)
		return LEVEL1_WAVES
	return loaded


func _process(delta: float) -> void:
	if _level_done:
		return
	# Ticks only while unpaused (PROCESS_MODE_INHERIT default means we stop
	# during tactical pause — matches what the player "feels" as level time).
	_level_elapsed += delta


func _spawn_hero() -> void:
	# Look up the selected hero data from ContentRegistry. Fall back to
	# first registered hero if the ID isn't found.
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null and ContentRegistry.heroes.size() > 0:
		hero_data = ContentRegistry.heroes[0]
	if hero_data == null:
		push_warning("[Main] no hero data found for '%s'" % LoadoutState.selected_hero_id)
		return
	# Phase 48 — first-boot: grant + auto-equip starter gear before the hero
	# node reads InventoryManager.get_all_equipped in _ready. No-op if this
	# hero was already granted in a prior run.
	InventoryManager.ensure_starter_gear(hero_data.hero_id)
	# Instantiate the template scene and override its data with the
	# selected hero's resource. The scene structure (CharacterBody2D +
	# AttackRange) is hero-agnostic — only the data differs.
	var hero: Node = HERO_TEMPLATE.instantiate()
	hero.data = hero_data
	# Level may expose an editor-placed HeroSpawn marker; fall back to
	# viewport center so levels that haven't added the marker still work.
	if level != null and level.has_method("get_hero_spawn_position"):
		hero.position = level.get_hero_spawn_position()
	else:
		hero.position = Vector2(960, 540)
	# Insert before HeroInputManager so tree-order for _unhandled_input
	# is correct (hero selection before move commands).
	add_child(hero)
	move_child(hero, hero_input.get_index())
	# Wire HeroInputManager to the dynamically spawned hero.
	hero_input._hero = hero


func _on_hero_spawned(hero: Node) -> void:
	print("[Main] hero spawned — %s @ %s" % [hero.data.hero_name if hero.data != null else "?", hero.global_position])


func _on_hero_died() -> void:
	print("[Main] hero died")


func _on_wave_started(wave_number: int, path_ids: Array) -> void:
	print("[Main] wave %d started — paths=%s" % [wave_number, path_ids])


func _on_wave_completed(wave_number: int) -> void:
	print("[Main] wave %d cleared" % wave_number)


func _on_all_waves_completed() -> void:
	_level_done = true
	# Campaign only — endless doesn't end this way, so best-time is
	# meaningless there (score/wave is tracked instead).
	if RunState.current_mode == "campaign":
		var is_new_best: bool = MetaProgression.try_record_best_time(
			RunState.current_level_id, _level_elapsed
		)
		if is_new_best:
			print("[Main] new best time on %s: %.2fs" % [RunState.current_level_id, _level_elapsed])
		else:
			print("[Main] completed %s in %.2fs (prev best: %.2fs)" % [
				RunState.current_level_id, _level_elapsed,
				MetaProgression.get_best_time(RunState.current_level_id),
			])
	print("[Main] VICTORY — all waves cleared")
