extends BaseEnemy
class_name EnemyFlying

# Phase 14: flying variant. Collision layer 3 (set in EnemyFlying.tscn) so
# ground-only towers (collision_mask limited to layer 2) don't see it and
# soldiers can't block it. Behavior identical to BaseEnemy otherwise —
# only _draw() is overridden so the placeholder sprite reads as "flying".


func _draw() -> void:
	# Purple body + gray wing bars. Larger than the basic orc so it's
	# obviously a different unit at a glance.
	draw_circle(Vector2.ZERO, 12.0, Color(0.55, 0.3, 0.75))
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 24, Color(0.15, 0.05, 0.2), 2.0)
	# Wings (static, perpendicular to travel direction — placeholder).
	draw_line(Vector2(-22, -2), Vector2(-12, -2), Color(0.8, 0.8, 0.85), 3.0)
	draw_line(Vector2(12, -2), Vector2(22, -2), Color(0.8, 0.8, 0.85), 3.0)
	# Status rings (reuse BaseEnemy's conventions).
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 23.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
	_draw_health_bar()
