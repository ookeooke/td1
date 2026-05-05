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
		return
	var unlocked: bool = MetaProgression.levels_unlocked.get(data.level_id, false)
	var total_stars: int = MetaProgression.calculate_total_stars_for_level(data.level_id)
	marker.set_state(int(data.unlock_order), unlocked, total_stars)


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


# Editor-only fallback: when no LevelNodeData is bound (designing the
# WorldMapView scene in isolation), derive the path from the scene's
# Marker2D order directly. Same Catmull-Rom path is drawn either way.
func _rebuild_path_from_scene() -> void:
	_path_points.clear()
	if level_markers_root == null:
		return
	for pos_node in level_markers_root.get_children():
		if pos_node is Node2D:
			_path_points.append((pos_node as Node2D).position)


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
	# winding feel without authoring control points.
	var n: int = _path_points.size()
	for i in range(n - 1):
		var p0: Vector2 = _path_points[max(i - 1, 0)]
		var p1: Vector2 = _path_points[i]
		var p2: Vector2 = _path_points[i + 1]
		var p3: Vector2 = _path_points[min(i + 2, n - 1)]
		var seg_len: float = p1.distance_to(p2)
		var step_count: int = max(int(seg_len / PATH_DOT_SPACING), 4)
		# Skip the last sample so the dot density stays even at joints.
		for s in range(1, step_count):
			var t: float = float(s) / float(step_count)
			var pt: Vector2 = _catmull_rom(p0, p1, p2, p3, t)
			draw_circle(pt, PATH_DOT_RADIUS, COLOR_PATH_DOT)


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
