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
@onready var sell_button: Button = %SellButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var branch_a_button: Button = %BranchARow
@onready var branch_b_button: Button = %BranchBRow
@onready var move_rally_button: Button = %MoveRallyButton
@onready var close_button: Button = %CloseButton

var _current_spot_id: String = ""
var _current_tower: Node = null
# Defensive gates: when the menu opens under a finger that's still down,
# the release of that same press can land on a button that just appeared
# at the tap coordinates and fire its action (observed for bottom-row
# spots where the Panel overlaps the spot position).
#   (1) _swallow_next_release  — primary guard. _input consumes the first
#       release that arrives after the menu opens, BEFORE the GUI phase
#       routes it to a button. Handles gestures that span multiple frames
#       (finger held beyond a single tick).
#   (2) _actions_enabled       — belt-and-suspenders. Rejects any button
#       action for one idle frame after open, in case a release slips
#       past _input (synthetic events, dev overrides, etc.).
var _swallow_next_release: bool = false
var _actions_enabled: bool = true


func _ready() -> void:
	# Toggle the CanvasLayer itself — the Main.tscn instance may be saved with
	# visible=false, which would block input regardless of inner Control state.
	visible = false
	root.visible = true
	sell_button.pressed.connect(_on_sell_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	branch_a_button.pressed.connect(_on_branch_pressed.bind(0))
	branch_b_button.pressed.connect(_on_branch_pressed.bind(1))
	move_rally_button.pressed.connect(_on_move_rally_pressed)
	close_button.pressed.connect(_dismiss)
	backdrop.gui_input.connect(_on_backdrop_input)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.tower_sold.connect(_on_tower_sold)
	EventBus.tower_upgraded.connect(_on_tower_upgraded)


func _on_spot_tapped(spot_id: String) -> void:
	var grid: Node = _find_grid()
	_current_spot_id = spot_id
	if grid != null and grid.is_occupied(spot_id):
		_current_tower = grid.get_tower_at(spot_id)
		_show_sell_mode()
	else:
		_current_tower = null
		_show_build_mode()
	visible = true
	_swallow_next_release = true
	_actions_enabled = false
	_enable_actions_next_frame()


func _enable_actions_next_frame() -> void:
	await get_tree().process_frame
	_actions_enabled = true


func _input(event: InputEvent) -> void:
	# Eats the release tail of the press that opened this menu so the
	# Button that just appeared under the finger doesn't fire. _input runs
	# before the GUI phase, so consuming here prevents Button.gui_input
	# from ever seeing this event.
	if not _swallow_next_release:
		return
	if event is InputEventScreenTouch and not event.pressed:
		_swallow_next_release = false
		get_viewport().set_input_as_handled()


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
	# Dynamic: generate one button per unlocked tower from ContentRegistry.
	for child in build_row.get_children():
		child.queue_free()
	for tower_data in ContentRegistry.towers:
		if tower_data == null:
			continue
		var tid: String = tower_data.tower_id
		if not UnlockManager.is_unlocked(tid):
			continue
		var cost: int = int(tower_data.cost)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 80)
		btn.set("theme_override_font_sizes/font_size", 22)
		btn.text = "Build %s (%dg)" % [tower_data.tower_name, cost]
		btn.disabled = GameState.gold < cost
		btn.pressed.connect(_on_build_pressed.bind(tid))
		build_row.add_child(btn)


func _refresh_sell_button() -> void:
	var refund: int = 0
	if _current_tower != null and _current_tower.has_method("get_sell_value"):
		refund = int(_current_tower.get_sell_value())
	elif _current_tower != null and "data" in _current_tower and _current_tower.data != null:
		refund = int(_current_tower.data.sell_value)
	sell_button.text = "Sell (+%dg)" % refund
	# "Move Rally" only makes sense for barracks — hide for attack towers.
	move_rally_button.visible = _current_tower != null and _current_tower.has_method("begin_rally_placement")
	# Upgrade button only when the tower supports it AND isn't at max level.
	_refresh_upgrade_button()


func _refresh_upgrade_button() -> void:
	# Hide everything first; the correct rows re-enable below.
	upgrade_button.visible = false
	branch_a_button.visible = false
	branch_b_button.visible = false
	if _current_tower == null:
		return
	# Branch choice always wins over the linear upgrade button when the
	# tower is at L2 with branches available.
	if _current_tower.has_method("has_branch_options") and _current_tower.has_branch_options():
		var branches: Array = _current_tower.get_branch_options()
		_refresh_branch_button(branch_a_button, branches, 0)
		_refresh_branch_button(branch_b_button, branches, 1)
		return
	if not (_current_tower.has_method("can_upgrade") and _current_tower.can_upgrade()):
		return
	var cost: int = _current_tower.get_upgrade_cost_to(_current_tower.level + 1)
	var next_level: int = _current_tower.level + 1
	upgrade_button.text = "Upgrade → Lv %d (%dg)" % [next_level, cost]
	upgrade_button.disabled = GameState.gold < cost
	upgrade_button.visible = true


func _refresh_branch_button(button: Button, branches: Array, idx: int) -> void:
	if idx >= branches.size():
		button.visible = false
		return
	var branch: Resource = branches[idx]
	var label: String = branch.upgrade_name if branch.upgrade_name != "" else "Branch %d" % (idx + 1)
	var cost: int = int(branch.cost)
	button.text = "%s (%dg)" % [label, cost]
	button.disabled = GameState.gold < cost
	button.visible = true


func _on_gold_changed(_amount: int) -> void:
	if not visible:
		return
	if build_row.visible:
		_refresh_build_buttons()
	elif sell_row.visible:
		_refresh_upgrade_button()


func _on_tower_sold(tower: Node, _refund: int) -> void:
	if tower == _current_tower:
		_dismiss()


func _on_tower_upgraded(tower: Node, _new_level: int) -> void:
	# Keep the menu open after an upgrade so the player can chain to the
	# next level without reopening — just refresh the labels.
	if visible and sell_row.visible and tower == _current_tower:
		_refresh_sell_button()


func _on_build_pressed(tower_id: String) -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	EventBus.tower_build_requested.emit(_current_spot_id, tower_id)
	_dismiss()


func _on_sell_pressed() -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	EventBus.tower_sell_requested.emit(_current_spot_id)
	# tower_sold signal dismisses the menu.


func _on_upgrade_pressed() -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	EventBus.tower_upgrade_requested.emit(_current_spot_id)
	# Menu stays open; _on_tower_upgraded refreshes the labels.


func _on_branch_pressed(idx: int) -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	EventBus.tower_branch_upgrade_requested.emit(_current_spot_id, idx)
	# _on_tower_upgraded fires after a successful branch and refreshes the
	# row; failed branches (insufficient gold) leave the menu unchanged.


func _on_move_rally_pressed() -> void:
	if not _actions_enabled or _current_tower == null:
		return
	EventBus.barracks_rally_move_requested.emit(_current_tower)
	_dismiss()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dismiss()


func _dismiss() -> void:
	_current_spot_id = ""
	_current_tower = null
	_swallow_next_release = false
	visible = false
	EventBus.tower_menu_dismissed.emit()


func _find_grid() -> Node:
	return get_tree().root.find_child("GridManager", true, false)
