extends Control

# Phase 40: per-hero talent tree. Spend stars on passive abilities that
# get pushed onto the hero at gameplay start. Mirrors UpgradeTree but
# scoped to the currently selected hero.

@onready var back_button: Button = %BackButton
@onready var stars_label: Label = %StarsLabel
@onready var hero_label: Label = %HeroLabel
@onready var switch_button: Button = %SwitchButton
@onready var talent_list: VBoxContainer = %TalentList

var _hero_data: Resource = null


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	switch_button.pressed.connect(_on_switch_hero)
	_select_hero(GameState.selected_hero_id)


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_switch_hero() -> void:
	var heroes: Array = ContentRegistry.heroes
	if heroes.size() <= 1:
		return
	var idx: int = 0
	for i in heroes.size():
		if heroes[i].hero_id == GameState.selected_hero_id:
			idx = i
			break
	idx = (idx + 1) % heroes.size()
	GameState.selected_hero_id = heroes[idx].hero_id
	_select_hero(GameState.selected_hero_id)


func _select_hero(hero_id: String) -> void:
	_hero_data = ContentRegistry.find_hero(hero_id)
	if _hero_data == null and ContentRegistry.heroes.size() > 0:
		_hero_data = ContentRegistry.heroes[0]
	_build_ui()


func _build_ui() -> void:
	for child in talent_list.get_children():
		child.queue_free()
	if _hero_data == null:
		hero_label.text = "No hero"
		return
	hero_label.text = "%s Talents" % _hero_data.hero_name
	stars_label.text = "★ %d available" % GameState.get_available_stars()
	if not ("talents" in _hero_data) or _hero_data.talents.is_empty():
		var empty := Label.new()
		empty.text = "No talents available for this hero."
		empty.set("theme_override_font_sizes/font_size", 16)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		talent_list.add_child(empty)
		return
	var purchased: Array = GameState.hero_talents.get(_hero_data.hero_id, [])
	for talent in _hero_data.talents:
		if talent == null:
			continue
		_add_talent_panel(talent, purchased)


func _add_talent_panel(talent: Resource, purchased: Array) -> void:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.set("theme_override_constants/margin_left", 12)
	margin.set("theme_override_constants/margin_top", 8)
	margin.set("theme_override_constants/margin_right", 12)
	margin.set("theme_override_constants/margin_bottom", 8)
	panel.add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.set("theme_override_constants/separation", 12)
	margin.add_child(hbox)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var name_label := Label.new()
	name_label.text = talent.talent_name
	name_label.set("theme_override_font_sizes/font_size", 20)
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = talent.description
	desc_label.set("theme_override_font_sizes/font_size", 14)
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(desc_label)

	var is_purchased: bool = talent.talent_id in purchased
	var prereq_met: bool = talent.prerequisite_id == "" or talent.prerequisite_id in purchased
	var can_afford: bool = GameState.get_available_stars() >= talent.star_cost

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(90, 50)
	btn.set("theme_override_font_sizes/font_size", 16)
	if is_purchased:
		btn.text = "Owned"
		btn.disabled = true
	elif not prereq_met:
		btn.text = "Locked"
		btn.disabled = true
	else:
		btn.text = "%d ★" % talent.star_cost
		btn.disabled = not can_afford
		btn.pressed.connect(_on_purchase.bind(talent))
	hbox.add_child(btn)
	talent_list.add_child(panel)


func _on_purchase(talent: Resource) -> void:
	var hero_id: String = _hero_data.hero_id
	if hero_id not in GameState.hero_talents:
		GameState.hero_talents[hero_id] = []
	if talent.talent_id in GameState.hero_talents[hero_id]:
		return
	if GameState.get_available_stars() < talent.star_cost:
		return
	GameState.hero_talents[hero_id].append(talent.talent_id)
	EventBus.skill_point_spent.emit(talent.talent_id)
	SaveManager.save_game()
	_build_ui()
