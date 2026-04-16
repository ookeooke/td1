extends Control

# Phase 20 cooldown button (Phase 22: generalized for spells too).
# Draws a colored placeholder tile with the provider's display name, plus
# a radial cooldown overlay that shrinks a dark pie-slice over the button
# as the cooldown counts down. Per CLAUDE.md: radial fill, not text.
#
# Emits `triggered(idx)` when tapped. The owning panel (SkillBar / SpellPanel)
# handles turning that into targeting mode and ultimately a cast. Driven by
# a duck-typed provider Node with:
#   cooldown_fraction(idx) -> float   (0 = ready, 1 = just fired)
#   display_name(idx) -> String
#
# We don't use a regular Button because we need a full-area custom _draw
# for the overlay and the label.

signal triggered(idx: int)

const MIN_SIZE: Vector2 = Vector2(80.0, 80.0)

# Provider-agnostic: anything with `cooldown_fraction(idx) -> float` and
# `display_name(idx) -> String` can drive this button. Hero uses it for
# skills; SpellPanel uses it for spells.
var _provider: Node = null
var _idx: int = -1
var _last_fraction: float = -1.0


func setup(provider: Node, idx: int) -> void:
	_provider = provider
	_idx = idx
	custom_minimum_size = MIN_SIZE


func refresh() -> void:
	# Called every frame by SkillBar — redraw only when cooldown fraction
	# visibly changes (UI cost is tiny, still worth gating).
	var f: float = _cooldown_fraction()
	if not is_equal_approx(f, _last_fraction):
		_last_fraction = f
		queue_redraw()


func _cooldown_fraction() -> float:
	if _provider == null or not is_instance_valid(_provider):
		return 0.0
	if _provider.has_method("cooldown_fraction"):
		return _provider.cooldown_fraction(_idx)
	return 0.0


func _display_name() -> String:
	if _provider == null or not _provider.has_method("display_name"):
		return "?"
	return str(_provider.display_name(_idx))


func _gui_input(event: InputEvent) -> void:
	# Use _gui_input (Control-native) so the backdrop-style modal stacks
	# above the button correctly — taps on UI always hit the UI first.
	if event is InputEventScreenTouch and event.pressed:
		accept_event()
		triggered.emit(_idx)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var is_ready: bool = _cooldown_fraction() <= 0.0
	var base: Color = Color(0.85, 0.4, 0.15) if is_ready else Color(0.35, 0.2, 0.1)
	draw_rect(rect, base)
	draw_rect(rect, Color(0.1, 0.05, 0.0), false, 2.0)

	# Radial cooldown overlay — pie slice that starts full on cast and
	# shrinks counter-clockwise as the cooldown drains. Dark so the tile
	# below stays readable.
	var frac: float = _cooldown_fraction()
	if frac > 0.0:
		var center: Vector2 = size * 0.5
		var radius: float = maxf(size.x, size.y)
		var start: float = -PI * 0.5  # 12 o'clock
		var end: float = start + TAU * frac
		var points: PackedVector2Array = PackedVector2Array()
		points.append(center)
		var steps: int = 32
		for i in steps + 1:
			var t: float = float(i) / float(steps)
			var angle: float = lerp(start, end, t)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, Color(0.0, 0.0, 0.0, 0.55))

	# Name label — drawn manually so it appears above both the tile and
	# the overlay. Centered, simple.
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 18
	var text: String = _display_name()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos: Vector2 = Vector2(size.x * 0.5 - text_size.x * 0.5, size.y * 0.5 + font_size * 0.35)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
