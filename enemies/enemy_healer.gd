extends BaseEnemy
class_name EnemyHealer

# Phase 15: Timer-based ally healer. Every data.heal_interval seconds the
# HealArea (mask 2|4 = 6, ground + flying) is polled for overlapping
# BaseEnemy instances; each non-self, non-dying ally is healed by
# data.heal_amount. Uses a Timer per the mobile-performance rule:
# "Enemy healing: Timer-based only — never _physics_process."

@onready var heal_area: Area2D = $HealArea
@onready var heal_shape: CollisionShape2D = $HealArea/CollisionShape2D
@onready var heal_timer: Timer = $HealTimer


func _ready() -> void:
	super._ready()
	if data == null:
		return
	var circle := CircleShape2D.new()
	circle.radius = data.heal_range
	heal_shape.shape = circle
	heal_timer.wait_time = data.heal_interval
	heal_timer.one_shot = false
	heal_timer.timeout.connect(_on_heal_pulse)
	heal_timer.start()


func _on_heal_pulse() -> void:
	if state == State.DYING or data == null or not data.heals_allies:
		return
	for area in heal_area.get_overlapping_areas():
		if area == self:
			continue
		if not (area is BaseEnemy):
			continue
		var ally: BaseEnemy = area
		if ally.state == BaseEnemy.State.DYING:
			continue
		ally.heal(data.heal_amount)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 15.0, Color(0.3, 0.7, 0.3))
	draw_arc(Vector2.ZERO, 15.0, 0, TAU, 24, Color(0.08, 0.25, 0.08), 2.0)
	draw_line(Vector2(-6, 0), Vector2(6, 0), Color(1, 1, 1), 2.5)
	draw_line(Vector2(0, -6), Vector2(0, 6), Color(1, 1, 1), 2.5)
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 20.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 24.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
