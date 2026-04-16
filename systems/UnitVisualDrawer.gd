extends RefCounted
class_name UnitVisualDrawer

# Static helper that draws a unit body + accent from UnitVisualData.
# Callers use: UnitVisualDrawer.draw_unit(self, visual, offset)
# Does NOT draw health bars, status rings, or selection indicators —
# those remain the responsibility of each unit script.


static func draw_unit(ci: CanvasItem, v: UnitVisualData, offset: Vector2 = Vector2.ZERO) -> void:
	if offset != Vector2.ZERO:
		ci.draw_set_transform(offset, 0.0, Vector2.ONE)

	if v.shape == UnitVisualData.Shape.CIRCLE:
		ci.draw_circle(Vector2.ZERO, v.radius, v.body_color)
		ci.draw_arc(Vector2.ZERO, v.radius, 0, TAU, 24, v.outline_color, v.outline_width)
	else:
		var half: Vector2 = v.body_size * 0.5
		var rect: Rect2 = Rect2(-half, v.body_size)
		ci.draw_rect(rect, v.body_color)
		ci.draw_rect(rect, v.outline_color, false, v.outline_width)

	_draw_accent(ci, v)

	if offset != Vector2.ZERO:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_accent(ci: CanvasItem, v: UnitVisualData) -> void:
	match v.accent_type:
		UnitVisualData.Accent.NONE:
			return
		UnitVisualData.Accent.WEAPON_LINE:
			# Vertical line above body (sword / staff)
			var top: float = -v.body_size.y * 0.5 if v.shape == UnitVisualData.Shape.SQUARE else -v.radius
			ci.draw_line(Vector2(0, top), Vector2(0, top - 6.0), v.accent_color, 2.5)
		UnitVisualData.Accent.CROSSHAIR:
			# Horizontal + vertical cross (healer)
			var r: float = v.radius * 0.45
			ci.draw_line(Vector2(-r, 0), Vector2(r, 0), v.accent_color, 2.0)
			ci.draw_line(Vector2(0, -r), Vector2(0, r), v.accent_color, 2.0)
		UnitVisualData.Accent.WINGS:
			# Horizontal bars extending from sides (flying)
			var r: float = v.radius
			ci.draw_line(Vector2(-r - 6, -2), Vector2(-r, -2), v.accent_color, 2.0)
			ci.draw_line(Vector2(-r - 4, 2), Vector2(-r, 2), v.accent_color, 2.0)
			ci.draw_line(Vector2(r, -2), Vector2(r + 6, -2), v.accent_color, 2.0)
			ci.draw_line(Vector2(r, 2), Vector2(r + 4, 2), v.accent_color, 2.0)
		UnitVisualData.Accent.CROWN:
			# Two angled lines above body (boss crown)
			var top: float = -v.radius
			ci.draw_line(Vector2(-6, top - 2), Vector2(-3, top - 8), v.accent_color, 2.0)
			ci.draw_line(Vector2(6, top - 2), Vector2(3, top - 8), v.accent_color, 2.0)
			ci.draw_line(Vector2(-3, top - 8), Vector2(0, top - 4), v.accent_color, 2.0)
			ci.draw_line(Vector2(3, top - 8), Vector2(0, top - 4), v.accent_color, 2.0)
