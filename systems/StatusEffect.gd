extends RefCounted
class_name StatusEffect

# Base class for timed status effects (applied via carrier.apply_status_effect).
# Subclasses override apply()/remove() for state hooks; carriers tick
# `duration` down and read effect-specific fields (e.g. slow_factor) directly.

var id: String = ""
var duration: float = 0.0


func apply(_carrier: Node) -> void:
	pass


func remove(_carrier: Node) -> void:
	pass


# Called by carriers when a second effect with the same id is applied while
# this one is still active. Default semantics: take the stronger duration —
# the new effect's duration if it's longer, otherwise keep the existing.
# Subclasses MUST override when they hold per-tick state (BurnEffect /
# PoisonEffect) so reapplication doesn't reset the tick accumulator and
# silently suppress damage from rapid hits. See BurnEffect.refresh.
func refresh(new_effect) -> void:
	if new_effect == null:
		return
	if new_effect.duration > duration:
		duration = new_effect.duration
