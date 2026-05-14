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
