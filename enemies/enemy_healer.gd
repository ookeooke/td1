extends BaseEnemy
class_name EnemyHealer

# Phase 20.5 refactor: heal-aura logic moved to HealAuraAbility (Resource),
# which BaseEnemy runs generically via AbilityHost. This subclass now
# exists ONLY to give the shaman its distinct placeholder sprite — once
# visuals go data-driven (Phase 41 polish) this file should go away.


func _draw() -> void:
	draw_circle(Vector2.ZERO, 15.0, Color(0.3, 0.7, 0.3))
	draw_arc(Vector2.ZERO, 15.0, 0, TAU, 24, Color(0.08, 0.25, 0.08), 2.0)
	draw_line(Vector2(-6, 0), Vector2(6, 0), Color(1, 1, 1), 2.5)
	draw_line(Vector2(0, -6), Vector2(0, 6), Color(1, 1, 1), 2.5)
	# Status rings — reuse BaseEnemy's convention.
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 20.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 24.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
	_draw_health_bar()
