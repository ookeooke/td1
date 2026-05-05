class_name MuzzleFlashVFX
extends Node2D

# Brief flash + outward rays at the barrel tip on every tower shot. Fires
# immediately before the projectile spawns so the eye reads "tower fires →
# projectile flies." Color tinted per tower type (orange archer / cyan ice /
# purple mage / orange artillery) so each shot reads as that tower's element.
# 0.06s lifetime — single short burst, never lingers into the next shot.

const LIFETIME: float = 0.06
const RADIUS_FROM: float = 4.0
const RADIUS_TO: float = 14.0
const RAY_COUNT: int = 3
const RAY_LENGTH: float = 18.0

var _color: Color = Color(1.0, 0.95, 0.6)
var _aim_angle: float = 0.0
var _t: float = LIFETIME


static func spawn(parent: Node, pos: Vector2, aim_angle: float, color: Color) -> void:
	if parent == null:
		return
	var inst := MuzzleFlashVFX.new()
	inst.global_position = pos
	inst._aim_angle = aim_angle
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
	var alpha: float = 1.0 - t01
	var r: float = lerpf(RADIUS_FROM, RADIUS_TO, t01)
	# Bright white core.
	draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 1.0, 1.0, alpha * 0.9))
	# Tinted halo.
	var halo: Color = _color
	halo.a = alpha * 0.65
	draw_circle(Vector2.ZERO, r, halo)
	# Outward rays in a small cone along aim direction.
	var ray: Color = _color
	ray.a = alpha * 0.85
	var spread: float = 0.55
	var denom: float = float(maxi(RAY_COUNT - 1, 1))
	for i in RAY_COUNT:
		var off: float = lerpf(-spread, spread, float(i) / denom)
		var a: float = _aim_angle + off
		var dir: Vector2 = Vector2.from_angle(a)
		var p_to: Vector2 = dir * RAY_LENGTH
		draw_line(dir * (r * 0.4), p_to, ray, 2.0, true)
