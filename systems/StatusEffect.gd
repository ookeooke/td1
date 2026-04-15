extends RefCounted
class_name StatusEffect

# Base class for timed enemy status effects (Phase 13+).
# Subclasses override apply()/remove() for state hooks; BaseEnemy ticks
# `duration` down and reads effect-specific fields (e.g. slow_factor) directly.

var id: String = ""
var duration: float = 0.0


func apply(_enemy: Node) -> void:
	pass


func remove(_enemy: Node) -> void:
	pass
