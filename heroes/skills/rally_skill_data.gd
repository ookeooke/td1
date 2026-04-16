extends SkillData
class_name RallySkillData

# Phase 21 skill #3: self-cast buff. Pushes a temporary OnHitBonusDamageAbility
# onto the hero for `buff_duration` seconds. AbilityHost auto-removes when
# the duration elapses, so this skill is fire-and-forget.
#
# This is the canonical "skill-as-ability-factory" pattern: the skill
# doesn't bake its own timer — it constructs an AbilityData instance and
# hands it to the host. Same primitive will power items, talents, shrines,
# and global spells. SELF target_type, so SkillBar casts it immediately
# on button press (no targeting step).

const _OnHitBonusScript: Script = preload("res://systems/abilities/OnHitBonusDamageAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var bonus_damage: float = 8.0
@export var buff_duration: float = 10.0


func apply(hero: Node, _target) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if not ("_ability_host" in hero) or hero._ability_host == null:
		return
	var buff: Resource = _OnHitBonusScript.new()
	buff.ability_id = "rally_bonus_damage"
	buff.trigger = _AbilityDataScript.Trigger.ON_HIT_DEALT
	buff.duration = buff_duration
	buff.bonus_damage = bonus_damage
	buff.bonus_damage_type = damage_type
	hero._ability_host.add_ability(buff)
	print("[Skill/Rally] %s empowered for %.1fs (+%d dmg)" % [
		hero.data.hero_name if hero.data != null else "?",
		buff_duration,
		int(bonus_damage),
	])
