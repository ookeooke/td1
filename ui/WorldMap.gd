extends Control

# World Map — level select screen. Shows one panel per level with name,
# stars earned, and locked/unlocked state. Tap unlocked → gameplay.
# Data-driven via `levels: Array[LevelNodeData]` set in the .tscn.
# Stars + unlock state read from GameState (populated by SaveManager later).

@export var levels: Array[Resource] = []

@onready var back_button: Button = %BackButton
@onready var level_list_container: VBoxContainer = %LevelList
@onready var heroes_button: Button = %HeroesButton
@onready var upgrades_button: Button = %UpgradesButton
@onready var endless_button: Button = %EndlessButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var encyclopedia_button: Button = %EncyclopediaButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	upgrades_button.pressed.connect(_on_upgrades)
	endless_button.pressed.connect(_on_endless)
	leaderboard_button.pressed.connect(_on_leaderboard)
	encyclopedia_button.pressed.connect(_on_encyclopedia)
	heroes_button.disabled = true
	_build_level_entries()


func _on_back() -> void:
	SceneManager.goto("res://ui/MainMenu.tscn")


func _on_upgrades() -> void:
	SceneManager.goto("res://ui/UpgradeTree.tscn")


func _on_endless() -> void:
	GameState.current_level_id = "endless"
	GameState.current_mode = "endless"
	SceneManager.goto("res://ui/LoadoutScreen.tscn")


func _on_leaderboard() -> void:
	SceneManager.goto("res://ui/LeaderboardScreen.tscn")


func _on_encyclopedia() -> void:
	SceneManager.goto("res://ui/EncyclopediaScreen.tscn")


func _build_level_entries() -> void:
	for child in level_list_container.get_children():
		child.queue_free()
	for data in levels:
		if data == null:
			continue
		var panel: PanelContainer = _make_level_panel(data)
		level_list_container.add_child(panel)


func _make_level_panel(data: Resource) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 100)
	var hbox := HBoxContainer.new()
	hbox.set("theme_override_constants/separation", 16)
	panel.add_child(hbox)

	# Left side: level info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.set("theme_override_font_sizes/font_size", 24)
	info_vbox.add_child(name_label)

	# Composite stars: campaign (0–3) + heroic (+1) + iron (+1) = max 5.
	var total_stars: int = GameState.calculate_total_stars_for_level(data.level_id)
	var star_text: String = "★".repeat(total_stars) + "☆".repeat(5 - total_stars)
	var stars_label := Label.new()
	stars_label.text = star_text
	stars_label.set("theme_override_font_sizes/font_size", 20)
	info_vbox.add_child(stars_label)

	# Right side: play button or lock
	var is_unlocked: bool = GameState.levels_unlocked.get(data.level_id, false)
	if is_unlocked:
		var play_btn := Button.new()
		play_btn.text = "Play"
		play_btn.custom_minimum_size = Vector2(100, 80)
		play_btn.set("theme_override_font_sizes/font_size", 22)
		play_btn.pressed.connect(_on_level_selected.bind(data))
		hbox.add_child(play_btn)
	else:
		var lock_label := Label.new()
		lock_label.text = "Locked"
		lock_label.set("theme_override_font_sizes/font_size", 20)
		lock_label.modulate = Color(0.5, 0.5, 0.5)
		hbox.add_child(lock_label)

	return panel


func _on_level_selected(data: Resource) -> void:
	GameState.current_level_id = data.level_id
	# Don't reset_for_level here — LoadoutScreen does it on Start so the
	# player can browse loadout without committing.
	SceneManager.goto("res://ui/LoadoutScreen.tscn")
