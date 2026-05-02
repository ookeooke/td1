extends CanvasLayer

# In-game pause overlay. Resume / Restart / Quit to Map. Mirrors
# GameOverScreen's CanvasLayer + dim + centered card pattern.
# process_mode = WHEN_PAUSED so buttons fire while the tree is paused.

@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	resume_button.pressed.connect(_on_resume)
	restart_button.pressed.connect(_on_restart)
	quit_button.pressed.connect(_on_quit)
	EventBus.pause_requested.connect(_on_pause_requested)


var _saved_time_scale: float = 1.0


func _on_pause_requested() -> void:
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = 1.0
	visible = true
	get_tree().paused = true


func _on_resume() -> void:
	get_tree().paused = false
	Engine.time_scale = _saved_time_scale
	visible = false


func _on_restart() -> void:
	get_tree().paused = false
	WaveManager.stop()
	RunState.reset_for_level()
	EventBus.gold_changed.emit(RunState.gold)
	EventBus.lives_changed.emit(RunState.lives)
	SceneManager.goto("res://main/Main.tscn")


func _on_quit() -> void:
	get_tree().paused = false
	WaveManager.stop()
	SceneManager.goto("res://ui/WorldMap.tscn")
