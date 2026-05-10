extends SkillData
class_name SummonSoldiersSkillData

# Phase 48 / Stage 3 — Warrior skill #1. AREA-targeted: player taps the
# skill button (arms targeting), then taps a spot within skill_range to
# choose the spawn point. Hero summons N temporary soldiers fanning around
# that spot; they behave like ordinary barracks soldiers (block, charge,
# take damage, draw HP bar) but auto-die after `lifetime` seconds via a
# LifetimeAbility on each soldier's AbilityHost.
#
# If _target is null (e.g. SELF fallback or programmatic call), spawn falls
# back to the hero's position so old SELF-cast call sites still work.
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


func apply(hero: Node, target, _ctx: Dictionary = {}) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if soldier_scene == null or soldier_data == null:
		push_warning("[SummonSoldiers] skill_summon_soldiers.tres missing soldier_scene or soldier_data")
		return
	var parent: Node = hero.get_tree().current_scene
	if parent == null:
		return
	# Spawn center: tap position when AREA-targeted, hero position otherwise.
	# Lets the skill stay backwards-compatible with SELF-cast sites.
	var spawn_center: Vector2 = hero.global_position
	if target is Vector2:
		spawn_center = target
	# Snap to navmesh per CORE RULE 13 — soldiers spawn on walkable ground
	# even if the player taps on water / mountain / off-map. Mirrors the
	# rally-flag pattern in TowerBarracks.
	var world_2d: World2D = hero.get_world_2d()
	if world_2d != null:
		var nav_map: RID = world_2d.navigation_map
		if nav_map.is_valid():
			spawn_center = NavigationServer2D.map_get_closest_point(nav_map, spawn_center)
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
		var rally_pos: Vector2 = spawn_center + off
		soldier.global_position = rally_pos
		if soldier.has_method("setup"):
			# blocking_position = rally; flag_position = the spawn center
			# (so the engagement zone stays anchored where the player tapped,
			# not on a phantom flag and not back at the hero).
			soldier.setup(rally_pos, spawn_center)
		# Auto-despawn — LifetimeAbility's _on_expired calls owner._die() so
		# the soldier dies cleanly (release engagements, fire signals, fall-
		# over death animation).
		var lifetime_ability: Resource = _LifetimeScript.new()
		lifetime_ability.ability_id = "summon_lifetime"
		lifetime_ability.trigger = _AbilityDataScript.Trigger.ON_SPAWN
		lifetime_ability.duration = lifetime
		if "_ability_host" in soldier and soldier._ability_host != null:
			soldier._ability_host.add_ability(lifetime_ability)
	print("[Skill/Summon] %s summoned %d soldiers at %s for %.1fs" % [
		hero.data.hero_name if hero.data != null else "?",
		count,
		spawn_center,
		lifetime,
	])
