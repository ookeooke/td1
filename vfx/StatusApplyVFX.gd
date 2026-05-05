class_name StatusApplyVFX
extends Node2D

# Single ring pop the moment a status effect first attaches to an enemy.
# Color picked by caller (cyan for slow, yellow for stun). Skipped on
# refresh so a chained slow doesn't spam every tower hit — the persistent
# rotating status ring inside BaseEnemy handles "still active" feedback.

const LIFETIME: float = 0.20
const RADIUS_TO_RATIO: float = 1.5

var _color: Color = Color.WHITE
var _base_radius: float = 18.0
var _t: float = LIFETIME


static func spawn(parent: Node, pos: Vector2, base_radius: float, color: Color) -> void:
	if parent == null:
		return
	var inst := StatusApplyVFX.new()
	inst.global_position = pos
	inst._color = color
	inst._base_radius = maxf(base_radius, 12.0)
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t01: float = clampf(1.0 - (_t / LIFETIME), 0.0, 1.0)
	var r: float = _base_radius * lerpf(0.0, RADIUS_TO_RATIO, t01)
	var alpha: float = (1.0 - t01) * 0.9
	var c: Color = _color
	c.a = alpha
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, c, lerpf(4.0, 1.0, t01))
