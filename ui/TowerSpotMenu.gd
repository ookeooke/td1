extends CanvasLayer

# Bottom-sheet popup shown when an empty tower spot is tapped.
# Phase 8: one build option (Archer). Phase 24+ adds upgrade / sell rows
# when tapping an occupied spot.

@onready var root: Control = %Root
@onready var backdrop: Control = %Backdrop
@onready var panel: PanelContainer = %Panel
@onready var archer_button: Button = %ArcherButton
@onready var close_button: Button = %CloseButton

const ARCHER_ID: String = "archer"
const ARCHER_COST: int = 50

var _current_spot_id: String = ""


func _ready() -> void:
	root.visible = false
	archer_button.pressed.connect(_on_archer_pressed)
	close_button.pressed.connect(_dismiss)
	backdrop.gui_input.connect(_on_backdrop_input)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)
	EventBus.gold_changed.connect(_on_gold_changed)


func _on_spot_tapped(spot_id: String) -> void:
	var grid: Node = get_tree().root.find_child("GridManager", true, false)
	if grid != null and grid.has_method("is_occupied") and grid.is_occupied(spot_id):
		# Phase 24 wires the upgrade/sell menu here.
		return
	_current_spot_id = spot_id
	_refresh_buttons()
	root.visible = true


func _on_gold_changed(_amount: int) -> void:
	if root.visible:
		_refresh_buttons()


func _refresh_buttons() -> void:
	archer_button.text = "Build Archer (%dg)" % ARCHER_COST
	archer_button.disabled = GameState.gold < ARCHER_COST


func _on_archer_pressed() -> void:
	if _current_spot_id == "":
		return
	EventBus.tower_build_requested.emit(_current_spot_id, ARCHER_ID)
	_dismiss()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dismiss()


func _dismiss() -> void:
	_current_spot_id = ""
	root.visible = false
	EventBus.tower_menu_dismissed.emit()
