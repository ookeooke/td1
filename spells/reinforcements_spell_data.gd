extends SpellData
class_name ReinforcementsSpellData

# Phase 23 spell #2: drops a temporary squad of soldiers at the tapped
# point. Each soldier is a normal blocking soldier (same BaseSoldier
# script, same engage/melee logic) with a LifetimeAbility attached at
# spawn — after `lifetime` seconds they self-destruct via their normal
# _die() path (fires soldier_died, cleans up engagements, queue_frees).
#
# No new Timer nodes, no new self-destruct logic. The ability system
# handles everything. Summon items / decoy spells in later phases will
# follow this exact pattern.

const _LifetimeAbilityScript: Script = preload("res://systems/abilities/LifetimeAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var soldier_scene: PackedScene
@export var squad_size: int = 4
@export var lifetime: float = 20.0
# Spread in world-space around the tap point — soldiers fan out in a
# rough circle with this radius.
@export var spread_radius: float = 18.0


func apply(world_pos: Vector2, caster: Node) -> void:
	if caster == null or soldier_scene == null:
		return
	var parent: Node = caster.get_tree().current_scene
	if parent == null:
		return
	for i in squad_size:
		var soldier: Node = soldier_scene.instantiate()
		parent.add_child(soldier)
		var angle: float = TAU * float(i) / float(maxi(1, squad_size))
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * spread_radius
		var slot: Vector2 = world_pos + offset
		if soldier is Node2D:
			(soldier as Node2D).global_position = slot
		if soldier.has_method("setup"):
			soldier.setup(slot)
		# Attach a LifetimeAbility so the soldier self-destructs after
		# `lifetime` seconds via its normal _die() path.
		if "_ability_host" in soldier and soldier._ability_host != null:
			var life: Resource = _LifetimeAbilityScript.new()
			life.ability_id = "reinforcement_lifetime"
			life.trigger = _AbilityDataScript.Trigger.ON_SPAWN
			life.duration = lifetime
			soldier._ability_host.add_ability(life)
