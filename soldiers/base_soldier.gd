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

# Identity of the parent barracks — populated by TowerBarracks._spawn_soldier
# so this instance can look up debug-only stat multipliers (HP / damage /
# attack_speed) keyed by (tower_id, tier_key) in BalanceOverrides. Empty
# strings = no overrides applied (production runtime / orphan spawns).
var tower_id: String = ""
var tier_key: String = ""
# Optional owning hero — populated by SummonSoldiersSkillData when this
# soldier was spawned by a Knight's Summon Soldiers cast. Null = standard
# barracks soldier, no XP credit on kill (towers don't have XP). When set,
# BaseEnemy._die routes the kill's xp_worth to this hero so the cooldown
# spent on the summon pays back in progression. Read by other scripts via
# reflection (`"_summoner" in soldier`), not by any method on this class.
@warning_ignore("unused_private_class_variable")
var _summoner: Node = null
const _BalanceOverrides := preload("res://balance/debug/BalanceOverrides.gd")

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
# Swing duration captured at strike start so the normalization stays stable
# even if attack_speed changes mid-swing. Cadence-scaled (see swing_duration).
var _lunge_dur: float = LUNGE_DURATION
var _hit_flash_t: float = 0.0
# Active status effects keyed by id ("burn", "poison", "slow", "stun").
# Mirrors the BaseEnemy pattern, with persistent foot rings drawn in _draw().
# Added in 2026-05-25 when the Goblin Fire Archer introduced the first
# enemy → friendly status effect (burn DoT).
var _effects: Dictionary = {}
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
# Combat Ground Line — mirror of BaseHero. Close the vertical (lane) gap at
# least as fast as the horizontal one while charging so the soldier reaches
# the enemy's Y *during* the charge instead of snapping to it at the end.
const APPROACH_Y_PRIORITY: float = 1.0
const Y_ALIGN_EPS: float = 2.0
# Assist-in-lull: when WaveManager says only the last engageable enemy
# remains, an idle soldier may charge it even outside its guard zone, up
# to this distance (avoids a cross-map sprint on huge maps; generous
# because by definition nothing else needs blocking). Tunable.
const ASSIST_MAX_DIST: float = 1100.0
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
# True while charging/holding a lone straggler acquired via the combat
# lull (outside the normal guard zone). Lowest-priority behavior — any
# normal guarded target or the lull ending preempts it.
var _assisting: bool = false
var _in_lull: bool = false
# Soldier claim watchdog — mirrors BaseHero.CLAIM_TIMEOUT. A soft claim
# reserves (freezes) an enemy before contact; if contact never happens
# (path blocked, or an assist chase toward an unreachable straggler) the
# enemy would stay frozen forever and the wave soft-locks. Drop the claim
# after this long without a hard engagement.
const CLAIM_TIMEOUT: float = 4.0
var _claim_age: float = 0.0
# Combat Blocking Doctrine — stop-on-claim (same model as BaseHero). The
# enemy this soldier has committed to is reserved so it halts and waits
# while the soldier walks over, instead of being chased while moving.
# _sync_claim() reconciles this every frame; _release_claim() clears it on
# death/despawn (physics is skipped while DEAD).
var _claimed_enemy: Node = null

# Phase 20.5: passive-ability dispatcher (same primitive as BaseEnemy /
# BaseHero). Paladin-style soldiers attach HealAuraAbility here; shield
# soldiers attach DamageBlockAbility; etc. — all variants author as data.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
const _DeathVFXScript := preload("res://vfx/DeathVFX.gd")
const _GuardZoneScript := preload("res://systems/GuardZone.gd")
var _ability_host: RefCounted = null

@onready var melee_range: Area2D = $MeleeRange
@onready var melee_shape: CollisionShape2D = $MeleeRange/CollisionShape2D
@onready var aggro_range: Area2D = $AggroRange
@onready var aggro_shape: CollisionShape2D = $AggroRange/CollisionShape2D


func _ready() -> void:
	if data:
		# Phase 28: permanent upgrade (Reinforced Walls / Soldier HP = type 7).
		_effective_max_hp = int(ceil(float(data.max_health) \
			* MetaProgression.get_upgrade_multiplier(MetaProgression.MOD_SOLDIER_HEALTH) \
			* _soldier_mult("soldier_hp_mult")))
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
	if not EventBus.combat_lull_changed.is_connected(_on_combat_lull_changed):
		EventBus.combat_lull_changed.connect(_on_combat_lull_changed)


func _on_combat_lull_changed(in_lull: bool) -> void:
	_in_lull = in_lull
	# Lull ended (more enemies arrived). A soldier still only ASSISTING
	# (not yet hard-engaged) must drop it and resume normal block-many
	# duty. One that already hard-locked stays — it's a normal block now.
	if not in_lull and _assisting and _engaged_enemies.is_empty():
		_assisting = false
		_charge_target = null
		_sync_claim()
		if state == State.CHARGING:
			change_state(State.RETURNING)


# Read a debug-only soldier-stat multiplier from BalanceOverrides keyed by
# (tower_id, tier_key). Returns 1.0 (identity) for orphan spawns / production
# runtime / when the stat hasn't been overridden — same convention as the
# combat-tower mult getters in base_tower.gd.
func _soldier_mult(stat: String) -> float:
	if tower_id == "" or tier_key == "":
		return 1.0
	return _BalanceOverrides.get_tower_mult(tower_id, tier_key, stat)


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
	# Also drop the soft (reserve) claim now, not next frame. _sync_claim would
	# reconcile it anyway (desired→null after the clears below), but releasing
	# explicitly means a reserved enemy resumes walking the instant the flag
	# moves instead of staying frozen for one physics tick. Idempotent; mirrors
	# _die()'s explicit _release_claim(). _sync_claim stays the steady-state
	# choke-point — this is only the edge release.
	_release_claim()
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
	# Status effects tick BEFORE hit-stop so a burn DoT doesn't pause every
	# time the soldier eats a hit (which would compress the burn window).
	if not _effects.is_empty():
		_tick_effects(delta)
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
	_sync_claim()
	# Claim watchdog — a soft claim with no hard engagement that drags on
	# past CLAIM_TIMEOUT means contact will never happen (path blocked /
	# assist toward an unreachable straggler). Drop it so the reserved
	# enemy resumes instead of freezing the wave forever.
	if _claimed_enemy != null and _engaged_enemies.is_empty():
		_claim_age += delta
		if _claim_age > CLAIM_TIMEOUT:
			_release_claim()
			_charge_target = null
			_assisting = false
			_claim_age = 0.0
			if state == State.CHARGING:
				change_state(State.RETURNING)
	else:
		_claim_age = 0.0
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
			var step: float = _effective_move_speed() * delta
			# Arrive when within the threshold OR when the next frame would
			# overshoot the target (prevents oscillation around the slot).
			if dist <= ARRIVE_THRESHOLD or dist <= step:
				global_position = _blocking_position
				velocity = Vector2.ZERO
				change_state(State.BLOCKING)
			else:
				velocity = to_target.normalized() * _effective_move_speed()
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
				velocity = to_rally.normalized() * _effective_move_speed()
			move_and_slide()


func _try_engage() -> void:
	# Drop stale/dead engagements first — they free capacity for new ones.
	_prune_engagements()
	var cap: int = data.max_block_targets if data != null and "max_block_targets" in data else 1
	if _engaged_enemies.size() >= cap:
		return
	# Combat Blocking Doctrine — target selection: only consider enemies
	# inside the guard zone, prefer fewest current blockers, then highest
	# path progress (closer-to-exit threat first), then nearest. Same rule
	# the hero uses for extra-block picks. See docs/COMBAT_BLOCKING_DOCTRINE.md.
	var best: BaseEnemy = null
	var best_block: int = 1 << 30
	var best_progress: float = -INF
	var best_d2: float = INF
	for area in melee_range.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		# Shared predicate: skip flying/bypass/dying/no-data uniformly.
		if not enemy.is_engageable_ground():
			continue
		if _engaged_enemies.has(enemy):
			continue
		if not _is_guardable(enemy):
			continue
		var bc: int = enemy.get_claim_count() if enemy.has_method("get_claim_count") else enemy._blockers.size()
		var prog: float = enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if bc < best_block \
				or (bc == best_block and prog > best_progress) \
				or (bc == best_block and prog == best_progress and d2 < best_d2):
			best_block = bc
			best_progress = prog
			best_d2 = d2
			best = enemy
	if best != null and best.engage_combat(self):
		_engaged_enemies.append(best)


# Combat Blocking Doctrine helper — is `enemy` inside this soldier's guard
# zone around the rally flag? Falls back to world distance if the enemy's
# path data is unavailable. See systems/GuardZone.gd.
func _is_guardable(enemy) -> bool:
	if data == null:
		return false
	var front: float = data.guard_front_px if "guard_front_px" in data else 0.0
	var back: float = data.guard_back_px if "guard_back_px" in data else 0.0
	return _GuardZoneScript.is_guardable(enemy, _flag_position, front, back)


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
	var eff_atk_speed: float = data.attack_speed * _soldier_mult("soldier_attack_speed_mult")
	_attack_cooldown = 1.0 / maxf(0.01, eff_atk_speed)
	_start_lunge(enemy.global_position)
	var pre_dying: bool = enemy.state == BaseEnemy.State.DYING
	var eff_dmg: float = data.attack_damage * _soldier_mult("soldier_damage_mult")
	enemy.take_damage(eff_dmg, DamageCalculator.DamageType.PHYSICAL, self)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": eff_dmg})
		if not pre_dying and enemy.state == BaseEnemy.State.DYING:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


# Combat Blocking Doctrine charge sensor: idle soldier at rally picks the
# best in-guard-zone enemy and transitions into CHARGING. Guard zone is
# path-projected when possible (world-distance fallback). Target selection:
# fewest blockers → highest path progress → nearest. Respects max_block_targets
# so a full-capacity soldier won't start a new chase.
func _scan_aggro_and_maybe_charge() -> void:
	if data == null:
		return
	var cap: int = data.max_block_targets if "max_block_targets" in data else 1
	if _engaged_enemies.size() >= cap:
		return
	var best: BaseEnemy = null
	var best_block: int = 1 << 30
	var best_progress: float = -INF
	var best_d2: float = INF
	for area in aggro_range.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		# Shared predicate: skip flying/bypass/dying/no-data uniformly.
		if not enemy.is_engageable_ground():
			continue
		if not _is_guardable(enemy):
			continue
		var bc: int = enemy.get_claim_count() if enemy.has_method("get_claim_count") else enemy._blockers.size()
		var prog: float = enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if bc < best_block \
				or (bc == best_block and prog > best_progress) \
				or (bc == best_block and prog == best_progress and d2 < best_d2):
			best_block = bc
			best_progress = prog
			best_d2 = d2
			best = enemy
	if best != null:
		_charge_target = best
		_assisting = false
		_sync_claim()
		change_state(State.CHARGING)
		return
	# Assist-in-lull fallback (lowest priority): no guardable target AND
	# only the last engageable enemy remains AND we're free. Charge it
	# even though it's outside the guard zone, within ASSIST_MAX_DIST.
	# Reuses the normal charge/engage path; the guard-zone cancel in
	# _tick_charge is skipped while _assisting.
	if _in_lull and _engaged_enemies.is_empty() and _charge_target == null:
		var lone: Node = WaveManager.lone_enemy()
		if lone != null and is_instance_valid(lone) and lone is BaseEnemy \
				and lone.is_engageable_ground() \
				and global_position.distance_to(lone.global_position) <= ASSIST_MAX_DIST:
			_charge_target = lone
			_assisting = true
			_sync_claim()
			change_state(State.CHARGING)


# Combat Ground Line — unit steer that never closes the vertical (lane) gap
# slower than the horizontal one (mirror of BaseHero._ground_line_dir), so
# the soldier rises onto the enemy's Y during the charge, not in a fast
# end-of-charge snap. Speed unchanged (caller × move_speed) — only direction.
func _ground_line_dir(to_target: Vector2) -> Vector2:
	var d: Vector2 = to_target
	var ay: float = absf(to_target.y)
	if ay > Y_ALIGN_EPS:
		var x_cap: float = ay * APPROACH_Y_PRIORITY
		if absf(to_target.x) > x_cap:
			d = Vector2(signf(to_target.x) * x_cap, to_target.y)
	if d.length_squared() < 0.000001:
		return Vector2.ZERO
	return d.normalized()


# Moves the soldier toward its committed charge target. As soon as the
# target enters melee_range the normal _try_engage picks it up, which fills
# _engaged_enemies and stops forward motion. When every engagement drops
# (target died or walked off), the soldier heads back to its rally slot.
func _tick_charge() -> void:
	_try_engage()
	_prune_engagements()
	if _charge_target != null and (not is_instance_valid(_charge_target) or _charge_target.state == BaseEnemy.State.DYING):
		_charge_target = null
	# Holding an engagement → settle onto the enemy's exact lane-Y, then
	# plant. The engaged enemy is reserved (stop-on-claim) so it's frozen;
	# if melee contact registered while we were still off-Y, finish closing
	# the short remaining distance to the Y-locked spot at move_speed
	# (continuous — no teleport, CORE RULE 13) so the duel reads on one
	# ground line. Once aligned, hold position. Don't chase further targets.
	if not _engaged_enemies.is_empty():
		_assisting = false  # hard contact made — it's a normal block now
		var eng: Node = _engaged_enemies[0]
		var settled: bool = true
		# Enemy is in _engaged_enemies ⇒ we hard-block it ⇒ it's frozen
		# (BaseEnemy COMBAT doesn't advance path progress), so the Y-locked
		# spot is stationary and safe to walk the last few px onto.
		if eng != null and is_instance_valid(eng) and eng.state != BaseEnemy.State.DYING:
			var mr2: float = data.melee_range if data != null and "melee_range" in data else 24.0
			var g2: float = maxf(mr2 * 0.8, 12.0)
			var f2: Vector2 = _GuardZoneScript.path_forward_at(eng)
			if f2 == Vector2.ZERO:
				f2 = Vector2(signf(eng.global_position.x - global_position.x), 0.0)
			var slot2: int = eng.block_slot_for(self) if eng.has_method("block_slot_for") else 0
			var sp2: Vector2 = _GuardZoneScript.melee_engage_spot(eng.global_position, f2, g2, slot2)
			var to_sp2: Vector2 = sp2 - global_position
			if to_sp2.length() > 4.0:
				velocity = _ground_line_dir(to_sp2) * _effective_move_speed()
				settled = false
		if settled:
			velocity = Vector2.ZERO
		move_and_slide()
		return
	# Combat Blocking Doctrine — guard-zone gate. If the chase target has
	# left the guard zone (path-projected when possible, world-distance
	# fallback otherwise) the soldier disengages pre-contact and heads home.
	# This is the "no chasing past the guard zone" rule. Once physical
	# engagement has succeeded the lock holds regardless — that's
	# _engaged_enemies above, which already short-circuits.
	# Assist charges deliberately ignore the guard-zone cancel (the lone
	# straggler is outside the zone by definition). Lull-end / target-loss
	# still preempts assist via _on_combat_lull_changed and the checks below.
	if _charge_target != null and is_instance_valid(_charge_target):
		if not _assisting and not _is_guardable(_charge_target):
			_charge_target = null
			change_state(State.RETURNING)
			return
	# Lost our chase target before making contact → go home.
	if _charge_target == null:
		_assisting = false
		change_state(State.RETURNING)
		return
	# Combat Ground Line — steer at the enemy's exact lane-Y, not its raw
	# position. The charge target is reserved (frozen by stop-on-claim) so
	# this spot is stable; arriving on it makes the soldier duel on the
	# enemy's Y (shares its shadow line) instead of planting at whatever
	# diagonal it happened to reach. Gap sits inside melee_range so the
	# normal _try_engage above still fires on arrival. Shared with
	# BaseHero._engage_position_for. CORE RULE 13 preserved — still a
	# direct straight-line move, only the target Y is corrected.
	var mr: float = data.melee_range if data != null and "melee_range" in data else 24.0
	var gap: float = maxf(mr * 0.8, 12.0)
	var fwd: Vector2 = _GuardZoneScript.path_forward_at(_charge_target)
	if fwd == Vector2.ZERO:
		fwd = Vector2(signf(_charge_target.global_position.x - global_position.x), 0.0)
	var slot: int = _charge_target.block_slot_for(self) if _charge_target.has_method("block_slot_for") else 0
	var spot: Vector2 = _GuardZoneScript.melee_engage_spot(_charge_target.global_position, fwd, gap, slot)
	var to_target: Vector2 = spot - global_position
	if to_target.length() < 3.0:
		velocity = Vector2.ZERO
	else:
		velocity = _ground_line_dir(to_target) * _effective_move_speed()
	move_and_slide()


# Release every enemy we currently engage. Also called by set_blocking_position
# and _die to free enemies cleanly.
func _release_all_engagements() -> void:
	for e in _engaged_enemies:
		if e != null and is_instance_valid(e):
			e.release_combat(self)
	_engaged_enemies.clear()
	_assisting = false


# Combat Blocking Doctrine — stop-on-claim reconciliation (mirrors
# BaseHero._sync_claim). Once per frame: reserve the enemy this soldier is
# committed to (the charge target, else the oldest engaged enemy) so it
# halts and waits while the soldier walks over; unreserve anything else.
# Single choke-point — covers every place _charge_target / _engaged_enemies
# changes without touching each site. Flying / bypass enemies no-op
# reserve(), so they keep moving (handled in BaseEnemy.reserve).
func _sync_claim() -> void:
	var desired: Node = null
	if _charge_target != null and is_instance_valid(_charge_target) \
			and _charge_target.state != BaseEnemy.State.DYING:
		desired = _charge_target
	elif not _engaged_enemies.is_empty():
		var e: Node = _engaged_enemies[0]
		if e != null and is_instance_valid(e):
			desired = e
	if desired == _claimed_enemy:
		return
	if _claimed_enemy != null and is_instance_valid(_claimed_enemy) \
			and _claimed_enemy.has_method("unreserve"):
		_claimed_enemy.unreserve(self)
	_claimed_enemy = desired
	if _claimed_enemy != null and _claimed_enemy.has_method("reserve"):
		_claimed_enemy.reserve(self)


# Free any held claim (death / despawn). _physics_process early-returns
# while DEAD so _sync_claim can't reconcile then — _die() calls this.
func _release_claim() -> void:
	if _claimed_enemy != null and is_instance_valid(_claimed_enemy) \
			and _claimed_enemy.has_method("unreserve"):
		_claimed_enemy.unreserve(self)
	_claimed_enemy = null


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
	var eff_atk_speed: float = data.attack_speed * _soldier_mult("soldier_attack_speed_mult") if data != null else 1.0
	_lunge_dur = UnitVisualDrawer.swing_duration(eff_atk_speed)
	_lunge_t = _lunge_dur
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	# Matches BaseHero wind-up curve — rear back, snap forward, settle.
	#   [0.00, 0.32]  0    → -0.30   anticipation (ease-in)
	#   [0.32, 0.55] -0.30 → +1.00   commit (ease-out — the snap)
	#   [0.55, 0.78] +1.00 → +0.85   hold near-extended
	#   [0.78, 1.00] +0.85 → 0       settle (ease-in-out)
	var t: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
	return _lunge_dir * (LUNGE_DISTANCE * UnitVisualDrawer.lunge_offset_scale(t))


# Active move-speed after status effects (slow). Wraps every read of
# data.move_speed so an enemy archer's "slow" payload uniformly affects
# rally-walk, return-walk, and engage-step. Identity when no slow is
# active; clamps to 0 if some hypothetical effect would push it negative.
func _effective_move_speed() -> float:
	if data == null:
		return 0.0
	var s: float = data.move_speed
	if not _effects.is_empty() and _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	return maxf(0.0, s)


# Status effect entry point. Mirrors BaseEnemy.apply_status_effect with no
# VFX (soldiers don't show the dashed ring overlays — keeps the squad
# silhouette clean). Reapplication routes through StatusEffect.refresh so
# DoTs (burn/poison) preserve their _tick_accumulator across rapid hits
# instead of resetting the clock and silently suppressing damage.
func apply_status_effect(effect) -> void:
	if effect == null or state == State.DEAD:
		return
	if _effects.has(effect.id):
		_effects[effect.id].refresh(effect)
		queue_redraw()
		return
	_effects[effect.id] = effect
	effect.apply(self)
	queue_redraw()


# Decrement duration on every active effect; call its tick() each frame (for
# DoT-style effects like burn that need per-tick callbacks). Remove and call
# the effect's remove() when duration expires. Mirrors BaseEnemy._tick_effects.
func _tick_effects(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired: Array[String] = []
	for id in _effects.keys():
		var e = _effects[id]
		if e.has_method("tick"):
			e.tick(self, delta)
		e.duration -= delta
		if e.duration <= 0.0:
			expired.append(id)
	for id in expired:
		_effects[id].remove(self)
		_effects.erase(id)
	queue_redraw()


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
		# Damage number is spawned by VFXSpawner via EventBus.hit_landed.
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()
	return final


func _die() -> void:
	change_state(State.DEAD)
	_release_all_engagements()
	# Free any claimed enemy so it resumes walking — _physics_process early-
	# returns while DEAD so _sync_claim can't reconcile this.
	_release_claim()
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
	# Race-independent: race==NONE soldier visuals still get a shadow
	# (draw_ground_shadow sizes from body_size). Visual-only.
	if data != null and data.visual != null:
		UnitVisualDrawer.draw_ground_shadow(self, data.visual)
		if not _effects.is_empty():
			UnitVisualDrawer.draw_blocker_status_rings(self, data.visual,
				_effects.keys(), _breath_t + _walk_phase, _get_zoom_scale())

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
	# Impact squash on attack commit — peaks at the strike frame (~t01 0.48).
	if _lunge_t > 0.0:
		var lt: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
		if lt > 0.32 and lt < 0.64:
			var sq: float = sin((lt - 0.32) / 0.32 * PI) * 0.18
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
		# Wind-up / strike-arc derived from lunge curve via the shared phase
		# mapping (single source of truth — soldier + hero stay in lockstep).
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
			ctx.merge(UnitVisualDrawer.swing_phase(t01))
			if ctx.has("strike_t"):
				ctx["strike_dir"] = _lunge_dir

	# 4. Body draw.
	if data != null and data.visual != null:
		var walk_t_arg: float = _walk_t if moving_state else -1.0
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale, walk_t_arg, _walk_phase, ctx)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
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
