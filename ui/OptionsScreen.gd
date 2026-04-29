extends Control

# Phase E — Options screen. Reachable from WorldMap top-bar gear icon.
# Holds settings that don't belong inside any per-content hub:
#   - Clean View toggle (formerly the in-game HUD "VFX" button)
#   - Reset Progress (relocated from MainMenu — putting it behind a layer
#     prevents accidental taps on first launch)
#
# Future home for: SFX/music volume, font scaler, color-blind palette,
# language picker. Keep this scene small until those features land.

@onready var back_button: Button = %BackButton
@onready var clean_view_button: Button = %CleanViewButton
@onready var reset_button: Button = %ResetButton

var _reset_confirm: bool = false


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	clean_view_button.pressed.connect(_on_clean_view_toggle)
	reset_button.pressed.connect(_on_reset)
	_refresh_clean_view_label()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


# --- Clean View toggle ------------------------------------------------------
# Mirrors the prior HUD CleanButton — emits the same EventBus signal so
# VFXSpawner picks up the change. State is per-session (not persisted) —
# matches the prior in-HUD behavior.

func _refresh_clean_view_label() -> void:
	if VFXSpawner.clean_view:
		clean_view_button.text = "Clean View: On"
	else:
		clean_view_button.text = "Clean View: Off"


func _on_clean_view_toggle() -> void:
	var enabled: bool = not VFXSpawner.clean_view
	EventBus.clean_view_toggled.emit(enabled)
	_refresh_clean_view_label()


# --- Reset Progress (two-tap confirm) --------------------------------------

func _on_reset() -> void:
	if not _reset_confirm:
		_reset_confirm = true
		reset_button.text = "Are you sure?"
		get_tree().create_timer(3.0).timeout.connect(func():
			_reset_confirm = false
			reset_button.text = "Reset Progress"
		)
		return
	_reset_confirm = false
	SaveManager.delete_save()
	reset_button.text = "Progress reset!"
	get_tree().create_timer(1.5).timeout.connect(func():
		reset_button.text = "Reset Progress"
	)
