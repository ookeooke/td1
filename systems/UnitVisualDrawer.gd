extends RefCounted
class_name UnitVisualDrawer

# Static helper that draws a unit body + accent from UnitVisualData.
# Callers use: UnitVisualDrawer.draw_unit(self, visual, offset)
# Does NOT draw health bars, status rings, or selection indicators —
# those remain the responsibility of each unit script.


static func draw_swing_arc(ci: CanvasItem, v: UnitVisualData, lunge_dir: Vector2, t01: float) -> void:
	# Short curved weapon-trail rendered in front of the unit during the
	# forward half of a lunge. t01 is [0, 1] over the lunge duration; lunge_dir
	# is the facing unit-vector passed from the unit's _lunge_dir. Drawn in
	# world-rotated space so the arc reads correctly in any direction, which
	# keeps the effect isometric-ready for future perspective changes.
	if lunge_dir.length_squared() < 0.01:
		return
	if t01 < 0.3 or t01 > 0.85:
		return
	var progress: float = (t01 - 0.3) / 0.55
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var reach: float = body_r + 14.0
	var half_span: float = PI / 3.0
	var center_angle: float = lunge_dir.angle()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 7:
		var frac: float = float(i) / 6.0
		var ang: float = center_angle + lerp(-half_span, half_span, frac)
		pts.append(Vector2(cos(ang), sin(ang)) * reach)
	var col: Color = v.accent_color
	col.a = (1.0 - progress) * 0.8
	ci.draw_polyline(pts, col, 3.5, true)


# Swing arc + trailing ghost copies. Ghost arcs are angularly trailed behind
# the primary and drawn at reduced alpha + radius to simulate motion blur.
# Phase 3 branches on v.weapon_type here to produce different silhouettes.
static func draw_swing_arc_trail(ci: CanvasItem, v: UnitVisualData, lunge_dir: Vector2, t01: float, ghost_count: int = 4) -> void:
	if lunge_dir.length_squared() < 0.01:
		return
	if t01 < 0.25 or t01 > 0.9:
		return
	var progress: float = clampf((t01 - 0.25) / 0.65, 0.0, 1.0)
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var center_angle: float = lunge_dir.angle()
	# Total count includes the primary (idx 0). Older ghosts (higher idx) trail
	# behind with less opacity and smaller reach.
	var total: int = maxi(1, ghost_count)
	for idx in total:
		var age: float = float(idx) / float(total)
		var alpha: float = (1.0 - progress) * 0.85 * (1.0 - age * 0.85)
		if alpha <= 0.02:
			continue
		var angle_trail: float = -age * 0.25  # ~14° trail per ghost
		var reach_factor: float = 1.0 - age * 0.15
		_draw_weapon_shape(ci, v, center_angle + angle_trail, body_r, reach_factor, alpha)


static func _draw_weapon_shape(ci: CanvasItem, v: UnitVisualData, angle: float, body_r: float, reach_factor: float, alpha: float) -> void:
	var col: Color = v.accent_color
	col.a = alpha
	match v.weapon_type:
		UnitVisualData.WeaponType.SPEAR:
			# Straight thrust — two-point line extending farther than the arc.
			var inner: Vector2 = Vector2.from_angle(angle) * (body_r * 0.3) * reach_factor
			var outer: Vector2 = Vector2.from_angle(angle) * (body_r + 22.0) * reach_factor
			ci.draw_line(inner, outer, col, 4.0, true)
		UnitVisualData.WeaponType.STAFF:
			# Short radial flick — 30° arc closer to the body.
			var reach_s: float = (body_r + 6.0) * reach_factor
			var half_span_s: float = PI / 6.0
			var pts_s: PackedVector2Array = PackedVector2Array()
			for i in 5:
				var frac: float = float(i) / 4.0
				var a: float = angle + lerp(-half_span_s, half_span_s, frac)
				pts_s.append(Vector2(cos(a), sin(a)) * reach_s)
			ci.draw_polyline(pts_s, col, 4.5, true)
		UnitVisualData.WeaponType.CLAWS:
			# Three parallel rake lines.
			var reach_c: float = (body_r + 12.0) * reach_factor
			var forward: Vector2 = Vector2.from_angle(angle)
			var side: Vector2 = Vector2.from_angle(angle + PI * 0.5)
			for i in range(-1, 2):
				var lateral: Vector2 = side * float(i) * 6.0
				var near: Vector2 = forward * (body_r * 0.5) + lateral
				var far: Vector2 = forward * reach_c + lateral
				ci.draw_line(near, far, col, 2.5, true)
		_:
			# SWORD (default) — 60° slash arc.
			var reach: float = (body_r + 14.0) * reach_factor
			var half_span: float = PI / 3.0
			var pts: PackedVector2Array = PackedVector2Array()
			for i in 7:
				var frac: float = float(i) / 6.0
				var a: float = angle + lerp(-half_span, half_span, frac)
				pts.append(Vector2(cos(a), sin(a)) * reach)
			ci.draw_polyline(pts, col, 3.5, true)


# Rotating dashed ring. Used for status overlays (slow / stun) so players
# get a clear "this is an active effect" animation instead of a static arc.
static func draw_status_ring(ci: CanvasItem, radius: float, color: Color, dashes: int, rotation_t: float, width: float) -> void:
	var d: int = maxi(2, dashes)
	var slot: float = TAU / float(d)
	var span: float = slot * 0.5
	for i in d:
		var start: float = rotation_t + float(i) * slot
		ci.draw_arc(Vector2.ZERO, radius, start, start + span, 6, color, width)


static func draw_hit_flash(ci: CanvasItem, v: UnitVisualData, amount: float, offset: Vector2 = Vector2.ZERO) -> void:
	# Additive white overlay in the body's silhouette, fading with amount
	# in [0, 1]. Intended to be called immediately after draw_unit() while
	# a hit flash is active. Brief (~80 ms) flashes read as "got hit."
	if amount <= 0.0:
		return
	var a: float = clampf(amount, 0.0, 1.0) * 0.65
	var col: Color = Color(1.0, 1.0, 1.0, a)
	if offset != Vector2.ZERO:
		ci.draw_set_transform(offset, 0.0, Vector2.ONE)
	if v.shape == UnitVisualData.Shape.CIRCLE:
		ci.draw_circle(Vector2.ZERO, v.radius, col)
	else:
		var half: Vector2 = v.body_size * 0.5
		ci.draw_rect(Rect2(-half, v.body_size), col)
	if offset != Vector2.ZERO:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_unit(ci: CanvasItem, v: UnitVisualData, offset: Vector2 = Vector2.ZERO) -> void:
	if offset != Vector2.ZERO:
		ci.draw_set_transform(offset, 0.0, Vector2.ONE)

	if v.shape == UnitVisualData.Shape.CIRCLE:
		ci.draw_circle(Vector2.ZERO, v.radius, v.body_color)
		ci.draw_arc(Vector2.ZERO, v.radius, 0, TAU, 24, v.outline_color, v.outline_width)
		if v.accent_band_color.a > 0.0:
			ci.draw_arc(Vector2.ZERO, v.radius - v.outline_width, 0, TAU, 24, v.accent_band_color, 3.0)
	else:
		var half: Vector2 = v.body_size * 0.5
		var rect: Rect2 = Rect2(-half, v.body_size)
		ci.draw_rect(rect, v.body_color)
		ci.draw_rect(rect, v.outline_color, false, v.outline_width)
		if v.accent_band_color.a > 0.0:
			var inset: float = v.outline_width
			ci.draw_rect(Rect2(-half + Vector2(inset, inset), v.body_size - Vector2(inset * 2.0, inset * 2.0)), v.accent_band_color, false, 3.0)

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
			ci.draw_line(Vector2(0, top), Vector2(0, top - 15.0), v.accent_color, 6.25)
		UnitVisualData.Accent.CROSSHAIR:
			# Horizontal + vertical cross (healer)
			var r: float = v.radius * 0.45
			ci.draw_line(Vector2(-r, 0), Vector2(r, 0), v.accent_color, 5.0)
			ci.draw_line(Vector2(0, -r), Vector2(0, r), v.accent_color, 5.0)
		UnitVisualData.Accent.WINGS:
			# Horizontal bars extending from sides (flying)
			var r: float = v.radius
			ci.draw_line(Vector2(-r - 15, -5), Vector2(-r, -5), v.accent_color, 5.0)
			ci.draw_line(Vector2(-r - 10, 5), Vector2(-r, 5), v.accent_color, 5.0)
			ci.draw_line(Vector2(r, -5), Vector2(r + 15, -5), v.accent_color, 5.0)
			ci.draw_line(Vector2(r, 5), Vector2(r + 10, 5), v.accent_color, 5.0)
		UnitVisualData.Accent.CROWN:
			# Two angled lines above body (boss crown)
			var top: float = -v.radius
			ci.draw_line(Vector2(-15, top - 5), Vector2(-7.5, top - 20), v.accent_color, 5.0)
			ci.draw_line(Vector2(15, top - 5), Vector2(7.5, top - 20), v.accent_color, 5.0)
			ci.draw_line(Vector2(-7.5, top - 20), Vector2(0, top - 10), v.accent_color, 5.0)
			ci.draw_line(Vector2(7.5, top - 20), Vector2(0, top - 10), v.accent_color, 5.0)
