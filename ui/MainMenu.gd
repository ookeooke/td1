extends Control

# Main menu — game entry point. Play → WorldMap.
# Reset Progress relocated to OptionsScreen (Phase E) — reachable from
# WorldMap top-bar gear icon. Two-tap-confirm flow preserved there.

@onready var play_button: Button = %PlayButton


func _ready() -> void:
	play_button.pressed.connect(_on_play)


func _on_play() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")
