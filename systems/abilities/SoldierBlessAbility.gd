extends "res://systems/AbilityData.gd"
class_name SoldierBlessAbility

# Phase 48 / Stage 3 — additive temporary buff for soldiers, pushed by the
# Warrior's "Bless" hero skill. apply() bumps damage + HP on attach, and
# _on_expired() (fired by AbilityHost when `duration` elapses) reverts the
# exact deltas this instance contributed.
#
# Authored as additive (`damage_bonus` / `health_bonus`) rather than
# multiplicative on purpose: stacking N blesses adds N×bonus and reverts N
# subtractions, which arithmetically cancels back to the soldier's
# unmodified stats. A multiplicative formulation would orphan a residual
# multiplier when the second-applied bless reverts before the first.
#
# Soldiers receive a `data.duplicate(true)` copy of SoldierData when
# spawned by TowerBarracks (and by the SummonSoldiers skill below), so
# mutating `owner.data.attack_damage` is per-soldier and never leaks into
# the shared resource.

@export var damage_bonus: float = 8.0
@export var health_bonus: int = 30
# Subtle golden tint applied while the buff is active so the player can
# tell which soldiers are blessed in a crowded melee.
@export var visual_tint: Color = Color(1.25, 1.15, 0.55, 1.0)

# Per-soldier metadata key — counts active blesses on the same soldier so
# the LAST one to expire is the one that resets modulate. Without this,
# a stack of two blesses would have the first-expire wipe the gold tint
# while the second is still active.
const _STACK_META_KEY: String = "soldier_bless_active_count"


func apply(owner: Node, ctx: Dictionary) -> void:
	# Only run on the initial attach (ON_SPAWN). The host won't dispatch
	# any other event to us, but `phase` is set on equip/unequip flows so
	# guard against a stray ON_UNEQUIP delivery.
	if int(ctx.get("phase", -1)) == Trigger.ON_UNEQUIP:
		return
	if owner == null or not is_instance_valid(owner) or owner.data == null:
		return
	owner.data.attack_damage += damage_bonus
	if "_effective_max_hp" in owner:
		owner._effective_max_hp += health_bonus
	if "current_health" in owner:
		owner.current_health += health_bonus
	# Bump the active-bless counter and apply the tint. Counter survives
	# stacking so the first-to-expire doesn't clear the visual indicator.
	var prev_count: int = int(owner.get_meta(_STACK_META_KEY, 0))
	owner.set_meta(_STACK_META_KEY, prev_count + 1)
	owner.modulate = visual_tint
	owner.queue_redraw()


func _on_expired(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner) or owner.data == null:
		return
	owner.data.attack_damage -= damage_bonus
	if "_effective_max_hp" in owner:
		owner._effective_max_hp = maxi(1, owner._effective_max_hp - health_bonus)
		# Clamp current_health so a buff expiring on a near-full soldier
		# doesn't push current above the new max.
		if "current_health" in owner:
			owner.current_health = mini(owner.current_health - health_bonus, owner._effective_max_hp)
			owner.current_health = maxi(0, owner.current_health)
			# If the buff expiring drops the soldier to 0 HP (took ≥
			# health_bonus damage during the buff), route through the normal
			# death path so engagements release, signals fire, and the body
			# clears. Without this the soldier sits at 0 HP as a "ghost",
			# unable to fight or respawn until something else hits it.
			if owner.current_health <= 0 and "state" in owner and owner.state != BaseSoldier.State.DEAD:
				if owner.has_method("_die"):
					owner._die()
				return
	# Decrement the bless counter; only the LAST active bless restores the
	# default modulate. Stacked blesses keep the gold tint until all expire.
	var remaining: int = maxi(0, int(owner.get_meta(_STACK_META_KEY, 1)) - 1)
	owner.set_meta(_STACK_META_KEY, remaining)
	if remaining <= 0:
		owner.modulate = Color.WHITE
	owner.queue_redraw()
