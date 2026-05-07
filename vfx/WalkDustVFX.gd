class_name WalkDustVFX
extends Node2D

# Tiny dust puff at a unit's feet on each foot-plant. Expands and fades over
# ~0.35s. Spawned by BaseEnemy when its walk-phase counter ticks past a
# half-cycle (`theta` crosses N*PI). Side-alternated by caller so plants
# alternate left/right feet — sells walking weight transfer.

const LIFETIME: float = 0.55
const RADIUS_FROM: float = 3.0
const RADIUS_TO: float = 9.0
const OUTLINE_COLOR: Color = Color(0.30, 0.22, 0.14)

var _t: float = LIFETIME
var _color: Color = Color(0.70, 0.62, 0.48)


static func spawn(parent: Node, pos: Vector2, color: Color = Color(0.70, 0.62, 0.48)) -> void:
	if parent == null:
		return
	var inst := WalkDustVFX.new()
	inst.global_position = pos
	inst._color = color
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t01: float = clampf(1.0 - (_t / LIFETIME), 0.0, 1.0)
	var r: float = lerpf(RADIUS_FROM, RADIUS_TO, t01)
	var alpha: float = (1.0 - t01) * 0.80
	var c: Color = _color
	c.a = alpha
	draw_circle(Vector2.ZERO, r, c)
	var outline: Color = OUTLINE_COLOR
	outline.a = alpha * 0.9
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, outline, 1.5)
