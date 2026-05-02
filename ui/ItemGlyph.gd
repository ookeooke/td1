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
		# Swords — generic "sword" stays as the iron-sword silhouette so any
		# base that wasn't migrated to a specific variant still renders.
		"sword", "sword_iron":
			_draw_sword_iron(canvas, center, radius, fill_color)
		"sword_wooden":
			_draw_sword_wooden(canvas, center, radius, fill_color)
		"sword_starter":
			_draw_sword_starter(canvas, center, radius, fill_color)
		"sword_steel":
			_draw_sword_steel(canvas, center, radius, fill_color)
		"sword_elven":
			_draw_sword_elven(canvas, center, radius, fill_color)
		# Armor — generic "shield" maps to chainmail so legacy bases still
		# render something armor-like rather than a literal shield.
		"shield", "armor_chainmail":
			_draw_armor_chainmail(canvas, center, radius, fill_color)
		"armor_tunic":
			_draw_armor_tunic(canvas, center, radius, fill_color)
		"armor_plate":
			_draw_armor_plate(canvas, center, radius, fill_color)
		# Trinkets / accessories.
		"star", "trinket_charm":
			_draw_star(canvas, center, radius, fill_color)
		"trinket_amulet":
			_draw_amulet(canvas, center, radius, fill_color)
		"trinket_orb":
			_draw_orb(canvas, center, radius, fill_color)
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


# --- Shared shading helpers --------------------------------------------------
# These give every metal/cloth/gem surface a consistent "lit-from-upper-left"
# look. Costs a couple extra primitives per call but turns flat polygons into
# something that reads as 3D.


# Round pommel with highlight crescent + base shadow. Replaces the previous
# flat circle + outline arc combo.
static func _draw_round_pommel_3d(canvas: CanvasItem, pos: Vector2, rad: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	canvas.draw_circle(pos, rad, col)
	# Base shadow — small darker arc on the lower-right.
	canvas.draw_arc(pos, rad * 0.85, PI * 0.0, PI * 0.6, 8, col.darkened(0.45), maxf(1.5, rad * 0.25), true)
	# Highlight — bright crescent on the upper-left.
	canvas.draw_arc(pos, rad * 0.6, PI * 0.9, PI * 1.5, 8, col.lightened(0.5), maxf(1.0, rad * 0.18), true)
	# Outline.
	canvas.draw_arc(pos, rad, 0.0, TAU, 16, outline, 1.5, true)


# Bright stripe down the LEFT edge of a vertical blade — simulates a
# specular highlight catching from upper-left. Use AFTER drawing the blade
# polygon and outline so the highlight paints over them.
static func _draw_blade_highlight(canvas: CanvasItem, top: Vector2, bot: Vector2, col: Color, length_scale: float = 0.85) -> void:
	# Pull the line slightly inward so it sits inside the blade silhouette.
	var hl_top: Vector2 = top.lerp(bot, (1.0 - length_scale) * 0.5)
	var hl_bot: Vector2 = top.lerp(bot, 1.0 - (1.0 - length_scale) * 0.5)
	canvas.draw_line(hl_top, hl_bot, col.lightened(0.55), 1.5)


# Diagonal cross-wrap pattern on a grip rect — looks like leather cord
# wrapped around the handle. Two sets of diagonal lines crossing at ~45°.
static func _draw_grip_wraps(canvas: CanvasItem, rect: Rect2, col: Color, count: int = 4) -> void:
	var wrap_color: Color = col.lightened(0.25)
	wrap_color.a = 0.6
	for i in count:
		var t: float = float(i) / float(count - 1) if count > 1 else 0.5
		var y: float = rect.position.y + rect.size.y * t
		var dy: float = rect.size.y / float(count) * 0.5
		# Diagonal stroke from left edge slightly above to right edge slightly below.
		canvas.draw_line(
			Vector2(rect.position.x, y - dy * 0.3),
			Vector2(rect.position.x + rect.size.x, y + dy * 0.3),
			wrap_color, 1.0)


# Small rivet dot — used on plate armor at hardpoints. Two-tone (dark body +
# tiny lighter highlight).
static func _draw_rivet(canvas: CanvasItem, pos: Vector2, rad: float, col: Color) -> void:
	canvas.draw_circle(pos, rad, col.darkened(0.55))
	canvas.draw_circle(pos + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.4, col.lightened(0.4))


# --- SWORD VARIANTS ----------------------------------------------------------
# All swords share a common skeleton: blade (top), crossguard, grip, pommel.
# Variants differ in blade silhouette (length, taper, curvature) and hilt
# detail (crossguard shape, pommel shape, grip color).


# Iron sword — the standard medieval longsword. Tapered double-edged blade,
# straight crossguard, wrapped grip, round pommel. Reads as the "default"
# sword shape; other variants depart from this.
static func _draw_sword_iron(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Blade — long tapered diamond. Y-coords stretched 1.25× compared to the
	# original 1.7:1 silhouette so the sword fills tall (1×2) inventory tiles.
	var blade_top: Vector2 = c + Vector2(0, -r * 1.19)
	var blade_midL: Vector2 = c + Vector2(-r * 0.18, -r * 0.06)
	var blade_midR: Vector2 = c + Vector2(r * 0.18, -r * 0.06)
	var blade_tipL: Vector2 = c + Vector2(-r * 0.05, -r * 1.13)
	var blade_tipR: Vector2 = c + Vector2(r * 0.05, -r * 1.13)
	var blade := PackedVector2Array([blade_tipL, blade_top, blade_tipR, blade_midR, blade_midL])
	canvas.draw_colored_polygon(blade, col)
	canvas.draw_polyline(PackedVector2Array([blade_tipL, blade_top, blade_tipR, blade_midR, blade_midL, blade_tipL]), outline, 1.5, true)
	# Center fuller — thin darker line down the blade.
	canvas.draw_line(c + Vector2(0, -r * 1.06), c + Vector2(0, -r * 0.13), outline, 1.0)
	# Specular highlight on the LEFT edge of the blade.
	_draw_blade_highlight(canvas, c + Vector2(-r * 0.08, -r * 1.06), c + Vector2(-r * 0.13, -r * 0.13), col)
	# Crossguard — straight horizontal bar with edge highlight on top.
	var cg_rect: Rect2 = Rect2(c + Vector2(-r * 0.55, -r * 0.13), Vector2(r * 1.1, r * 0.19))
	canvas.draw_rect(cg_rect, col, true)
	canvas.draw_rect(cg_rect, outline, false, 1.5)
	canvas.draw_line(cg_rect.position, cg_rect.position + Vector2(cg_rect.size.x, 0), col.lightened(0.4), 1.0)
	# Grip with diagonal leather wraps.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.12, r * 0.10), Vector2(r * 0.24, r * 0.56))
	canvas.draw_rect(hilt_rect, col.darkened(0.5), true)
	canvas.draw_rect(hilt_rect, outline, false, 1.5)
	_draw_grip_wraps(canvas, hilt_rect, col, 5)
	# Pommel — round knob with 3D shading.
	_draw_round_pommel_3d(canvas, c + Vector2(0, r * 0.78), r * 0.12, col)


# Wooden sword — short stubby blade, no metal crossguard, plank-flat shape.
# Reads as a beginner / training implement.
static func _draw_sword_wooden(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Blade — flat plank, blunt rounded tip. Y-coords stretched 1.25× so it
	# fills tall tiles like the iron sword does.
	var blade_rect: Rect2 = Rect2(c + Vector2(-r * 0.13, -r * 0.875), Vector2(r * 0.26, r * 0.81))
	canvas.draw_rect(blade_rect, col, true)
	canvas.draw_rect(blade_rect, outline, false, 1.5)
	# Wood grain — two faint vertical lines + a knot detail.
	canvas.draw_line(c + Vector2(-r * 0.05, -r * 0.81), c + Vector2(-r * 0.05, -r * 0.13), outline, 1.0)
	canvas.draw_line(c + Vector2(r * 0.05, -r * 0.78), c + Vector2(r * 0.05, -r * 0.15), outline, 1.0)
	# Knot — small ellipse-ish darker spot mid-blade.
	canvas.draw_circle(c + Vector2(r * 0.07, -r * 0.50), r * 0.04, col.darkened(0.35))
	# Highlight stripe along the LEFT edge for "polished wood" feel.
	_draw_blade_highlight(canvas, c + Vector2(-r * 0.1, -r * 0.81), c + Vector2(-r * 0.1, -r * 0.13), col, 0.9)
	# Tiny wooden cap — substitute for crossguard.
	var cap_rect: Rect2 = Rect2(c + Vector2(-r * 0.22, -r * 0.10), Vector2(r * 0.44, r * 0.15))
	canvas.draw_rect(cap_rect, col.darkened(0.25), true)
	canvas.draw_rect(cap_rect, outline, false, 1.5)
	canvas.draw_line(cap_rect.position, cap_rect.position + Vector2(cap_rect.size.x, 0), col.lightened(0.3), 1.0)
	# Round grip — short.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.1, r * 0.075), Vector2(r * 0.2, r * 0.5))
	canvas.draw_rect(hilt_rect, col.darkened(0.45), true)
	canvas.draw_rect(hilt_rect, outline, false, 1.5)
	# Wood grain on the grip.
	canvas.draw_line(hilt_rect.position + Vector2(hilt_rect.size.x * 0.5, 0),
					 hilt_rect.position + Vector2(hilt_rect.size.x * 0.5, hilt_rect.size.y),
					 outline, 0.8)
	# Bottom cap (no fancy pommel).
	var btm_rect: Rect2 = Rect2(c + Vector2(-r * 0.13, r * 0.575), Vector2(r * 0.26, r * 0.10))
	canvas.draw_rect(btm_rect, col.darkened(0.25), true)
	canvas.draw_rect(btm_rect, outline, false, 1.0)


# Starter / training sword — basic shape, worn-looking with chips on the
# blade edge to convey "well-used."
static func _draw_sword_starter(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Y-coords stretched 1.25× for tall-tile fill.
	var blade_top: Vector2 = c + Vector2(0, -r * 1.06)
	var blade_midL: Vector2 = c + Vector2(-r * 0.20, -r * 0.06)
	var blade_midR: Vector2 = c + Vector2(r * 0.20, -r * 0.06)
	# Two notches on the right edge — visible blade chips.
	var blade := PackedVector2Array([
		blade_midL,
		c + Vector2(-r * 0.06, -r * 0.975),
		blade_top,
		c + Vector2(r * 0.06, -r * 0.975),
		c + Vector2(r * 0.13, -r * 0.69),
		c + Vector2(r * 0.18, -r * 0.625),  # chip in
		c + Vector2(r * 0.13, -r * 0.525),  # chip out
		blade_midR,
	])
	canvas.draw_colored_polygon(blade, col)
	var ring: PackedVector2Array = blade.duplicate()
	ring.append(blade[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	# Specular highlight along left edge — partial because the blade is worn.
	_draw_blade_highlight(canvas, c + Vector2(-r * 0.10, -r * 0.975), c + Vector2(-r * 0.15, -r * 0.13), col, 0.7)
	# Crossguard.
	var cg_rect: Rect2 = Rect2(c + Vector2(-r * 0.5, -r * 0.125), Vector2(r * 1.0, r * 0.16))
	canvas.draw_rect(cg_rect, col.darkened(0.15), true)
	canvas.draw_rect(cg_rect, outline, false, 1.5)
	canvas.draw_line(cg_rect.position, cg_rect.position + Vector2(cg_rect.size.x, 0), col.lightened(0.3), 1.0)
	# Grip with diagonal leather wraps.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.11, r * 0.06), Vector2(r * 0.22, r * 0.525))
	canvas.draw_rect(hilt_rect, col.darkened(0.55), true)
	canvas.draw_rect(hilt_rect, outline, false, 1.5)
	_draw_grip_wraps(canvas, hilt_rect, col, 4)
	# Small flat pommel — square cap with edge highlight.
	var pommel_rect: Rect2 = Rect2(c + Vector2(-r * 0.1, r * 0.6), Vector2(r * 0.2, r * 0.125))
	canvas.draw_rect(pommel_rect, col, true)
	canvas.draw_rect(pommel_rect, outline, false, 1.0)
	canvas.draw_line(pommel_rect.position, pommel_rect.position + Vector2(pommel_rect.size.x, 0), col.lightened(0.4), 1.0)


# Steel sword — refined: slightly longer blade with prominent fuller, swept
# crossguard with curled tips, faceted diamond pommel.
static func _draw_sword_steel(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Long tapered blade. Y-coords stretched 1.25× for tall-tile fill.
	var blade := PackedVector2Array([
		c + Vector2(-r * 0.15, -r * 0.06),
		c + Vector2(-r * 0.04, -r * 1.15),
		c + Vector2(0, -r * 1.225),
		c + Vector2(r * 0.04, -r * 1.15),
		c + Vector2(r * 0.15, -r * 0.06),
	])
	canvas.draw_colored_polygon(blade, col)
	var ring: PackedVector2Array = blade.duplicate()
	ring.append(blade[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	# Prominent fuller — two parallel lines down the blade.
	canvas.draw_line(c + Vector2(-r * 0.04, -r * 1.06), c + Vector2(-r * 0.03, -r * 0.13), outline, 1.0)
	canvas.draw_line(c + Vector2(r * 0.04, -r * 1.06), c + Vector2(r * 0.03, -r * 0.13), outline, 1.0)
	# Specular highlight along the LEFT blade edge — strongest of all swords.
	_draw_blade_highlight(canvas, c + Vector2(-r * 0.07, -r * 1.125), c + Vector2(-r * 0.12, -r * 0.13), col, 0.92)
	# Swept crossguard — central rectangular bar plus two triangular curled
	# tips pointing up-and-out at each end.
	var cg_main: Rect2 = Rect2(c + Vector2(-r * 0.5, -r * 0.06), Vector2(r * 1.0, r * 0.15))
	canvas.draw_rect(cg_main, col, true)
	canvas.draw_rect(cg_main, outline, false, 1.5)
	# Curled tip triangles (left + right pointing UP).
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.5, -r * 0.06),
		c + Vector2(-r * 0.7, -r * 0.06),
		c + Vector2(-r * 0.55, -r * 0.225),
	]), col)
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(r * 0.5, -r * 0.06),
		c + Vector2(r * 0.7, -r * 0.06),
		c + Vector2(r * 0.55, -r * 0.225),
	]), col)
	# Grip with diagonal wraps.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.1, r * 0.0875), Vector2(r * 0.2, r * 0.525))
	canvas.draw_rect(hilt_rect, col.darkened(0.55), true)
	canvas.draw_rect(hilt_rect, outline, false, 1.5)
	_draw_grip_wraps(canvas, hilt_rect, col, 5)
	# Diamond pommel with facet highlight.
	var pommel := PackedVector2Array([
		c + Vector2(0, r * 0.625),
		c + Vector2(r * 0.14, r * 0.775),
		c + Vector2(0, r * 0.925),
		c + Vector2(-r * 0.14, r * 0.775),
	])
	canvas.draw_colored_polygon(pommel, col)
	# Upper-left facet — bright triangle inside the diamond.
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, r * 0.625),
		c + Vector2(-r * 0.14, r * 0.775),
		c + Vector2(-r * 0.05, r * 0.75),
	]), col.lightened(0.5))
	# Lower-right facet — darker triangle.
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, r * 0.925),
		c + Vector2(r * 0.14, r * 0.775),
		c + Vector2(r * 0.05, r * 0.825),
	]), col.darkened(0.4))
	var pring: PackedVector2Array = pommel.duplicate()
	pring.append(pommel[0])
	canvas.draw_polyline(pring, outline, 1.5, true)


# Elven blade — leaf-shaped curved blade, ornate swept crossguard with branch
# motif, slim wrapped grip, teardrop pommel. Slimmer + more flowing than the
# heavy iron/steel sword.
static func _draw_sword_elven(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Leaf-shaped blade — bulges in the middle, tapers at both top and base.
	# Y-coords stretched 1.25× for tall-tile fill.
	var blade := PackedVector2Array([
		c + Vector2(-r * 0.06, -r * 0.06),
		c + Vector2(-r * 0.18, -r * 0.5),
		c + Vector2(-r * 0.14, -r * 0.875),
		c + Vector2(0, -r * 1.19),
		c + Vector2(r * 0.14, -r * 0.875),
		c + Vector2(r * 0.18, -r * 0.5),
		c + Vector2(r * 0.06, -r * 0.06),
	])
	canvas.draw_colored_polygon(blade, col)
	var ring: PackedVector2Array = blade.duplicate()
	ring.append(blade[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	# Center vein.
	canvas.draw_line(c + Vector2(0, -r * 1.06), c + Vector2(0, -r * 0.13), outline, 1.0)
	# Bright specular along the LEFT edge — leaf blade catching light.
	_draw_blade_highlight(canvas, c + Vector2(-r * 0.10, -r * 0.875), c + Vector2(-r * 0.10, -r * 0.19), col, 0.85)
	# Small magical glint near the tip — tiny lightened triangle.
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r * 1.19),
		c + Vector2(-r * 0.05, -r * 0.975),
		c + Vector2(r * 0.05, -r * 0.975),
	]), col.lightened(0.5))
	# Ornate crossguard — base wedge + branch flourish accent. Drawn as two
	# simple polygons per side so the triangulator never sees a self-
	# intersecting outline. The flourish triangle overlaps the wedge for the
	# decorative "curl" read without forming a non-simple polygon.
	var cg_left_base := PackedVector2Array([
		c + Vector2(-r * 0.06, -r * 0.05),    # near-blade top
		c + Vector2(-r * 0.60, -r * 0.225),   # curled tip (up + outward)
		c + Vector2(-r * 0.55,  r * 0.00),    # far-left mid
		c + Vector2(-r * 0.06,  r * 0.06),    # near-blade bottom
	])
	canvas.draw_colored_polygon(cg_left_base, col)
	canvas.draw_polyline(PackedVector2Array(cg_left_base + PackedVector2Array([cg_left_base[0]])), outline, 1.3, true)
	var cg_left_curl := PackedVector2Array([
		c + Vector2(-r * 0.55,  r * 0.00),
		c + Vector2(-r * 0.40, -r * 0.06),
		c + Vector2(-r * 0.30,  r * 0.04),
	])
	canvas.draw_colored_polygon(cg_left_curl, col.darkened(0.15))
	canvas.draw_polyline(PackedVector2Array(cg_left_curl + PackedVector2Array([cg_left_curl[0]])), outline, 1.0, true)
	var cg_right_base := PackedVector2Array([
		c + Vector2(r * 0.06, -r * 0.05),
		c + Vector2(r * 0.60, -r * 0.225),
		c + Vector2(r * 0.55,  r * 0.00),
		c + Vector2(r * 0.06,  r * 0.06),
	])
	canvas.draw_colored_polygon(cg_right_base, col)
	canvas.draw_polyline(PackedVector2Array(cg_right_base + PackedVector2Array([cg_right_base[0]])), outline, 1.3, true)
	var cg_right_curl := PackedVector2Array([
		c + Vector2(r * 0.55,  r * 0.00),
		c + Vector2(r * 0.40, -r * 0.06),
		c + Vector2(r * 0.30,  r * 0.04),
	])
	canvas.draw_colored_polygon(cg_right_curl, col.darkened(0.15))
	canvas.draw_polyline(PackedVector2Array(cg_right_curl + PackedVector2Array([cg_right_curl[0]])), outline, 1.0, true)
	# Slim grip with diagonal wraps.
	var hilt_rect: Rect2 = Rect2(c + Vector2(-r * 0.07, r * 0.06), Vector2(r * 0.14, r * 0.56))
	canvas.draw_rect(hilt_rect, col.darkened(0.6), true)
	canvas.draw_rect(hilt_rect, outline, false, 1.2)
	_draw_grip_wraps(canvas, hilt_rect, col, 5)
	# Teardrop pommel with highlight + a tiny embedded gem.
	var pommel := PackedVector2Array([
		c + Vector2(-r * 0.11, r * 0.625),
		c + Vector2(0, r * 0.575),
		c + Vector2(r * 0.11, r * 0.625),
		c + Vector2(r * 0.13, r * 0.775),
		c + Vector2(0, r * 0.975),
		c + Vector2(-r * 0.13, r * 0.775),
	])
	canvas.draw_colored_polygon(pommel, col)
	# Highlight crescent on the upper-left of the pommel.
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.11, r * 0.625),
		c + Vector2(0, r * 0.575),
		c + Vector2(-r * 0.04, r * 0.69),
		c + Vector2(-r * 0.10, r * 0.75),
	]), col.lightened(0.45))
	canvas.draw_polyline(PackedVector2Array(pommel + PackedVector2Array([pommel[0]])), outline, 1.3, true)
	# Embedded gem — small bright dot near the center of the pommel.
	canvas.draw_circle(c + Vector2(0, r * 0.75), r * 0.04, col.lightened(0.6))


# --- ARMOR VARIANTS ----------------------------------------------------------
# All armor variants use a chest-piece silhouette (NOT a shield) — squared
# torso shape with a neck cutout at top + sleeve stubs at the shoulders.
# Variants differ in surface detail: cloth = stitching, mail = link grid,
# plate = breastplate seam + pauldrons.


# Helper — base chest silhouette polygon shared by all armor variants.
static func _armor_chest_polygon(c: Vector2, r: float) -> PackedVector2Array:
	# Coordinates traced clockwise starting at top-left of neck.
	return PackedVector2Array([
		c + Vector2(-r * 0.25, -r * 0.85),   # neck-left top
		c + Vector2(-r * 0.6, -r * 0.7),     # left shoulder out
		c + Vector2(-r * 0.85, -r * 0.55),   # outer shoulder peak
		c + Vector2(-r * 0.7, -r * 0.4),     # underarm
		c + Vector2(-r * 0.7, r * 0.7),      # bottom-left
		c + Vector2(-r * 0.5, r * 0.9),      # hip flare
		c + Vector2(r * 0.5, r * 0.9),       # hip flare
		c + Vector2(r * 0.7, r * 0.7),       # bottom-right
		c + Vector2(r * 0.7, -r * 0.4),      # underarm
		c + Vector2(r * 0.85, -r * 0.55),    # outer shoulder peak
		c + Vector2(r * 0.6, -r * 0.7),      # right shoulder out
		c + Vector2(r * 0.25, -r * 0.85),    # neck-right top
		c + Vector2(0, -r * 0.7),            # neckline V
	])


# Padded tunic — cloth silhouette with cross-stitch lines, no metal hardware.
# Reads as starter / commoner gear.
static func _draw_armor_tunic(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts: PackedVector2Array = _armor_chest_polygon(c, r)
	canvas.draw_colored_polygon(pts, col)
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	# Soft cloth highlight along the upper-left of the chest silhouette.
	canvas.draw_line(c + Vector2(-r * 0.55, -r * 0.65), c + Vector2(-r * 0.6, r * 0.4), col.lightened(0.3), 1.5)
	# Vertical center seam — tunic lacing.
	canvas.draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, r * 0.85), outline, 1.0)
	# Lacing X marks down the center, with small eyelets (dots) at each crossing.
	for i in 4:
		var y: float = r * (-0.4 + i * 0.3)
		var hw: float = r * 0.06
		canvas.draw_line(c + Vector2(-hw, y - hw * 0.5), c + Vector2(hw, y + hw * 0.5), outline, 1.0)
		canvas.draw_line(c + Vector2(-hw, y + hw * 0.5), c + Vector2(hw, y - hw * 0.5), outline, 1.0)
		canvas.draw_circle(c + Vector2(-hw - r * 0.02, y), r * 0.018, outline)
		canvas.draw_circle(c + Vector2(hw + r * 0.02, y), r * 0.018, outline)
	# Collar band at the neck — slightly darker cloth strip with topstitching.
	var collar_rect: Rect2 = Rect2(c + Vector2(-r * 0.28, -r * 0.78), Vector2(r * 0.56, r * 0.12))
	canvas.draw_rect(collar_rect, col.darkened(0.25), true)
	canvas.draw_rect(collar_rect, outline, false, 1.0)
	# Topstitching dashes along the bottom of the collar.
	for i in 5:
		var dx: float = r * (-0.22 + i * 0.11)
		canvas.draw_line(c + Vector2(dx, -r * 0.66), c + Vector2(dx + r * 0.04, -r * 0.66), outline, 0.8)
	# Stitched belt at the waist with buckle.
	canvas.draw_line(c + Vector2(-r * 0.7, r * 0.35), c + Vector2(r * 0.7, r * 0.35), outline, 1.5)
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.05, r * 0.3), Vector2(r * 0.10, r * 0.10)), col.darkened(0.15), true)
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.05, r * 0.3), Vector2(r * 0.10, r * 0.10)), outline, false, 1.0)


# Chain mail — chest silhouette with a grid of small interlocking circles.
# Reads as woven metal rings.
static func _draw_armor_chainmail(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts: PackedVector2Array = _armor_chest_polygon(c, r)
	canvas.draw_colored_polygon(pts, col)
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	# Mail link pattern — small interlocking rings with per-ring highlights so
	# they read as polished metal rather than flat dots. Each ring: outline
	# arc (dark) + tiny lit dot at upper-left for specular catch.
	var dark: Color = col.darkened(0.35)
	var ring_hl: Color = col.lightened(0.4)
	var link_r: float = r * 0.06
	var spacing: float = r * 0.18
	var grid_cols: int = 5
	var rows: int = 6
	var grid_left: float = c.x - spacing * (grid_cols - 1) * 0.5
	var grid_top: float = c.y - r * 0.4
	for row in rows:
		# Stagger every other row so the links interlock visually.
		var row_offset: float = spacing * 0.5 if row % 2 == 1 else 0.0
		for cn in grid_cols:
			var x: float = grid_left + cn * spacing + row_offset
			var y: float = grid_top + row * spacing * 0.85
			# Skip links that fall outside the rough silhouette bounds.
			if absf(x - c.x) > r * 0.62:
				continue
			if y > c.y + r * 0.78:
				continue
			var ring_pos: Vector2 = Vector2(x, y)
			canvas.draw_arc(ring_pos, link_r, 0.0, TAU, 8, dark, 1.2, true)
			# Tiny highlight on the upper-left of the ring.
			canvas.draw_circle(ring_pos + Vector2(-link_r * 0.4, -link_r * 0.4), link_r * 0.3, ring_hl)
	# Mail collar — small darker band around the neck with a top edge highlight.
	var collar: Rect2 = Rect2(c + Vector2(-r * 0.28, -r * 0.85), Vector2(r * 0.56, r * 0.12))
	canvas.draw_rect(collar, col.darkened(0.2), true)
	canvas.draw_rect(collar, outline, false, 1.0)
	canvas.draw_line(collar.position, collar.position + Vector2(collar.size.x, 0), col.lightened(0.4), 1.0)


# Plate armor — full plate silhouette with prominent breastplate, pauldrons,
# and an emblem / chest crest. Reads as heavy metal armor.
static func _draw_armor_plate(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var pts: PackedVector2Array = _armor_chest_polygon(c, r)
	canvas.draw_colored_polygon(pts, col)
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	canvas.draw_polyline(ring, outline, 1.8, true)
	# Bright vertical highlight stripe down the breastplate (light from upper-left).
	canvas.draw_line(c + Vector2(-r * 0.18, -r * 0.55), c + Vector2(-r * 0.18, r * 0.75), col.lightened(0.35), 2.0)
	# Pauldrons — rounded shoulder caps with a bright highlight crescent on
	# top so they read as 3D balls rather than flat circles.
	var dark: Color = col.darkened(0.25)
	var p_left: Vector2 = c + Vector2(-r * 0.65, -r * 0.55)
	var p_right: Vector2 = c + Vector2(r * 0.65, -r * 0.55)
	canvas.draw_circle(p_left, r * 0.22, dark)
	canvas.draw_arc(p_left, r * 0.16, PI * 0.9, PI * 1.5, 8, col.lightened(0.4), 2.0, true)
	canvas.draw_arc(p_left, r * 0.22, 0.0, TAU, 16, outline, 1.5, true)
	canvas.draw_circle(p_right, r * 0.22, dark)
	canvas.draw_arc(p_right, r * 0.16, PI * 0.9, PI * 1.5, 8, col.lightened(0.4), 2.0, true)
	canvas.draw_arc(p_right, r * 0.22, 0.0, TAU, 16, outline, 1.5, true)
	# Vertical breastplate seam.
	canvas.draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.85), outline, 2.0)
	# Horizontal armor segment lines (3 plates: chest, midriff, waist).
	for y_frac in [-0.2, 0.15, 0.5]:
		canvas.draw_line(c + Vector2(-r * 0.65, r * y_frac), c + Vector2(r * 0.65, r * y_frac), outline, 1.2)
	# Chest emblem — small diamond crest at the upper sternum.
	var crest_y: float = -r * 0.4
	var crest := PackedVector2Array([
		c + Vector2(0, crest_y - r * 0.13),
		c + Vector2(r * 0.1, crest_y),
		c + Vector2(0, crest_y + r * 0.13),
		c + Vector2(-r * 0.1, crest_y),
	])
	canvas.draw_colored_polygon(crest, col.lightened(0.3))
	# Crest facet — upper triangle brighter so the diamond reads as faceted.
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, crest_y - r * 0.13),
		c + Vector2(r * 0.1, crest_y),
		c + Vector2(-r * 0.1, crest_y),
	]), col.lightened(0.55))
	canvas.draw_polyline(PackedVector2Array(crest + PackedVector2Array([crest[0]])), outline, 1.0, true)
	# Rivets — six small two-tone dots at structural hardpoints.
	var rivet_r: float = r * 0.05
	for rivet_pos in [
		c + Vector2(-r * 0.55, -r * 0.3),  # upper-left chest
		c + Vector2(r * 0.55, -r * 0.3),   # upper-right chest
		c + Vector2(-r * 0.55, r * 0.05),  # mid-left
		c + Vector2(r * 0.55, r * 0.05),   # mid-right
		c + Vector2(-r * 0.4, r * 0.65),   # hip-left
		c + Vector2(r * 0.4, r * 0.65),    # hip-right
	]:
		_draw_rivet(canvas, rivet_pos, rivet_r, col)


# --- TRINKET VARIANTS --------------------------------------------------------


# Amulet — chain on top, gem-shaped pendant hanging below.
static func _draw_amulet(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	# Chain — V-shape from top-left and top-right meeting at a ring above the gem.
	var ring_pos: Vector2 = c + Vector2(0, -r * 0.35)
	canvas.draw_line(c + Vector2(-r * 0.7, -r * 0.85), ring_pos, col.darkened(0.2), 2.0)
	canvas.draw_line(c + Vector2(r * 0.7, -r * 0.85), ring_pos, col.darkened(0.2), 2.0)
	# Connector ring.
	canvas.draw_arc(ring_pos, r * 0.1, 0.0, TAU, 12, col, 2.5, true)
	# Pendant — teardrop / inverted-pear gem hanging below the ring.
	var pendant := PackedVector2Array([
		ring_pos + Vector2(0, r * 0.05),
		ring_pos + Vector2(r * 0.3, r * 0.4),
		ring_pos + Vector2(r * 0.32, r * 0.7),
		ring_pos + Vector2(0, r * 1.05),
		ring_pos + Vector2(-r * 0.32, r * 0.7),
		ring_pos + Vector2(-r * 0.3, r * 0.4),
	])
	canvas.draw_colored_polygon(pendant, col)
	# Faceted gem — upper-left triangle bright (light catching), lower-right
	# triangle dark (shadow side). Three filled wedges total.
	canvas.draw_colored_polygon(PackedVector2Array([
		ring_pos + Vector2(0, r * 0.05),
		ring_pos + Vector2(-r * 0.3, r * 0.4),
		ring_pos + Vector2(-r * 0.05, r * 0.5),
	]), col.lightened(0.5))
	canvas.draw_colored_polygon(PackedVector2Array([
		ring_pos + Vector2(r * 0.32, r * 0.7),
		ring_pos + Vector2(0, r * 1.05),
		ring_pos + Vector2(r * 0.05, r * 0.7),
	]), col.darkened(0.4))
	canvas.draw_polyline(PackedVector2Array(pendant + PackedVector2Array([pendant[0]])), outline, 1.5, true)
	# Inner facet edges — thin lines from gem center to each silhouette vertex,
	# making the cut faces explicit.
	var gem_center: Vector2 = ring_pos + Vector2(0, r * 0.55)
	for v in [
		ring_pos + Vector2(0, r * 0.05),
		ring_pos + Vector2(r * 0.3, r * 0.4),
		ring_pos + Vector2(r * 0.32, r * 0.7),
		ring_pos + Vector2(0, r * 1.05),
		ring_pos + Vector2(-r * 0.32, r * 0.7),
		ring_pos + Vector2(-r * 0.3, r * 0.4),
	]:
		canvas.draw_line(gem_center, v, outline, 0.8)
	# Center sparkle dot.
	canvas.draw_circle(gem_center, r * 0.04, col.lightened(0.6))


# Demon-core / orb — sphere with concentric rings, suggests a magical core.
static func _draw_orb(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outline: Color = _outline_color(col)
	var orb_r: float = r * 0.7
	# Main sphere.
	canvas.draw_circle(c, orb_r, col)
	# Shadow crescent on lower-right — gives the orb 3D weight.
	canvas.draw_arc(c, orb_r * 0.92, PI * -0.05, PI * 0.5, 10, col.darkened(0.5), 4.0, true)
	# Outer outline.
	canvas.draw_arc(c, orb_r, 0.0, TAU, 24, outline, 2.0, true)
	# Inner ring (darker).
	canvas.draw_arc(c, orb_r * 0.7, 0.0, TAU, 20, col.darkened(0.4), 2.0, true)
	# Energy radii — short rays from the inner ring to the outer ring at four
	# cardinal points, suggesting the core is "wired" to its shell.
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		var v: Vector2 = Vector2(cos(ang), sin(ang))
		canvas.draw_line(c + v * orb_r * 0.7, c + v * orb_r * 0.92, col.darkened(0.3), 1.5)
	# Core dot — bright pulsing center.
	canvas.draw_circle(c, orb_r * 0.28, col.lightened(0.5))
	canvas.draw_circle(c, orb_r * 0.15, col.lightened(0.7))
	canvas.draw_arc(c, orb_r * 0.28, 0.0, TAU, 12, outline, 1.0, true)
	# Highlight crescent — bright arc on the upper-left to suggest 3D.
	canvas.draw_arc(c, orb_r * 0.85, PI * 0.7, PI * 1.25, 10, col.lightened(0.5), 2.5, true)
	# Tiny specular dot on the upper-left edge for that polished gem look.
	canvas.draw_circle(c + Vector2(-orb_r * 0.5, -orb_r * 0.5), orb_r * 0.08, col.lightened(0.8))


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
