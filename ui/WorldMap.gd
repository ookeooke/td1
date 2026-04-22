extends Control

# World Map — level select screen. Shows one panel per level with name,
# stars earned, and locked/unlocked state. Tap unlocked → gameplay.
# Data-driven via `levels: Array[LevelNodeData]` set in the .tscn.
# Stars + unlock state read from GameState (populated by SaveManager later).

@export var levels: Array[Resource] = []

@onready var back_button: Button = %BackButton
@onready var level_list_container: VBoxContainer = %LevelList
@onready var heroes_button: Button = %HeroesButton
@onready var loadout_button: Button = %LoadoutButton
@onready var equipment_button: Button = %EquipmentButton
@onready var upgrades_button: Button = %UpgradesButton
@onready var endless_button: Button = %EndlessButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var encyclopedia_button: Button = %EncyclopediaButton
@onready var shop_button: Button = %ShopButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	upgrades_button.pressed.connect(_on_upgrades)
	endless_button.pressed.connect(_on_endless)
	leaderboard_button.pressed.connect(_on_leaderboard)
	encyclopedia_button.pressed.connect(_on_encyclopedia)
	shop_button.pressed.connect(_on_shop)
	heroes_button.pressed.connect(_on_heroes)
	loadout_button.pressed.connect(_on_loadout)
	equipment_button.pressed.connect(_on_equipment)
	_build_level_entries()


func _on_loadout() -> void:
	SceneManager.goto("res://ui/LoadoutPickerScreen.tscn")


func _on_equipment() -> void:
	SceneManager.goto("res://ui/EquipmentScreen.tscn")


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


func _on_heroes() -> void:
	SceneManager.goto("res://ui/TalentScreen.tscn")


func _on_shop() -> void:
	SceneManager.goto("res://ui/ShopScreen.tscn")


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
	panel.custom_minimum_size = Vector2(320, 110)
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

	# Phase 48 — best time + endless high score. Only show if the player
	# has posted a run (otherwise the row would read "Best: —  Endless: —"
	# which adds clutter with zero information).
	var metrics_line: String = _format_level_metrics(data.level_id)
	if metrics_line != "":
		var metrics_label := Label.new()
		metrics_label.text = metrics_line
		metrics_label.set("theme_override_font_sizes/font_size", 14)
		metrics_label.modulate = Color(0.7, 0.78, 0.9)
		info_vbox.add_child(metrics_label)

	# Right side: play buttons (campaign + endless) or lock
	var is_unlocked: bool = GameState.levels_unlocked.get(data.level_id, false)
	if is_unlocked:
		var button_vbox := VBoxContainer.new()
		button_vbox.set("theme_override_constants/separation", 6)
		hbox.add_child(button_vbox)

		var play_btn := Button.new()
		play_btn.text = "Play"
		play_btn.custom_minimum_size = Vector2(100, 44)
		play_btn.set("theme_override_font_sizes/font_size", 18)
		play_btn.pressed.connect(_on_level_selected.bind(data))
		button_vbox.add_child(play_btn)

		var endless_btn := Button.new()
		endless_btn.text = "Endless"
		endless_btn.custom_minimum_size = Vector2(100, 44)
		endless_btn.set("theme_override_font_sizes/font_size", 16)
		endless_btn.pressed.connect(_on_level_endless.bind(data))
		button_vbox.add_child(endless_btn)
	else:
		var lock_btn := Button.new()
		lock_btn.text = "Locked"
		lock_btn.custom_minimum_size = Vector2(100, 94)
		lock_btn.set("theme_override_font_sizes/font_size", 20)
		lock_btn.modulate = Color(0.7, 0.7, 0.7)
		lock_btn.pressed.connect(func(): Toast.show_message("Clear prior levels to unlock"))
		hbox.add_child(lock_btn)

	return panel


func _format_level_metrics(level_id: String) -> String:
	var parts: PackedStringArray = []
	var best: float = GameState.get_best_time(level_id)
	if best > 0.0:
		parts.append("Best: %s" % _format_seconds(best))
	var endless: int = GameState.get_endless_best_score(level_id)
	if endless > 0:
		parts.append("Endless: %d" % endless)
	return "   ".join(parts)


func _format_seconds(s: float) -> String:
	if s < 60.0:
		return "%.1fs" % s
	var minutes: int = int(s / 60.0)
	var rem: float = s - float(minutes * 60)
	return "%d:%05.2f" % [minutes, rem]


func _on_level_selected(data: Resource) -> void:
	GameState.current_level_id = data.level_id
	GameState.current_mode = "campaign"
	# Don't reset_for_level here — LoadoutScreen does it on Start so the
	# player can browse loadout without committing.
	SceneManager.goto("res://ui/LoadoutScreen.tscn")


func _on_level_endless(data: Resource) -> void:
	GameState.current_level_id = data.level_id
	GameState.current_mode = "endless"
	SceneManager.goto("res://ui/LoadoutScreen.tscn")
