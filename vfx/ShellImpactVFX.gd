class_name ShellImpactVFX
extends Node2D

# Ground impact for AoE projectiles (artillery shells, fireballs, anything
# with _aoe_radius > 0). Two layered effects: a slow scorch ellipse that
# lingers on the ground (~0.6s) and a fast expanding white ring at the AoE
# radius (~0.22s) that pops then fades. The ring doubles as a teaching aid —
# players see the actual splash radius instead of guessing.

const LIFETIME: float = 0.6
const RING_DURATION: float = 0.22

var _radius: float = 60.0
var _t: float = LIFETIME
var _ring_t: float = RING_DURATION


static func spawn(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null:
		return
	var inst := ShellImpactVFX.new()
	inst.global_position = pos
	inst._radius = radius
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	_ring_t = maxf(0.0, _ring_t - delta)
	if _t <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# Scorch — fades smoothly over the full lifetime.
	var alpha: float = clampf(_t / LIFETIME, 0.0, 1.0)
	draw_circle(Vector2.ZERO, _radius, Color(0.06, 0.05, 0.04, alpha * 0.40))
	draw_circle(Vector2.ZERO, _radius * 0.55, Color(0.0, 0.0, 0.0, alpha * 0.45))
	# Expanding ring at AoE radius — short pop that snaps the eye to the splash.
	if _ring_t > 0.0:
		var rt: float = 1.0 - _ring_t / RING_DURATION
		var r: float = lerpf(_radius * 0.3, _radius, rt)
		var ring_a: float = (1.0 - rt) * 0.85
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(1.0, 0.95, 0.75, ring_a), lerpf(5.0, 1.5, rt))
