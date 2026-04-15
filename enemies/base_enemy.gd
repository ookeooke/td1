extends Area2D
class_name BaseEnemy

enum State { WALKING, STUNNED, COMBAT, STEALTHED, DYING }

@export var data: EnemyData

var state: int = State.WALKING
var current_health: int = 0

var _path_follow: PathFollow2D
var _path_id: String = ""

# Active status effects keyed by id ("slow", "stun"). Reapplying the same id
# replaces the prior effect (refreshes duration / takes stronger value).
var _effects: Dictionary = {}

# Combat engagement — set by soldiers calling engage_combat(self).
var _blocker: Node = null
var _combat_cooldown: float = 0.0


func _ready() -> void:
	if data:
		current_health = data.max_health
	queue_redraw()


func setup(path_follow: PathFollow2D, path_id: String) -> void:
	_path_follow = path_follow
	_path_id = path_id


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if _path_follow == null or data == null:
		return
	_tick_effects(delta)
	match state:
		State.WALKING:
			_path_follow.progress += _effective_speed() * delta
			if _path_follow.progress_ratio >= 1.0:
				_reach_end()
		State.COMBAT:
			_combat_tick(delta)
		State.STUNNED, State.STEALTHED, State.DYING:
			pass


func engage_combat(soldier: Node) -> void:
	if state == State.DYING or soldier == null:
		return
	_blocker = soldier
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed) if data != null else 1.0
	change_state(State.COMBAT)


func release_combat(soldier: Node = null) -> void:
	# If a specific soldier is provided, only release if it matches the
	# current blocker (prevents stale release calls).
	if soldier != null and _blocker != soldier:
		return
	_blocker = null
	_combat_cooldown = 0.0
	if state == State.COMBAT:
		change_state(State.WALKING)


func _combat_tick(delta: float) -> void:
	if _blocker == null or not is_instance_valid(_blocker) or data == null:
		release_combat()
		return
	_combat_cooldown -= delta
	if _combat_cooldown > 0.0:
		return
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	if _blocker.has_method("take_damage"):
		_blocker.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)


func apply_status_effect(effect) -> void:
	# effect: StatusEffect subclass (SlowEffect / StunEffect / etc.)
	# Untyped param so this compiles before Godot indexes systems/*.gd class_names.
	if effect == null or state == State.DYING:
		return
	_effects[effect.id] = effect
	effect.apply(self)
	if effect.id == "stun" and state != State.STUNNED:
		change_state(State.STUNNED)
	queue_redraw()


func _tick_effects(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired: Array[String] = []
	for id in _effects.keys():
		var e = _effects[id]
		e.duration -= delta
		if e.duration <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		var e = _effects[id]
		e.remove(self)
		_effects.erase(id)
		if id == "stun" and state == State.STUNNED:
			change_state(State.WALKING)
	queue_redraw()


func _effective_speed() -> float:
	var s: float = data.move_speed
	if _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	return s


func take_damage(amount: float, type: int, _source: Node = null) -> void:
	if state == State.DYING or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if current_health <= 0:
		_die()


func heal(amount: float) -> void:
	if state == State.DYING or data == null:
		return
	if current_health >= data.max_health:
		return
	var before: int = current_health
	current_health = mini(data.max_health, current_health + int(ceil(amount)))
	if current_health != before:
		print("[Enemy/heal] %s %d → %d" % [data.enemy_name, before, current_health])


func _die() -> void:
	change_state(State.DYING)
	EventBus.enemy_died.emit(self, data.gold_worth)
	_despawn()


func _reach_end() -> void:
	change_state(State.DYING)
	EventBus.enemy_reached_end.emit(self, data.lives_worth)
	_despawn()


func _despawn() -> void:
	if is_instance_valid(_path_follow):
		_path_follow.queue_free()
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(0.75, 0.2, 0.2))
	draw_arc(Vector2.ZERO, 14.0, 0, TAU, 24, Color(0.15, 0.05, 0.05), 2.0)
	# Status-effect overlay rings. Stun drawn outermost so it's visible even
	# if a slow is also active.
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 23.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
