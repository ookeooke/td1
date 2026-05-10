class_name CoverageHeatmap
extends Control

# Visual heatmap of a level's coverage — Phase 5/7 of the coverage plan.
# Renders the level's paths colored by aggregate spot coverage and tower
# spots sized by their best-tier coverage. Read-only; no interaction.
#
# Driven by:
#   set_level(level: Dictionary, profiles: Array, gold: int)
# where `level` is the structure returned by CoverageAnalyzer.parse_level
# and `profiles` is the array from WaveDamageSimulator.build_tower_profiles.

const PATH_WIDTH: float = 12.0
const SAMPLE_STEP_PX: float = 24.0

var _level: Dictionary = {}
var _profiles: Array = []
var _gold: int = 0

# Cached per-redraw computations.
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _sample_max_coverage: Array = []  # for label, max %


func _ready() -> void:
	custom_minimum_size = Vector2(640, 380)


func set_level(level: Dictionary, profiles: Array, gold: int) -> void:
	_level = level
	_profiles = profiles
	_gold = gold
	queue_redraw()


func _draw() -> void:
	if _level.is_empty():
		_draw_placeholder()
		return

	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	# Background.
	draw_rect(rect, Color(0.08, 0.10, 0.12), true)

	var bounds: Rect2 = _level.get("map_bounds", Rect2(0, 0, 2000, 1160))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_draw_placeholder()
		return

	var pad: float = 16.0
	var avail: Vector2 = size - Vector2(pad * 2.0, pad * 2.0)
	var sx: float = avail.x / bounds.size.x
	var sy: float = avail.y / bounds.size.y
	_scale = min(sx, sy)
	var draw_size: Vector2 = bounds.size * _scale
	_origin = Vector2(pad, pad) + (avail - draw_size) * 0.5 - bounds.position * _scale

	# Map background.
	var map_rect: Rect2 = Rect2(_origin + bounds.position * _scale, bounds.size * _scale)
	draw_rect(map_rect, Color(0.22, 0.36, 0.20), true)

	# Build the per-spot best-tier coverage given the current gold budget.
	var spots_dict: Dictionary = _level.get("spots", {})
	var paths_dict: Dictionary = _level.get("paths", {})

	# spot_id -> {profile, range, coverage_avg_pct, per_path_pct: {path_id: pct}}
	var spot_summary: Dictionary = {}
	for spot_id in spots_dict:
		spot_summary[spot_id] = _best_affordable_summary(String(spot_id), paths_dict)

	# Path coloring — sample each baked polyline at intervals, color by max
	# coverage_pct from any spot at that sample point.
	for path_id in paths_dict:
		var pts: PackedVector2Array = paths_dict[path_id]
		if pts.size() < 2:
			continue
		_draw_path_colored(pts, spot_summary, paths_dict, String(path_id))

	# Tower spots — circles sized by best coverage.
	for spot_id in spots_dict:
		var spot_pos: Vector2 = spots_dict[spot_id]
		var summary: Dictionary = spot_summary.get(spot_id, {})
		var cov_pct: float = float(summary.get("coverage_avg_pct", 0.0))
		var screen_pos: Vector2 = _world_to_screen(spot_pos)
		var radius: float = 9.0 + 14.0 * cov_pct  # 9..23 px depending on coverage
		var fill: Color = _coverage_color(cov_pct).darkened(0.2)
		fill.a = 0.85
		draw_circle(screen_pos, radius, fill)
		draw_arc(screen_pos, radius, 0.0, TAU, 32, Color(0.05, 0.05, 0.05), 2.0, true)
		# Spot label.
		var sid_short: String = String(spot_id).replace("Spot", "")
		_draw_text_centered(screen_pos + Vector2(0, -radius - 2), sid_short, 12, Color.WHITE)

	# Hero spawn — small triangle.
	var hs: Vector2 = _level.get("hero_spawn", Vector2.ZERO)
	if hs != Vector2.ZERO:
		var hs_pos: Vector2 = _world_to_screen(hs)
		var tri: PackedVector2Array = PackedVector2Array([
			hs_pos + Vector2(0, -8),
			hs_pos + Vector2(7, 6),
			hs_pos + Vector2(-7, 6),
		])
		draw_polygon(tri, PackedColorArray([Color(1.0, 0.85, 0.30), Color(1.0, 0.85, 0.30), Color(1.0, 0.85, 0.30)]))

	# Legend top-right.
	_draw_legend(map_rect)


# ── Coverage rollup per spot ─────────────────────────────────────────────

func _best_affordable_summary(spot_id: String, paths_dict: Dictionary) -> Dictionary:
	var spots_dict: Dictionary = _level.get("spots", {})
	if not spots_dict.has(spot_id):
		return {}
	var spot_pos: Vector2 = spots_dict[spot_id]
	# Pick the best tier this spot could ever reach within the gold budget,
	# regardless of where else gold is spent. This matches "best-case" framing.
	var best: Dictionary = {}
	var best_avg: float = -1.0
	for p in _profiles:
		if p.get("is_barracks", false):
			continue
		if int(p["cost"]) > _gold:
			continue
		var rng: float = float(p["attack_range"])
		if rng <= 0.0:
			continue
		var sum_pct: float = 0.0
		var per_path: Dictionary = {}
		var n_paths: int = 0
		for path_id in paths_dict:
			var cov: Dictionary = CoverageAnalyzer.spot_path_coverage(spot_pos, paths_dict[path_id], rng)
			var pct: float = float(cov.get("coverage_pct", 0.0))
			per_path[path_id] = pct
			sum_pct += pct
			n_paths += 1
		var avg: float = sum_pct / max(1, n_paths)
		if avg > best_avg:
			best_avg = avg
			best = {
				"profile": p,
				"range": rng,
				"coverage_avg_pct": avg,
				"per_path_pct": per_path,
			}
	return best


# ── Drawing primitives ──────────────────────────────────────────────────

func _draw_path_colored(pts: PackedVector2Array, spot_summary: Dictionary, paths_dict: Dictionary, path_id: String) -> void:
	# Walk the polyline by chunks of SAMPLE_STEP_PX and color each chunk by
	# the maximum count of spots whose coverage circle contains the sample.
	var spots_dict: Dictionary = _level.get("spots", {})
	# Pre-extract spot positions + their reach (best-tier range) for this path.
	var spot_reach: Array = []
	for spot_id in spots_dict:
		var summ: Dictionary = spot_summary.get(spot_id, {})
		if summ.is_empty():
			continue
		spot_reach.append({
			"pos": spots_dict[spot_id] as Vector2,
			"range_sq": float(summ["range"]) * float(summ["range"]),
		})

	var cumulative: float = 0.0
	var step_acc: float = 0.0
	var prev_world: Vector2 = pts[0]
	var prev_screen: Vector2 = _world_to_screen(prev_world)
	for i in range(1, pts.size()):
		var cur_world: Vector2 = pts[i]
		var seg_len: float = prev_world.distance_to(cur_world)
		if seg_len <= 0.001:
			continue
		var dir: Vector2 = (cur_world - prev_world) / seg_len
		var cursor_world: Vector2 = prev_world
		var remaining: float = seg_len
		while remaining > 0.0:
			var step: float = min(SAMPLE_STEP_PX - step_acc, remaining)
			var next_world: Vector2 = cursor_world + dir * step
			var mid_world: Vector2 = (cursor_world + next_world) * 0.5
			var coverers: int = 0
			for sr in spot_reach:
				if (sr["pos"] as Vector2).distance_squared_to(mid_world) <= float(sr["range_sq"]):
					coverers += 1
			# Color: 0 coverers = red, 1 = yellow, 2+ = green / over-saturated.
			var color: Color = _coverers_to_color(coverers)
			var p_a: Vector2 = _world_to_screen(cursor_world)
			var p_b: Vector2 = _world_to_screen(next_world)
			draw_line(p_a, p_b, color, PATH_WIDTH, true)
			cursor_world = next_world
			remaining -= step
			step_acc += step
			if step_acc >= SAMPLE_STEP_PX:
				step_acc = 0.0
		prev_world = cur_world
		prev_screen = _world_to_screen(cur_world)
		cumulative += seg_len


func _coverers_to_color(n: int) -> Color:
	# 0 = red, 1 = yellow, 2 = green, 3+ = teal (over-saturated).
	match n:
		0:
			return Color(0.85, 0.30, 0.30)
		1:
			return Color(0.95, 0.85, 0.30)
		2:
			return Color(0.40, 0.85, 0.40)
		_:
			return Color(0.30, 0.85, 0.85)


func _coverage_color(pct: float) -> Color:
	# Continuous red→yellow→green ramp for spot circles.
	pct = clamp(pct, 0.0, 1.0)
	if pct < 0.5:
		var t: float = pct / 0.5
		return Color(0.85, 0.30 + 0.55 * t, 0.30)
	else:
		var t: float = (pct - 0.5) / 0.5
		return Color(0.85 - 0.45 * t, 0.85, 0.30 + 0.10 * t)


func _world_to_screen(p: Vector2) -> Vector2:
	return _origin + p * _scale


func _draw_legend(map_rect: Rect2) -> void:
	var x: float = map_rect.end.x - 168.0
	var y: float = map_rect.position.y + 8.0
	var bg: Rect2 = Rect2(x - 6, y - 4, 162, 88)
	draw_rect(bg, Color(0, 0, 0, 0.55), true)
	_draw_text_topleft(Vector2(x, y), "Path coloring:", 11, Color(0.9, 0.9, 0.9))
	_draw_swatch(Vector2(x, y + 16), _coverers_to_color(0), "0 spots reach")
	_draw_swatch(Vector2(x, y + 32), _coverers_to_color(1), "1 spot")
	_draw_swatch(Vector2(x, y + 48), _coverers_to_color(2), "2 spots")
	_draw_swatch(Vector2(x, y + 64), _coverers_to_color(3), "3+ (saturated)")


func _draw_swatch(pos: Vector2, color: Color, label: String) -> void:
	draw_rect(Rect2(pos + Vector2(0, 4), Vector2(12, 6)), color, true)
	_draw_text_topleft(pos + Vector2(18, 0), label, 11, Color(0.9, 0.9, 0.9))


func _draw_text_centered(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var f: Font = ThemeDB.fallback_font
	var sz: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(f, pos - Vector2(sz.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_text_topleft(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var f: Font = ThemeDB.fallback_font
	draw_string(f, pos + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_placeholder() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.12, 0.14), true)
	_draw_text_centered(size * 0.5, "(no level loaded)", 14, Color(0.6, 0.6, 0.6))
