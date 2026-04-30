extends Node2D

# Gameplay scene. Spawns the hero dynamically from ContentRegistry +
# GameState.selected_hero_id, then starts waves (campaign or endless).

const LEVEL1_WAVES: Resource = preload("res://levels/level1_waves.tres")
const HERO_TEMPLATE: PackedScene = preload("res://heroes/HeroWarrior.tscn")

@onready var level: Node2D = $Level1
@onready var towers: Node2D = $Towers
@onready var hero_input: Node = $HeroInputManager

# Wall-clock timer for best-completion tracking. Uses accumulated process
# delta so PAUSE_MODE_STOP (tactical pause) doesn't inflate the time.
var _level_elapsed: float = 0.0
var _level_done: bool = false


func _ready() -> void:
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)

	_spawn_hero()

	if GameState.current_mode == "endless":
		WaveManager.start_endless(level)
	else:
		# Look up early_call_window for this level from level_list.tres so the
		# Send-Wave button is bounded per the level's authored design.
		WaveManager.start(LEVEL1_WAVES, level, _resolve_early_call_window())


# Read early_call_window_sec from the LevelNodeData matching current_level_id.
# Falls back to 10s default if the registry / level can't be found.
func _resolve_early_call_window() -> float:
	var registry: Resource = load("res://ui/world_map/level_list.tres")
	if registry == null:
		return 10.0
	# `.levels` resolves via the LevelList script attached to the resource.
	var levels: Array = registry.levels
	for entry in levels:
		if entry is LevelNodeData and entry.level_id == GameState.current_level_id:
			return entry.early_call_window_sec
	return 10.0


func _process(delta: float) -> void:
	if _level_done:
		return
	# Ticks only while unpaused (PROCESS_MODE_INHERIT default means we stop
	# during tactical pause — matches what the player "feels" as level time).
	_level_elapsed += delta


func _spawn_hero() -> void:
	# Look up the selected hero data from ContentRegistry. Fall back to
	# first registered hero if the ID isn't found.
	var hero_data: Resource = ContentRegistry.find_hero(GameState.selected_hero_id)
	if hero_data == null and ContentRegistry.heroes.size() > 0:
		hero_data = ContentRegistry.heroes[0]
	if hero_data == null:
		push_warning("[Main] no hero data found for '%s'" % GameState.selected_hero_id)
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
	if GameState.current_mode == "campaign":
		var is_new_best: bool = GameState.try_record_best_time(
			GameState.current_level_id, _level_elapsed
		)
		if is_new_best:
			print("[Main] new best time on %s: %.2fs" % [GameState.current_level_id, _level_elapsed])
		else:
			print("[Main] completed %s in %.2fs (prev best: %.2fs)" % [
				GameState.current_level_id, _level_elapsed,
				GameState.get_best_time(GameState.current_level_id),
			])
	print("[Main] VICTORY — all waves cleared")
