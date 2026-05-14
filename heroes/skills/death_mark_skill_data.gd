extends SkillData
class_name DeathMarkSkillData

# Necromancer SINGLE-target curse. Two payloads in one skill:
#   1) Marked status (existing MarkedEffect path) — towers, hero, and
#      soldiers all hit the cursed enemy for damage_taken_mult more.
#   2) On-death summon (SummonOnDeathAbility attached to the enemy's
#      AbilityHost) — if the cursed enemy dies before the mark expires,
#      N skeletons spawn at the corpse. AbilityHost auto-removes the
#      ability after `mark_duration` if no death occurred, so the spawn
#      is gated on "killed while cursed", not just "ever cursed".

const _MarkedEffectScript: Script = preload("res://systems/MarkedEffect.gd")
const _SummonOnDeathScript: Script = preload("res://systems/abilities/SummonOnDeathAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var damage_taken_mult: float = 1.5
@export var mark_duration: float = 6.0
@export var skeleton_scene: PackedScene
@export var skeleton_data: Resource  # SoldierData
@export var skeletons_on_death: int = 1
@export var skeleton_lifetime: float = 12.0
# Optional per-skeleton spawn VFX (e.g. SoulRiseVFX). Forwarded onto the
# SummonOnDeathAbility attached to the cursed enemy.
@export var skeleton_spawn_vfx_scene: PackedScene


func apply(hero: Node, target, ctx: Dictionary = {}) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("apply_status_effect"):
		return false
	var eff_mult: float = damage_taken_mult * float(ctx.get("damage_mult", 1.0))
	var eff_dur: float = mark_duration * float(ctx.get("duration_mult", 1.0))
	target.apply_status_effect(_MarkedEffectScript.new(eff_mult, eff_dur))
	if skeleton_scene != null and skeleton_data != null \
			and "_ability_host" in target and target._ability_host != null:
		var on_death: Resource = _SummonOnDeathScript.new()
		on_death.ability_id = "necro_death_mark_summon"
		on_death.trigger = _AbilityDataScript.Trigger.ON_DEATH
		on_death.duration = eff_dur
		on_death.summon_scene = skeleton_scene
		on_death.summon_data = skeleton_data
		on_death.count = skeletons_on_death
		on_death.lifetime = skeleton_lifetime
		on_death.summoner = hero
		on_death.spawn_vfx_scene = skeleton_spawn_vfx_scene
		target._ability_host.add_ability(on_death)
	print("[Skill/DeathMark] %s cursed %s for %.1fs (×%.2f damage, %d skel on death)" % [
		hero.data.hero_name if hero.data != null else "?",
		target.name,
		eff_dur,
		eff_mult,
		skeletons_on_death,
	])
	return true
