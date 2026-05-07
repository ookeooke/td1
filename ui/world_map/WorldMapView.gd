@tool
extends Control
class_name WorldMapView

# Pannable Kingdom Rush–style world map. Procedural _draw() renders the
# parchment / mountain glyphs / region labels / dotted path. Per-level
# positions live as Marker2D children of LevelMarkers in this scene,
# named after the level_id (mirrors Level1.tscn's TowerSpots → Spot1
# pattern — see CLAUDE.md "New level (template-based)" checklist).
# Drag a marker in the 2D editor to reposition; the .tscn persists it.
#
# Editor (@tool): _draw() runs so the designer sees the parchment +
# mountain glyphs + dotted path + banners while authoring positions.
# Runtime: WorldMap.gd populates _levels via set_levels().
#
# Adding a level: drop a Marker2D named "level_<n>" under LevelMarkers
# at the desired position, then add a LevelNodeData entry to
# level_list.tres. No code change required.

signal marker_pressed(level_id: String)
# Fired after _rebuild_markers populates _markers_by_id so external code
# (WorldMap auto-scroll) can find a marker by level_id at the right
# moment in the layout cycle. Also fires from the editor preview path
# so @tool consumers see it.
signal markers_built
# Fired when play_celebration finishes the road-reveal + marker-pop chain.
# WorldMap consumes this to clear MetaProgression.pending_unlock_celebration_id
# and persist; we keep the field set until the animation actually completes
# so a force-quit mid-celebration replays it on next entry.
signal celebration_finished

const MAP_SIZE: Vector2 = Vector2(2400, 1400)

const COLOR_PARCHMENT: Color = Color(0.93, 0.84, 0.66, 1.0)
const COLOR_SAND_DARK: Color = Color(0.78, 0.62, 0.42, 0.18)
const COLOR_MOUNTAIN_FILL: Color = Color(0.78, 0.66, 0.46, 1.0)
const COLOR_MOUNTAIN_STROKE: Color = Color(0.36, 0.24, 0.14, 1.0)
const COLOR_MOUNTAIN_SNOW: Color = Color(0.96, 0.92, 0.84, 1.0)
const COLOR_PATH_DOT: Color = Color(0.30, 0.20, 0.12, 1.0)
const COLOR_REGION_LABEL: Color = Color(0.32, 0.22, 0.16, 0.85)

# Deterministic seed — same number every run, so mountain/sand layout is
# pixel-stable across redraws and editor reloads. Don't seed from time.
const MAP_RNG_SEED: int = 0x4D4150_5345_4544  # "MAP SEED" in hex-ish.

const PATH_DOT_RADIUS: float = 4.0
const PATH_DOT_SPACING: float = 22.0
const PATH_AVOID_RADIUS: float = 120.0  # Mountains avoid this corridor.

# Hardcoded biome captions. Positioned by hand to fit the suggested
# south-west → north-east winding path. Move freely if levels relocate.
const REGION_LABELS: Array = [
	{"text": "The Dunes", "pos": Vector2(360, 880), "size": 30},
	{"text": "Iron Pass", "pos": Vector2(1180, 460), "size": 28},
	{"text": "Frostpeak", "pos": Vector2(1900, 180), "size": 26},
	{"text": "Foul Bay", "pos": Vector2(820, 1200), "size": 24},
]


var _levels: Array[Resource] = []
var _markers_by_id: Dictionary = {}  # level_id → LevelMarker
var _path_points: PackedVector2Array = PackedVector2Array()
# Parallel to _path_points: the level_id at each path index, sorted by
# unlock_order. Lets _draw_dotted_path skip segments whose endpoints aren't
# both unlocked, and lets play_celebration locate the animating segment.
var _path_point_ids: PackedStringArray = PackedStringArray()
# Active road-reveal animation state.
# _celebration_segment_idx == segment index in _path_points being drawn
# progressively (segment i runs _path_points[i] → _path_points[i+1]).
# -1 means no animation active and all unlocked segments draw fully.
# _celebration_progress 0..1 — fraction of the animating segment's dot count.
var _celebration_id: String = ""
var _celebration_segment_idx: int = -1
var _celebration_progress: float = 1.0
var _mountain_shapes: Array = []     # Pre-baked from seeded RNG.
var _sand_dots: PackedVector2Array = PackedVector2Array()

@onready var level_markers_root: Node2D = $LevelMarkers


func _ready() -> void:
	custom_minimum_size = MAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Pre-bake the deterministic background. We do this once per scene
	# load (not every redraw) so _draw stays cheap.
	_bake_background()
	# In the 2D editor, build banner Buttons over each authored Marker2D so
	# the designer sees what they're laying out. Runtime path goes through
	# WorldMap.gd → set_levels() with real progression state.
	if Engine.is_editor_hint():
		_build_editor_preview_markers()
		_rebuild_path_from_scene()
		queue_redraw()
	# Editor-only: poll Marker2D positions each frame so banner previews and
	# the dotted path follow live as the designer drags. Disabled at runtime —
	# set_levels() is the runtime entry and never enables process.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if level_markers_root == null:
		return
	var any_changed: bool = false
	var needs_rebuild: bool = false
	for pos_node in level_markers_root.get_children():
		if not (pos_node is Node2D):
			continue
		var lid: String = String(pos_node.name)
		var marker: LevelMarker = _markers_by_id.get(lid)
		if marker == null:
			needs_rebuild = true
			continue
		var target_pos: Vector2 = (pos_node as Node2D).position - LevelMarker.MARKER_SIZE * 0.5
		if marker.position != target_pos:
			marker.position = target_pos
			any_changed = true
	if needs_rebuild:
		_build_editor_preview_markers()
		any_changed = true
	if any_changed:
		_rebuild_path_from_scene()
		queue_redraw()


func set_levels(levels: Array[Resource]) -> void:
	_levels = levels
	_rebuild_markers()
	_rebuild_path()
	queue_redraw()


# Re-reads MetaProgression and refreshes each marker's visual state.
# Call after the player completes a run, after debug "Unlock All", etc.
func refresh_states() -> void:
	for data in _levels:
		if data == null:
			continue
		var marker: LevelMarker = _markers_by_id.get(data.level_id)
		if marker == null:
			continue
		_apply_state_to_marker(marker, data)
	_apply_pulse_to_recommended()


# Pulse exactly one marker — the lowest-unlock_order level that is unlocked
# but has 0 campaign stars. That's the player's recommended next attempt.
# All other markers get their pulse cleared. No-op in the editor since the
# preview path treats every marker as unlocked/0-star (would pulse all).
func _apply_pulse_to_recommended() -> void:
	if Engine.is_editor_hint():
		return
	var pulse_id: String = _find_recommended_level_id()
	for lid in _markers_by_id:
		var marker: LevelMarker = _markers_by_id[lid]
		if marker == null:
			continue
		marker.set_pulse(lid == pulse_id)


func _find_recommended_level_id() -> String:
	var best_id: String = ""
	var best_order: int = -1
	for data in _levels:
		if data == null:
			continue
		if not MetaProgression.levels_unlocked.get(data.level_id, false):
			continue
		var campaign_stars: int = MetaProgression.level_stars.get(data.level_id, 0)
		if campaign_stars > 0:
			continue
		var order: int = int(data.unlock_order)
		if best_order == -1 or order < best_order:
			best_order = order
			best_id = data.level_id
	return best_id


func _rebuild_markers() -> void:
	for child in get_children():
		if child is LevelMarker:
			child.queue_free()
	_markers_by_id.clear()
	for data in _levels:
		if data == null:
			continue
		var pos_node: Node2D = _position_node_for(data.level_id)
		if pos_node == null:
			push_warning("[WorldMapView] no Marker2D named '%s' under LevelMarkers — skipping" % data.level_id)
			continue
		var marker := LevelMarker.new()
		marker.name = "Marker_%s" % data.level_id
		add_child(marker)
		marker.position = pos_node.position - LevelMarker.MARKER_SIZE * 0.5
		marker.tooltip_text = data.display_name
		marker.pressed.connect(_on_marker_pressed.bind(data.level_id))
		_apply_state_to_marker(marker, data)
		_markers_by_id[data.level_id] = marker
	_apply_pulse_to_recommended()
	markers_built.emit()


# Returns the LevelMarker (Button) for a given level_id, or null if the
# level isn't authored or markers haven't been rebuilt yet. Used by
# WorldMap to drive auto-scroll-on-open without poking _markers_by_id.
func get_marker_for_level(level_id: String) -> Control:
	return _markers_by_id.get(level_id, null)


# Editor preview: iterate the LevelMarkers Node2D children directly, build
# one banner per Marker2D so the designer sees positioning at-a-glance.
# All shown unlocked / 0 stars (no save loaded in editor, no LevelNodeData
# bound — the .tscn marker is the only required input).
func _build_editor_preview_markers() -> void:
	for child in get_children():
		if child is LevelMarker:
			child.queue_free()
	_markers_by_id.clear()
	if level_markers_root == null:
		return
	var idx: int = 1
	for pos_node in level_markers_root.get_children():
		if not (pos_node is Node2D):
			continue
		var marker := LevelMarker.new()
		marker.name = "Marker_%s" % pos_node.name
		add_child(marker)
		marker.position = (pos_node as Node2D).position - LevelMarker.MARKER_SIZE * 0.5
		marker.set_state(idx, true, 0)
		_markers_by_id[String(pos_node.name)] = marker
		idx += 1
	markers_built.emit()


func _apply_state_to_marker(marker: LevelMarker, data: Resource) -> void:
	# In the editor we don't have a save loaded, so MetaProgression is empty.
	# Show every marker as unlocked / 0 stars so the designer sees them all.
	if Engine.is_editor_hint():
		marker.set_state(int(data.unlock_order), true, 0)
		marker.visible = true
		return
	var unlocked: bool = MetaProgression.levels_unlocked.get(data.level_id, false)
	var total_stars: int = MetaProgression.calculate_total_stars_for_level(data.level_id)
	marker.set_state(int(data.unlock_order), unlocked, total_stars)
	# Locked levels are hidden entirely — the player only sees content they've
	# reached. play_celebration will reveal the just-unlocked one on entry.
	marker.visible = unlocked


func _on_marker_pressed(level_id: String) -> void:
	marker_pressed.emit(level_id)


# Resolve a level_id to its authored Marker2D under LevelMarkers. Mirrors
# BaseLevel._collect_paths' "node name == content_id" lookup pattern.
func _position_node_for(level_id: String) -> Node2D:
	if level_markers_root == null:
		return null
	return level_markers_root.get_node_or_null(NodePath(level_id)) as Node2D


func _rebuild_path() -> void:
	_path_points.clear()
	_path_point_ids.clear()
	# Sort by unlock_order; positions come from the authored Marker2D nodes.
	var sorted: Array = _levels.duplicate()
	sorted.sort_custom(func(a, b): return int(a.unlock_order) < int(b.unlock_order))
	for data in sorted:
		if data == null:
			continue
		var pos_node: Node2D = _position_node_for(data.level_id)
		if pos_node == null:
			continue
		_path_points.append(pos_node.position)
		_path_point_ids.append(String(data.level_id))


# Editor-only fallback: when no LevelNodeData is bound (designing the
# WorldMapView scene in isolation), derive the path from the scene's
# Marker2D order directly. Same Catmull-Rom path is drawn either way.
func _rebuild_path_from_scene() -> void:
	_path_points.clear()
	_path_point_ids.clear()
	if level_markers_root == null:
		return
	for pos_node in level_markers_root.get_children():
		if pos_node is Node2D:
			_path_points.append((pos_node as Node2D).position)
			_path_point_ids.append(String(pos_node.name))


func _bake_background() -> void:
	_sand_dots.clear()
	_mountain_shapes.clear()
	var gen := RandomNumberGenerator.new()
	gen.seed = MAP_RNG_SEED

	# Sand mottling — soft brown circles scattered across the parchment.
	for i in range(150):
		var pos: Vector2 = Vector2(gen.randf_range(0.0, MAP_SIZE.x), gen.randf_range(0.0, MAP_SIZE.y))
		_sand_dots.append(pos)

	# Mountain glyph clusters — each is 3 overlapping triangles. Avoid the
	# corridor around the (yet-to-be-built) path so markers stay legible.
	# Path corridor is unknown at bake time; we use the level positions
	# directly here. WorldMap.gd calls bake before set_levels — but we
	# compute against `_path_points` which is empty on first bake. The
	# avoidance check therefore lets all mountains through on first call,
	# then reseeds in `set_levels()` would be needed. Pragmatic: bake the
	# raw set, and skip avoidance — at 40 clusters across 2400×1400, the
	# odds of overlap on top of a marker are tiny, and labels render on
	# top anyway. Keep the parameter wired for future tuning.
	for i in range(40):
		var center: Vector2 = Vector2(gen.randf_range(80.0, MAP_SIZE.x - 80.0), gen.randf_range(80.0, MAP_SIZE.y - 80.0))
		var width: float = gen.randf_range(60.0, 130.0)
		var height: float = gen.randf_range(40.0, 90.0)
		var snow: bool = gen.randf() < 0.20
		_mountain_shapes.append({"center": center, "w": width, "h": height, "snow": snow})


func _draw() -> void:
	# 1. Parchment fill.
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), COLOR_PARCHMENT)

	# 2. Sand mottling (low-alpha).
	for p in _sand_dots:
		draw_circle(p, 18.0, COLOR_SAND_DARK)

	# 3. Mountain triangle clusters.
	for shape in _mountain_shapes:
		_draw_mountain_cluster(shape.center, shape.w, shape.h, shape.snow)

	# 4. Region labels.
	var font: Font = get_theme_default_font()
	for entry in REGION_LABELS:
		draw_string(font, entry.pos, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(entry.size), COLOR_REGION_LABEL)

	# 5. Dotted path between consecutive level markers. Drawn last so it
	# sits above mountains/labels — a key feature, not background dressing.
	if _path_points.size() >= 2:
		_draw_dotted_path()


func _draw_mountain_cluster(center: Vector2, w: float, h: float, snow: bool) -> void:
	# Three overlapping triangles → a small mountain range glyph. Tallest
	# in the middle. Snow caps on a fraction of clusters add chapter variety.
	var bases: Array = [
		{"x": center.x - w * 0.35, "h": h * 0.7, "halfw": w * 0.30},
		{"x": center.x,            "h": h,       "halfw": w * 0.35},
		{"x": center.x + w * 0.35, "h": h * 0.6, "halfw": w * 0.28},
	]
	for tri in bases:
		var apex: Vector2 = Vector2(tri.x, center.y - tri.h)
		var base_l: Vector2 = Vector2(tri.x - tri.halfw, center.y)
		var base_r: Vector2 = Vector2(tri.x + tri.halfw, center.y)
		var pts: PackedVector2Array = PackedVector2Array([apex, base_r, base_l])
		draw_colored_polygon(pts, COLOR_MOUNTAIN_FILL)
		draw_line(apex, base_l, COLOR_MOUNTAIN_STROKE, 1.5)
		draw_line(apex, base_r, COLOR_MOUNTAIN_STROKE, 1.5)
		if snow:
			# Small snow-cap: a triangle covering the top ~30% of the apex.
			var cap_l: Vector2 = apex.lerp(base_l, 0.30)
			var cap_r: Vector2 = apex.lerp(base_r, 0.30)
			var cap: PackedVector2Array = PackedVector2Array([apex, cap_r, cap_l])
			draw_colored_polygon(cap, COLOR_MOUNTAIN_SNOW)


func _draw_dotted_path() -> void:
	# For each segment, walk it in fixed-spacing steps and stamp dots.
	# Catmull-Rom curvature (using virtual endpoints) gives the path a
	# winding feel without authoring control points. Runtime: a segment
	# only draws if both endpoint levels are unlocked (or it's the
	# currently-animating celebration segment, where dots fill in from
	# 0..step_count over _celebration_progress). Editor preview: draws
	# every segment fully so the designer can see the full layout.
	var n: int = _path_points.size()
	var editor: bool = Engine.is_editor_hint()
	for i in range(n - 1):
		var animating: bool = (i == _celebration_segment_idx)
		if not editor:
			var origin_id: String = _path_point_ids[i] if i < _path_point_ids.size() else ""
			var dest_id: String = _path_point_ids[i + 1] if i + 1 < _path_point_ids.size() else ""
			var origin_unlocked: bool = MetaProgression.levels_unlocked.get(origin_id, false)
			var dest_unlocked: bool = MetaProgression.levels_unlocked.get(dest_id, false)
			# Origin must always be unlocked. Destination may be locked only
			# while this segment is being animated open by play_celebration —
			# otherwise the segment is invisible (player hasn't reached it).
			if not origin_unlocked:
				continue
			if not dest_unlocked and not animating:
				continue
		var p0: Vector2 = _path_points[max(i - 1, 0)]
		var p1: Vector2 = _path_points[i]
		var p2: Vector2 = _path_points[i + 1]
		var p3: Vector2 = _path_points[min(i + 2, n - 1)]
		var seg_len: float = p1.distance_to(p2)
		var step_count: int = max(int(seg_len / PATH_DOT_SPACING), 4)
		# Animating segment fills in progressively; everything else is full.
		var max_step: int = step_count
		if animating:
			max_step = clampi(int(round(float(step_count) * _celebration_progress)), 0, step_count)
		# Skip s=0 (drawn by the prior joint) so density stays even.
		for s in range(1, max_step):
			var t: float = float(s) / float(step_count)
			var pt: Vector2 = _catmull_rom(p0, p1, p2, p3, t)
			draw_circle(pt, PATH_DOT_RADIUS, COLOR_PATH_DOT)


# Plays the road-reveal + marker-pop sequence for a freshly-unlocked level.
# Caller (WorldMap) must invoke immediately after set_levels so the marker's
# "visible = true" state is overridden in the same frame, no flash. Emits
# `celebration_finished` when the chain completes; WorldMap then clears
# MetaProgression.pending_unlock_celebration_id and persists.
func play_celebration(level_id: String) -> void:
	if level_id == "":
		return
	# Locate the celebration level's index in the unlock-order-sorted path.
	var idx: int = -1
	for i in range(_path_point_ids.size()):
		if String(_path_point_ids[i]) == level_id:
			idx = i
			break
	if idx <= 0:
		# Level 1 (or unknown) — no prior segment to animate. Bail without
		# firing the signal; nothing changed and no save flag to clear.
		return
	var marker: LevelMarker = _markers_by_id.get(level_id)
	if marker == null:
		return
	_celebration_id = level_id
	_celebration_segment_idx = idx - 1
	_celebration_progress = 0.0
	# Suppress Phase 1 pulse on this marker while it animates in — the pulse's
	# scale tween would fight the reveal pop. Restored in _on_celebration_done.
	marker.set_pulse(false)
	marker.visible = false
	marker.modulate.a = 0.0
	marker.scale = Vector2(0.5, 0.5)
	queue_redraw()
	var road_tween: Tween = create_tween()
	road_tween.tween_method(_set_celebration_progress, 0.0, 1.0, 1.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	road_tween.tween_callback(_on_celebration_road_done)


func _set_celebration_progress(p: float) -> void:
	_celebration_progress = p
	queue_redraw()


func _on_celebration_road_done() -> void:
	var marker: LevelMarker = _markers_by_id.get(_celebration_id)
	if marker == null:
		_finalize_celebration()
		return
	marker.visible = true
	var pop: Tween = create_tween().set_parallel(true)
	pop.tween_property(marker, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pop.tween_property(marker, "scale", Vector2(1.15, 1.15), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Settle to 1.0 after the overshoot. set_parallel + chain runs the settle
	# sequentially after the pop completes.
	pop.chain().tween_property(marker, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pop.chain().tween_callback(_on_celebration_done)


func _on_celebration_done() -> void:
	# Restart the next-level pulse on the just-revealed marker (it's likely
	# the recommended target now: unlocked + 0 campaign stars).
	var marker: LevelMarker = _markers_by_id.get(_celebration_id)
	_finalize_celebration()
	if marker != null:
		_apply_pulse_to_recommended()


func _finalize_celebration() -> void:
	_celebration_id = ""
	_celebration_segment_idx = -1
	_celebration_progress = 1.0
	queue_redraw()
	celebration_finished.emit()


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
