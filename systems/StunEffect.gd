extends "res://systems/StatusEffect.gd"
class_name StunEffect

# Freezes the enemy for `duration` seconds. While active, BaseEnemy forces
# State.STUNNED (speed = 0). On expiry BaseEnemy transitions back to WALKING.


func _init(p_duration: float = 1.0) -> void:
	id = "stun"
	duration = p_duration
