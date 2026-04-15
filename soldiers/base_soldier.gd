extends CharacterBody2D
class_name BaseSoldier

# Phase 16: ground blocker. Spawned by TowerBarracks, walks in a straight
# line to its `blocking_position`, then engages the first non-flying
# BaseEnemy that overlaps its MeleeRange. Engagement pins the enemy to
# State.COMBAT so its path progress halts. Both sides attack on Timers.
# On soldier death the enemy is released back to WALKING and the barracks
# schedules a respawn via the soldier_died signal.

enum State { MOVING, BLOCKING, DEAD }

@export var data: Resource  # SoldierData — typed loosely until Godot indexes the class_name

var state: int = State.MOVING
var current_health: int = 0

var _blocking_position: Vector2 = Vector2.ZERO
var _engaged_enemy: Node = null
var _attack_cooldown: float = 0.0

@onready var melee_range: Area2D = $MeleeRange
@onready var melee_shape: CollisionShape2D = $MeleeRange/CollisionShape2D


func _ready() -> void:
	if data:
		current_health = data.max_health
		var circle := CircleShape2D.new()
		circle.radius = data.melee_range
		melee_shape.shape = circle


func setup(blocking_position: Vector2) -> void:
	_blocking_position = blocking_position


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if state == State.DEAD or data == null:
		return
	match state:
		State.MOVING:
			var to_target: Vector2 = _blocking_position - global_position
			if to_target.length() < 3.0:
				velocity = Vector2.ZERO
				change_state(State.BLOCKING)
			else:
				velocity = to_target.normalized() * data.move_speed
			move_and_slide()
		State.BLOCKING:
			_try_engage()
			velocity = Vector2.ZERO
			move_and_slide()
			_attack_cycle(delta)


func _try_engage() -> void:
	if _engaged_enemy != null and is_instance_valid(_engaged_enemy) and _engaged_enemy.state != BaseEnemy.State.DYING:
		return
	_engaged_enemy = null
	for area in melee_range.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.data == null or enemy.data.is_flying:
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		_engaged_enemy = enemy
		enemy.engage_combat(self)
		break


func _attack_cycle(delta: float) -> void:
	if _engaged_enemy == null or not is_instance_valid(_engaged_enemy):
		return
	var enemy: BaseEnemy = _engaged_enemy
	if enemy.state == BaseEnemy.State.DYING:
		_engaged_enemy = null
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	enemy.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)


func take_damage(amount: float, type: int, _source: Node = null) -> void:
	if state == State.DEAD or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if current_health <= 0:
		_die()


func _die() -> void:
	change_state(State.DEAD)
	if _engaged_enemy != null and is_instance_valid(_engaged_enemy):
		_engaged_enemy.release_combat(self)
	_engaged_enemy = null
	EventBus.soldier_died.emit(self)
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(-6, -6, 12, 12), Color(0.8, 0.8, 0.2))
	draw_rect(Rect2(-6, -6, 12, 12), Color(0.3, 0.25, 0.05), false, 1.5)
