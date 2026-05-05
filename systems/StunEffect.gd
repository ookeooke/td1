extends "res://systems/StatusEffect.gd"
class_name StunEffect

# Freezes the enemy for `duration` seconds. While active, BaseEnemy gates
# _physics_process on _effects.has("stun") — the unit doesn't walk or
# counter-attack, but its underlying state (WALKING / COMBAT) is preserved.
# Engaged enemies stay COMBAT-blocked through the stun and resume hitting
# the instant it expires — no change_state ping-pong, no lost engagement.


func _init(p_duration: float = 1.0) -> void:
	id = "stun"
	duration = p_duration
