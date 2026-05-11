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
const COLOR_PLANK_FILL: Color = Color(0.55, 0.40, 0.25, 0.90)
const COLOR_PLANK_STROKE: Color = Color(0.30, 0.20, 0.12, 1.0)
const COLOR_CLOUD_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.028)
const COLOR_CLOUD_HALO: Color = Color(0.0, 0.0, 0.0, 0.012)
const COLOR_BIRD: Color = Color(0.20, 0.16, 0.12, 0.85)
const COLOR_VIGNETTE_DARK: Color = Color(0.18, 0.12, 0.06, 0.35)
const COLOR_VIGNETTE_CLEAR: Color = Color(0.18, 0.12, 0.06, 0.0)

# Mountain depth bands — back-to-front. Far-distance bands are pale and
# desaturated to fake atmospheric depth; near bands keep the original
# warm tan + dark stroke so foreground silhouettes still pop.
const MOUNTAIN_BANDS: Array = [
	{
		"count": 30, "y_min": 0.00, "y_max": 0.40,
		"w_min": 70.0, "w_max": 150.0, "h_min": 30.0, "h_max": 70.0,
		"fill": Color(0.62, 0.66, 0.70, 0.55),
		"stroke": Color(0.50, 0.55, 0.60, 0.0),  # alpha 0 = no stroke
		"stroke_w": 0.0, "snow_chance": 0.0,
	},
	{
		"count": 25, "y_min": 0.20, "y_max": 0.70,
		"w_min": 70.0, "w_max": 130.0, "h_min": 40.0, "h_max": 80.0,
		"fill": Color(0.70, 0.62, 0.48, 0.85),
		"stroke": Color(0.40, 0.30, 0.20, 0.7),
		"stroke_w": 1.0, "snow_chance": 0.10,
	},
	{
		"count": 20, "y_min": 0.40, "y_max": 1.00,
		"w_min": 60.0, "w_max": 130.0, "h_min": 50.0, "h_max": 95.0,
		"fill": COLOR_MOUNTAIN_FILL,
		"stroke": COLOR_MOUNTAIN_STROKE,
		"stroke_w": 1.5, "snow_chance": 0.30,
	},
]

# Biome radial tints — drawn as stacked low-alpha circles for cheap
# soft-falloff radial gradients without per-pixel work.
const BIOME_TINTS: Array = [
	{"center": Vector2(360, 880),  "radius": 700.0, "color": Color(1.00, 0.65, 0.30, 0.10)},  # Dunes — warm orange
	{"center": Vector2(1180, 460), "radius": 600.0, "color": Color(0.85, 0.82, 0.80, 0.06)},  # Iron Pass — neutral grey
	{"center": Vector2(1900, 180), "radius": 700.0, "color": Color(0.55, 0.75, 1.00, 0.10)},  # Frostpeak — cool blue
	{"center": Vector2(820, 1200), "radius": 650.0, "color": Color(0.40, 0.65, 0.35, 0.10)},  # Foul Bay — sickly green
]

# Cloud shadows — drift slowly across the map. Positions wrap modulo
# (MAP_SIZE.x + max_radius * 2) so they re-enter from the left edge.
const CLOUD_DEFS: Array = [
	{"x": 200.0,  "y": 240.0,  "r": 160.0},
	{"x": 950.0,  "y": 700.0,  "r": 190.0},
	{"x": 1700.0, "y": 350.0,  "r": 140.0},
	{"x": 1500.0, "y": 1100.0, "r": 170.0},
]
const CLOUD_DRIFT_SECONDS: float = 90.0
# Each cloud is built from one main blob, one outer halo, and a few lobes
# baked in around the center for an irregular silhouette. Alpha stacks
# where lobes overlap the main body so the cloud has a darker core.
const CLOUD_LOBE_COUNT: int = 4

# Birds — small "M" silhouettes drifting across the map. Few enough to
# feel like life, not enough to be busy.
const BIRD_COUNT: int = 5
const BIRD_SIZE: float = 8.0   # half-width of the wingspan in px
const BIRD_SPEED_PX_S: float = 35.0
const BIRD_BOB_AMPLITUDE: float = 6.0  # vertical sine bob radius
const BIRD_BOB_HZ: float = 0.6         # cycles/sec for the bob
const BIRD_FLAP_HZ: float = 2.4        # cycles/sec for the wing-flap angle

# Animation tick — drives clouds + birds. 20fps keeps bird motion smooth
# enough without forcing per-frame redraws of the heavy mountain layer.
const ANIM_TICK_INTERVAL: float = 0.05

# Decorative scatter — small trees / bushes / ruins placed in the
# parchment between mountains. Avoids level marker positions.
const DECORATION_COUNT: int = 80
const DECORATION_AVOID_MARKER_RADIUS: float = 110.0

# Parchment grain — tiled noise texture multiplied into the parchment
# color. Tile size kept tiny so RAM is trivial (~256 KB at RGBA8).
const PARCHMENT_TILE_SIZE: int = 256
const PARCHMENT_NOISE_OCTAVES: int = 3
const PARCHMENT_NOISE_AMPLITUDE: float = 0.07  # ±7% brightness wobble.

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
var _mountain_bands: Array = []      # Pre-baked: 3 bands of mountain shapes (back→front).
var _sand_dots: PackedVector2Array = PackedVector2Array()
var _decorations: Array = []         # Pre-baked: trees/bushes/ruins {pos, kind, scale}.
var _parchment_tex: ImageTexture     # Tiled parchment+grain texture.
# Cloud shadows + birds drift via a ticking Timer (cheaper than per-frame
# redraw). Disabled in editor so authors aren't distracted while dragging
# markers. _cloud_shapes is baked once with deterministic per-cloud lobe
# offsets so silhouettes stay consistent across redraws.
var _cloud_offset_x: float = 0.0
var _cloud_shapes: Array = []   # [{base_x, y, lobes:[{dx,dy,r,c}]}, ...]
var _birds: Array = []          # [{pos, dir, speed, phase, bob_phase}]
var _bird_anim_time: float = 0.0
var _anim_timer: Timer

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
	# Runtime-only: start the cloud-drift timer. Editor skips so authors
	# aren't distracted by movement while dragging Marker2D positions.
	if not Engine.is_editor_hint():
		_start_cloud_drift()


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
	_mountain_bands.clear()
	_decorations.clear()
	_cloud_shapes.clear()
	_birds.clear()
	var gen := RandomNumberGenerator.new()
	gen.seed = MAP_RNG_SEED

	# Cloud silhouettes — main blob + outer halo + a few off-center lobes
	# so the cloud reads as an irregular shape rather than a perfect circle.
	# Where lobes overlap the main body, alpha stacks → darker core.
	var cloud_gen := RandomNumberGenerator.new()
	cloud_gen.seed = MAP_RNG_SEED + 200
	for cdef in CLOUD_DEFS:
		var r: float = float(cdef.r)
		var lobes: Array = []
		# Soft outer halo (larger, very faint) → feathered edge.
		lobes.append({"dx": 0.0, "dy": 0.0, "r": r * 1.18, "c": COLOR_CLOUD_HALO})
		# Main body.
		lobes.append({"dx": 0.0, "dy": 0.0, "r": r, "c": COLOR_CLOUD_SHADOW})
		# Off-center lobes — irregular silhouette + darker core where they overlap.
		for li in range(CLOUD_LOBE_COUNT):
			var ang: float = cloud_gen.randf_range(0.0, TAU)
			var dist: float = r * cloud_gen.randf_range(0.30, 0.60)
			var lobe_r: float = r * cloud_gen.randf_range(0.45, 0.75)
			lobes.append({
				"dx": cos(ang) * dist,
				"dy": sin(ang) * dist * 0.55,  # squashed Y → cloud is wider than tall
				"r": lobe_r,
				"c": COLOR_CLOUD_SHADOW,
			})
		_cloud_shapes.append({"base_x": float(cdef.x), "y": float(cdef.y), "lobes": lobes})

	# Birds — scattered initial positions, half flying left-to-right and half
	# right-to-left at varying speeds. Confined to the upper 60% of the map
	# so they don't visually compete with the path/markers in the lower half.
	var bird_gen := RandomNumberGenerator.new()
	bird_gen.seed = MAP_RNG_SEED + 300
	for bi in range(BIRD_COUNT):
		_birds.append({
			"pos": Vector2(
				bird_gen.randf_range(0.0, MAP_SIZE.x),
				bird_gen.randf_range(80.0, MAP_SIZE.y * 0.6)
			),
			"dir": 1 if bird_gen.randf() < 0.5 else -1,
			"speed": bird_gen.randf_range(0.85, 1.20),
			"phase": bird_gen.randf_range(0.0, TAU),
			"bob_phase": bird_gen.randf_range(0.0, TAU),
		})

	# Parchment grain — single tiny tiled noise texture, multiplied into the
	# parchment color. Drawn first in _draw via tiled draw_texture_rect so the
	# whole map gets paper character without per-pixel work per frame.
	_parchment_tex = _bake_parchment_tile(gen)

	# Sand mottling — soft brown circles scattered across the parchment.
	for i in range(150):
		var pos: Vector2 = Vector2(gen.randf_range(0.0, MAP_SIZE.x), gen.randf_range(0.0, MAP_SIZE.y))
		_sand_dots.append(pos)

	# Mountain glyph clusters — three depth bands drawn back-to-front.
	# Far/mid bands fake atmospheric depth via desaturation + alpha; the
	# near band keeps the original warm tan + dark stroke for foreground
	# silhouettes. Each band reseeds deterministically so layouts stay
	# pixel-stable across redraws and editor reloads (CORE: don't seed
	# from time). Path-corridor avoidance is impractical at bake time —
	# _path_points is empty on first bake — so we accept the overlap risk
	# (40+ clusters across 2400×1400, label/marker layers draw over top).
	for band_idx in range(MOUNTAIN_BANDS.size()):
		var band: Dictionary = MOUNTAIN_BANDS[band_idx]
		var band_gen := RandomNumberGenerator.new()
		band_gen.seed = MAP_RNG_SEED + band_idx + 1
		var shapes: Array = []
		for i in range(int(band.count)):
			var y_min: float = float(band.y_min) * MAP_SIZE.y
			var y_max: float = float(band.y_max) * MAP_SIZE.y
			var center: Vector2 = Vector2(
				band_gen.randf_range(80.0, MAP_SIZE.x - 80.0),
				band_gen.randf_range(y_min, y_max)
			)
			var width: float = band_gen.randf_range(float(band.w_min), float(band.w_max))
			var height: float = band_gen.randf_range(float(band.h_min), float(band.h_max))
			var snow: bool = band_gen.randf() < float(band.snow_chance)
			shapes.append({"center": center, "w": width, "h": height, "snow": snow})
		_mountain_bands.append({"shapes": shapes, "def": band})

	# Decorative scatter — trees, bushes, ruins. Placed in open parchment
	# between mountains, biased away from level markers so banners don't
	# get visually cluttered. Marker positions are read from the LevelMarkers
	# scene-tree node (available before set_levels since it's an authored
	# child).
	var marker_positions: Array[Vector2] = _collect_marker_positions()
	var deco_gen := RandomNumberGenerator.new()
	deco_gen.seed = MAP_RNG_SEED + 100
	var attempts: int = 0
	var max_attempts: int = DECORATION_COUNT * 4
	while _decorations.size() < DECORATION_COUNT and attempts < max_attempts:
		attempts += 1
		var pos: Vector2 = Vector2(
			deco_gen.randf_range(60.0, MAP_SIZE.x - 60.0),
			deco_gen.randf_range(60.0, MAP_SIZE.y - 60.0)
		)
		var too_close: bool = false
		for mp in marker_positions:
			if pos.distance_to(mp) < DECORATION_AVOID_MARKER_RADIUS:
				too_close = true
				break
		if too_close:
			continue
		var roll: float = deco_gen.randf()
		var kind: String = "tree"
		if roll < 0.55:
			kind = "tree"
		elif roll < 0.85:
			kind = "bush"
		else:
			kind = "ruin"
		var deco_scale: float = deco_gen.randf_range(0.85, 1.25)
		_decorations.append({"pos": pos, "kind": kind, "scale": deco_scale})


# Returns positions of authored Marker2D children under LevelMarkers. Used
# by _bake_background for decoration avoidance. Safe pre-_ready: returns
# empty if the @onready ref isn't bound yet (caller falls back to no avoid).
func _collect_marker_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if level_markers_root == null:
		return out
	for child in level_markers_root.get_children():
		if child is Node2D:
			out.append((child as Node2D).position)
	return out


# Builds a small tiled parchment texture: base parchment color modulated by
# 3-octave value noise. RGBA8, ~256 KB. Tiled across the entire map in _draw.
func _bake_parchment_tile(gen: RandomNumberGenerator) -> ImageTexture:
	var tile: int = PARCHMENT_TILE_SIZE
	var img: Image = Image.create(tile, tile, false, Image.FORMAT_RGBA8)
	# Pre-roll octave seeds so the noise is deterministic per bake call.
	var octave_offsets: Array = []
	for o in range(PARCHMENT_NOISE_OCTAVES):
		octave_offsets.append(Vector2(gen.randf() * 1024.0, gen.randf() * 1024.0))
	for y in range(tile):
		for x in range(tile):
			var n: float = 0.0
			var weight: float = 1.0
			var freq: float = 1.0 / 32.0
			var weight_sum: float = 0.0
			for o in range(PARCHMENT_NOISE_OCTAVES):
				var off: Vector2 = octave_offsets[o]
				# Cheap hash-noise — sin-based so the texture tiles seamlessly
				# is NOT guaranteed, but at PARCHMENT_TILE_SIZE=256 with low
				# amplitude the seam reads as paper grain at zoom levels
				# anyone will play at. Acceptable for the cost.
				var sx: float = (float(x) + off.x) * freq
				var sy: float = (float(y) + off.y) * freq
				var sample: float = sin(sx * 12.9898 + sy * 78.233) * 43758.5453
				sample = sample - floor(sample)  # fract
				n += sample * weight
				weight_sum += weight
				weight *= 0.5
				freq *= 2.0
			n = (n / weight_sum) - 0.5  # center around 0
			var brightness: float = 1.0 + n * PARCHMENT_NOISE_AMPLITUDE * 2.0
			var c: Color = COLOR_PARCHMENT
			c.r = clamp(c.r * brightness, 0.0, 1.0)
			c.g = clamp(c.g * brightness, 0.0, 1.0)
			c.b = clamp(c.b * brightness, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	# 1. Parchment fill — tiled grain texture (replaces flat draw_rect).
	if _parchment_tex != null:
		draw_texture_rect(_parchment_tex, Rect2(Vector2.ZERO, MAP_SIZE), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), COLOR_PARCHMENT)

	# 2. Biome radial tints — stacked low-alpha circles for cheap soft falloff.
	# 3 concentric circles per biome (full / 2/3 / 1/3 radius) double-multiply
	# alpha at the center so tints read warmer near label anchors and fade
	# out toward neighboring biomes.
	for biome in BIOME_TINTS:
		var c: Color = biome.color
		draw_circle(biome.center, biome.radius, c)
		draw_circle(biome.center, biome.radius * 0.66, c)
		draw_circle(biome.center, biome.radius * 0.33, c)

	# 3. Sand mottling (low-alpha).
	for p in _sand_dots:
		draw_circle(p, 18.0, COLOR_SAND_DARK)

	# 4. Mountain triangle clusters — back-to-front bands.
	for band_entry in _mountain_bands:
		_draw_mountain_band(band_entry)

	# 5. Decorative scatter — trees, bushes, ruins between mountains.
	for deco in _decorations:
		_draw_decoration(deco.pos, String(deco.kind), float(deco.scale))

	# 6. Cloud shadows + birds — drift / flap. Skipped in editor (would distract).
	if not Engine.is_editor_hint():
		_draw_clouds()
		_draw_birds()

	# 7. Region label backing planks + labels.
	var font: Font = get_theme_default_font()
	for entry in REGION_LABELS:
		_draw_region_plank(font, entry)

	# 8. Dotted path between consecutive level markers. Drawn last so it
	# sits above mountains/labels — a key feature, not background dressing.
	if _path_points.size() >= 2:
		_draw_dotted_path()

	# 9. Soft vignette — darkens the edges to sell the "old map" feel.
	_draw_vignette()


func _draw_mountain_band(band_entry: Dictionary) -> void:
	var def: Dictionary = band_entry.def
	var fill: Color = def.fill
	var stroke: Color = def.stroke
	var stroke_w: float = float(def.stroke_w)
	var has_stroke: bool = stroke_w > 0.0 and stroke.a > 0.001
	for shape in band_entry.shapes:
		_draw_mountain_cluster(shape.center, shape.w, shape.h, shape.snow, fill, stroke, stroke_w, has_stroke)


func _draw_mountain_cluster(center: Vector2, w: float, h: float, snow: bool, fill: Color, stroke: Color, stroke_w: float, has_stroke: bool) -> void:
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
		draw_colored_polygon(pts, fill)
		if has_stroke:
			draw_line(apex, base_l, stroke, stroke_w)
			draw_line(apex, base_r, stroke, stroke_w)
		if snow:
			# Small snow-cap: a triangle covering the top ~30% of the apex.
			var cap_l: Vector2 = apex.lerp(base_l, 0.30)
			var cap_r: Vector2 = apex.lerp(base_r, 0.30)
			var cap: PackedVector2Array = PackedVector2Array([apex, cap_r, cap_l])
			draw_colored_polygon(cap, COLOR_MOUNTAIN_SNOW)


# Tree / bush / ruin micro-decoration. Each uses 2-3 cheap primitives. The
# scl multiplier varies apparent size 0.85×–1.25× per instance. Param is
# `scl` not `scale` because Control.scale is a base-class property.
func _draw_decoration(pos: Vector2, kind: String, scl: float) -> void:
	match kind:
		"tree":
			var trunk_w: float = 3.0 * scl
			var trunk_h: float = 8.0 * scl
			var crown_h: float = 18.0 * scl
			var crown_halfw: float = 7.0 * scl
			# Trunk.
			draw_rect(Rect2(pos.x - trunk_w * 0.5, pos.y, trunk_w, trunk_h), Color(0.36, 0.24, 0.14, 0.85))
			# Crown (dark green triangle).
			var apex: Vector2 = Vector2(pos.x, pos.y - crown_h)
			var bl: Vector2 = Vector2(pos.x - crown_halfw, pos.y)
			var br: Vector2 = Vector2(pos.x + crown_halfw, pos.y)
			draw_colored_polygon(PackedVector2Array([apex, br, bl]), Color(0.22, 0.40, 0.22, 0.90))
			draw_line(apex, bl, Color(0.12, 0.22, 0.12, 0.85), 1.0)
			draw_line(apex, br, Color(0.12, 0.22, 0.12, 0.85), 1.0)
		"bush":
			var r: float = 5.0 * scl
			draw_circle(pos + Vector2(-r * 0.7, 0.0), r, Color(0.30, 0.45, 0.28, 0.85))
			draw_circle(pos + Vector2(r * 0.7, 0.0), r, Color(0.30, 0.45, 0.28, 0.85))
			draw_circle(pos + Vector2(0.0, -r * 0.5), r * 1.1, Color(0.34, 0.50, 0.30, 0.90))
		"ruin":
			var rw: float = 16.0 * scl
			var rh: float = 9.0 * scl
			# Two stones with a notch between them — reads as a low broken wall.
			draw_rect(Rect2(pos.x - rw * 0.5, pos.y - rh, rw * 0.40, rh), Color(0.55, 0.52, 0.48, 0.90))
			draw_rect(Rect2(pos.x + rw * 0.10, pos.y - rh * 0.7, rw * 0.40, rh * 0.7), Color(0.55, 0.52, 0.48, 0.90))


# Sets up the animation Timer driving cloud drift + bird motion. Tick at
# ANIM_TICK_INTERVAL (20fps) — birds need smoother updates than clouds, so
# we share a single timer at the bird-friendly rate. Cloud offset increment
# scales by tick interval so cloud speed is independent of tick frequency.
func _start_cloud_drift() -> void:
	if _anim_timer != null:
		return
	_anim_timer = Timer.new()
	_anim_timer.wait_time = ANIM_TICK_INTERVAL
	_anim_timer.autostart = true
	_anim_timer.one_shot = false
	_anim_timer.timeout.connect(_on_anim_tick)
	add_child(_anim_timer)


func _on_anim_tick() -> void:
	# Cloud drift — speed = full-map width per CLOUD_DRIFT_SECONDS. fposmod
	# in _draw_clouds wraps the offset, so this just accumulates.
	_cloud_offset_x += MAP_SIZE.x / CLOUD_DRIFT_SECONDS * ANIM_TICK_INTERVAL
	# Bird motion — advance global anim clock (drives wing flap + bob),
	# step each bird's position by its individual velocity, wrap on exit.
	_bird_anim_time += ANIM_TICK_INTERVAL
	_step_birds(ANIM_TICK_INTERVAL)
	queue_redraw()


func _step_birds(delta: float) -> void:
	for bird in _birds:
		var speed: float = BIRD_SPEED_PX_S * float(bird.speed)
		var dir: float = float(bird.dir)
		bird.pos.x += speed * dir * delta
		# Wrap horizontally with a healthy margin so we don't pop in/out
		# right on the visible edge. Re-randomize the y when wrapping so
		# birds don't trace identical horizontal lines forever.
		var margin: float = 60.0
		if dir > 0.0 and bird.pos.x > MAP_SIZE.x + margin:
			bird.pos.x = -margin
			bird.pos.y = randf_range(80.0, MAP_SIZE.y * 0.6)
		elif dir < 0.0 and bird.pos.x < -margin:
			bird.pos.x = MAP_SIZE.x + margin
			bird.pos.y = randf_range(80.0, MAP_SIZE.y * 0.6)


# Drifting cloud shadows. Each cloud is a multi-lobe blob (halo + body +
# off-center lobes baked into _cloud_shapes) for an irregular silhouette
# with a darker core where lobes overlap. The shape's center x wraps mod
# (MAP_SIZE.x + 2 * outer-radius) so clouds slide off the right edge and
# re-enter from the left.
func _draw_clouds() -> void:
	for shape in _cloud_shapes:
		# Halo radius is the outer extent — use it for the wrap span so the
		# whole blob exits the screen before re-entering from the other side.
		var halo: Dictionary = shape.lobes[0]
		var outer_r: float = float(halo.r)
		var span: float = MAP_SIZE.x + outer_r * 2.0
		var raw_x: float = float(shape.base_x) + _cloud_offset_x
		var center_x: float = fposmod(raw_x + outer_r, span) - outer_r
		var center_y: float = float(shape.y)
		for lobe in shape.lobes:
			var pos: Vector2 = Vector2(center_x + float(lobe.dx), center_y + float(lobe.dy))
			draw_circle(pos, float(lobe.r), lobe.c)


# Birds — small "M"/wide-V silhouettes drifting across the upper map. Wing
# angle modulates with a per-bird flap phase so they look like they glide
# and flap rather than slide rigidly. Vertical bob adds a sine wobble.
func _draw_birds() -> void:
	for bird in _birds:
		var flap: float = sin(_bird_anim_time * TAU * BIRD_FLAP_HZ + float(bird.phase))
		var bob: float = sin(_bird_anim_time * TAU * BIRD_BOB_HZ + float(bird.bob_phase)) * BIRD_BOB_AMPLITUDE
		var center: Vector2 = Vector2(bird.pos.x, bird.pos.y + bob)
		# Wings: two short lines forming a wide V/M. flap ∈ [-1..1] tilts
		# the wing tips up (positive) or near-flat (negative).
		var tip_dy: float = -1.0 + flap * 2.5  # -3.5 .. +1.5
		var inner_dy: float = 1.5 - flap * 1.5  # peak depth at downstroke
		var left_tip: Vector2 = center + Vector2(-BIRD_SIZE, tip_dy)
		var right_tip: Vector2 = center + Vector2(BIRD_SIZE, tip_dy)
		var inner_l: Vector2 = center + Vector2(-BIRD_SIZE * 0.25, inner_dy)
		var inner_r: Vector2 = center + Vector2(BIRD_SIZE * 0.25, inner_dy)
		draw_line(left_tip, inner_l, COLOR_BIRD, 1.5)
		draw_line(inner_l, inner_r, COLOR_BIRD, 1.5)
		draw_line(inner_r, right_tip, COLOR_BIRD, 1.5)


# Wooden plank backing for region labels. Auto-sized to the text.
func _draw_region_plank(font: Font, entry: Dictionary) -> void:
	var text: String = entry.text
	var fsz: int = int(entry.size)
	var pos: Vector2 = entry.pos
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	# draw_string baseline pos.y = baseline. Plank rect goes a bit above and
	# below to wrap descenders + ascenders.
	var pad_x: float = 14.0
	var pad_y_top: float = float(fsz) * 0.85
	var pad_y_bot: float = float(fsz) * 0.30
	var rect: Rect2 = Rect2(
		pos.x - pad_x,
		pos.y - pad_y_top,
		text_size.x + pad_x * 2.0,
		pad_y_top + pad_y_bot
	)
	draw_rect(rect, COLOR_PLANK_FILL)
	draw_rect(rect, COLOR_PLANK_STROKE, false, 1.5)
	# Subtle plank-grain — two horizontal lines for woodgrain feel.
	var grain: Color = Color(COLOR_PLANK_STROKE.r, COLOR_PLANK_STROKE.g, COLOR_PLANK_STROKE.b, 0.25)
	draw_line(Vector2(rect.position.x + 4.0, rect.position.y + rect.size.y * 0.35),
		Vector2(rect.position.x + rect.size.x - 4.0, rect.position.y + rect.size.y * 0.35),
		grain, 1.0)
	draw_line(Vector2(rect.position.x + 4.0, rect.position.y + rect.size.y * 0.70),
		Vector2(rect.position.x + rect.size.x - 4.0, rect.position.y + rect.size.y * 0.70),
		grain, 1.0)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COLOR_REGION_LABEL)


# Soft edge vignette via 4 trapezoids with per-vertex alpha. Inner edge is
# transparent; outer edge darkens. No shader, no texture — one draw_polygon
# per edge.
func _draw_vignette() -> void:
	var w: float = MAP_SIZE.x
	var h: float = MAP_SIZE.y
	var depth: float = 110.0
	var dark: Color = COLOR_VIGNETTE_DARK
	var clear: Color = COLOR_VIGNETTE_CLEAR
	# Top edge: outer y=0 dark, inner y=depth clear.
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, depth), Vector2(0, depth)]),
		PackedColorArray([dark, dark, clear, clear])
	)
	# Bottom edge.
	draw_polygon(
		PackedVector2Array([Vector2(0, h - depth), Vector2(w, h - depth), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, dark, dark])
	)
	# Left edge.
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(depth, 0), Vector2(depth, h), Vector2(0, h)]),
		PackedColorArray([dark, clear, clear, dark])
	)
	# Right edge.
	draw_polygon(
		PackedVector2Array([Vector2(w - depth, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - depth, h)]),
		PackedColorArray([clear, dark, dark, clear])
	)


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
