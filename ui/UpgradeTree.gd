extends Control

# Phase 28: permanent upgrade tree. Spend campaign stars on global bonuses.
# Reads purchased state from GameState.purchased_upgrades; writes on
# purchase → SaveManager.save_game() for persistence.

@export var upgrades: Array[Resource] = []

@onready var back_button: Button = %BackButton
@onready var stars_label: Label = %StarsLabel
@onready var upgrade_list: VBoxContainer = %UpgradeList

var _buttons: Dictionary = {}  # upgrade_id → Button


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	GameState.rebuild_upgrade_cache(upgrades)
	_build_ui()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _build_ui() -> void:
	for child in upgrade_list.get_children():
		child.queue_free()
	_buttons.clear()
	_refresh_stars_label()
	for data in upgrades:
		if data == null:
			continue
		var panel: PanelContainer = _make_upgrade_panel(data)
		upgrade_list.add_child(panel)


func _make_upgrade_panel(data: Resource) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)

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
	name_label.text = data.upgrade_name
	name_label.set("theme_override_font_sizes/font_size", 20)
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = data.description
	desc_label.set("theme_override_font_sizes/font_size", 14)
	desc_label.modulate = Color(0.8, 0.8, 0.8)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(desc_label)

	var is_purchased: bool = data.upgrade_id in GameState.purchased_upgrades
	var prereq_met: bool = data.prerequisite_id == "" or data.prerequisite_id in GameState.purchased_upgrades
	var can_afford: bool = GameState.get_available_stars() >= data.star_cost

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 60)
	btn.set("theme_override_font_sizes/font_size", 18)
	if is_purchased:
		btn.text = "Owned"
		btn.disabled = true
	elif not prereq_met:
		btn.text = "Locked"
		btn.disabled = true
	else:
		btn.text = "%d ★" % data.star_cost
		btn.disabled = not can_afford
		btn.pressed.connect(_on_purchase.bind(data))
	hbox.add_child(btn)
	_buttons[data.upgrade_id] = btn
	return panel


func _on_purchase(data: Resource) -> void:
	if data.upgrade_id in GameState.purchased_upgrades:
		return
	if GameState.get_available_stars() < data.star_cost:
		return
	GameState.purchased_upgrades.append(data.upgrade_id)
	GameState.rebuild_upgrade_cache(upgrades)
	EventBus.permanent_upgrade_purchased.emit(data.upgrade_id)
	SaveManager.save_game()
	# Rebuild the full UI so prereq chains + afford states refresh.
	_build_ui()


func _refresh_stars_label() -> void:
	var total: int = GameState.get_total_stars()
	var available: int = GameState.get_available_stars()
	stars_label.text = "★ %d / %d available" % [available, total]
