class_name EnemyDeathDrift
extends Node2D

# Snapshot of a dying enemy that drifts + rotates + fades, giving death a
# physical reaction instead of a silent despawn. Draws the enemy's visual
# data one last time and lets it ragdoll briefly before disposing.

const _UnitVisualDrawer := preload("res://systems/UnitVisualDrawer.gd")

const LIFETIME: float = 0.35
const DRIFT_SPEED: float = 120.0
const ANGULAR_MIN: float = -6.0
const ANGULAR_MAX: float = 6.0

var _visual: Resource = null  # UnitVisualData
var _velocity: Vector2 = Vector2.ZERO
var _angular: float = 0.0
var _t: float = LIFETIME


static func spawn(parent: Node, visual: Resource, pos: Vector2, hit_dir: Vector2) -> void:
	if parent == null or visual == null:
		return
	var inst := EnemyDeathDrift.new()
	inst.global_position = pos
	inst._visual = visual
	var d: Vector2 = hit_dir if hit_dir.length_squared() > 0.0001 else Vector2.RIGHT
	inst._velocity = d.normalized() * DRIFT_SPEED
	inst._angular = randf_range(ANGULAR_MIN, ANGULAR_MAX)
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	position += _velocity * delta
	rotation += _angular * delta
	# Ease drift + spin to zero so it doesn't fly off-screen.
	_velocity = _velocity.lerp(Vector2.ZERO, 3.0 * delta)
	_angular = lerpf(_angular, 0.0, 3.0 * delta)
	modulate.a = clampf(_t / LIFETIME, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _visual == null:
		return
	_UnitVisualDrawer.draw_unit(self, _visual)
