extends "res://systems/AbilityData.gd"
class_name LifetimeAbility

# Phase 23: "this unit exists for X seconds, then dies."
# Attach one to any unit (soldier, summon, decoy) at spawn time. The
# AbilityHost's duration timer handles the expiry; `_on_expired` routes
# through the owner's normal death path (_die() fires soldier_died /
# enemy_died signals and queue_frees correctly), so listeners (barracks
# respawn, XP accounting, ability ON_DEATH triggers) all behave exactly
# as if the unit died naturally.
#
# Set trigger = ON_SPAWN and duration = <lifetime_in_seconds> in code or
# .tres. Duration is what the host's tick() uses for auto-removal; this
# ability itself does nothing in apply().


func apply(_owner: Node, _ctx: Dictionary) -> void:
	# No-op. All the work is in _on_expired() below, fired by AbilityHost
	# when `duration` elapses.
	pass


func _on_expired(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if owner.has_method("_die"):
		owner._die()
	else:
		owner.queue_free()
