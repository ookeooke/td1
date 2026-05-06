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
		_draw_weapon_shape(ci, v, center_angle + angle_trail, body_r, reach_factor, alpha * v.weapon_trail_strength)


static func _draw_weapon_shape(ci: CanvasItem, v: UnitVisualData, angle: float, body_r: float, reach_factor: float, alpha: float) -> void:
	var col: Color = v.accent_color
	col.a = clampf(alpha, 0.0, 1.0)
	if v.weapon_glow_strength > 0.0 and v.weapon_glow_color.a > 0.0:
		var glow_col: Color = v.weapon_glow_color
		glow_col.a *= clampf(alpha * v.weapon_glow_strength, 0.0, 1.0)
		_draw_weapon_glow(ci, v, angle, body_r, reach_factor, glow_col)
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


static func draw_hit_flash(ci: CanvasItem, v: UnitVisualData, amount: float, offset: Vector2 = Vector2.ZERO, scale: Vector2 = Vector2.ONE) -> void:
	# Additive white overlay in the body's silhouette, fading with amount
	# in [0, 1]. Intended to be called immediately after draw_unit() while
	# a hit flash is active. Brief (~80 ms) flashes read as "got hit."
	if amount <= 0.0:
		return
	var a: float = clampf(amount, 0.0, 1.0) * 0.65
	var col: Color = Color(1.0, 1.0, 1.0, a)
	var has_xform: bool = offset != Vector2.ZERO or scale != Vector2.ONE
	if has_xform:
		ci.draw_set_transform(offset, 0.0, scale)
	if v.shape == UnitVisualData.Shape.CIRCLE:
		ci.draw_circle(Vector2.ZERO, v.radius, col)
	else:
		var half: Vector2 = v.body_size * 0.5
		ci.draw_rect(Rect2(-half, v.body_size), col)
	# When multi-part body is active, also flash head + legs so the whole
	# silhouette pulses, not just the torso.
	if v.race != UnitVisualData.Race.NONE:
		var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
		var head_r: float = torso_r * v.head_radius_ratio
		var head_y: float = v.head_y_offset * torso_r
		ci.draw_circle(Vector2(0.0, head_y), head_r, col)
		var leg_x: float = torso_r * 0.40
		var leg_top_y: float = torso_r * 0.55
		var leg_w: float = torso_r * 0.30
		var leg_h: float = torso_r * 0.65
		ci.draw_rect(Rect2(Vector2(-leg_x - leg_w * 0.5, leg_top_y), Vector2(leg_w, leg_h)), col)
		ci.draw_rect(Rect2(Vector2(leg_x - leg_w * 0.5, leg_top_y), Vector2(leg_w, leg_h)), col)
	if has_xform:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Returns {"offset": Vector2, "scale": Vector2} for a walking body, driven
# by v.walk_bob_amplitude / walk_bob_speed / walk_squash. `phase` (radians)
# offsets the cycle per-unit so a swarm doesn't step in lockstep. When both
# amplitude and squash are 0, returns identity (caller can skip applying).
static func compute_walk_anim(v: UnitVisualData, t: float, phase: float) -> Dictionary:
	var amp: float = v.walk_bob_amplitude
	var sq: float = clampf(v.walk_squash, 0.0, 0.25)
	var tilt_amp: float = v.walk_tilt_amplitude if "walk_tilt_amplitude" in v else 0.0
	if amp <= 0.0 and sq <= 0.0 and tilt_amp <= 0.0:
		return {"offset": Vector2.ZERO, "scale": Vector2.ONE, "rotation": 0.0}
	var theta: float = t * v.walk_bob_speed + phase
	var s: float = sin(theta)
	var lift: float = absf(s)  # 0 at plant, 1 at peak — two plants per cycle
	var bob_y: float = -lift * amp
	# Squash peaks at foot-plant (lift == 0): body compresses vertically +
	# spreads horizontally, then recovers at peak.
	var plant_weight: float = 1.0 - lift
	var sx: float = 1.0 + sq * plant_weight
	var sy: float = 1.0 - sq * plant_weight
	# Tilt: rocks left/right between plants. Zero at plants (theta = N*PI),
	# extremum at peaks. Direction alternates per step so the body sways
	# weight-shift style instead of just leaning one way forever.
	var rot: float = s * tilt_amp
	return {"offset": Vector2(0.0, bob_y), "scale": Vector2(sx, sy), "rotation": rot}


static func draw_unit(ci: CanvasItem, v: UnitVisualData, offset: Vector2 = Vector2.ZERO, scale: Vector2 = Vector2.ONE, walk_t: float = -1.0, walk_phase: float = 0.0, ctx: Dictionary = {}) -> void:
	# Walk-rocking rotation, computed by caller via compute_walk_anim and
	# passed through ctx so the existing draw_unit signature stays stable.
	var walk_rot: float = ctx.get("walk_rotation", 0.0)
	var has_xform: bool = offset != Vector2.ZERO or scale != Vector2.ONE or walk_rot != 0.0
	if has_xform:
		ci.draw_set_transform(offset, walk_rot, scale)

	# Texture override — when set, paint the image and skip the entire
	# procedural body. Walk-bob/squash inherits via the transform above.
	# Other layers (shadow, hit-flash, status rings, HP bar, swing-arc trail)
	# draw outside draw_unit() and continue to wrap the texture correctly.
	# skin_tint (endless HP-scaling reddening) is multiplied into the texture
	# so scaled enemies still visibly redden. Boss phase tints use
	# CanvasItem.modulate which compounds on top automatically.
	if v.texture != null:
		var ts: Vector2 = v.texture_size if v.texture_size.x > 0.0 and v.texture_size.y > 0.0 else Vector2(v.radius * 2.0, v.radius * 2.0)
		var tex_tint: Color = ctx.get("skin_tint", Color.WHITE)
		ci.draw_texture_rect(v.texture, Rect2(-ts * 0.5, ts), false, tex_tint)
		if has_xform:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# Per-enemy variation + state. All ctx fields are optional; defaults
	# reproduce the previous draw exactly when ctx is empty.
	var skin_tint: Color = ctx.get("skin_tint", Color.WHITE)
	var hat_tilt: float = ctx.get("hat_tilt", 0.0)
	var face_dir: Vector2 = ctx.get("face", Vector2.ZERO)
	var wind_t: float = ctx.get("wind_t", 0.0)
	# strike_t in [0, 1]: 0 = just struck (arm raised), 0.4 = arm forward
	# at impact, 1 = follow-through low. Negative = no strike active.
	var strike_t: float = ctx.get("strike_t", -1.0)
	var strike_dir: Vector2 = ctx.get("strike_dir", Vector2.ZERO)
	var low_hp: bool = ctx.get("low_hp", false)
	var body_col: Color = v.body_color * skin_tint
	var head_col: Color = v.head_color * skin_tint
	var leg_col: Color = v.leg_color * skin_tint
	var arm_col: Color = v.arm_color * skin_tint

	# Cape/back cloth draws first so all body parts paint over it. This gives
	# hero silhouettes more readable depth without adding nodes or sprites.
	if v.race != UnitVisualData.Race.NONE and v.cape_color.a > 0.0:
		_draw_cape(ci, v, walk_t, walk_phase)
	if v.race != UnitVisualData.Race.NONE and v.accent_type == UnitVisualData.Accent.WINGS:
		_draw_wings(ci, v, walk_t, walk_phase)

	# Legs draw first so the torso paints over the inner edge — gives a
	# clean two-leg silhouette rooted under the body.
	if v.race != UnitVisualData.Race.NONE:
		_draw_legs(ci, v, walk_t, walk_phase, leg_col, low_hp)

	if v.shape == UnitVisualData.Shape.CIRCLE:
		ci.draw_circle(Vector2.ZERO, v.radius, body_col)
		ci.draw_arc(Vector2.ZERO, v.radius, 0, TAU, 24, v.outline_color, v.outline_width)
		if v.accent_band_color.a > 0.0:
			ci.draw_arc(Vector2.ZERO, v.radius - v.outline_width, 0, TAU, 24, v.accent_band_color, 3.0)
	else:
		var half: Vector2 = v.body_size * 0.5
		var rect: Rect2 = Rect2(-half, v.body_size)
		ci.draw_rect(rect, body_col)
		ci.draw_rect(rect, v.outline_color, false, v.outline_width)
		if v.accent_band_color.a > 0.0:
			var inset: float = v.outline_width
			ci.draw_rect(Rect2(-half + Vector2(inset, inset), v.body_size - Vector2(inset * 2.0, inset * 2.0)), v.accent_band_color, false, 3.0)
	_draw_body_polish(ci, v)
	if v.armor_plate_color.a > 0.0:
		_draw_armor_plates(ci, v)
	if v.shoulder_pad_color.a > 0.0:
		_draw_shoulder_pads(ci, v)

	# Arms with held weapon — drawn over the torso so the weapon arm sits
	# visibly in front of the body. Front arm raises during wind-up, then
	# sweeps through a full arc during the strike commit.
	if v.race != UnitVisualData.Race.NONE:
		_draw_arms_and_weapon(ci, v, walk_t, walk_phase, wind_t, strike_t, strike_dir, arm_col)

	_draw_accent(ci, v)

	# Head, tusks, hat draw last so they sit visually above the torso.
	if v.race != UnitVisualData.Race.NONE:
		_draw_head_and_hat(ci, v, head_col, hat_tilt, face_dir)

	if has_xform:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_weapon_glow(ci: CanvasItem, v: UnitVisualData, angle: float, body_r: float, reach_factor: float, col: Color) -> void:
	# Wider translucent under-stroke before the crisp weapon/trail shape. This
	# reads as a tiny slash glow at gameplay zoom and is skipped by default.
	match v.weapon_type:
		UnitVisualData.WeaponType.SPEAR:
			var inner: Vector2 = Vector2.from_angle(angle) * (body_r * 0.2) * reach_factor
			var outer: Vector2 = Vector2.from_angle(angle) * (body_r + 25.0) * reach_factor
			ci.draw_line(inner, outer, col, 9.0, true)
		UnitVisualData.WeaponType.CLAWS:
			var reach_c: float = (body_r + 14.0) * reach_factor
			var forward: Vector2 = Vector2.from_angle(angle)
			var side: Vector2 = Vector2.from_angle(angle + PI * 0.5)
			for i in range(-1, 2):
				var lateral: Vector2 = side * float(i) * 6.0
				ci.draw_line(forward * (body_r * 0.45) + lateral, forward * reach_c + lateral, col, 6.0, true)
		_:
			var reach: float = (body_r + 16.0) * reach_factor
			var half_span: float = PI / 3.0
			var pts: PackedVector2Array = PackedVector2Array()
			for i in 7:
				var frac: float = float(i) / 6.0
				var a: float = angle + lerp(-half_span, half_span, frac)
				pts.append(Vector2(cos(a), sin(a)) * reach)
			ci.draw_polyline(pts, col, 8.0, true)


static func _draw_cape(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var flutter: float = 0.0
	if walk_t >= 0.0:
		flutter = sin(walk_t * v.walk_bob_speed + walk_phase) * torso_r * 0.10
	var top_y: float = -torso_r * 0.55
	var bottom_y: float = torso_r * 1.35
	var shoulder_w: float = torso_r * 1.15
	var hem_w: float = torso_r * 1.55
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(-shoulder_w * 0.5, top_y),
		Vector2(shoulder_w * 0.5, top_y),
		Vector2(hem_w * 0.5 + flutter, bottom_y),
		Vector2(0.0, bottom_y + torso_r * 0.20),
		Vector2(-hem_w * 0.5 + flutter, bottom_y),
	])
	ci.draw_colored_polygon(pts, v.cape_color)
	var shade: Color = v.outline_color
	shade.a = minf(0.45, v.cape_color.a)
	ci.draw_polyline(PackedVector2Array([
		Vector2(-shoulder_w * 0.5, top_y),
		Vector2(-hem_w * 0.5 + flutter, bottom_y),
		Vector2(0.0, bottom_y + torso_r * 0.20),
		Vector2(hem_w * 0.5 + flutter, bottom_y),
		Vector2(shoulder_w * 0.5, top_y),
	]), shade, maxf(1.5, v.outline_width * 0.35), true)


static func _draw_wings(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var flap: float = 0.0
	if walk_t >= 0.0:
		flap = sin(walk_t * maxf(8.0, v.walk_bob_speed * 1.6) + walk_phase) * torso_r * 0.25
	var col: Color = v.accent_color
	var shade: Color = v.outline_color
	shade.a = minf(0.55, col.a)
	var wing_w: float = torso_r * 1.15
	var wing_h: float = torso_r * 0.55
	var root_y: float = -torso_r * 0.10
	for side in [-1.0, 1.0]:
		var root: Vector2 = Vector2(side * torso_r * 0.58, root_y)
		var tip: Vector2 = Vector2(side * (torso_r + wing_w), root_y - wing_h + flap)
		var lower: Vector2 = Vector2(side * (torso_r + wing_w * 0.62), root_y + wing_h * 0.55 + flap * 0.30)
		var inner: Vector2 = Vector2(side * torso_r * 0.78, root_y + wing_h * 0.35)
		var pts: PackedVector2Array = PackedVector2Array([root, tip, lower, inner])
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(PackedVector2Array([root, tip, lower, inner, root]), shade, maxf(1.5, v.outline_width * 0.35), true)
		ci.draw_line(root, lower, shade, maxf(1.0, v.outline_width * 0.25), true)


static func _draw_body_polish(ci: CanvasItem, v: UnitVisualData) -> void:
	if v.highlight_strength <= 0.0 or v.highlight_color.a <= 0.0:
		return
	var col: Color = v.highlight_color
	col.a *= clampf(v.highlight_strength, 0.0, 1.0)
	if v.shape == UnitVisualData.Shape.CIRCLE:
		var r: float = v.radius
		ci.draw_arc(Vector2(-r * 0.12, -r * 0.10), r * 0.62, deg_to_rad(210.0), deg_to_rad(300.0), 8, col, maxf(2.0, v.outline_width * 0.45), true)
		ci.draw_circle(Vector2(-r * 0.25, -r * 0.35), r * 0.10, col)
		return
	var half: Vector2 = v.body_size * 0.5
	var shine_w: float = maxf(5.0, v.body_size.x * 0.16)
	var shine_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-half.x + v.outline_width * 1.2, -half.y + v.outline_width * 1.2),
		Vector2(-half.x + v.outline_width * 1.2 + shine_w, -half.y + v.outline_width * 1.2),
		Vector2(half.x * 0.05, half.y - v.outline_width * 1.4),
		Vector2(-half.x * 0.25, half.y - v.outline_width * 1.4),
	])
	ci.draw_colored_polygon(shine_pts, col)


static func _draw_armor_plates(ci: CanvasItem, v: UnitVisualData) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var plate: Color = v.armor_plate_color
	var outline_w: float = maxf(1.5, v.outline_width * 0.35)
	var chest_w: float = torso_r * 0.82
	var chest_h: float = torso_r * 0.72
	var top_y: float = -torso_r * 0.32
	var chest: PackedVector2Array = PackedVector2Array([
		Vector2(-chest_w * 0.5, top_y),
		Vector2(chest_w * 0.5, top_y),
		Vector2(chest_w * 0.36, top_y + chest_h),
		Vector2(0.0, top_y + chest_h + torso_r * 0.18),
		Vector2(-chest_w * 0.36, top_y + chest_h),
	])
	ci.draw_colored_polygon(chest, plate)
	ci.draw_polyline(PackedVector2Array([
		chest[0], chest[1], chest[2], chest[3], chest[4], chest[0]
	]), v.outline_color, outline_w, true)
	# Center ridge + belt line make the tiny torso read as metal armor.
	ci.draw_line(Vector2(0.0, top_y + 2.0), Vector2(0.0, top_y + chest_h + torso_r * 0.10), v.outline_color, outline_w, true)
	ci.draw_line(Vector2(-chest_w * 0.34, top_y + chest_h * 0.70), Vector2(chest_w * 0.34, top_y + chest_h * 0.70), v.outline_color, outline_w, true)
	if v.highlight_color.a > 0.0:
		var shine: Color = v.highlight_color
		shine.a *= clampf(maxf(v.highlight_strength, 0.25), 0.0, 1.0)
		ci.draw_line(Vector2(-chest_w * 0.26, top_y + chest_h * 0.15), Vector2(-chest_w * 0.10, top_y + chest_h * 0.52), shine, outline_w, true)


static func _draw_shoulder_pads(ci: CanvasItem, v: UnitVisualData) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var col: Color = v.shoulder_pad_color
	var outline_w: float = maxf(1.5, v.outline_width * 0.40)
	var shoulder_y: float = -torso_r * 0.12
	var shoulder_x: float = torso_r * 0.78
	var pad_w: float = torso_r * 0.46
	var pad_h: float = torso_r * 0.32
	for side in [-1.0, 1.0]:
		var c: Vector2 = Vector2(shoulder_x * side, shoulder_y)
		var pts: PackedVector2Array = PackedVector2Array([
			c + Vector2(-pad_w * side, -pad_h * 0.30),
			c + Vector2(0.0, -pad_h * 0.70),
			c + Vector2(pad_w * 0.65 * side, -pad_h * 0.12),
			c + Vector2(pad_w * 0.48 * side, pad_h * 0.55),
			c + Vector2(-pad_w * 0.70 * side, pad_h * 0.42),
		])
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), v.outline_color, outline_w, true)


# Soft dark ellipse under the body. Drawn at the enemy's local origin (not
# inside any transform) so walk-bob, breathing, and flinch don't move the
# shadow — it stays glued to the ground beneath the unit.
static func draw_ground_shadow(ci: CanvasItem, v: UnitVisualData) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var w: float = torso_r * 1.3
	var h: float = torso_r * 0.32
	var y: float = torso_r * 0.95
	# Approximate ellipse via filled polygon (16 verts is plenty for a small
	# blob). Cheaper than draw_circle + scale tricks.
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * w * 0.5, y + sin(a) * h * 0.5))
	ci.draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.28))


# Three rotating yellow stars around the head — classic stunned read. `t` is
# any monotonically-growing time value (the rotation angle).
static func draw_stun_stars(ci: CanvasItem, v: UnitVisualData, t: float) -> void:
	if v.race == UnitVisualData.Race.NONE:
		return
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var head_r: float = torso_r * v.head_radius_ratio
	var head_y: float = v.head_y_offset * torso_r
	var orbit_r: float = head_r * 1.4
	var star_size: float = maxf(3.5, head_r * 0.28)
	var col: Color = Color(1.0, 0.95, 0.25, 0.95)
	for i in 3:
		var a: float = t * 2.0 + float(i) * TAU / 3.0
		var c: Vector2 = Vector2(cos(a) * orbit_r, head_y - head_r * 0.3 + sin(a) * orbit_r * 0.35)
		_draw_star(ci, c, star_size, col)


# Faint blue silhouette drawn at a lagged offset behind a slowed enemy.
# Simplified to a torso + head blob so we don't fight the canvas-item
# self_modulate sampling order. Reads as an afterimage at gameplay zoom.
static func draw_slow_ghost(ci: CanvasItem, v: UnitVisualData, lag_offset: Vector2, alpha: float = 0.30) -> void:
	if alpha <= 0.0 or v.race == UnitVisualData.Race.NONE:
		return
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var head_r: float = torso_r * v.head_radius_ratio
	var head_y: float = v.head_y_offset * torso_r
	var col: Color = Color(0.55, 0.80, 1.0, alpha)
	ci.draw_circle(lag_offset, torso_r, col)
	ci.draw_circle(lag_offset + Vector2(0.0, head_y), head_r, col)


static func _draw_star(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	# 5-point star: alternate outer / inner radii.
	for i in 10:
		var r: float = size if i % 2 == 0 else size * 0.45
		var a: float = -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, color)


# Two stubby ovals positioned under the torso. When walk_t >= 0 (caller is in
# the WALKING state), each leg lifts on alternating foot-plants. Otherwise
# legs hang straight down. low_hp gives an asymmetric drag (left lifts hard,
# right barely lifts) — telegraphs an imminent kill.
static func _draw_legs(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float, leg_col: Color, low_hp: bool) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var leg_w: float = maxf(6.0, torso_r * 0.30)
	var leg_h: float = maxf(10.0, torso_r * 0.65)
	var leg_x: float = torso_r * 0.40
	var leg_top_y: float = torso_r * 0.55
	var lift_l: float = 0.0
	var lift_r: float = 0.0
	if walk_t >= 0.0:
		var theta: float = walk_t * v.walk_bob_speed + walk_phase
		var s: float = sin(theta)
		var amp: float = maxf(2.0, v.walk_bob_amplitude * 0.9)
		if low_hp:
			# Limp: leading leg lifts double, trailing leg drags (no lift).
			lift_l = -maxf(0.0, s) * amp * 1.8
			lift_r = -maxf(0.0, -s) * amp * 0.2
		else:
			lift_l = -maxf(0.0, s) * amp
			lift_r = -maxf(0.0, -s) * amp
	var outline_w: float = maxf(2.0, v.outline_width * 0.6)
	_fill_capsule(ci, Vector2(-leg_x, leg_top_y + lift_l), leg_w, leg_h, leg_col, v.outline_color, outline_w)
	_fill_capsule(ci, Vector2(leg_x, leg_top_y + lift_r), leg_w, leg_h, leg_col, v.outline_color, outline_w)


# Two arms attached at torso shoulder height. Walking: arms swing fore/aft
# counter-phase to the legs. wind_t (0..1) raises the weapon arm overhead
# during the anticipation window. strike_t (0..1) then sweeps the arm
# through a full arc: 0 = raised back, ~0.4 = forward at impact, 1 = low
# follow-through. strike_dir flips the swing direction so the weapon points
# at the actual target. The right arm carries the held weapon (sword/staff/
# spear/etc.) which travels with the hand throughout the arc.
static func _draw_arms_and_weapon(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float, wind_t: float, strike_t: float, strike_dir: Vector2, arm_col: Color) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var shoulder_y: float = -torso_r * 0.10
	var shoulder_x: float = torso_r * 0.70
	var arm_len: float = torso_r * 0.55
	var arm_w: float = maxf(5.0, torso_r * 0.22)
	var max_swing: float = deg_to_rad(28.0)
	# Walk swing — counter-phase to legs (legs use sin(theta), arms use -sin).
	var swing_l: float = 0.0
	var swing_r: float = 0.0
	if walk_t >= 0.0:
		var theta: float = walk_t * v.walk_bob_speed + walk_phase
		swing_l = -sin(theta) * max_swing
		swing_r = sin(theta) * max_swing
	# Right arm: rest swing → wind-up raise → strike-commit arc.
	# Local arm angle convention: 0 = arm hangs straight down, +PI/2 = arm
	# points forward (toward +X), -PI = arm points up. raised_angle is just
	# past vertical (~-153°) so the arm sits up-and-slightly-back.
	var right_angle: float = swing_r
	var raised_angle: float = -PI * 0.85
	if wind_t > 0.0:
		right_angle = lerp(swing_r, raised_angle, clampf(wind_t, 0.0, 1.0))
	if strike_t >= 0.0:
		# Decide swing direction in local space from strike_dir. Default to
		# +X (rightward) when no direction supplied; mirror for leftward
		# strikes by negating the forward angle.
		var face_sign: float = 1.0
		if strike_dir.length_squared() > 0.0001:
			face_sign = signf(strike_dir.x) if absf(strike_dir.x) > 0.05 else 1.0
		var impact_angle: float = (PI * 0.55) * face_sign  # ~+99° = forward-and-down
		var follow_angle: float = (PI * 0.40) * face_sign  # ~+72° = lower follow-through
		var s: float = clampf(strike_t, 0.0, 1.0)
		# Two-phase ease: raised → impact (fast), impact → follow-through (slow).
		if s < 0.45:
			right_angle = lerp(raised_angle, impact_angle, s / 0.45)
		else:
			right_angle = lerp(impact_angle, follow_angle, (s - 0.45) / 0.55)
	# Compute arm end positions (hand). Arm hangs down at angle 0; positive
	# angle swings forward (toward +X), negative swings back.
	var left_hand: Vector2 = Vector2(-shoulder_x + sin(swing_l) * arm_len, shoulder_y + cos(swing_l) * arm_len)
	var right_hand: Vector2 = Vector2(shoulder_x + sin(right_angle) * arm_len, shoulder_y + cos(right_angle) * arm_len)
	var outline_w: float = maxf(2.0, v.outline_width * 0.55)
	_draw_arm_segment(ci, Vector2(-shoulder_x, shoulder_y), left_hand, arm_w, arm_col, v.outline_color, outline_w)
	_draw_arm_segment(ci, Vector2(shoulder_x, shoulder_y), right_hand, arm_w, arm_col, v.outline_color, outline_w)
	# Held weapon at the right hand. Skip CLAWS (claws are part of the hand).
	_draw_held_weapon(ci, v, Vector2(shoulder_x, shoulder_y), right_hand, right_angle)


static func _draw_arm_segment(ci: CanvasItem, shoulder: Vector2, hand: Vector2, arm_w: float, fill: Color, outline: Color, outline_w: float) -> void:
	var dir: Vector2 = (hand - shoulder)
	if dir.length_squared() < 0.001:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized() * (arm_w * 0.5)
	# Quad arm body (rectangle along arm axis).
	var pts: PackedVector2Array = PackedVector2Array([
		shoulder + perp,
		hand + perp,
		hand - perp,
		shoulder - perp,
	])
	ci.draw_colored_polygon(pts, fill)
	# Hand circle at the tip.
	ci.draw_circle(hand, arm_w * 0.55, fill)
	# Light outline along the arm.
	ci.draw_line(shoulder + perp, hand + perp, outline, outline_w, true)
	ci.draw_line(shoulder - perp, hand - perp, outline, outline_w, true)
	ci.draw_arc(hand, arm_w * 0.55, 0.0, TAU, 12, outline, outline_w)


static func _draw_held_weapon(ci: CanvasItem, v: UnitVisualData, shoulder: Vector2, hand: Vector2, _arm_angle: float) -> void:
	var dir: Vector2 = hand - shoulder
	if dir.length_squared() < 0.001:
		return
	var fwd: Vector2 = dir.normalized()
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	match v.weapon_type:
		UnitVisualData.WeaponType.SPEAR:
			# Long shaft past the hand + small triangle tip.
			var shaft_end: Vector2 = hand + fwd * 38.0
			ci.draw_line(hand - fwd * 8.0, shaft_end, Color(0.45, 0.30, 0.18), 4.0, true)
			var tip_pts: PackedVector2Array = PackedVector2Array([
				shaft_end - side * 5.0,
				shaft_end + side * 5.0,
				shaft_end + fwd * 12.0,
			])
			ci.draw_colored_polygon(tip_pts, Color(0.78, 0.78, 0.74))
		UnitVisualData.WeaponType.STAFF:
			# Wooden shaft + glowing knob at the top.
			var top: Vector2 = hand + fwd * 30.0
			ci.draw_line(hand - fwd * 6.0, top, Color(0.50, 0.32, 0.18), 4.5, true)
			ci.draw_circle(top, 5.0, Color(0.55, 0.85, 1.0))
			ci.draw_circle(top, 2.5, Color(1.0, 1.0, 1.0))
		UnitVisualData.WeaponType.CLAWS:
			# Claws are part of the hand — skip the held weapon. The arm tip
			# already reads as a fist; nothing to draw.
			return
		_:
			# SWORD (default) — also serves as a serviceable club for orcs:
			# rectangular shaft with a pommel and a wider blade body.
			var grip_end: Vector2 = hand + fwd * 4.0
			var blade_end: Vector2 = hand + fwd * 32.0
			# Crossguard (perpendicular bar at the hilt).
			ci.draw_line(grip_end - side * 7.0, grip_end + side * 7.0, Color(0.55, 0.45, 0.25), 4.0, true)
			# Blade shape — narrow trapezoid tapering to a point.
			var blade_pts: PackedVector2Array = PackedVector2Array([
				grip_end - side * 3.5,
				grip_end + side * 3.5,
				blade_end + side * 1.8,
				blade_end + fwd * 5.0,
				blade_end - side * 1.8,
			])
			ci.draw_colored_polygon(blade_pts, Color(0.82, 0.82, 0.86))
			ci.draw_polyline(PackedVector2Array([
				grip_end - side * 3.5,
				blade_end - side * 1.8,
				blade_end + fwd * 5.0,
				blade_end + side * 1.8,
				grip_end + side * 3.5,
			]), Color(0.18, 0.18, 0.20), 1.5, true)


static func _fill_capsule(ci: CanvasItem, top_center: Vector2, w: float, h: float, fill: Color, outline: Color, outline_w: float) -> void:
	var hw: float = w * 0.5
	var rect: Rect2 = Rect2(top_center + Vector2(-hw, hw), Vector2(w, h - w))
	ci.draw_rect(rect, fill)
	ci.draw_circle(top_center + Vector2(0.0, hw), hw, fill)
	ci.draw_circle(top_center + Vector2(0.0, h - hw), hw, fill)
	# Outline: two side lines + bottom arc. Keep it cheap.
	ci.draw_line(top_center + Vector2(-hw, hw), top_center + Vector2(-hw, h - hw), outline, outline_w, true)
	ci.draw_line(top_center + Vector2(hw, hw), top_center + Vector2(hw, h - hw), outline, outline_w, true)
	ci.draw_arc(top_center + Vector2(0.0, h - hw), hw, 0.0, PI, 10, outline, outline_w)


static func _draw_head_and_hat(ci: CanvasItem, v: UnitVisualData, head_col: Color, hat_tilt: float, face_dir: Vector2) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var head_r: float = maxf(6.0, torso_r * v.head_radius_ratio)
	var head_pos: Vector2 = Vector2(0.0, v.head_y_offset * torso_r)
	# HOOD draws behind the head as a wider arc, so render before the head fill.
	if v.hat == UnitVisualData.Hat.HOOD or v.hat_secondary == UnitVisualData.Hat.HOOD:
		_draw_hood(ci, v, head_pos, head_r)
	# Head fill + outline.
	ci.draw_circle(head_pos, head_r, head_col)
	ci.draw_arc(head_pos, head_r, 0.0, TAU, 20, v.outline_color, maxf(2.0, v.outline_width * 0.7))
	# Eyes — small dark dots. Direction-aware: shift toward facing direction
	# so the enemy "looks where it's going". face_dir is in world space; we
	# treat its X component as our local left/right (PathFollow2D rotates is
	# disabled in this project, so world ↔ local X are the same axis).
	var eye_off: float = head_r * 0.35
	var eye_r: float = maxf(1.5, head_r * 0.12)
	var eye_y: float = -head_r * 0.05
	var eye_shift_x: float = 0.0
	if face_dir.length_squared() > 0.0001:
		eye_shift_x = signf(face_dir.x) * eye_r * 0.55
	ci.draw_circle(head_pos + Vector2(-eye_off + eye_shift_x, eye_y), eye_r, v.outline_color)
	ci.draw_circle(head_pos + Vector2(eye_off + eye_shift_x, eye_y), eye_r, v.outline_color)
	# Tusks — two small upward-pointing white triangles at the mouth line.
	if v.has_tusks:
		_draw_tusks(ci, head_pos, head_r)
	# Hat layers (HOOD already drawn behind head). Per-enemy hat_tilt is
	# reserved — applying it here would need to compose with draw_unit's
	# active transform; deferred until that refactor.
	var _tilt_unused: float = hat_tilt
	if v.hat != UnitVisualData.Hat.HOOD:
		_draw_hat(ci, v, v.hat, head_pos, head_r)
	if v.hat_secondary != UnitVisualData.Hat.HOOD and v.hat_secondary != UnitVisualData.Hat.NONE:
		_draw_hat(ci, v, v.hat_secondary, head_pos, head_r)


static func _draw_tusks(ci: CanvasItem, head_pos: Vector2, head_r: float) -> void:
	var tusk_w: float = head_r * 0.18
	var tusk_h: float = head_r * 0.30
	var y_base: float = head_pos.y + head_r * 0.45
	var x_off: float = head_r * 0.30
	var col: Color = Color(0.95, 0.92, 0.82)
	# Pointing up from chin — orcs' lower tusks. Small filled triangles.
	var left: PackedVector2Array = PackedVector2Array([
		Vector2(head_pos.x - x_off - tusk_w * 0.5, y_base),
		Vector2(head_pos.x - x_off + tusk_w * 0.5, y_base),
		Vector2(head_pos.x - x_off, y_base - tusk_h),
	])
	var right: PackedVector2Array = PackedVector2Array([
		Vector2(head_pos.x + x_off - tusk_w * 0.5, y_base),
		Vector2(head_pos.x + x_off + tusk_w * 0.5, y_base),
		Vector2(head_pos.x + x_off, y_base - tusk_h),
	])
	ci.draw_colored_polygon(left, col)
	ci.draw_colored_polygon(right, col)


static func _draw_hood(ci: CanvasItem, v: UnitVisualData, head_pos: Vector2, head_r: float) -> void:
	# Wider semi-circle behind the head, dark fill — reads as a hood cowl.
	var hood_r: float = head_r * 1.35
	var hood_center: Vector2 = head_pos + Vector2(0.0, head_r * 0.10)
	# Fill the upper hemisphere.
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(hood_center + Vector2(-hood_r, 0.0))
	for i in 13:
		var a: float = PI + PI * (float(i) / 12.0)
		pts.append(hood_center + Vector2(cos(a), sin(a)) * hood_r)
	pts.append(hood_center + Vector2(hood_r, 0.0))
	ci.draw_colored_polygon(pts, v.hat_color)


static func _draw_hat(ci: CanvasItem, v: UnitVisualData, hat: int, head_pos: Vector2, head_r: float) -> void:
	match hat:
		UnitVisualData.Hat.NONE:
			return
		UnitVisualData.Hat.HORNS:
			# Two short triangles tilting outward from the top of the head.
			var horn_h: float = head_r * 0.7
			var horn_base: float = head_r * 0.25
			var top_y: float = head_pos.y - head_r * 0.85
			var x_off: float = head_r * 0.55
			var left: PackedVector2Array = PackedVector2Array([
				Vector2(head_pos.x - x_off - horn_base * 0.5, top_y),
				Vector2(head_pos.x - x_off + horn_base * 0.5, top_y),
				Vector2(head_pos.x - x_off - horn_base * 0.7, top_y - horn_h),
			])
			var right: PackedVector2Array = PackedVector2Array([
				Vector2(head_pos.x + x_off - horn_base * 0.5, top_y),
				Vector2(head_pos.x + x_off + horn_base * 0.5, top_y),
				Vector2(head_pos.x + x_off + horn_base * 0.7, top_y - horn_h),
			])
			ci.draw_colored_polygon(left, v.hat_color)
			ci.draw_colored_polygon(right, v.hat_color)
		UnitVisualData.Hat.HELMET:
			# Filled half-disk over the top of the head + nose-guard line.
			var helm_pts: PackedVector2Array = PackedVector2Array()
			helm_pts.append(head_pos + Vector2(-head_r, head_r * 0.05))
			for i in 13:
				var a: float = PI + PI * (float(i) / 12.0)
				helm_pts.append(head_pos + Vector2(cos(a), sin(a)) * head_r * 1.05)
			helm_pts.append(head_pos + Vector2(head_r, head_r * 0.05))
			ci.draw_colored_polygon(helm_pts, v.hat_color)
			ci.draw_line(head_pos + Vector2(0.0, -head_r * 0.4), head_pos + Vector2(0.0, head_r * 0.45), v.outline_color, maxf(2.0, v.outline_width * 0.6), true)
		UnitVisualData.Hat.BANDANA:
			# Thin band across the forehead with two trailing tails behind.
			var band_y: float = head_pos.y - head_r * 0.45
			var band_h: float = head_r * 0.25
			ci.draw_rect(Rect2(Vector2(head_pos.x - head_r, band_y - band_h * 0.5), Vector2(head_r * 2.0, band_h)), v.hat_color)
			# Tails fluttering to one side.
			var tail_pts: PackedVector2Array = PackedVector2Array([
				Vector2(head_pos.x - head_r, band_y - band_h * 0.4),
				Vector2(head_pos.x - head_r - head_r * 0.7, band_y + head_r * 0.05),
				Vector2(head_pos.x - head_r - head_r * 0.5, band_y + head_r * 0.25),
				Vector2(head_pos.x - head_r, band_y + band_h * 0.4),
			])
			ci.draw_colored_polygon(tail_pts, v.hat_color)
		UnitVisualData.Hat.CROWN_BIG:
			# Reproduces the legacy Accent.CROWN silhouette mounted on the head.
			# When stacked over horns (boss), lift it so the crown peaks clear
			# the horn tips instead of intersecting them.
			var top_y: float = head_pos.y - head_r
			if v.hat_secondary == UnitVisualData.Hat.HORNS or v.hat == UnitVisualData.Hat.HORNS:
				top_y -= head_r * 0.7  # match horn height so crown sits above
			var x: float = head_pos.x
			var c: Color = v.hat_color
			ci.draw_line(Vector2(x - 15, top_y - 5), Vector2(x - 7.5, top_y - 20), c, 5.0)
			ci.draw_line(Vector2(x + 15, top_y - 5), Vector2(x + 7.5, top_y - 20), c, 5.0)
			ci.draw_line(Vector2(x - 7.5, top_y - 20), Vector2(x, top_y - 10), c, 5.0)
			ci.draw_line(Vector2(x + 7.5, top_y - 20), Vector2(x, top_y - 10), c, 5.0)
		_:
			return


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
			if v.race != UnitVisualData.Race.NONE:
				return
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
