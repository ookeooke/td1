extends SkillData
class_name BuffSkillData

# Generic SELF-cast buff: duplicates `buff_ability`, sets its duration to
# `buff_duration`, and pushes it onto the hero's AbilityHost. AbilityHost
# auto-removes when duration expires. Zero bookkeeping in the skill.
#
# This replaces per-buff skill subclasses. Rally, Mana Shield, Speed Boost,
# item-use effects — all use this script with different buff_ability .tres.

const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var buff_ability: Resource  # AbilityData instance to push (duplicated at cast)
@export var buff_duration: float = 10.0


func apply(hero: Node, _target, ctx: Dictionary = {}) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if buff_ability == null:
		return
	if not ("_ability_host" in hero) or hero._ability_host == null:
		return
	# Phase 3G — duration_mult lets mods stretch / shrink the buff window.
	# Phase 3R-followup-2 — damage_mult folds into the buff ability's
	# damage_pct field if present. Without this, Adrenaline Rush on Hunter's
	# Stance (damage_mult=1.4) only shortened the buff without amplifying
	# the +30% damage that's the buff's whole point. attack_speed_mult /
	# armor_mult could be wired similarly but no current mod authors them,
	# so leaving the door open without dead code.
	var eff_duration: float = buff_duration * float(ctx.get("duration_mult", 1.0))
	var buff: Resource = buff_ability.duplicate()
	buff.duration = eff_duration
	var dmg_mult: float = float(ctx.get("damage_mult", 1.0))
	if not is_equal_approx(dmg_mult, 1.0) and "damage_pct" in buff:
		# damage_pct stored as fraction (0.30 = "+30% damage"). Multiplying
		# by 1.4 yields 0.42 = "+42%". Mod sidegrade made visible.
		buff.damage_pct = float(buff.damage_pct) * dmg_mult
	hero._ability_host.add_ability(buff)
	print("[Skill/Buff] %s buffed for %.1fs" % [
		hero.data.hero_name if hero.data != null else "?",
		eff_duration,
	])
