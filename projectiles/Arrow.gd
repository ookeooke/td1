extends Node2D
class_name Arrow

@export var speed: float = 1250.0
@export var hit_radius: float = 62.5
# Projectile body color — overridden per tower via setup. Default = arrow tan.
@export var proj_color: Color = Color(0.95, 0.85, 0.55)
# Fading motion-blur tail behind the projectile. Off on per-scene overrides
# (set in the .tscn inspector) when the effect doesn't fit — e.g. a heavy
# ArtilleryShell might want a smoke puff instead. Default on.
@export var trail_enabled: bool = true

# Ring buffer of world-space positions sampled once per _process tick.
# Older → lower alpha. Max length capped by TRAIL_SAMPLES.
const TRAIL_SAMPLES: int = 5
var _trail: PackedVector2Array = PackedVector2Array()

var _target: Node = null
var _damage: float = 0.0
var _damage_type: int = 0
var _source: Node = null
var _status_effect = null  # optional StatusEffect subclass, applied on hit
var _aoe_radius: float = 0.0  # > 0 = splash on hit


func setup(target: Node, damage: float, damage_type: int, source: Node, status_effect = null, aoe_radius: float = 0.0) -> void:
	_target = target
	_damage = damage
	_damage_type = damage_type
	_source = source
	_status_effect = status_effect
	_aoe_radius = aoe_radius


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist <= hit_radius:
		_on_hit()
		queue_free()
		return
	# Sample the current world position before advancing so the trail draws
	# *behind* the projectile, not through its current body.
	if trail_enabled:
		_trail.append(global_position)
		if _trail.size() > TRAIL_SAMPLES:
			_trail.remove_at(0)
	var step: float = minf(speed * delta, dist)
	global_position += to_target.normalized() * step
	rotation = to_target.angle()
	queue_redraw()


func _on_hit() -> void:
	var impact_pos: Vector2 = _target.global_position if is_instance_valid(_target) else global_position
	var total_dealt: float = 0.0
	# Primary target damage.
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		total_dealt += _target.take_damage(_damage, _damage_type, _source)
	if _status_effect != null and is_instance_valid(_target) and _target.has_method("apply_status_effect"):
		_target.apply_status_effect(_status_effect)
	# AoE splash — damage all enemies in radius (excluding already-hit primary).
	if _aoe_radius > 0.0:
		var r2: float = _aoe_radius * _aoe_radius
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy == _target:
				continue
			if not (enemy is BaseEnemy):
				continue
			if enemy.state == BaseEnemy.State.DYING:
				continue
			if impact_pos.distance_squared_to(enemy.global_position) <= r2:
				total_dealt += enemy.take_damage(_damage * 0.5, _damage_type, _source)
	# Report damage to source tower for stat tracking.
	if total_dealt > 0.0 and _source != null and is_instance_valid(_source) and _source.has_method("record_damage"):
		_source.record_damage(total_dealt)


func _draw() -> void:
	# Trail drawn BEFORE the body so the arrow sits on top of its own tail.
	# Samples are world-space, so transform each back to local frame using
	# the inverse of the node's current rotation + position.
	if trail_enabled and _trail.size() >= 2:
		var inv_rot: float = -rotation
		var trail_col: Color = proj_color.darkened(0.2)
		for i in range(_trail.size() - 1):
			var a_world: Vector2 = _trail[i]
			var b_world: Vector2 = _trail[i + 1]
			var a_local: Vector2 = (a_world - global_position).rotated(inv_rot)
			var b_local: Vector2 = (b_world - global_position).rotated(inv_rot)
			# Newer segments (higher i) get more alpha + thicker line.
			var frac: float = float(i + 1) / float(TRAIL_SAMPLES)
			var col: Color = trail_col
			col.a = frac * 0.6
			draw_line(a_local, b_local, col, lerpf(4.0, 10.0, frac), true)
	draw_line(Vector2(-62.5, 0), Vector2(50, 0), proj_color.darkened(0.2), 12.5)
	draw_colored_polygon(
		PackedVector2Array([Vector2(75, 0), Vector2(25, -25), Vector2(25, 25)]),
		proj_color
	)
