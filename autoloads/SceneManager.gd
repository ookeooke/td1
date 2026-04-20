extends CanvasLayer

# Scene transition manager. Single entry point for all screen changes:
#   SceneManager.goto("res://ui/WorldMap.tscn")
#
# Optionally fades a full-screen ColorRect to black and back (0.3 s each
# way) so transitions feel polished. The CanvasLayer sits at layer 100 —
# above every other UI layer — so the fade covers everything.

const FADE_DURATION: float = 0.3

var _color_rect: ColorRect
var _transitioning: bool = false


func _ready() -> void:
	layer = 100
	# Run through pause so a fade initiated from a paused menu (e.g. the
	# GameOverScreen unpauses before calling goto, but defensive) still
	# completes instead of freezing at full black.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_color_rect = ColorRect.new()
	_color_rect.color = Color(0, 0, 0, 0)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_color_rect)


func goto(scene_path: String, fade: bool = true) -> void:
	if _transitioning:
		return
	# Reset fast-forward so menus and WorldMap run at normal speed.
	Engine.time_scale = 1.0
	if not fade:
		get_tree().change_scene_to_file(scene_path)
		return
	_transitioning = true
	_color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_color_rect, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(get_tree().change_scene_to_file.bind(scene_path))
	tween.tween_property(_color_rect, "color:a", 0.0, FADE_DURATION)
	tween.tween_callback(_on_fade_done)


func _on_fade_done() -> void:
	_transitioning = false
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
