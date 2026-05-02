extends SkillData
class_name SummonSoldiersSkillData

# Phase 48 / Stage 3 — Warrior skill #1. SELF-cast: hero summons N
# temporary soldiers at his position. They behave like ordinary barracks
# soldiers (block, charge, take damage, draw HP bar) but auto-die after
# `lifetime` seconds via a LifetimeAbility on each soldier's AbilityHost.
#
# Reuses the spawn pattern from TowerBarracks._spawn_soldier
# (towers/TowerBarracks.gd:253-273): instantiate soldier_scene → assign a
# duplicated SoldierData → add_child to the level scene → call
# soldier.setup(blocking_position, flag_position) → add to the "soldiers"
# group so HealAura / Bless / etc. find them.

const _LifetimeScript: Script = preload("res://systems/abilities/LifetimeAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")
# Spawn arc — 90° fan above the hero (negative-Y is "in front" for TD camera
# angles). For count=2 this places summons as front-left / front-right
# flankers; for higher counts they fan out evenly along the same arc.
const _FAN_ARC: float = PI * 0.5
const _FAN_CENTER: float = -PI * 0.5

@export var soldier_scene: PackedScene
@export var soldier_data: Resource  # SoldierData — duplicated per spawn
@export var count: int = 2
@export var lifetime: float = 15.0
# Spread offset — soldiers spawn around the hero in a small arc so two
# units don't pile on the exact same pixel.
@export var spread_radius: float = 35.0


func apply(hero: Node, _target) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if soldier_scene == null or soldier_data == null:
		push_warning("[SummonSoldiers] skill_summon_soldiers.tres missing soldier_scene or soldier_data")
		return
	var parent: Node = hero.get_tree().current_scene
	if parent == null:
		return
	for i in count:
		var soldier: CharacterBody2D = soldier_scene.instantiate()
		soldier.data = soldier_data.duplicate(true)
		# Add to the soldiers group so other systems (Bless, hero soldier-aura
		# talents, splitting rules) treat them as friendly ground units.
		soldier.add_to_group("soldiers")
		parent.add_child(soldier)
		var t: float = 0.5 if count <= 1 else float(i) / float(count - 1)
		var angle: float = _FAN_CENTER - _FAN_ARC * 0.5 + _FAN_ARC * t
		var off: Vector2 = Vector2(cos(angle), sin(angle)) * spread_radius
		var rally_pos: Vector2 = hero.global_position + off
		soldier.global_position = rally_pos
		if soldier.has_method("setup"):
			# blocking_position = rally; flag_position = hero (so engagement
			# zone stays anchored on the hero, not on a phantom flag).
			soldier.setup(rally_pos, hero.global_position)
		# Auto-despawn — LifetimeAbility's _on_expired calls owner._die() so
		# the soldier dies cleanly (release engagements, fire signals, fall-
		# over death animation).
		var lifetime_ability: Resource = _LifetimeScript.new()
		lifetime_ability.ability_id = "summon_lifetime"
		lifetime_ability.trigger = _AbilityDataScript.Trigger.ON_SPAWN
		lifetime_ability.duration = lifetime
		if "_ability_host" in soldier and soldier._ability_host != null:
			soldier._ability_host.add_ability(lifetime_ability)
	print("[Skill/Summon] %s summoned %d soldiers for %.1fs" % [
		hero.data.hero_name if hero.data != null else "?",
		count,
		lifetime,
	])
