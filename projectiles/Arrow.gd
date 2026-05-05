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

const TRAIL_SAMPLES: int = 5
var _trail: PackedVector2Array = PackedVector2Array()

var _target: Node = null
var _damage: float = 0.0
var _damage_type: int = 0
var _source: Node = null
var _status_effect = null
var _aoe_radius: float = 0.0

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


func setup(target: Node, damage: float, damage_type: int, source: Node, status_effect = null, aoe_radius: float = 0.0) -> void:
	_target = target
	_damage = damage
	_damage_type = damage_type
	_source = source
	_status_effect = status_effect
	_aoe_radius = aoe_radius
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
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		total_dealt += _target.take_damage(_damage, _damage_type, _source)
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
				total_dealt += enemy.take_damage(_damage * 0.5, _damage_type, _source)
		# Splash VFX — scorch + radius ring at the impact. Visualizes the AoE
		# the player just paid for. Skipped on clean_view.
		if not VFXSpawner.clean_view:
			_ShellImpactScript.spawn(get_tree().current_scene, impact_pos, _aoe_radius)
	if total_dealt > 0.0 and _source != null and is_instance_valid(_source) and _source.has_method("record_damage"):
		_source.record_damage(total_dealt)


func _draw() -> void:
	# Trail first — drawn behind everything in local frame, samples are world-
	# space so transform back via inverse rotation.
	if trail_enabled and _trail.size() >= 2:
		var inv_rot: float = -rotation
		var trail_col: Color = proj_color.darkened(0.2)
		for i in range(_trail.size() - 1):
			var a_world: Vector2 = _trail[i]
			var b_world: Vector2 = _trail[i + 1]
			var a_local: Vector2 = (a_world - global_position).rotated(inv_rot)
			var b_local: Vector2 = (b_world - global_position).rotated(inv_rot)
			var frac: float = float(i + 1) / float(TRAIL_SAMPLES)
			var col: Color = trail_col
			col.a = frac * 0.6
			draw_line(a_local, b_local, col, lerpf(4.0, 10.0, frac), true)
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
			_draw_shell_shape()


func _draw_arrow_shape() -> void:
	# Shaft + arrowhead, ~50px total length (was ~140px).
	draw_line(Vector2(-22, 0), Vector2(18, 0), proj_color.darkened(0.2), 4.0)
	draw_colored_polygon(
		PackedVector2Array([Vector2(28, 0), Vector2(9, -8), Vector2(9, 8)]),
		proj_color
	)
	# Fletching — two small feather triangles at the tail.
	var feather: Color = proj_color.lightened(0.15)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-22, -1), Vector2(-30, -6), Vector2(-16, -2)]),
		feather
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-22, 1), Vector2(-30, 6), Vector2(-16, 2)]),
		feather
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


func _draw_shell_shape() -> void:
	var body: Color = Color(0.18, 0.16, 0.14)
	draw_circle(Vector2.ZERO, 14.0, body)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.05, 0.04, 0.03), 2.0, true)
	# Metallic highlight on upper-left.
	draw_circle(Vector2(-4, -5), 3.5, Color(0.55, 0.5, 0.45))
	# Lit fuse ember at the tail, in proj_color (orange).
	draw_circle(Vector2(-13, 0), 3.0, proj_color)
