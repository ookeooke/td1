extends Control

# Phase 45b: generic action slot for the occupied-spot radial menu.
# Covers upgrade / sell / targeting / rally / branch. Same 90×90 circular
# slot shape as TowerIconButton so the visual vocabulary stays uniform
# across build and action rings.
#
# Setup is data-driven — menu code builds each slot by action_id, passes
# pictogram + color + badge text, and the slot handles its own draw +
# input. Slot emits pressed(action_id, payload) on release.

signal pressed(action_id: String, payload)

const SIZE_PX: float = 90.0

var action_id: String = ""
var payload = null

var _pictogram: String = ""
var _pictogram_variant: int = 0
var _color: Color = Color(0.3, 0.3, 0.35)
var _badge_text: String = ""
var _badge_color: Color = Color(0.95, 0.78, 0.22)
var _enabled: bool = true
var _is_pressed: bool = false
var _is_mouse_over: bool = false
# Armed = first tap has selected this slot; next tap commits.
var _armed: bool = false


func set_armed(on: bool) -> void:
	if _armed == on:
		return
	_armed = on
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func setup(
		id: String,
		pay,
		pict: String,
		variant: int,
		color: Color,
		badge: String,
		badge_color: Color,
		enabled: bool) -> void:
	action_id = id
	payload = pay
	_pictogram = pict
	_pictogram_variant = variant
	_color = color
	_badge_text = badge
	_badge_color = badge_color
	_enabled = enabled
	queue_redraw()


func set_enabled(on: bool) -> void:
	if _enabled == on:
		return
	_enabled = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Touch-only per CLAUDE.md. Project has emulate_touch_from_mouse=true, so
	# mouse clicks arrive here as InputEventScreenTouch. Handling both event
	# types would double-fire `pressed` on PC and break the two-step commit.
	if not _enabled:
		return
	if not (event is InputEventScreenTouch):
		return
	var was_inside: bool = Rect2(Vector2.ZERO, size).has_point(event.position)
	if event.pressed:
		_is_pressed = true
		queue_redraw()
	else:
		_is_pressed = false
		queue_redraw()
		if was_inside:
			pressed.emit(action_id, payload)


func _on_mouse_entered() -> void:
	_is_mouse_over = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_is_mouse_over = false
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = size.x * 0.5 - 2.0
	var press_scale: float = 0.92 if _is_pressed else 1.0
	var r: float = radius * press_scale
	var alpha: float = 1.0 if _enabled else 0.55
	var base_color: Color = _color if _enabled else Color(0.45, 0.45, 0.5)
	base_color.a = alpha

	if _armed and _enabled:
		draw_circle(center, r + 7.0, Color(1.0, 0.95, 0.55, 0.45))
	elif (_is_mouse_over or _is_pressed) and _enabled:
		draw_circle(center, r + 5.0, Color(1.0, 0.95, 0.55, 0.28))

	draw_circle(center, r, base_color)
	draw_arc(center, r, 0.0, TAU, 48, Color(0.08, 0.08, 0.1, alpha), 2.5)

	_draw_pictogram(center, r, alpha)
	if _badge_text != "":
		_draw_badge(center, r)


func _draw_pictogram(center: Vector2, radius: float, alpha: float) -> void:
	var white: Color = Color(1.0, 0.97, 0.88, alpha)
	var dark: Color = Color(0.12, 0.14, 0.2, alpha)
	var g: float = radius * 0.55
	match _pictogram:
		"upgrade":
			_draw_chevron_up(center, g, white)
		"sell":
			_draw_coins(center, g, white, dark)
		"target":
			_draw_target(center, g, white, dark, _pictogram_variant)
		"rally":
			_draw_flag(center, g, white, dark)
		"branch":
			_draw_chevron_up(center + Vector2(0, -g * 0.15), g * 0.75, white)
			_draw_branch_letter(center + Vector2(0, g * 0.55), _pictogram_variant, white)
		_:
			draw_circle(center, g * 0.5, white)


func _draw_chevron_up(c: Vector2, g: float, col: Color) -> void:
	var tip: Vector2 = c + Vector2(0, -g * 0.65)
	var left_out: Vector2 = c + Vector2(-g * 0.85, g * 0.1)
	var right_out: Vector2 = c + Vector2(g * 0.85, g * 0.1)
	var left_in: Vector2 = c + Vector2(-g * 0.3, g * 0.25)
	var right_in: Vector2 = c + Vector2(g * 0.3, g * 0.25)
	var tip_in: Vector2 = c + Vector2(0, -g * 0.2)
	var pts: PackedVector2Array = PackedVector2Array([
		tip, right_out, right_in, tip_in, left_in, left_out
	])
	draw_colored_polygon(pts, col)
	# Vertical stem for emphasis.
	draw_line(c + Vector2(0, -g * 0.15), c + Vector2(0, g * 0.6), col, 7.0)


func _draw_coins(c: Vector2, g: float, col: Color, dark: Color) -> void:
	var rc: float = g * 0.42
	var positions: Array[Vector2] = [
		c + Vector2(-g * 0.28, g * 0.12),
		c + Vector2(g * 0.28, g * 0.12),
		c + Vector2(0, -g * 0.28),
	]
	for p in positions:
		draw_circle(p, rc, col)
		draw_arc(p, rc, 0.0, TAU, 20, dark, 1.5)
		draw_circle(p, rc * 0.28, dark)


func _draw_target(c: Vector2, g: float, col: Color, dark: Color, variant: int) -> void:
	match variant:
		0:
			# FIRST — forward arrow, same language as the build-ring archer.
			var p0: Vector2 = c + Vector2(-g * 0.5, 0.0)
			var p1: Vector2 = c + Vector2(g * 0.6, 0.0)
			draw_line(p0, p1, col, 5.0)
			draw_line(p1, p1 + Vector2(-g * 0.3, -g * 0.3), col, 5.0)
			draw_line(p1, p1 + Vector2(-g * 0.3, g * 0.3), col, 5.0)
		1:
			# STRONG — skull silhouette.
			draw_circle(c + Vector2(0, -g * 0.08), g * 0.55, col)
			draw_circle(c + Vector2(-g * 0.22, -g * 0.1), g * 0.12, dark)
			draw_circle(c + Vector2(g * 0.22, -g * 0.1), g * 0.12, dark)
			var jaw: Rect2 = Rect2(c + Vector2(-g * 0.22, g * 0.25), Vector2(g * 0.44, g * 0.24))
			draw_rect(jaw, col)
			draw_line(c + Vector2(-g * 0.08, g * 0.28), c + Vector2(-g * 0.08, g * 0.46), dark, 2.0)
			draw_line(c + Vector2(g * 0.08, g * 0.28), c + Vector2(g * 0.08, g * 0.46), dark, 2.0)
		2:
			# WEAK — teardrop / water drop.
			# Tip above, arc sweeps 270° through right→bottom→left, closing
			# back to the tip. Starts at upper-right (-π/4) and ends at
			# upper-left (5π/4) so neither connecting edge crosses the arc.
			var drop: PackedVector2Array = PackedVector2Array()
			var bulge: Vector2 = c + Vector2(0.0, g * 0.1)
			var rr: float = g * 0.42
			drop.append(c + Vector2(0.0, -g * 0.65))
			var sweep: float = PI * 1.5
			var start_ang: float = -PI * 0.25
			var steps: int = 24
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var ang: float = start_ang + sweep * t
				drop.append(bulge + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(drop, col)


func _draw_flag(c: Vector2, g: float, col: Color, _dark: Color) -> void:
	# Pole.
	draw_line(
		c + Vector2(-g * 0.4, g * 0.65),
		c + Vector2(-g * 0.4, -g * 0.65),
		col, 4.5)
	# Pennant.
	var flag: PackedVector2Array = PackedVector2Array([
		c + Vector2(-g * 0.35, -g * 0.6),
		c + Vector2(g * 0.55, -g * 0.3),
		c + Vector2(-g * 0.35, -g * 0.02),
	])
	draw_colored_polygon(flag, col)


func _draw_branch_letter(pos: Vector2, variant: int, col: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 16
	var txt: String = "A" if variant == 0 else "B"
	var sz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font, pos - Vector2(sz.x * 0.5, -sz.y * 0.3),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_badge(center: Vector2, radius: float) -> void:
	var badge_pos: Vector2 = center + Vector2(radius * 0.58, radius * 0.58)
	var br: float = 15.0
	draw_circle(badge_pos, br, _badge_color)
	draw_arc(badge_pos, br, 0.0, TAU, 20, Color(0.08, 0.08, 0.1), 1.5)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_size: Vector2 = font.get_string_size(_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos: Vector2 = badge_pos - Vector2(text_size.x * 0.5, -text_size.y * 0.3)
	draw_string(
		font, text_pos, _badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(0.05, 0.05, 0.05))
