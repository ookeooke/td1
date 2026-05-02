extends MarginContainer

# MarginContainer that automatically sets its margins to the display safe
# area. Place as the root Control inside a CanvasLayer — all children are
# pushed inward away from notches, punch-hole cameras, and gesture bars.
#
# On desktop (no notch), margins stay at 0. Recalculates on window resize.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply()
	get_viewport().size_changed.connect(_apply)


func _apply() -> void:
	var insets: Vector4 = DisplayUtils.get_safe_insets()  # top, bottom, left, right
	add_theme_constant_override("margin_top", int(insets.x))
	add_theme_constant_override("margin_bottom", int(insets.y))
	add_theme_constant_override("margin_left", int(insets.z))
	add_theme_constant_override("margin_right", int(insets.w))
