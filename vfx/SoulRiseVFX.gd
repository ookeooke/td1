extends Node2D

# Necromancer skeleton-spawn burst. Small green/purple soul wisps rising
# from the ground plus a brief dim ring at the feet. ~0.55s total, then
# queue_free. Cheap _draw + Tween, no particles.

const LIFETIME: float = 0.55
const WISP_COUNT: int = 5
const WISP_RISE: float = 28.0

var _t: float = 0.0  # 0 → 1 over LIFETIME
var _phase_offsets: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	z_index = 4
	# Stable per-instance jitter so each wisp rises at a slightly different
	# rate / lateral drift. Seeded from the spawn timestamp.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in WISP_COUNT:
		_phase_offsets.append(rng.randf_range(-0.2, 0.2))
	var tw: Tween = create_tween()
	tw.tween_property(self, "_t", 1.0, LIFETIME)
	tw.tween_callback(queue_free)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Ground ring — quick dim flash at the feet.
	var ring_t: float = clampf(_t * 2.5, 0.0, 1.0)
	var ring_alpha: float = (1.0 - ring_t) * 0.55
	if ring_alpha > 0.01:
		var r: float = lerpf(6.0, 18.0, ring_t)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(0.50, 0.95, 0.55, ring_alpha), 2.5)
	# Soft purple ground stain — sells "torn from the earth."
	var stain_alpha: float = (1.0 - _t) * 0.30
	if stain_alpha > 0.0:
		draw_circle(Vector2(0.0, 4.0), 14.0, Color(0.35, 0.10, 0.45, stain_alpha))
	# Wisps — rising green-tinted dots with trailing tails.
	for i in WISP_COUNT:
		var phase: float = float(i) / float(WISP_COUNT)
		var local_t: float = clampf(_t + _phase_offsets[i], 0.0, 1.0)
		if local_t <= 0.0 or local_t >= 1.0:
			continue
		var rise: float = ease(local_t, 0.6) * WISP_RISE
		var x_drift: float = sin((phase * TAU) + local_t * PI * 1.5) * 6.0
		var pos: Vector2 = Vector2(x_drift, -rise)
		var alpha: float = sin(local_t * PI) * 0.95
		var wisp_col: Color = Color(0.55, 1.0, 0.65, alpha)
		# Trail — three fading dots behind the head.
		for j in range(1, 4):
			var trail_t: float = clampf(local_t - float(j) * 0.06, 0.0, 1.0)
			if trail_t <= 0.0:
				continue
			var trail_rise: float = ease(trail_t, 0.6) * WISP_RISE
			var trail_x: float = sin((phase * TAU) + trail_t * PI * 1.5) * 6.0
			var trail_pos: Vector2 = Vector2(trail_x, -trail_rise)
			var trail_alpha: float = sin(trail_t * PI) * (0.5 - float(j) * 0.12)
			if trail_alpha <= 0.0:
				continue
			draw_circle(trail_pos, 2.2 - float(j) * 0.4, Color(0.45, 0.85, 0.55, trail_alpha))
		# Head — soft halo + bright core.
		var halo: Color = Color(0.40, 0.85, 0.55, alpha * 0.4)
		draw_circle(pos, 5.0, halo)
		draw_circle(pos, 2.6, wisp_col)
