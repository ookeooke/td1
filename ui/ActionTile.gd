extends Button
class_name ActionTile

# Phase 50 — Hero Hall deep-link tile. Four of these sit in a row at the
# bottom of HeroHallView (Stats / Equipment / Skills / Talents). Each one
# routes to a sub-view inside HeroesHub.
#
# Visual (200×120):
#   ┌────────────────────────┐
#   │         GLYPH          │
#   │       (HubTabIcon)     │
#   │                        │
#   │       LABEL            │
#   │       subtitle         │
#   └────────────────────────┘

const _TILE_SIZE: Vector2 = Vector2(220, 132)
const _BG: Color = Color(0.13, 0.17, 0.23, 1.0)
const _BG_HOVER: Color = Color(0.18, 0.24, 0.34, 1.0)
const _BORDER: Color = Color(0.28, 0.34, 0.46, 1.0)
const _BORDER_HOVER: Color = Color(1.0, 0.85, 0.4, 1.0)
const _GLYPH_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
const _LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const _SUB_COLOR: Color = Color(0.65, 0.72, 0.85, 1.0)

var _kind: String = ""
var _label_text: String = ""
var _subtitle: String = ""
var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = _TILE_SIZE
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw()
	)


func setup(kind: String, label: String, subtitle: String = "") -> void:
	_kind = kind
	_label_text = label
	_subtitle = subtitle
	queue_redraw()


func set_subtitle(subtitle: String) -> void:
	if _subtitle == subtitle:
		return
	_subtitle = subtitle
	queue_redraw()


func get_kind() -> String:
	return _kind


func _draw() -> void:
	var bg: Color = _BG_HOVER if _hovered else _BG
	var border: Color = _BORDER_HOVER if _hovered else _BORDER
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0 if _hovered else 1.0)
	# Glyph centered upper-half.
	var glyph_center := Vector2(size.x * 0.5, size.y * 0.36)
	HubTabIcon.draw(self, _kind, glyph_center, 22.0, _GLYPH_COLOR)
	# Label + subtitle below the glyph.
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var lbl_size := font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16)
	var lbl_pos := Vector2((size.x - lbl_size.x) * 0.5, size.y * 0.74)
	draw_string(font, lbl_pos, _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, _LABEL_COLOR)
	if _subtitle != "":
		var sub_size := font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12)
		var sub_pos := Vector2((size.x - sub_size.x) * 0.5, size.y * 0.92)
		draw_string(font, sub_pos, _subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, _SUB_COLOR)
