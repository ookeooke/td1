extends BaseEnemy
class_name EnemyFlying

# Phase 14: flying variant. Collision layer 3 (set in EnemyFlying.tscn) so
# ground-only towers (collision_mask limited to layer 2) don't see it and
# soldiers can't block it. Behavior identical to BaseEnemy otherwise —
# only _draw() is overridden so the placeholder sprite reads as "flying".


func _draw() -> void:
	if data != null and data.visual != null:
		# Data-driven: BaseEnemy._draw() handles body + status rings + HP bar.
		super._draw()
		return
	# Legacy fallback: purple body + gray wing bars.
	draw_circle(Vector2.ZERO, 12.0, Color(0.55, 0.3, 0.75))
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 24, Color(0.15, 0.05, 0.2), 2.0)
	draw_line(Vector2(-22, -2), Vector2(-12, -2), Color(0.8, 0.8, 0.85), 3.0)
	draw_line(Vector2(12, -2), Vector2(22, -2), Color(0.8, 0.8, 0.85), 3.0)
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 23.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
	_draw_health_bar()
