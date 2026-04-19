extends Camera2D

# Camera2D with gesture-based pan, pinch-to-zoom, mouse wheel zoom,
# double-tap reset, and tap dispatch via EventBus.map_tap_confirmed.
#
# Sits in _unhandled_input — _input-phase handlers (SkillBar, SpellPanel,
# TowerBarracks rally, TowerSpotMenu) consume events before this script
# ever sees them. Only unhandled map touches reach the gesture classifier.
#
# When a touch is classified as a tap, the camera does NOT consume it
# directly. Instead it emits EventBus.map_tap_confirmed(screen_pos, claim)
# so SpotInputManager, BaseHero, and HeroInputManager can handle it via
# their signal connections (priority = connection order).

class TapClaim extends RefCounted:
	var claimed: bool = false

# ── Constants ────────────────────────────────────────────────────────────

const TAP_MAX_DISTANCE: float = 12.0      # px — must stay within for tap
const TAP_MAX_DURATION: float = 0.3       # seconds
const PAN_MIN_DISTANCE: float = 12.0      # px — must move this far to pan
const ZOOM_MIN: float = 0.5              # max zoom-out (see 2x area)
const ZOOM_MAX: float = 2.0              # max zoom-in (see 0.5x area)
const ZOOM_SPEED_WHEEL: float = 0.1      # per scroll tick (PC)
const ZOOM_SPEED_PINCH: float = 0.005    # multiplied by pixel-distance delta
const DOUBLE_TAP_WINDOW: float = 0.3     # seconds between taps
const DOUBLE_TAP_DISTANCE: float = 30.0  # px — must be near first tap
const BLEED_MARGIN: float = 125.0        # extra world px beyond map_bounds
const PAN_DECEL: float = 8.0             # momentum decay rate
const RESET_TWEEN_DURATION: float = 0.3  # double-tap reset animation

# ── State ────────────────────────────────────────────────────────────────

enum GestureState { IDLE, PENDING, PANNING, PINCHING }

var _state: int = GestureState.IDLE
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_start_time: float = 0.0
var _last_touch_pos: Vector2 = Vector2.ZERO
var _finger_positions: Dictionary = {}     # finger index → screen Vector2

# Pinch
var _pinch_start_distance: float = 0.0
var _pinch_start_zoom: float = 1.0

# Double-tap
var _last_tap_time: float = -1000.0
var _last_tap_pos: Vector2 = Vector2.ZERO

# Momentum
var _velocity: Vector2 = Vector2.ZERO
var _momentum_active: bool = false

# Shake — additive offset perturbation that decays to zero. Applied every
# _process frame. Tactical pause freezes shake because _process respects
# PROCESS_MODE_INHERIT.
var _shake_t: float = 0.0
var _shake_dur0: float = 0.0
var _shake_amp: float = 0.0

# Map bounds — set by the level (Level1.map_bounds). Defaults to the
# standard 375x812 design viewport.
var map_bounds: Rect2 = Rect2(0, 0, 1920, 1080)

# Reference zoom level that fits the entire map. Computed in _ready().
var _fit_zoom: float = 1.0

# Tween for smooth reset
var _reset_tween: Tween = null


func _ready() -> void:
	# Listen for viewport resize to recalculate fit zoom.
	get_viewport().size_changed.connect(_on_viewport_resized)
	EventBus.camera_focus_requested.connect(_on_focus_requested)
	_compute_fit_zoom()
	_center_on_map()


func _on_viewport_resized() -> void:
	_compute_fit_zoom()
	_clamp_to_bounds()


func _process(delta: float) -> void:
	if _shake_t <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_shake_t = maxf(0.0, _shake_t - delta)
	var decay: float = _shake_t / maxf(0.001, _shake_dur0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp * decay


func add_shake(amount: float, duration: float) -> void:
	# Only overwrite the current shake if the new one is stronger, or the
	# previous is almost done — stacking tiny shakes otherwise turns into a
	# constant jitter during sustained boss damage.
	if amount > _shake_amp or _shake_t < 0.05:
		_shake_amp = amount
		_shake_t = duration
		_shake_dur0 = duration


func configure_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
	_compute_fit_zoom()
	_center_on_map()


func _compute_fit_zoom() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if map_bounds.size.x <= 0 or map_bounds.size.y <= 0:
		_fit_zoom = 1.0
		return
	# Fit zoom = the zoom level at which the full map fits in the viewport.
	# We pick the axis that requires more zoom-out so nothing is clipped.
	var zoom_x: float = vp_size.x / map_bounds.size.x
	var zoom_y: float = vp_size.y / map_bounds.size.y
	_fit_zoom = minf(zoom_x, zoom_y)
	# Clamp fit_zoom so we never zoom out past ZOOM_MIN.
	_fit_zoom = maxf(_fit_zoom, ZOOM_MIN)


func _center_on_map() -> void:
	position = map_bounds.position + map_bounds.size * 0.5
	# If the map fits on screen at 1:1, use fit_zoom (centers small maps).
	# If the map is BIGGER than the viewport, start at 1:1 and let the player pan.
	var vp_size: Vector2 = get_viewport_rect().size
	if map_bounds.size.x <= vp_size.x and map_bounds.size.y <= vp_size.y:
		zoom = Vector2(_fit_zoom, _fit_zoom)
	else:
		zoom = Vector2(1.0, 1.0)
	_clamp_to_bounds()


# ── Zoom helper ──────────────────────────────────────────────────────────

static func get_zoom_scale() -> float:
	# Returns inverse of current camera zoom for use by _draw() methods
	# that want screen-constant sizes. Call from any node.
	var vp: Viewport = Engine.get_main_loop().root
	if vp == null:
		return 1.0
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x


# ── Physics process — momentum ───────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _momentum_active:
		return
	_velocity = _velocity.lerp(Vector2.ZERO, PAN_DECEL * delta)
	if _velocity.length_squared() < 1.0:
		_velocity = Vector2.ZERO
		_momentum_active = false
		return
	position -= _velocity * delta
	_clamp_to_bounds()


# ── Input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom (PC).
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, ZOOM_SPEED_WHEEL)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, -ZOOM_SPEED_WHEEL)
				get_viewport().set_input_as_handled()
				return

	# Touch events.
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_positions[event.index] = event.position
		else:
			_finger_positions.erase(event.index)

		match _state:
			GestureState.IDLE:
				if event.pressed and event.index == 0:
					_start_pending(event.position)
					get_viewport().set_input_as_handled()
			GestureState.PENDING:
				if event.pressed and event.index == 1:
					_start_pinch()
					get_viewport().set_input_as_handled()
				elif not event.pressed and event.index == 0:
					_resolve_pending()
					get_viewport().set_input_as_handled()
			GestureState.PANNING:
				if not event.pressed and event.index == 0:
					_end_pan()
					get_viewport().set_input_as_handled()
			GestureState.PINCHING:
				if _finger_positions.size() < 2:
					_end_pinch()
					get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		_finger_positions[event.index] = event.position

		match _state:
			GestureState.PENDING:
				if event.index == 0:
					var moved: float = event.position.distance_to(_touch_start_pos)
					if moved > PAN_MIN_DISTANCE:
						_start_pan(event.position)
				get_viewport().set_input_as_handled()
			GestureState.PANNING:
				if event.index == 0:
					_update_pan(event.position)
				get_viewport().set_input_as_handled()
			GestureState.PINCHING:
				_update_pinch()
				get_viewport().set_input_as_handled()
		return


# ── Gesture states ───────────────────────────────────────────────────────

func _start_pending(screen_pos: Vector2) -> void:
	_state = GestureState.PENDING
	_touch_start_pos = screen_pos
	_touch_start_time = _now()
	_last_touch_pos = screen_pos
	_momentum_active = false
	_velocity = Vector2.ZERO


func _resolve_pending() -> void:
	# Finger went down and came back up without moving far — classify.
	var elapsed: float = _now() - _touch_start_time
	var moved: float = _last_touch_pos.distance_to(_touch_start_pos)
	_state = GestureState.IDLE
	_finger_positions.clear()

	if elapsed <= TAP_MAX_DURATION and moved <= TAP_MAX_DISTANCE:
		# Check double-tap BEFORE updating last-tap state.
		var since_last: float = _now() - _last_tap_time
		var tap_dist: float = _touch_start_pos.distance_to(_last_tap_pos)
		var is_double: bool = since_last <= DOUBLE_TAP_WINDOW and tap_dist <= DOUBLE_TAP_DISTANCE

		if is_double:
			_last_tap_time = -1000.0  # prevent triple-tap
			_last_tap_pos = Vector2.ZERO
			_double_tap_reset()
			return

		# Record this tap for future double-tap detection.
		_last_tap_time = _now()
		_last_tap_pos = _touch_start_pos

		# Single tap — dispatch to game handlers.
		var claim: TapClaim = TapClaim.new()
		EventBus.map_tap_confirmed.emit(_touch_start_pos, claim)


# ── Pan ──────────────────────────────────────────────────────────────────

func _start_pan(screen_pos: Vector2) -> void:
	_state = GestureState.PANNING
	_last_touch_pos = screen_pos
	_momentum_active = false
	_velocity = Vector2.ZERO
	# Kill any active reset tween.
	if _reset_tween != null and _reset_tween.is_running():
		_reset_tween.kill()
		_reset_tween = null


func _update_pan(screen_pos: Vector2) -> void:
	var delta_screen: Vector2 = screen_pos - _last_touch_pos
	# Convert screen delta to world delta (inverse zoom).
	var delta_world: Vector2 = delta_screen / zoom.x
	position -= delta_world
	# Store velocity in world units per second for momentum.
	var dt: float = get_physics_process_delta_time()
	if dt > 0.0:
		_velocity = delta_world / dt
	_last_touch_pos = screen_pos
	_clamp_to_bounds()


func _end_pan() -> void:
	_state = GestureState.IDLE
	# Start momentum if velocity is meaningful (world units/sec).
	if _velocity.length_squared() > 400.0:
		_momentum_active = true
	else:
		_velocity = Vector2.ZERO


# ── Pinch zoom ───────────────────────────────────────────────────────────

func _start_pinch() -> void:
	_state = GestureState.PINCHING
	_momentum_active = false
	_velocity = Vector2.ZERO
	_pinch_start_distance = _current_pinch_distance()
	_pinch_start_zoom = zoom.x
	if _reset_tween != null and _reset_tween.is_running():
		_reset_tween.kill()
		_reset_tween = null


func _update_pinch() -> void:
	if _finger_positions.size() < 2:
		return
	var curr_dist: float = _current_pinch_distance()
	if _pinch_start_distance <= 0.01:
		return
	var scale_factor: float = curr_dist / _pinch_start_distance
	var new_zoom: float = clampf(_pinch_start_zoom * scale_factor, ZOOM_MIN, ZOOM_MAX)
	# Zoom centered on midpoint between fingers.
	var midpoint: Vector2 = _pinch_midpoint()
	var world_before: Vector2 = _screen_to_world(midpoint)
	zoom = Vector2(new_zoom, new_zoom)
	var world_after: Vector2 = _screen_to_world(midpoint)
	position += world_before - world_after
	_clamp_to_bounds()


func _end_pinch() -> void:
	_state = GestureState.IDLE
	_finger_positions.clear()


func _current_pinch_distance() -> float:
	var keys: Array = _finger_positions.keys()
	if keys.size() < 2:
		return 0.0
	return (_finger_positions[keys[0]] as Vector2).distance_to(_finger_positions[keys[1]] as Vector2)


func _pinch_midpoint() -> Vector2:
	var keys: Array = _finger_positions.keys()
	if keys.size() < 2:
		return Vector2.ZERO
	return ((_finger_positions[keys[0]] as Vector2) + (_finger_positions[keys[1]] as Vector2)) * 0.5


# ── Zoom at point ────────────────────────────────────────────────────────

func _zoom_at(screen_pos: Vector2, zoom_delta: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom + zoom_delta, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	# Keep content under cursor/finger stable.
	var world_before: Vector2 = _screen_to_world(screen_pos)
	zoom = Vector2(new_zoom, new_zoom)
	var world_after: Vector2 = _screen_to_world(screen_pos)
	position += world_before - world_after
	_clamp_to_bounds()


# ── Double-tap reset ─────────────────────────────────────────────────────

func _double_tap_reset() -> void:
	if _reset_tween != null and _reset_tween.is_running():
		_reset_tween.kill()
	var target_pos: Vector2 = map_bounds.position + map_bounds.size * 0.5
	var target_zoom: float = _fit_zoom
	_reset_tween = create_tween().set_parallel(true)
	_reset_tween.tween_property(self, "position", target_pos, RESET_TWEEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_reset_tween.tween_property(self, "zoom", Vector2(target_zoom, target_zoom), RESET_TWEEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# ── Focus request (for future auto-pan) ─────────────────────────────────

func _on_focus_requested(world_pos: Vector2, duration: float) -> void:
	if _reset_tween != null and _reset_tween.is_running():
		_reset_tween.kill()
	_momentum_active = false
	_velocity = Vector2.ZERO
	if duration <= 0.0:
		position = world_pos
		_clamp_to_bounds()
		return
	_reset_tween = create_tween()
	_reset_tween.tween_property(self, "position", world_pos, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


# ── Bounds clamping ──────────────────────────────────────────────────────

func _clamp_to_bounds() -> void:
	var vp_size: Vector2 = get_viewport_rect().size / zoom.x
	var half_vp: Vector2 = vp_size * 0.5
	var bounds_min: Vector2 = map_bounds.position - Vector2(BLEED_MARGIN, BLEED_MARGIN)
	var bounds_max: Vector2 = map_bounds.end + Vector2(BLEED_MARGIN, BLEED_MARGIN)
	# If viewport is larger than bounds (map fits on screen), center it.
	if vp_size.x >= (bounds_max.x - bounds_min.x):
		position.x = (bounds_min.x + bounds_max.x) * 0.5
	else:
		position.x = clampf(position.x, bounds_min.x + half_vp.x, bounds_max.x - half_vp.x)
	if vp_size.y >= (bounds_max.y - bounds_min.y):
		position.y = (bounds_min.y + bounds_max.y) * 0.5
	else:
		position.y = clampf(position.y, bounds_min.y + half_vp.y, bounds_max.y - half_vp.y)


# ── Helpers ──────────────────────────────────────────────────────────────

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
