extends CanvasLayer

# Bottom-sheet popup. Two modes:
#   empty spot    → Build rows (Phase 8)
#   occupied spot → Sell row (Phase 9)
# Phase 24 adds upgrade rows alongside Sell when the spot is occupied.

@onready var root: Control = %Root
@onready var backdrop: Control = %Backdrop
@onready var title_label: Label = %TitleLabel
@onready var build_row: VBoxContainer = %BuildRow
@onready var sell_row: VBoxContainer = %SellRow
@onready var archer_button: Button = %ArcherButton
@onready var sell_button: Button = %SellButton
@onready var close_button: Button = %CloseButton

const ARCHER_ID: String = "archer"
const ARCHER_COST: int = 50

var _current_spot_id: String = ""
var _current_tower: Node = null


func _ready() -> void:
	root.visible = false
	archer_button.pressed.connect(_on_archer_pressed)
	sell_button.pressed.connect(_on_sell_pressed)
	close_button.pressed.connect(_dismiss)
	backdrop.gui_input.connect(_on_backdrop_input)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.tower_sold.connect(_on_tower_sold)


func _on_spot_tapped(spot_id: String) -> void:
	var grid: Node = _find_grid()
	_current_spot_id = spot_id
	if grid != null and grid.is_occupied(spot_id):
		_current_tower = grid.get_tower_at(spot_id)
		_show_sell_mode()
	else:
		_current_tower = null
		_show_build_mode()
	root.visible = true


func _show_build_mode() -> void:
	title_label.text = "Build Tower"
	build_row.visible = true
	sell_row.visible = false
	_refresh_build_buttons()


func _show_sell_mode() -> void:
	title_label.text = "Tower"
	build_row.visible = false
	sell_row.visible = true
	_refresh_sell_button()


func _refresh_build_buttons() -> void:
	archer_button.text = "Build Archer (%dg)" % ARCHER_COST
	archer_button.disabled = GameState.gold < ARCHER_COST


func _refresh_sell_button() -> void:
	var refund: int = 0
	if _current_tower != null and "data" in _current_tower and _current_tower.data != null:
		refund = int(_current_tower.data.sell_value)
	sell_button.text = "Sell (+%dg)" % refund


func _on_gold_changed(_amount: int) -> void:
	if root.visible and build_row.visible:
		_refresh_build_buttons()


func _on_tower_sold(tower: Node, _refund: int) -> void:
	if tower == _current_tower:
		_dismiss()


func _on_archer_pressed() -> void:
	if _current_spot_id == "":
		return
	EventBus.tower_build_requested.emit(_current_spot_id, ARCHER_ID)
	_dismiss()


func _on_sell_pressed() -> void:
	if _current_spot_id == "":
		return
	EventBus.tower_sell_requested.emit(_current_spot_id)
	# tower_sold signal dismisses the menu.


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dismiss()


func _dismiss() -> void:
	_current_spot_id = ""
	_current_tower = null
	root.visible = false
	EventBus.tower_menu_dismissed.emit()


func _find_grid() -> Node:
	return get_tree().root.find_child("GridManager", true, false)
