extends RefCounted
class_name GuardZone

# Combat Blocking Doctrine — shared guardability check used by BaseSoldier
# and BaseHero. Returns true iff `enemy` is currently inside the caller's
# guard zone around `hold_point`. Prefer path-progress comparison; fall back
# to world distance when path data is unavailable. See docs/COMBAT_BLOCKING_DOCTRINE.md.
#
# Convention (semantic, matches the doctrine field descriptions):
#   - `front_px`: how far AHEAD of the hold point (toward spawn — approaching
#     enemies that haven't reached the blocker yet) the blocker may intercept.
#   - `back_px`: how far BEHIND the hold point (toward exit — enemies that
#     just slipped past) the blocker may still clean up.
# In Godot PathFollow2D, progress increases from spawn toward exit, so:
#   delta = enemy.progress - hold.progress
#   - delta < 0 → enemy has not reached the blocker yet (approaching) → use front_px
#   - delta > 0 → enemy passed the blocker → use back_px
# Combined guard range: delta ∈ [-front_px, +back_px].

const FALLBACK_DISTANCE_SLACK_PX: float = 20.0


# Returns true iff the blocker may engage this enemy from `hold_point`.
# Filters out flying / bypass / dying enemies up front so callers don't
# repeat that boilerplate.
static func is_guardable(enemy, hold_point: Vector2, front_px: float, back_px: float) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if "data" in enemy and enemy.data != null:
		if "is_flying" in enemy.data and enemy.data.is_flying:
			return false
		if "bypass_engagement" in enemy.data and enemy.data.bypass_engagement:
			return false
	# DYING state filter — BaseEnemy.State.DYING == 3, but we check the
	# accessor-free way so the helper has no compile-time dependency on
	# BaseEnemy. Enemies expose `.state` as an int.
	if "state" in enemy and enemy.has_method("get_path_progress"):
		# State.DYING is 3 in the existing enum; soft-filter via property.
		if enemy.state == 3:
			return false

	# Path-progress check (preferred). Project hold_point onto the enemy's
	# path curve, compare progress delta.
	if enemy.has_method("get_path_follow"):
		var pf = enemy.get_path_follow()
		if pf != null and is_instance_valid(pf):
			var path = pf.get_parent()
			if path != null and path is Path2D and path.curve != null:
				var curve: Curve2D = path.curve
				var local_pt: Vector2 = path.to_local(hold_point)
				var hold_offset: float = curve.get_closest_offset(local_pt)
				var enemy_offset: float = enemy.get_path_progress()
				var delta: float = enemy_offset - hold_offset
				return delta >= -front_px and delta <= back_px

	# Fallback: world-distance ring around hold_point. Uses the larger of
	# front/back as the radius plus a small slack so authoring intent
	# (which dimension is dominant) carries through.
	if "global_position" in enemy:
		var radius: float = maxf(front_px, back_px) + FALLBACK_DISTANCE_SLACK_PX
		return enemy.global_position.distance_to(hold_point) <= radius
	return false


# Hero on the Path — snap a world position onto the nearest Path2D curve
# under `paths_parent` (typically the level's "Paths" Node2D). Returns the
# snapped position if the closest path point is within `slack` px; otherwise
# returns `world_pos` unchanged so deliberate off-path placement is respected.
# Uses the same Curve2D primitives as is_guardable (get_closest_offset +
# sample_baked) so path-knowledge stays in one file.
static func snap_to_nearest_path(world_pos: Vector2, paths_parent: Node, slack: float) -> Vector2:
	if paths_parent == null:
		return world_pos
	var best: Vector2 = world_pos
	var best_d2: float = slack * slack
	for child in paths_parent.get_children():
		if not (child is Path2D):
			continue
		var path: Path2D = child
		if path.curve == null:
			continue
		var local: Vector2 = path.to_local(world_pos)
		var off: float = path.curve.get_closest_offset(local)
		var closest_local: Vector2 = path.curve.sample_baked(off)
		var closest_world: Vector2 = path.to_global(closest_local)
		var d2: float = world_pos.distance_squared_to(closest_world)
		if d2 < best_d2:
			best_d2 = d2
			best = closest_world
	return best


# Unit tangent of the enemy's path at its current progress, in world space,
# pointing toward the exit (increasing progress / spawn → exit). Used by the
# hero to place its engage spot AHEAD of the enemy along the road so it
# blocks the way instead of tackling from behind. Returns Vector2.ZERO when
# no path data is available — callers fall back to their own heuristic.
static func path_forward_at(enemy) -> Vector2:
	if enemy == null or not is_instance_valid(enemy):
		return Vector2.ZERO
	if not enemy.has_method("get_path_follow"):
		return Vector2.ZERO
	var pf = enemy.get_path_follow()
	if pf == null or not is_instance_valid(pf):
		return Vector2.ZERO
	var path = pf.get_parent()
	if path == null or not (path is Path2D) or path.curve == null:
		return Vector2.ZERO
	var curve: Curve2D = path.curve
	var off: float = enemy.get_path_progress()
	var baked_len: float = curve.get_baked_length()
	if baked_len <= 0.0:
		return Vector2.ZERO
	# Sample slightly ahead and behind, clamped, to get a stable tangent even
	# at the curve ends. Transform both into world space before differencing.
	var step: float = 4.0
	var a: float = clampf(off - step, 0.0, baked_len)
	var b: float = clampf(off + step, 0.0, baked_len)
	var pa: Vector2 = path.to_global(curve.sample_baked(a))
	var pb: Vector2 = path.to_global(curve.sample_baked(b))
	var fwd: Vector2 = pb - pa
	if fwd.length_squared() < 0.0001:
		return Vector2.ZERO
	return fwd.normalized()


# Returns the enemy's path-progress delta from `hold_point` in pixels.
# Positive = enemy has passed the hold point (toward exit).
# Negative = enemy is still approaching.
# Returns 0.0 if no path data is available — callers should check is_guardable
# first and treat fallback-mode enemies as having delta=0.
static func progress_delta(enemy, hold_point: Vector2) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0
	if not enemy.has_method("get_path_follow"):
		return 0.0
	var pf = enemy.get_path_follow()
	if pf == null or not is_instance_valid(pf):
		return 0.0
	var path = pf.get_parent()
	if path == null or not (path is Path2D) or path.curve == null:
		return 0.0
	var curve: Curve2D = path.curve
	var local_pt: Vector2 = path.to_local(hold_point)
	var hold_offset: float = curve.get_closest_offset(local_pt)
	return enemy.get_path_progress() - hold_offset


# Combat Ground Line — the single Y every melee blocker fights at. Returns the
# blocking spot: the enemy's exact lane-Y (top-down ground line) with a
# horizontal `gap` offset toward the path-exit side so the blocker stands in
# the enemy's way instead of on top of / behind it. `enemy_pos.y` already
# includes the enemy's v_offset lane (walk-bob / flight-lift are draw-only and
# never in global_position), so matching it puts blocker + enemy on the same
# shadow line. Used by BaseHero._engage_position_for AND BaseSoldier so every
# melee blocker (soldier, melee hero, ranged hero in close-combat) duels on the
# enemy's exact Y. See docs/COMBAT_BLOCKING_DOCTRINE.md — Combat Ground Line.
#
# `slot` is the blocker's enemy-owned fan-out index (BaseEnemy.block_slot_for).
# slot 0 is byte-identical to the legacy single-spot result — the dominant
# case (all shipped heroes + soldiers are max_block_targets = 1) is unchanged,
# so the approach-steer / settle math and every existing test are unaffected.
# When 2+ blockers pile on ONE enemy (more friendlies than enemies), extra
# blockers spread by SLOT_SPREAD_PX along the road-width axis (perpendicular
# to path-forward), alternating sides around the slot-0 front duelist. They
# stay on the exit-side wall and ~on the ground line; only the off-center
# stagger prevents the shadows/bodies merging into one blob.
const SLOT_SPREAD_PX: float = 28.0

static func melee_engage_spot(enemy_pos: Vector2, forward: Vector2, gap: float, slot: int = 0) -> Vector2:
	var dir_x: float = signf(forward.x) if absf(forward.x) > 0.05 else 1.0
	var spot: Vector2 = Vector2(enemy_pos.x + dir_x * gap, enemy_pos.y)
	if slot <= 0:
		return spot
	# Perpendicular to travel = the road-width axis (≈ world-Y for the
	# horizontal paths this game ships). Alternate sides so the front
	# duelist (slot 0) stays centered and extras fan symmetrically:
	# slot 1 → +1 step, 2 → −1, 3 → +2, 4 → −2 …
	var perp: Vector2 = Vector2(-forward.y, forward.x)
	if perp.length_squared() < 0.0001:
		perp = Vector2(0.0, 1.0)
	perp = perp.normalized()
	@warning_ignore("integer_division")
	var rank: int = (slot + 1) / 2
	var side: float = 1.0 if (slot % 2) == 1 else -1.0
	return spot + perp * (side * float(rank) * SLOT_SPREAD_PX)
