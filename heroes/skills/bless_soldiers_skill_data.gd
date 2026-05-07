extends SkillData
class_name BlessSoldiersSkillData

# Phase 48 / Stage 3 — Warrior skill #2. SELF-cast: every friendly
# blockable ally (soldiers + the hero himself) within `radius` of the hero
# gains +damage_bonus and +health_bonus for `buff_duration` seconds via a
# fresh SoldierBlessAbility instance pushed onto each ally's AbilityHost.
#
# The ability's apply()/_on_expired() guard with `if "_effective_max_hp" in
# owner` (see SoldierBlessAbility.gd:42, 58) so it degrades cleanly on the
# hero — hero gets the damage bump (and current_health bump) but skips the
# soldier-specific max-hp cache. Per CORE RULE 11, the ability is owner-
# agnostic; this skill just decides who's in range.
#
# Each blessed ally gets its own ability instance (so the revert-on-expire
# subtraction is per-ally and stacks cleanly — see the additive-math note
# in SoldierBlessAbility.gd). Out-of-range allies are skipped; allies with
# no `_ability_host` are silently skipped.

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
	# Soldiers in radius.
	for soldier in hero.get_tree().get_nodes_in_group("soldiers"):
		if soldier == null or not is_instance_valid(soldier):
			continue
		if not (soldier is Node2D):
			continue
		if hero_pos.distance_squared_to((soldier as Node2D).global_position) > r2:
			continue
		if not ("_ability_host" in soldier) or soldier._ability_host == null:
			continue
		soldier._ability_host.add_ability(_make_bless())
		blessed += 1
	# Hero himself — always within his own radius (distance = 0). Skipped
	# silently if the hero lacks an _ability_host (shouldn't happen, but
	# stays defensive).
	if "_ability_host" in hero and hero._ability_host != null:
		hero._ability_host.add_ability(_make_bless())
		blessed += 1
	print("[Skill/Bless] %s blessed %d allies for %.1fs (+%.0f dmg, +%d HP)" % [
		hero.data.hero_name if hero.data != null else "?",
		blessed,
		buff_duration,
		damage_bonus,
		health_bonus,
	])


# Build a fresh bless ability instance per recipient so per-target revert
# math stays isolated (see additive-stacking note in SoldierBlessAbility.gd).
func _make_bless() -> Resource:
	var bless: Resource = _BlessScript.new()
	bless.ability_id = "soldier_bless"
	bless.trigger = _AbilityDataScript.Trigger.ON_SPAWN
	bless.duration = buff_duration
	bless.damage_bonus = damage_bonus
	bless.health_bonus = health_bonus
	return bless
