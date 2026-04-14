extends Area2D
class_name BaseEnemy

enum State { WALKING, STUNNED, COMBAT, STEALTHED, DYING }

@export var data: EnemyData

var state: int = State.WALKING
var current_health: int = 0

var _path_follow: PathFollow2D
var _path_id: String = ""


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
	match state:
		State.WALKING:
			_path_follow.progress += data.move_speed * delta
			if _path_follow.progress_ratio >= 1.0:
				_reach_end()
		State.STUNNED, State.COMBAT, State.STEALTHED, State.DYING:
			pass


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
