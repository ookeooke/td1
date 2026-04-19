extends CanvasLayer

# Phase 45a + 45b: radial menu anchored at the tapped tower spot.
#   Empty spot    → build ring (tower icons fan around the spot).
#   Occupied spot → action ring (upgrade / sell / target / rally / branch)
#                    with a floating stats card above the ring.
#
# Flow:
#   EventBus.tower_spot_tapped(spot_id)
#     → occupied: open action ring for tower
#     → empty:    open build ring
#
# One CanvasLayer, one backdrop, one anchor node. Slot nodes are rebuilt
# each open (and on tower_upgraded / targeting cycle so labels + glyphs
# stay live). Replaces the retired TowerSpotMenu bottom sheet.

const RING_RADIUS: float = 120.0
const ICON_SIZE: float = 90.0
const OPEN_DURATION: float = 0.18
const STAGGER: float = 0.03
const EDGE_PADDING: float = 20.0
const STATS_CARD_CLEARANCE: float = RING_RADIUS + ICON_SIZE * 0.5 + 16.0  # anchor→card bottom

const TowerIconButton := preload("res://ui/TowerIconButton.gd")
const RadialActionButton := preload("res://ui/RadialActionButton.gd")
const TowerStatsCardScene := preload("res://ui/TowerStatsCard.tscn")

const COLOR_UPGRADE: Color = Color(0.3, 0.72, 0.38)
const COLOR_SELL: Color = Color(0.82, 0.32, 0.28)
const COLOR_TARGET: Color = Color(0.35, 0.55, 0.82)
const COLOR_RALLY: Color = Color(0.88, 0.58, 0.24)
const BADGE_GOLD: Color = Color(0.95, 0.78, 0.22)
const BADGE_REFUND: Color = Color(0.95, 0.78, 0.22)
const BADGE_DIMMED: Color = Color(0.6, 0.5, 0.4)

@onready var root: Control = %Root
@onready var backdrop: Control = %Backdrop
@onready var anchor_node: Control = %Anchor

var _current_spot_id: String = ""
var _current_tower: Node = null
var _slots: Array = []
var _grid: Node = null
var _range_preview: Node = null
var _stats_card: Control = null
var _actions_enabled: bool = true
# Two-step commit state: first tap on a slot arms it (shows preview); a
# second tap on the SAME slot commits. Tap a different slot → re-arm.
# Target/rally are single-tap carve-outs (no peek state needed).
var _armed_slot: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	backdrop.gui_input.connect(_on_backdrop_input)
	EventBus.tower_spot_tapped.connect(_on_spot_tapped)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.tower_sold.connect(_on_tower_sold)
	EventBus.tower_upgraded.connect(_on_tower_upgraded)


# ── Entry point ─────────────────────────────────────────────────────────

func _on_spot_tapped(spot_id: String) -> void:
	if _grid == null:
		_grid = get_tree().root.find_child("GridManager", true, false)
	if _grid == null:
		return
	_current_spot_id = spot_id
	var world_pos: Vector2 = _grid.get_spot_position(spot_id)
	var anchor_pos: Vector2 = _compute_anchor(_project_to_screen(world_pos))
	anchor_node.position = anchor_pos
	if _grid.is_occupied(spot_id):
		_current_tower = _grid.get_tower_at(spot_id)
		_open_action_ring(anchor_pos, world_pos)
	else:
		_current_tower = null
		_open_build_ring(world_pos)


func _project_to_screen(world_pos: Vector2) -> Vector2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return world_pos
	return cam.get_canvas_transform() * world_pos


func _compute_anchor(screen_pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var insets: Vector4 = Vector4.ZERO
	if GameState.has_method("get_safe_insets"):
		insets = GameState.get_safe_insets()
	var pad: float = RING_RADIUS + ICON_SIZE * 0.5 + EDGE_PADDING
	var min_x: float = pad + insets.z
	var max_x: float = vp.x - pad - insets.w
	# Extra top padding so stats card doesn't clip the top edge on action-rings.
	var min_y: float = pad + insets.x + 80.0
	var max_y: float = vp.y - pad - insets.y
	if max_x < min_x:
		min_x = vp.x * 0.5
		max_x = min_x
	if max_y < min_y:
		min_y = vp.y * 0.5
		max_y = min_y
	return Vector2(clamp(screen_pos.x, min_x, max_x), clamp(screen_pos.y, min_y, max_y))


# ── Build ring (empty spots) ───────────────────────────────────────────

func _open_build_ring(world_pos: Vector2) -> void:
	_clear_slots()
	_hide_stats_card()
	_hide_range_preview()
	var buildable: Array = []
	for data in ContentRegistry.towers:
		if data == null:
			continue
		if not UnlockManager.is_tower_unlocked(data.tower_id):
			continue
		buildable.append(data)
	if buildable.is_empty():
		return
	var n: int = buildable.size()
	for i in range(n):
		var data: Resource = buildable[i]
		var slot: Control = TowerIconButton.new()
		var angle: float = -PI * 0.5 + (TAU / float(n)) * float(i)
		_place_slot(slot, angle)
		anchor_node.add_child(slot)
		slot.setup(data, world_pos)
		slot.pressed.connect(_on_build_slot_pressed.bind(slot))
		_slots.append(slot)
	visible = true
	_animate_open()
	_gate_actions_one_frame()


func _on_build_slot_pressed(tower_id: String, slot: Control) -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	# Two-step commit: first tap arms (shows preview), second tap on same slot
	# commits the build. Tapping a different icon re-arms without committing.
	if _armed_slot != slot:
		_arm_build_slot(slot, tower_id)
		return
	_hide_range_preview()
	EventBus.tower_build_requested.emit(_current_spot_id, tower_id)
	_dismiss()


func _arm_build_slot(slot: Control, tower_id: String) -> void:
	var data: Resource = ContentRegistry.find_tower(tower_id)
	if data == null:
		return
	_set_armed(slot)
	var world_pos: Vector2 = slot.get_world_pos() if slot.has_method("get_world_pos") else Vector2.ZERO
	_show_range_preview(world_pos, float(data.get_preview_range()))
	_hide_upgrade_ring()
	var anchor_pos: Vector2 = anchor_node.position
	_show_stats_card_build_preview(data, anchor_pos)


# ── Action ring (occupied spots) ───────────────────────────────────────

func _open_action_ring(anchor_pos: Vector2, world_pos: Vector2) -> void:
	_clear_slots()
	if _current_tower == null:
		return
	_populate_action_slots()
	_show_stats_card(anchor_pos)
	_show_range_preview(world_pos, _tower_effective_range())
	visible = true
	_animate_open()
	_gate_actions_one_frame()


func _populate_action_slots() -> void:
	var tower: Node = _current_tower
	var has_branches: bool = tower.has_method("has_branch_options") and tower.has_branch_options()

	# Top slot: upgrade OR two branch cards.
	if has_branches:
		var branches: Array = tower.get_branch_options()
		if branches.size() >= 1:
			_add_branch_slot(branches[0], 0, -PI * 2.0 / 3.0)
		if branches.size() >= 2:
			_add_branch_slot(branches[1], 1, -PI / 3.0)
	elif tower.has_method("can_upgrade") and tower.can_upgrade():
		var cost: int = tower.get_upgrade_cost_to(tower.level + 1)
		var enabled: bool = GameState.gold >= cost
		_add_action_slot(
			"upgrade", null, "upgrade", 0,
			COLOR_UPGRADE,
			"%dg" % cost,
			BADGE_GOLD if enabled else BADGE_DIMMED,
			enabled,
			-PI * 0.5)

	# Right slot: targeting mode (attack towers only).
	if "targeting_mode" in tower and tower.has_method("cycle_targeting_mode"):
		_add_action_slot(
			"target", null, "target", int(tower.targeting_mode),
			COLOR_TARGET, "", BADGE_GOLD, true, 0.0)

	# Bottom slot: sell. CORE RULE 14 — read through the accessor, not data.
	var refund: int = int(tower.get_sell_value())
	_add_action_slot(
		"sell", null, "sell", 0,
		COLOR_SELL,
		"+%dg" % refund,
		BADGE_REFUND, true,
		PI * 0.5)

	# Left slot: rally (barracks only).
	if tower.has_method("begin_rally_placement"):
		_add_action_slot(
			"rally", null, "rally", 0,
			COLOR_RALLY, "", BADGE_GOLD, true, PI)


func _add_action_slot(
		id: String, payload, pict: String, variant: int,
		color: Color, badge: String, badge_color: Color,
		enabled: bool, angle: float) -> void:
	var slot: Control = RadialActionButton.new()
	_place_slot(slot, angle)
	anchor_node.add_child(slot)
	slot.setup(id, payload, pict, variant, color, badge, badge_color, enabled)
	slot.pressed.connect(_on_action_slot_pressed.bind(slot))
	_slots.append(slot)


func _add_branch_slot(branch: Resource, idx: int, angle: float) -> void:
	var cost: int = int(branch.cost)
	var enabled: bool = GameState.gold >= cost
	_add_action_slot(
		"branch", idx, "branch", idx,
		COLOR_UPGRADE,
		"%dg" % cost,
		BADGE_GOLD if enabled else BADGE_DIMMED,
		enabled,
		angle)


func _on_action_slot_pressed(action_id: String, payload, slot: Control) -> void:
	if not _actions_enabled or _current_spot_id == "":
		return
	# Single-tap carve-outs: target cycles non-destructively; rally enters
	# placement mode (not a commit). Everything else is two-step.
	if action_id == "target":
		if _current_tower != null and _current_tower.has_method("cycle_targeting_mode"):
			_current_tower.cycle_targeting_mode()
			_rebuild_action_slots()
			# Rebuild cleared any armed state; reset card to the built-tower
			# view so a lingering upgrade/sell preview doesn't stay stale.
			_show_stats_card(anchor_node.position)
		return
	if action_id == "rally":
		if _current_tower != null and _current_tower.has_method("begin_rally_placement"):
			EventBus.barracks_rally_move_requested.emit(_current_tower)
			_dismiss()
		return
	# Two-step: arm on first tap, commit on second tap on same slot.
	if _armed_slot != slot:
		_arm_action_slot(slot, action_id, payload)
		return
	match action_id:
		"upgrade":
			EventBus.tower_upgrade_requested.emit(_current_spot_id)
		"branch":
			EventBus.tower_branch_upgrade_requested.emit(_current_spot_id, int(payload))
		"sell":
			EventBus.tower_sell_requested.emit(_current_spot_id)


func _arm_action_slot(slot: Control, action_id: String, payload) -> void:
	if _current_tower == null or not is_instance_valid(_current_tower):
		return
	_set_armed(slot)
	var anchor_pos: Vector2 = anchor_node.position
	match action_id:
		"upgrade":
			_show_stats_card_upgrade_preview(_next_upgrade_data(), anchor_pos)
			var r: float = float(_current_tower.get_upgrade_range())
			if r > 0.0:
				_show_upgrade_ring(r)
			else:
				_hide_upgrade_ring()
		"branch":
			var branches: Array = _current_tower.get_branch_options() if _current_tower.has_method("get_branch_options") else []
			var idx: int = int(payload)
			var branch: Resource = branches[idx] if idx >= 0 and idx < branches.size() else null
			_show_stats_card_upgrade_preview(branch, anchor_pos)
			if branch != null and branch.attack_range > 0.0:
				var gr: float = float(branch.attack_range) * GameState.get_upgrade_multiplier(GameState.MOD_TOWER_RANGE)
				_show_upgrade_ring(gr)
			else:
				_hide_upgrade_ring()
		"sell":
			_show_stats_card_sell_confirm(int(_current_tower.get_sell_value()), anchor_pos)
			_hide_upgrade_ring()


func _next_upgrade_data() -> Resource:
	# Returns the TowerUpgradeData for the linear next level (L2 from L1,
	# linear L3 from L2 without branches). Branches are previewed via
	# _arm_action_slot's "branch" handler instead.
	if _current_tower == null or _current_tower.data == null:
		return null
	var lvl: int = int(_current_tower.level) if "level" in _current_tower else 1
	var idx: int = lvl - 1
	var ups: Array = _current_tower.data.level_upgrades
	if idx < 0 or idx >= ups.size():
		return null
	return ups[idx]


func _rebuild_action_slots() -> void:
	# In-place rebuild (no anim) after an upgrade or targeting cycle.
	_clear_slots()
	_armed_slot = null
	if _current_tower == null or not is_instance_valid(_current_tower):
		return
	_populate_action_slots()


# Arm/disarm helper — keeps visual state on slots in sync with _armed_slot.
func _set_armed(slot: Control) -> void:
	if _armed_slot == slot:
		return
	if _armed_slot != null and is_instance_valid(_armed_slot) and _armed_slot.has_method("set_armed"):
		_armed_slot.set_armed(false)
	_armed_slot = slot
	if slot != null and slot.has_method("set_armed"):
		slot.set_armed(true)


# ── Shared helpers ──────────────────────────────────────────────────────

func _place_slot(slot: Control, angle: float) -> void:
	var slot_offset: Vector2 = Vector2(cos(angle), sin(angle)) * RING_RADIUS
	slot.position = slot_offset - Vector2(ICON_SIZE, ICON_SIZE) * 0.5
	slot.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5


func _animate_open() -> void:
	for i in _slots.size():
		var slot: Control = _slots[i]
		slot.scale = Vector2.ZERO
		slot.modulate.a = 0.0
		var tw: Tween = create_tween()
		tw.tween_interval(float(i) * STAGGER)
		tw.tween_property(slot, "modulate:a", 1.0, OPEN_DURATION * 0.6)
		var tw2: Tween = create_tween()
		tw2.tween_interval(float(i) * STAGGER)
		tw2.tween_property(slot, "scale", Vector2.ONE, OPEN_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _gate_actions_one_frame() -> void:
	_actions_enabled = false
	await get_tree().process_frame
	_actions_enabled = true


func _clear_slots() -> void:
	for slot in _slots:
		if slot != null and is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	# Freed slots would leave _armed_slot dangling — always drop the ref here.
	_armed_slot = null


# ── Stats card ──────────────────────────────────────────────────────────

func _ensure_stats_card() -> void:
	if _stats_card == null:
		_stats_card = TowerStatsCardScene.instantiate()
		root.add_child(_stats_card)


func _show_stats_card(anchor_pos: Vector2) -> void:
	_ensure_stats_card()
	_stats_card.show_for(_current_tower, anchor_pos, STATS_CARD_CLEARANCE)


func _show_stats_card_build_preview(data: Resource, anchor_pos: Vector2) -> void:
	_ensure_stats_card()
	_stats_card.show_for_build_preview(data, anchor_pos, STATS_CARD_CLEARANCE)


func _show_stats_card_upgrade_preview(upgrade: Resource, anchor_pos: Vector2) -> void:
	if upgrade == null:
		return
	_ensure_stats_card()
	_stats_card.show_for_upgrade_preview(_current_tower, upgrade, anchor_pos, STATS_CARD_CLEARANCE)


func _show_stats_card_sell_confirm(refund: int, anchor_pos: Vector2) -> void:
	_ensure_stats_card()
	_stats_card.show_for_sell_confirm(refund, anchor_pos, STATS_CARD_CLEARANCE)


func _hide_stats_card() -> void:
	if _stats_card != null:
		_stats_card.hide_card()


func _refresh_stats_card() -> void:
	if _stats_card != null and _stats_card.visible:
		_stats_card.refresh()


# ── Range preview ──────────────────────────────────────────────────────

func _show_range_preview(world_pos: Vector2, radius: float) -> void:
	if _range_preview == null:
		_range_preview = get_tree().root.find_child("RangePreview", true, false)
	if _range_preview != null and _range_preview.has_method("show_preview"):
		_range_preview.show_preview(world_pos, radius)


func _hide_range_preview() -> void:
	if _range_preview != null and _range_preview.has_method("hide_preview"):
		_range_preview.hide_preview()


func _show_upgrade_ring(radius: float) -> void:
	if _range_preview == null:
		_range_preview = get_tree().root.find_child("RangePreview", true, false)
	if _range_preview != null and _range_preview.has_method("show_upgrade_preview"):
		_range_preview.show_upgrade_preview(radius)


func _hide_upgrade_ring() -> void:
	if _range_preview != null and _range_preview.has_method("hide_upgrade_preview"):
		_range_preview.hide_upgrade_preview()


func _tower_effective_range() -> float:
	# CORE RULE 14 — every tower implements get_preview_range().
	if _current_tower == null:
		return 0.0
	return float(_current_tower.get_preview_range())


# ── Signal listeners ───────────────────────────────────────────────────

func _on_gold_changed(_amount: int) -> void:
	if not visible:
		return
	if _current_tower == null:
		# Build ring — refresh tower icons.
		for slot in _slots:
			if slot != null and slot.has_method("refresh_affordability"):
				slot.refresh_affordability()
		# If the armed build slot became unaffordable, disarm it and drop its
		# preview so the player isn't stuck with a glowing, unclickable icon.
		if _armed_slot != null and is_instance_valid(_armed_slot) \
				and _armed_slot.has_method("is_affordable") and not _armed_slot.is_affordable():
			_set_armed(null)
			_hide_range_preview()
			_hide_stats_card()
	else:
		# Action ring — rebuild upgrade/branch slots to reflect new gold.
		_rebuild_action_slots()
		# Rebuild cleared the armed state; if the card was in upgrade/sell
		# preview mode, reset it to the built-tower view so we don't leave a
		# stale peek displayed.
		_show_stats_card(anchor_node.position)


func _on_tower_built(_tower: Node, _spot_id: String) -> void:
	if visible and _current_tower == null:
		_dismiss()


func _on_tower_sold(tower: Node, _refund: int) -> void:
	if tower == _current_tower:
		_dismiss()


func _on_tower_upgraded(tower: Node, _new_level: int) -> void:
	# Dismiss on upgrade/branch commit so the commit reads as "done" instead
	# of nudging the next purchase. Covers both `tower.upgrade()` and
	# `tower.upgrade_to_branch()` paths (both emit tower_upgraded).
	if visible and tower == _current_tower:
		_dismiss()


# ── Dismissal ──────────────────────────────────────────────────────────

func _on_backdrop_input(event: InputEvent) -> void:
	if not _actions_enabled:
		return
	var is_tap: bool = false
	if event is InputEventScreenTouch:
		is_tap = event.pressed
	elif event is InputEventMouseButton:
		is_tap = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if is_tap:
		_dismiss()


func _dismiss() -> void:
	if not visible:
		return
	_hide_range_preview()
	_hide_upgrade_ring()
	_hide_stats_card()
	_current_spot_id = ""
	_current_tower = null
	_armed_slot = null
	_clear_slots()
	visible = false
	EventBus.tower_menu_dismissed.emit()
