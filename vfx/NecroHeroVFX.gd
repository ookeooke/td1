class_name NecroHeroVFX
extends Node2D

# One-shot hero lifecycle VFX for the Necromancer. Drawn procedurally so it
# matches the premium UnitVisualDrawer profile: rough rings, soul wisps, and
# cloak-like shadow shards.

const MODE_DEATH: int = 0
const MODE_RESPAWN: int = 1
const LIFETIME: float = 0.70
const WISP_COUNT: int = 7

var _mode: int = MODE_DEATH
var _t: float = 0.0
var _phase_offsets: PackedFloat32Array = PackedFloat32Array()


static func spawn(parent: Node, pos: Vector2, mode: int) -> void:
	if parent == null:
		return
	var inst := NecroHeroVFX.new()
	inst.global_position = pos
	inst._mode = mode
	parent.add_child(inst)


func _ready() -> void:
	z_index = 8
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in WISP_COUNT:
		_phase_offsets.append(rng.randf_range(-0.12, 0.12))
	var tw: Tween = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "_t", 1.0, LIFETIME)
	tw.tween_callback(queue_free)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var soul: Color = Color(0.58, 1.0, 0.68, 1.0)
	var violet: Color = Color(0.56, 0.22, 0.82, 1.0)
	var fade: float = 1.0 - _t
	if _mode == MODE_RESPAWN:
		_draw_respawn(soul, violet, fade)
	else:
		_draw_death(soul, violet, fade)


func _draw_death(soul: Color, violet: Color, fade: float) -> void:
	var ring_col: Color = soul
	ring_col.a = fade * 0.58
	draw_arc(Vector2.ZERO, lerpf(12.0, 58.0, _t), 0.0, TAU, 32, ring_col, lerpf(5.0, 1.0, _t), true)

	var shadow: Color = violet
	shadow.a = fade * 0.26
	var collapse_y: float = lerpf(-22.0, 18.0, _t)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-28.0, collapse_y - 18.0),
		Vector2(24.0, collapse_y - 14.0),
		Vector2(20.0, collapse_y + 22.0),
		Vector2(4.0, collapse_y + 34.0),
		Vector2(-12.0, collapse_y + 24.0),
		Vector2(-34.0, collapse_y + 18.0),
	]), shadow)

	for i in WISP_COUNT:
		var phase: float = float(i) / float(WISP_COUNT)
		var local_t: float = clampf(_t + _phase_offsets[i], 0.0, 1.0)
		var angle: float = phase * TAU + local_t * 1.2
		var rise: float = ease(local_t, 0.55) * 70.0
		var spread: float = lerpf(8.0, 36.0, local_t)
		var pos: Vector2 = Vector2(cos(angle) * spread, -rise + sin(angle) * 8.0)
		var a: float = sin(local_t * PI) * 0.82
		_draw_wisp(pos, soul, a)


func _draw_respawn(soul: Color, violet: Color, _fade: float) -> void:
	var build: float = ease(_t, 0.55)
	var ring_col: Color = soul
	ring_col.a = sin(_t * PI) * 0.68
	draw_arc(Vector2.ZERO, lerpf(64.0, 18.0, build), 0.0, TAU, 36, ring_col, lerpf(1.0, 4.0, build), true)

	var stain: Color = violet
	stain.a = sin(_t * PI) * 0.22
	draw_circle(Vector2(0.0, 10.0), lerpf(34.0, 18.0, build), stain)

	for i in WISP_COUNT:
		var phase: float = float(i) / float(WISP_COUNT)
		var local_t: float = clampf(_t + _phase_offsets[i], 0.0, 1.0)
		var angle: float = phase * TAU - local_t * 2.0
		var pull: float = 1.0 - ease(local_t, 0.65)
		var pos: Vector2 = Vector2(cos(angle) * 45.0 * pull, -54.0 * pull + sin(angle) * 10.0)
		var a: float = sin(local_t * PI) * 0.78
		_draw_wisp(pos, soul, a)

	var ignite: Color = soul
	ignite.a = maxf(0.0, (_t - 0.48) / 0.52) * 0.75
	draw_circle(Vector2(-5.0, -34.0), 5.0, ignite)
	draw_circle(Vector2(5.0, -33.0), 4.0, ignite)


func _draw_wisp(pos: Vector2, color: Color, alpha: float) -> void:
	if alpha <= 0.01:
		return
	var halo: Color = color
	halo.a = alpha * 0.28
	var core: Color = color
	core.a = alpha
	draw_circle(pos, 6.0, halo)
	draw_circle(pos, 2.5, core)
