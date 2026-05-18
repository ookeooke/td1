extends "res://systems/AbilityData.gd"
class_name CritStrikeAbility

# Phase 2 offensive affix. ON_HIT_DEALT: with probability `crit_chance`, the
# owner's hit "crits" — an extra `(crit_mult - 1.0) × hit_amount` is dealt to
# the same target as a secondary packet. Net effect on a crit = a `crit_mult`×
# hit; non-crits are unchanged.
#
# Same secondary-take_damage pattern as OnHitBonusDamageAbility / LifestealAbility
# (the original hit is untouched; this is a separate event). Owner-agnostic —
# no `if owner is BaseHero`. `crit_mult` is fixed on the template; only
# `crit_chance` is rolled by the affix. Default damage type PHYSICAL so the
# bonus is mitigated the same way the weapon hit was.

@export var crit_chance: float = 0.0          # [0..1], rolled by the affix
@export var crit_mult: float = 1.5            # fixed multiplier on a crit
@export var bonus_damage_type: int = 0        # DamageCalculator.DamageType.PHYSICAL


func apply(owner: Node, ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if ctx == null or not ctx.has("target"):
		return
	var target = ctx.get("target")
	if target == null or not is_instance_valid(target):
		return
	if not (target is BaseEnemy):
		return
	var enemy: BaseEnemy = target
	if enemy.state == BaseEnemy.State.DYING:
		return
	if crit_chance <= 0.0 or crit_mult <= 1.0:
		return
	if randf() >= crit_chance:
		return
	var hit_amount: float = float(ctx.get("amount", 0.0))
	if hit_amount <= 0.0:
		return
	var bonus: float = (crit_mult - 1.0) * hit_amount
	enemy.take_damage(bonus, bonus_damage_type, owner)
