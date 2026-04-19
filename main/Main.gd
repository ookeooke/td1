extends Node2D

# Gameplay scene. Spawns the hero dynamically from ContentRegistry +
# GameState.selected_hero_id, then starts waves (campaign or endless).

const LEVEL1_WAVES: Resource = preload("res://levels/level1_waves.tres")
const HERO_TEMPLATE: PackedScene = preload("res://heroes/HeroWarrior.tscn")

@onready var level: Node2D = $Level1
@onready var towers: Node2D = $Towers
@onready var hero_input: Node = $HeroInputManager


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = level.get_node("GridManager")
	print("[Main] Level1 loaded — free spots: ", grid.get_free_spot_ids())

	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)

	_spawn_hero()

	if GameState.current_mode == "endless":
		WaveManager.start_endless(level)
	else:
		WaveManager.start(LEVEL1_WAVES, level)


func _spawn_hero() -> void:
	# Look up the selected hero data from ContentRegistry. Fall back to
	# first registered hero if the ID isn't found.
	var hero_data: Resource = ContentRegistry.find_hero(GameState.selected_hero_id)
	if hero_data == null and ContentRegistry.heroes.size() > 0:
		hero_data = ContentRegistry.heroes[0]
	if hero_data == null:
		push_warning("[Main] no hero data found for '%s'" % GameState.selected_hero_id)
		return
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
	print("[Main] VICTORY — all waves cleared")


func _on_tower_built(_tower: Node, spot_id: String) -> void:
	print("[Main] tower built on %s" % spot_id)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	print("[Main] leak — lives -%d (remaining: %d)" % [lives_lost, GameState.lives])
