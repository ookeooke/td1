extends "res://systems/StatusEffect.gd"
class_name MarkedEffect

# Phase 3L — Ranger Marked Shot status effect.
# While active, multiplies all incoming damage on the marked enemy by
# `damage_taken_mult`. BaseEnemy.get_damage_taken_mult() reads it; the
# DamageCalculator applies it as a final multiplier after armor / resist.
#
# Ranger fantasy: paint a target, towers + hero burn it down faster.

var damage_taken_mult: float = 1.4


func _init(p_damage_taken_mult: float = 1.4, p_duration: float = 5.0) -> void:
	id = "marked"
	damage_taken_mult = maxf(1.0, p_damage_taken_mult)
	duration = p_duration
