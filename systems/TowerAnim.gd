extends RefCounted
class_name TowerAnim

# Shared animation helpers for BaseTower + TowerBarracks. Stateless — callers
# hold their own _construct_t / _upgrade_t timers and ask for the current
# scale / draw rings based on normalized time. Keeps construction + upgrade
# visual parity between combat towers and barracks without coupling their
# scripts (one extends Node2D, the other extends Node2D, no shared parent).

const CONSTRUCTION_DURATION: float = 0.35
const UPGRADE_DURATION: float = 0.35


# Returns a uniform scale in [0, 1] with a small overshoot near completion so
# the tower "lands" instead of drifting into place. construct_t ticks down
# from CONSTRUCTION_DURATION to 0.
static func construct_scale(construct_t: float) -> float:
	if construct_t <= 0.0:
		return 1.0
	var p: float = clampf(1.0 - construct_t / CONSTRUCTION_DURATION, 0.0, 1.0)
	# Ease-out-cubic + sin bump (~0.1 overshoot near p=0.7, resolves to 1.0).
	var eased: float = 1.0 - pow(1.0 - p, 3.0)
	var bump: float = 0.1 * sin(p * PI)
	return eased + bump


# Returns alpha ∈ [0, 1] during construction. Fades in linearly, applied by
# caller via self.modulate.a so it affects all draws uniformly.
static func construct_alpha(construct_t: float) -> float:
	if construct_t <= 0.0:
		return 1.0
	return clampf(1.0 - construct_t / CONSTRUCTION_DURATION, 0.0, 1.0)


# Returns uniform scale for the upgrade pulse (1.0 → 1.2 at mid → 1.0).
# upgrade_t ticks down from UPGRADE_DURATION to 0.
static func upgrade_scale(upgrade_t: float) -> float:
	if upgrade_t <= 0.0:
		return 1.0
	var p: float = clampf(1.0 - upgrade_t / UPGRADE_DURATION, 0.0, 1.0)
	return 1.0 + 0.2 * sin(p * PI)


# Expanding gold ring drawn at the tower base on upgrade. Fades with time.
static func draw_upgrade_ring(ci: CanvasItem, upgrade_t: float, start_radius: float = 55.0) -> void:
	if upgrade_t <= 0.0:
		return
	var p: float = clampf(1.0 - upgrade_t / UPGRADE_DURATION, 0.0, 1.0)
	var radius: float = lerpf(start_radius, start_radius + 65.0, p)
	var alpha: float = 1.0 - p
	var col: Color = Color(1.0, 0.85, 0.2, alpha)
	ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, col, 4.0)


# Dust ring expanding outward from the tower base during construction.
# Sits under the body (caller should draw this first, then the body).
static func draw_construct_ring(ci: CanvasItem, construct_t: float, start_radius: float = 20.0) -> void:
	if construct_t <= 0.0:
		return
	var p: float = clampf(1.0 - construct_t / CONSTRUCTION_DURATION, 0.0, 1.0)
	var radius: float = lerpf(start_radius, start_radius + 60.0, p)
	var alpha: float = (1.0 - p) * 0.5
	var col: Color = Color(0.7, 0.6, 0.45, alpha)
	ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, col, 6.0)
