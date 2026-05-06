extends RefCounted
class_name HubTabIcon

# Hero hub — procedural glyph renderer for the segment bar (Loadout / Stats /
# Equipment / Skills / Talents). Mirrors StatIcon / ItemGlyph: static class,
# single public `draw` entry point, drawing primitives only.


static func draw(canvas: CanvasItem, kind: String, center: Vector2, radius: float, fill: Color) -> void:
	match kind:
		"loadout":
			_draw_loadout(canvas, center, radius, fill)
		"stats":
			_draw_stats(canvas, center, radius, fill)
		"equipment":
			_draw_equipment(canvas, center, radius, fill)
		"skills":
			_draw_skills(canvas, center, radius, fill)
		"talents":
			_draw_talents(canvas, center, radius, fill)
		"overview":
			_draw_overview(canvas, center, radius, fill)
		_:
			canvas.draw_circle(center, radius * 0.6, fill)


static func _outline(c: Color) -> Color:
	return c.darkened(0.5)


# Helmet silhouette — rounded crown + visor slit. Reads as "the hero".
static func _draw_loadout(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.75, -r * 0.10),
		c + Vector2(-r * 0.65, -r * 0.70),
		c + Vector2(-r * 0.30, -r * 0.95),
		c + Vector2(r * 0.30, -r * 0.95),
		c + Vector2(r * 0.65, -r * 0.70),
		c + Vector2(r * 0.75, -r * 0.10),
		c + Vector2(r * 0.55, r * 0.55),
		c + Vector2(-r * 0.55, r * 0.55),
	])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), ol, 1.2, true)
	# Visor slit — horizontal dark band across the lower face.
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.05), Vector2(r * 1.10, r * 0.20)), col.darkened(0.55), true)
	# Plume nub on top.
	canvas.draw_circle(c + Vector2(0, -r * 0.95), r * 0.10, col.lightened(0.2))


# Crossed swords — two diagonal blades meeting at center, stat-like read.
static func _draw_stats(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	# Diagonal NW→SE blade.
	var b1 := PackedVector2Array([
		c + Vector2(-r * 0.85, -r * 0.85),
		c + Vector2(-r * 0.55, -r * 0.85),
		c + Vector2(r * 0.85, r * 0.55),
		c + Vector2(r * 0.85, r * 0.85),
		c + Vector2(r * 0.55, r * 0.85),
		c + Vector2(-r * 0.85, -r * 0.55),
	])
	canvas.draw_colored_polygon(b1, col)
	canvas.draw_polyline(PackedVector2Array(b1 + PackedVector2Array([b1[0]])), ol, 1.0, true)
	# Diagonal NE→SW blade.
	var b2 := PackedVector2Array([
		c + Vector2(r * 0.85, -r * 0.85),
		c + Vector2(r * 0.55, -r * 0.85),
		c + Vector2(-r * 0.85, r * 0.55),
		c + Vector2(-r * 0.85, r * 0.85),
		c + Vector2(-r * 0.55, r * 0.85),
		c + Vector2(r * 0.85, -r * 0.55),
	])
	canvas.draw_colored_polygon(b2, col)
	canvas.draw_polyline(PackedVector2Array(b2 + PackedVector2Array([b2[0]])), ol, 1.0, true)
	# Center pommel disc.
	canvas.draw_circle(c, r * 0.18, col.darkened(0.2))
	canvas.draw_arc(c, r * 0.18, 0.0, TAU, 12, ol, 1.0, true)


# Shield + sword — equipment iconography. Shield behind, sword on top.
static func _draw_equipment(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	# Shield (left side).
	var sh := PackedVector2Array([
		c + Vector2(-r * 0.85, -r * 0.65),
		c + Vector2(-r * 0.05, -r * 0.65),
		c + Vector2(0.0, -r * 0.10),
		c + Vector2(-r * 0.45, r * 0.85),
		c + Vector2(-r * 0.90, -r * 0.10),
	])
	canvas.draw_colored_polygon(sh, col.darkened(0.15))
	canvas.draw_polyline(PackedVector2Array(sh + PackedVector2Array([sh[0]])), ol, 1.0, true)
	# Sword pointing up-right, slightly offset to the right.
	var sw := PackedVector2Array([
		c + Vector2(r * 0.80, -r * 0.95),    # tip
		c + Vector2(r * 0.90, -r * 0.85),
		c + Vector2(r * 0.10, r * 0.05),     # blade base right
		c + Vector2(r * 0.00, -r * 0.05),    # blade base left
	])
	canvas.draw_colored_polygon(sw, col.lightened(0.1))
	canvas.draw_polyline(PackedVector2Array(sw + PackedVector2Array([sw[0]])), ol, 1.0, true)
	# Crossguard — short bar perpendicular to the blade.
	var guard := PackedVector2Array([
		c + Vector2(-r * 0.20, r * 0.10),
		c + Vector2(r * 0.05, -r * 0.15),
		c + Vector2(r * 0.30, r * 0.25),
		c + Vector2(r * 0.05, r * 0.50),
	])
	canvas.draw_colored_polygon(guard, col.darkened(0.2))
	canvas.draw_polyline(PackedVector2Array(guard + PackedVector2Array([guard[0]])), ol, 1.0, true)
	# Hilt grip.
	canvas.draw_line(c + Vector2(r * 0.05, r * 0.30), c + Vector2(r * 0.45, r * 0.70), col.darkened(0.35), 3.0)


# Sparkle / starburst — 8-rayed glint for skills. Active "ability" feel.
static func _draw_skills(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	# Long axis rays.
	for angle_deg in [0, 45, 90, 135]:
		var a: float = deg_to_rad(angle_deg)
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var long_r: float = r * 0.95 if angle_deg % 90 == 0 else r * 0.55
		var pts := PackedVector2Array([
			c + dir * long_r,
			c + perp * (r * 0.10),
			c - dir * long_r,
			c - perp * (r * 0.10),
		])
		canvas.draw_colored_polygon(pts, col)
		canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), ol, 0.8, true)
	# Center bright disc.
	canvas.draw_circle(c, r * 0.18, col.lightened(0.4))


# Castle silhouette with crenellations — "Hero Hall" overview.
static func _draw_overview(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	# Main keep body (taller center) + two short side towers.
	var body := PackedVector2Array([
		c + Vector2(-r * 0.85, r * 0.85),
		c + Vector2(-r * 0.85, -r * 0.20),
		c + Vector2(-r * 0.55, -r * 0.20),
		c + Vector2(-r * 0.55, -r * 0.55),
		c + Vector2(-r * 0.20, -r * 0.55),
		c + Vector2(-r * 0.20, -r * 0.85),
		c + Vector2(r * 0.20, -r * 0.85),
		c + Vector2(r * 0.20, -r * 0.55),
		c + Vector2(r * 0.55, -r * 0.55),
		c + Vector2(r * 0.55, -r * 0.20),
		c + Vector2(r * 0.85, -r * 0.20),
		c + Vector2(r * 0.85, r * 0.85),
	])
	canvas.draw_colored_polygon(body, col)
	canvas.draw_polyline(PackedVector2Array(body + PackedVector2Array([body[0]])), ol, 1.0, true)
	# Crenellation notches on the top edges (3 small notches along the top plateau).
	for nx in [-0.55, 0.0, 0.55]:
		var notch := Rect2(c + Vector2(r * (nx - 0.10), -r * 0.85 if nx == 0.0 else -r * 0.55), Vector2(r * 0.20, r * 0.18))
		canvas.draw_rect(notch, col.darkened(0.5), true)
	# Door arch at the base.
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.18, r * 0.30), Vector2(r * 0.36, r * 0.55)), col.darkened(0.55), true)


# 5-point star with inner pip — talents.
static func _draw_talents(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ol: Color = _outline(col)
	var outer: float = r * 0.95
	var inner: float = r * 0.45
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = -PI * 0.5 + i * PI / 5.0
		var rad: float = outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), ol, 1.2, true)
	# Inner pip.
	canvas.draw_circle(c, r * 0.16, col.lightened(0.3))
