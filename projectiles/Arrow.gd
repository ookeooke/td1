extends Node2D
class_name Arrow

# Shared projectile script for every tower. Per-projectile look is selected by
# `shape` and a handful of toggles set in each .tscn (Arrow / IceShard /
# MageBolt / ArtilleryShell). Hit detection uses the homing-linear ground
# position; arc_height lifts the body visually so a shell reads as ballistic
# without breaking the on-target-arrival timing.
enum Shape { ARROW, CRYSTAL, ORB, SHELL }

const _ShellImpactScript := preload("res://vfx/ShellImpactVFX.gd")

@export var shape: Shape = Shape.ARROW
@export var speed: float = 1250.0
@export var hit_radius: float = 62.5
@export var proj_color: Color = Color(0.95, 0.85, 0.55)
@export var trail_enabled: bool = true
# Faint additive halo behind the body — circle in proj_color at low alpha.
@export var glow_enabled: bool = false
@export var glow_radius: float = 22.0
# Extra rotation applied only to the body draw (trail still aligns with
# velocity). Useful for crystals; ignored on circular shapes.
@export var spin_speed: float = 0.0  # rad/sec
# Peak vertical lift in pixels at mid-flight. 0 = straight homing line.
@export var arc_height: float = 0.0
# Ground shadow under the projectile — flattened ellipse at _ground_pos that
# scales/darkens inversely with arc lift. Reads as "this is up in 3D space"
# in 2D. Only meaningful with arc_height > 0; default off so straight-flying
# projectiles (mage, ice) don't sprout shadows. Industry-standard AAA TD
# pattern (Kingdom Rush, Bloons, PvZ).
@export var cast_shadow: bool = false

# Base shadow ellipse half-width in pixels at ground level. Half-height is
# this * 0.33 (squat 3:1 ratio = faux-isometric ground shadow).
const SHADOW_BASE_RADIUS: float = 12.0

const TRAIL_SAMPLES: int = 10
# Catmull-Rom interpolated points per recorded segment when trail_smooth is on.
# Smooths the polyline into a curved ribbon for arcing projectiles. Cheap:
# 9 segments * 4 = 36 draw_lines per smoothed projectile per frame.
const TRAIL_SMOOTH_STEPS: int = 4
var _trail: PackedVector2Array = PackedVector2Array()

# Trail color gradient. Both default to zero alpha = fall back to proj_color
# (lightened for core / darkened for edge). Set per-tscn for distinctive looks
# (mage = white core, violet edge; ice = white core, cyan edge; etc.).
@export var trail_color_core: Color = Color(0, 0, 0, 0)
@export var trail_color_edge: Color = Color(0, 0, 0, 0)
# Catmull-Rom smoothing for the trail polyline. Worth enabling on arcing
# projectiles (Arrow, ArtilleryShell) where the recorded samples form a
# parabola that reads better as a smooth ribbon than as polyline segments.
@export var trail_smooth: bool = false

var _target: Node = null
var _damage: float = 0.0
var _damage_type: int = 0
var _source: Node = null
var _status_effect = null
var _aoe_radius: float = 0.0
var _splash_pct: float = 0.5

# Linear-homing position (no arc). Hit math runs against this; the visual
# global_position is _ground_pos + arc lift.
var _ground_pos: Vector2 = Vector2.ZERO
var _start_pos: Vector2 = Vector2.ZERO
var _total_dist: float = 0.0
var _spin_offset: float = 0.0
var _time: float = 0.0
# Previous-frame visual position. Used to compute rotation from the arc
# tangent (so an arc'd arrow tilts through the parabola, not horizontally).
var _prev_global: Vector2 = Vector2.ZERO
var _has_prev: bool = false


func setup(target: Node, damage: float, damage_type: int, source: Node, status_effect = null, aoe_radius: float = 0.0, splash_pct: float = 0.5) -> void:
	_target = target
	_damage = damage
	_damage_type = damage_type
	_source = source
	_status_effect = status_effect
	_aoe_radius = aoe_radius
	_splash_pct = splash_pct
	_ground_pos = global_position
	_start_pos = global_position
	if is_instance_valid(target):
		_total_dist = _start_pos.distance_to(target.global_position)


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	_time += delta
	_spin_offset += spin_speed * delta
	var to_target: Vector2 = _target.global_position - _ground_pos
	var dist: float = to_target.length()
	if dist <= hit_radius:
		_on_hit()
		queue_free()
		return
	if trail_enabled:
		_trail.append(global_position)
		if _trail.size() > TRAIL_SAMPLES:
			_trail.remove_at(0)
	var step: float = minf(speed * delta, dist)
	_ground_pos += to_target.normalized() * step
	# Arc lift — visual only. _total_dist anchors progress to the original
	# travel distance so the lift hits zero exactly on impact.
	var arc_off: Vector2 = Vector2.ZERO
	if arc_height > 0.0 and _total_dist > 0.0:
		var t: float = clampf(_start_pos.distance_to(_ground_pos) / _total_dist, 0.0, 1.0)
		arc_off.y = -arc_height * 4.0 * t * (1.0 - t)
	global_position = _ground_pos + arc_off
	# Rotation tracks the visual trajectory tangent (frame-to-frame delta),
	# so an arc'd projectile tilts up on the way up and down on the way
	# down. First frame has no prev sample — fall back to to_target.
	if _has_prev:
		var visual_dir: Vector2 = global_position - _prev_global
		if visual_dir.length_squared() > 0.0001:
			rotation = visual_dir.angle()
		else:
			rotation = to_target.angle()
	else:
		rotation = to_target.angle()
	_prev_global = global_position
	_has_prev = true
	queue_redraw()


func _on_hit() -> void:
	var impact_pos: Vector2 = _target.global_position if is_instance_valid(_target) else _ground_pos
	var total_dealt: float = 0.0
	# Source tower may have been sold while this projectile was in flight — the
	# raw _source ref is then a freed Object, and passing it as a Node-typed
	# arg to take_damage trips Godot's type check. Resolve to null instead so
	# damage still lands; the run-stats record_damage call below already guards
	# the same way.
	var src: Node = _source if (_source != null and is_instance_valid(_source)) else null
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		total_dealt += _target.take_damage(_damage, _damage_type, src)
	if _status_effect != null and is_instance_valid(_target) and _target.has_method("apply_status_effect"):
		_target.apply_status_effect(_status_effect)
	if _aoe_radius > 0.0:
		var r2: float = _aoe_radius * _aoe_radius
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy == _target:
				continue
			if not (enemy is BaseEnemy):
				continue
			if enemy.state == BaseEnemy.State.DYING:
				continue
			if impact_pos.distance_squared_to(enemy.global_position) <= r2:
				total_dealt += enemy.take_damage(_damage * _splash_pct, _damage_type, src)
		# Splash VFX — scorch + radius ring at the impact. Visualizes the AoE
		# the player just paid for. Skipped on clean_view.
		if not VFXSpawner.clean_view:
			_ShellImpactScript.spawn(get_tree().current_scene, impact_pos, _aoe_radius)
	if total_dealt > 0.0 and _source != null and is_instance_valid(_source) and _source.has_method("record_damage"):
		_source.record_damage(total_dealt)


func _draw() -> void:
	# Compute current arc-lift fraction (0=ground, 1=apex). Used by ground
	# shadow rendering and by SHELL's descending-ember pulse. Always 0 on
	# straight-flying projectiles (no arc_height).
	var lift_t: float = 0.0
	if arc_height > 0.0:
		var arc_off_local: Vector2 = global_position - _ground_pos
		# arc_off_local.y is negative (lifted up); flip to positive 0..arc_height.
		lift_t = clampf(-arc_off_local.y / arc_height, 0.0, 1.0)

	# Ground shadow first — drawn behind trail and body. Flattened ellipse at
	# the un-lifted ground position (_ground_pos), shrinks and fades as the
	# projectile climbs. Sells the "in the air" depth illusion in 2D.
	if cast_shadow and arc_height > 0.0:
		var inv_rot_s: float = -rotation
		var shadow_scale: float = lerpf(1.0, 0.5, lift_t)
		var shadow_alpha: float = lerpf(0.40, 0.15, lift_t)
		var rx: float = SHADOW_BASE_RADIUS * shadow_scale
		var ry: float = SHADOW_BASE_RADIUS * shadow_scale * 0.33
		var pts: PackedVector2Array = PackedVector2Array()
		for i in 12:
			var ang: float = TAU * float(i) / 12.0
			var w: Vector2 = _ground_pos + Vector2(cos(ang) * rx, sin(ang) * ry)
			pts.append((w - global_position).rotated(inv_rot_s))
		draw_colored_polygon(pts, Color(0, 0, 0, shadow_alpha))

	# Trail next — drawn behind body in local frame, samples are world-space
	# so transform back via inverse rotation. Optional Catmull-Rom smoothing
	# turns the polyline into a curved ribbon for arcing shots.
	if trail_enabled and _trail.size() >= 2:
		var inv_rot: float = -rotation
		# Resolve trail colors. Zero-alpha exports fall back to proj_color
		# tinted (matches the legacy single-color trail behavior).
		var col_core: Color = trail_color_core
		if col_core.a <= 0.0:
			col_core = proj_color.lightened(0.4)
			col_core.a = 1.0
		var col_edge: Color = trail_color_edge
		if col_edge.a <= 0.0:
			col_edge = proj_color.darkened(0.2)
			col_edge.a = 1.0
		# Build the polyline of local-space points, optionally interpolated.
		var points_local: PackedVector2Array = PackedVector2Array()
		var n: int = _trail.size()
		if trail_smooth:
			for i in range(n - 1):
				var p0: Vector2 = _trail[max(i - 1, 0)]
				var p1: Vector2 = _trail[i]
				var p2: Vector2 = _trail[i + 1]
				var p3: Vector2 = _trail[min(i + 2, n - 1)]
				for s in range(TRAIL_SMOOTH_STEPS):
					var t: float = float(s) / float(TRAIL_SMOOTH_STEPS)
					var pw: Vector2 = _catmull_rom(p0, p1, p2, p3, t)
					points_local.append((pw - global_position).rotated(inv_rot))
			points_local.append((_trail[n - 1] - global_position).rotated(inv_rot))
		else:
			for pw in _trail:
				points_local.append((pw - global_position).rotated(inv_rot))
		# Per-segment color/alpha/width by position along the trail. frac = 0
		# at the tail, 1.0 at the head — alpha and width grow toward the body.
		var n_pts: int = points_local.size()
		for i in range(n_pts - 1):
			var frac: float = float(i + 1) / float(n_pts - 1)
			var col: Color = col_edge.lerp(col_core, frac)
			col.a *= frac * 0.6
			draw_line(points_local[i], points_local[i + 1], col, lerpf(3.0, 10.0, frac), true)
	# Glow halo under the body — flat alpha circle in proj_color.
	if glow_enabled:
		var glow_col: Color = proj_color
		glow_col.a = 0.25
		draw_circle(Vector2.ZERO, glow_radius, glow_col)
	# Body. Spin transforms only the body draws — trail is already laid down.
	if spin_speed != 0.0:
		draw_set_transform(Vector2.ZERO, _spin_offset, Vector2.ONE)
	match shape:
		Shape.ARROW:
			_draw_arrow_shape()
		Shape.CRYSTAL:
			_draw_crystal_shape()
		Shape.ORB:
			_draw_orb_shape()
		Shape.SHELL:
			_draw_shell_shape(lift_t)


func _draw_arrow_shape() -> void:
	# Smaller, more "real arrow" silhouette: brown wooden shaft, sharp steel
	# arrowhead with a pointy nose, dark-red feather fletching. ~42 px total
	# (down from ~58). Body colors are hardcoded — trail stays gold via the
	# trail_color_* exports on Arrow.tscn, giving a brown arrow + gold streak.
	var shaft_color: Color = Color(0.32, 0.20, 0.10)
	var head_color: Color = Color(0.55, 0.50, 0.45)
	var head_dark: Color = Color(0.25, 0.20, 0.16)
	var fletching: Color = Color(0.58, 0.20, 0.18)
	# Shaft — thinner than before to read as a stick, not a log.
	draw_line(Vector2(-16, 0), Vector2(12, 0), shaft_color, 3.0)
	# Arrowhead — long and narrow. 10 px nose × 3 px half-width = pointy.
	draw_colored_polygon(
		PackedVector2Array([Vector2(22, 0), Vector2(12, -3), Vector2(12, 3)]),
		head_color
	)
	# Tiny dark dot at the haft-to-head join — sells the metal lashing.
	draw_circle(Vector2(12, 0), 1.5, head_dark)
	# Fletching — two small feather triangles at the tail. Dark red.
	draw_colored_polygon(
		PackedVector2Array([Vector2(-16, -1), Vector2(-22, -4), Vector2(-12, -1)]),
		fletching
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-16, 1), Vector2(-22, 4), Vector2(-12, 1)]),
		fletching
	)


func _draw_crystal_shape() -> void:
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(28, 0), Vector2(0, -16), Vector2(-28, 0), Vector2(0, 16)
	])
	draw_colored_polygon(body, proj_color)
	var dark: Color = proj_color.darkened(0.4)
	draw_polyline(PackedVector2Array([
		Vector2(28, 0), Vector2(0, -16), Vector2(-28, 0), Vector2(0, 16), Vector2(28, 0)
	]), dark, 2.0, true)
	# Bright facet highlight on the upper-left edge.
	var hl: Color = Color(1.0, 1.0, 1.0, 0.6)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-22, -2), Vector2(-2, -14), Vector2(-2, -10), Vector2(-18, -1)
	]), hl)


func _draw_orb_shape() -> void:
	# Pulsing outer halo + bright core. Pulse via shared _time so multiple
	# orbs in flight don't sync-lockstep visibly (they share but it's fine).
	var pulse: float = 1.0 + 0.12 * sin(_time * 8.0)
	var outer: Color = proj_color
	outer.a = 0.45
	draw_circle(Vector2.ZERO, 18.0 * pulse, outer)
	var core: Color = proj_color.lerp(Color(1, 1, 1), 0.65)
	draw_circle(Vector2.ZERO, 9.0 * pulse, core)


func _draw_shell_shape(lift_t: float) -> void:
	var body: Color = Color(0.18, 0.16, 0.14)
	draw_circle(Vector2.ZERO, 14.0, body)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.05, 0.04, 0.03), 2.0, true)
	# Metallic highlight on upper-left.
	draw_circle(Vector2(-4, -5), 3.5, Color(0.55, 0.5, 0.45))
	# Lit fuse ember at the tail. Brightens and grows on descent (last ~40%
	# of flight) — telegraphs "incoming!" from a distance.
	var ember_boost: float = 0.0
	if lift_t < 0.4:
		ember_boost = 1.0 - (lift_t / 0.4)
	var ember_radius: float = 3.0 * (1.0 + ember_boost * 0.5)
	var ember_color: Color = proj_color.lerp(Color(1.0, 1.0, 0.7), ember_boost * 0.5)
	draw_circle(Vector2(-13, 0), ember_radius, ember_color)


# Catmull-Rom interpolation between p1 and p2, using p0 and p3 as tangent
# anchors. t ∈ [0, 1]; t=0 returns p1, t=1 returns p2. Standard centripetal
# form. Used by trail rendering when trail_smooth is enabled.
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
