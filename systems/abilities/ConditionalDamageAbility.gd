extends "res://systems/AbilityData.gd"
class_name ConditionalDamageAbility

# Phase 2 offensive affix. ON_HIT_DEALT: if the struck enemy matches a
# configured class (flying / boss / enemy-id substring), deal an extra
# `bonus_pct × hit_amount`. One template, three .tres flavours (vs Armored /
# vs Flying / vs Boss). Because the bonus only applies to a subset of enemies
# it can carry a higher pct than an unconditional damage affix.
#
# Secondary-take_damage pattern, owner-agnostic. Match tests inspect the
# TARGET (the victim), never the owner — fine under CORE RULE 11. `bonus_pct`
# is rolled by the affix; the match fields are fixed on each .tres flavour.

@export var bonus_pct: float = 0.0            # fraction of the hit, rolled
@export var match_flying: bool = false
@export var match_boss: bool = false
@export var match_enemy_id: String = ""       # substring match on data.enemy_id
@export var bonus_damage_type: int = 0        # PHYSICAL


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
	if bonus_pct <= 0.0:
		return
	var matched: bool = false
	if match_flying and enemy.data != null and "is_flying" in enemy.data and enemy.data.is_flying:
		matched = true
	if not matched and match_boss and target is BaseBoss:
		matched = true
	if not matched and match_enemy_id != "" and enemy.data != null \
			and String(enemy.data.enemy_id).find(match_enemy_id) != -1:
		matched = true
	if not matched:
		return
	var hit_amount: float = float(ctx.get("amount", 0.0))
	if hit_amount <= 0.0:
		return
	enemy.take_damage(bonus_pct * hit_amount, bonus_damage_type, owner)
