extends Node2D
class_name Arrow

# Shared projectile script for every tower. Per-projectile look is selected by
# `shape` and a handful of toggles set in each .tscn (Arrow / IceShard /
# MageBolt / ArtilleryShell). Hit detection uses the homing-linear ground
# position; arc_height lifts the body visually so a shell reads as ballistic
# without breaking the on-target-arrival timing.
enum Shape { ARROW, CRYSTAL, ORB, SHELL, HERO_ARROW, ARCANE_BOLT, NECRO_BOLT }

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
# Optional visual-only wandering. Hit math still follows _ground_pos, so the
# projectile can snake upward/sideways and still land cleanly on the target.
@export var flight_wander_amplitude: float = 0.0
@export var flight_wander_vertical: float = 0.0
@export var flight_wander_frequency: float = 1.0
@export_range(0.0, 1.0, 0.05) var flight_wander_randomness: float = 0.0
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
@export_range(0.0, 1.0, 0.05) var trail_width_jitter: float = 0.0
@export_range(0.0, 1.0, 0.05) var trail_alpha_jitter: float = 0.0
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
var _wander_phase_a: float = 0.0
var _wander_phase_b: float = 0.0
var _wander_freq_a: float = 1.0
var _wander_freq_b: float = 1.0
var _wander_side: float = 1.0
var _trail_width_mult: float = 1.0
var _trail_alpha_mult: float = 1.0


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
	_randomize_flight_wander()
	_randomize_trail_variation()
	if is_instance_valid(target):
		_total_dist = _start_pos.distance_to(target.global_position)
		if shape == Shape.NECRO_BOLT and not VFXSpawner.clean_view:
			_spawn_necro_launch_vfx(target.global_position)


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
	# Arc/wander are visual only. _total_dist anchors progress to the original
	# travel distance so offsets hit zero exactly on impact.
	var progress: float = 0.0
	if _total_dist > 0.0:
		progress = clampf(_start_pos.distance_to(_ground_pos) / _total_dist, 0.0, 1.0)
	var arc_off: Vector2 = Vector2.ZERO
	if arc_height > 0.0 and _total_dist > 0.0:
		arc_off.y = -arc_height * 4.0 * progress * (1.0 - progress)
	var wander_off: Vector2 = _flight_wander_offset(progress, to_target)
	global_position = _ground_pos + arc_off + wander_off
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


func _randomize_flight_wander() -> void:
	var r: float = clampf(flight_wander_randomness, 0.0, 1.0)
	_wander_phase_a = randf_range(0.0, TAU)
	_wander_phase_b = randf_range(0.0, TAU)
	_wander_side = -1.0 if randf() < 0.5 else 1.0
	_wander_freq_a = maxf(0.05, flight_wander_frequency * randf_range(1.0 - 0.28 * r, 1.0 + 0.34 * r))
	_wander_freq_b = maxf(0.05, flight_wander_frequency * randf_range(0.62 - 0.15 * r, 0.90 + 0.20 * r))


func _randomize_trail_variation() -> void:
	var w: float = clampf(trail_width_jitter, 0.0, 1.0)
	var a: float = clampf(trail_alpha_jitter, 0.0, 1.0)
	_trail_width_mult = randf_range(1.0 - 0.35 * w, 1.0 + 0.45 * w)
	_trail_alpha_mult = randf_range(1.0 - 0.28 * a, 1.0 + 0.35 * a)


func _spawn_necro_launch_vfx(target_pos: Vector2) -> void:
	var parent: Node = get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		return
	var vfx := _NecroLaunchVFX.new()
	vfx.global_position = global_position
	vfx._aim_angle = (target_pos - global_position).angle()
	vfx._color = proj_color
	parent.add_child(vfx)


func _flight_wander_offset(progress: float, to_target: Vector2) -> Vector2:
	if flight_wander_amplitude <= 0.0 and flight_wander_vertical <= 0.0:
		return Vector2.ZERO
	var proximity_fade: float = clampf((to_target.length() - hit_radius) / maxf(hit_radius * 3.0, 1.0), 0.0, 1.0)
	var fade: float = sin(clampf(progress, 0.0, 1.0) * PI) * proximity_fade
	if fade <= 0.0:
		return Vector2.ZERO
	var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT
	var side: Vector2 = Vector2(-dir.y, dir.x) * _wander_side
	var p: float = clampf(progress, 0.0, 1.0) * TAU
	var side_wave: float = (
		sin(p * _wander_freq_a + _wander_phase_a) * 0.72
		+ sin(p * (_wander_freq_a * 2.15) + _wander_phase_b) * 0.28
	)
	var vertical_wave: float = sin(p * _wander_freq_b + _wander_phase_b)
	var off: Vector2 = (
		side * side_wave * flight_wander_amplitude * fade
		+ Vector2(0.0, vertical_wave * flight_wander_vertical * fade)
	)
	if shape == Shape.NECRO_BOLT:
		var surge: float = sin(p * 2.2 + _wander_phase_a * 0.7) * 2.0 * fade
		off += dir * surge
	return off


func _on_hit() -> void:
	var impact_pos: Vector2 = _target.global_position if is_instance_valid(_target) else _ground_pos
	var total_dealt: float = 0.0
	# Source tower may have been sold while this projectile was in flight — the
	# raw _source ref is then a freed Object, and passing it as a Node-typed
	# arg to take_damage trips Godot's type check. Resolve to null instead so
	# damage still lands; the run-stats record_damage call below already guards
	# the same way.
	var src: Node = _source if (_source != null and is_instance_valid(_source)) else null
	# Capture the primary target's pre-hit state so we can tell whether THIS
	# arrow's hit transitioned it into DYING (the kill credit). Combat
	# Blocking Doctrine Phase 7 — projectile ON_KILL must fire on impact, not
	# at launch, so passives like lifesteal score off real arrival kills.
	var primary_target: Node = _target if is_instance_valid(_target) else null
	var primary_was_dying: bool = primary_target != null and "state" in primary_target and primary_target.state == BaseEnemy.State.DYING
	var primary_dealt: float = 0.0
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		primary_dealt = _target.take_damage(_damage, _damage_type, src)
		total_dealt += primary_dealt
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
	# Per-shape impact polish on the primary target. HitSparkVFX is already
	# routed via EventBus.hit_landed for every hit — these add an element-
	# specific flourish on top (frost shatter, arcane ring) so each projectile
	# class has a distinct hit signature, not just a different in-flight look.
	if not VFXSpawner.clean_view:
		_spawn_impact_vfx(impact_pos)
	if total_dealt > 0.0 and _source != null and is_instance_valid(_source) and _source.has_method("record_damage"):
		_source.record_damage(total_dealt)
	# Combat Blocking Doctrine Phase 7 — fire the source's on-impact hook so
	# ON_HIT_DEALT / ON_KILL ability passives (lifesteal, mark-on-kill) score
	# off the real impact, not the launch frame. Hero implements this; tower
	# does not (no AbilityHost), so the has_method check no-ops cleanly.
	if src != null and src.has_method("on_projectile_impact") and primary_target != null:
		var killed: bool = (not primary_was_dying) \
				and "state" in primary_target \
				and primary_target.state == BaseEnemy.State.DYING
		src.on_projectile_impact(primary_target, primary_dealt, killed)


func _spawn_impact_vfx(impact_pos: Vector2) -> void:
	var parent: Node = get_tree().current_scene
	if parent == null:
		return
	# Shift the spawn down to the target's feet so the impact reads as a
	# ground splat under the enemy, not a halo around its body. Flying
	# enemies don't touch the ground — keep the impact at body center for
	# them. z_index = -1 on each spawned VFX so the body sprite draws on top.
	var ground_pos: Vector2 = impact_pos
	if is_instance_valid(_target) and "data" in _target and _target.data != null and _target.data.visual != null:
		var on_ground: bool = true
		if "is_flying" in _target.data:
			on_ground = not _target.data.is_flying
		if on_ground:
			ground_pos.y += _target.data.visual.radius * 0.95
	match shape:
		Shape.CRYSTAL:
			# Frost shatter — 6 outward shard streaks, cyan-white, very brief.
			var burst := _IceShatterVFX.new()
			burst.global_position = ground_pos
			burst.z_index = -1
			burst._color = proj_color
			parent.add_child(burst)
		Shape.NECRO_BOLT:
			var soul := _NecroImpactVFX.new()
			soul.global_position = ground_pos
			soul.z_index = -1
			soul._color = proj_color
			parent.add_child(soul)
		Shape.ORB:
			# Arcane ring — single expanding ring in proj_color.
			var ring := _ArcaneRingVFX.new()
			ring.global_position = ground_pos
			ring.z_index = -1
			ring._color = proj_color
			parent.add_child(ring)
		Shape.ARCANE_BOLT:
			# Bigger arcane burst — a ring + 5 radial rune flashes. Slightly
			# more theatrical than the tower MageBolt ring because the hero
			# shot fires slower and is "the" attack the player is watching.
			var ring2 := _ArcaneRingVFX.new()
			ring2.global_position = ground_pos
			ring2.z_index = -1
			ring2._color = proj_color
			parent.add_child(ring2)
			var burst := _ArcaneBurstVFX.new()
			burst.global_position = ground_pos
			burst.z_index = -1
			burst._color = proj_color
			parent.add_child(burst)


# Tiny inner VFX classes — kept here so the shape→effect dispatch is local
# to Arrow.gd and we don't fan out a new .gd per impact variant.
class _NecroLaunchVFX extends Node2D:
	const LIFE: float = 0.22
	var _t: float = LIFE
	var _color: Color = Color(0.55, 0.18, 0.75)
	var _aim_angle: float = 0.0
	var _spokes: Array = []
	var _spoke_reach: Array = []
	var _wisp_angles: Array = []
	func _ready() -> void:
		for i in 4:
			_spokes.append(randf_range(-0.62, 0.62))
			_spoke_reach.append(randf_range(0.85, 1.12))
		for i in 3:
			_wisp_angles.append(randf_range(0.0, TAU))
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(1.0 - _t / LIFE, 0.0, 1.0)
		var alpha: float = 1.0 - k
		var aim: Vector2 = Vector2.from_angle(_aim_angle)
		var side: Vector2 = Vector2.from_angle(_aim_angle + PI * 0.5)
		var halo: Color = _color
		halo.a = alpha * 0.30
		draw_circle(Vector2.ZERO, lerpf(11.0, 4.0, k), halo)
		var rune: Color = _color.lerp(Color(0.72, 1.0, 0.78), 0.32)
		rune.a = alpha * 0.34
		draw_arc(Vector2.ZERO, lerpf(13.0, 4.0, k), _aim_angle - PI * 0.82, _aim_angle + PI * 0.82, 18, rune, lerpf(1.3, 0.45, k), false)
		draw_arc(Vector2.ZERO, lerpf(8.0, 2.0, k), _aim_angle + PI * 0.20, _aim_angle + PI * 1.55, 10, rune, lerpf(0.9, 0.35, k), false)
		var core: Color = Color(0.92, 0.76, 1.0, alpha * 0.62)
		draw_circle(aim * lerpf(-2.0, 5.0, k), lerpf(4.0, 1.4, k), core)
		for i in range(_wisp_angles.size()):
			var a: float = float(_wisp_angles[i]) + k * 2.6
			var pull: float = 1.0 - k
			var p: Vector2 = Vector2(cos(a), sin(a) * 0.55) * lerpf(13.0, 3.0, k)
			p += aim * k * 5.0 + side * sin(k * PI + float(i)) * pull
			var wc: Color = Color(0.68, 1.0, 0.70, alpha * 0.32)
			draw_circle(p, lerpf(1.6, 0.7, k), wc)
		for i in range(_spokes.size()):
			var off: float = float(_spokes[i])
			var dir: Vector2 = Vector2.from_angle(_aim_angle + float(off))
			var reach: float = lerpf(4.0, 22.0, k) * float(_spoke_reach[i])
			var flame: Color = _color.lerp(Color(0.72, 1.0, 0.78), 0.18)
			flame.a = alpha * 0.38
			draw_line(dir * 3.0, dir * reach, flame, lerpf(2.0, 0.6, k), false)


class _NecroImpactVFX extends Node2D:
	const LIFE: float = 0.34
	var _t: float = LIFE
	var _color: Color = Color(0.55, 0.18, 0.75)
	var _angles: Array = []
	func _ready() -> void:
		var base: float = randf_range(0.0, TAU)
		for i in 7:
			_angles.append(base + TAU * float(i) / 7.0 + randf_range(-0.18, 0.18))
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(1.0 - _t / LIFE, 0.0, 1.0)
		var alpha: float = 1.0 - k
		var smoke: Color = Color(0.06, 0.02, 0.10, alpha * 0.70)
		draw_circle(Vector2.ZERO, lerpf(10.0, 28.0, k), smoke)
		var ring: Color = _color.lerp(Color(0.62, 1.0, 0.70), 0.25)
		ring.a = alpha * 0.82
		draw_arc(Vector2.ZERO, lerpf(5.0, 31.0, k), 0.0, TAU, 24, ring, lerpf(4.0, 1.0, k), false)
		for a in _angles:
			var dir: Vector2 = Vector2.from_angle(float(a))
			var c: Color = _color.lerp(Color(0.82, 1.0, 0.86), 0.38)
			c.a = alpha * 0.74
			draw_line(dir * 3.0, dir * lerpf(10.0, 38.0, k), c, lerpf(3.0, 0.8, k), false)
		var skull: Color = Color(0.85, 1.0, 0.80, alpha * 0.55)
		draw_circle(Vector2(-3.0, -2.0), lerpf(2.6, 1.0, k), skull)
		draw_circle(Vector2(3.0, -2.0), lerpf(2.6, 1.0, k), skull)
		draw_line(Vector2(-4.0, 4.0), Vector2(4.0, 4.0), skull, lerpf(1.6, 0.5, k), false)


class _IceShatterVFX extends Node2D:
	const LIFE: float = 0.22
	var _t: float = LIFE
	var _color: Color = Color(0.55, 0.85, 1.0)
	var _angles: Array = []
	func _ready() -> void:
		for i in 6:
			_angles.append(randf_range(0.0, TAU))
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(1.0 - _t / LIFE, 0.0, 1.0)
		var alpha: float = 1.0 - k
		var reach: float = lerpf(6.0, 26.0, k)
		var c: Color = _color.lerp(Color(1, 1, 1), 0.4)
		c.a = alpha
		for a in _angles:
			var dir: Vector2 = Vector2.from_angle(float(a))
			draw_line(dir * 3.0, dir * reach, c, 2.0, false)
		# Center frost puff.
		var puff: Color = _color
		puff.a = alpha * 0.5
		draw_circle(Vector2.ZERO, lerpf(4.0, 10.0, k), puff)


class _ArcaneBurstVFX extends Node2D:
	const LIFE: float = 0.32
	var _t: float = LIFE
	var _color: Color = Color(0.6, 0.45, 1.0)
	var _angles: Array = []
	func _ready() -> void:
		# 5 rune flashes radiating outward at evenly-distributed angles + a
		# random rotation so two consecutive impacts don't look identical.
		var base: float = randf_range(0.0, TAU)
		for i in 5:
			_angles.append(base + TAU * float(i) / 5.0)
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(1.0 - _t / LIFE, 0.0, 1.0)
		var alpha: float = 1.0 - k
		# Central white flash collapses to nothing.
		var flash: Color = Color(1, 1, 1, alpha * 0.85)
		draw_circle(Vector2.ZERO, lerpf(12.0, 2.0, k), flash)
		# Rune streaks — thick at the head, fading to a point.
		var reach: float = lerpf(8.0, 32.0, k)
		var c: Color = _color.lerp(Color(1, 1, 1), 0.4)
		c.a = alpha
		for a in _angles:
			var dir: Vector2 = Vector2.from_angle(float(a))
			draw_line(dir * 4.0, dir * reach, c, lerpf(3.5, 1.0, k), false)


class _ArcaneRingVFX extends Node2D:
	const LIFE: float = 0.26
	var _t: float = LIFE
	var _color: Color = Color(0.6, 0.45, 1.0)
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(1.0 - _t / LIFE, 0.0, 1.0)
		var r: float = lerpf(4.0, 30.0, k)
		var alpha: float = (1.0 - k) * 0.9
		var ring: Color = _color
		ring.a = alpha
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, ring, lerpf(4.0, 1.0, k), false)
		# Inner glow flash, white core.
		var core: Color = _color.lerp(Color(1, 1, 1), 0.6)
		core.a = alpha * 0.7
		draw_circle(Vector2.ZERO, lerpf(6.0, 2.0, k), core)


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
		if shape == Shape.NECRO_BOLT:
			_draw_necro_trail_underlay(points_local)
		# Per-segment color/alpha/width by position along the trail. frac = 0
		# at the tail, 1.0 at the head — alpha and width grow toward the body.
		var n_pts: int = points_local.size()
		for i in range(n_pts - 1):
			var frac: float = float(i + 1) / float(n_pts - 1)
			var col: Color = col_edge.lerp(col_core, frac)
			col.a *= frac * 0.6 * _trail_alpha_mult
			draw_line(points_local[i], points_local[i + 1], col, lerpf(3.0, 10.0, frac) * _trail_width_mult, false)
		if shape == Shape.NECRO_BOLT:
			_draw_necro_trail_overlay(points_local)
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
		Shape.HERO_ARROW:
			_draw_hero_arrow_shape()
		Shape.ARCANE_BOLT:
			_draw_arcane_bolt_shape()
		Shape.NECRO_BOLT:
			_draw_necro_bolt_shape()


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


func _draw_hero_arrow_shape() -> void:
	# Elven hero arrow — lighter ash shaft, brighter steel head, green
	# fletching, faint warm glow. Reads as "magical / hero-fired" next to
	# the plain brown tower arrow without changing silhouette enough to
	# break the language of "this is an arrow." ~46 px total.
	var shaft_color: Color = Color(0.82, 0.70, 0.48)
	var head_color: Color = Color(0.85, 0.88, 0.92)
	var head_dark: Color = Color(0.30, 0.32, 0.36)
	var fletching: Color = Color(0.30, 0.75, 0.40)
	var fletching_dark: Color = Color(0.18, 0.45, 0.22)
	# Faint warm halo behind the body — sells "enchanted arrow."
	draw_circle(Vector2(0, 0), 14.0, Color(1.0, 0.92, 0.55, 0.18))
	# Shaft — pale ash, slightly thinner than the tower arrow.
	draw_line(Vector2(-18, 0), Vector2(13, 0), shaft_color, 2.5)
	# Arrowhead — long bright steel.
	draw_colored_polygon(
		PackedVector2Array([Vector2(24, 0), Vector2(13, -3), Vector2(13, 3)]),
		head_color
	)
	# Head edge highlight.
	draw_line(Vector2(24, 0), Vector2(13, -3), Color(1.0, 1.0, 1.0, 0.7), 1.0, false)
	# Tiny dark binding at haft-to-head join.
	draw_circle(Vector2(13, 0), 1.5, head_dark)
	# Fletching — green leaf-feather pair, with a darker inner stripe so it
	# reads as layered feathers, not flat triangles.
	draw_colored_polygon(
		PackedVector2Array([Vector2(-18, -1), Vector2(-25, -5), Vector2(-12, -1)]),
		fletching
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-18, 1), Vector2(-25, 5), Vector2(-12, 1)]),
		fletching
	)
	draw_line(Vector2(-18, -1), Vector2(-24, -3), fletching_dark, 1.0, false)
	draw_line(Vector2(-18, 1), Vector2(-24, 3), fletching_dark, 1.0, false)


func _draw_arcane_bolt_shape() -> void:
	# Wand-fired arcane bolt — distinct from soft round ORB users. Reads as a
	# charged, directional spell: a faceted shard with a bright white core,
	# cyan crackle, and a few disciplined rune sparks.
	# Mage basic attacks now use this as a shard: sharp silhouette first,
	# tiny rune sparks second.
	var t: float = _time * 7.5
	var pulse: float = 1.0 + sin(t) * 0.055
	# Outer halo — proj_color, soft.
	var halo: Color = proj_color
	halo.a = 0.22
	draw_circle(Vector2.ZERO, 15.0 * pulse, halo)
	# Faceted energy shard — diamond-ish, lit toward the front.
	var rim: Color = Color(0.42, 0.28, 1.0, 0.88)
	var shard: PackedVector2Array = PackedVector2Array([
		Vector2(20.0, 0.0),
		Vector2(6.0, -6.8),
		Vector2(-10.0, -4.0),
		Vector2(-18.0, 0.0),
		Vector2(-10.0, 4.0),
		Vector2(6.0, 6.8),
	])
	draw_colored_polygon(shard, rim)
	var body: Color = proj_color.lerp(Color(1.0, 1.0, 1.0), 0.42)
	var inner: PackedVector2Array = PackedVector2Array([
		Vector2(17.0, 0.0),
		Vector2(4.0, -4.8),
		Vector2(-9.0, -2.4),
		Vector2(-13.0, 0.0),
		Vector2(-9.0, 2.4),
		Vector2(4.0, 4.8),
	])
	draw_colored_polygon(inner, body)
	# Bright core — slim, brighter near the tip.
	var core: PackedVector2Array = PackedVector2Array([
		Vector2(16.5, 0.0),
		Vector2(0.5, -1.7),
		Vector2(-10.5, 0.0),
		Vector2(0.5, 1.7),
	])
	draw_colored_polygon(core, Color(1.0, 1.0, 1.0, 0.95))
	var highlight: Color = Color(1.0, 1.0, 1.0, 0.62)
	draw_line(Vector2(17.0, 0.0), Vector2(4.0, -4.8), highlight, 1.0, false)
	draw_line(Vector2(4.0, -4.8), Vector2(-9.0, -2.4), Color(0.72, 0.96, 1.0, 0.42), 0.8, false)
	# Crackle — short rune lines fanning back, alpha pulsing.
	var crackle: Color = proj_color.lerp(Color(1, 1, 1), 0.6)
	crackle.a = 0.42 + 0.22 * maxf(0.0, sin(t * 1.4))
	draw_line(Vector2(-10.0, -3.0), Vector2(-19.0, -6.0 + sin(t) * 1.2), crackle, 1.0, false)
	draw_line(Vector2(-10.0, 3.0), Vector2(-19.0, 6.0 + cos(t * 0.8) * 1.2), crackle, 1.0, false)
	# Tiny gold sparks give Mage a disciplined arcane accent.
	var gold: Color = Color(1.0, 0.86, 0.34, 0.52)
	for i in 3:
		var a: float = t * (0.55 + float(i) * 0.12) + float(i) * TAU / 3.0
		var p: Vector2 = Vector2(-5.0 + cos(a) * 6.5, sin(a) * 3.2)
		draw_circle(p, 1.0 if i == 0 else 0.75, gold)


func _draw_necro_bolt_shape() -> void:
	# Soul flame bolt: green soul core inside a smoky violet shell. It keeps a
	# forward point for direction readability, but the flickering skull/eye
	# hints make it read as "alive" rather than engineered magic.
	var t: float = _time * 9.0
	var pulse: float = 1.0 + sin(t) * 0.10
	var dark_core: Color = Color(0.05, 0.00, 0.08, 0.94)
	var soul: Color = proj_color.lerp(Color(0.70, 1.0, 0.74), 0.34)
	var smoke: Color = Color(0.06, 0.015, 0.10, 0.22)
	var halo: Color = soul
	halo.a = 0.16
	draw_circle(Vector2.ZERO, 13.5 * pulse, halo)
	draw_colored_polygon(PackedVector2Array([
		Vector2(10.5, -6.0),
		Vector2(-1.5, -11.0 - sin(t * 0.8) * 1.2),
		Vector2(-16.0, -5.6 + cos(t * 0.7) * 1.2),
		Vector2(-12.5, 6.2 + sin(t * 0.9) * 1.2),
		Vector2(0.0, 10.5 + cos(t * 0.6)),
		Vector2(12.5, 4.2),
	]), smoke)
	var flame: PackedVector2Array = PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(5.2, -6.0 - sin(t * 0.7)),
		Vector2(-6.0, -3.8 + cos(t * 1.1)),
		Vector2(-15.0, -7.5 + sin(t * 0.9) * 1.4),
		Vector2(-10.5, 0.0),
		Vector2(-16.0, 6.8 + cos(t * 0.8) * 1.2),
		Vector2(-3.8, 4.6 - sin(t * 1.3)),
		Vector2(6.0, 5.2 + cos(t) * 0.8),
	])
	draw_colored_polygon(flame, soul)
	var crescent: Color = Color(0.86, 0.80, 0.68, 0.72)
	draw_arc(Vector2(5.8, 0.4), 7.0 + sin(t * 0.6) * 0.5, deg_to_rad(-72.0), deg_to_rad(68.0), 10, crescent, 1.3, true)
	var inner: PackedVector2Array = PackedVector2Array([
		Vector2(10.0, 0.0),
		Vector2(1.5, -2.5),
		Vector2(-7.0, -1.5),
		Vector2(-10.5, 0.0),
		Vector2(-7.0, 1.8),
		Vector2(1.5, 2.5),
	])
	draw_colored_polygon(inner, dark_core)
	var eye_col: Color = Color(0.84, 1.0, 0.78, 0.46 + 0.16 * maxf(0.0, sin(t * 1.4)))
	draw_circle(Vector2(2.0, -1.4), 1.45, eye_col)
	draw_circle(Vector2(2.2, 1.5), 1.15, eye_col)
	var skull_jaw: Color = Color(0.84, 1.0, 0.78, 0.28)
	draw_line(Vector2(-2.0, 3.2), Vector2(3.3, 3.0 + sin(t * 1.7) * 0.6), skull_jaw, 0.8, false)
	var lick: Color = proj_color.lerp(Color(1.0, 1.0, 0.9), 0.40)
	lick.a = 0.42 + sin(t * 1.3) * 0.08
	draw_line(Vector2(-8.5, -1.4), Vector2(-17.5, -3.4 + sin(t) * 2.0), lick, 1.0, false)
	draw_line(Vector2(-8.0, 2.1), Vector2(-17.0, 4.0 + cos(t * 0.8) * 1.6), lick, 0.8, false)
	var mote_col: Color = Color(0.68, 1.0, 0.70, 0.35)
	for i in 2:
		var a: float = t * (0.7 + float(i) * 0.11) + float(i) * TAU / 3.0
		var p: Vector2 = Vector2(-6.0 + cos(a) * 5.5, sin(a) * 3.0)
		draw_circle(p, 1.2 if i == 0 else 0.9, mote_col)


func _draw_necro_trail_underlay(points_local: PackedVector2Array) -> void:
	var n: int = points_local.size()
	if n < 2:
		return
	for i in range(n - 1):
		var frac: float = float(i + 1) / float(n - 1)
		var smoke: Color = Color(0.025, 0.0, 0.045, 0.07 * frac * _trail_alpha_mult)
		draw_line(points_local[i], points_local[i + 1], smoke, lerpf(5.0, 9.0, frac) * _trail_width_mult, false)


func _draw_necro_trail_overlay(points_local: PackedVector2Array) -> void:
	var n: int = points_local.size()
	if n < 2:
		return
	var thread: Color = Color(0.66, 1.0, 0.68, 0.32 * _trail_alpha_mult)
	for i in range(n - 1):
		var frac: float = float(i + 1) / float(n - 1)
		var col: Color = thread
		col.a *= frac
		draw_line(points_local[i], points_local[i + 1], col, lerpf(0.5, 1.1, frac), false)
	var mote_count: int = 2 if n >= 4 else 1
	for j in mote_count:
		var idx: int = clampi(n - 2 - j * 2, 1, n - 1)
		var p: Vector2 = points_local[idx]
		var a: float = _time * 4.3 + float(j) * 1.7
		var drift: Vector2 = Vector2(cos(a), sin(a * 0.7)) * (1.1 + float(j) * 0.4)
		var mote: Color = Color(0.74, 1.0, 0.72, 0.16 * (1.0 - float(j) * 0.15))
		draw_circle(p + drift, 0.8 + float(j % 2) * 0.4, mote)


func _draw_crystal_shape() -> void:
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(28, 0), Vector2(0, -16), Vector2(-28, 0), Vector2(0, 16)
	])
	draw_colored_polygon(body, proj_color)
	var dark: Color = proj_color.darkened(0.4)
	draw_polyline(PackedVector2Array([
		Vector2(28, 0), Vector2(0, -16), Vector2(-28, 0), Vector2(0, 16), Vector2(28, 0)
	]), dark, 2.0, false)
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
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.05, 0.04, 0.03), 2.0, false)
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
