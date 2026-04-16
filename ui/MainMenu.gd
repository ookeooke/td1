extends Control

# Main menu — game entry point. Play → WorldMap. Other buttons are
# placeholders for future phases (Heroes Phase 30, Upgrades Phase 28,
# Settings deferred).

@onready var play_button: Button = %PlayButton
@onready var reset_button: Button = %ResetButton

var _reset_confirm: bool = false


func _ready() -> void:
	play_button.pressed.connect(_on_play)
	reset_button.pressed.connect(_on_reset)


func _on_play() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_reset() -> void:
	# Two-tap confirm: first tap changes label to warn, second tap executes.
	if not _reset_confirm:
		_reset_confirm = true
		reset_button.text = "Are you sure?"
		# Auto-revert after 3 seconds if player doesn't confirm.
		get_tree().create_timer(3.0).timeout.connect(func():
			_reset_confirm = false
			reset_button.text = "Reset Progress"
		)
		return
	_reset_confirm = false
	SaveManager.delete_save()
	reset_button.text = "Progress reset!"
	# Brief feedback, then restore label.
	get_tree().create_timer(1.5).timeout.connect(func():
		reset_button.text = "Reset Progress"
	)
