extends Node2D

# Placeholder Fireball impact visual: orange expanding disc that fades
# to transparent, then queue_frees. Cheap custom _draw + Tween. No
# particles, no atlas — Phase 41 polish replaces with a real VFX scene.

const LIFETIME: float = 0.4

var _radius: float = 80.0
var _fill_alpha: float = 0.75
var _scale_t: float = 0.0


func setup(radius: float) -> void:
	_radius = radius


func _ready() -> void:
	z_index = 7
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "_scale_t", 1.0, LIFETIME)
	tween.tween_property(self, "_fill_alpha", 0.0, LIFETIME)
	tween.chain().tween_callback(queue_free)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r: float = _radius * lerpf(0.3, 1.0, _scale_t)
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.5, 0.1, _fill_alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.2, 0.0, _fill_alpha), 3.0)
