class_name HitSparkVFX
extends Node2D

# Radial burst at impact, styled by damage type.
#   PHYSICAL → yellow-white radial lines
#   MAGIC    → cyan lines + inner half-ring shockwave
#   TRUE     → gold 4-point star
# Fades over ~0.18 s.

const LIFETIME: float = 0.30
const REACH_FROM: float = 22.0
const REACH_TO: float = 2.0
const SPREAD_RAD: float = 0.6

const STYLE_PHYSICAL: int = 0
const STYLE_MAGIC: int = 1
const STYLE_TRUE: int = 2

var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(1.0, 0.95, 0.7)
var _count: int = 4
var _style: int = STYLE_PHYSICAL
var _t: float = LIFETIME
var _lines: Array = []  # Array of angle offsets (radians), stable per spawn


static func spawn_for_damage_type(parent: Node, pos: Vector2, dir: Vector2, dmg_type: int) -> void:
	# dmg_type uses DamageCalculator.DamageType — 0 = PHYSICAL, 1 = MAGIC, 2 = TRUE.
	match dmg_type:
		1:
			spawn(parent, pos, dir, Color(0.4, 0.85, 1.0), 6, STYLE_MAGIC)
		2:
			spawn(parent, pos, dir, Color(1.0, 0.85, 0.2), 4, STYLE_TRUE)
		_:
			spawn(parent, pos, dir, Color(1.0, 0.95, 0.7), 4, STYLE_PHYSICAL)


static func spawn(parent: Node, pos: Vector2, dir: Vector2, color: Color = Color(1.0, 0.95, 0.7), count: int = 4, style: int = STYLE_PHYSICAL) -> void:
	if parent == null:
		return
	var inst := HitSparkVFX.new()
	inst.global_position = pos
	if dir.length_squared() > 0.0001:
		inst._dir = dir.normalized()
	inst._color = color
	inst._count = clampi(count, 1, 8)
	inst._style = style
	if style == STYLE_TRUE:
		# 4-point star — fixed orthogonal angles, no random spread.
		for i in 4:
			inst._lines.append(float(i) * PI * 0.5)
	else:
		for i in inst._count:
			inst._lines.append(randf_range(-SPREAD_RAD, SPREAD_RAD))
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t01: float = clampf(1.0 - (_t / LIFETIME), 0.0, 1.0)
	var alpha: float = 1.0 - t01
	var base_angle: float = _dir.angle()
	var length: float = lerpf(REACH_FROM, REACH_TO, t01)
	var c: Color = _color
	c.a = alpha
	if _style == STYLE_TRUE:
		# 4-point star — four lines through the origin, orthogonal.
		var reach: float = length + 3.0
		for a in _lines:
			var p: Vector2 = Vector2.from_angle(a) * reach
			draw_line(-p * 0.3, p, c, 3.0, false)
		return
	for a_off in _lines:
		var a: float = base_angle + a_off
		var from: Vector2 = Vector2.from_angle(a) * 3.0
		var to: Vector2 = Vector2.from_angle(a) * (3.0 + length)
		draw_line(from, to, c, 2.5, false)
	if _style == STYLE_MAGIC:
		# Inner expanding shockwave half-ring facing hit direction.
		var ring_r: float = lerpf(6.0, 22.0, t01)
		var span: float = PI * 0.6
		draw_arc(Vector2.ZERO, ring_r, base_angle - span * 0.5, base_angle + span * 0.5, 18, c, 2.5)
