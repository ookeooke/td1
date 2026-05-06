extends CharacterBody2D
class_name BaseSoldier

# Phase 16+42: ground blocker with NavigationAgent2D pathfinding.
# Spawned by TowerBarracks, nav-paths to its `blocking_position`, then
# engages the first non-flying BaseEnemy that overlaps its MeleeRange.
# Engagement pins the enemy to State.COMBAT so its path progress halts.
# Both sides attack on Timers. On soldier death the enemy is released
# back to WALKING and the barracks schedules a respawn via soldier_died.

enum State { MOVING, BLOCKING, CHARGING, RETURNING, DEAD }

const HP_BAR_SIZE: Vector2 = Vector2(55.0, 8.0)
const HP_BAR_Y_OFFSET: float = -40.0
const HIT_FLASH_DURATION: float = 0.08
# Lunge animation — same shape as the hero's. Slightly smaller distance
# since the militia square is half the hero's footprint.
const LUNGE_DURATION: float = 0.12
const LUNGE_DISTANCE: float = 12.0

@export var data: Resource  # SoldierData — typed loosely until Godot indexes the class_name

var state: int = State.MOVING
var current_health: int = 0
var _effective_max_hp: int = 0  # set in _ready with upgrade multiplier

var _blocking_position: Vector2 = Vector2.ZERO
# Flag world position — center of the barracks's engagement zone. Multiple
# soldiers in one squad share the same flag position even though each has
# its own slot. Set by TowerBarracks in setup() and kept in sync when the
# player drags the flag.
var _flag_position: Vector2 = Vector2.ZERO
# Enemies this soldier currently blocks. Capped at data.max_block_targets
# (default 1 for basic grunts). Populated via _try_engage; drained on
# death, rally-flag move, or enemy death/walk-out.
var _engaged_enemies: Array[Node] = []
var _attack_cooldown: float = 0.0

var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_t: float = 0.0
var _hit_flash_t: float = 0.0
# Animation pipeline parity with BaseHero/BaseEnemy. Drives walk-bob, flinch,
# breath, hit-stop, direction-aware eyes, and per-soldier skin variation
# through UnitVisualDrawer's ctx Dictionary.
const FLINCH_DURATION: float = 0.12
const FLINCH_DISTANCE: float = 5.0
const HIT_STOP_DURATION: float = 0.05
var _walk_t: float = 0.0
var _walk_phase: float = 0.0
# Stuck-in-MOVING fallback. If the soldier hasn't made meaningful progress
# toward the rally for STUCK_TIMEOUT seconds, force the BLOCKING transition.
# Prevents the walk-loop bug where overshoot oscillation around a navmesh
# edge point kept the top-row soldiers in MOVING forever.
const ARRIVE_THRESHOLD: float = 8.0
const STUCK_TIMEOUT: float = 1.5
var _stuck_t: float = 0.0
var _stuck_last_pos: Vector2 = Vector2.ZERO
var _flinch_t: float = 0.0
var _flinch_dir: Vector2 = Vector2.ZERO
var _breath_t: float = 0.0
var _hit_stop_t: float = 0.0
var _facing_dir: Vector2 = Vector2.RIGHT
var _prev_pos: Vector2 = Vector2.ZERO
var _skin_tint: Color = Color.WHITE

# Kingdom-Rush charge: enemy this soldier is committed to chase after
# spotting it in aggro_range. Cleared when the target dies or the soldier
# successfully engages it (the engagement itself then holds position).
var _charge_target: BaseEnemy = null

# Phase 20.5: passive-ability dispatcher (same primitive as BaseEnemy /
# BaseHero). Paladin-style soldiers attach HealAuraAbility here; shield
# soldiers attach DamageBlockAbility; etc. — all variants author as data.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
const _FloatingTextScript := preload("res://vfx/FloatingText.gd")
const _DeathVFXScript := preload("res://vfx/DeathVFX.gd")
var _ability_host: RefCounted = null

@onready var melee_range: Area2D = $MeleeRange
@onready var melee_shape: CollisionShape2D = $MeleeRange/CollisionShape2D
@onready var aggro_range: Area2D = $AggroRange
@onready var aggro_shape: CollisionShape2D = $AggroRange/CollisionShape2D


func _ready() -> void:
	if data:
		# Phase 28: permanent upgrade (Reinforced Walls / Soldier HP = type 7).
		_effective_max_hp = int(ceil(float(data.max_health) * MetaProgression.get_upgrade_multiplier(MetaProgression.MOD_SOLDIER_HEALTH)))
		current_health = _effective_max_hp
		var circle := CircleShape2D.new()
		circle.radius = data.melee_range
		melee_shape.shape = circle
		# Aggro sensor must exceed melee range — a charge that's smaller than
		# melee contact would never fire. A .tres that leaves aggro_range at 0
		# collapses to no-charge (behaves like the pre-Phase-45d pure wait).
		var aggro_circle := CircleShape2D.new()
		var aggro_r: float = data.aggro_range if "aggro_range" in data else 0.0
		aggro_circle.radius = maxf(data.melee_range, aggro_r)
		aggro_shape.shape = aggro_circle
	_ability_host = _AbilityHostScript.new(self)
	if data != null and "abilities" in data:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	# Per-soldier variation: phase + skin tint randomized at spawn so a
	# squad of three doesn't march and look identical.
	_walk_phase = randf() * TAU
	var v_seed: float = randf()
	var tint_amount: float = (v_seed - 0.5) * 0.10
	_skin_tint = Color(1.0 + tint_amount, 1.0 + tint_amount * 0.6, 1.0 + tint_amount * 0.3, 1.0)
	_prev_pos = global_position


func setup(blocking_position: Vector2, flag_position: Vector2 = Vector2.INF) -> void:
	_blocking_position = blocking_position
	# Fallback (legacy callers that don't pass a flag): use the slot itself
	# as zone center. New callers (TowerBarracks) always pass the real flag.
	_flag_position = flag_position if flag_position != Vector2.INF else blocking_position


func set_blocking_position(new_pos: Vector2, flag_position: Vector2 = Vector2.INF) -> void:
	# Called when the player drags the barracks flag. Break all engagements,
	# drop any mid-charge pursuit, and walk to the new rally slot in a direct
	# straight line (per CORE RULE 13 — navmesh constrains rally placement,
	# not soldier pathing).
	_blocking_position = new_pos
	if flag_position != Vector2.INF:
		_flag_position = flag_position
	_release_all_engagements()
	_charge_target = null
	if state != State.DEAD:
		change_state(State.MOVING)


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	# Reset stuck-detector + walk accumulator on any transition into / out of
	# MOVING so the next traversal starts clean and the previous walk-bob
	# phase doesn't persist into the rest pose.
	if new_state == State.MOVING:
		_stuck_t = 0.0
		_stuck_last_pos = global_position
	if state == State.MOVING and new_state != State.MOVING:
		_walk_t = 0.0
	state = new_state


func _physics_process(delta: float) -> void:
	if state == State.DEAD or data == null:
		return
	# Hit-stop — universal freeze for a few frames after every hit. Matches
	# BaseHero / BaseEnemy behavior so combat reads consistently.
	if _hit_stop_t > 0.0:
		_hit_stop_t = maxf(0.0, _hit_stop_t - delta)
		return
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		queue_redraw()
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
		queue_redraw()
	if _flinch_t > 0.0:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		queue_redraw()
	# Facing direction — sampled from world delta. Falls back to lunge dir
	# when soldier is stationary so eyes still face the target while engaged.
	var dp: Vector2 = global_position - _prev_pos
	if dp.length_squared() > 0.05:
		_facing_dir = dp.normalized()
	elif _lunge_t > 0.0 and _lunge_dir.length_squared() > 0.001:
		_facing_dir = _lunge_dir
	_prev_pos = global_position
	if _ability_host != null:
		_ability_host.tick(delta)
	# Walk-bob accumulator — ticks in any state where we're actually moving
	# (MOVING, CHARGING, RETURNING). Idle states use breath instead.
	var moving_state: bool = state == State.MOVING or state == State.CHARGING or state == State.RETURNING
	if moving_state and data != null and data.visual != null:
		var v: UnitVisualData = data.visual
		if v.walk_bob_amplitude > 0.0 or v.walk_squash > 0.0:
			_walk_t += delta
			queue_redraw()
	elif state == State.BLOCKING:
		_breath_t += delta
		queue_redraw()
	match state:
		State.MOVING:
			# Direct straight-line motion toward the assigned rally slot.
			# Rally slot positions are snapped to navmesh by TowerBarracks, so
			# soldiers always arrive on walkable terrain. No nav-agent routing.
			var to_target: Vector2 = _blocking_position - global_position
			var dist: float = to_target.length()
			var step: float = data.move_speed * delta
			# Arrive when within the threshold OR when the next frame would
			# overshoot the target (prevents oscillation around the slot).
			if dist <= ARRIVE_THRESHOLD or dist <= step:
				global_position = _blocking_position
				velocity = Vector2.ZERO
				change_state(State.BLOCKING)
			else:
				velocity = to_target.normalized() * data.move_speed
				move_and_slide()
				# Stuck-detection: if the soldier hasn't moved much since the
				# last sample and is still in MOVING, count up. Force-block
				# after STUCK_TIMEOUT so a slot the soldier physically can't
				# reach (snapped onto an edge, etc.) doesn't loop forever.
				if global_position.distance_squared_to(_stuck_last_pos) < 0.25:
					_stuck_t += delta
					if _stuck_t >= STUCK_TIMEOUT:
						global_position = _blocking_position
						velocity = Vector2.ZERO
						change_state(State.BLOCKING)
						_stuck_t = 0.0
				else:
					_stuck_t = 0.0
				_stuck_last_pos = global_position
		State.BLOCKING:
			# Idle at rally. Anything in melee_range already gets engaged
			# (covers enemies that wandered right into us); otherwise scan
			# the wider aggro_range and charge out after the best target.
			_try_engage()
			if _engaged_enemies.is_empty():
				_scan_aggro_and_maybe_charge()
			velocity = Vector2.ZERO
			move_and_slide()
			_attack_cycle(delta)
		State.CHARGING:
			_tick_charge()
			_attack_cycle(delta)
		State.RETURNING:
			var to_rally: Vector2 = _blocking_position - global_position
			if to_rally.length() < 3.0:
				velocity = Vector2.ZERO
				change_state(State.BLOCKING)
			else:
				velocity = to_rally.normalized() * data.move_speed
			move_and_slide()


func _try_engage() -> void:
	# Drop stale/dead engagements first — they free capacity for new ones.
	_prune_engagements()
	var cap: int = data.max_block_targets if data != null and "max_block_targets" in data else 1
	if _engaged_enemies.size() >= cap:
		return
	# Split-rule pick: prefer enemies with the fewest current blockers so
	# multiple soldiers/heroes don't pile on the same target when there
	# are other threats to block. Ties broken by distance.
	var best: BaseEnemy = null
	var best_block: int = 1 << 30
	var best_d2: float = INF
	for area in melee_range.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.data == null or enemy.data.is_flying:
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if _engaged_enemies.has(enemy):
			continue
		var bc: int = enemy._blockers.size()
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if bc < best_block or (bc == best_block and d2 < best_d2):
			best_block = bc
			best_d2 = d2
			best = enemy
	if best != null and best.engage_combat(self):
		_engaged_enemies.append(best)


func _attack_cycle(delta: float) -> void:
	_prune_engagements()
	if _engaged_enemies.is_empty():
		return
	# Focus the first engager slot — the enemy this soldier committed to
	# first — so the lunge and damage stay consistent instead of rotating
	# every tick.
	var enemy: BaseEnemy = _engaged_enemies[0]
	if enemy == null or not is_instance_valid(enemy) or enemy.state == BaseEnemy.State.DYING:
		_engaged_enemies.pop_front()
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	_start_lunge(enemy.global_position)
	var pre_dying: bool = enemy.state == BaseEnemy.State.DYING
	enemy.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": data.attack_damage})
		if not pre_dying and enemy.state == BaseEnemy.State.DYING:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


# KR-style charge sensor: idle soldier at rally picks the best enemy in
# aggro_range (split-rule: fewest blockers, then nearest) and transitions
# into CHARGING. Respects max_block_targets so a full-capacity soldier
# won't start a new chase.
func _scan_aggro_and_maybe_charge() -> void:
	if data == null:
		return
	var cap: int = data.max_block_targets if "max_block_targets" in data else 1
	if _engaged_enemies.size() >= cap:
		return
	# Engagement zone = leash_range circle centered on the barracks flag.
	# Enemies outside the zone aren't this barracks's problem, even if
	# they're physically within the soldier's aggro Area2D (which moves
	# with the soldier and would otherwise pick up past-the-barracks
	# enemies that are geographically close).
	var zone: float = data.leash_range if "leash_range" in data else 0.0
	var zone2: float = zone * zone
	var best: BaseEnemy = null
	var best_block: int = 1 << 30
	var best_d2: float = INF
	for area in aggro_range.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.data == null or enemy.data.is_flying:
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if zone > 0.0 and _flag_position.distance_squared_to(enemy.global_position) > zone2:
			continue
		var bc: int = enemy._blockers.size()
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if bc < best_block or (bc == best_block and d2 < best_d2):
			best_block = bc
			best_d2 = d2
			best = enemy
	if best != null:
		_charge_target = best
		change_state(State.CHARGING)


# Moves the soldier toward its committed charge target. As soon as the
# target enters melee_range the normal _try_engage picks it up, which fills
# _engaged_enemies and stops forward motion. When every engagement drops
# (target died or walked off), the soldier heads back to its rally slot.
func _tick_charge() -> void:
	_try_engage()
	_prune_engagements()
	if _charge_target != null and (not is_instance_valid(_charge_target) or _charge_target.state == BaseEnemy.State.DYING):
		_charge_target = null
	# Holding an engagement → plant feet next to the enemy; combat_tick
	# will run from _attack_cycle. Don't chase further targets while busy.
	if not _engaged_enemies.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Zone gate: if our target has walked out of the flag's engagement
	# circle (the barracks's area of responsibility), it is no longer our
	# problem — drop it and head home. Radius = leash_range, centered on
	# the shared flag position (not this soldier's individual slot), so
	# all squad members share one coherent zone.
	var zone: float = data.leash_range if "leash_range" in data else 0.0
	if _charge_target != null and is_instance_valid(_charge_target) and zone > 0.0:
		if _flag_position.distance_squared_to(_charge_target.global_position) > zone * zone:
			_charge_target = null
			change_state(State.RETURNING)
			return
	# Leash: if we've drifted past leash_range from our rally slot chasing a
	# target we still haven't contacted, give up and head home. Protects
	# against faster-than-soldier enemies dragging us off-lane.
	var leash: float = zone
	if leash > 0.0 and global_position.distance_to(_blocking_position) > leash:
		_charge_target = null
		change_state(State.RETURNING)
		return
	# Lost our chase target before making contact → go home.
	if _charge_target == null:
		change_state(State.RETURNING)
		return
	var to_target: Vector2 = _charge_target.global_position - global_position
	if to_target.length() < 3.0:
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * data.move_speed
	move_and_slide()


# Release every enemy we currently engage. Also called by set_blocking_position
# and _die to free enemies cleanly.
func _release_all_engagements() -> void:
	for e in _engaged_enemies:
		if e != null and is_instance_valid(e):
			e.release_combat(self)
	_engaged_enemies.clear()


# Drop dead/invalid engagements so _try_engage can pick replacements.
func _prune_engagements() -> void:
	var keep: Array[Node] = []
	for e in _engaged_enemies:
		if e == null or not is_instance_valid(e):
			continue
		if e.state == BaseEnemy.State.DYING:
			e.release_combat(self)
			continue
		keep.append(e)
	if keep.size() != _engaged_enemies.size():
		_engaged_enemies = keep


func _start_lunge(target_world_pos: Vector2) -> void:
	var dir: Vector2 = target_world_pos - global_position
	if dir.length_squared() < 0.01:
		return
	_lunge_dir = dir.normalized()
	_lunge_t = LUNGE_DURATION
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	# Matches BaseHero wind-up curve — rear back, commit, recover.
	var t: float = 1.0 - (_lunge_t / LUNGE_DURATION)
	var offset_scale: float = 0.0
	if t < 0.25:
		offset_scale = -0.3 * (t / 0.25)
	elif t < 0.75:
		offset_scale = -0.3 + 1.3 * ((t - 0.25) / 0.5)
	else:
		offset_scale = 1.0 - ((t - 0.75) / 0.25)
	return _lunge_dir * (LUNGE_DISTANCE * offset_scale)


func take_damage(amount: float, type: int, source: Node = null) -> float:
	if state == State.DEAD or data == null:
		return 0.0
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if final > 0.0:
		_hit_flash_t = HIT_FLASH_DURATION
		# Hit-stop on both this soldier and the source.
		_hit_stop_t = HIT_STOP_DURATION
		if source != null and is_instance_valid(source) and "_hit_stop_t" in source:
			source._hit_stop_t = HIT_STOP_DURATION
		# Flinch — recoil away from damage source.
		_flinch_t = FLINCH_DURATION
		var have_src_pos: bool = false
		var src_pos: Vector2 = Vector2.ZERO
		if source != null and is_instance_valid(source) and source is Node2D:
			src_pos = (source as Node2D).global_position
			have_src_pos = true
		if have_src_pos:
			var away: Vector2 = global_position - src_pos
			if away.length_squared() > 0.001:
				_flinch_dir = away.normalized()
			else:
				_flinch_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.0)).normalized()
		else:
			_flinch_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.0)).normalized()
		EventBus.hit_landed.emit(self, source, final, type)
		var parent: Node = get_tree().current_scene
		if parent != null:
			_FloatingTextScript.spawn(parent, str(int(ceil(final))), Color(1.0, 0.85, 0.2), global_position + Vector2(0, -40), 26)
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()
	return final


func _die() -> void:
	change_state(State.DEAD)
	_release_all_engagements()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.soldier_died.emit(self)
	# Impact ring + dust puff at fall point — same DeathVFX enemies use,
	# colored from the soldier's body so the burst reads as "this guy fell".
	var parent: Node = get_tree().current_scene
	if parent != null and data != null and data.visual != null:
		var ring_color: Color = data.visual.body_color
		var ring_radius: float = data.visual.radius if data.visual.shape == UnitVisualData.Shape.CIRCLE else maxf(data.visual.body_size.x, data.visual.body_size.y) * 0.5
		_DeathVFXScript.spawn(parent, ring_color, ring_radius, global_position)
	# Fall-over death — tip the body ~90° and fade out over 0.4 s before
	# freeing. Tween inherits pause mode so tactical pause freezes it.
	var tilt_dir: float = 1.0 if randf() < 0.5 else -1.0
	var facing: Vector2 = _lunge_dir if _lunge_dir.length_squared() > 0.0001 else Vector2.RIGHT
	EventBus.soldier_fell.emit(self, facing)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "rotation", PI * 0.5 * tilt_dir, 0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	# 1. Ground shadow — anchored under feet, ignores body offset/scale.
	if data != null and data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		UnitVisualDrawer.draw_ground_shadow(self, data.visual)

	# 2. Compose body offset + scale.
	var lunge_off: Vector2 = _lunge_offset()
	var body_offset: Vector2 = lunge_off
	var body_scale: Vector2 = Vector2.ONE
	var moving_state: bool = state == State.MOVING or state == State.CHARGING or state == State.RETURNING
	var walk_rotation: float = 0.0
	if data != null and data.visual != null and moving_state:
		var anim: Dictionary = UnitVisualDrawer.compute_walk_anim(data.visual, _walk_t, _walk_phase)
		body_offset += anim.offset
		body_scale = anim.scale
		walk_rotation = anim.get("rotation", 0.0)
	if _flinch_t > 0.0:
		var fa: float = _flinch_t / FLINCH_DURATION
		body_offset += _flinch_dir * FLINCH_DISTANCE * fa
	if state == State.BLOCKING:
		var breath: float = sin(_breath_t * 2.5) * 0.025
		body_scale.x *= 1.0 + breath
		body_scale.y *= 1.0 - breath
	# Impact squash on attack commit — peaks around the strike frame.
	if _lunge_t > 0.0:
		var lt: float = 1.0 - (_lunge_t / LUNGE_DURATION)
		if lt > 0.30 and lt < 0.65:
			var sq: float = sin((lt - 0.30) / 0.35 * PI) * 0.18
			body_scale.x *= 1.0 + sq
			body_scale.y *= 1.0 - sq

	# 3. Build ctx for the drawer.
	var ctx: Dictionary = {}
	if data != null and data.visual != null:
		ctx["skin_tint"] = _skin_tint
		ctx["face"] = _facing_dir
		if walk_rotation != 0.0:
			ctx["walk_rotation"] = walk_rotation
		var max_hp: int = _effective_max_hp if _effective_max_hp > 0 else (data.max_health if data != null else 1)
		if max_hp > 0 and float(current_health) / float(max_hp) < 0.30:
			ctx["low_hp"] = true
		# Wind-up / strike-arc derived from lunge curve, mirroring BaseHero.
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / LUNGE_DURATION)
			if t01 < 0.30:
				ctx["wind_t"] = clampf(t01 / 0.30, 0.0, 1.0)
			else:
				ctx["strike_t"] = clampf((t01 - 0.30) / 0.65, 0.0, 1.0)
				ctx["strike_dir"] = _lunge_dir

	# 4. Body draw.
	if data != null and data.visual != null:
		var walk_t_arg: float = _walk_t if moving_state else -1.0
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale, walk_t_arg, _walk_phase, ctx)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / LUNGE_DURATION)
			UnitVisualDrawer.draw_swing_arc_trail(self, data.visual, _lunge_dir, t01)
	else:
		# Legacy fallback.
		if body_offset != Vector2.ZERO:
			draw_set_transform(body_offset, 0.0, body_scale)
		draw_rect(Rect2(-15, -15, 30, 30), Color(0.8, 0.8, 0.2))
		draw_rect(Rect2(-15, -15, 30, 30), Color(0.3, 0.25, 0.05), false, 3.0)
		if body_offset != Vector2.ZERO:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar()


func _draw_health_bar() -> void:
	var max_hp: int = _effective_max_hp if _effective_max_hp > 0 else (data.max_health if data != null else 0)
	if max_hp <= 0:
		return
	if current_health >= max_hp:
		return
	var zs: float = _get_zoom_scale()
	var bar_size: Vector2 = HP_BAR_SIZE * zs
	var bar_y: float = HP_BAR_Y_OFFSET * zs
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-bar_size.x * 0.5, bar_y)
	draw_rect(Rect2(origin, bar_size), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(bar_size.x * pct, bar_size.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0), false, 1.0)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
