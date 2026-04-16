extends Node2D

# Brief expanding-ring + shrinking-flash death effect. Tween-based.
# Usage: DeathVFX.spawn(parent, Color.RED, 14.0, pos)

const _Scene: PackedScene = preload("res://vfx/DeathVFX.tscn")

var _color: Color = Color.RED
var _ring_radius: float = 0.0
var _ring_max: float = 30.0
var _flash_radius: float = 14.0
var _alpha: float = 1.0


static func spawn(parent: Node, color: Color, base_radius: float, pos: Vector2) -> void:
	var inst: Node2D = _Scene.instantiate()
	inst.global_position = pos
	inst._color = color
	inst._flash_radius = base_radius
	inst._ring_max = base_radius + 16.0
	parent.add_child(inst)
	inst._start()


func _start() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "_ring_radius", _ring_max, 0.3)
	tween.tween_property(self, "_flash_radius", 0.0, 0.25)
	tween.tween_property(self, "_alpha", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Expanding ring.
	if _ring_radius > 0.0:
		draw_arc(Vector2.ZERO, _ring_radius, 0, TAU, 24, Color(_color.r, _color.g, _color.b, _alpha * 0.7), 2.5)
	# Shrinking flash.
	if _flash_radius > 0.0:
		draw_circle(Vector2.ZERO, _flash_radius, Color(1.0, 1.0, 1.0, _alpha * 0.5))
