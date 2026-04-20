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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(_instance)
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit(_instance)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var bg: Color = _EMPTY_BG if _is_empty else _FILLED_BG
	draw_rect(rect, bg, true)
	# Border — rarity-tinted when filled, grey when empty, dark when locked.
	var border_color: Color = _EMPTY_BORDER
	if _locked:
		border_color = _LOCKED_COLOR
	elif not _is_empty and _base != null:
		var r: int = clampi(int(_base.rarity), 0, _RARITY_COLORS.size() - 1)
		border_color = _RARITY_COLORS[r]
	draw_rect(rect, border_color, false, BORDER_THICKNESS_PX)
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


