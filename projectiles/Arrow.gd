extends Node2D
class_name Arrow

@export var speed: float = 500.0
@export var hit_radius: float = 10.0

var _target: Node = null
var _damage: float = 0.0
var _damage_type: int = 0
var _source: Node = null


func setup(target: Node, damage: float, damage_type: int, source: Node) -> void:
	_target = target
	_damage = damage
	_damage_type = damage_type
	_source = source


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist <= hit_radius:
		if _target.has_method("take_damage"):
			_target.take_damage(_damage, _damage_type, _source)
		queue_free()
		return
	var step: float = minf(speed * delta, dist)
	global_position += to_target.normalized() * step
	rotation = to_target.angle()
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(-10, 0), Vector2(8, 0), Color(0.9, 0.85, 0.7), 2.0)
	draw_colored_polygon(
		PackedVector2Array([Vector2(12, 0), Vector2(4, -4), Vector2(4, 4)]),
		Color(0.95, 0.85, 0.55)
	)
