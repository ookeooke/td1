extends RefCounted
class_name ItemGlyph

# Phase 48 F — shared procedural glyph renderer for item icons. Called by
# both ItemIcon (UI tile) and ItemPickup (ground drop) so the same item
# looks identical on the ground and in the inventory.
#
# Each glyph is centered on `center` and sized to fit within a `radius`.
# `fill_color` is the primary tint (typically base.icon_color); shapes use
# darker outlines for readability.
#
# Add a new glyph by adding a case + a _draw_X static func. No Resource
# files involved — pure code.

static func draw(canvas: CanvasItem, glyph: String, center: Vector2, radius: float, fill_color: Color) -> void:
	match glyph:
		"sword":
			_draw_sword(canvas, center, radius, fill_color)
		"shield":
			_draw_shield(canvas, center, radius, fill_color)
		"star":
			_draw_star(canvas, center, radius, fill_color)
		_:
			_draw_generic(canvas, center, radius, fill_color)


# Phase polish — rarity pips. Drawn above the glyph, one small dot per
# tier-above-common. MAGIC=1 blue dot, RARE=2 yellow, EPIC=3 purple,
# LEGENDARY=4 orange. COMMON items render no pips. Called by ItemIcon +
# ItemPickup after the main glyph so pips sit on top.
const _PIP_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.75),   # 0 COMMON  — unused (no pips)
	Color(0.4, 0.7, 1.0),      # 1 MAGIC
	Color(1.0, 0.9, 0.3),      # 2 RARE
	Color(0.8, 0.4, 1.0),      # 3 EPIC
	Color(1.0, 0.55, 0.1),     # 4 LEGENDARY
]


static func draw_rarity_pips(canvas: CanvasItem, rarity: int, center: Vector2, radius: float) -> void:
	if rarity <= 0:
		return   # COMMON: nothing to draw
	var pip_radius: float = maxf(1.5, radius * 0.09)
	var pip_spacing: float = pip_radius * 2.6
	var pip_y: float = center.y - radius * 1.05
	var pip_color: Color = _PIP_COLORS[clampi(rarity, 0, _PIP_COLORS.size() - 1)]
	var count: int = clampi(rarity, 1, 4)   # MAGIC=1, RARE=2, EPIC=3, LEGENDARY=4
	var total_width: float = pip_spacing * (count - 1)
	var start_x: float = center.x - total_width * 0.5
	for i in count:
		var pip_pos: Vector2 = Vector2(start_x + i * pip_spacing, pip_y)
		canvas.draw_circle(pip_pos, pip_radius, pip_color)
		canvas.draw_arc(pip_pos, pip_radius, 0.0, TAU, 10, pip_color.darkened(0.4), 1.0, true)


static func _outline_color(fill: Color) -> Color:
	return fill.darkened(0.55)


static func _draw_sword(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Blade — long vertical trapezoid/diamond from near-top to near-middle.
	var blade_top: Vector2 = c + Vector2(0, -r * 0.95)
	var blade_midL: Vector2 = c + Vector2(-r * 0.18, -r * 0.05)
	var blade_midR: Vector2 = c + Vector2(r * 0.18, -r * 0.05)
	var blade_tipL: Vector2 = c + Vector2(-r * 0.05, -r * 0.9)
	var blade_tipR: Vector2 = c + Vector2(r * 0.05, -r * 0.9)
	var blade := PackedVector2Array([blade_tipL, blade_top, blade_tipR, blade_midR, blade_midL])
	canvas.draw_colored_polygon(blade, col)
	canvas.draw_polyline(PackedVector2Array([blade_tipL, blade_top, blade_tipR, blade_midR, blade_midL, blade_tipL]), outline, 1.5, true)
	# Crossguard — horizontal bar at the blade base.
	var cg_rect: Rect2 = Rect2(c + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.15))
	canvas.draw_rect(cg_rect, col, true)
	canvas.draw_rect(cg_rect, outline, false, 1.5)
	# Hilt — small grip below crossguard.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.12, r * 0.08), Vector2(r * 0.24, r * 0.45))
	canvas.draw_rect(hilt_rect, col, true)
	canvas.draw_rect(hilt_rect, outline, false, 1.5)
	# Pommel — round knob at the bottom.
	canvas.draw_circle(c + Vector2(0, r * 0.62), r * 0.12, col)
	canvas.draw_arc(c + Vector2(0, r * 0.62), r * 0.12, 0.0, TAU, 16, outline, 1.5, true)


static func _draw_shield(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Kite / heater-shield shape — wider at top, tapers to a point.
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.75, -r * 0.85),   # top-left corner
		c + Vector2(r * 0.75, -r * 0.85),    # top-right corner
		c + Vector2(r * 0.85, -r * 0.15),    # mid-right shoulder
		c + Vector2(0, r * 0.9),             # bottom point
		c + Vector2(-r * 0.85, -r * 0.15),   # mid-left shoulder
	])
	canvas.draw_colored_polygon(pts, col)
	var ring := pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 2.0, true)
	# Cross motif — vertical + horizontal bar in darker color.
	var dark: Color = col.darkened(0.3)
	var v_rect: Rect2 = Rect2(c + Vector2(-r * 0.1, -r * 0.75), Vector2(r * 0.2, r * 1.4))
	var h_rect: Rect2 = Rect2(c + Vector2(-r * 0.55, -r * 0.25), Vector2(r * 1.1, r * 0.2))
	canvas.draw_rect(v_rect, dark, true)
	canvas.draw_rect(h_rect, dark, true)


static func _draw_star(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# 5-point star: 10 vertices alternating outer (r) and inner (0.4 * r).
	var outer_r: float = r * 0.95
	var inner_r: float = r * 0.42
	var pts := PackedVector2Array()
	var start_angle: float = -PI * 0.5   # point straight up
	for i in 10:
		var radius: float = outer_r if i % 2 == 0 else inner_r
		var a: float = start_angle + float(i) * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	canvas.draw_colored_polygon(pts, col)
	var ring := pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 1.5, true)


static func _draw_generic(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Diamond — 4 points, rotated square.
	var pts := PackedVector2Array([
		c + Vector2(0, -r * 0.9),
		c + Vector2(r * 0.9, 0),
		c + Vector2(0, r * 0.9),
		c + Vector2(-r * 0.9, 0),
	])
	canvas.draw_colored_polygon(pts, col)
	var ring := pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
