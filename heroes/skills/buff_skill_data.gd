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


func apply(hero: Node, _target) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if buff_ability == null:
		return
	if not ("_ability_host" in hero) or hero._ability_host == null:
		return
	var buff: Resource = buff_ability.duplicate()
	buff.duration = buff_duration
	hero._ability_host.add_ability(buff)
	print("[Skill/Buff] %s buffed for %.1fs" % [
		hero.data.hero_name if hero.data != null else "?",
		buff_duration,
	])
