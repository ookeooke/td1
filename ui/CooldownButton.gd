extends Control

# Phase 20 cooldown button.
# Draws a colored placeholder tile with the provider's display name, plus
# a radial cooldown overlay that shrinks a dark pie-slice over the button
# as the cooldown counts down. Per CLAUDE.md: radial fill, not text.
#
# Emits `triggered(idx)` when tapped. SkillBar handles turning that into
# targeting mode and ultimately a cast. Driven by a duck-typed provider
# Node (BaseHero today) with:
#   cooldown_fraction(idx) -> float   (0 = ready, 1 = just fired)
#   display_name(idx) -> String
#
# We don't use a regular Button because we need a full-area custom _draw
# for the overlay and the label.

signal triggered(idx: int)

const MIN_SIZE: Vector2 = Vector2(80.0, 80.0)

# Provider-agnostic: anything with `cooldown_fraction(idx) -> float` and
# `display_name(idx) -> String` can drive this button. Hero uses it for
# skills today.
var _provider: Node = null
var _idx: int = -1
var _last_fraction: float = -1.0
# Tracked separately so the ready / not-ready transition always redraws,
# even when float tolerance would otherwise skip the diff. Without this,
# a fraction that drifts to (0, ε) one frame and clamps to 0 the next
# leaves _last_fraction inside is_equal_approx tolerance of 0, so the
# transition redraw is skipped and the button stays in its dark
# COOLDOWN_ACTIVE base color forever.
var _last_is_ready: bool = false
# Armed = SkillBar has selected this skill for ground-targeting and is
# waiting for the player's confirm tap. We render a bright pulsing yellow
# ring around the button so the player sees "I picked this, now tap a
# target." Set by SkillBar via set_armed().
var _armed: bool = false


func setup(provider: Node, idx: int) -> void:
	_provider = provider
	_idx = idx
	custom_minimum_size = MIN_SIZE


# SkillBar calls this when the player taps the button to enter targeting
# mode (and again with false on cast/cancel). Drives the bright pulsing
# armed ring drawn in _draw().
func set_armed(armed: bool) -> void:
	if _armed == armed:
		return
	_armed = armed
	queue_redraw()


func refresh() -> void:
	# Called every frame by SkillBar — redraw only when cooldown fraction
	# visibly changes (UI cost is tiny, still worth gating). When armed,
	# always redraw so the pulse animates smoothly.
	var f: float = _cooldown_fraction()
	var now_ready: bool = f <= 0.0
	if _armed:
		queue_redraw()
		_last_fraction = f
		_last_is_ready = now_ready
		return
	if now_ready != _last_is_ready or not is_equal_approx(f, _last_fraction):
		_last_is_ready = now_ready
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
	var center: Vector2 = size * 0.5
	# Round button — radius is half the smaller dimension so the circle
	# inscribes the layout box. Mirrors EmptySkillSlot's circular shape so
	# every slot in the cluster reads as a round disk regardless of state
	# (ready, active, empty).
	var radius: float = minf(size.x, size.y) * 0.5
	var is_ready: bool = _cooldown_fraction() <= 0.0
	var base: Color = ThemeColors.COOLDOWN_READY if is_ready else ThemeColors.COOLDOWN_ACTIVE
	draw_circle(center, radius, base)
	draw_arc(center, radius, 0.0, TAU, 32, ThemeColors.COOLDOWN_BORDER, 2.0, true)

	# Radial cooldown overlay — pie slice that starts full on cast and
	# shrinks counter-clockwise as the cooldown drains. Radius matches the
	# button circle so the overlay never spills past the visible disk.
	var frac: float = _cooldown_fraction()
	if frac > 0.0:
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

	# Armed ring — drawn LAST so it sits above the cooldown overlay and
	# label. Bright yellow, slightly outside the button's silhouette, with
	# a soft pulsing outer halo so the player's eye is drawn here while
	# they pick a target on the map. Cleared by SkillBar on cast/cancel.
	if _armed:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		var ring_color: Color = Color(1.0, 0.9, 0.35, 0.85 + pulse * 0.15)
		var halo_color: Color = Color(1.0, 0.9, 0.35, 0.10 + pulse * 0.18)
		# Outer halo — fat soft ring just outside the button.
		draw_arc(center, radius + 8.0 + pulse * 3.0, 0.0, TAU, 36, halo_color, 6.0, true)
		# Crisp inner accent ring on the button rim.
		draw_arc(center, radius + 2.0, 0.0, TAU, 36, ring_color, 3.0, true)
