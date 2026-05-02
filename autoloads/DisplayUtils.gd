extends Node

# Display / window utilities. Mobile screen safe-area math lived on
# GameState until 2026-05-01 — moved here because it has nothing to do
# with game state. Two callers today: ui/SafeAreaMargin.gd and any future
# safe-area consumer.


# Returns Vector4(top, bottom, left, right) in logical viewport pixels.
# Safe area from DisplayServer is in screen coordinates; we convert to
# viewport coordinates so UI Controls can use the values directly.
func get_safe_insets() -> Vector4:
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return Vector4(0, 0, 0, 0)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var win_size: Vector2i = DisplayServer.window_get_size()
	var sx: float = vp_size.x / float(win_size.x) if win_size.x > 0 else 1.0
	var sy: float = vp_size.y / float(win_size.y) if win_size.y > 0 else 1.0
	return Vector4(
		float(safe_rect.position.y) * sy,
		float(screen_size.y - safe_rect.position.y - safe_rect.size.y) * sy,
		float(safe_rect.position.x) * sx,
		float(screen_size.x - safe_rect.position.x - safe_rect.size.x) * sx,
	)
