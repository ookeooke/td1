extends RefCounted
class_name EnvironmentScatter

# Procedural scenery for level maps — trees, bushes, flowers, grass tufts
# scattered into the off-path interior so the playfield reads as a forest
# clearing instead of a uniform green rectangle.
#
# Usage:
#   var deco := EnvironmentScatter.generate(seed, bounds, path_points, spot_positions, hero_spawn)
#   for d in deco: EnvironmentScatter.draw(ci, d)
#
# All output is deterministic per seed so the same map always lays out the
# same way. Drawing is plain CanvasItem primitives (matches project Asset
# Strategy — no textures).


enum Kind { TREE, BUSH, FLOWER, GRASS }

const MARGIN_FROM_BOUNDS: float = 60.0
const MIN_DIST_FROM_PATH: float = 70.0
const MIN_DIST_FROM_SPOT: float = 80.0
const MIN_DIST_FROM_HERO: float = 75.0
const MIN_DIST_BETWEEN_DECO: float = 34.0


# Returns Array of {kind: int, pos: Vector2, size: float, seed: float} dicts.
# attempts caps RNG iterations so we don't loop forever on dense maps. The
# typed return preserves stable ordering across runs (helps with z-order).
static func generate(rng_seed: int, bounds: Rect2, path_points: PackedVector2Array, spot_positions: Array, hero_spawn: Vector2, target_count: int = 80, attempts: int = 600) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	# Bounds inset so trees don't poke into the mountain / cliff / water
	# border bleed area.
	var inset_min: Vector2 = bounds.position + Vector2(MARGIN_FROM_BOUNDS, MARGIN_FROM_BOUNDS)
	var inset_max: Vector2 = bounds.position + bounds.size - Vector2(MARGIN_FROM_BOUNDS, MARGIN_FROM_BOUNDS)
	# Squared thresholds — distance_squared_to is cheaper than distance_to.
	var path_sq: float = MIN_DIST_FROM_PATH * MIN_DIST_FROM_PATH
	var spot_sq: float = MIN_DIST_FROM_SPOT * MIN_DIST_FROM_SPOT
	var hero_sq: float = MIN_DIST_FROM_HERO * MIN_DIST_FROM_HERO
	var deco_sq: float = MIN_DIST_BETWEEN_DECO * MIN_DIST_BETWEEN_DECO

	for _i in attempts:
		if out.size() >= target_count:
			break
		var p: Vector2 = Vector2(
			rng.randf_range(inset_min.x, inset_max.x),
			rng.randf_range(inset_min.y, inset_max.y)
		)
		# Reject near paths.
		if _too_close_to_points(p, path_points, path_sq):
			continue
		# Reject near tower spots.
		var bad_spot: bool = false
		for sp in spot_positions:
			if (sp as Vector2).distance_squared_to(p) < spot_sq:
				bad_spot = true
				break
		if bad_spot:
			continue
		# Reject near hero spawn.
		if hero_spawn.distance_squared_to(p) < hero_sq:
			continue
		# Reject near other decorations (Poisson-disk style spacing).
		var bad_neighbor: bool = false
		for d in out:
			if (d.pos as Vector2).distance_squared_to(p) < deco_sq:
				bad_neighbor = true
				break
		if bad_neighbor:
			continue
		out.append({
			"kind": _pick_kind(rng),
			"pos": p,
			"size": rng.randf_range(0.85, 1.25),
			"seed": rng.randf(),
		})
	# Sort by Y so closer-to-camera decorations draw on top of farther ones —
	# gives a faux-isometric overlap when canopies brush each other.
	out.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	return out


static func _pick_kind(rng: RandomNumberGenerator) -> int:
	# Distribution per plan: tree 50, bush 28, flower 12, grass 10.
	var r: float = rng.randf()
	if r < 0.50:
		return Kind.TREE
	elif r < 0.78:
		return Kind.BUSH
	elif r < 0.90:
		return Kind.FLOWER
	return Kind.GRASS


static func _too_close_to_points(p: Vector2, points: PackedVector2Array, sq_thresh: float) -> bool:
	for q in points:
		if (q as Vector2).distance_squared_to(p) < sq_thresh:
			return true
	return false


# Single-entry draw dispatcher — keeps Level draw code tight (one loop).
static func draw(ci: CanvasItem, d: Dictionary) -> void:
	match d.kind:
		Kind.TREE:
			_draw_tree(ci, d.pos, d.size, d.seed)
		Kind.BUSH:
			_draw_bush(ci, d.pos, d.size, d.seed)
		Kind.FLOWER:
			_draw_flower(ci, d.pos, d.size, d.seed)
		Kind.GRASS:
			_draw_grass(ci, d.pos, d.size, d.seed)


# Trunk rect + canopy circle. Per-tree shade variation derived from seed so
# adjacent trees don't all match exactly. Tiny ground shadow under trunk.
static func _draw_tree(ci: CanvasItem, pos: Vector2, size: float, seed_val: float) -> void:
	var trunk_w: float = 6.0 * size
	var trunk_h: float = 18.0 * size
	var canopy_r: float = 22.0 * size
	var trunk_color: Color = Color(0.32, 0.20, 0.12)
	var canopy_a: Color = Color(0.18, 0.42, 0.18)
	var canopy_b: Color = Color(0.30, 0.58, 0.28)
	var canopy_color: Color = canopy_a.lerp(canopy_b, seed_val)
	var canopy_outline: Color = Color(0.10, 0.20, 0.08)
	# Ground shadow ellipse approximated as a flattened polygon so it reads
	# as a soft footprint without a perfect circle.
	var sh_w: float = canopy_r * 1.05
	var sh_h: float = canopy_r * 0.30
	var sh_pts: PackedVector2Array = PackedVector2Array()
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		sh_pts.append(pos + Vector2(cos(a) * sh_w * 0.5, trunk_h * 0.5 + sin(a) * sh_h * 0.5))
	ci.draw_colored_polygon(sh_pts, Color(0.0, 0.0, 0.0, 0.20))
	# Trunk.
	var trunk_rect: Rect2 = Rect2(pos + Vector2(-trunk_w * 0.5, -trunk_h * 0.5), Vector2(trunk_w, trunk_h))
	ci.draw_rect(trunk_rect, trunk_color)
	ci.draw_rect(trunk_rect, canopy_outline, false, 1.5)
	# Canopy — main circle + small darker side circle for a clumpy silhouette.
	var canopy_pos: Vector2 = pos + Vector2(0.0, -trunk_h * 0.5 - canopy_r * 0.55)
	# Lower bump (farther from camera) goes first so the main canopy occludes it.
	ci.draw_circle(canopy_pos + Vector2(canopy_r * 0.5, canopy_r * 0.15), canopy_r * 0.65, canopy_color.darkened(0.10))
	ci.draw_circle(canopy_pos, canopy_r, canopy_color)
	ci.draw_arc(canopy_pos, canopy_r, 0.0, TAU, 16, canopy_outline, 1.5)
	# Highlight wedge — small lighter blob on the upper-left so canopy
	# doesn't read as a flat disk.
	ci.draw_circle(canopy_pos + Vector2(-canopy_r * 0.35, -canopy_r * 0.25), canopy_r * 0.30, canopy_color.lightened(0.18))


# 2 or 3 overlapping smaller green circles. Color tinted from seed.
static func _draw_bush(ci: CanvasItem, pos: Vector2, size: float, seed_val: float) -> void:
	var r: float = 11.0 * size
	var col_a: Color = Color(0.22, 0.50, 0.22)
	var col_b: Color = Color(0.32, 0.62, 0.30)
	var col: Color = col_a.lerp(col_b, seed_val)
	var outline: Color = Color(0.10, 0.22, 0.10)
	# Small ground shadow.
	ci.draw_circle(pos + Vector2(0.0, r * 0.6), r * 0.9, Color(0.0, 0.0, 0.0, 0.18))
	# Three blobs in a triangle so the bush silhouette feels chunky.
	ci.draw_circle(pos + Vector2(-r * 0.7, r * 0.1), r * 0.95, col.darkened(0.10))
	ci.draw_circle(pos + Vector2(r * 0.7, r * 0.05), r * 0.85, col.darkened(0.05))
	ci.draw_circle(pos + Vector2(0.0, -r * 0.35), r, col)
	# Combined outline by re-drawing the three arc rings (cheap).
	ci.draw_arc(pos + Vector2(-r * 0.7, r * 0.1), r * 0.95, 0.0, TAU, 12, outline, 1.2)
	ci.draw_arc(pos + Vector2(r * 0.7, r * 0.05), r * 0.85, 0.0, TAU, 12, outline, 1.2)
	ci.draw_arc(pos + Vector2(0.0, -r * 0.35), r, 0.0, TAU, 14, outline, 1.2)


# Three tiny stem-and-petal flowers in a small cluster. Petal color cycles
# through red / yellow / blue so the patch reads as a wildflower mix.
static func _draw_flower(ci: CanvasItem, pos: Vector2, size: float, seed_val: float) -> void:
	var stem_color: Color = Color(0.30, 0.55, 0.25)
	var petal_palette: Array = [
		Color(0.95, 0.30, 0.30),  # red
		Color(0.98, 0.85, 0.20),  # yellow
		Color(0.45, 0.55, 0.95),  # blue
		Color(0.95, 0.45, 0.85),  # pink
	]
	var spread: float = 8.0 * size
	for i in 3:
		var dx: float = (float(i) - 1.0) * spread
		var dy: float = (sin(seed_val * 7.0 + float(i)) * 2.5)
		var stem_top: Vector2 = pos + Vector2(dx, dy - 4.0 * size)
		var stem_base: Vector2 = pos + Vector2(dx, dy + 3.0 * size)
		ci.draw_line(stem_base, stem_top, stem_color, 1.5, true)
		var petal_color: Color = petal_palette[(i + int(seed_val * 4.0)) % petal_palette.size()]
		ci.draw_circle(stem_top, 2.5 * size, petal_color)
		ci.draw_circle(stem_top, 1.0 * size, Color(1.0, 1.0, 0.85))


# Three short vertical green lines, slightly fanned out. Cheap ground texture.
static func _draw_grass(ci: CanvasItem, pos: Vector2, size: float, _seed_val: float) -> void:
	var col_a: Color = Color(0.28, 0.55, 0.22)
	var col_b: Color = Color(0.40, 0.70, 0.30)
	var h: float = 7.0 * size
	for i in 3:
		var dx: float = (float(i) - 1.0) * 3.0 * size
		var lean: float = (float(i) - 1.0) * 1.5
		var top: Vector2 = pos + Vector2(dx + lean, -h)
		var base: Vector2 = pos + Vector2(dx, 0.0)
		var c: Color = col_a if i == 1 else col_b
		ci.draw_line(base, top, c, 1.6, true)
