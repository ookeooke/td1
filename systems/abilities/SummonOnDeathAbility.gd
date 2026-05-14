extends "res://systems/AbilityData.gd"
class_name SummonOnDeathAbility

# Necromancer Death Mark payoff. Attached to a cursed enemy's AbilityHost
# with trigger = ON_DEATH and duration = mark duration. When the enemy dies
# while still cursed, BaseEnemy._die fires ON_DEATH on its AbilityHost and
# this ability spawns N friendly skeletons at the corpse. If the mark
# expires without a death, AbilityHost.tick auto-removes the ability (no
# _on_expired override = no spawn).
#
# Owner-agnostic — works on any unit exposing global_position + a
# parent in the scene tree. `summoner` is a non-exported field set at
# attach time so kill-XP from the spawned skeletons routes back to the
# casting hero (BaseEnemy._die walks _last_damage_source._summoner).

const _LifetimeAbilityScript: Script = preload("res://systems/abilities/LifetimeAbility.gd")
const _AbilityDataScript: Script = preload("res://systems/AbilityData.gd")

@export var summon_scene: PackedScene
@export var summon_data: Resource  # SoldierData — duplicated per spawn
@export var count: int = 1
@export var lifetime: float = 12.0
@export var spread_radius: float = 30.0
# Optional spawn VFX (e.g. SoulRiseVFX) instantiated per spawned summon.
@export var spawn_vfx_scene: PackedScene
var summoner: Node


func apply(owner: Node, _ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if summon_scene == null or summon_data == null:
		return
	var tree: SceneTree = owner.get_tree()
	if tree == null:
		return
	var parent: Node = tree.current_scene
	if parent == null:
		return
	var center: Vector2 = owner.global_position
	var eff_count: int = maxi(1, count)
	for i in eff_count:
		var s: CharacterBody2D = summon_scene.instantiate()
		s.data = summon_data.duplicate(true)
		s.add_to_group("soldiers")
		if "_summoner" in s and summoner != null and is_instance_valid(summoner):
			s._summoner = summoner
		parent.add_child(s)
		var angle: float = TAU * float(i) / float(eff_count)
		var off: Vector2 = Vector2(cos(angle), sin(angle)) * spread_radius
		var pos: Vector2 = center + off
		s.global_position = pos
		if s.has_method("setup"):
			s.setup(pos, center)
		var life: Resource = _LifetimeAbilityScript.new()
		life.ability_id = "skel_lifetime"
		life.trigger = _AbilityDataScript.Trigger.ON_SPAWN
		life.duration = lifetime
		if "_ability_host" in s and s._ability_host != null:
			s._ability_host.add_ability(life)
		if spawn_vfx_scene != null:
			var vfx: Node = spawn_vfx_scene.instantiate()
			parent.add_child(vfx)
			if vfx is Node2D:
				(vfx as Node2D).global_position = pos
