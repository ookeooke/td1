extends Control
class_name ItemIcon

# Phase 48 D1 — reusable tile for EquipmentScreen slots + inventory grid.
# Procedural _draw() renders a rarity-tinted border + icon glyph. Mirrors
# TowerIconButton's render style (no sprites needed, works on any theme).
#
# Three modes:
#   - Empty slot (setup_empty): grey hatched square, no glyph, no rarity
#   - Filled (setup_instance): rarity-colored border, glyph in center,
#     optional "armed" outline for two-step-commit interaction
#   - Locked (setup_locked): padlock-style dim overlay, no click
#
# Emits `pressed(instance)` when clicked — null instance means empty slot
# was tapped (useful for "tap to unequip" UX).

signal pressed(instance)
signal hovered(instance)
signal unhovered
# IP-2 — fired when the user holds touch/click for >= LONG_PRESS_SECONDS.
# Mobile-friendly replacement for hover-only details (touch has no hover).
# When emitted, `pressed` is suppressed for that interaction so a long-press
# doesn't also accidentally equip / sell-arm the item.
signal long_pressed(instance)

const SIZE_PX: float = 92.0
const BORDER_THICKNESS_PX: float = 3.0
const ARMED_RING_THICKNESS_PX: float = 3.0
const GLYPH_RADIUS_PX: float = 28.0

# Rarity tints for the border — same palette as ItemPickup halo so drops
# the player sees on the ground match what they see in the UI.
const _RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.75),   # 0 COMMON
	Color(0.4, 0.7, 1.0),      # 1 MAGIC
	Color(1.0, 0.9, 0.3),      # 2 RARE
	Color(0.8, 0.4, 1.0),      # 3 EPIC
	Color(1.0, 0.55, 0.1),     # 4 LEGENDARY
]

# IP-1 — Per-rarity border thickness + background tint. Dramatic visual
# hierarchy at a glance (Common reads as plain, Legendary reads as obvious
# treasure). Index matches _RARITY_COLORS.
const _RARITY_BORDER_THICKNESS: Array[float] = [3.0, 4.0, 4.5, 5.0, 6.0]
# Background tints — base dark + a kiss of rarity color. Common keeps the
# original _FILLED_BG; higher rarities lerp toward their rarity color at
# small alpha so the icon glyph still reads.
const _RARITY_BG_TINT_AMOUNT: Array[float] = [0.0, 0.10, 0.16, 0.22, 0.30]

const _ARMED_COLOR: Color = Color(1.0, 0.95, 0.4)      # yellow (matches tower menu)
const _LOCKED_COLOR: Color = Color(0.25, 0.25, 0.25)
# Empty tiles need enough contrast to be visible against the screen
# background (which is ~0.1,0.14,0.18 in EquipmentScreen). Lifted bg + hot
# border so the cell reads clearly as "slot, no item".
const _EMPTY_BG: Color = Color(0.19, 0.22, 0.28)
const _EMPTY_BORDER: Color = Color(0.45, 0.48, 0.55)
const _EMPTY_PLUS_COLOR: Color = Color(0.38, 0.42, 0.5)
const _FILLED_BG: Color = Color(0.08, 0.08, 0.12)

var _instance = null
var _base: Resource = null
var _armed: bool = false
var _locked: bool = false
var _is_empty: bool = true
# IP-3 — "do not sell" pin (separate from `_locked` which means slot-locked /
# disabled). When true, the icon draws a small padlock glyph in the
# upper-right corner; rendering is otherwise unchanged.
var _locked_for_sale: bool = false

# IP-2 — long-press tracking. Started on touch/mouse-down; if the press is
# released before LONG_PRESS_SECONDS, fires `pressed`. If the timer elapses
# while still pressed, fires `long_pressed` and marks `_long_press_consumed`
# so the eventual release is a no-op.
const LONG_PRESS_SECONDS: float = 0.45
var _press_timer: SceneTreeTimer = null
var _long_press_consumed: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	if not _is_empty and not _locked:
		hovered.emit(_instance)


func _on_mouse_exited() -> void:
	unhovered.emit()


func setup_instance(inst) -> void:
	_instance = inst
	_base = null
	_is_empty = false
	_locked = false
	_locked_for_sale = inst != null and "locked" in inst and inst.locked
	if inst != null:
		_base = ContentRegistry.find_item_base(inst.base_id)
	queue_redraw()


func setup_empty() -> void:
	_instance = null
	_base = null
	_is_empty = true
	_locked = false
	queue_redraw()


func setup_locked() -> void:
	_instance = null
	_base = null
	_is_empty = true
	_locked = true
	queue_redraw()


func set_armed(on: bool) -> void:
	if _armed == on:
		return
	_armed = on
	queue_redraw()


func get_instance():
	return _instance


func _on_gui_input(event: InputEvent) -> void:
	if _locked:
		return
	# Press-down: start long-press timer. Release before timeout = pressed
	# emit; release after = long_pressed already fired, swallow this release.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press()
		else:
			_end_press()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_press()
		else:
			_end_press()


func _begin_press() -> void:
	_long_press_consumed = false
	# Cancel any stale timer (defensive — shouldn't normally happen).
	_press_timer = get_tree().create_timer(LONG_PRESS_SECONDS)
	var captured_timer: SceneTreeTimer = _press_timer
	captured_timer.timeout.connect(func():
		# Only fire if this captured timer is still the active one (the user
		# might have released and started a new press in the meantime).
		if is_instance_valid(self) and _press_timer == captured_timer and not _long_press_consumed:
			_long_press_consumed = true
			long_pressed.emit(_instance)
	)


func _end_press() -> void:
	# Clear the timer reference so any pending callback no-ops.
	_press_timer = null
	if _long_press_consumed:
		# Long-press already handled this interaction — don't double-fire pressed.
		_long_press_consumed = false
		return
	pressed.emit(_instance)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	# IP-1 — rarity-tinted background for filled items. Common stays neutral
	# (matches the prior look); Magic+ get a progressively stronger color
	# wash so legendary drops jump out of the grid.
	var bg: Color = _EMPTY_BG if _is_empty else _FILLED_BG
	if not _is_empty and _base != null:
		var rarity_idx: int = clampi(int(_base.rarity), 0, _RARITY_COLORS.size() - 1)
		bg = _FILLED_BG.lerp(_RARITY_COLORS[rarity_idx], _RARITY_BG_TINT_AMOUNT[rarity_idx])
	draw_rect(rect, bg, true)
	# Border — rarity-tinted when filled, grey when empty, dark when locked.
	# IP-1: thickness also scales with rarity (Common 3px → Legendary 6px).
	var border_color: Color = _EMPTY_BORDER
	var border_thickness: float = BORDER_THICKNESS_PX
	if _locked:
		border_color = _LOCKED_COLOR
	elif not _is_empty and _base != null:
		var r: int = clampi(int(_base.rarity), 0, _RARITY_COLORS.size() - 1)
		border_color = _RARITY_COLORS[r]
		border_thickness = _RARITY_BORDER_THICKNESS[r]
	draw_rect(rect, border_color, false, border_thickness)
	# Locked overlay: crosshatch pattern to read as "unavailable".
	if _locked:
		var cross_color: Color = Color(0.4, 0.4, 0.4, 0.4)
		draw_line(rect.position, rect.position + rect.size, cross_color, 2.0)
		draw_line(Vector2(rect.position.x + rect.size.x, rect.position.y),
				  Vector2(rect.position.x, rect.position.y + rect.size.y),
				  cross_color, 2.0)
		return
	# Empty-slot "+" mark — makes it obvious this is a placeholder rather
	# than an item rendering as nothing.
	if _is_empty:
		var center: Vector2 = rect.position + rect.size * 0.5
		var arm: float = rect.size.x * 0.18
		var thick: float = 3.0
		draw_line(center + Vector2(-arm, 0), center + Vector2(arm, 0), _EMPTY_PLUS_COLOR, thick)
		draw_line(center + Vector2(0, -arm), center + Vector2(0, arm), _EMPTY_PLUS_COLOR, thick)
		return
	# Glyph — procedural shape keyed by base.icon_glyph (sword/shield/star/
	# generic). Shared helper with ItemPickup so ground drop and UI tile
	# render the same thing. Rarity pips drawn on top.
	if not _is_empty and _base != null:
		var center: Vector2 = rect.position + rect.size * 0.5
		ItemGlyph.draw(self, _base.icon_glyph, center, GLYPH_RADIUS_PX, _base.icon_color)
		ItemGlyph.draw_rarity_pips(self, int(_base.rarity), center, GLYPH_RADIUS_PX)
	# Armed outline — drawn over everything, pulsing-y color.
	if _armed:
		var armed_rect: Rect2 = rect.grow(-1.0)
		draw_rect(armed_rect, _ARMED_COLOR, false, ARMED_RING_THICKNESS_PX)
	# IP-3 — pin glyph in the upper-right when the item is locked-for-sale.
	# Small filled rect with a U-shaped shackle so it reads as a padlock at
	# this size; uses pure draw primitives so no font dependency.
	if _locked_for_sale and not _is_empty:
		var pad_size: Vector2 = Vector2(18.0, 18.0)
		var pad_pos: Vector2 = rect.position + Vector2(rect.size.x - pad_size.x - 4.0, 4.0)
		var pad_rect: Rect2 = Rect2(pad_pos, pad_size)
		draw_rect(pad_rect, Color(0.95, 0.85, 0.3, 0.95), true)
		draw_rect(pad_rect, Color(0.2, 0.16, 0.05, 1.0), false, 2.0)
		# Shackle — a small arc above the body, drawn as two short verticals
		# so we don't pull in draw_arc (cheap, readable).
		var shackle_y0: float = pad_pos.y - 5.0
		var shackle_y1: float = pad_pos.y + 1.0
		draw_line(Vector2(pad_pos.x + 4.0, shackle_y0), Vector2(pad_pos.x + 4.0, shackle_y1), Color(0.2, 0.16, 0.05, 1.0), 2.0)
		draw_line(Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y0), Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y1), Color(0.2, 0.16, 0.05, 1.0), 2.0)
		draw_line(Vector2(pad_pos.x + 4.0, shackle_y0), Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y0), Color(0.2, 0.16, 0.05, 1.0), 2.0)


