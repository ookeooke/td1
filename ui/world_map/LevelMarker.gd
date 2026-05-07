@tool
extends Button
class_name LevelMarker

# WorldMap level marker — banner-on-post procedural visual.
# Variants chosen from (unlocked, total_stars):
#   locked            → grey shield + chain
#   unlocked, 0★      → red banner + level number
#   unlocked, 1–4★    → adds gold filled stars under the banner
#   unlocked, 5★ (3 campaign + heroic + iron) → adds gold "wings"
#
# Drawing is local to (0,0)..(custom_minimum_size). The marker is positioned
# by WorldMapView (its parent) at the level's authored Marker2D position
# minus this size/2 (so the centre of the banner sits over the marker).

const MARKER_SIZE: Vector2 = Vector2(96, 128)

const COLOR_POST_WOOD: Color = Color(0.42, 0.27, 0.17, 1.0)
const COLOR_POST_GREY: Color = Color(0.45, 0.45, 0.45, 1.0)
const COLOR_BANNER_RED: Color = Color(0.62, 0.18, 0.16, 1.0)
const COLOR_BANNER_DARK: Color = Color(0.32, 0.10, 0.10, 1.0)
const COLOR_BANNER_GREY: Color = Color(0.55, 0.55, 0.55, 1.0)
const COLOR_BANNER_GREY_DARK: Color = Color(0.32, 0.32, 0.32, 1.0)
const COLOR_STAR_GOLD: Color = Color(1.0, 0.84, 0.20, 1.0)
const COLOR_STAR_EMPTY: Color = Color(0.45, 0.40, 0.30, 1.0)
const COLOR_WING_GOLD: Color = Color(0.95, 0.78, 0.20, 1.0)
const COLOR_WING_DARK: Color = Color(0.55, 0.40, 0.10, 1.0)
const COLOR_CHAIN: Color = Color(0.25, 0.22, 0.20, 1.0)
const COLOR_NUMBER: Color = Color(1.0, 0.94, 0.78, 1.0)
const COLOR_NUMBER_LOCKED: Color = Color(0.75, 0.75, 0.75, 1.0)

var _level_number: int = 1
var _unlocked: bool = false
var _total_stars: int = 0       # 0..5 composite (campaign 0-3 + heroic + iron)
var _pulse_tween: Tween = null


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = MARKER_SIZE
	pivot_offset = MARKER_SIZE * 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Repositioning markers is done by dragging the authored Marker2D nodes
	# under WorldMapView/LevelMarkers in the 2D editor (W move tool). The
	# Button visuals here are runtime-instantiated and not directly editable.


func set_state(level_number: int, unlocked: bool, total_stars: int) -> void:
	_level_number = level_number
	_unlocked = unlocked
	_total_stars = clampi(total_stars, 0, 5)
	queue_redraw()


# Looping scale pulse to nudge the player toward the recommended next level
# (lowest-unlock_order unlocked level with 0 campaign stars). WorldMapView
# computes the target and toggles this on exactly one marker; callers must
# disable on the previously-pulsing marker themselves.
func set_pulse(active: bool) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if not active:
		scale = Vector2.ONE
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _draw() -> void:
	var w: float = MARKER_SIZE.x
	var h: float = MARKER_SIZE.y

	# 1. Wooden post — vertical rectangle anchored to the bottom center.
	var post_w: float = 8.0
	var post_h: float = 38.0
	var post_x: float = (w - post_w) * 0.5
	var post_y: float = h - post_h
	var post_color: Color = COLOR_POST_GREY if not _unlocked else COLOR_POST_WOOD
	draw_rect(Rect2(post_x, post_y, post_w, post_h), post_color)
	# Post-cap shadow (a thin darker stripe down the right edge sells the
	# round-wood feel at a glance).
	draw_rect(Rect2(post_x + post_w - 2.0, post_y, 2.0, post_h), post_color.darkened(0.25))

	# 2. Wings (drawn behind banner) — only when 5★ and unlocked.
	if _unlocked and _total_stars >= 5:
		_draw_wings(Vector2(w * 0.5, 36.0))

	# 3. Banner shield — trapezoid with a downward-pointing notch at the
	# bottom. Sits on top of the post, slightly overlapping it.
	var banner_top: float = 24.0
	var banner_bottom: float = post_y + 6.0
	var banner_top_half: float = 28.0
	var banner_bot_half: float = 22.0
	var cx: float = w * 0.5
	var banner_color: Color = COLOR_BANNER_RED if _unlocked else COLOR_BANNER_GREY
	var banner_dark: Color = COLOR_BANNER_DARK if _unlocked else COLOR_BANNER_GREY_DARK
	var shield: PackedVector2Array = PackedVector2Array([
		Vector2(cx - banner_top_half, banner_top),
		Vector2(cx + banner_top_half, banner_top),
		Vector2(cx + banner_bot_half, banner_bottom),
		Vector2(cx, banner_bottom + 10.0),  # bottom point (shield notch)
		Vector2(cx - banner_bot_half, banner_bottom),
	])
	draw_colored_polygon(shield, banner_color)
	# Outline.
	for i in range(shield.size()):
		var a: Vector2 = shield[i]
		var b: Vector2 = shield[(i + 1) % shield.size()]
		draw_line(a, b, banner_dark, 2.0)

	# 4. Level number on the banner (always visible, dimmed when locked).
	var num_color: Color = COLOR_NUMBER if _unlocked else COLOR_NUMBER_LOCKED
	var num_str: String = str(_level_number)
	var font: Font = get_theme_default_font()
	var font_size: int = 22
	var ascent: float = font.get_ascent(font_size)
	var num_size: Vector2 = font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var num_pos: Vector2 = Vector2(cx - num_size.x * 0.5, banner_top + (banner_bottom - banner_top + 10.0) * 0.5 - num_size.y * 0.5 + ascent)
	draw_string(font, num_pos, num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, num_color)

	# 5. Stars row — drawn above the banner. Always 5 slots (3 campaign +
	# heroic + iron) so the player reads earned-vs-max at a glance, like KR.
	if _unlocked:
		_draw_star_row(Vector2(cx, banner_top - 18.0), _total_stars)

	# 6. Locked overlay — chain across the shield.
	if not _unlocked:
		_draw_chain(Vector2(cx, banner_top + 4.0), Vector2(cx, banner_bottom + 6.0))


func _draw_star_row(center_top: Vector2, filled: int) -> void:
	# Always 5 slots, centered around center_top. First `filled` are gold;
	# the rest render as outlined empties so the marker reads "X / 5".
	var slots: int = 5
	var r_outer: float = 10.4
	var spacing: float = 22.0
	var total_w: float = float(slots - 1) * spacing
	var x: float = center_top.x - total_w * 0.5
	for i in range(slots):
		if i < filled:
			_draw_star(Vector2(x, center_top.y), r_outer, COLOR_STAR_GOLD)
		else:
			_draw_star_outline(Vector2(x, center_top.y), r_outer, COLOR_STAR_EMPTY)
		x += spacing


func _draw_star(center: Vector2, r_outer: float, color: Color) -> void:
	# Five-point star — alternates outer and inner radii at 36° intervals.
	# Pre-rotated -90° so the top point faces up.
	var r_inner: float = r_outer * 0.45
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var ang: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = r_outer if (i % 2 == 0) else r_inner
		pts.append(center + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, color)


func _draw_star_outline(center: Vector2, r_outer: float, color: Color) -> void:
	# Same shape as _draw_star but stroked, not filled — empty-slot variant.
	var r_inner: float = r_outer * 0.45
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var ang: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = r_outer if (i % 2 == 0) else r_inner
		pts.append(center + Vector2(cos(ang), sin(ang)) * rr)
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, color, 1.8)


func _draw_wings(banner_top_center: Vector2) -> void:
	# Two mirrored gold "wings" flanking the banner. Each wing is a short
	# fan of feathers drawn as a polygon — kept minimal so it reads at
	# a glance without overwhelming the banner.
	var feather_count: int = 4
	for side_idx in range(2):
		var dir: float = -1.0 if side_idx == 0 else 1.0
		var origin: Vector2 = banner_top_center + Vector2(dir * 22.0, 4.0)
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(origin)
		for i in range(feather_count + 1):
			var t: float = float(i) / float(feather_count)
			var ang: float = lerp(-0.25, -1.05, t) if dir > 0.0 else lerp(PI + 0.25, PI + 1.05, t)
			var rr: float = 18.0 + sin(t * PI) * 4.0
			pts.append(origin + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(pts, COLOR_WING_GOLD)
		# Outline for definition.
		for i in range(pts.size()):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			draw_line(a, b, COLOR_WING_DARK, 1.5)


func _draw_chain(top: Vector2, bottom: Vector2) -> void:
	# Two diagonals + four small circles for "chained shut".
	draw_line(top + Vector2(-18, 0), bottom + Vector2(18, 0), COLOR_CHAIN, 3.0)
	draw_line(top + Vector2(18, 0), bottom + Vector2(-18, 0), COLOR_CHAIN, 3.0)
	for i in range(4):
		var t: float = (float(i) + 0.5) / 4.0
		var p1: Vector2 = top.lerp(bottom, t) + Vector2(lerp(-18.0, 18.0, t), 0)
		var p2: Vector2 = top.lerp(bottom, t) + Vector2(lerp(18.0, -18.0, t), 0)
		draw_circle(p1, 3.0, COLOR_CHAIN)
		draw_circle(p2, 3.0, COLOR_CHAIN)
