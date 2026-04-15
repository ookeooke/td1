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
		State.STUNNED, State.COMBAT, State.STEALTHED, State.DYING:
			pass


func apply_status_effect(effect) -> void:
	# effect: StatusEffect subclass (SlowEffect / StunEffect / etc.)
	# Untyped param so this compiles before Godot indexes systems/*.gd class_names.
	if effect == null or state == State.DYING:
		return
	_effects[effect.id] = effect
	effect.apply(self)
	if effect.id == "stun" and state != State.STUNNED:
		change_state(State.STUNNED)
	_refresh_visuals()


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
	_refresh_visuals()


func _effective_speed() -> float:
	var s: float = data.move_speed
	if _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	return s


func _refresh_visuals() -> void:
	# Stun takes visual priority over slow.
	if _effects.has("stun"):
		modulate = Color(1.0, 1.0, 0.3)
	elif _effects.has("slow"):
		modulate = Color(0.5, 0.8, 1.0)
	else:
		modulate = Color(1, 1, 1)


func take_damage(amount: float, type: int, _source: Node = null) -> void:
	if state == State.DYING or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if current_health <= 0:
		_die()


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
