extends Control

# Phase 45a: radial slot button for TowerRadialMenu. Procedural _draw()
# pictogram + cost badge + affordability state. Lives as a child of the
# menu's Anchor node — positioned absolutely by the parent menu.
#
# Signals a tap (build request) and press-in/press-out for range preview.

signal pressed(tower_id: String)

const SIZE_PX: float = 90.0

var _data: Resource = null  # TowerData
var _tower_id: String = ""
var _world_pos: Vector2 = Vector2.ZERO
var _affordable: bool = true
var _is_pressed: bool = false
var _is_mouse_over: bool = false
# Armed = first tap has selected this slot; next tap on the SAME slot
# commits. Driven by TowerRadialMenu.
var _armed: bool = false
# Phase 47d-3: a locked slot renders a padlock + dimmed body and emits
# `locked_pressed` instead of `pressed` when tapped. No TowerData attached.
var _locked: bool = false
# Phase 47d-4: display-only mode (used in LoadoutScreen / picker read-only
# previews). Consumes input so nothing happens on tap without emitting.
var _display_only: bool = false
# Phase 47d-4: "equipped" badge + dim on pool icons that are already in the
# player's loadout.
var _equipped: bool = false

signal locked_pressed


func get_world_pos() -> Vector2:
	return _world_pos


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


func setup(data: Resource, world_pos: Vector2) -> void:
	_data = data
	_tower_id = data.tower_id if data != null else ""
	_world_pos = world_pos
	_locked = false
	refresh_affordability()


func setup_locked() -> void:
	# Phase 47d-3: placeholder slot for a not-yet-unlocked loadout position.
	# No TowerData, no cost badge, no armed/affordable state — just a
	# padlock that emits `locked_pressed` on tap.
	_data = null
	_tower_id = ""
	_locked = true
	_affordable = false
	queue_redraw()


func setup_display(data: Resource) -> void:
	# Phase 47d-4: read-only icon for LoadoutScreen's tower row. Same visuals
	# as a normal slot (with optional equipped dim/badge), but swallows input.
	_data = data
	_tower_id = data.tower_id if data != null else ""
	_locked = false
	_display_only = true
	_affordable = true
	queue_redraw()


func setup_pool(data: Resource) -> void:
	# Phase 47d-6: LoadoutPickerScreen pool icon. Same visual as the in-game
	# build ring but AFFORDABILITY IS IGNORED — the player isn't spending
	# gold, they're picking which towers they'll carry into the next run.
	# Without this, pool icons costing more than current gold silently
	# swallow taps (the `if not _affordable` gate in _gui_input).
	_data = data
	_tower_id = data.tower_id if data != null else ""
	_locked = false
	_display_only = false
	_affordable = true
	queue_redraw()


func set_equipped(on: bool) -> void:
	if _equipped == on:
		return
	_equipped = on
	queue_redraw()


func refresh_affordability() -> void:
	if _data == null:
		return
	_affordable = RunState.gold >= int(_data.cost)
	queue_redraw()


func is_affordable() -> bool:
	return _affordable


func _gui_input(event: InputEvent) -> void:
	# Touch-only per CLAUDE.md. Project has emulate_touch_from_mouse=true, so
	# mouse clicks arrive here as InputEventScreenTouch. Handling both event
	# types would double-fire `pressed` on PC and break the two-step commit.
	if _display_only:
		return
	if not (event is InputEventScreenTouch):
		return
	var was_inside: bool = Rect2(Vector2.ZERO, size).has_point(event.position)
	if _locked:
		if event.pressed:
			_is_pressed = true
			queue_redraw()
		else:
			_is_pressed = false
			queue_redraw()
			if was_inside:
				locked_pressed.emit()
		return
	if _data == null:
		return
	# Affordability is enforced on RELEASE rather than at function entry so
	# unaffordable taps still feel registered: the press visual fires, and on
	# release we emit `purchase_denied` so HUD/SFX/local jiggle can react.
	if event.pressed:
		_is_pressed = true
		queue_redraw()
	else:
		_is_pressed = false
		queue_redraw()
		if was_inside:
			if _affordable:
				pressed.emit(_tower_id)
			else:
				EventBus.purchase_denied.emit("not_enough_gold")
				_play_deny_shake()


# Brief head-shake jiggle so the player's tap feels acknowledged even when
# the action was rejected. Tween targets `rotation` (post-layout transform —
# safe inside a Container) so it doesn't fight whatever is positioning us.
var _deny_tween: Tween = null
func _play_deny_shake() -> void:
	if _deny_tween != null and _deny_tween.is_valid():
		_deny_tween.kill()
	rotation = 0.0
	_deny_tween = create_tween()
	_deny_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_deny_tween.tween_property(self, "rotation", 0.10, 0.05)
	_deny_tween.tween_property(self, "rotation", -0.10, 0.07)
	_deny_tween.tween_property(self, "rotation", 0.05, 0.06)
	_deny_tween.tween_property(self, "rotation", 0.0, 0.05)


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

	# Locked variant — padlock on a dim body, no badge, no hover glow.
	if _locked:
		draw_circle(center, r, Color(0.22, 0.22, 0.28, 1.0))
		draw_arc(center, r, 0.0, TAU, 48, Color(0.08, 0.08, 0.1, 0.9), 2.5)
		# Reuse `_draw_pictogram` with a synthetic "padlock" override.
		var locked_glyph: Color = Color(0.7, 0.7, 0.75, 1.0)
		_draw_glyph(center, r, "padlock", locked_glyph, Color(0.08, 0.08, 0.1, 1.0))
		return

	if _data == null:
		return
	var alpha: float = 1.0 if _affordable else 0.55
	if _equipped:
		alpha *= 0.55  # pool icons already in the loadout dim to read as taken
	var base_color: Color = _data.body_color if _affordable else Color(0.45, 0.45, 0.5)
	base_color.a = alpha

	# Persistent glow when armed (first tap selected this slot); transient
	# glow when pressed/hovered. Armed reads stronger to signal the commit-
	# next-tap state.
	if _armed and _affordable:
		draw_circle(center, r + 7.0, Color(1.0, 0.95, 0.55, 0.45))
	elif (_is_mouse_over or _is_pressed) and _affordable and not _display_only:
		draw_circle(center, r + 5.0, Color(1.0, 0.95, 0.55, 0.28))

	# Inner body.
	draw_circle(center, r, base_color)
	# Border.
	draw_arc(center, r, 0.0, TAU, 48, Color(0.08, 0.08, 0.1, alpha), 2.5)

	_draw_pictogram(center, r, alpha)
	if not _display_only:
		_draw_cost_badge(center, r)
	if _equipped:
		_draw_equipped_badge(center, r)


func _draw_equipped_badge(center: Vector2, radius: float) -> void:
	# Small green checkmark in the top-left, signalling "already in your loadout".
	var badge_pos: Vector2 = center + Vector2(-radius * 0.58, -radius * 0.58)
	var br: float = 13.0
	draw_circle(badge_pos, br, Color(0.35, 0.75, 0.35, 1.0))
	draw_arc(badge_pos, br, 0.0, TAU, 20, Color(0.08, 0.08, 0.1), 1.5)
	# Check shape.
	var p0: Vector2 = badge_pos + Vector2(-br * 0.42, 0.0)
	var p1: Vector2 = badge_pos + Vector2(-br * 0.1, br * 0.38)
	var p2: Vector2 = badge_pos + Vector2(br * 0.5, -br * 0.36)
	draw_line(p0, p1, Color(0.05, 0.1, 0.05), 3.0)
	draw_line(p1, p2, Color(0.05, 0.1, 0.05), 3.0)


func _draw_pictogram(center: Vector2, radius: float, alpha: float) -> void:
	var white: Color = Color(1.0, 0.97, 0.88, alpha)
	var dark: Color = Color(0.12, 0.14, 0.2, alpha)
	# Phase 47d-1: dispatch on the data-driven `pictogram` key so multiple
	# towers can share a glyph ("bow" for any archer variant) and adding a
	# new tower needs zero edits here unless it wants a brand-new glyph.
	var glyph: String = "generic"
	if _data != null and "pictogram" in _data and String(_data.pictogram) != "":
		glyph = String(_data.pictogram)
	_draw_glyph(center, radius, glyph, white, dark)


func _draw_glyph(center: Vector2, radius: float, glyph: String, white: Color, dark: Color) -> void:
	var g: float = radius * 0.55  # glyph half-extent
	match glyph:
		"bow":
			# Bow arc + arrow.
			var bow_c: Vector2 = center + Vector2(-g * 0.25, 0.0)
			draw_arc(bow_c, g, -PI * 0.55, PI * 0.55, 14, white, 3.0)
			var a0: Vector2 = center + Vector2(-g * 0.1, g * 0.25)
			var a1: Vector2 = center + Vector2(g * 0.65, -g * 0.5)
			draw_line(a0, a1, white, 3.0)
			var dir: Vector2 = (a1 - a0).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_line(a1, a1 - dir * 9.0 + perp * 6.0, white, 3.0)
			draw_line(a1, a1 - dir * 9.0 - perp * 6.0, white, 3.0)
		"star":
			# 5-point star.
			var pts: PackedVector2Array = PackedVector2Array()
			for i in range(10):
				var ang: float = -PI * 0.5 + i * TAU / 10.0
				var rr: float = g if i % 2 == 0 else g * 0.42
				pts.append(center + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(pts, white)
		"cannon":
			# Cannonball + angled barrel.
			var ball_c: Vector2 = center + Vector2(-g * 0.35, g * 0.35)
			draw_circle(ball_c, g * 0.32, white)
			draw_arc(ball_c, g * 0.32, 0.0, TAU, 16, dark, 1.5)
			var angle: float = -PI * 0.32
			var dir2: Vector2 = Vector2(cos(angle), sin(angle))
			var perp2: Vector2 = Vector2(-dir2.y, dir2.x)
			var base: Vector2 = center + Vector2(-g * 0.1, g * 0.1)
			var blen: float = g * 1.1
			var bw: float = g * 0.28
			var quad: PackedVector2Array = PackedVector2Array([
				base + perp2 * bw,
				base - perp2 * bw,
				base + dir2 * blen - perp2 * bw,
				base + dir2 * blen + perp2 * bw,
			])
			draw_colored_polygon(quad, white)
		"shield":
			# Shield.
			var shield: PackedVector2Array = PackedVector2Array([
				center + Vector2(-g * 0.55, -g * 0.55),
				center + Vector2(g * 0.55, -g * 0.55),
				center + Vector2(g * 0.55, g * 0.1),
				center + Vector2(0.0, g * 0.8),
				center + Vector2(-g * 0.55, g * 0.1),
			])
			draw_colored_polygon(shield, white)
			# Crossed swords on top of shield.
			draw_line(
				center + Vector2(-g * 0.42, -g * 0.3),
				center + Vector2(g * 0.42, g * 0.3),
				dark, 3.5)
			draw_line(
				center + Vector2(g * 0.42, -g * 0.3),
				center + Vector2(-g * 0.42, g * 0.3),
				dark, 3.5)
		"snowflake":
			# 6-spoke snowflake with small perpendicular tips on each spoke.
			for i in range(6):
				var ang: float = (TAU / 6.0) * float(i)
				var dir: Vector2 = Vector2(cos(ang), sin(ang))
				var tip: Vector2 = center + dir * g * 0.85
				draw_line(center, tip, white, 3.5)
				# V-fork at the outer tip.
				var perp: Vector2 = Vector2(-dir.y, dir.x)
				var fork_back: Vector2 = tip - dir * g * 0.25
				draw_line(tip, fork_back + perp * g * 0.18, white, 2.5)
				draw_line(tip, fork_back - perp * g * 0.18, white, 2.5)
			# Small center hub so the spokes read as joined.
			draw_circle(center, g * 0.18, white)
		"padlock":
			# Padlock — body + shackle arc.
			var body_rect: Rect2 = Rect2(center + Vector2(-g * 0.45, -g * 0.05), Vector2(g * 0.9, g * 0.7))
			draw_rect(body_rect, white)
			draw_arc(center + Vector2(0, -g * 0.05), g * 0.38, PI, TAU, 16, white, 5.0)
			# Keyhole.
			draw_circle(center + Vector2(0, g * 0.2), g * 0.12, dark)
			draw_line(center + Vector2(0, g * 0.22), center + Vector2(0, g * 0.45), dark, 4.0)
		_:
			# Generic placeholder: filled circle.
			draw_circle(center, g * 0.5, white)


func _draw_cost_badge(center: Vector2, radius: float) -> void:
	if _data == null:
		return
	var badge_pos: Vector2 = center + Vector2(radius * 0.58, radius * 0.58)
	var br: float = 15.0
	var bg: Color = Color(0.95, 0.78, 0.22) if _affordable else Color(0.78, 0.26, 0.22)
	draw_circle(badge_pos, br, bg)
	draw_arc(badge_pos, br, 0.0, TAU, 20, Color(0.08, 0.08, 0.1), 1.5)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 15
	var cost_text: String = str(int(_data.cost))
	var text_size: Vector2 = font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos: Vector2 = badge_pos - Vector2(text_size.x * 0.5, -text_size.y * 0.3)
	draw_string(font, text_pos, cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.05, 0.05, 0.05))
