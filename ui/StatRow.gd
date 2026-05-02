extends Control
class_name StatRow

# Phase 49 — single row in the Stats panel: procedural icon on the left,
# stat name (small / muted), value (larger / bright). Public flash() method
# tweens the row's modulate to give visual feedback when the stat changes.
#
# Layout:
#   ┌──┬───────────────┬─────────┐
#   │⚔ │ Damage         │      9 │
#   └──┴───────────────┴─────────┘
#     ↑       ↑              ↑
#   icon   name (left)    value (right)

const _ROW_HEIGHT: float = 24.0
const _ICON_SIZE: float = 18.0
const _ICON_LEFT_PAD: float = 4.0
const _NAME_LEFT_PAD: float = 28.0   # icon area + small gap
const _VALUE_RIGHT_PAD: float = 4.0
const _ICON_TINT: Color = Color(0.85, 0.9, 1.0, 1.0)

const _NAME_FONT_SIZE: int = 13
const _VALUE_FONT_SIZE: int = 15
const _NAME_COLOR: Color = Color(0.7, 0.75, 0.85, 1.0)
const _VALUE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

const _FLASH_DURATION: float = 0.6

var _kind: String = ""
var _name_label: Label
var _value_label: Label
var _flash_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, _ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Name label — left-aligned, takes space between icon and value.
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", _NAME_COLOR)
	_name_label.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_name_label.offset_left = _NAME_LEFT_PAD
	_name_label.offset_right = -120.0   # leave room for value column on the right
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_name_label)
	# Value label — right-aligned, fixed width column.
	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", _VALUE_FONT_SIZE)
	_value_label.add_theme_color_override("font_color", _VALUE_COLOR)
	_value_label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_value_label.offset_left = -120.0
	_value_label.offset_right = -_VALUE_RIGHT_PAD
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_value_label)


func setup(kind: String, display_name: String, value_text: String) -> void:
	_kind = kind
	if _name_label != null:
		_name_label.text = display_name
	if _value_label != null:
		_value_label.text = value_text
	queue_redraw()


func update_value(value_text: String) -> void:
	if _value_label != null:
		_value_label.text = value_text


# Flash the row's modulate to `color` then back to white. Used by the
# Stats panel to signal that a stat changed (green = up, red = down).
# Safe to call repeatedly; previous tween is killed first.
func flash(color: Color) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", color, _FLASH_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "modulate", Color.WHITE, _FLASH_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _draw() -> void:
	# Procedural stat icon on the left of the row, centered vertically.
	var icon_center: Vector2 = Vector2(
		_ICON_LEFT_PAD + _ICON_SIZE * 0.5,
		size.y * 0.5,
	)
	StatIcon.draw(self, _kind, icon_center, _ICON_SIZE * 0.5, _ICON_TINT)
