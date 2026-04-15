extends Node2D
class_name BaseTower

# DEBUG: every 3–6 shots, attach a random SlowEffect/StunEffect to the arrow
# so Phase 13's status system can be exercised through real gameplay instead
# of Main.gd's one-shot demo. Flip DEBUG_STATUS_ARROWS = false to disable.
const DEBUG_STATUS_ARROWS: bool = true
const _SlowEffectScript := preload("res://systems/SlowEffect.gd")
const _StunEffectScript := preload("res://systems/StunEffect.gd")

@export var data: TowerData

var level: int = 1

var _shots_since_buff: int = 0
var _next_buff_threshold: int = 0

@onready var range_area: Area2D = $RangeArea
@onready var range_shape: CollisionShape2D = $RangeArea/CollisionShape2D
@onready var attack_timer: Timer = $AttackTimer


func _ready() -> void:
	if data == null:
		push_warning("[%s] no TowerData assigned" % name)
		return

	var circle := CircleShape2D.new()
	circle.radius = data.attack_range
	range_shape.shape = circle

	attack_timer.wait_time = 1.0 / maxf(0.01, data.attack_speed)
	attack_timer.one_shot = false
	attack_timer.timeout.connect(_on_attack_tick)
	attack_timer.start()

	_next_buff_threshold = randi_range(3, 6)


func _on_attack_tick() -> void:
	var target: Node = _pick_target()
	if target == null:
		return
	_fire_projectile(target)


func _pick_target() -> Node:
	# First-target: enemy furthest along its PathFollow2D.
	var best: Node = null
	var best_progress: float = -1.0
	for area in range_area.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if enemy.data != null and enemy.data.is_flying and not data.targets_flying:
			continue
		var progress: float = 0.0
		if enemy.get_parent() is PathFollow2D:
			progress = enemy.get_parent().progress_ratio
		if progress > best_progress:
			best_progress = progress
			best = enemy
	return best


func _fire_projectile(target: Node) -> void:
	if data.projectile_scene == null:
		return
	var proj: Node2D = data.projectile_scene.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position

	var effect = _maybe_roll_debug_effect()
	if proj.has_method("setup"):
		proj.setup(target, data.damage, data.damage_type, self, effect)


func _maybe_roll_debug_effect():
	if not DEBUG_STATUS_ARROWS:
		return null
	_shots_since_buff += 1
	if _shots_since_buff < _next_buff_threshold:
		return null
	_shots_since_buff = 0
	_next_buff_threshold = randi_range(3, 6)
	if randi() % 2 == 0:
		print("[Tower/debug] slow arrow")
		return _SlowEffectScript.new(0.5, 2.0)
	print("[Tower/debug] stun arrow")
	return _StunEffectScript.new(0.8)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(0.35, 0.45, 0.75))
	draw_arc(Vector2.ZERO, 22.0, 0, TAU, 28, Color(0.08, 0.1, 0.25), 2.5)
