extends SkillData
class_name FalconStormSkillData

# Phase 3Q — Ranger AREA-targeted multi-tick skill. Tap a point on the map;
# the cast schedules `tick_count` damage pulses, one every `tick_interval`
# seconds, each dealing `damage` to enemies inside `aoe_radius` of the
# original tap point. The hero stays mobile during the storm — the spell
# fires-and-forgets via async await, so casting Falcon Storm and immediately
# moving the hero is the intended play.
#
# `apply()` is async: each tick is interleaved with `await get_tree().
# create_timer(...)`. The caller (cast_skill) ignores the return value, so
# the coroutine runs in the background.
#
# ctx keys read:
#   damage_mult         → per-tick damage
#   aoe_radius_mult     → tick reach
#   count_mult          → number of ticks (rounded, min 1)
#   duration_mult       → tick interval (slower or faster cadence)

# `damage` and `damage_type` are inherited from SkillData — redeclaring them
# is a parser error ("member already exists in parent class"). Override values
# in the .tres file instead.
@export var aoe_radius: float = 130.0
@export var tick_count: int = 4
@export var tick_interval: float = 0.6
@export var vfx_scene: PackedScene


func apply(hero: Node, target, ctx: Dictionary = {}) -> bool:
	# Sync gate — validates target shape and bails (returning false) so
	# BaseHero.cast_skill can refund the cooldown if the cast is malformed.
	# The actual tick loop is fire-and-forget via _run_storm, which awaits
	# between ticks; cast_skill doesn't await us, so kicking off the async
	# work from a sync wrapper is the cleanest way to keep both contracts.
	if hero == null or not is_instance_valid(hero):
		return false
	if target == null or not (target is Vector2):
		return false
	_run_storm(hero, target, ctx)
	return true


func _run_storm(hero: Node, target: Vector2, ctx: Dictionary) -> void:
	# Pre-merge ctx multipliers once so the loop reads stable locals.
	var eff_count: int = maxi(1, int(round(float(tick_count) * float(ctx.get("count_mult", 1.0)))))
	var eff_damage: float = damage * float(ctx.get("damage_mult", 1.0))
	var eff_radius: float = aoe_radius * float(ctx.get("aoe_radius_mult", 1.0))
	var eff_interval: float = tick_interval * float(ctx.get("duration_mult", 1.0))
	for i in eff_count:
		# Hero may have died / scene swapped between ticks. Bail safely.
		if not is_instance_valid(hero) or hero.get_tree() == null:
			return
		_do_tick(hero, target, eff_damage, eff_radius)
		if i < eff_count - 1:
			# Pass process_always=false so the inter-tick wait freezes with
			# the paused SceneTree. Godot 4.6's create_timer defaults the
			# second arg to TRUE — without explicit false the storm keeps
			# ticking through tactical pause / GameOverScreen pause, which
			# would let post-victory waves of falcons damage cleanup state.
			await hero.get_tree().create_timer(eff_interval, false).timeout


func _do_tick(hero: Node, center: Vector2, dmg: float, r: float) -> void:
	var r2: float = r * r
	for enemy in hero.get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy):
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if center.distance_squared_to(enemy.global_position) <= r2:
			enemy.take_damage(dmg, damage_type, hero)
	# Per-tick VFX. Same pattern as ShieldBashSkillData — instantiate, place,
	# call setup() if the scene has it. Falcon Storm has many ticks, so the
	# VFX scene should be self-cleaning (queue_free after its animation).
	if vfx_scene != null:
		var vfx: Node = vfx_scene.instantiate()
		hero.get_tree().current_scene.add_child(vfx)
		if vfx is Node2D:
			(vfx as Node2D).global_position = center
		if vfx.has_method("setup"):
			vfx.setup(r)
