extends Node2D

# Necromancer kill tell — three small green wisps drift from the dying
# enemy's position toward the hero over LIFETIME seconds, fading on
# arrival. Spawned by VFXSpawner on enemy_died when the Necromancer is
# the active hero. Self-frees on completion.
#
# Target tracking: we snapshot the hero at setup() and re-read its
# global_position each frame (the hero is moving). If the hero ref goes
# null mid-drift (death, despawn) we keep drifting toward the last known
# position so the visual completes cleanly.

const LIFETIME: float = 0.65
const WISP_COUNT: int = 3
const ARRIVAL_RADIUS: float = 14.0

var _t: float = 0.0
var _hero_ref: Node2D = null
var _target_world: Vector2 = Vector2.ZERO
var _origin_world: Vector2 = Vector2.ZERO
# Per-wisp lateral offset (perpendicular to the drift axis) and phase so
# the three wisps fan out instead of stacking on the centerline.
var _wisp_offsets: PackedFloat32Array = PackedFloat32Array()
var _wisp_phases: PackedFloat32Array = PackedFloat32Array()


func setup(hero: Node2D) -> void:
	_hero_ref = hero
	if hero != null and is_instance_valid(hero):
		_target_world = hero.global_position
	else:
		_target_world = global_position
	_origin_world = global_position


func _ready() -> void:
	z_index = 5
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in WISP_COUNT:
		_wisp_offsets.append(rng.randf_range(-9.0, 9.0))
		_wisp_phases.append(rng.randf_range(0.0, TAU))
	var tw: Tween = create_tween()
	tw.tween_property(self, "_t", 1.0, LIFETIME)
	tw.tween_callback(queue_free)
	set_process(true)


func _process(_delta: float) -> void:
	if _hero_ref != null and is_instance_valid(_hero_ref):
		_target_world = _hero_ref.global_position
	queue_redraw()


func _draw() -> void:
	# Each wisp interpolates from _origin_world to _target_world along an
	# eased curve, with a sin-shaped lateral wobble so the trail reads as
	# a wisp, not a straight line. Drawn in local space → translate by
	# (target - self.global_position) etc.
	var t: float = clampf(_t, 0.0, 1.0)
	# Snap drift to arrival when within ARRIVAL_RADIUS so wisps look like
	# they "land" on the hero instead of overshooting.
	var lerp_t: float = ease(t, 0.45)  # bias toward fast-start, slow-end
	for i in WISP_COUNT:
		var phase: float = _wisp_phases[i]
		var lateral: float = _wisp_offsets[i] * sin(t * PI + phase * 0.5)
		var arr_world: Vector2 = _origin_world.lerp(_target_world, lerp_t)
		# Perpendicular to the drift axis for the lateral wobble.
		var dir: Vector2 = _target_world - _origin_world
		var perp: Vector2 = Vector2(-dir.y, dir.x).normalized() if dir.length_squared() > 0.0001 else Vector2.UP
		var pos_world: Vector2 = arr_world + perp * lateral
		var pos_local: Vector2 = pos_world - global_position
		# Alpha: full for first 70%, fade to zero on arrival.
		var alpha: float = 1.0 if t < 0.70 else 1.0 - (t - 0.70) / 0.30
		var halo: Color = Color(0.45, 0.95, 0.55, alpha * 0.45)
		var core: Color = Color(0.75, 1.00, 0.80, alpha * 0.95)
		draw_circle(pos_local, 5.0, halo)
		draw_circle(pos_local, 2.2, core)
		# Trail dot — one short tail segment behind the wisp.
		var trail_t: float = maxf(t - 0.08, 0.0)
		var trail_world: Vector2 = _origin_world.lerp(_target_world, ease(trail_t, 0.45)) + perp * lateral
		var trail_local: Vector2 = trail_world - global_position
		draw_circle(trail_local, 1.4, Color(0.55, 0.95, 0.65, alpha * 0.55))
