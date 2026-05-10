extends Node2D

# World-space overlay that draws marching chevrons along the paths the
# next callable wave will use. Tied to WaveManager.early_call_available()
# so it shares lifecycle with the Send-Wave badge — visible during pre-W1
# grace and every early-call window, hidden the moment the player commits
# (or no wave is callable). Inspired by KR Alliance's "most paths are
# highlighted from the beginning of a round" + KR Vengeance's route preview.

const CHEVRON_SPACING_WORLD: float = 90.0    # world px between chevrons along the curve
const CHEVRON_SIZE: float = 12.0             # half-length of each chevron in screen px (zoom-scaled)
const CHEVRON_THICKNESS: float = 4.0         # line width in screen px (zoom-scaled)
const MARCH_SPEED: float = 60.0              # world px per second the chevron stream advances

# Match WaveCallIndicator's two states. Amber for pre-W1 (calm), orange
# for OVERLAP_CALLABLE (urgent). Same family of warm tones the badge uses.
const COLOR_PRE_W1 := Color(1.0, 0.92, 0.55, 0.95)
const COLOR_OVERLAP := Color(1.0, 0.55, 0.18, 0.95)

var _level: Node = null
var _phase: float = 0.0
var _color: Color = COLOR_OVERLAP


func _ready() -> void:
	# Below tower spots (z=0) and range indicators, above background fill
	# (-100) and L5+ painted backgrounds (-50 per CORE RULE 21).
	z_index = -10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not WaveManager.early_call_available():
		if visible:
			visible = false
			queue_redraw()
		return
	visible = true
	_ensure_level()
	_color = COLOR_PRE_W1 if WaveManager.is_pre_w1_pending() else COLOR_OVERLAP
	# Phase wraps within one chevron-spacing so the count and positions
	# stay stable; only the offset slides, producing the "marching" effect.
	_phase = fmod(_phase + MARCH_SPEED * delta, CHEVRON_SPACING_WORLD)
	queue_redraw()


# Walk the scene tree for a node implementing BaseLevel's path API.
# Mirrors WaveCallIndicator._ensure_level — level-agnostic, works on
# L1..L5 and any future level without hardcoding scene names.
func _ensure_level() -> void:
	if _level != null and is_instance_valid(_level) and _level.has_method("get_path_by_id"):
		return
	_level = null
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		if child.has_method("get_path_by_id") and child.has_method("get_path_ids"):
			_level = child
			return
	var paths_node: Node = scene.find_child("Paths", true, false)
	if paths_node != null and paths_node.get_parent() != null and paths_node.get_parent().has_method("get_path_by_id"):
		_level = paths_node.get_parent()


func _draw() -> void:
	if _level == null or not visible:
		return
	var zoom_scale: float = _zoom_scale()
	for pid in WaveManager.get_next_wave_path_ids():
		var p: Path2D = _level.get_path_by_id(String(pid))
		if p == null or p.curve == null or p.curve.get_baked_length() <= 0.0:
			continue
		_draw_chevrons_along(p, zoom_scale)


# Sample the path's baked curve at evenly-spaced arc-length offsets and
# render a chevron at each point, oriented along the local tangent.
func _draw_chevrons_along(p: Path2D, zoom_scale: float) -> void:
	var curve: Curve2D = p.curve
	var length: float = curve.get_baked_length()
	var size: float = CHEVRON_SIZE * zoom_scale
	var thickness: float = CHEVRON_THICKNESS * zoom_scale
	var offset: float = _phase
	while offset < length:
		var pos_local: Vector2 = curve.sample_baked(offset, true)
		# Tangent via finite difference along the baked curve (1px ahead).
		# Robust on straight + curved sections without needing curve.get_*.
		var ahead: Vector2 = curve.sample_baked(minf(offset + 1.0, length), true)
		var dir: Vector2 = (ahead - pos_local).normalized()
		if dir == Vector2.ZERO:
			offset += CHEVRON_SPACING_WORLD
			continue
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var pos_world: Vector2 = p.to_global(pos_local)
		# Chevron tip points along travel direction (toward the base).
		var tip: Vector2 = pos_world + dir * size
		var tail_l: Vector2 = pos_world - dir * size + perp * size
		var tail_r: Vector2 = pos_world - dir * size - perp * size
		draw_polyline(PackedVector2Array([tail_l, tip, tail_r]), _color, thickness, true)
		offset += CHEVRON_SPACING_WORLD


# Inverse of camera zoom — multiply screen-pixel sizes by this so they
# stay constant on screen at any zoom level (CLAUDE.md zoom-scale rule).
func _zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / maxf(cam.zoom.x, 0.0001)
