extends Node2D

# Necromancer Soul Nova impact visual. Expanding violet shockwave plus
# 8 outward-shooting soul wisps with a brief inner core flash. ~0.7s
# total. Mirrors the FireballVFX pattern (Tween-driven scalar progress,
# custom _draw, queue_free on end).

const LIFETIME: float = 0.55
const AFTERMATH: float = 0.25
const WISP_COUNT: int = 8

var _radius: float = 140.0
var _ring_t: float = 0.0
var _ring_alpha: float = 1.0
var _core_alpha: float = 1.0
var _aftermath_alpha: float = 0.0


func setup(radius: float) -> void:
	_radius = radius


func _ready() -> void:
	z_index = 7
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "_ring_t", 1.0, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_ring_alpha", 0.0, LIFETIME)
	tw.tween_property(self, "_core_alpha", 0.0, LIFETIME * 0.45)
	tw.chain().tween_callback(_begin_aftermath)
	set_process(true)


func _begin_aftermath() -> void:
	_aftermath_alpha = 0.35
	var fade: Tween = create_tween()
	fade.tween_property(self, "_aftermath_alpha", 0.0, AFTERMATH)
	fade.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Aftermath wash (drawn first so the ring reads on top during overlap).
	if _aftermath_alpha > 0.0:
		var ar: float = _radius * 0.95
		draw_circle(Vector2.ZERO, ar, Color(0.20, 0.05, 0.30, _aftermath_alpha * 0.45))
	# Inner core flash — bright lavender disc, only for the first ~45% of life.
	if _core_alpha > 0.0:
		var cr: float = _radius * lerpf(0.15, 0.55, _ring_t)
		draw_circle(Vector2.ZERO, cr, Color(0.85, 0.55, 1.0, _core_alpha * 0.6))
	# Main shockwave ring.
	if _ring_alpha > 0.0:
		var r: float = _radius * lerpf(0.2, 1.0, _ring_t)
		var w_outer: float = lerpf(9.0, 3.0, _ring_t)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.78, 0.32, 0.95, _ring_alpha), w_outer)
		# Inner companion ring for thickness without overdraw.
		var r_inner: float = r * 0.88
		draw_arc(Vector2.ZERO, r_inner, 0.0, TAU, 36, Color(0.92, 0.70, 1.0, _ring_alpha * 0.55), 2.5)
		# Soul wisps — short outward dashes spinning slightly with progress.
		var spin: float = _ring_t * 0.6
		var wisp_in: float = r * 0.82
		var wisp_out: float = r * 1.06
		for i in WISP_COUNT:
			var a: float = TAU * float(i) / float(WISP_COUNT) + spin
			var dir: Vector2 = Vector2(cos(a), sin(a))
			var col: Color = Color(0.95, 0.80, 1.0, _ring_alpha * 0.75)
			draw_line(dir * wisp_in, dir * wisp_out, col, 2.5, false)
