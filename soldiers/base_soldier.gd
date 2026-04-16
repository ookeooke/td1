extends CharacterBody2D
class_name BaseSoldier

# Phase 16: ground blocker. Spawned by TowerBarracks, walks in a straight
# line to its `blocking_position`, then engages the first non-flying
# BaseEnemy that overlaps its MeleeRange. Engagement pins the enemy to
# State.COMBAT so its path progress halts. Both sides attack on Timers.
# On soldier death the enemy is released back to WALKING and the barracks
# schedules a respawn via the soldier_died signal.

enum State { MOVING, BLOCKING, DEAD }

const HP_BAR_SIZE: Vector2 = Vector2(22.0, 3.0)
const HP_BAR_Y_OFFSET: float = -16.0
# Lunge animation — same shape as the hero's. Slightly smaller distance
# since the militia square is half the hero's footprint.
const LUNGE_DURATION: float = 0.12
const LUNGE_DISTANCE: float = 5.0

@export var data: Resource  # SoldierData — typed loosely until Godot indexes the class_name

var state: int = State.MOVING
var current_health: int = 0
var _effective_max_hp: int = 0  # set in _ready with upgrade multiplier

var _blocking_position: Vector2 = Vector2.ZERO
var _engaged_enemy: Node = null
var _attack_cooldown: float = 0.0

var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_t: float = 0.0

# Phase 20.5: passive-ability dispatcher (same primitive as BaseEnemy /
# BaseHero). Paladin-style soldiers attach HealAuraAbility here; shield
# soldiers attach DamageBlockAbility; etc. — all variants author as data.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
var _ability_host: RefCounted = null

@onready var melee_range: Area2D = $MeleeRange
@onready var melee_shape: CollisionShape2D = $MeleeRange/CollisionShape2D


func _ready() -> void:
	if data:
		# Phase 28: permanent upgrade (Reinforced Walls / Soldier HP = type 7).
		_effective_max_hp = int(ceil(float(data.max_health) * GameState.get_upgrade_multiplier(GameState.MOD_SOLDIER_HEALTH)))
		current_health = _effective_max_hp
		var circle := CircleShape2D.new()
		circle.radius = data.melee_range
		melee_shape.shape = circle
	_ability_host = _AbilityHostScript.new(self)
	if data != null and "abilities" in data:
		for ability in data.abilities:
			_ability_host.add_ability(ability)


func setup(blocking_position: Vector2) -> void:
	_blocking_position = blocking_position


func set_blocking_position(new_pos: Vector2) -> void:
	# Called when the player drags the barracks flag. Break any engagement
	# and walk to the new rally slot.
	_blocking_position = new_pos
	if _engaged_enemy != null and is_instance_valid(_engaged_enemy):
		_engaged_enemy.release_combat(self)
	_engaged_enemy = null
	if state != State.DEAD:
		change_state(State.MOVING)


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if state == State.DEAD or data == null:
		return
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		queue_redraw()
	if _ability_host != null:
		_ability_host.tick(delta)
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
	_start_lunge(enemy.global_position)
	var pre_dying: bool = enemy.state == BaseEnemy.State.DYING
	enemy.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": data.attack_damage})
		if not pre_dying and enemy.state == BaseEnemy.State.DYING:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


func _start_lunge(target_world_pos: Vector2) -> void:
	var dir: Vector2 = target_world_pos - global_position
	if dir.length_squared() < 0.01:
		return
	_lunge_dir = dir.normalized()
	_lunge_t = LUNGE_DURATION
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	var t: float = 1.0 - (_lunge_t / LUNGE_DURATION)
	var phase: float = 1.0 - absf(t * 2.0 - 1.0)
	return _lunge_dir * (LUNGE_DISTANCE * phase)


func take_damage(amount: float, type: int, source: Node = null) -> void:
	if state == State.DEAD or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()


func _die() -> void:
	change_state(State.DEAD)
	if _engaged_enemy != null and is_instance_valid(_engaged_enemy):
		_engaged_enemy.release_combat(self)
	_engaged_enemy = null
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.soldier_died.emit(self)
	queue_free()


func _draw() -> void:
	var off: Vector2 = _lunge_offset()
	if data != null and data.visual != null:
		UnitVisualDrawer.draw_unit(self, data.visual, off)
	else:
		# Legacy fallback.
		if off != Vector2.ZERO:
			draw_set_transform(off, 0.0, Vector2.ONE)
		draw_rect(Rect2(-6, -6, 12, 12), Color(0.8, 0.8, 0.2))
		draw_rect(Rect2(-6, -6, 12, 12), Color(0.3, 0.25, 0.05), false, 1.5)
		if off != Vector2.ZERO:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar()


func _draw_health_bar() -> void:
	var max_hp: int = _effective_max_hp if _effective_max_hp > 0 else (data.max_health if data != null else 0)
	if max_hp <= 0:
		return
	if current_health >= max_hp:
		return
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-HP_BAR_SIZE.x * 0.5, HP_BAR_Y_OFFSET)
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * pct, HP_BAR_SIZE.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0), false, 1.0)
