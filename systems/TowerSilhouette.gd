extends RefCounted
class_name TowerSilhouette

# Per-tower-type procedural silhouette. Each draw_* function owns the entire
# visual — base + body + aimable part — so a tower's identity reads at a
# glance ("that's an archer", "that's the mage tower") without relying on a
# generic colored circle. Levels add structural detail: stones become walls,
# bows grow, orbs glow brighter, cannons get bigger.
#
# Dispatch via TowerSilhouette.draw(ci, tower_id, level, branch_idx, tint, aim_angle).
# Falls back to draw_default when an id has no entry.


static func _ellipse_points(center: Vector2, radius_x: float, radius_y: float, segments: int = 28) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radius_x, sin(a) * radius_y))
	return pts


static func _draw_ellipse(ci: CanvasItem, center: Vector2, radius_x: float, radius_y: float, fill: Color, outline: Color = Color(0, 0, 0, 0), outline_width: float = 0.0) -> void:
	var pts: PackedVector2Array = _ellipse_points(center, radius_x, radius_y)
	ci.draw_colored_polygon(pts, fill)
	if outline_width > 0.0:
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), outline, outline_width, true)


static func _draw_ground_pad(ci: CanvasItem, center: Vector2, radius_x: float, radius_y: float, accent: Color) -> void:
	# Cheap procedural footprint: a soft shadow plus a small stone/earth pad.
	# This helps towers read as anchored to the authored Marker2D spot without
	# increasing their collision/tap footprint or changing placement logic.
	_draw_ellipse(ci, center + Vector2(0.0, 4.0), radius_x * 1.05, radius_y * 1.15, Color(0.0, 0.0, 0.0, 0.20))
	_draw_ellipse(ci, center, radius_x, radius_y, Color(0.24, 0.20, 0.14, 0.82) * accent, Color(0.10, 0.08, 0.05, 0.70), 1.5)
	_draw_ellipse(ci, center + Vector2(0.0, -1.5), radius_x * 0.72, radius_y * 0.48, Color(0.55, 0.48, 0.33, 0.16) * accent)


static func _draw_highlight_line(ci: CanvasItem, a: Vector2, b: Vector2, tint: Color, width: float = 1.3) -> void:
	ci.draw_line(a, b, Color(1.0, 0.92, 0.70, 0.22) * tint, width, true)


static func draw(ci: CanvasItem, tower_id: String, level: int, branch_idx: int, tint: Color, aim_angle: float) -> void:
	match tower_id:
		"tower_archer":
			draw_archer(ci, level, branch_idx, tint, aim_angle)
		"tower_mage":
			draw_mage(ci, level, branch_idx, tint, aim_angle)
		"tower_ice":
			draw_ice(ci, level, branch_idx, tint, aim_angle)
		"tower_artillery":
			draw_artillery(ci, level, branch_idx, tint, aim_angle)
		"tower_barracks":
			draw_barracks(ci, level, branch_idx, tint)
		_:
			draw_default(ci, level, tint)


# Local-space muzzle tip per tower type, used by base_tower to spawn the
# muzzle-flash VFX at the actual barrel/tip rather than the tower center.
# Geometry mirrors the silhouette draws above — keep these in sync if the
# silhouette anatomy moves. Returns Vector2.ZERO for non-firing towers
# (barracks) and unknowns; caller skips spawning when so.
static func muzzle_offset(tower_id: String, level: int, aim_angle: float) -> Vector2:
	var dir: Vector2 = Vector2.from_angle(aim_angle)
	match tower_id:
		"tower_archer":
			# Bow center at (0, deck_y - 28 - 5) with deck_y = -10. Arrow tip
			# extends along aim by bow_size * 1.05 (matches draw_archer).
			var bow_anchor: Vector2 = Vector2(0.0, -43.0)
			var bow_size: float = 18.0 + level * 6.0
			if level >= 3:
				bow_size += 4.0
			return bow_anchor + dir * bow_size * 1.05
		"tower_mage":
			# Orb center sits atop the spire; magic streams from the orb edge
			# in aim direction. spire_top_y = -32 - level*6, orb_r = 9 + level*2.5.
			var spire_top_y: float = -32.0 - level * 6.0
			var orb_r: float = 9.0 + level * 2.5
			var orb_pos: Vector2 = Vector2(0.0, spire_top_y - orb_r * 0.6)
			return orb_pos + dir * orb_r
		"tower_ice":
			# Crystal apex at (0, 30 - crystal_h), crystal_h = 50 + level*8.
			var crystal_tip: Vector2 = Vector2(0.0, -20.0 - level * 8.0)
			return crystal_tip + dir * 8.0
		"tower_artillery":
			# Trunnion at (0, -2). Barrel extends barrel_len = 36 + level*6
			# along aim_angle to the muzzle hole.
			var trunnion: Vector2 = Vector2(0.0, -2.0)
			var barrel_len: float = 36.0 + level * 6.0
			return trunnion + dir * barrel_len
	return Vector2.ZERO


# Element tint for the muzzle flash — orange-yellow archer/artillery, cyan
# ice, purple mage. Falls back to a neutral warm white for unknowns.
static func muzzle_color(tower_id: String) -> Color:
	match tower_id:
		"tower_archer":
			return Color(1.0, 0.85, 0.40)
		"tower_mage":
			return Color(0.65, 0.45, 1.00)
		"tower_ice":
			return Color(0.55, 0.90, 1.00)
		"tower_artillery":
			return Color(1.0, 0.55, 0.15)
	return Color(1.0, 0.95, 0.60)


# Wooden / stone platform with an archer's bow on top. Bow rotates with
# aim_angle. Higher levels = stone base, larger bow, fletching detail.
static func draw_archer(ci: CanvasItem, level: int, branch_idx: int, tint: Color, aim_angle: float) -> void:
	var stone_base: bool = level >= 2
	var base_w: float = 70.0 if level >= 2 else 60.0
	var base_h: float = 22.0
	_draw_ground_pad(ci, Vector2(0.0, 39.0), 43.0, 14.0, tint)
	# Branch tints: ranger = green wash, musketeer = orange.
	var wood_col: Color = ThemeColors.WOOD_PLANK * tint
	var stone_col: Color = ThemeColors.STONE_LIGHT * tint
	if branch_idx == 0:
		wood_col = wood_col.lerp(Color(0.45, 0.65, 0.30), 0.4)  # ranger green
	elif branch_idx == 1:
		wood_col = wood_col.lerp(Color(0.65, 0.40, 0.20), 0.4)  # musketeer orange
	# Near-black KR-style contour shared by every stroke on this tower.
	var outline: Color = Color(0.08, 0.06, 0.05)
	# Ground base — stone (L2/L3) or wood (L1).
	var base_y: float = 36.0
	var base_rect: Rect2 = Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h))
	ci.draw_rect(base_rect, stone_col if stone_base else wood_col)
	ci.draw_rect(base_rect, outline, false, 3.5)
	_highlight_stone_or_wood(ci, base_rect, stone_base, tint)
	# Lit-edge highlight along the top of the base, KR "sun-from-above" feel.
	ci.draw_line(Vector2(-base_w * 0.5 + 4.0, base_y - base_h + 2.0), Vector2(base_w * 0.5 - 4.0, base_y - base_h + 2.0), Color(1.0, 0.95, 0.78, 0.32), 1.5, true)
	# Vertical posts (frame). Heavier inner stroke + dark outline for KR depth.
	var post_x: float = base_w * 0.36
	var post_top_y: float = -10.0
	for px in [-post_x, post_x]:
		ci.draw_line(Vector2(px, base_y - base_h), Vector2(px, post_top_y), outline, 8.0, true)
		ci.draw_line(Vector2(px, base_y - base_h), Vector2(px, post_top_y), wood_col.darkened(0.15), 6.0, true)
	# Upper deck where the archer stands.
	var deck_y: float = post_top_y
	var deck_w: float = base_w * 0.95
	var deck_rect: Rect2 = Rect2(Vector2(-deck_w * 0.5, deck_y - 6.0), Vector2(deck_w, 12.0))
	ci.draw_rect(deck_rect, wood_col)
	ci.draw_rect(deck_rect, outline, false, 3.5)
	_highlight_line_for_rect(ci, deck_rect, tint)
	if level >= 3:
		# Painted side shields read as "fortified archer" at thumb zoom — a
		# clearer L3 silhouette change than the previous tiny green dots.
		var shield_col: Color = Color(0.26, 0.48, 0.24) * tint
		for s in [-1.0, 1.0]:
			var sc: Vector2 = Vector2(s * deck_w * 0.42, deck_y - 14.0)
			var sg: float = 7.0
			var shield_pts: PackedVector2Array = PackedVector2Array([
				sc + Vector2(-sg * 0.55, -sg * 0.55),
				sc + Vector2(sg * 0.55, -sg * 0.55),
				sc + Vector2(sg * 0.55, sg * 0.1),
				sc + Vector2(0.0, sg * 0.8),
				sc + Vector2(-sg * 0.55, sg * 0.1),
			])
			ci.draw_colored_polygon(shield_pts, shield_col)
			ci.draw_polyline(shield_pts + PackedVector2Array([shield_pts[0]]), outline, 2.0, true)
			# Cross stroke.
			ci.draw_line(sc + Vector2(0.0, -sg * 0.45), sc + Vector2(0.0, sg * 0.55), outline, 1.5, true)
			ci.draw_line(sc + Vector2(-sg * 0.40, 0.0), sc + Vector2(sg * 0.40, 0.0), outline, 1.5, true)
	# Archer figure (small orc-killer dude on the deck).
	var arch_y: float = deck_y - 28.0
	ci.draw_circle(Vector2(0.0, arch_y - 12.0), 7.0, ThemeColors.SKIN_LIGHT * tint)  # head
	ci.draw_arc(Vector2(0.0, arch_y - 12.0), 7.0, 0.0, TAU, 14, outline, 2.5)
	var tunic_rect: Rect2 = Rect2(Vector2(-5.0, arch_y - 5.0), Vector2(10.0, 14.0))
	ci.draw_rect(tunic_rect, Color(0.50, 0.40, 0.20) * tint)  # tunic
	ci.draw_rect(tunic_rect, outline, false, 2.0)
	# The bow — drawn rotated toward target, anchored at the archer's hand.
	var bow_size: float = 18.0 + level * 6.0
	if level >= 3:
		bow_size += 4.0
	ci.draw_set_transform(Vector2(0.0, arch_y - 5.0), aim_angle, Vector2.ONE)
	# Bow drawn twice: outer contour stroke + wood stroke on top for KR-style
	# heavy contour without changing the bow's silhouette.
	ci.draw_arc(Vector2.ZERO, bow_size * 0.55, -PI * 0.55, PI * 0.55, 16, outline, 5.5)
	ci.draw_arc(Vector2.ZERO, bow_size * 0.55, -PI * 0.55, PI * 0.55, 16, ThemeColors.WOOD_DARK, 3.5)
	var t1: Vector2 = Vector2(cos(-PI * 0.55), sin(-PI * 0.55)) * bow_size * 0.55
	var t2: Vector2 = Vector2(cos(PI * 0.55), sin(PI * 0.55)) * bow_size * 0.55
	ci.draw_line(t1, t2, Color(0.92, 0.92, 0.92), 1.5, true)
	# Nocked arrow (always drawn — a bow without an arrow looks too peaceful).
	ci.draw_line(Vector2(-2.0, 0.0), Vector2(bow_size * 0.85, 0.0), outline, 3.5, true)
	ci.draw_line(Vector2(-2.0, 0.0), Vector2(bow_size * 0.85, 0.0), Color(0.75, 0.65, 0.40) * tint, 2.0, true)
	# Arrowhead triangle — fill + heavy outline.
	var head_pts: PackedVector2Array = PackedVector2Array([
		Vector2(bow_size * 0.85, -3.0),
		Vector2(bow_size * 0.85, 3.0),
		Vector2(bow_size * 1.05, 0.0),
	])
	ci.draw_colored_polygon(head_pts, ThemeColors.BLADE_STEEL * tint)
	ci.draw_polyline(head_pts + PackedVector2Array([head_pts[0]]), outline, 1.5, true)
	# Fletching at L2+.
	if level >= 2:
		var fletch_pts: PackedVector2Array = PackedVector2Array([
			Vector2(-4.0, -2.5), Vector2(-4.0, 2.5), Vector2(0.0, 0.0),
		])
		ci.draw_colored_polygon(fletch_pts, Color(0.85, 0.30, 0.25) * tint)
		ci.draw_polyline(fletch_pts + PackedVector2Array([fletch_pts[0]]), outline, 1.2, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Stone tower / spire with a magical orb at the top. Orb glows brighter and
# adds runes per level. Branches tint the magic.
static func draw_mage(ci: CanvasItem, level: int, branch_idx: int, tint: Color, aim_angle: float) -> void:
	var stone_a: Color = Color(0.55, 0.55, 0.62) * tint
	var stone_b: Color = Color(0.42, 0.42, 0.50) * tint
	var orb_col: Color = Color(0.55, 0.45, 0.95)
	_draw_ground_pad(ci, Vector2(0.0, 39.0), 38.0, 13.0, tint)
	if branch_idx == 0:
		orb_col = Color(1.0, 0.45, 0.20)  # fire variant
	elif branch_idx == 1:
		orb_col = Color(0.30, 0.95, 1.0)  # arcane/ice variant
	var outline: Color = Color(0.14, 0.12, 0.20)
	# Base stones — wider at level 2/3.
	var base_w: float = 50.0 + (level - 1) * 8.0
	var base_h: float = 18.0
	var base_y: float = 36.0
	ci.draw_rect(Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), stone_b)
	ci.draw_rect(Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), outline, false, 3.0)
	_highlight_line_for_rect(ci, Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), tint)
	# Spire — trapezoid narrowing toward the top.
	var spire_h: float = 50.0 + level * 6.0
	var spire_top_y: float = base_y - base_h - spire_h
	var spire_top_w: float = 24.0 + level * 2.0
	var spire_bot_w: float = base_w * 0.75
	var spire_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-spire_bot_w * 0.5, base_y - base_h),
		Vector2(spire_bot_w * 0.5, base_y - base_h),
		Vector2(spire_top_w * 0.5, spire_top_y),
		Vector2(-spire_top_w * 0.5, spire_top_y),
	])
	ci.draw_colored_polygon(spire_pts, stone_a)
	ci.draw_polyline(spire_pts + PackedVector2Array([spire_pts[0]]), outline, 2.5, true)
	# Side buttresses improve map readability: mage reads as a tall stone tower,
	# not just a thin triangle under a glowing orb.
	var buttress_y: float = base_y - base_h - 4.0
	ci.draw_line(Vector2(-spire_bot_w * 0.47, buttress_y), Vector2(-spire_top_w * 0.62, spire_top_y + 12.0), stone_b.darkened(0.10), 4.0, true)
	ci.draw_line(Vector2(spire_bot_w * 0.47, buttress_y), Vector2(spire_top_w * 0.62, spire_top_y + 12.0), stone_b.darkened(0.10), 4.0, true)
	_draw_highlight_line(ci, Vector2(-spire_top_w * 0.20, spire_top_y + 6.0), Vector2(-spire_bot_w * 0.22, base_y - base_h - 6.0), tint)
	# Brick rows — drawn as horizontal lines crossing the spire.
	var rows: int = 3 + level
	for i in rows:
		var ry: float = lerp(base_y - base_h - 6.0, spire_top_y + 6.0, float(i) / float(rows - 1))
		var rw: float = lerp(spire_bot_w, spire_top_w, float(i) / float(rows - 1))
		ci.draw_line(Vector2(-rw * 0.5 + 3.0, ry), Vector2(rw * 0.5 - 3.0, ry), outline, 1.0, true)
	# Glowing rune band at L2+.
	if level >= 2:
		var rune_y: float = lerp(base_y - base_h, spire_top_y, 0.55)
		var rune_w: float = lerp(spire_bot_w, spire_top_w, 0.55)
		ci.draw_line(Vector2(-rune_w * 0.45, rune_y), Vector2(rune_w * 0.45, rune_y), orb_col, 2.5, true)
	# The orb — sits on top, scaled with level. aim_angle ignored for the
	# tower body; mage attack is "magic streams from orb" so we just brighten
	# the orb side facing the target.
	var orb_r: float = 9.0 + level * 2.5
	var orb_pos: Vector2 = Vector2(0.0, spire_top_y - orb_r * 0.6)
	# Outer halo.
	ci.draw_circle(orb_pos, orb_r * 1.4, Color(orb_col.r, orb_col.g, orb_col.b, 0.18))
	ci.draw_circle(orb_pos, orb_r, orb_col)
	# Inner highlight offset toward aim direction.
	var aim_dir: Vector2 = Vector2(cos(aim_angle), sin(aim_angle))
	ci.draw_circle(orb_pos + aim_dir * orb_r * 0.25, orb_r * 0.45, Color(1.0, 1.0, 1.0, 0.85))
	ci.draw_arc(orb_pos, orb_r, 0.0, TAU, 18, outline, 2.0)
	# Floating runes around orb at L3.
	if level >= 3:
		for i in 4:
			var a: float = TAU * float(i) / 4.0
			var p: Vector2 = orb_pos + Vector2(cos(a), sin(a)) * orb_r * 1.7
			ci.draw_circle(p, 2.5, orb_col)


# Crystalline cluster radiating cold. Higher levels add taller spikes and a
# brighter core.
static func draw_ice(ci: CanvasItem, level: int, _branch_idx: int, tint: Color, aim_angle: float) -> void:
	var ice_a: Color = Color(0.65, 0.85, 1.0) * tint
	var ice_b: Color = Color(0.45, 0.70, 0.95) * tint
	var outline: Color = Color(0.20, 0.30, 0.50)
	_draw_ground_pad(ci, Vector2(0.0, 36.0), 42.0, 14.0, Color(0.85, 0.94, 1.0) * tint)
	# Snow base / mound.
	ci.draw_circle(Vector2(0.0, 30.0), 38.0, Color(0.85, 0.92, 1.0) * tint)
	ci.draw_arc(Vector2(0.0, 30.0), 38.0, PI, TAU, 16, outline, 2.0)
	ci.draw_arc(Vector2(0.0, 25.0), 28.0, PI * 0.08, PI * 0.92, 14, Color(1.0, 1.0, 1.0, 0.45), 2.0)
	# Central crystal — diamond shape, scales with level.
	var crystal_h: float = 50.0 + level * 8.0
	var crystal_w: float = 22.0 + level * 3.0
	var pts_main: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 30.0 - crystal_h),  # top tip
		Vector2(crystal_w * 0.5, 0.0),
		Vector2(0.0, 30.0),
		Vector2(-crystal_w * 0.5, 0.0),
	])
	ci.draw_colored_polygon(pts_main, ice_a)
	ci.draw_polyline(pts_main + PackedVector2Array([pts_main[0]]), outline, 2.5, true)
	ci.draw_line(Vector2(0.0, 30.0 - crystal_h + 4.0), Vector2(0.0, 28.0), Color(1.0, 1.0, 1.0, 0.42), 1.6, true)
	# Inner highlight.
	var pts_hl: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 30.0 - crystal_h + 4.0),
		Vector2(crystal_w * 0.18, 0.0),
		Vector2(0.0, 28.0),
		Vector2(-crystal_w * 0.18, 0.0),
	])
	ci.draw_colored_polygon(pts_hl, Color(1.0, 1.0, 1.0, 0.45))
	# Side spikes — number scales with level.
	var spike_count: int = 2 + level
	for i in spike_count:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var idx_int: int = i / 2 + 1
		var idx: float = float(idx_int)
		var sx: float = side * (crystal_w * 0.4 + idx * 6.0)
		var sy: float = 18.0 - idx * 6.0
		var sh: float = 22.0 + idx * 4.0
		var spike_pts: PackedVector2Array = PackedVector2Array([
			Vector2(sx - 4.0, sy),
			Vector2(sx + 4.0, sy),
			Vector2(sx + (4.0 if side > 0.0 else -4.0) * 0.4, sy - sh),
		])
		ci.draw_colored_polygon(spike_pts, ice_b)
		ci.draw_polyline(spike_pts + PackedVector2Array([spike_pts[0]]), outline, 1.5, true)
	# Aim indicator — small flash at the crystal apex toward aim direction.
	var aim_dir: Vector2 = Vector2(cos(aim_angle), sin(aim_angle))
	ci.draw_circle(Vector2(0.0, 30.0 - crystal_h) + aim_dir * 8.0, 5.0, Color(0.95, 0.98, 1.0, 0.9))


# Cannon on a stone / wooden carriage. Barrel is the aim element. Bigger
# stone fortification at higher levels.
static func draw_artillery(ci: CanvasItem, level: int, _branch_idx: int, tint: Color, aim_angle: float) -> void:
	var stone_col: Color = Color(0.50, 0.50, 0.55) * tint
	var wood_col: Color = Color(0.45, 0.30, 0.18) * tint
	var iron_col: Color = Color(0.25, 0.25, 0.28)
	var outline: Color = Color(0.10, 0.10, 0.14)
	_draw_ground_pad(ci, Vector2(0.0, 39.0), 45.0, 14.0, tint)
	# Stone base/platform — wider at L2/L3.
	var base_w: float = 60.0 + (level - 1) * 10.0
	var base_h: float = 24.0
	var base_y: float = 36.0
	ci.draw_rect(Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), stone_col)
	ci.draw_rect(Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), outline, false, 3.0)
	_highlight_line_for_rect(ci, Rect2(Vector2(-base_w * 0.5, base_y - base_h), Vector2(base_w, base_h)), tint)
	# Brickwork lines.
	for i in 3:
		var ry: float = base_y - base_h + (i + 1) * (base_h / 4.0)
		ci.draw_line(Vector2(-base_w * 0.5 + 4.0, ry), Vector2(base_w * 0.5 - 4.0, ry), outline, 1.0, true)
	# Wooden carriage on top of stone — wheels at L2+.
	var carriage_w: float = 38.0 + level * 4.0
	var carriage_h: float = 16.0
	var carriage_y: float = base_y - base_h - carriage_h
	ci.draw_rect(Rect2(Vector2(-carriage_w * 0.5, carriage_y), Vector2(carriage_w, carriage_h)), wood_col)
	ci.draw_rect(Rect2(Vector2(-carriage_w * 0.5, carriage_y), Vector2(carriage_w, carriage_h)), outline, false, 2.0)
	_highlight_line_for_rect(ci, Rect2(Vector2(-carriage_w * 0.5, carriage_y), Vector2(carriage_w, carriage_h)), tint, 1.0)
	if level >= 2:
		var wheel_y: float = carriage_y + carriage_h - 4.0
		ci.draw_circle(Vector2(-carriage_w * 0.4, wheel_y), 7.0, iron_col)
		ci.draw_circle(Vector2(carriage_w * 0.4, wheel_y), 7.0, iron_col)
	# The cannon barrel — rotated to aim. Origin at the trunnion (carriage center).
	var trunnion: Vector2 = Vector2(0.0, carriage_y + 2.0)
	var barrel_len: float = 36.0 + level * 6.0
	var barrel_w: float = 12.0 + level * 1.5
	ci.draw_set_transform(trunnion, aim_angle, Vector2.ONE)
	# Barrel rectangle extending forward.
	ci.draw_rect(Rect2(Vector2(0.0, -barrel_w * 0.5), Vector2(barrel_len, barrel_w)), iron_col)
	ci.draw_rect(Rect2(Vector2(0.0, -barrel_w * 0.5), Vector2(barrel_len, barrel_w)), outline, false, 2.0)
	ci.draw_line(Vector2(4.0, -barrel_w * 0.22), Vector2(barrel_len - 5.0, -barrel_w * 0.22), Color(0.58, 0.58, 0.62, 0.42), 1.2, true)
	# Reinforcement bands.
	var bands: int = 2 + (1 if level >= 3 else 0)
	for i in bands:
		var bx: float = lerp(barrel_len * 0.20, barrel_len * 0.80, float(i) / float(bands - 1))
		ci.draw_rect(Rect2(Vector2(bx - 2.0, -barrel_w * 0.5 - 2.0), Vector2(4.0, barrel_w + 4.0)), outline)
	# Muzzle (the dark hole at the tip).
	ci.draw_circle(Vector2(barrel_len, 0.0), barrel_w * 0.42, Color(0.05, 0.05, 0.08))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Barracks — small fortified building with a banner. Higher level = stone
# walls + battlements + bigger flag. branch_idx unused (no barracks branches).
static func draw_barracks(ci: CanvasItem, level: int, _branch_idx: int, tint: Color) -> void:
	var wall_a: Color = Color(0.55, 0.45, 0.30) * tint  # wood at L1
	var wall_b: Color = Color(0.62, 0.60, 0.55) * tint  # stone at L2/L3
	var roof_col: Color = Color(0.55, 0.20, 0.18) * tint
	var outline: Color = Color(0.14, 0.10, 0.06)
	_draw_ground_pad(ci, Vector2(0.0, 39.0), 47.0, 15.0, tint)
	var stone: bool = level >= 2
	var wall_col: Color = wall_b if stone else wall_a
	# Building body — wider at higher levels.
	var b_w: float = 70.0 + (level - 1) * 6.0
	var b_h: float = 50.0 + (level - 1) * 4.0
	var b_y: float = 36.0
	var body_rect: Rect2 = Rect2(Vector2(-b_w * 0.5, b_y - b_h), Vector2(b_w, b_h))
	ci.draw_rect(body_rect, wall_col)
	ci.draw_rect(body_rect, outline, false, 3.0)
	_highlight_stone_or_wood(ci, body_rect, stone, tint)
	# Brick / plank lines.
	if stone:
		for i in 3:
			var by: float = b_y - b_h + (i + 1) * (b_h / 4.0)
			ci.draw_line(Vector2(-b_w * 0.5 + 4.0, by), Vector2(b_w * 0.5 - 4.0, by), outline, 1.2, true)
	else:
		for i in 4:
			var px: float = -b_w * 0.5 + (i + 1) * (b_w / 5.0)
			ci.draw_line(Vector2(px, b_y - b_h + 3.0), Vector2(px, b_y - 3.0), outline, 1.2, true)
	# Door — small dark rectangle.
	var door_w: float = 14.0
	var door_h: float = 22.0
	ci.draw_rect(Rect2(Vector2(-door_w * 0.5, b_y - door_h), Vector2(door_w, door_h)), Color(0.15, 0.10, 0.05))
	ci.draw_rect(Rect2(Vector2(-door_w * 0.5, b_y - door_h), Vector2(door_w, door_h)), outline, false, 2.0)
	# Windows at L2+ (stone version has slits, L3 has shuttered windows).
	if level >= 2:
		var win_y: float = b_y - b_h * 0.55
		ci.draw_rect(Rect2(Vector2(-b_w * 0.35, win_y), Vector2(8.0, 10.0)), Color(0.12, 0.18, 0.30))
		ci.draw_rect(Rect2(Vector2(b_w * 0.35 - 8.0, win_y), Vector2(8.0, 10.0)), Color(0.12, 0.18, 0.30))
		ci.draw_line(Vector2(-b_w * 0.5 + 5.0, b_y - b_h + 5.0), Vector2(-b_w * 0.5 + 5.0, b_y - 5.0), Color(1.0, 0.95, 0.75, 0.16) * tint, 1.2, true)
	# Roof / battlements. L1 = simple peaked roof; L2 = flat with merlons;
	# L3 = battlements + watchtower.
	var roof_top_y: float = b_y - b_h
	if level == 1:
		var roof_pts: PackedVector2Array = PackedVector2Array([
			Vector2(-b_w * 0.5 - 4.0, roof_top_y),
			Vector2(b_w * 0.5 + 4.0, roof_top_y),
			Vector2(b_w * 0.30, roof_top_y - 22.0),
			Vector2(-b_w * 0.30, roof_top_y - 22.0),
		])
		ci.draw_colored_polygon(roof_pts, roof_col)
		ci.draw_polyline(roof_pts + PackedVector2Array([roof_pts[0]]), outline, 2.0, true)
	else:
		# Battlement merlons — alternating rectangles along the top edge.
		var merlon_count: int = 5
		var merlon_w: float = b_w / float(merlon_count * 2 - 1)
		for i in merlon_count:
			var mx: float = -b_w * 0.5 + i * merlon_w * 2.0
			ci.draw_rect(Rect2(Vector2(mx, roof_top_y - 8.0), Vector2(merlon_w, 8.0)), wall_col)
			ci.draw_rect(Rect2(Vector2(mx, roof_top_y - 8.0), Vector2(merlon_w, 8.0)), outline, false, 1.5)
	# Flag pole + banner — bigger at L3, banner sways procedurally via t.
	var pole_x: float = b_w * 0.5 + 3.0
	var pole_top_y: float = roof_top_y - 28.0 - (4.0 if level >= 3 else 0.0)
	ci.draw_line(Vector2(pole_x, roof_top_y), Vector2(pole_x, pole_top_y), outline, 2.5, true)
	var banner_w: float = 18.0 + (level - 1) * 4.0
	var banner_h: float = 14.0 + (level - 1) * 2.0
	var sway: float = sin(Time.get_ticks_msec() / 300.0) * 1.5
	var banner_pts: PackedVector2Array = PackedVector2Array([
		Vector2(pole_x, pole_top_y),
		Vector2(pole_x + banner_w + sway, pole_top_y + banner_h * 0.3),
		Vector2(pole_x + banner_w * 0.85 + sway, pole_top_y + banner_h),
		Vector2(pole_x, pole_top_y + banner_h),
	])
	ci.draw_colored_polygon(banner_pts, roof_col)
	ci.draw_polyline(banner_pts + PackedVector2Array([banner_pts[0]]), outline, 1.5, true)
	# Watchtower at L3 — small extension above center.
	if level >= 3:
		var t_w: float = 22.0
		var t_h: float = 16.0
		var t_y: float = roof_top_y - 8.0 - t_h
		ci.draw_rect(Rect2(Vector2(-t_w * 0.5, t_y), Vector2(t_w, t_h)), wall_col)
		ci.draw_rect(Rect2(Vector2(-t_w * 0.5, t_y), Vector2(t_w, t_h)), outline, false, 2.0)
		# Tower window slit.
		ci.draw_rect(Rect2(Vector2(-2.0, t_y + 3.0), Vector2(4.0, 8.0)), Color(0.12, 0.18, 0.30))


# Generic fallback for unknown tower_id — keeps the legacy circle so any new
# tower added without a silhouette entry still renders.
static func draw_default(ci: CanvasItem, level: int, tint: Color) -> void:
	_draw_ground_pad(ci, Vector2(0.0, 39.0), 44.0, 14.0, tint)
	var col: Color = Color(0.35, 0.45, 0.75) * tint
	ci.draw_circle(Vector2.ZERO, 55.0, col)
	ci.draw_arc(Vector2.ZERO, 55.0, 0, TAU, 28, Color(0.08, 0.1, 0.25), 6.25)
	for i in level:
		ci.draw_circle(Vector2(-15.0 + i * 15.0, -70.0), 5.5, Color(1.0, 0.85, 0.2))


static func _highlight_line_for_rect(ci: CanvasItem, rect: Rect2, tint: Color, width: float = 1.4) -> void:
	_draw_highlight_line(ci, rect.position + Vector2(4.0, 3.0), rect.position + Vector2(rect.size.x - 4.0, 3.0), tint, width)


static func _highlight_stone_or_wood(ci: CanvasItem, rect: Rect2, stone: bool, tint: Color) -> void:
	_highlight_line_for_rect(ci, rect, tint)
	if stone:
		var chip_col: Color = Color(0.18, 0.16, 0.14, 0.28)
		ci.draw_line(rect.position + Vector2(rect.size.x * 0.28, rect.size.y * 0.15), rect.position + Vector2(rect.size.x * 0.28, rect.size.y * 0.85), chip_col, 1.0, true)
		ci.draw_line(rect.position + Vector2(rect.size.x * 0.62, rect.size.y * 0.15), rect.position + Vector2(rect.size.x * 0.62, rect.size.y * 0.85), chip_col, 1.0, true)
	else:
		ci.draw_line(rect.position + Vector2(6.0, rect.size.y - 5.0), rect.position + Vector2(rect.size.x - 6.0, rect.size.y - 5.0), Color(0.10, 0.07, 0.04, 0.25), 1.0, true)
