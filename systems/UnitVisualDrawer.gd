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
	ci.draw_polyline(pts, col, 3.5, false)


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
			ci.draw_line(inner, outer, col, 4.0, false)
		UnitVisualData.WeaponType.STAFF:
			# Short radial flick — 30° arc closer to the body.
			var reach_s: float = (body_r + 6.0) * reach_factor
			var half_span_s: float = PI / 6.0
			var pts_s: PackedVector2Array = PackedVector2Array()
			for i in 5:
				var frac: float = float(i) / 4.0
				var a: float = angle + lerp(-half_span_s, half_span_s, frac)
				pts_s.append(Vector2(cos(a), sin(a)) * reach_s)
			ci.draw_polyline(pts_s, col, 4.5, false)
		UnitVisualData.WeaponType.CLAWS:
			# Three parallel rake lines.
			var reach_c: float = (body_r + 12.0) * reach_factor
			var forward: Vector2 = Vector2.from_angle(angle)
			var side: Vector2 = Vector2.from_angle(angle + PI * 0.5)
			for i in range(-1, 2):
				var lateral: Vector2 = side * float(i) * 6.0
				var near: Vector2 = forward * (body_r * 0.5) + lateral
				var far: Vector2 = forward * reach_c + lateral
				ci.draw_line(near, far, col, 2.5, false)
		UnitVisualData.WeaponType.BOW:
			# Arrow streak — single forward dart for the release "twang."
			# Shorter near-end than SPEAR (the arrow leaves the bow, doesn't
			# extend from it), longer reach to suggest the projectile flying.
			var inner_b: Vector2 = Vector2.from_angle(angle) * (body_r * 0.4) * reach_factor
			var outer_b: Vector2 = Vector2.from_angle(angle) * (body_r + 18.0) * reach_factor
			ci.draw_line(inner_b, outer_b, col, 2.5, false)
		_:
			# SWORD (default) — 60° slash arc.
			var reach: float = (body_r + 14.0) * reach_factor
			var half_span: float = PI / 3.0
			var pts: PackedVector2Array = PackedVector2Array()
			for i in 7:
				var frac: float = float(i) / 6.0
				var a: float = angle + lerp(-half_span, half_span, frac)
				pts.append(Vector2(cos(a), sin(a)) * reach)
			ci.draw_polyline(pts, col, 3.5, false)


# Rotating dashed ring. Used for status overlays (slow / stun) so players
# get a clear "this is an active effect" animation instead of a static arc.
static func draw_status_ring(ci: CanvasItem, radius: float, color: Color, dashes: int, rotation_t: float, width: float) -> void:
	var d: int = maxi(2, dashes)
	var slot: float = TAU / float(d)
	var span: float = slot * 0.5
	for i in d:
		var start: float = rotation_t + float(i) * slot
		ci.draw_arc(Vector2.ZERO, radius, start, start + span, 6, color, width)


# Death-mark skull glyph drawn above the cursed enemy's head. Position is
# positional (above the body), not color-only, so the curse reads even on
# enemies whose palette already has orange. `bob_t` drives a slow vertical
# float; `body_top_y` is the enemy's body-top y in local coords (negative).
static func draw_marked_skull(ci: CanvasItem, body_top_y: float, bob_t: float) -> void:
	var center: Vector2 = Vector2(0.0, body_top_y - 18.0 + sin(bob_t * 2.5) * 2.0)
	_draw_skull_glyph(ci, center, 7.0, true)


# Skull glyph primitive — bone cranium, eye sockets, hinged jaw. Reused by
# the floating death-mark indicator (with bob + halo) and the chest-emblem
# accent (no halo, smaller). `with_halo` toggles the soft outer glow.
static func _draw_skull_glyph(ci: CanvasItem, center: Vector2, skull_r: float, with_halo: bool) -> void:
	var bone: Color = Color(0.95, 0.92, 0.82, 0.95)
	var dark: Color = Color(0.10, 0.05, 0.12, 1.0)
	if with_halo:
		var glow: Color = Color(0.95, 0.55, 0.30, 0.35)
		ci.draw_circle(center, skull_r + 4.0, glow)
	ci.draw_circle(center, skull_r, bone)
	ci.draw_arc(center, skull_r, 0.0, TAU, 10, dark, 1.5)
	# Snap socket / jaw offsets to whole pixels so the glyph reads as a
	# stable sticker, not a shimmering blob, with AA off.
	var eye_off: float = roundf(skull_r * 0.42)
	var eye_r: float = roundf(skull_r * 0.30)
	var eye_y: float = roundf(-skull_r * 0.05)
	ci.draw_circle(center + Vector2(-eye_off, eye_y), eye_r, dark)
	ci.draw_circle(center + Vector2(eye_off, eye_y), eye_r, dark)
	var jaw_w: float = roundf(skull_r * 0.85)
	var jaw_top: float = roundf(skull_r * 0.55)
	var jaw_bot: float = roundf(skull_r * 1.15)
	var jaw_w_b: float = roundf(skull_r * 0.60)
	var jaw: PackedVector2Array = PackedVector2Array([
		center + Vector2(-jaw_w * 0.5, jaw_top),
		center + Vector2(jaw_w * 0.5, jaw_top),
		center + Vector2(jaw_w_b * 0.5, jaw_bot),
		center + Vector2(-jaw_w_b * 0.5, jaw_bot),
	])
	ci.draw_colored_polygon(jaw, bone)
	var tick_y_top: float = jaw_top + 1.0
	var tick_y_bot: float = jaw_bot - 0.5
	for i in 3:
		var x: float = -jaw_w * 0.25 + float(i) * (jaw_w * 0.25)
		ci.draw_line(center + Vector2(x, tick_y_top), center + Vector2(x * 0.7, tick_y_bot), dark, 1.0, false)


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
	if v.render_profile == UnitVisualData.RenderProfile.NECROMANCER_PREMIUM:
		_draw_necromancer_hit_flash(ci, v, a)
		if has_xform:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
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
	# Flight lift — body sprite floats above its true ground position by
	# flight_height_px. Shadow stays at ground (draw_ground_shadow ignores
	# this offset). AAA convention — see UnitVisualData.flight_height_px.
	if v.flight_height_px > 0.0:
		offset.y -= v.flight_height_px
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
	# cast_t in [0, 1]: 1 immediately after a skill cast fires, decaying to
	# 0 over CAST_ANIM_DURATION. Used by the STAFF finial to flash on shot.
	var cast_t: float = ctx.get("cast_t", 0.0)
	var low_hp: bool = ctx.get("low_hp", false)
	var body_col: Color = v.body_color * skin_tint
	var head_col: Color = v.head_color * skin_tint
	var leg_col: Color = v.leg_color * skin_tint
	var arm_col: Color = v.arm_color * skin_tint

	if v.render_profile == UnitVisualData.RenderProfile.NECROMANCER_PREMIUM:
		_draw_necromancer_premium(ci, v, walk_t, walk_phase, ctx, body_col, head_col, arm_col)
		if has_xform:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

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
		ci.draw_arc(Vector2.ZERO, v.radius, 0, TAU, 16, v.outline_color, v.outline_width)
		if v.accent_band_color.a > 0.0:
			ci.draw_arc(Vector2.ZERO, v.radius - v.outline_width, 0, TAU, 16, v.accent_band_color, 3.0)
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
		_draw_arms_and_weapon(ci, v, walk_t, walk_phase, wind_t, strike_t, strike_dir, arm_col, cast_t)

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
			ci.draw_line(inner, outer, col, 9.0, false)
		UnitVisualData.WeaponType.CLAWS:
			var reach_c: float = (body_r + 14.0) * reach_factor
			var forward: Vector2 = Vector2.from_angle(angle)
			var side: Vector2 = Vector2.from_angle(angle + PI * 0.5)
			for i in range(-1, 2):
				var lateral: Vector2 = side * float(i) * 6.0
				ci.draw_line(forward * (body_r * 0.45) + lateral, forward * reach_c + lateral, col, 6.0, false)
		UnitVisualData.WeaponType.BOW:
			# Wider under-glow for the arrow streak.
			var inner_b: Vector2 = Vector2.from_angle(angle) * (body_r * 0.3) * reach_factor
			var outer_b: Vector2 = Vector2.from_angle(angle) * (body_r + 22.0) * reach_factor
			ci.draw_line(inner_b, outer_b, col, 5.5, false)
		_:
			var reach: float = (body_r + 16.0) * reach_factor
			var half_span: float = PI / 3.0
			var pts: PackedVector2Array = PackedVector2Array()
			for i in 7:
				var frac: float = float(i) / 6.0
				var a: float = angle + lerp(-half_span, half_span, frac)
				pts.append(Vector2(cos(a), sin(a)) * reach)
			ci.draw_polyline(pts, col, 8.0, false)


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
	]), shade, maxf(1.5, v.outline_width * 0.35), false)


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
		ci.draw_polyline(PackedVector2Array([root, tip, lower, inner, root]), shade, maxf(1.5, v.outline_width * 0.35), false)
		ci.draw_line(root, lower, shade, maxf(1.0, v.outline_width * 0.25), false)


static func _draw_body_polish(ci: CanvasItem, v: UnitVisualData) -> void:
	if v.highlight_strength <= 0.0 or v.highlight_color.a <= 0.0:
		return
	var col: Color = v.highlight_color
	col.a *= clampf(v.highlight_strength, 0.0, 1.0)
	if v.shape == UnitVisualData.Shape.CIRCLE:
		var r: float = v.radius
		ci.draw_arc(Vector2(-r * 0.12, -r * 0.10), r * 0.62, deg_to_rad(210.0), deg_to_rad(300.0), 8, col, maxf(2.0, v.outline_width * 0.45), false)
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
	]), v.outline_color, outline_w, false)
	# Center ridge + belt line make the tiny torso read as metal armor.
	ci.draw_line(Vector2(0.0, top_y + 2.0), Vector2(0.0, top_y + chest_h + torso_r * 0.10), v.outline_color, outline_w, false)
	ci.draw_line(Vector2(-chest_w * 0.34, top_y + chest_h * 0.70), Vector2(chest_w * 0.34, top_y + chest_h * 0.70), v.outline_color, outline_w, false)
	if v.highlight_color.a > 0.0:
		var shine: Color = v.highlight_color
		shine.a *= clampf(maxf(v.highlight_strength, 0.25), 0.0, 1.0)
		ci.draw_line(Vector2(-chest_w * 0.26, top_y + chest_h * 0.15), Vector2(-chest_w * 0.10, top_y + chest_h * 0.52), shine, outline_w, false)


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
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), v.outline_color, outline_w, false)


# Soft dark ellipse under the body. Drawn at the enemy's local origin (not
# inside any transform) so walk-bob, breathing, and flinch don't move the
# shadow — it stays glued to the ground beneath the unit. For flying units
# (v.flight_height_px > 0) the shadow shrinks and dims as height increases,
# while staying at the unit's true ground-Y — the body is what lifts.
# Universal AAA convention (KR / Bloons / PvZ / Brawl Stars).
const _MAX_FLIGHT_HEIGHT: float = 80.0
static func draw_ground_shadow(ci: CanvasItem, v: UnitVisualData) -> void:
	var torso_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	# Flight-height scaling. height_t = 0 at ground, 1.0 at MAX_FLIGHT_HEIGHT.
	var height_t: float = 0.0
	if v.flight_height_px > 0.0:
		height_t = clampf(v.flight_height_px / _MAX_FLIGHT_HEIGHT, 0.0, 1.0)
	var shadow_scale: float = lerpf(1.0, 0.55, height_t)
	var alpha: float = lerpf(0.28, 0.16, height_t)
	var w: float = torso_r * 1.3 * shadow_scale
	var h: float = torso_r * 0.32 * shadow_scale
	var y: float = torso_r * 0.95
	# Approximate ellipse via filled polygon. Chunky shadow reads fine at
	# 10 verts and matches the silhouette polygonal feel.
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		pts.append(Vector2(cos(a) * w * 0.5, y + sin(a) * h * 0.5))
	ci.draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, alpha))


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
static func _draw_arms_and_weapon(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float, wind_t: float, strike_t: float, strike_dir: Vector2, arm_col: Color, cast_t: float = 0.0) -> void:
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
	_draw_held_weapon(ci, v, Vector2(shoulder_x, shoulder_y), right_hand, right_angle, cast_t)


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
	ci.draw_line(shoulder + perp, hand + perp, outline, outline_w, false)
	ci.draw_line(shoulder - perp, hand - perp, outline, outline_w, false)
	ci.draw_arc(hand, arm_w * 0.55, 0.0, TAU, 12, outline, outline_w)


static func _draw_held_weapon(ci: CanvasItem, v: UnitVisualData, shoulder: Vector2, hand: Vector2, _arm_angle: float, cast_t: float = 0.0) -> void:
	var dir: Vector2 = hand - shoulder
	if dir.length_squared() < 0.001:
		return
	var fwd: Vector2 = dir.normalized()
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	match v.weapon_type:
		UnitVisualData.WeaponType.SPEAR:
			# Long shaft past the hand + small triangle tip.
			var shaft_end: Vector2 = hand + fwd * 38.0
			ci.draw_line(hand - fwd * 8.0, shaft_end, Color(0.45, 0.30, 0.18), 4.0, false)
			var tip_pts: PackedVector2Array = PackedVector2Array([
				shaft_end - side * 5.0,
				shaft_end + side * 5.0,
				shaft_end + fwd * 12.0,
			])
			ci.draw_colored_polygon(tip_pts, Color(0.78, 0.78, 0.74))
		UnitVisualData.WeaponType.STAFF:
			# Wooden shaft + glowing knob at the top. When staff_finial_color
			# is set (alpha > 0), the knob is data-driven (size + color) with
			# a soft outer halo. Otherwise the legacy blue knob renders so
			# the Mage and any other STAFF-wielding unit looks unchanged.
			# `cast_t` (post-cast release flash, 0..1) swells the orb and
			# brightens the core for ~CAST_ANIM_DURATION after each shot.
			var top: Vector2 = hand + fwd * 30.0
			ci.draw_line(hand - fwd * 6.0, top, Color(0.50, 0.32, 0.18), 4.5, false)
			var flash: float = clampf(cast_t, 0.0, 1.0)
			if v.staff_finial_color.a > 0.0 and v.staff_finial_size > 0.0:
				var halo: Color = v.staff_finial_color
				halo.a *= 0.35 + flash * 0.45
				var size_mult: float = 1.0 + flash * 0.9
				ci.draw_circle(top, v.staff_finial_size * 1.6 * size_mult, halo)
				ci.draw_circle(top, v.staff_finial_size * size_mult, v.staff_finial_color)
				var core_r: float = maxf(1.5, v.staff_finial_size * 0.45) * (1.0 + flash * 0.5)
				ci.draw_circle(top, core_r, Color(1.0, 1.0, 1.0, 0.9))
			else:
				var size_mult_d: float = 1.0 + flash * 0.7
				ci.draw_circle(top, 5.0 * size_mult_d, Color(0.55, 0.85, 1.0))
				ci.draw_circle(top, 2.5 * size_mult_d, Color(1.0, 1.0, 1.0))
		UnitVisualData.WeaponType.CLAWS:
			# Claws are part of the hand — skip the held weapon. The arm tip
			# already reads as a fist; nothing to draw.
			return
		UnitVisualData.WeaponType.BOW:
			# Recurve bow held at the hand. Arc body curves forward (convex
			# face down-range, toward the archer's target); string is a
			# straight chord on the archer's side. Arc center sits BEHIND
			# the hand along `-fwd` so the arc bulges forward through the
			# hand position and ends symmetrically along the `side` axis.
			var bow_color := Color(0.45, 0.30, 0.18)
			var string_color := Color(0.92, 0.90, 0.78, 0.85)
			var arc_radius: float = 26.0
			var arc_center: Vector2 = hand - fwd * 17.0
			var center_angle: float = atan2(fwd.y, fwd.x)
			var half_span: float = PI * 0.45
			ci.draw_arc(arc_center, arc_radius,
				center_angle - half_span, center_angle + half_span,
				14, bow_color, 3.0, false)
			# String — chord between the two limb tips.
			var ang_a: float = center_angle - half_span
			var ang_b: float = center_angle + half_span
			var tip_a: Vector2 = arc_center + Vector2(cos(ang_a), sin(ang_a)) * arc_radius
			var tip_b: Vector2 = arc_center + Vector2(cos(ang_b), sin(ang_b)) * arc_radius
			ci.draw_line(tip_a, tip_b, string_color, 1.5, false)
			# Nocked arrow — a small forward stub from the hand for the
			# "ready to fire" silhouette. Drawn only when the hand is roughly
			# at rest; the swing-arc trail handles the in-flight visual.
			ci.draw_line(hand - fwd * 3.0, hand + fwd * 12.0, Color(0.55, 0.40, 0.25), 1.8, false)
		_:
			# SWORD (default) — also serves as a serviceable club for orcs:
			# rectangular shaft with a pommel and a wider blade body.
			var grip_end: Vector2 = hand + fwd * 4.0
			var blade_end: Vector2 = hand + fwd * 32.0
			# Crossguard (perpendicular bar at the hilt).
			ci.draw_line(grip_end - side * 7.0, grip_end + side * 7.0, Color(0.55, 0.45, 0.25), 4.0, false)
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
			]), Color(0.18, 0.18, 0.20), 1.5, false)


static func _fill_capsule(ci: CanvasItem, top_center: Vector2, w: float, h: float, fill: Color, outline: Color, outline_w: float) -> void:
	var hw: float = w * 0.5
	var rect: Rect2 = Rect2(top_center + Vector2(-hw, hw), Vector2(w, h - w))
	ci.draw_rect(rect, fill)
	ci.draw_circle(top_center + Vector2(0.0, hw), hw, fill)
	ci.draw_circle(top_center + Vector2(0.0, h - hw), hw, fill)
	# Outline: two side lines + bottom arc. Keep it cheap.
	ci.draw_line(top_center + Vector2(-hw, hw), top_center + Vector2(-hw, h - hw), outline, outline_w, false)
	ci.draw_line(top_center + Vector2(hw, hw), top_center + Vector2(hw, h - hw), outline, outline_w, false)
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
	ci.draw_arc(head_pos, head_r, 0.0, TAU, 12, v.outline_color, maxf(2.0, v.outline_width * 0.7))
	# Eyes — small dark dots. Direction-aware: shift toward facing direction
	# so the enemy "looks where it's going". face_dir is in world space; we
	# treat its X component as our local left/right (PathFollow2D rotates is
	# disabled in this project, so world ↔ local X are the same axis).
	# Snap eye offsets to whole pixels so the dots don't shimmer with AA off.
	var eye_off: float = roundf(head_r * 0.35)
	var eye_r: float = maxf(1.5, roundf(head_r * 0.12))
	var eye_y: float = roundf(-head_r * 0.05)
	var eye_shift_x: float = 0.0
	if face_dir.length_squared() > 0.0001:
		eye_shift_x = signf(face_dir.x) * roundf(eye_r * 0.55)
	var eye_l: Vector2 = head_pos + Vector2(-eye_off + eye_shift_x, eye_y)
	var eye_r_pos: Vector2 = head_pos + Vector2(eye_off + eye_shift_x, eye_y)
	if v.eye_glow_color.a > 0.0:
		# Glowing eyes — soft outer halo, bright core. Halo radius is small
		# enough to stay inside the head outline at typical head sizes.
		var halo: Color = v.eye_glow_color
		halo.a *= 0.45
		ci.draw_circle(eye_l, eye_r * 2.1, halo)
		ci.draw_circle(eye_r_pos, eye_r * 2.1, halo)
		ci.draw_circle(eye_l, eye_r, v.eye_glow_color)
		ci.draw_circle(eye_r_pos, eye_r, v.eye_glow_color)
	else:
		ci.draw_circle(eye_l, eye_r, v.outline_color)
		ci.draw_circle(eye_r_pos, eye_r, v.outline_color)
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
	for i in 8:
		var a: float = PI + PI * (float(i) / 7.0)
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
			for i in 8:
				var a: float = PI + PI * (float(i) / 7.0)
				helm_pts.append(head_pos + Vector2(cos(a), sin(a)) * head_r * 1.05)
			helm_pts.append(head_pos + Vector2(head_r, head_r * 0.05))
			ci.draw_colored_polygon(helm_pts, v.hat_color)
			ci.draw_line(head_pos + Vector2(0.0, -head_r * 0.4), head_pos + Vector2(0.0, head_r * 0.45), v.outline_color, maxf(2.0, v.outline_width * 0.6), false)
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
		UnitVisualData.Accent.SKULL_CHEST:
			# Small bone skull centered on the upper chest. Reuses the skull
			# primitive shared with the death-mark indicator so the necromancer
			# pendant and his curse glyph speak the same visual language.
			var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
			_draw_skull_glyph(ci, Vector2(0.0, body_r * 0.10), maxf(4.5, body_r * 0.18), false)
		UnitVisualData.Accent.RIBCAGE:
			# Skeletal ribcage on the chest — central spine + 3 curved rib bars
			# tapering toward the waist. Used by raised skeletons to give the
			# silhouette the bone-cage tell a generic pale soldier lacks.
			var body_r2: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
			var rib_col: Color = v.outline_color
			rib_col.a = 0.85
			# Snap rib offsets to whole pixels so the cage looks like an
			# engraved sticker, not a wavy line, with AA off.
			var chest_top_y: float = roundf(-body_r2 * 0.15)
			var chest_bot_y: float = roundf(body_r2 * 0.55)
			# Central spine.
			ci.draw_line(Vector2(0.0, chest_top_y), Vector2(0.0, chest_bot_y), rib_col, maxf(1.5, roundf(body_r2 * 0.08)), false)
			# Three rib bars, narrowing toward the waist.
			var rib_count: int = 3
			for i in rib_count:
				var ti: float = float(i) / float(rib_count - 1)
				var y: float = roundf(lerpf(chest_top_y + body_r2 * 0.08, chest_bot_y - body_r2 * 0.05, ti))
				var half_w: float = roundf(lerpf(body_r2 * 0.40, body_r2 * 0.22, ti))
				ci.draw_line(Vector2(-half_w, y), Vector2(half_w, y), rib_col, maxf(1.5, roundf(body_r2 * 0.07)), false)


static func _ink_step_time(t: float, fps: float = 10.0) -> float:
	var step: float = 1.0 / maxf(1.0, fps)
	return floorf(t / step) * step


static func _ink_jitter(rng_seed: float, t: float, amount: float = 0.65) -> Vector2:
	var stepped_t: float = _ink_step_time(t)
	var jx: float = sin((stepped_t + rng_seed * 13.17) * 123.456)
	var jy: float = cos((stepped_t + rng_seed * 19.31) * 789.012)
	return Vector2(jx, jy) * amount * 0.45


static func _rough_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, closed: bool, t: float, jitter: float = 0.45, overshoot: float = 1.0) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var segment_count: int = n if closed else n - 1
	for i in segment_count:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var dir: Vector2 = p1 - p0
		if dir.length_squared() < 0.001:
			continue
		dir = dir.normalized()
		var rng_seed: float = float(i) + float(n) * 0.37
		var a: Vector2 = p0 - dir * overshoot + _ink_jitter(rng_seed, t, jitter)
		var b: Vector2 = p1 + dir * overshoot + _ink_jitter(rng_seed + 0.51, t, jitter)
		ci.draw_line(a, b, col, width, true)


# Variable-weight inked outline (#2). Same hand-drawn jitter as
# _rough_polyline, but each edge's stroke width is modulated by the same
# centroid-vs-light test _cel_overlay uses: heavy on shadow-facing edges,
# thin on lit edges, with a small ink "pool" dabbed at shadow-side
# corners. Reads as deliberate inking, not a traced border.
static func _ink_weighted(ci: CanvasItem, pts: PackedVector2Array, col: Color, base_w: float, closed: bool, t: float, jitter: float = 0.45, overshoot: float = 1.0) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var c: Vector2 = Vector2.ZERO
	for p in pts:
		c += p
	c /= float(n)
	var segment_count: int = n if closed else n - 1
	for i in segment_count:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var dir: Vector2 = p1 - p0
		if dir.length_squared() < 0.001:
			continue
		dir = dir.normalized()
		var mid: Vector2 = (p0 + p1) * 0.5
		var face: float = (mid - c).normalized().dot(NECRO_LIGHT)  # >0 lit, <0 shadow
		# face -1 (shadow) → heavy 1.7×, face +1 (lit) → thin 0.5×.
		var w: float = base_w * lerpf(1.70, 0.50, smoothstep(-1.0, 1.0, face))
		var rng_seed: float = float(i) + float(n) * 0.37
		var a: Vector2 = p0 - dir * overshoot + _ink_jitter(rng_seed, t, jitter)
		var b: Vector2 = p1 + dir * overshoot + _ink_jitter(rng_seed + 0.51, t, jitter)
		ci.draw_line(a, b, col, w, true)
		# Ink pool at the shadow-side corner (start vertex).
		if face < -0.05:
			ci.draw_circle(p0 + _ink_jitter(rng_seed + 0.13, t, jitter * 0.4), w * 0.55, col)


static func _rough_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float, t: float, rng_seed: float, jitter: float = 0.35, overshoot: float = 0.75) -> void:
	var pts: PackedVector2Array = PackedVector2Array([a + _ink_jitter(rng_seed, t, jitter), b + _ink_jitter(rng_seed + 0.33, t, jitter)])
	_rough_polyline(ci, pts, col, width, false, t, jitter * 0.55, overshoot)


static func _rough_circle_points(center: Vector2, radius: float, point_count: int, t: float, rng_seed: float, roughness: float = 0.10) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var stepped_t: float = _ink_step_time(t)
	for i in point_count:
		var a: float = TAU * float(i) / float(point_count)
		var wobble: float = sin(rng_seed * 41.3 + float(i) * 2.17 + stepped_t * 11.0) * roughness
		var r: float = radius * (1.0 + wobble)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


static func _draw_rough_circle(ci: CanvasItem, center: Vector2, radius: float, fill: Color, outline: Color, outline_w: float, t: float, rng_seed: float, point_count: int = 9, roughness: float = 0.10) -> void:
	var pts: PackedVector2Array = _rough_circle_points(center, radius, point_count, t, rng_seed, roughness)
	ci.draw_colored_polygon(pts, fill)
	if outline_w > 0.0 and outline.a > 0.0:
		_rough_polyline(ci, pts, outline, outline_w, true, t, 0.25, 0.35)


static func _draw_necromancer_hit_flash(ci: CanvasItem, v: UnitVisualData, alpha: float) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var ghost: Color = v.eye_glow_color if v.eye_glow_color.a > 0.0 else Color(0.55, 1.0, 0.65, 1.0)
	ghost.a = alpha * 0.34
	var veil: Color = v.accent_color
	veil.a = alpha * 0.18
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var robe: PackedVector2Array = PackedVector2Array([
		Vector2(-body_r * 0.62, -body_r * 0.72),
		Vector2(body_r * 0.54, -body_r * 0.68),
		Vector2(body_r * 0.82, body_r * 0.82),
		Vector2(body_r * 0.36, body_r * 1.28),
		Vector2(0.02, body_r * 1.58),
		Vector2(-body_r * 0.52, body_r * 1.36),
		Vector2(-body_r * 0.88, body_r * 0.68),
	])
	ci.draw_colored_polygon(robe, veil)
	_rough_polyline(ci, robe, ghost, maxf(2.0, v.outline_width * 0.40), true, t, 0.28, 1.2)
	ci.draw_arc(Vector2(0.0, body_r * 0.98), body_r * 0.92, -PI * 0.20, PI * 1.15, 24, ghost, 2.0, true)
	for i in 4:
		var a0: float = t * 3.0 + float(i) * TAU / 4.0
		var p0: Vector2 = Vector2(cos(a0) * body_r * 0.22, -body_r * 0.10 + sin(a0) * body_r * 0.16)
		var p1: Vector2 = p0 + Vector2(cos(a0 + 0.5), sin(a0 + 0.5)) * body_r * 0.35
		_rough_line(ci, p0, p1, ghost, 1.4, t, 40.0 + float(i), 0.15, 0.3)


static func _draw_necromancer_premium(ci: CanvasItem, v: UnitVisualData, walk_t: float, walk_phase: float, ctx: Dictionary, body_col: Color, head_col: Color, arm_col: Color) -> void:
	var raw_t: float = walk_t if walk_t >= 0.0 else float(Time.get_ticks_msec()) * 0.001
	var t: float = raw_t + walk_phase
	var ink_t: float = _ink_step_time(t, 6.0)
	var is_moving: bool = walk_t >= 0.0
	var cast_t: float = clampf(ctx.get("cast_t", 0.0), 0.0, 1.0)
	var wind_t: float = clampf(ctx.get("wind_t", 0.0), 0.0, 1.0)
	# Pre-cast wind-up — 1.0 right after cast trigger, 0.0 at wind end.
	# Drawer uses this to swell the staff orb + brighten the ground rune
	# BEFORE the projectile spawns, so the cast reads as a wind-up release.
	var cast_wind_t: float = clampf(ctx.get("cast_wind_t", 0.0), 0.0, 1.0)
	var strike_t: float = ctx.get("strike_t", -1.0)
	var strike_dir: Vector2 = ctx.get("strike_dir", Vector2.ZERO)
	var motion: Dictionary = _necromancer_motion_channels(v, raw_t, walk_phase, is_moving, ctx, wind_t, strike_t, cast_t, cast_wind_t)
	# Glow shimmer is secondary — step it on twos (Phase 4 hybrid cadence).
	var pulse: float = sin(_ink_step_time(t, 12.0) * 2.2)
	# Idle breath + hit recoil — premium drawer reads these from ctx and
	# applies a whole-body offset that runs through every sub-helper.
	var breath_t: float = ctx.get("breath_t", 0.0)
	var breath_amp: float = sin(breath_t * 2.0) * 0.5 + 0.5
	var flinch_t: float = clampf(ctx.get("flinch_t", 0.0), 0.0, 1.0)
	var flinch_dir: Vector2 = ctx.get("flinch_dir", Vector2.ZERO)
	var body_r_local: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var flinch_off: Vector2 = flinch_dir * flinch_t * body_r_local * 0.10
	var soul_col: Color = v.eye_glow_color if v.eye_glow_color.a > 0.0 else Color(0.55, 1.0, 0.65, 1.0)
	var magic_col: Color = v.staff_finial_color if v.staff_finial_color.a > 0.0 else v.accent_color

	# Phase 1 part-rig — directional pose (head LEADS, torso leans into the
	# move, cape TRAILS) is applied as rigid per-part Transform2Ds about the
	# unit centre, NOT as in-helper width/offset hacks. Silhouette width
	# stays constant (no scale.x mirror — that was the reverted bug), and
	# the HP bar / status rings (drawn by base_hero OUTSIDE this drawer)
	# stay glued because the rig lives entirely below them. Flinch folds
	# into the rig root so every part inherits recoil for free.
	var gait_theta: float = raw_t * v.walk_bob_speed + walk_phase
	var rig: Dictionary = _necromancer_rig(motion, flinch_off, body_r_local, gait_theta, strike_t, cast_t, cast_wind_t, strike_dir)
	# Helpers draw symmetric, undistorted LOCAL geometry: the rig owns all
	# directional turn (Phase 1), so each helper forces its local turn to 0
	# and its legacy asymmetric width / tuck / head-shift math stays inert.
	# Secondary motion (gait, cape/staff lag, idle, weights) flows through
	# `motion` untouched.
	ci.draw_set_transform_matrix(rig["ground"])
	_draw_necromancer_rune(ci, v, t, soul_col, cast_t, cast_wind_t)
	_draw_necromancer_wisps(ci, v, t, soul_col, cast_t)
	ci.draw_set_transform_matrix(rig["cape"])
	_draw_necromancer_cape(ci, v, t, ink_t, motion)
	# Stepping feet — drawn in the GROUND frame (rig root) so the stance
	# foot stays planted while the body bobs over it; the robe (drawn next
	# at the torso frame) overlaps the shins so only the lower leg + boot
	# show. Walk-only (mv gate) → idle unchanged (hem covers the band).
	var mv_local: float = clampf(float(motion.get("move_weight", 0.0)), 0.0, 1.0)
	var body_off: Vector2 = (rig["torso"] as Transform2D).origin - (rig["root"] as Transform2D).origin
	var speed01: float = clampf(float(ctx.get("move_speed01", 1.0)), 0.0, 1.0)
	# Travel direction for the leg treadmill: smoothed facing X, with a
	# deadzone so near-vertical movement keeps the last horizontal sign
	# rather than collapsing the stride.
	var face_v: Vector2 = ctx.get("face", Vector2.RIGHT)
	var face_sign: float = -1.0 if face_v.x < -0.02 else 1.0
	ci.draw_set_transform_matrix(rig["root"])
	_draw_necromancer_feet(ci, v, body_r_local, gait_theta, mv_local, body_off, speed01, face_sign)
	ci.draw_set_transform_matrix(rig["torso"])
	_draw_necromancer_robe(ci, v, body_col, soul_col, pulse, ink_t, cast_t, motion)
	_draw_necromancer_arms_and_staff(ci, v, t, ink_t, motion, wind_t, strike_t, strike_dir, arm_col, magic_col, cast_t, breath_amp, cast_wind_t)
	ci.draw_set_transform_matrix(rig["head"])
	_draw_necromancer_hood(ci, v, head_col, soul_col, pulse, ink_t, cast_t, motion, breath_amp)

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _necromancer_motion_channels(v: UnitVisualData, raw_t: float, walk_phase: float, is_moving: bool, ctx: Dictionary, wind_t: float, strike_t: float, cast_t: float, cast_wind_t: float) -> Dictionary:
	var gait: float = sin(raw_t * v.walk_bob_speed + walk_phase) if is_moving else 0.0
	var face_dir: Vector2 = ctx.get("face", Vector2.ZERO)
	var body_turn: float = clampf(face_dir.x, -1.0, 1.0) if absf(face_dir.x) > 0.08 else 0.0
	if not is_moving:
		body_turn *= 0.35
	var cape_lag: float = clampf(float(ctx.get("cape_lag", -body_turn)), -1.0, 1.0)
	var move_weight: float = 1.0 if is_moving else 0.0
	var strike_weight: float = sin(clampf(strike_t, 0.0, 1.0) * PI) if strike_t >= 0.0 else 0.0
	var attack_weight: float = maxf(clampf(wind_t, 0.0, 1.0), strike_weight)
	var cast_weight: float = maxf(clampf(cast_t, 0.0, 1.0), clampf(cast_wind_t, 0.0, 1.0))
	var idle_weight: float = clampf(1.0 - maxf(move_weight, maxf(attack_weight, cast_weight)), 0.0, 1.0)
	# Phase 4 hybrid cadence — idle harmonics are SECONDARY motion, so they
	# run "on twos" (~12 fps stepped) for the hand-drawn staccato charm.
	# Locomotion (gait, rig bob, springs) stays smooth 60 fps elsewhere.
	var sraw: float = _ink_step_time(raw_t, 12.0)
	var idle_breath: float = sin(sraw * 1.05)
	var idle_settle: float = sin(sraw * 0.48 + 1.10)
	var idle_cape: float = sin(sraw * 0.62 + 0.85)
	var idle_staff: float = sin(sraw * 0.78 + 2.10)
	var idle_orb: float = 0.5 + 0.5 * sin(sraw * 1.18 + 0.40)
	return {
		"gait": gait,
		"idle_weight": idle_weight,
		"idle_breath": idle_breath,
		"idle_settle": idle_settle,
		"idle_cape": idle_cape,
		"idle_staff": idle_staff,
		"idle_orb": idle_orb,
		"move_weight": move_weight,
		"attack_weight": attack_weight,
		"strike_weight": strike_weight,
		"cast_weight": cast_weight,
		# body_turn → consumed by the rig; cape_lag/staff_lag → live
		# secondary motion in the cape/arms helpers. torso_turn/robe_turn/
		# hood_turn were removed: the rig owns turn, helpers force it to 0.
		"body_turn": body_turn,
		"cape_lag": clampf(cape_lag - body_turn * attack_weight * 0.10, -1.0, 1.0),
		"staff_lag": clampf(cape_lag * 0.28 - body_turn * 0.06 - attack_weight * body_turn * 0.10, -1.0, 1.0)
	}


static func _window_sin(a: float, lo: float, hi: float) -> float:
	# A single raised-sine lobe over [lo, hi], 0 outside. Building block for
	# keyframed action windows (anticipation / follow-through / settle).
	if a <= lo or a >= hi:
		return 0.0
	return sin(clampf((a - lo) / (hi - lo), 0.0, 1.0) * PI)


static func _gait_pose(theta: float) -> Dictionary:
	# Weighted gait keys (Phase 2). Raw sin reads as a float; biasing the
	# vertical rise with pow<1 makes the body push off the contact frame
	# fast then hang at the passing position — that snap is what reads as
	# "stepping with weight". `lift` peaks twice per stride (one per foot).
	var s: float = sin(theta)
	var lift: float = absf(s)
	var bob: float = pow(lift, 0.62)
	var roll: float = signf(s) * pow(absf(s), 0.85)        # weight shift, eased
	# Head/cape trail the torso bob by ~15% of the cycle (overlapping
	# action) — 0.94 rad ≈ 0.15·TAU.
	var lag_bob: float = pow(absf(sin(theta - 0.94)), 0.62)
	# Lateral pelvis weight-shift: hips slide over the stance foot, once
	# per stride, in phase with the roll. Translation, not rotation.
	var psway: float = s
	# Contrapposto: the upper body counter-rotates the pelvis, lagged
	# ~0.55 rad so the spine twist reads as a delayed reaction
	# (overlapping action — the classic "alive walk" tell).
	var twist: float = sin(theta - 0.55)
	# Heel-strike: a narrow spike at footfall (theta ≈ k·π → lift→0) for a
	# quick weight settle as the foot lands. ≈0 everywhere else.
	var contact: float = pow(1.0 - lift, 6.0)
	return {"bob": bob, "roll": roll, "lag_bob": lag_bob, "psway": psway, "twist": twist, "contact": contact}


static func _action_lean(strike_t: float, cast_t: float, cast_wind_t: float, strike_dir: Vector2, body_turn: float) -> Dictionary:
	# Anticipation + follow-through + settle as a signed lean (toward the
	# target on +). Melee: brief pull-back, then a longer thrust window
	# that overshoots and decays. Cast: wind back while the orb charges,
	# snap forward on release. Pure pose shaping off existing signals.
	var dir: float = signf(strike_dir.x) if absf(strike_dir.x) > 0.05 else signf(body_turn)
	if dir == 0.0:
		dir = 1.0
	var st: float = clampf(strike_t, 0.0, 1.0) if strike_t >= 0.0 else 0.0
	var atk: float = -0.55 * _window_sin(st, 0.0, 0.34) + 1.0 * _window_sin(st, 0.26, 0.92)
	var cw: float = clampf(cast_wind_t, 0.0, 1.0)
	var cr: float = clampf(cast_t, 0.0, 1.0)
	# Cast 3-beat: coil back while the orb charges, snap forward on
	# release, then a short counter-settle (follow-through, not a flat
	# decay) so the spell reads as a deliberate gesture.
	var cst: float = -0.70 * cw + 1.05 * _window_sin(cr, 0.0, 0.50) - 0.20 * _window_sin(cr, 0.48, 1.0)
	var lean: float = clampf((atk + cst) * dir, -1.4, 1.4)
	var drop: float = clampf(0.35 * _window_sin(st, 0.26, 0.92) + 0.30 * _window_sin(cr, 0.0, 0.55), 0.0, 1.0)
	# Chest rears UP while channelling (negative = up), commits down on the
	# release frame. Cape billows out on the release beat.
	var cast_rear: float = -0.30 * cw + 0.18 * _window_sin(cr, 0.0, 0.45)
	var cast_open: float = _window_sin(cr, 0.0, 0.45)
	return {"lean": lean, "drop": drop, "dir": dir, "cast_rear": cast_rear, "cast_open": cast_open}


static func _necromancer_rig(motion: Dictionary, flinch_off: Vector2, body_r: float, gait_theta: float, strike_t: float, cast_t: float, cast_wind_t: float, strike_dir: Vector2) -> Dictionary:
	# Builds one Transform2D per part. draw_set_transform_matrix is ABSOLUTE
	# in Godot 2D, so children are composed by multiplying the parent
	# (root * local) here rather than relying on a transform stack.
	var b: float = clampf(float(motion.get("body_turn", 0.0)), -1.0, 1.0)
	var clag: float = clampf(float(motion.get("cape_lag", -b)), -1.0, 1.0)
	var mv: float = clampf(float(motion.get("move_weight", 0.0)), 0.0, 1.0)
	var root: Transform2D = Transform2D(0.0, flinch_off)
	# Phase 2 — keyframed pelvis bob/roll (whole figure rises off the
	# contact frame and weight-shifts), plus anticipation/follow-through
	# lean off the attack/cast signals. Helpers still own intra-part
	# deformation (hem sway, cloth flutter) via the unchanged gait channel.
	var gp: Dictionary = _gait_pose(gait_theta)
	# Walk amplitudes are sized for a small body_r (~25px) — keep them
	# clearly above idle (~0.3px) so a step reads as a STEP, not a hover.
	var bob_y: float = -float(gp["bob"]) * body_r * 0.16 * mv
	var lag_y: float = -float(gp["lag_bob"]) * body_r * 0.15 * mv
	var roll_r: float = float(gp["roll"]) * 0.065 * mv
	# C3 weighted-walk channels (all gated by mv): hips slide over the
	# stance foot; the upper body counter-rotates the pelvis with a lag
	# (contrapposto); the head drifts opposite the hips (figure-8); a
	# narrow settle lands at each footfall (heel-strike).
	var psway: float = float(gp["psway"])
	var twist: float = float(gp["twist"])
	var contact: float = float(gp["contact"])
	var hip_x: float = psway * body_r * 0.055 * mv
	var twist_r: float = twist * 0.050 * mv
	var head_fig8: float = -psway * body_r * 0.022 * mv
	var heel_y: float = contact * body_r * 0.030 * mv
	var act: Dictionary = _action_lean(strike_t, cast_t, cast_wind_t, strike_dir, b)
	var lean: float = float(act["lean"])
	var drop_y: float = float(act["drop"]) * body_r * 0.05
	# Cast 3-beat channels: chest rears up while channelling then commits;
	# cape billows out toward the cast direction on the release frame.
	var c_dir: float = float(act["dir"])
	var c_rear: float = float(act["cast_rear"]) * body_r * 0.05
	var c_open: float = float(act["cast_open"])
	# Idle life — slow weight-shift + head scan, FULLY gated by idle_weight
	# (zero while moving or acting). Driven by the always-advancing gait
	# clock so it needs no extra state.
	var iw: float = clampf(float(motion.get("idle_weight", 0.0)), 0.0, 1.0)
	var it: float = gait_theta * 0.18
	var idle_roll: float = sin(it) * 0.012 * iw
	var idle_x: float = sin(it * 0.70) * body_r * 0.012 * iw
	var idle_bob: float = -absf(sin(it * 0.90)) * body_r * 0.010 * iw
	var scan: float = sin(it * 0.50 + 1.0)
	var head_scan_x: float = scan * body_r * 0.020 * iw
	var head_scan_r: float = scan * 0.020 * iw
	# Torso leans into the move + action lean; rolls with the pelvis.
	# Head LEADS the turn and counter-rolls (overlapping action). Cape
	# TRAILS on its lag channel and counter-rolls slightly. Rotations stay
	# tiny (≤ ~5°), pivoting about the unit centre — read, not distortion.
	# Torso = hips+shoulders: rolls with the pelvis but only ~0.70 of it,
	# so the head's counter-twist below produces a readable spine torsion
	# (contrapposto) instead of the body moving as one rigid block.
	# Turn read is amplified, and amplified MORE while walking, so he
	# clearly yaws into the direction of travel (head leads, torso yaws,
	# cape trails). Still pure rotation+translation about the centre — no
	# scale, silhouette width constant (the no-mirror rule holds).
	var turn_gain: float = 1.0 + mv * 1.10
	var torso: Transform2D = root * Transform2D(
		b * 0.080 * turn_gain + roll_r * 0.70 + lean * 0.050 + idle_roll,
		Vector2(b * body_r * 0.10 * turn_gain + lean * body_r * 0.06 + idle_x + hip_x, bob_y + drop_y + c_rear + idle_bob + heel_y))
	# Head LEADS the turn, counter-rolls the pelvis (overlapping action)
	# AND counter-twists it on a lag, drifting opposite the hips (figure-8).
	var head: Transform2D = root * Transform2D(
		-b * 0.105 * turn_gain - roll_r * 0.50 + twist_r + lean * 0.040 + idle_roll * 0.60 + head_scan_r,
		Vector2(b * body_r * 0.26 * turn_gain + lean * body_r * 0.05 + idle_x * 0.80 + head_scan_x + head_fig8, lag_y + drop_y * 0.80 + c_rear * 0.90 + idle_bob * 0.80 + heel_y * 0.80))
	# Cape TRAILS on its lag channel and counter-rolls/twists slightly.
	var cape: Transform2D = root * Transform2D(
		clag * 0.080 * turn_gain - roll_r * 0.30 - twist_r * 0.40,
		Vector2(clag * body_r * 0.26 * turn_gain + c_dir * c_open * body_r * 0.06, lag_y * 1.05 + drop_y * 0.60 + c_rear * 0.55 - c_open * body_r * 0.10))
	return {"root": root, "ground": root, "torso": torso, "head": head, "cape": cape}


# Cel-shading overlay for a part polygon: a dark occlusion wash on the
# shadow side (interior, pushed away from the light) + a bright thin rim
# light on the edges that face the light. Turns a flat fill into a
# read-as-painted mass. Centroid-relative so it's winding-agnostic.
# Local part space: -Y is up, so the light comes from up-and-left.
const NECRO_LIGHT: Vector2 = Vector2(-0.55, -0.84)
static func _cel_overlay(ci: CanvasItem, pts: PackedVector2Array, rim: Color, occ_a: float = 0.15, rim_w: float = 1.6) -> void:
	var n: int = pts.size()
	if n < 3:
		return
	var c: Vector2 = Vector2.ZERO
	for p in pts:
		c += p
	c /= float(n)
	var span: float = 0.0
	for p in pts:
		span = maxf(span, (p - c).length())
	# Occlusion: shrink toward the centroid + nudge to the shadow side.
	var push: Vector2 = -NECRO_LIGHT * span * 0.10
	var occ: PackedVector2Array = PackedVector2Array()
	for p in pts:
		occ.append(c.lerp(p, 0.88) + push)
	ci.draw_colored_polygon(occ, Color(0.0, 0.0, 0.0, occ_a))
	# Rim light: stroke only the edges whose outward direction faces the
	# light (centroid→midpoint · light > 0).
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		if ((a + b) * 0.5 - c).normalized().dot(NECRO_LIGHT) > 0.12:
			ci.draw_line(a, b, rim, rim_w, true)


static func _draw_necromancer_rune(ci: CanvasItem, v: UnitVisualData, t: float, soul_col: Color, cast_t: float, cast_wind_t: float = 0.0) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	# Brighten during wind-up so the rune glows BEFORE the bolt fires.
	var base_a: float = 0.14 + cast_t * 0.20 + cast_wind_t * 0.40
	var rune_col: Color = soul_col
	rune_col.a = base_a
	var y: float = body_r * 1.18
	var rx: float = body_r * 0.78
	ci.draw_arc(Vector2(0.0, y), rx, t * 0.55, t * 0.55 + PI * 1.45, 24, rune_col, 1.6, true)
	rune_col.a *= 0.55
	ci.draw_arc(Vector2(0.0, y), rx * 0.55, -t * 0.75, -t * 0.75 + PI * 1.15, 18, rune_col, 1.2, true)
	for i in 3:
		var a: float = t * 0.55 + float(i) * TAU / 3.0
		var p: Vector2 = Vector2(cos(a) * rx, y + sin(a) * rx * 0.26)
		var dot_col: Color = soul_col
		dot_col.a = 0.18 + cast_t * 0.25
		ci.draw_circle(p, 2.0 + cast_t * 1.0, dot_col)


static func _draw_necromancer_wisps(ci: CanvasItem, v: UnitVisualData, t: float, soul_col: Color, cast_t: float) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var side_offsets: PackedFloat32Array = PackedFloat32Array([-0.82, 0.18, 0.62])
	for i in 3:
		var phase: float = t * 0.55 + float(i) * 2.1
		var rise: float = fposmod(phase, 1.0)
		var side: float = side_offsets[i]
		var x: float = side * body_r + sin(t * 1.7 + float(i) * 1.4) * 2.4
		var y: float = body_r * 0.42 - rise * body_r * 1.25
		var fade: float = sin(rise * PI)
		var col: Color = soul_col
		col.a = (0.075 + cast_t * 0.10) * fade
		ci.draw_circle(Vector2(x, y), 3.8 + fade * 2.0, col)
		col.a *= 0.70
		ci.draw_arc(Vector2(x, y), 5.0 + fade * 2.5, phase * TAU, phase * TAU + PI * 0.65, 8, col, 0.9, true)


static func _knee_ik(hip: Vector2, foot: Vector2, bone: float, face_sign: float) -> Vector2:
	# Equal-bone 2-link IK: knee on the perpendicular bisector of hip→foot,
	# bent toward the travel direction. bone·2 > reach, so the knee always
	# carries a slight bend (a stick never locks), and it bends MORE as the
	# foot lifts (hip-foot distance shrinks during swing).
	var ax: Vector2 = foot - hip
	var d_raw: float = ax.length()
	var d: float = clampf(d_raw, 0.001, bone * 2.0 * 0.999)
	var hh: float = sqrt(maxf(0.0, bone * bone - d * d * 0.25))
	var axn: Vector2 = ax / d_raw if d_raw > 0.001 else Vector2.DOWN
	var perp: Vector2 = Vector2(-axn.y, axn.x)
	if perp.x * face_sign < 0.0:
		perp = -perp
	return (hip + foot) * 0.5 + perp * hh


static func _draw_necromancer_feet(ci: CanvasItem, v: UnitVisualData, body_r: float, gait_theta: float, mv: float, body_off: Vector2, speed01: float = 1.0, face_sign: float = 1.0) -> void:
	# Two stepping legs that peek below the robe hem so the walk reads at
	# the feet, not just the body. Walk-only — nothing drawn when idle
	# (the robe hem covers this band, so idle is unchanged).
	#
	# Drawn in the GROUND frame (rig root), NOT the torso frame: the foot
	# is ground-locked during its stance phase while `body_off` (the
	# torso's bob/hip-shift) only moves the HIP. The leg
	# extends/compresses as the body rolls over the planted foot — that
	# knee read is what sells the weight. Classic 2-state stance/swing
	# treadmill cycle (stance ≈ 62% of the stride, like a real walk).
	# Continuous fade from real speed (mv keeps it off when the state isn't
	# MOVING). speed01 ramps, so the feet fade in/out under the hem instead
	# of popping on/off at gait start/stop.
	var fb: float = smoothstep(0.0, 1.0, clampf(speed01 / 0.30, 0.0, 1.0) * clampf(mv, 0.0, 1.0))
	if fb <= 0.01:
		return
	var hip_y: float = body_r * 0.86
	var leg_w: float = maxf(5.0, body_r * 0.24)
	var leg_len: float = body_r * 0.80
	var ground_y: float = hip_y + leg_len
	var bone: float = leg_len * 0.53
	var sp: float = clampf(speed01, 0.0, 1.0)
	# Stride scales with speed; both stride + lift also scale with the
	# fade so the feet settle to the ground as they vanish (no float).
	var stride: float = body_r * 0.32 * lerpf(0.55, 1.15, sp) * lerpf(0.45, 1.0, fb)
	var lift: float = body_r * 0.20 * lerpf(0.80, 1.05, sp) * fb
	var leg_fill: Color = v.outline_color.lerp(Color(0.16, 0.13, 0.20, 1.0), 0.45)
	leg_fill.a *= fb
	var leg_ink: Color = v.outline_color
	leg_ink.a *= fb
	var boot_col: Color = v.outline_color
	boot_col.a *= fb
	var ow: float = maxf(1.5, v.outline_width * 0.40)
	const STANCE: float = 0.62
	for s in [-1.0, 1.0]:
		var p: float = gait_theta + (0.0 if s < 0.0 else PI)
		var ph: float = fposmod(p, TAU) / TAU
		var anchor_x: float = s * body_r * 0.16
		var fx: float
		var fy: float
		if ph < STANCE:
			# Stance: foot pinned, drifting backward at CONSTANT ground
			# speed. Linear on purpose — easing here would skate the
			# planted foot relative to the floor.
			var u: float = ph / STANCE
			fx = anchor_x + face_sign * lerpf(stride * 0.5, -stride * 0.5, u)
			fy = ground_y
		else:
			# Swing: airborne, so the path is EASED. X smoothsteps
			# (accelerate out of toe-off, decelerate into the plant). Y is
			# an arc peaking ~45% that eases to ZERO slope at touchdown —
			# a soft landing, not the old downward-velocity hard stop.
			var u: float = (ph - STANCE) / (1.0 - STANCE)
			fx = anchor_x + face_sign * lerpf(-stride * 0.5, stride * 0.5, smoothstep(0.0, 1.0, u))
			var apex: float = 0.45
			var h01: float = smoothstep(0.0, 1.0, u / apex) if u < apex else 1.0 - smoothstep(0.0, 1.0, (u - apex) / (1.0 - apex))
			fy = ground_y - h01 * lift
		# Hip follows the body (bob + hip-shift); foot stays on the floor.
		var hip: Vector2 = body_off + Vector2(anchor_x, hip_y)
		var foot: Vector2 = Vector2(fx, fy)
		# Dust scuff — bursts the instant the foot plants (ph≈0), expands
		# + fades over the first ~16% of the stride. Faded by fb.
		if ph < 0.16:
			var sf: float = 1.0 - ph / 0.16
			var grow: float = 1.0 - sf
			var dy: float = ground_y + body_r * 0.10
			var dust: Color = Color(0.60, 0.56, 0.50, 0.20 * sf * fb)
			ci.draw_arc(Vector2(fx, dy), body_r * (0.10 + 0.26 * grow), PI * 1.04, PI * 1.96, 9, dust, 1.6, true)
			dust.a *= 0.7
			ci.draw_circle(Vector2(fx - body_r * (0.10 + 0.20 * grow), dy - body_r * 0.06 * grow), 1.5 + 1.4 * grow, dust)
			ci.draw_circle(Vector2(fx + body_r * (0.10 + 0.22 * grow), dy - body_r * 0.05 * grow), 1.3 + 1.2 * grow, dust)
		# 2-bone leg: hip → knee → foot. The knee bends toward travel and
		# auto-bends more in swing (real knee read, not a straight stick).
		var knee: Vector2 = _knee_ik(hip, foot, bone, face_sign)
		_draw_arm_segment(ci, hip, knee, leg_w, leg_fill, leg_ink, ow)
		_draw_arm_segment(ci, knee, foot, leg_w * 0.82, leg_fill, leg_ink, ow)
		# Boot rolled about the ankle: heel-strike just after plant → flat
		# through stance → toe-off push near stance end → level in swing.
		var bw: float = body_r * 0.36
		var bh: float = body_r * 0.18
		var roll: float = (0.22 * _window_sin(ph, 0.0, 0.18) - 0.42 * _window_sin(ph, 0.46, 0.70) + 0.12 * _window_sin(ph, 0.70, 1.0)) * face_sign
		var raw_boot: PackedVector2Array = PackedVector2Array([
			Vector2(face_sign * (-bw * 0.45), -bh * 0.65),
			Vector2(face_sign * (bw * 0.60), -bh * 0.50),
			Vector2(face_sign * (bw * 0.66), bh * 0.50),
			Vector2(face_sign * (-bw * 0.50), bh * 0.50),
		])
		var boot_pts: PackedVector2Array = PackedVector2Array()
		for q in raw_boot:
			boot_pts.append(foot + q.rotated(roll))
		ci.draw_colored_polygon(boot_pts, boot_col)
		# Rim only (occ 0 — boots are near-black): faint leather sheen.
		_cel_overlay(ci, boot_pts, Color(0.62, 0.64, 0.74, 0.26 * fb), 0.0, 1.1)


static func _draw_necromancer_cape(ci: CanvasItem, v: UnitVisualData, t: float, ink_t: float, motion: Dictionary) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	# Phase D — cape lags the body's gait by ~π/3 (secondary motion).
	# `gait_lag` approximates "the cape catches up to the body half a beat
	# later" so the cape and torso don't move in lockstep.
	# Hood and eyes lead the direction change; cape trails opposite so the
	# rear silhouette never reads as the front of the move.
	var gait: float = float(motion.get("gait", 0.0))
	var turn: float = 0.0  # rig owns directional turn (Phase 1); kept 0 so the legacy tuck math stays inert
	var cape_lag: float = float(motion.get("cape_lag", -turn))
	var idle_weight: float = float(motion.get("idle_weight", 0.0))
	var idle_cape: float = float(motion.get("idle_cape", 0.0))
	var idle_settle: float = float(motion.get("idle_settle", 0.0))
	var move_weight: float = float(motion.get("move_weight", 0.0))
	var attack_weight: float = float(motion.get("attack_weight", 0.0))
	var cast_weight: float = float(motion.get("cast_weight", 0.0))
	# Phase 4 — cloth flutter is secondary motion: step it on twos. The
	# gait term stays smooth (it's locomotion, fed by the smooth gait).
	var sct: float = _ink_step_time(t, 12.0)
	var gait_lag: float = gait * 0.6 - sin(sct * 1.4) * 0.30
	var idle_wave: float = (idle_cape * body_r * 0.026 + idle_settle * body_r * 0.010) * idle_weight
	var cloth_wave: float = idle_wave + sin(sct * 1.5) * body_r * 0.035 * move_weight + gait_lag * body_r * 0.075 * move_weight
	var cloth_trail: float = cape_lag * body_r * 0.32
	var upper_flutter: float = cloth_wave * 0.15 + cloth_trail * 0.10
	var mid_flutter: float = cloth_wave * 0.55 + cloth_trail * 0.55
	var hem_flutter: float = cloth_wave + cloth_trail
	var cape_lift: float = -cast_weight * body_r * 0.08 + attack_weight * body_r * 0.04
	var right_front_tuck: float = maxf(turn, 0.0) * body_r * 0.20
	var left_front_tuck: float = maxf(-turn, 0.0) * body_r * 0.20
	var cape: Color = v.cape_color if v.cape_color.a > 0.0 else Color(0.09, 0.04, 0.16, 0.72)
	var shade: Color = v.outline_color
	shade.a = 0.45
	var inner_shadow: Color = Color(0.0, 0.0, 0.0, 0.24)
	# Top anchors stay close to the shoulders; lower vertices trail harder.
	# The front-side edge also tucks inward so the robe/hood lead the motion.
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(-body_r * 0.60 + upper_flutter + left_front_tuck * 0.30, -body_r * 0.59 + cape_lift * 0.25),
		Vector2(body_r * 0.46 + upper_flutter - right_front_tuck * 0.30, -body_r * 0.55 + cape_lift * 0.25),
		Vector2(body_r * 0.70 + hem_flutter - right_front_tuck, body_r * 1.20 + cape_lift),
		Vector2(body_r * 0.36 + mid_flutter - right_front_tuck * 0.55, body_r * 1.10 + cape_lift * 0.75),
		Vector2(body_r * 0.12 + hem_flutter, body_r * 1.44 + cape_lift),
		Vector2(-body_r * 0.08 + mid_flutter, body_r * 1.23 + cape_lift * 0.75),
		Vector2(-body_r * 0.42 + hem_flutter + left_front_tuck * 0.55, body_r * 1.42 + cape_lift),
		Vector2(-body_r * 0.82 + hem_flutter + left_front_tuck, body_r * 1.18 + cape_lift),
	])
	ci.draw_colored_polygon(pts, cape)
	_cel_overlay(ci, pts, Color(0.52, 0.54, 0.78, 0.26), 0.10, 1.4)
	_ink_weighted(ci, PackedVector2Array([pts[0], pts[7], pts[6], pts[5], pts[4], pts[3], pts[2], pts[1]]), shade, 2.0, false, ink_t, 0.35, 1.2)
	# Dark pinned shoulder gap. The front robe is drawn later, so this reads
	# as separation between the stable torso and the trailing cape.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-body_r * 0.50 + upper_flutter * 0.30, -body_r * 0.48),
		Vector2(body_r * 0.44 + upper_flutter * 0.25, -body_r * 0.45),
		Vector2(body_r * 0.36 + mid_flutter * 0.25, -body_r * 0.22),
		Vector2(-body_r * 0.42 + mid_flutter * 0.25, -body_r * 0.24),
	]), inner_shadow)
	var dry_ink: Color = shade
	dry_ink.a = 0.18
	_rough_polyline(ci, PackedVector2Array([pts[0], pts[7], pts[6], pts[5], pts[4], pts[3], pts[2], pts[1]]), dry_ink, 1.0, false, ink_t + 0.37, 0.18, 1.8)
	for i in 3:
		var k: float = float(i)
		var fold_x: float = lerpf(-body_r * 0.45, body_r * 0.32, k / 2.0) + hem_flutter * (0.18 + k * 0.06)
		_rough_line(ci, Vector2(fold_x, -body_r * 0.18 + k * body_r * 0.07), Vector2(fold_x + cloth_trail * 0.25, body_r * (0.70 + k * 0.12) + cape_lift * 0.60), dry_ink, 0.9, ink_t, 43.0 + k, 0.10, 0.25)


static func _draw_necromancer_robe(ci: CanvasItem, v: UnitVisualData, body_col: Color, soul_col: Color, pulse: float, ink_t: float, cast_t: float, motion: Dictionary) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var outline_w: float = maxf(2.0, v.outline_width * 0.55)
	# Phase D — boost gait amplitudes so the robe visibly walks (hem swings,
	# torso leans into the step). Multi-frequency `step_sweep` adds a second
	# harmonic so the hem reads as 4-keyframe (contact/recoil/passing/high)
	# rather than a pure sin wobble.
	var gait: float = float(motion.get("gait", 0.0))
	var turn: float = 0.0  # rig owns directional turn (Phase 1); kept 0 so the legacy width/shift math stays inert
	var torso_turn: float = 0.0
	var idle_weight: float = float(motion.get("idle_weight", 0.0))
	var idle_breath: float = float(motion.get("idle_breath", 0.0))
	var idle_settle: float = float(motion.get("idle_settle", 0.0))
	var attack_weight: float = float(motion.get("attack_weight", 0.0))
	var cast_weight: float = float(motion.get("cast_weight", 0.0))
	var step_sweep: float = gait * 0.65 + sin(gait * PI * 2.0) * 0.18
	var shoulder_sway: float = step_sweep * body_r * 0.025
	var hem_sway: float = step_sweep * body_r * 0.16
	var idle_hem: float = idle_settle * body_r * 0.018 * idle_weight
	var hem_lag: float = -step_sweep * body_r * 0.20 + idle_hem
	var cast_lift: float = (cast_t * 0.10 + cast_weight * 0.04 + attack_weight * 0.03) * body_r
	var torso_shift: float = torso_turn * body_r * 0.07
	var torso_breath_y: float = idle_breath * body_r * 0.014 * idle_weight
	var side_turn_shift: float = turn * body_r * 0.10
	var hem_turn_shift: float = turn * body_r * 0.08
	var right_front: float = maxf(turn, 0.0)
	var left_front: float = maxf(-turn, 0.0)
	var right_side_w: float = 1.0 - right_front * 0.10 + left_front * 0.12
	var left_side_w: float = 1.0 - left_front * 0.10 + right_front * 0.12
	var torso_shadow: Color = Color(0.0, 0.0, 0.0, 0.30)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2((-body_r * 0.58 * left_side_w) + torso_shift - body_r * 0.04, -body_r * 0.60 - cast_lift),
		Vector2((body_r * 0.52 * right_side_w) + torso_shift + body_r * 0.05, -body_r * 0.57 - cast_lift),
		Vector2((body_r * 0.62 * right_side_w) + side_turn_shift * 0.45, body_r * 0.98),
		Vector2(body_r * 0.12 + hem_lag * 0.40, body_r * 1.32),
		Vector2(-body_r * 0.48 + hem_lag * 0.45, body_r * 1.24),
		Vector2((-body_r * 0.66 * left_side_w) + side_turn_shift * 0.35, body_r * 0.28),
	]), torso_shadow)
	var robe: PackedVector2Array = PackedVector2Array([
		Vector2((-body_r * 0.52 * left_side_w) + shoulder_sway + torso_shift, -body_r * 0.68 - cast_lift),
		Vector2((body_r * 0.46 * right_side_w) + shoulder_sway * 0.70 + torso_shift, -body_r * 0.65 - cast_lift),
		Vector2((body_r * 0.70 * right_side_w) + side_turn_shift + hem_sway * 0.30, -body_r * 0.18 - cast_lift * 0.45),
		Vector2((body_r * 0.78 * right_side_w) + hem_sway + hem_turn_shift * 0.5, body_r * 0.78),
		Vector2(body_r * 0.57 + hem_lag - hem_turn_shift * 0.20, body_r * 1.15),
		Vector2(body_r * 0.30 + hem_lag * 0.65 - hem_turn_shift * 0.25, body_r * 1.03),
		Vector2(body_r * 0.08 + hem_lag - hem_turn_shift * 0.55, body_r * 1.50),
		Vector2(-body_r * 0.12 + hem_lag * 0.80 - hem_turn_shift * 0.60, body_r * 1.20),
		Vector2(-body_r * 0.45 + hem_lag - hem_turn_shift * 0.35, body_r * 1.42),
		Vector2((-body_r * 0.76 * left_side_w) + hem_sway * 0.35 + side_turn_shift * 0.35, body_r * 1.04),
		Vector2((-body_r * 0.82 * left_side_w) + hem_sway * 0.25 + side_turn_shift * 0.45, body_r * 0.50),
		Vector2((-body_r * 0.66 * left_side_w) + shoulder_sway * 0.50 + side_turn_shift * 0.35, -body_r * 0.24 - cast_lift * 0.30),
	])
	ci.draw_colored_polygon(robe, body_col)
	var robe_rim: Color = (v.highlight_color if v.highlight_color.a > 0.0 else soul_col).lerp(Color(1, 1, 1, 1), 0.40)
	robe_rim.a = 0.34
	_cel_overlay(ci, robe, robe_rim, 0.16, 1.8)
	_ink_weighted(ci, robe, v.outline_color, outline_w, true, ink_t, 0.42, 1.4)

	var shadow: Color = v.outline_color
	shadow.a = 0.38
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(body_r * 0.10, -body_r * 0.55),
		Vector2(body_r * 0.54, -body_r * 0.20),
		Vector2(body_r * 0.60, body_r * 0.92),
		Vector2(body_r * 0.24, body_r * 1.12),
		Vector2(body_r * 0.02, body_r * 0.62),
	]), shadow)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-body_r * 0.50, -body_r * 0.20),
		Vector2(-body_r * 0.18, -body_r * 0.54),
		Vector2(-body_r * 0.10, body_r * 0.68),
		Vector2(-body_r * 0.40, body_r * 1.10),
		Vector2(-body_r * 0.62, body_r * 0.84),
	]), Color(0.0, 0.0, 0.0, 0.18))

	var panel_col: Color = Color(
		minf(body_col.r * 1.22 + 0.025, 1.0),
		minf(body_col.g * 1.16 + 0.020, 1.0),
		minf(body_col.b * 1.20 + 0.030, 1.0),
		body_col.a
	)
	var front_panel: PackedVector2Array = PackedVector2Array([
		Vector2(-body_r * 0.34 + torso_shift, -body_r * 0.52 - cast_lift * 0.80 + torso_breath_y),
		Vector2(body_r * 0.28 + torso_shift, -body_r * 0.50 - cast_lift * 0.80 + torso_breath_y),
		Vector2(body_r * 0.42 + torso_shift * 0.55, body_r * 0.58 + torso_breath_y * 0.20),
		Vector2(body_r * 0.16 + hem_lag * 0.18, body_r * 1.22),
		Vector2(-body_r * 0.08 + hem_lag * 0.14, body_r * 1.42),
		Vector2(-body_r * 0.36 + torso_shift * 0.35, body_r * 0.72 + torso_breath_y * 0.20),
	])
	ci.draw_colored_polygon(front_panel, panel_col)
	_cel_overlay(ci, front_panel, robe_rim, 0.10, 1.3)
	var panel_ink: Color = v.outline_color
	panel_ink.a = 0.74
	_rough_polyline(ci, front_panel, panel_ink, maxf(1.6, outline_w * 0.72), true, ink_t, 0.18, 0.65)
	var sketch_ink: Color = v.outline_color
	sketch_ink.a = 0.16
	_rough_line(ci, Vector2(-body_r * 0.27 + torso_shift, -body_r * 0.33), Vector2(-body_r * 0.22 + hem_lag * 0.10, body_r * 0.98), sketch_ink, 0.9, ink_t, 35.0, 0.08, 0.25)
	_rough_line(ci, Vector2(body_r * 0.20 + torso_shift, -body_r * 0.30), Vector2(body_r * 0.12 + hem_lag * 0.08, body_r * 1.03), sketch_ink, 0.9, ink_t, 36.0, 0.08, 0.25)

	var trim: Color = v.highlight_color if v.highlight_color.a > 0.0 else soul_col
	trim.a = 0.24 + maxf(0.0, pulse) * 0.08
	_rough_line(ci, Vector2(-body_r * 0.34, -body_r * 0.42), Vector2(-body_r * 0.39, body_r * 0.10), trim, 1.5, ink_t, 8.0)
	_rough_line(ci, Vector2(-body_r * 0.43, body_r * 0.24), Vector2(-body_r * 0.48, body_r * 0.82), trim, 1.2, ink_t, 9.0)
	_rough_line(ci, Vector2(body_r * 0.26, -body_r * 0.38), Vector2(body_r * 0.20, body_r * 0.36), trim, 1.1, ink_t, 10.0)
	_rough_line(ci, Vector2(body_r * 0.32, body_r * 0.52), Vector2(body_r * 0.26, body_r * 1.02), trim, 1.0, ink_t, 11.0)

	var fold_dark: Color = Color(0.02, 0.01, 0.05, 0.34)
	_rough_line(ci, Vector2(-body_r * 0.10, -body_r * 0.40), Vector2(-body_r * 0.21, body_r * 0.38), fold_dark, 1.3, ink_t, 12.0)
	_rough_line(ci, Vector2(-body_r * 0.18, body_r * 0.56), Vector2(-body_r * 0.28, body_r * 1.05), fold_dark, 1.0, ink_t, 13.0)
	_rough_line(ci, Vector2(body_r * 0.09, -body_r * 0.34), Vector2(body_r * 0.02, body_r * 0.38), fold_dark, 1.1, ink_t, 14.0)
	_rough_line(ci, Vector2(body_r * 0.12, body_r * 0.58), Vector2(body_r * 0.02, body_r * 1.18), fold_dark, 1.0, ink_t, 15.0)

	var collar: Color = v.hat_color if v.hat_color.a > 0.0 else v.outline_color
	collar.a = maxf(collar.a, 0.95)
	var collar_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-body_r * 0.44 + torso_shift, -body_r * 0.62),
		Vector2(body_r * 0.44 + torso_shift, -body_r * 0.62),
		Vector2(body_r * 0.30 + torso_shift * 0.75, -body_r * 0.32),
		Vector2(torso_shift * 0.45, -body_r * 0.18),
		Vector2(-body_r * 0.30 + torso_shift * 0.75, -body_r * 0.32),
	])
	ci.draw_colored_polygon(collar_pts, collar)
	_cel_overlay(ci, collar_pts, robe_rim, 0.12, 1.3)

	var chest_glow: Color = soul_col
	chest_glow.a = 0.12 + maxf(0.0, pulse) * 0.06 + maxf(0.0, idle_breath) * idle_weight * 0.035
	var pendant_center: Vector2 = Vector2(-body_r * 0.04 + torso_shift + torso_turn * body_r * 0.08, body_r * 0.12 + torso_breath_y * 0.55)
	_rough_line(ci, Vector2(-body_r * 0.20, -body_r * 0.28), pendant_center, Color(0.74, 0.68, 0.58, 0.70), 1.0, ink_t, 16.0, 0.20, 0.35)
	_rough_line(ci, Vector2(body_r * 0.14, -body_r * 0.26), pendant_center, Color(0.74, 0.68, 0.58, 0.62), 1.0, ink_t, 17.0, 0.20, 0.35)
	_draw_rough_circle(ci, pendant_center, body_r * 0.19, chest_glow, Color(0, 0, 0, 0), 0.0, ink_t, 18.0, 8, 0.09)
	_draw_skull_glyph(ci, pendant_center, maxf(4.0, body_r * 0.14), false)

	var bone: Color = Color(0.90, 0.84, 0.72, 0.95)
	for side in [-1.0, 1.0]:
		_rough_line(ci, Vector2(side * body_r * 0.26, body_r * 0.45), Vector2(side * body_r * 0.40, body_r * 0.70), bone, 2.0, ink_t, 19.0 + side, 0.18, 0.25)
		_draw_rough_circle(ci, Vector2(side * body_r * 0.43, body_r * 0.75), 2.2, bone, Color(0, 0, 0, 0), 0.0, ink_t, 20.0 + side, 7, 0.12)


static func _draw_necromancer_arms_and_staff(ci: CanvasItem, v: UnitVisualData, t: float, ink_t: float, motion: Dictionary, wind_t: float, strike_t: float, strike_dir: Vector2, arm_col: Color, magic_col: Color, cast_t: float, breath_amp: float = 0.0, cast_wind_t: float = 0.0) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var outline_w: float = maxf(1.6, v.outline_width * 0.38)
	var cast_raise: float = sin(clampf(cast_t, 0.0, 1.0) * PI) * body_r * 0.20
	var gait: float = float(motion.get("gait", 0.0))
	var turn: float = 0.0  # rig owns directional turn (Phase 1); kept 0 so the legacy depth-shift math stays inert
	var staff_lag: float = float(motion.get("staff_lag", -turn * 0.08))
	var idle_weight: float = float(motion.get("idle_weight", 0.0))
	var move_weight: float = float(motion.get("move_weight", 0.0))
	var idle_staff_channel: float = float(motion.get("idle_staff", 0.0))
	var idle_orb: float = float(motion.get("idle_orb", 0.5))
	var attack_weight: float = float(motion.get("attack_weight", 0.0))
	var cast_weight: float = float(motion.get("cast_weight", 0.0))
	var depth_shift: float = turn * body_r * 0.16
	var idle_staff: float = idle_staff_channel * body_r * 0.032 * idle_weight
	var attack_pull: float = attack_weight * body_r * 0.12
	var left_shoulder: Vector2 = Vector2(-body_r * 0.48 + gait * body_r * 0.025 + depth_shift * 0.35, -body_r * 0.42 - cast_raise * 0.35 - cast_weight * body_r * 0.03)
	# Phase 4 — idle hand jitter + staff sway are secondary: step on twos.
	var sat: float = _ink_step_time(t, 12.0)
	var left_hand: Vector2 = Vector2(-body_r * 0.72 - gait * body_r * 0.055 + depth_shift * 0.20 - attack_pull * 0.15, body_r * 0.22 + sin(sat * 1.8) * 1.8 - cast_raise)
	_draw_arm_segment(ci, left_shoulder, left_hand, body_r * 0.18, arm_col, v.outline_color, outline_w)

	# Staff lags the turn like a ritual cane; hood and eyes carry the
	# forward read while the prop catches up a beat later.
	var staff_sway: float = idle_staff + sin(sat * 1.35) * (0.65 + move_weight * 1.35) - gait * body_r * 0.10 + staff_lag * body_r * 0.22
	# Melee staff swing — a real arc, not a sway: anticipation cocks the
	# staff back + up, impact sweeps it across toward the target and down,
	# then a short follow-through settles. Off the existing strike signal;
	# the cast path (cast_t / cast_wind_t) is untouched.
	var melee_y: float = 0.0
	if strike_t >= 0.0:
		var st: float = clampf(strike_t, 0.0, 1.0)
		var mdir: float = signf(strike_dir.x) if absf(strike_dir.x) > 0.001 else 1.0
		var melee_x: float = (-0.50 * _window_sin(st, 0.0, 0.30) + 1.00 * _window_sin(st, 0.22, 0.66) - 0.22 * _window_sin(st, 0.58, 1.0)) * mdir * body_r * 0.55
		melee_y = (-0.55 * _window_sin(st, 0.0, 0.32) + 0.70 * _window_sin(st, 0.24, 0.64)) * body_r
		staff_sway += melee_x
	var release_snap: float = sin(clampf(cast_t, 0.0, 1.0) * PI) * body_r * 0.18
	var grip: Vector2 = Vector2(body_r * 0.58 + staff_sway * 0.25 - release_snap * 0.35 - depth_shift * 0.35 - attack_pull * 0.25, -body_r * 0.18 - cast_raise * 0.35 + melee_y * 0.25)
	var staff_top: Vector2 = Vector2(body_r * 0.69 + staff_sway - release_snap - depth_shift * 0.55 - attack_pull, -body_r * (2.05 + wind_t * 0.14 + cast_weight * 0.08) - cast_raise + melee_y)
	var staff_upper: Vector2 = Vector2(body_r * 0.56 + staff_sway * 0.65 - release_snap * 0.70 - depth_shift * 0.45 - attack_pull * 0.65, -body_r * 1.25 - cast_raise * 0.78 + melee_y * 0.70)
	var staff_mid: Vector2 = Vector2(body_r * 0.66 + staff_sway * 0.45 - release_snap * 0.45 - depth_shift * 0.35 - attack_pull * 0.35, -body_r * 0.62 - cast_raise * 0.35)
	var staff_lower: Vector2 = Vector2(body_r * 0.54 - staff_sway * 0.12 - depth_shift * 0.22, body_r * 0.32)
	var staff_bot: Vector2 = Vector2(body_r * 0.47 - staff_sway * 0.18 + gait * body_r * 0.05 - depth_shift * 0.16, body_r * 1.22)
	var shaft_shadow: Color = v.outline_color
	shaft_shadow.a = 0.95
	var shaft: PackedVector2Array = PackedVector2Array([staff_bot, staff_lower, grip, staff_mid, staff_upper, staff_top])
	if cast_t > 0.62:
		var smear_a: float = clampf((cast_t - 0.62) / 0.38, 0.0, 1.0)
		var shaft_dir: Vector2 = (staff_top - grip).normalized()
		var side: Vector2 = Vector2(-shaft_dir.y, shaft_dir.x)
		var smear_col: Color = magic_col
		smear_col.a = 0.16 * smear_a
		ci.draw_colored_polygon(PackedVector2Array([
			staff_top + side * body_r * 0.28,
			staff_top - side * body_r * 0.18,
			grip - side * body_r * 0.10,
			grip + side * body_r * 0.18,
		]), smear_col)
	_rough_polyline(ci, shaft, shaft_shadow, 5.3, false, ink_t, 0.20, 0.75)
	_rough_polyline(ci, shaft, Color(0.42, 0.26, 0.16, 1.0), 2.4, false, ink_t, 0.15, 0.55)
	_rough_line(ci, staff_lower + Vector2(-1.0, -2.0), staff_lower + Vector2(2.0, 5.0), Color(0.18, 0.10, 0.08, 0.70), 1.0, ink_t, 23.0, 0.14, 0.2)
	_rough_line(ci, staff_upper + Vector2(1.0, -4.0), staff_upper + Vector2(-2.0, 5.0), Color(0.72, 0.48, 0.28, 0.45), 1.0, ink_t, 24.0, 0.14, 0.2)

	var right_shoulder: Vector2 = Vector2(body_r * 0.45 + gait * body_r * 0.025 - depth_shift * 0.12, -body_r * 0.42 - cast_raise * 0.35 - cast_weight * body_r * 0.03)
	_draw_arm_segment(ci, right_shoulder, grip, body_r * 0.18, arm_col, v.outline_color, outline_w)

	var bone_col: Color = Color(0.86, 0.80, 0.68, 0.98)
	ci.draw_arc(staff_top + Vector2(-1.0, 1.0), body_r * 0.22, deg_to_rad(116.0), deg_to_rad(286.0), 12, bone_col, 3.0, true)
	ci.draw_arc(staff_top + Vector2(1.5, 2.0), body_r * 0.29, deg_to_rad(-62.0), deg_to_rad(72.0), 12, v.outline_color, 1.8, true)
	_draw_rough_circle(ci, staff_top + Vector2(-body_r * 0.19, body_r * 0.02), 1.7, bone_col, Color(0, 0, 0, 0), 0.0, ink_t, 25.0, 7, 0.12)

	var flash: float = clampf(cast_t, 0.0, 1.0)
	# Subtle idle breath pulse on the orb — multiplies the size and alpha
	# by ±8% on a slow sin so the staff reads as "alive" when standing still.
	var breath_mult: float = 1.0 + breath_amp * 0.05 + idle_orb * idle_weight * 0.09
	# Pre-cast wind-up — orb swells dramatically and core brightens before
	# the projectile fires. Decays to 0 by the time `cast_t` aftermath starts.
	var wind_mult: float = 1.0 + cast_wind_t * 1.5
	var orb_col: Color = magic_col
	orb_col.a = (0.18 + idle_orb * idle_weight * 0.08 + flash * 0.36 + cast_wind_t * 0.50) * breath_mult
	ci.draw_circle(staff_top, body_r * (0.34 + flash * 0.14) * breath_mult * wind_mult, orb_col)
	orb_col.a = 0.85
	_draw_rough_circle(ci, staff_top, body_r * (0.15 + flash * 0.05) * breath_mult * wind_mult, orb_col, Color(0, 0, 0, 0), 0.0, ink_t, 26.0, 9, 0.07)
	_draw_rough_circle(ci, staff_top + _ink_jitter(27.0, ink_t, 0.25), body_r * (0.06 + flash * 0.04) * breath_mult * wind_mult, Color(1.0, 1.0, 1.0, 0.92), Color(0, 0, 0, 0), 0.0, ink_t, 27.0, 7, 0.10)


static func _draw_necromancer_hood(ci: CanvasItem, v: UnitVisualData, head_col: Color, soul_col: Color, pulse: float, ink_t: float, cast_t: float, motion: Dictionary, breath_amp: float = 0.0) -> void:
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	# The premium robe has its own shoulder line, so keep the hood nested
	# into the collar instead of inheriting the generic hero's high head slot.
	# Idle breath bobs the hood Y down by ~1% body_r on the exhale frame.
	var gait: float = float(motion.get("gait", 0.0))
	var turn: float = 0.0  # rig owns directional turn (Phase 1); kept 0 so the legacy head-shift math stays inert
	var idle_weight: float = float(motion.get("idle_weight", 0.0))
	var attack_weight: float = float(motion.get("attack_weight", 0.0))
	var cast_weight: float = float(motion.get("cast_weight", 0.0))
	var idle_breath: float = float(motion.get("idle_breath", 0.0))
	var idle_settle: float = float(motion.get("idle_settle", 0.0))
	var idle_nod: float = (idle_breath * body_r * 0.008 + idle_settle * body_r * 0.004) * idle_weight
	var head_y: float = maxf(v.head_y_offset * body_r, -body_r * 1.08) - cast_t * body_r * 0.06 + breath_amp * body_r * 0.010 + idle_nod - cast_weight * body_r * 0.035 + attack_weight * body_r * 0.018
	var head_x: float = -gait * body_r * 0.025 + turn * body_r * 0.14 + idle_settle * body_r * 0.006 * idle_weight
	var hood_right_w: float = 1.0 - maxf(turn, 0.0) * 0.08 + maxf(-turn, 0.0) * 0.10
	var hood_left_w: float = 1.0 - maxf(-turn, 0.0) * 0.08 + maxf(turn, 0.0) * 0.10
	var hood_fill: Color = v.hat_color if v.hat_color.a > 0.0 else Color(0.08, 0.05, 0.14, 1.0)
	var hood: PackedVector2Array = PackedVector2Array([
		Vector2(head_x - body_r * 0.06, head_y - body_r * 0.98),
		Vector2(head_x + body_r * 0.42 * hood_right_w, head_y - body_r * 0.64),
		Vector2(head_x + body_r * 0.66 * hood_right_w, head_y - body_r * 0.10),
		Vector2(head_x + body_r * 0.34 * hood_right_w, head_y + body_r * 0.27),
		Vector2(head_x + body_r * 0.05, head_y + body_r * 0.45),
		Vector2(head_x - body_r * 0.24 * hood_left_w, head_y + body_r * 0.34),
		Vector2(head_x - body_r * 0.56 * hood_left_w, head_y + body_r * 0.08),
		Vector2(head_x - body_r * 0.54 * hood_left_w, head_y - body_r * 0.48),
	])
	ci.draw_colored_polygon(hood, hood_fill)
	_cel_overlay(ci, hood, Color(0.70, 0.74, 0.88, 0.30), 0.14, 1.5)
	_ink_weighted(ci, hood, v.outline_color, maxf(2.0, v.outline_width * 0.45), true, ink_t, 0.36, 1.0)
	var hood_dry_ink: Color = v.outline_color
	hood_dry_ink.a = 0.20
	_rough_polyline(ci, hood, hood_dry_ink, 1.0, true, ink_t + 0.21, 0.14, 1.6)

	var face_void: Color = Color(0.02, 0.01, 0.04, 0.96)
	var face: PackedVector2Array = PackedVector2Array([
		Vector2(head_x - body_r * 0.02, head_y - body_r * 0.70),
		Vector2(head_x + body_r * 0.23, head_y - body_r * 0.43),
		Vector2(head_x + body_r * 0.19, head_y - body_r * 0.02),
		Vector2(head_x - body_r * 0.02, head_y + body_r * 0.17),
		Vector2(head_x - body_r * 0.25, head_y - body_r * 0.04),
		Vector2(head_x - body_r * 0.21, head_y - body_r * 0.43),
	])
	ci.draw_colored_polygon(face, face_void)
	var hood_fold: Color = Color(0.0, 0.0, 0.0, 0.22)
	_rough_line(ci, Vector2(head_x - body_r * 0.34, head_y - body_r * 0.38), Vector2(head_x - body_r * 0.20, head_y + body_r * 0.18), hood_fold, 0.9, ink_t, 32.0, 0.08, 0.20)
	_rough_line(ci, Vector2(head_x + body_r * 0.30, head_y - body_r * 0.33), Vector2(head_x + body_r * 0.16, head_y + body_r * 0.16), hood_fold, 0.9, ink_t, 33.0, 0.08, 0.20)

	var cheek: Color = head_col
	cheek.a = 0.24
	_rough_line(ci, Vector2(head_x - body_r * 0.14, head_y - body_r * 0.04), Vector2(head_x - body_r * 0.04, head_y + body_r * 0.09), cheek, 1.0, ink_t, 28.0, 0.18, 0.25)
	_rough_line(ci, Vector2(head_x + body_r * 0.12, head_y - body_r * 0.07), Vector2(head_x + body_r * 0.03, head_y + body_r * 0.08), cheek, 0.9, ink_t, 29.0, 0.18, 0.25)

	var eye_a: float = 0.72 + maxf(0.0, pulse) * 0.22
	var halo: Color = soul_col
	halo.a = 0.24 * eye_a
	var eye: Color = soul_col
	eye.a = eye_a
	var eye_y: float = head_y - body_r * 0.25
	var eye_l: Vector2 = Vector2(head_x - body_r * (0.13 - turn * 0.02), eye_y - body_r * 0.01)
	var eye_r: Vector2 = Vector2(head_x + body_r * (0.11 + turn * 0.02), eye_y + body_r * 0.015)
	var near_eye_idx: int = 1 if turn >= 0.0 else 0
	var eyes: PackedVector2Array = PackedVector2Array([eye_l, eye_r])
	for i in range(eyes.size()):
		var p: Vector2 = eyes[i]
		var visibility: float = 1.0 if absf(turn) < 0.18 or i == near_eye_idx else 0.30
		halo.a = 0.24 * eye_a * visibility
		eye.a = eye_a * visibility
		ci.draw_circle(p, body_r * 0.065, halo)
		_draw_rough_circle(ci, p, body_r * 0.028, eye, Color(0, 0, 0, 0), 0.0, ink_t, 30.0 + p.x, 7, 0.16)
	var mouth_col: Color = head_col
	mouth_col.a = 0.18
	_rough_line(ci, Vector2(head_x - body_r * 0.05, head_y + body_r * 0.06), Vector2(head_x + body_r * 0.05, head_y + body_r * 0.07), mouth_col, 0.8, ink_t, 31.0, 0.12, 0.15)
