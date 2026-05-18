extends "res://systems/AbilityData.gd"
class_name ExecuteAbility

# Phase 2 offensive affix. ON_HIT_DEALT: if the struck NON-boss enemy is at or
# below `hp_threshold` of its effective max HP, finish it (deal its remaining
# health as TRUE damage so armor/resist can't save it). Bosses are immune to
# the instakill — they instead take a small `boss_bonus_pct × hit_amount`
# bonus, so the affix is never dead on a boss but never trivializes one.
#
# Secondary-take_damage pattern, owner-agnostic. `hp_threshold` is rolled by
# the affix; `boss_bonus_pct` is fixed on the template. Boss check is a target
# type test (BaseBoss), not an owner test — owner-agnostic per CORE RULE 11.

@export var hp_threshold: float = 0.0         # [0..1] of max HP, rolled
@export var boss_bonus_pct: float = 0.10      # fixed: applied to bosses instead
@export var boss_bonus_damage_type: int = 0   # PHYSICAL


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
	if target is BaseBoss:
		var hit_amount: float = float(ctx.get("amount", 0.0))
		if hit_amount > 0.0 and boss_bonus_pct > 0.0:
			enemy.take_damage(boss_bonus_pct * hit_amount, boss_bonus_damage_type, owner)
		return
	if hp_threshold <= 0.0:
		return
	if not enemy.has_method("_effective_max_health"):
		return
	var max_hp: float = float(enemy._effective_max_health())
	if max_hp <= 0.0:
		return
	var frac: float = float(enemy.current_health) / max_hp
	if frac > hp_threshold:
		return
	# Deal the remaining health as TRUE damage — guaranteed finish.
	enemy.take_damage(float(enemy.current_health), 2, owner)
