extends CanvasLayer

# Phase 47d-3: minimal transient-message layer. Call `Toast.show_message("…")`
# from anywhere to display a floating label for 1.8s. Used today for locked-
# slot feedback; reusable by any "can't do that right now" UX in the future.
#
# One CanvasLayer at a high layer (99) so it paints above gameplay and the
# radial menu. Not part of the camera — uses screen coordinates.

const DURATION: float = 1.8
const FADE_IN: float = 0.15
const FADE_OUT: float = 0.35

var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.modulate.a = 0.0
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.7
	_label.anchor_bottom = 0.7
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = 0.0
	_label.offset_bottom = 40.0
	add_child(_label)


func show_message(text: String) -> void:
	if _label == null:
		return
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(DURATION - FADE_IN - FADE_OUT)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
