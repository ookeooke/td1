extends CanvasLayer

# In-game pause overlay with TACTICAL PAUSE support.
#
# Two sub-states while `get_tree().paused`:
#   menu-visible  — Dim + Card (Resume/Restart/Quit/Hide) shown
#   menu-hidden   — only the small "PAUSED ≡" badge top-center; the
#                   playfield is fully interactable via the existing
#                   PROCESS_MODE_ALWAYS UIs (TowerRadialMenu, HeroHudPortrait,
#                   SkillBar, GameCamera).
#
# HUD pause button toggles the paused state itself; tapping the Dim (or the
# Hide button) drops to menu-hidden; tapping the badge "≡" restores the menu.
# process_mode = WHEN_PAUSED so the card buttons fire while the tree is paused.

@onready var root: Control = %Root
@onready var dim: ColorRect = %Dim
@onready var center: CenterContainer = %Center
@onready var badge: PanelContainer = %PausedBadge
@onready var resume_button: Button = %ResumeButton
@onready var hide_button: Button = %HideButton
@onready var stats_button: Button = %StatsButton
@onready var help_button: Button = %HelpButton
@onready var restart_button: Button = %RestartButton
@onready var quit_button: Button = %QuitButton
@onready var menu_button: Button = %MenuButton

var _is_paused: bool = false
var _menu_visible: bool = false
var _saved_time_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	resume_button.pressed.connect(_on_resume)
	hide_button.pressed.connect(_on_hide_menu)
	stats_button.pressed.connect(_on_stats)
	help_button.pressed.connect(_on_help)
	restart_button.pressed.connect(_on_restart)
	quit_button.pressed.connect(_on_quit)
	menu_button.pressed.connect(_on_show_menu)
	dim.gui_input.connect(_on_dim_input)
	EventBus.pause_requested.connect(_on_pause_requested)
	_apply_visibility()


# HUD pause button → toggle. While running: enter pause (menu visible).
# While paused: resume (whether the menu is currently visible or hidden).
func _on_pause_requested() -> void:
	if _is_paused:
		_resume()
	else:
		_enter_pause()


func _enter_pause() -> void:
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = 1.0
	get_tree().paused = true
	_is_paused = true
	_menu_visible = true
	_apply_visibility()
	EventBus.pause_state_changed.emit(true)
	EventBus.pause_menu_visibility_changed.emit(true)


func _resume() -> void:
	_is_paused = false
	_menu_visible = false
	_apply_visibility()
	get_tree().paused = false
	Engine.time_scale = _saved_time_scale
	EventBus.pause_state_changed.emit(false)
	EventBus.pause_menu_visibility_changed.emit(false)


# menu-hidden ↔ menu-visible toggle. Paused state unchanged.
func _set_menu_visible(v: bool) -> void:
	if not _is_paused:
		return
	_menu_visible = v
	_apply_visibility()
	EventBus.pause_menu_visibility_changed.emit(v)


func _on_hide_menu() -> void:
	_set_menu_visible(false)


func _on_show_menu() -> void:
	_set_menu_visible(true)


func _on_dim_input(event: InputEvent) -> void:
	# Tap anywhere on the dim backdrop (outside the centered card) → hide menu.
	if event is InputEventScreenTouch and event.pressed:
		_set_menu_visible(false)


func _on_resume() -> void:
	_resume()


# Stats / Help: route to the dedicated modal scenes via the EventBus. Drop
# the pause card to menu-hidden so the modal isn't competing with our own
# Dim for input focus — the game stays paused and the small PAUSED badge
# remains visible. Closing the modal (X / Dim tap) returns to badge-only;
# re-press the HUD pause button to bring the card back via _on_show_menu.
func _on_stats() -> void:
	EventBus.run_stats_panel_requested.emit()
	_set_menu_visible(false)


func _on_help() -> void:
	EventBus.help_overlay_requested.emit()
	_set_menu_visible(false)


# Resolve visibility from (_is_paused, _menu_visible). Root must stop input
# while the menu is up (Dim handles dismiss) and pass-through while hidden,
# otherwise the full-screen Root would swallow taps meant for towers/heroes
# during tactical pause. Children of Root (Badge buttons) still receive their
# own clicks because hit-tests run on children before consulting the parent.
func _apply_visibility() -> void:
	dim.visible = _is_paused and _menu_visible
	center.visible = _is_paused and _menu_visible
	badge.visible = _is_paused and not _menu_visible
	root.mouse_filter = Control.MOUSE_FILTER_STOP if (_is_paused and _menu_visible) else Control.MOUSE_FILTER_IGNORE


func _on_restart() -> void:
	_is_paused = false
	_menu_visible = false
	_apply_visibility()
	get_tree().paused = false
	Engine.time_scale = _saved_time_scale
	EventBus.pause_state_changed.emit(false)
	EventBus.pause_menu_visibility_changed.emit(false)
	WaveManager.stop()
	RunState.reset_for_level()
	EventBus.gold_changed.emit(RunState.gold)
	EventBus.lives_changed.emit(RunState.lives)
	SceneManager.goto("res://main/Main.tscn")


func _on_quit() -> void:
	_is_paused = false
	_menu_visible = false
	_apply_visibility()
	get_tree().paused = false
	Engine.time_scale = _saved_time_scale
	EventBus.pause_state_changed.emit(false)
	EventBus.pause_menu_visibility_changed.emit(false)
	WaveManager.stop()
	SceneManager.goto("res://ui/WorldMap.tscn")
