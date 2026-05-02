extends SkillData
class_name BlessSoldiersSkillData

# Phase 48 / Stage 3 — Warrior skill #2. SELF-cast: every friendly soldier
# within `radius` of the hero gains +damage_bonus and +health_bonus for
# `buff_duration` seconds via a fresh SoldierBlessAbility instance pushed
# onto each soldier's AbilityHost.
#
# Each soldier gets its own ability instance (so the revert-on-expire
# subtraction is per-soldier and stacks cleanly — see the additive-math
# note in SoldierBlessAbility.gd). Soldiers outside the radius are ignored;
# soldiers with no `_ability_host` (none should exist post-Phase-20.5) are
# silently skipped.

const _BlessScript: Script = preload("res://systems/abilities/SoldierBlessAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var radius: float = 200.0
@export var damage_bonus: float = 8.0
@export var health_bonus: int = 30
@export var buff_duration: float = 8.0


func apply(hero: Node, _target) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var hero_pos: Vector2 = hero.global_position
	var r2: float = radius * radius
	var blessed: int = 0
	for soldier in hero.get_tree().get_nodes_in_group("soldiers"):
		if soldier == null or not is_instance_valid(soldier):
			continue
		if not (soldier is Node2D):
			continue
		if hero_pos.distance_squared_to((soldier as Node2D).global_position) > r2:
			continue
		if not ("_ability_host" in soldier) or soldier._ability_host == null:
			continue
		var bless: Resource = _BlessScript.new()
		bless.ability_id = "soldier_bless"
		bless.trigger = _AbilityDataScript.Trigger.ON_SPAWN
		bless.duration = buff_duration
		bless.damage_bonus = damage_bonus
		bless.health_bonus = health_bonus
		soldier._ability_host.add_ability(bless)
		blessed += 1
	print("[Skill/Bless] %s blessed %d soldiers for %.1fs (+%.0f dmg, +%d HP)" % [
		hero.data.hero_name if hero.data != null else "?",
		blessed,
		buff_duration,
		damage_bonus,
		health_bonus,
	])
