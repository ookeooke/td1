extends Control

# Phase 30 + 31: pre-level loadout + mode selection. Shows hero/tower/spell
# roster and 3 mode buttons (Campaign / Heroic / Iron) with unlock status.
# Player picks a mode, then Start → gameplay.

@onready var back_button: Button = %BackButton
@onready var start_button: Button = %StartButton
@onready var hero_label: Label = %HeroLabel
@onready var towers_label: Label = %TowersLabel
@onready var spells_label: Label = %SpellsLabel
@onready var level_label: Label = %LevelLabel
@onready var campaign_button: Button = %CampaignButton
@onready var heroic_button: Button = %HeroicButton
@onready var iron_button: Button = %IronButton
@onready var mode_info_label: Label = %ModeInfoLabel

var _selected_mode: String = "campaign"


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	start_button.pressed.connect(_on_start)
	campaign_button.pressed.connect(_on_mode_selected.bind("campaign"))
	heroic_button.pressed.connect(_on_mode_selected.bind("heroic"))
	iron_button.pressed.connect(_on_mode_selected.bind("iron"))
	_selected_mode = "campaign"
	_refresh()


func _refresh() -> void:
	var lid: String = GameState.current_level_id
	var is_endless: bool = GameState.current_mode == "endless"
	level_label.text = "Endless Mode" if is_endless else lid.replace("_", " ").capitalize()
	hero_label.text = "Hero: Knight\nHP 120  DMG 12  SPD 1.0\nSkills: Slash, Bash, Rally"
	towers_label.text = "Towers: Archer, Barracks"
	spells_label.text = "Spells: Fireball, Recruit"
	# Endless skips the mode selector — it IS the mode.
	campaign_button.visible = not is_endless
	heroic_button.visible = not is_endless
	iron_button.visible = not is_endless
	if is_endless:
		mode_info_label.text = "Infinite waves. Difficulty scales each wave.\nBest score: %d" % GameState.endless_best_score
	else:
		_refresh_mode_buttons()


func _refresh_mode_buttons() -> void:
	var lid: String = GameState.current_level_id
	var campaign_stars: int = GameState.level_stars.get(lid, 0)
	var heroic_done: bool = GameState.heroic_complete.get(lid, false)
	var iron_done: bool = GameState.iron_complete.get(lid, false)
	var heroic_unlocked: bool = GameState.is_heroic_unlocked(lid)
	var iron_unlocked: bool = GameState.is_iron_unlocked(lid)

	# Campaign — always available.
	var c_stars: String = "★".repeat(campaign_stars) + "☆".repeat(3 - campaign_stars)
	campaign_button.text = "Campaign\n%s" % c_stars
	campaign_button.disabled = false

	# Heroic
	if heroic_done:
		heroic_button.text = "Heroic\nComplete ✓"
		heroic_button.disabled = false
	elif heroic_unlocked:
		heroic_button.text = "Heroic\nAvailable"
		heroic_button.disabled = false
	else:
		heroic_button.text = "Heroic\nNeed 3★"
		heroic_button.disabled = true

	# Iron
	if iron_done:
		iron_button.text = "Iron\nComplete ✓"
		iron_button.disabled = false
	elif iron_unlocked:
		iron_button.text = "Iron\nAvailable"
		iron_button.disabled = false
	else:
		iron_button.text = "Iron\nNeed Heroic"
		iron_button.disabled = true

	_highlight_selected()
	_update_mode_info()


func _on_mode_selected(mode: String) -> void:
	_selected_mode = mode
	_highlight_selected()
	_update_mode_info()


func _highlight_selected() -> void:
	# Simple visual: modulate the selected button brighter, others dimmer.
	campaign_button.modulate = Color.WHITE if _selected_mode == "campaign" else Color(0.6, 0.6, 0.6)
	heroic_button.modulate = Color.WHITE if _selected_mode == "heroic" else Color(0.6, 0.6, 0.6)
	iron_button.modulate = Color.WHITE if _selected_mode == "iron" else Color(0.6, 0.6, 0.6)


func _update_mode_info() -> void:
	match _selected_mode:
		"campaign":
			mode_info_label.text = "Standard waves. Earn 1-3 stars based on lives remaining."
		"heroic":
			mode_info_label.text = "Harder waves: 1.5x enemies, faster spawns. +1 bonus star on completion."
		"iron":
			mode_info_label.text = "1 life only. Any enemy leak = instant defeat. +1 bonus star on completion."
		_:
			mode_info_label.text = ""


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_start() -> void:
	GameState.current_mode = _selected_mode
	GameState.reset_for_level()
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.lives_changed.emit(GameState.lives)
	SceneManager.goto("res://main/Main.tscn")
