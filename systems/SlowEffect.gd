extends "res://systems/StatusEffect.gd"
class_name SlowEffect

# Reduces enemy effective move speed by `slow_factor` (0..1) for `duration` seconds.
# BaseEnemy reads slow_factor directly via its "slow" status slot.

var slow_factor: float = 0.5


func _init(p_slow_factor: float = 0.5, p_duration: float = 2.0) -> void:
	id = "slow"
	slow_factor = clampf(p_slow_factor, 0.0, 1.0)
	duration = p_duration
