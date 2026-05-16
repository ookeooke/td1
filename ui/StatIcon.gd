extends RefCounted
class_name StatIcon

# Phase 49 — procedural stat glyph renderer for the Equipment screen's
# Stats panel. Mirrors the ItemGlyph pattern: static class, single public
# `draw` entry point that matches on the stat kind name.
#
# Each glyph is centered on `center` and sized to fit within `radius`.
# `fill_color` is the primary tint. Drawing primitives only — no fonts,
# no sprite assets.


static func draw(canvas: CanvasItem, kind: String, center: Vector2, radius: float, fill_color: Color) -> void:
	# Kind names match the keys returned by EquipmentScreen._compute_stats_dict
	# so the same string both selects the glyph and drives stat formatting.
	match kind:
		"damage":
			_draw_damage(canvas, center, radius, fill_color)
		"dps":
			# Phase 53 — DPS is "damage per second"; reuse the sword glyph so
			# the player sees a unified offense icon. Could be replaced with
			# a sword-with-clock composite later.
			_draw_damage(canvas, center, radius, fill_color)
		"attack_speed":
			_draw_atk_speed(canvas, center, radius, fill_color)
		"attack_range":
			_draw_attack_range(canvas, center, radius, fill_color)
		"max_health":
			_draw_max_hp(canvas, center, radius, fill_color)
		"armor":
			_draw_armor(canvas, center, radius, fill_color)
		"magic_resist":
			# Phase 53 — magic resist mirrors armor's defensive role; reuse the
			# shield glyph for consistency with the DEFENSE section grouping.
			_draw_armor(canvas, center, radius, fill_color)
		"move_speed":
			_draw_move_speed(canvas, center, radius, fill_color)
		"xp_gain_mult":
			_draw_xp_gain(canvas, center, radius, fill_color)
		_:
			_draw_dot(canvas, center, radius, fill_color)


static func _outline_color(fill: Color) -> Color:
	return fill.darkened(0.5)


# Sword tip — small upward-pointing diamond suggesting a blade. Compact,
# reads at 18-24 px sizes used by stat rows.
static func _draw_damage(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts := PackedVector2Array([
		c + Vector2(0, -r * 0.95),         # tip
		c + Vector2(r * 0.30, -r * 0.10),  # right shoulder
		c + Vector2(r * 0.12, r * 0.40),   # right hilt
		c + Vector2(-r * 0.12, r * 0.40),  # left hilt
		c + Vector2(-r * 0.30, -r * 0.10), # left shoulder
	])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), outline, 1.2, true)
	# Crossguard — tiny horizontal bar.
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.40), Vector2(r * 0.9, r * 0.18)), col.darkened(0.2), true)
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.40), Vector2(r * 0.9, r * 0.18)), outline, false, 1.0)


# Lightning bolt — zig-zag for attack speed. Reads as "fast / electric".
static func _draw_atk_speed(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts := PackedVector2Array([
		c + Vector2(r * 0.10, -r * 0.95),    # top right
		c + Vector2(-r * 0.45, r * 0.05),    # mid-left elbow
		c + Vector2(-r * 0.10, r * 0.05),    # mid notch
		c + Vector2(-r * 0.30, r * 0.95),    # bottom-left tip
		c + Vector2(r * 0.45, -r * 0.10),    # right elbow
		c + Vector2(r * 0.10, -r * 0.10),    # mid-right notch
	])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), outline, 1.2, true)


# Crosshair ring for attack range. This keeps range visually distinct from
# damage and speed while staying legible at compact stat-row sizes.
static func _draw_attack_range(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	canvas.draw_circle(c, r * 0.72, col.darkened(0.15))
	canvas.draw_arc(c, r * 0.72, 0.0, TAU, 24, outline, 1.4, true)
	canvas.draw_arc(c, r * 0.36, 0.0, TAU, 18, outline, 1.0, true)
	canvas.draw_line(c + Vector2(-r * 0.95, 0), c + Vector2(-r * 0.25, 0), outline, 1.2)
	canvas.draw_line(c + Vector2(r * 0.25, 0), c + Vector2(r * 0.95, 0), outline, 1.2)
	canvas.draw_line(c + Vector2(0, -r * 0.95), c + Vector2(0, -r * 0.25), outline, 1.2)
	canvas.draw_line(c + Vector2(0, r * 0.25), c + Vector2(0, r * 0.95), outline, 1.2)


# Heart — classic two-lobe + point silhouette for HP.
static func _draw_max_hp(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Two top lobes drawn as filled circles.
	var lobe_r: float = r * 0.40
	var lobe_y: float = -r * 0.30
	canvas.draw_circle(c + Vector2(-r * 0.35, lobe_y), lobe_r, col)
	canvas.draw_circle(c + Vector2(r * 0.35, lobe_y), lobe_r, col)
	# Triangular bottom that meets at the point.
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.75, lobe_y),
		c + Vector2(r * 0.75, lobe_y),
		c + Vector2(0, r * 0.95),
	])
	canvas.draw_colored_polygon(pts, col)
	# Outline — left arc, top crease between lobes, right arc, then triangle.
	canvas.draw_arc(c + Vector2(-r * 0.35, lobe_y), lobe_r, PI, TAU, 12, outline, 1.2, true)
	canvas.draw_arc(c + Vector2(r * 0.35, lobe_y), lobe_r, PI, TAU, 12, outline, 1.2, true)
	canvas.draw_line(c + Vector2(-r * 0.75, lobe_y), c + Vector2(0, r * 0.95), outline, 1.2)
	canvas.draw_line(c + Vector2(r * 0.75, lobe_y), c + Vector2(0, r * 0.95), outline, 1.2)


# Shield — small heater-shield silhouette for armor.
static func _draw_armor(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.65, -r * 0.85),
		c + Vector2(r * 0.65, -r * 0.85),
		c + Vector2(r * 0.70, -r * 0.10),
		c + Vector2(0, r * 0.95),
		c + Vector2(-r * 0.70, -r * 0.10),
	])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), outline, 1.2, true)
	# Center divider line for shield-like read.
	canvas.draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.95), col.darkened(0.3), 1.5)


# Forward chevron arrow for move speed.
static func _draw_move_speed(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Two stacked chevrons pointing right — clear "movement" read.
	for i in 2:
		var x_offset: float = (float(i) - 0.5) * r * 0.45
		var pts := PackedVector2Array([
			c + Vector2(x_offset - r * 0.30, -r * 0.55),
			c + Vector2(x_offset + r * 0.10, 0),
			c + Vector2(x_offset - r * 0.30, r * 0.55),
			c + Vector2(x_offset - r * 0.10, 0),
		])
		canvas.draw_colored_polygon(pts, col)
		canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), outline, 1.0, true)


# 4-point star for XP gain — bright, "reward" feel.
static func _draw_xp_gain(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var outer: float = r * 0.95
	var inner: float = r * 0.30
	var pts := PackedVector2Array([
		c + Vector2(0, -outer),
		c + Vector2(inner, -inner),
		c + Vector2(outer, 0),
		c + Vector2(inner, inner),
		c + Vector2(0, outer),
		c + Vector2(-inner, inner),
		c + Vector2(-outer, 0),
		c + Vector2(-inner, -inner),
	])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array(pts + PackedVector2Array([pts[0]])), outline, 1.2, true)


# Generic fallback — a filled circle with outline. Used when the kind
# name isn't recognized.
static func _draw_dot(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	canvas.draw_circle(c, r * 0.7, col)
	canvas.draw_arc(c, r * 0.7, 0.0, TAU, 16, outline, 1.2, true)
