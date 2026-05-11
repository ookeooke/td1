extends CanvasLayer

# Diegetic Send-Wave badge anchored at each path's first curve-point in
# world space, projected to screen each frame, edge-clamped, and pushed
# out of HUD reserved zones. One round badge per path the NEXT wave will
# spawn from. Tap a badge (or press W on PC) to call the next wave early.
# WaveManager mechanics, gold bonus, and overlap behavior are unchanged —
# this is pure UI.
#
# States (per-frame):
#   HIDDEN — WaveManager.early_call_available() is false; nothing drawn.
#   PRE_W1 — level parked before wave 1; calm amber pulse, "start" glyph,
#            no bonus chip, no countdown ring.
#   OVERLAP_CALLABLE — inside the early-call window during current wave's
#                      spawn; hot orange pulse, double-chevron glyph,
#                      drain ring, +Ng chip, Ns readout.

const BADGE_RADIUS: float = 50.0          # screen px, gold rim circle
const RING_RADIUS: float = 60.0           # countdown ring radius (outside rim)
const RIM_THICKNESS: float = 6.0
const RING_THICKNESS: float = 5.0
const TAP_RADIUS: float = 80.0            # forgiving touch target — meets CLAUDE.md 80 px floor

# HUD reserved zones — clamp badges OUT of these rectangles so they don't
# collide with chips, pause/speed buttons, or the SkillBar cluster.
# Push perpendicular along the shortest axis.
const TL_ZONE: Vector2 = Vector2(160, 260)
const TR_ZONE: Vector2 = Vector2(160, 140)
const BR_ZONE: Vector2 = Vector2(220, 220)
const ZONE_PAD: float = 8.0               # extra clearance around the badge

const EDGE_MARGIN: float = 70.0           # screen-edge clamp

# Tap-vs-drag classifier — must match GameCamera's TAP_MAX_DISTANCE /
# TAP_MAX_DURATION so a touch that the camera reads as a pan also gets
# rejected here. Without this, the badge's _input (Phase 1, runs BEFORE the
# camera's gesture classifier in Phase 4) would fire on the press-down of
# a pan, accidentally launching W1 the first time the player drags near
# the spawn portal at level start. See SESSIONS.md ab8a317 for the
# regression this guard fixes.
const TAP_COMMIT_MAX_DISTANCE: float = 12.0
# UI buttons should tolerate a slightly slower finger than map taps. Drag
# distance is the important pan guard; this limit only rejects long holds.
const TAP_COMMIT_MAX_DURATION: float = 0.75

# Two badges with screen-space centers within this distance get merged into
# one larger grouped badge. Keeps multi-path waves whose entrances cluster
# (e.g. both at the left edge) from rendering as visually-redundant pairs.
const GROUP_DISTANCE: float = 120.0
const GROUPED_RADIUS_MULT: float = 1.25

# Colors.
const RIM_COLOR := Color(0.95, 0.78, 0.25)
const FILL_COLOR := Color(0.10, 0.06, 0.02, 0.88)
const GLYPH_PRE_W1 := Color(1.0, 0.92, 0.55)
const GLYPH_OVERLAP := Color(1.0, 0.55, 0.18)
const RING_BG := Color(0.20, 0.12, 0.05, 0.7)
const RING_FG := Color(1.0, 0.55, 0.18)
const CHIP_FILL := Color(0.95, 0.78, 0.25)
const CHIP_TEXT := Color(0.10, 0.06, 0.02)
const SECONDS_TEXT := Color(0.95, 0.92, 0.85)

enum State { HIDDEN, PRE_W1, OVERLAP_CALLABLE }

var _draw_node: Control = null

# Per-frame: Array of badge dicts. Shape:
#   {
#     paths:       Array[String]    one path_id per single, multiple per grouped
#     screen_pos:  Vector2          clamped + zone-avoided draw position
#     grouped:     bool             true after _merge_nearby_badges absorbed
#                                   one or more siblings within GROUP_DISTANCE
#   }
# Tap any badge → WaveManager.call_early_wave(). No two-step commit.
var _active_badges: Array = []
var _state: int = State.HIDDEN

# Pending touch — populated on press-down inside a badge, committed on
# release if the touch stayed within TAP_COMMIT_MAX_DISTANCE for less than
# TAP_COMMIT_MAX_DURATION. Cleared if the touch drifts (player is panning)
# or releases outside any badge. Index keyed by InputEventScreenTouch.index
# so a multi-touch pinch over a badge doesn't accidentally commit.
#   index → { start_pos: Vector2, start_msec: int, badge_idx: int }
var _pending_taps: Dictionary = {}

# PRE_W1 two-step commit. First tap on a badge during pre-W1 grace arms;
# second tap commits (launches W1). Any confirmed map-tap elsewhere
# disarms via the EventBus.map_tap_confirmed hook. Clears automatically
# when _refresh_state observes a non-PRE_W1 state (W1 launched, scene
# change, game over).
#
# OVERLAP keeps single-tap commit — reaction-time decision, arming would
# feel sluggish there. The arming gate sits in the PRE_W1 branch of the
# release handler, in front of the call_early_wave() commit.
var _armed_pre_w1: bool = false

# Cached labels resolved each _process from WaveManager.
var _bonus: int = 0
var _seconds_left: float = 0.0
var _window: float = 0.0

# Lazy-resolved level reference. Re-found when the cached node becomes
# invalid (level reload). Anchor lookup uses the Path2D first curve-point
# (where enemies emerge); the SpawnMarker cache is a fallback for path-
# lookup failure only (typo in WaveSpawn.path_id, partially-authored level).
var _level: Node = null
# path_id → world Vector2, populated when _level is resolved.
var _spawn_markers: Dictionary = {}

# Debug: throttled diagnostic of the gate inputs. Toggle to true to log
# the gate state once per second; off in production.
const DEBUG_PRINT: bool = false
var _last_debug_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 7
	follow_viewport_enabled = false
	if _draw_node == null:
		_draw_node = get_node_or_null("DrawLayer")
	if _draw_node == null:
		_draw_node = Control.new()
		_draw_node.name = "DrawLayer"
		_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	# Tap-elsewhere disarm. GameCamera's gesture classifier dispatches this
	# whenever a press classifies as a tap (vs pan/pinch). We use it as a
	# side-effect-only hook to clear _armed_pre_w1 — never claim the tap,
	# so the same dispatch keeps flowing through SpotInputManager / BaseHero
	# / HeroInputManager for normal map-tap handling (hero moves, spot menu
	# opens). When _armed_pre_w1 is false, this is effectively a no-op.
	EventBus.map_tap_confirmed.connect(_on_map_tap_disarm)


func _ensure_level() -> void:
	if _level != null and is_instance_valid(_level) and _level.has_method("get_path_by_id"):
		return
	_level = null
	_spawn_markers.clear()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	# Walk the scene tree for a node implementing BaseLevel's path API.
	# Level-agnostic — works on L1..L5 without hardcoding scene names.
	for child in scene.get_children():
		if child.has_method("get_path_by_id") and child.has_method("get_path_ids"):
			_level = child
			break
	if _level == null:
		# Fall back to deeper search.
		var found: Node = scene.find_child("Paths", true, false)
		if found != null and found.get_parent() != null and found.get_parent().has_method("get_path_by_id"):
			_level = found.get_parent()
	if _level != null:
		_build_spawn_marker_cache()


# Cache author-placed SpawnMarker positions, keyed by path_id. Used as a
# FALLBACK in _spawn_world_pos when a path_id has no matching Path2D
# (typo, partially-authored level). Populated once when the level is
# resolved; cleared in _ensure_level on level swap.
func _build_spawn_marker_cache() -> void:
	# Caller (_ensure_level) already cleared _spawn_markers.
	if _level == null:
		return
	var markers: Node = _level.get_node_or_null("SpawnMarkers")
	if markers == null:
		return
	for child in markers.get_children():
		if "path_id" in child and child is Node2D:
			_spawn_markers[String(child.path_id)] = (child as Node2D).global_position


# World position to anchor the badge for `path_id`. Two-tier lookup:
#   1. Path2D.curve.get_point_position(0) in world space — where enemies
#      actually emerge (KR-canonical: badge AT the spawn portal).
#   2. Fallback: author-placed SpawnMarker.global_position. Should not be
#      reached on properly-authored levels — kept as a safety net for
#      typos in WaveSpawn.path_id or partially-authored test levels.
# Returns Vector2.INF on miss so callers can skip drawing.
func _spawn_world_pos(path_id: String) -> Vector2:
	if _level != null and _level.has_method("get_path_by_id"):
		var p: Path2D = _level.get_path_by_id(path_id)
		if p != null and p.curve != null and p.curve.point_count > 0:
			return p.to_global(p.curve.get_point_position(0))
	if _spawn_markers.has(path_id):
		return _spawn_markers[path_id]
	return Vector2.INF


func _process(_delta: float) -> void:
	_refresh_state()
	_draw_node.queue_redraw()


func _refresh_state() -> void:
	_active_badges.clear()
	if DEBUG_PRINT:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_debug_msec >= 1000:
			_last_debug_msec = now_ms
			var avail: bool = WaveManager.early_call_available()
			var pre_w1: bool = WaveManager.is_pre_w1_pending()
			var rem_raw: float = WaveManager.seconds_left_in_current_spawn()
			var rem_clamped: float = WaveManager.countdown_remaining()
			var tot: float = WaveManager.countdown_total()
			var paths: Array = WaveManager.get_next_wave_path_ids()
			var lvl_name: String = "null" if _level == null else String(_level.name)
			print("[WaveCallIndicator] avail=%s pre_w1=%s raw_left=%.1fs clamped=%.1fs window=%.1fs next_paths=%s level=%s" % [
				avail, pre_w1, rem_raw, rem_clamped, tot, str(paths), lvl_name,
			])
	if not WaveManager.early_call_available():
		_state = State.HIDDEN
		_armed_pre_w1 = false
		return
	_ensure_level()
	if _level == null:
		_state = State.HIDDEN
		_armed_pre_w1 = false
		return
	_state = State.PRE_W1 if WaveManager.is_pre_w1_pending() else State.OVERLAP_CALLABLE
	# Leaving PRE_W1 (W1 launched, or jumped straight to OVERLAP) clears the
	# armed state so a stale arming doesn't follow the player into mid-game.
	if _state != State.PRE_W1:
		_armed_pre_w1 = false
	_bonus = WaveManager.current_early_call_bonus()
	_seconds_left = WaveManager.countdown_remaining()
	_window = WaveManager.countdown_total()
	var cam: Camera2D = get_viewport().get_camera_2d()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	for pid in WaveManager.get_next_wave_path_ids():
		var key: String = String(pid)
		var world_pos: Vector2 = _spawn_world_pos(key)
		if world_pos == Vector2.INF:
			continue
		var screen_pos: Vector2 = world_pos
		if cam != null:
			screen_pos = cam.get_viewport().get_canvas_transform() * world_pos
		# Clamp to viewport edge with margin.
		screen_pos.x = clampf(screen_pos.x, EDGE_MARGIN, vp_size.x - EDGE_MARGIN)
		screen_pos.y = clampf(screen_pos.y, EDGE_MARGIN, vp_size.y - EDGE_MARGIN)
		# Push out of HUD reserved zones.
		screen_pos = _avoid_zone(screen_pos, Rect2(Vector2.ZERO, TL_ZONE))
		screen_pos = _avoid_zone(screen_pos, Rect2(Vector2(vp_size.x - TR_ZONE.x, 0), TR_ZONE))
		screen_pos = _avoid_zone(screen_pos, Rect2(vp_size - BR_ZONE, BR_ZONE))
		_active_badges.append({
			"paths": [key],
			"screen_pos": screen_pos,
			"grouped": false,
		})
	# Collapse pairs whose anchors land within GROUP_DISTANCE of each other
	# into one larger badge centered between them. Same tap action either way.
	_active_badges = _merge_nearby_badges(_active_badges)


# Greedy O(n²) merge — fine because n is at most the number of paths the
# next wave uses (typically 1-3, never more than 4). Each badge absorbs
# every other unmerged badge within GROUP_DISTANCE; the merged screen_pos
# is the centroid of all members.
func _merge_nearby_badges(badges: Array) -> Array:
	if badges.size() < 2:
		return badges
	var consumed: Array[bool] = []
	for i in badges.size():
		consumed.append(false)
	var result: Array = []
	for i in badges.size():
		if consumed[i]:
			continue
		var b: Dictionary = badges[i].duplicate(true)
		var sum_pos: Vector2 = b.screen_pos
		var n: int = 1
		for j in range(i + 1, badges.size()):
			if consumed[j]:
				continue
			var other: Dictionary = badges[j]
			if (b.screen_pos as Vector2).distance_to(other.screen_pos) <= GROUP_DISTANCE:
				consumed[j] = true
				for p in other.paths:
					b.paths.append(p)
				sum_pos += other.screen_pos
				n += 1
		if n > 1:
			b.screen_pos = sum_pos / float(n)
			b.grouped = true
		result.append(b)
	return result


# Push pos perpendicular to the nearest edge of `rect` until it clears.
# `BADGE_RADIUS + ZONE_PAD` padding so the entire badge is outside the zone.
func _avoid_zone(pos: Vector2, rect: Rect2) -> Vector2:
	var pad: float = BADGE_RADIUS + ZONE_PAD
	var inflated := Rect2(rect.position - Vector2(pad, pad), rect.size + Vector2(pad * 2.0, pad * 2.0))
	if not inflated.has_point(pos):
		return pos
	var dl: float = pos.x - inflated.position.x
	var dr: float = inflated.end.x - pos.x
	var dt: float = pos.y - inflated.position.y
	var db: float = inflated.end.y - pos.y
	var m: float = minf(minf(dl, dr), minf(dt, db))
	if m == dl:
		return Vector2(inflated.position.x, pos.y)
	if m == dr:
		return Vector2(inflated.end.x, pos.y)
	if m == dt:
		return Vector2(pos.x, inflated.position.y)
	return Vector2(pos.x, inflated.end.y)


# ── Input ────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Touch-only handling. emulate_touch_from_mouse turns PC clicks into
	# InputEventScreenTouch, so handling mouse as well would double-fire.
	#
	# Pan-cancel guard: press-down arms a pending tap; release commits only
	# if the touch stayed within TAP_COMMIT_MAX_DISTANCE for less than
	# TAP_COMMIT_MAX_DURATION. Mirrors GameCamera's tap classifier so a
	# drag-from-near-the-badge reads as a pan everywhere in the pipeline,
	# not "tap" here and "pan" downstream.
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if _state == State.HIDDEN or _active_badges.is_empty():
				return
			var badge_idx: int = _badge_index_at(te.position)
			if badge_idx < 0:
				return
			_pending_taps[te.index] = {
				"start_pos": te.position,
				"start_msec": Time.get_ticks_msec(),
				"badge_idx": badge_idx,
			}
			# Don't consume on press — let the camera also see the touch so
			# its gesture classifier can claim it for a pan/pinch if the
			# player drags away. We only consume on a successful commit.
			return
		# Release.
		if not _pending_taps.has(te.index):
			return
		var rec: Dictionary = _pending_taps[te.index]
		_pending_taps.erase(te.index)
		if _state == State.HIDDEN or _active_badges.is_empty():
			return
		var moved: float = (rec.start_pos as Vector2).distance_to(te.position)
		var elapsed: float = float(Time.get_ticks_msec() - int(rec.start_msec)) / 1000.0
		if moved > TAP_COMMIT_MAX_DISTANCE or elapsed > TAP_COMMIT_MAX_DURATION:
			return # player panned or held — not a tap
		# Re-check the release position is still inside a badge. Badges
		# can shift between press and release (camera pan in-flight).
		if _badge_index_at(te.position) < 0:
			return
		# PRE_W1 two-step commit: first tap arms; second tap launches W1.
		# A visible 80 px touch target should behave like a button — eat
		# the release so the camera never dispatches map_tap_confirmed
		# and the hero doesn't ALSO move on this tap. OVERLAP keeps
		# single-tap; reaction-time decision, arming would feel sluggish.
		if _state == State.PRE_W1 and not _armed_pre_w1:
			_armed_pre_w1 = true
			if DEBUG_PRINT:
				print("[WaveCallIndicator] ARM (PRE_W1, tap at %s)" % te.position)
			get_viewport().set_input_as_handled()
			return
		if DEBUG_PRINT:
			print("[WaveCallIndicator] COMMIT call_early_wave (state=%d armed=%s tap=%s)" % [
				_state, _armed_pre_w1, te.position,
			])
		WaveManager.call_early_wave()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if not _pending_taps.has(de.index):
			return
		var rec2: Dictionary = _pending_taps[de.index]
		var moved2: float = (rec2.start_pos as Vector2).distance_to(de.position)
		if moved2 > TAP_COMMIT_MAX_DISTANCE:
			_pending_taps.erase(de.index)


# Returns the index of the first _active_badges entry whose hit-circle
# contains `pos`, or -1 if none. Honors the grouped-badge radius multiplier.
func _badge_index_at(pos: Vector2) -> int:
	for i in _active_badges.size():
		var b: Dictionary = _active_badges[i]
		var hit_r: float = TAP_RADIUS * (GROUPED_RADIUS_MULT if b.grouped else 1.0)
		if (b.screen_pos as Vector2).distance_to(pos) <= hit_r:
			return i
	return -1


# EventBus.map_tap_confirmed listener. Side-effect only: clears the
# armed-pre-W1 state when the player taps anywhere on the map (= any
# confirmed tap that wasn't on the badge, since a release inside the
# badge consumes the event in _input before the camera can classify it).
# Does NOT claim the tap — the dispatch continues to other listeners
# (hero move, tower spot, etc.).
func _on_map_tap_disarm(_screen_pos: Vector2, _claim: RefCounted) -> void:
	if DEBUG_PRINT and _armed_pre_w1:
		print("[WaveCallIndicator] disarm (map tap at %s)" % _screen_pos)
	_armed_pre_w1 = false


func _unhandled_input(event: InputEvent) -> void:
	# PC hotkey W mirrors a tap. Gated on early_call_available so it's a no-op
	# when there's nothing to call. NOTE: W deliberately bypasses the PRE_W1
	# two-step arming gate that the tap path enforces — a keyboard keypress is
	# unambiguous (no underlying map-tap competing for the input), so requiring
	# a second press would feel sluggish without adding any safety.
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_W:
			if WaveManager.early_call_available():
				WaveManager.call_early_wave()
				get_viewport().set_input_as_handled()


# ── Drawing ─────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if _state == State.HIDDEN or _active_badges.is_empty():
		return
	# Pulse phase shared across badges so multi-path levels read as one
	# coordinated signal rather than competing rhythms.
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	# Armed PRE_W1 pulses faster (matches the "hot" OVERLAP rhythm) so the
	# player can see the first tap registered.
	var armed: bool = _armed_pre_w1 and _state == State.PRE_W1
	var period: float = 0.55 if armed else (1.0 if _state == State.PRE_W1 else 0.55)
	var pulse: float = 0.5 + 0.5 * sin(t * (TAU / period))    # 0..1
	# Brighter alpha floor when armed so the badge reads "primed."
	var alpha: float = lerp(0.92, 1.0, pulse) if armed else lerp(0.78, 1.0, pulse)
	for b in _active_badges:
		var radius: float = BADGE_RADIUS * (GROUPED_RADIUS_MULT if b.grouped else 1.0)
		_draw_badge(b.screen_pos, radius, alpha, pulse)


func _draw_badge(pos: Vector2, radius: float, alpha: float, pulse: float) -> void:
	var ring_r: float = radius + (RING_RADIUS - BADGE_RADIUS)
	# Countdown ring (only OVERLAP). Background full circle + foreground arc
	# that drains as seconds_left / window shrinks.
	if _state == State.OVERLAP_CALLABLE and _window > 0.0:
		_draw_node.draw_arc(pos, ring_r, 0.0, TAU, 64,
			Color(RING_BG.r, RING_BG.g, RING_BG.b, RING_BG.a * alpha), RING_THICKNESS, true)
		var frac: float = clampf(_seconds_left / _window, 0.0, 1.0)
		# Drain clockwise from 12 o'clock.
		var start_a: float = -PI * 0.5
		var end_a: float = start_a + frac * TAU
		_draw_node.draw_arc(pos, ring_r, start_a, end_a, 64,
			Color(RING_FG.r, RING_FG.g, RING_FG.b, alpha), RING_THICKNESS, true)
	# Backdrop fill + gold rim.
	_draw_node.draw_circle(pos, radius - RIM_THICKNESS * 0.5,
		Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, FILL_COLOR.a * alpha))
	_draw_node.draw_arc(pos, radius, 0.0, TAU, 64,
		Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), RIM_THICKNESS, true)
	# Armed halo — scaled-down mirror of the radial menu's +7 px golden ring
	# (RadialActionButton.gd:140-143). +4 px outer ring, half-opaque, sits
	# outside the gold rim so it reads "primed, tap again to commit."
	if _armed_pre_w1 and _state == State.PRE_W1:
		_draw_node.draw_arc(pos, radius + 4.0, 0.0, TAU, 64,
			Color(1.0, 0.95, 0.55, 0.45 * alpha), 3.0, true)
	# Glyph: PRE_W1 = play triangle (start). OVERLAP = double-chevron (advance).
	if _state == State.PRE_W1:
		# Armed glyph shifts toward white so the "primed" state is unambiguous.
		var pre_glyph: Color = Color(1.0, 1.0, 0.95) if _armed_pre_w1 else GLYPH_PRE_W1
		_draw_play_glyph(pos, radius, pre_glyph, alpha)
	else:
		_draw_chevron_glyph(pos, radius, GLYPH_OVERLAP, alpha, pulse)
	# Bonus chip + seconds text (OVERLAP only).
	if _state == State.OVERLAP_CALLABLE:
		_draw_bonus_chip(pos, radius)
		_draw_seconds_text(pos, radius)


func _draw_play_glyph(pos: Vector2, radius: float, c: Color, alpha: float) -> void:
	var s: float = radius * 0.45
	var tip := pos + Vector2(s, 0.0)
	var tl := pos + Vector2(-s * 0.7, -s * 0.85)
	var bl := pos + Vector2(-s * 0.7, s * 0.85)
	var col := Color(c.r, c.g, c.b, alpha)
	_draw_node.draw_colored_polygon(PackedVector2Array([tip, tl, bl]), col)


func _draw_chevron_glyph(pos: Vector2, radius: float, c: Color, alpha: float, pulse: float) -> void:
	# Double-chevron pointing right. Slight horizontal jitter on `pulse` so the
	# glyph reads as "moving forward" instead of static during the urgent phase.
	var col := Color(c.r, c.g, c.b, alpha)
	var w: float = radius * 0.55
	var h: float = radius * 0.55
	var nudge: float = (pulse - 0.5) * 4.0
	var x_offsets: Array[float] = [-w * 0.55 + nudge, w * 0.05 + nudge]
	for x in x_offsets:
		var p_top := pos + Vector2(x, -h * 0.5)
		var p_mid := pos + Vector2(x + w * 0.5, 0.0)
		var p_bot := pos + Vector2(x, h * 0.5)
		_draw_node.draw_polyline(PackedVector2Array([p_top, p_mid, p_bot]), col, 6.0, true)


func _draw_bonus_chip(center: Vector2, radius: float) -> void:
	if _bonus <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = 16
	var text: String = "+%dg" % _bonus
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var pad: float = 5.0
	var w: float = max(36.0, text_size.x + pad * 2.0)
	var h: float = 22.0
	# Lower-right of the badge, slightly outside the rim.
	var rect := Rect2(center + Vector2(radius * 0.45, radius * 0.45), Vector2(w, h))
	_draw_node.draw_rect(rect, CHIP_FILL, true)
	_draw_node.draw_rect(rect, Color(0.45, 0.32, 0.08), false, 2.0)
	var text_pos := rect.position + Vector2(pad, h * 0.5 + text_size.y * 0.35)
	_draw_node.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, CHIP_TEXT)


func _draw_seconds_text(center: Vector2, radius: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = 13
	var s_int: int = int(ceil(maxf(0.0, _seconds_left)))
	var text: String = "%ds" % s_int
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	# Lower-left of the badge so it doesn't collide with the +Ng chip.
	var pos: Vector2 = center + Vector2(-radius * 0.45 - text_size.x, radius * 0.55 + text_size.y * 0.5)
	_draw_node.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, SECONDS_TEXT)
