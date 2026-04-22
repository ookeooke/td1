extends Node2D

# Placeholder Fireball impact visual: orange expanding disc that fades
# to transparent, then queue_frees. Cheap custom _draw + Tween. No
# particles, no atlas — Phase 41 polish replaces with a real VFX scene.
#
# Two phases: flash (LIFETIME) then scorch aftermath (AFTERMATH_DURATION)
# so the impact zone stays visible for ~1.0s total. The scorch ring is a
# translucent dark mark that fades out slowly.

const LIFETIME: float = 0.4
const AFTERMATH_DURATION: float = 0.6

var _radius: float = 200.0
var _fill_alpha: float = 0.75
var _scale_t: float = 0.0
var _aftermath_alpha: float = 0.0


func setup(radius: float) -> void:
	_radius = radius


func _ready() -> void:
	z_index = 7
	# Phase 1: flash — existing behavior (expanding disc + outline fading out).
	var flash: Tween = create_tween().set_parallel(true)
	flash.tween_property(self, "_scale_t", 1.0, LIFETIME)
	flash.tween_property(self, "_fill_alpha", 0.0, LIFETIME)
	# Phase 2 chained after the flash completes: scorch aftermath fades from
	# 0.5 → 0 over AFTERMATH_DURATION, then queue_free.
	flash.chain().tween_callback(_begin_aftermath)
	set_process(true)


func _begin_aftermath() -> void:
	_aftermath_alpha = 0.5
	var fade: Tween = create_tween()
	fade.tween_property(self, "_aftermath_alpha", 0.0, AFTERMATH_DURATION)
	fade.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Scorch aftermath sits UNDER the flash so the flash reads on top during
	# the brief overlap (won't happen with the chained tweens, but safe).
	if _aftermath_alpha > 0.0:
		var sr: float = _radius * 0.95
		draw_circle(Vector2.ZERO, sr, Color(0.2, 0.08, 0.03, _aftermath_alpha * 0.35))
		draw_arc(Vector2.ZERO, sr, 0.0, TAU, 48, Color(0.25, 0.1, 0.05, _aftermath_alpha), 8.0)
	if _fill_alpha > 0.0:
		var r: float = _radius * lerpf(0.3, 1.0, _scale_t)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.5, 0.1, _fill_alpha))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.2, 0.0, _fill_alpha), 7.5)
