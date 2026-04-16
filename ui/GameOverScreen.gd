extends CanvasLayer

# Phase 12 + Phase 26: end-of-run overlay.
# Victory: shows stars + Continue button → WorldMap (records best stars).
# Defeat: shows wave reached + Restart button → reloads gameplay scene.
# Uses SceneManager for all transitions instead of reload_current_scene.

@onready var title_label: Label = %TitleLabel
@onready var summary_label: Label = %SummaryLabel
@onready var continue_button: Button = %ContinueButton
@onready var restart_button: Button = %RestartButton

var _shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)


func _on_game_over() -> void:
	if _shown:
		return
	if GameState.current_mode == "endless":
		var score: int = GameState.compute_endless_score()
		var is_best: bool = score > GameState.endless_best_score
		if is_best:
			GameState.endless_best_score = score
		GameState.submit_endless_score("Player", score)
		EventBus.endless_score_updated.emit(score)
		SaveManager.save_game()
		continue_button.visible = true
		restart_button.visible = true
		var best_text: String = " NEW BEST!" if is_best else " (Best: %d)" % GameState.endless_best_score
		_show("Game Over", "Wave reached: %d\nScore: %d%s" % [GameState.wave_number, score, best_text])
		return
	continue_button.visible = false
	restart_button.visible = true
	_show("Defeat", "You lost all your lives.\nWave reached: %d" % GameState.wave_number)


func _on_all_waves_completed() -> void:
	if _shown:
		return
	if GameState.lives <= 0:
		return
	var stars: int = GameState.calculate_stars()
	GameState.stars_earned = stars
	# Build the summary based on mode.
	var summary: String = ""
	match GameState.current_mode:
		"campaign":
			var star_text: String = "★".repeat(stars) + "☆".repeat(3 - stars)
			summary = "Campaign cleared!\n%s\nLives: %d  Gold: %d" % [star_text, GameState.lives, GameState.gold]
		"heroic":
			summary = "Heroic cleared!\n+1 bonus star\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
		"iron":
			summary = "Iron cleared!\n+1 bonus star — flawless!\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
		_:
			summary = "All waves cleared.\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
	continue_button.visible = true
	restart_button.visible = false
	_show("Victory!", summary)
	EventBus.level_completed.emit(GameState.current_level_id, stars, GameState.current_mode)


func _show(title: String, summary: String) -> void:
	_shown = true
	title_label.text = title
	summary_label.text = summary
	visible = true
	get_tree().paused = true


func _on_continue_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	if GameState.current_mode != "endless":
		GameState.record_stars()
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	GameState.reset_for_level()
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.lives_changed.emit(GameState.lives)
	SceneManager.goto("res://main/Main.tscn")
