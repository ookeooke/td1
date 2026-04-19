class_name SkillCastFlare
extends Node2D

# Expanding ring drawn at the caster's feet the instant a skill is used.
# Element color is picked by VFXSpawner from a small skill-name → color map.

const LIFETIME: float = 0.18
const RADIUS_FROM: float = 0.0
const RADIUS_TO: float = 60.0
const WIDTH_FROM: float = 6.0
const WIDTH_TO: float = 1.0

var _color: Color = Color(1.0, 0.9, 0.3)
var _t: float = LIFETIME


static func spawn(parent: Node, pos: Vector2, color: Color = Color(1.0, 0.9, 0.3)) -> void:
	if parent == null:
		return
	var inst := SkillCastFlare.new()
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
	var w: float = lerpf(WIDTH_FROM, WIDTH_TO, t01)
	var c: Color = _color
	c.a = 0.9 * (1.0 - t01)
	if r > 1.0:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, w)
