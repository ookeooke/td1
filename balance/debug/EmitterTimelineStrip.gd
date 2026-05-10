extends Control
class_name EmitterTimelineStrip

# Per-emitter spawn-schedule visualizer + drag editor for BalanceSliders.
# Renders a horizontal strip with one tick per spawn and three drag zones:
#
#   [LEFT_EDGE handle]  ───────── BODY ─────────  [RIGHT_EDGE handle]
#       ↕ retime start_delay,         ↕ retime everything,         ↕ resize count
#         end stays anchored,         interval + count unchanged,    (interval const)
#         count adjusts
#
# Width = wave's spawn window scaled to the strip rect, so multiple strips
# stacked vertically share an x-axis aligned with the WaveTimelineChart bar
# columns. Industry pattern: Unity Timeline / Adobe Premiere clip with
# trim handles.
#
# Debug-only — instantiated by BalanceSliders.gd's _add_emitter_slider.
# values_changed is emitted on every drag delta; BalanceSliders writes the
# corresponding BalanceOverrides and re-syncs sibling strips + chart.

signal values_changed(new_start: float, new_interval: float, new_count: int)

const STRIP_HEIGHT: float = 18.0
const TICK_HEIGHT: float = 12.0
const TICK_WIDTH: float = 1.5
const EDGE_HIT_PX: float = 6.0
const SNAP_S: float = 0.5

const COL_BASELINE: Color = Color(0.25, 0.27, 0.30, 1.0)
const COL_HOVER_HANDLE: Color = Color(1.0, 0.95, 0.5, 0.9)
const COL_DRAG_GUIDE: Color = Color(0.95, 0.95, 1.0, 0.85)
const COL_DRAG_LABEL: Color = Color(0.95, 0.95, 1.0)

enum DragMode { NONE, BODY, LEFT_EDGE, RIGHT_EDGE }

# Authored / override-resolved values, set via set_data().
var _start: float = 0.0
var _interval: float = 1.0
var _count: int = 0
var _window_sec: float = 60.0
var _tick_color: Color = Color(0.65, 0.65, 0.70)

# Drag state.
var _drag_mode: int = DragMode.NONE
var _drag_origin_x: float = 0.0
var _drag_origin_start: float = 0.0
var _drag_origin_count: int = 0
var _drag_end_anchor: float = 0.0   # LEFT_EDGE drag pins this t.
var _drag_cursor_t: float = 0.0     # Live cursor time for the guide line.

# Hover state — drives cursor + edge highlight.
var _hover_zone: int = DragMode.NONE


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP


func set_data(start: float, interval: float, count: int,
		window_sec: float, color: Color) -> void:
	_start = start
	_interval = max(0.1, interval)
	_count = count
	_window_sec = max(0.001, window_sec)
	_tick_color = color
	custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	queue_redraw()


# ─── Coordinate transforms ─────────────────────────────────────────────────

func _t_per_pixel() -> float:
	if size.x <= 0.0:
		return 0.0
	return _window_sec / size.x


func _pixel_for_t(t: float) -> float:
	return clampf(t / _window_sec, 0.0, 1.0) * size.x


func _t_for_x(x: float) -> float:
	if size.x <= 0.0:
		return 0.0
	return clampf(x / size.x * _window_sec, 0.0, _window_sec)


# ─── Hit-testing ───────────────────────────────────────────────────────────

func _zone_at_x(x: float) -> int:
	if _count <= 0:
		return DragMode.NONE
	var sx: float = _pixel_for_t(_start)
	var ex: float = _pixel_for_t(_start + float(max(_count - 1, 0)) * _interval)
	# Single-tick emitter: edges coincide. Treat the whole region as body
	# (retime). Tested before the edge zones so we don't accidentally hit
	# LEFT_EDGE first and lock count adjustments out.
	if abs(ex - sx) < 0.5:
		if abs(x - sx) <= EDGE_HIT_PX:
			return DragMode.BODY
		return DragMode.NONE
	if abs(x - sx) <= EDGE_HIT_PX:
		return DragMode.LEFT_EDGE
	if abs(x - ex) <= EDGE_HIT_PX:
		return DragMode.RIGHT_EDGE
	if x >= sx and x <= ex:
		return DragMode.BODY
	return DragMode.NONE


func _update_cursor() -> void:
	match _hover_zone:
		DragMode.LEFT_EDGE, DragMode.RIGHT_EDGE:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		DragMode.BODY:
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


# ─── Input ─────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position.x)
			else:
				_end_drag()
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag_mode != DragMode.NONE:
			_continue_drag(event.position.x, event.ctrl_pressed)
			accept_event()
		else:
			var z: int = _zone_at_x(event.position.x)
			if z != _hover_zone:
				_hover_zone = z
				_update_cursor()
				queue_redraw()


func _begin_drag(x: float) -> void:
	var z: int = _zone_at_x(x)
	if z == DragMode.NONE:
		return
	_drag_mode = z
	_drag_origin_x = x
	_drag_origin_start = _start
	_drag_origin_count = _count
	_drag_end_anchor = _start + float(max(_count - 1, 0)) * _interval
	_drag_cursor_t = _t_for_x(x)
	queue_redraw()


func _continue_drag(x: float, ctrl_held: bool) -> void:
	var t_pp: float = _t_per_pixel()
	if t_pp <= 0.0:
		return
	var snap: bool = not ctrl_held
	match _drag_mode:
		DragMode.BODY:
			var dt: float = t_pp * (x - _drag_origin_x)
			var new_start: float = max(0.0, _drag_origin_start + dt)
			if snap:
				new_start = round(new_start / SNAP_S) * SNAP_S
			_start = new_start
			_drag_cursor_t = new_start
			values_changed.emit(_start, _interval, _count)
		DragMode.RIGHT_EDGE:
			var cursor_t: float = max(_start, _t_for_x(x))
			var new_count: int = int(floor((cursor_t - _start) / _interval)) + 1
			_count = max(1, new_count)
			_drag_cursor_t = cursor_t
			values_changed.emit(_start, _interval, _count)
		DragMode.LEFT_EDGE:
			var ct: float = clampf(_t_for_x(x), 0.0, _drag_end_anchor)
			if snap:
				ct = round(ct / SNAP_S) * SNAP_S
				ct = clampf(ct, 0.0, _drag_end_anchor)
			_start = ct
			var span: float = _drag_end_anchor - ct
			_count = max(1, int(round(span / _interval)) + 1)
			_drag_cursor_t = ct
			values_changed.emit(_start, _interval, _count)
	queue_redraw()


func _end_drag() -> void:
	if _drag_mode == DragMode.NONE:
		return
	_drag_mode = DragMode.NONE
	queue_redraw()


# ─── Rendering ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0:
		return
	var mid: float = h * 0.5
	draw_line(Vector2(0, mid), Vector2(w, mid), COL_BASELINE, 1.0, true)
	if _count <= 0:
		return
	var tick_top: float = (h - TICK_HEIGHT) * 0.5
	var tick_bot: float = tick_top + TICK_HEIGHT
	# Tick marks at every spawn time.
	for i in range(_count):
		var t: float = _start + float(i) * _interval
		if t > _window_sec:
			break
		var x: float = clampf(t / _window_sec, 0.0, 1.0) * w
		draw_line(Vector2(x, tick_top), Vector2(x, tick_bot),
			_tick_color, TICK_WIDTH, false)
	# Edge handle highlight on hover or while dragging.
	var sx: float = _pixel_for_t(_start)
	var ex: float = _pixel_for_t(_start + float(max(_count - 1, 0)) * _interval)
	if _hover_zone == DragMode.LEFT_EDGE or _drag_mode == DragMode.LEFT_EDGE:
		draw_line(Vector2(sx, tick_top - 1), Vector2(sx, tick_bot + 1),
			COL_HOVER_HANDLE, 3.0, false)
	if _hover_zone == DragMode.RIGHT_EDGE or _drag_mode == DragMode.RIGHT_EDGE:
		draw_line(Vector2(ex, tick_top - 1), Vector2(ex, tick_bot + 1),
			COL_HOVER_HANDLE, 3.0, false)
	# Drag preview: vertical guide line + live readout near the cursor.
	if _drag_mode != DragMode.NONE:
		var gx: float = _pixel_for_t(_drag_cursor_t)
		draw_line(Vector2(gx, 0), Vector2(gx, h), COL_DRAG_GUIDE, 1.0, true)
		var font: Font = ThemeDB.fallback_font
		var end_t: float = _start + float(max(_count - 1, 0)) * _interval
		var label: String = "t=%.1fs · n=%d · end=%.1fs" % [_start, _count, end_t]
		var label_x: float = gx + 4.0
		# Flip label to the left of the cursor when it would overflow the
		# right edge of the strip.
		var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 10).x
		if label_x + label_w > w - 2.0:
			label_x = gx - label_w - 4.0
		draw_string(font, Vector2(label_x, h * 0.5 + 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, COL_DRAG_LABEL)
