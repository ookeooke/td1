extends BaseEnemy
class_name EnemyHealer

# Phase 20.5 refactor: heal-aura logic moved to HealAuraAbility (Resource),
# which BaseEnemy runs generically via AbilityHost. This subclass now
# exists ONLY to give the shaman its distinct placeholder sprite — once
# visuals go data-driven (Phase 41 polish) this file should go away.


func _draw() -> void:
	if data != null and data.visual != null:
		super._draw()
		return
	# Legacy fallback: green body + white crosshair.
	draw_circle(Vector2.ZERO, 37.5, Color(0.3, 0.7, 0.3))
	draw_arc(Vector2.ZERO, 37.5, 0, TAU, 24, Color(0.08, 0.25, 0.08), 5.0)
	draw_line(Vector2(-15, 0), Vector2(15, 0), Color(1, 1, 1), 6.25)
	draw_line(Vector2(0, -15), Vector2(0, 15), Color(1, 1, 1), 6.25)
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 50.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 7.5)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 60.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 7.5)
	_draw_health_bar()
