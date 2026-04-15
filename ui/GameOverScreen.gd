extends CanvasLayer

# Phase 12: end-of-run overlay. Defeat (lives hit 0) or Victory (all waves clear).
# Pauses the tree while shown; Restart resets state and reloads the scene.

@onready var title_label: Label = %TitleLabel
@onready var summary_label: Label = %SummaryLabel
@onready var restart_button: Button = %RestartButton

var _shown: bool = false


func _ready() -> void:
	# Let buttons work while the tree is paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)


func _on_game_over() -> void:
	if _shown:
		return
	_show("Defeat", "You lost all your lives.\nWave reached: %d" % GameState.wave_number)


func _on_all_waves_completed() -> void:
	if _shown:
		return
	if GameState.lives <= 0:
		return
	_show("Victory!", "All waves cleared.\nLives remaining: %d\nGold: %d" % [GameState.lives, GameState.gold])


func _show(title: String, summary: String) -> void:
	_shown = true
	title_label.text = title
	summary_label.text = summary
	visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	GameState.reset()
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.lives_changed.emit(GameState.lives)
	get_tree().reload_current_scene()
