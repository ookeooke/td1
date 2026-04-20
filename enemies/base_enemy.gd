extends Area2D
class_name BaseEnemy

enum State { WALKING, STUNNED, COMBAT, STEALTHED, DYING }

const HP_BAR_SIZE: Vector2 = Vector2(70.0, 10.0)
const HP_BAR_Y_OFFSET: float = -65.0
# Phase 44: brief white overlay on damage so hits read visually.
const HIT_FLASH_DURATION: float = 0.08
# Last 150 ms of the melee cooldown renders a red telegraph arc on the
# side of the enemy facing its blocker — gives the player a visible "tell"
# before each counter-attack lands.
const ATTACK_TELEGRAPH_DURATION: float = 0.15

@export var data: EnemyData

var state: int = State.WALKING
var current_health: int = 0

var _path_follow: PathFollow2D
var _path_id: String = ""

# Active status effects keyed by id ("slow", "stun"). Reapplying the same id
# replaces the prior effect (refreshes duration / takes stronger value).
var _effects: Dictionary = {}

# Combat engagement — populated by soldiers AND heroes calling
# engage_combat(self). Any number of blockers are allowed; per-blocker
# capacity lives on the blocker's data (SoldierData/HeroData.max_block_targets).
# Counter-attacks focus on _blockers[0] — the oldest engager — so the
# telegraph arc points at one stable target instead of flickering.
var _blockers: Array[Node] = []
var _combat_cooldown: float = 0.0

# Last source that dealt damage — used by _die() to award XP to the hero
# when the hero landed the killing blow (last-hit semantics). Towers get
# gold, not XP.
var _last_damage_source: Node = null
# Seconds remaining on the on-hit white flash (decays in _physics_process).
var _hit_flash_t: float = 0.0
# Accumulates while any status effect is active so the dashed rings rotate.
var _status_ring_t: float = 0.0
# Accumulates while in WALKING so body bob + squash animate. Randomized phase
# per-enemy so a swarm doesn't step in sync. Driven by UnitVisualData fields.
var _walk_t: float = 0.0
var _walk_phase: float = 0.0

# Phase 20.5: per-unit ability dispatcher. Populated from data.abilities
# in _ready(); ticked each physics frame; triggered on death so
# abilities like ExplodeOnDeath or SummonOnDeath can hook in.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
const _FloatingTextScript := preload("res://vfx/FloatingText.gd")
var _ability_host: RefCounted = null


func _ready() -> void:
	if data:
		current_health = data.max_health
	# Phase 20: group membership so skill targeting can enumerate live
	# enemies without walking the whole tree. get_tree().get_nodes_in_group
	# is only called on tap (targeting), not per-frame — perf rule intact.
	add_to_group("enemies")
	# Phase 20.5: host any abilities attached via EnemyData.abilities.
	# Added after add_to_group so ON_SPAWN abilities that look up
	# group members already see this enemy registered.
	_ability_host = _AbilityHostScript.new(self)
	if data != null:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	_walk_phase = randf() * TAU
	queue_redraw()


func setup(path_follow: PathFollow2D, path_id: String) -> void:
	_path_follow = path_follow
	_path_id = path_id


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if _path_follow == null or data == null:
		return
	_tick_effects(delta)
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
		queue_redraw()
	if not _effects.is_empty():
		_status_ring_t += delta
		queue_redraw()
	if _ability_host != null:
		_ability_host.tick(delta)
	match state:
		State.WALKING:
			_path_follow.progress += _effective_speed() * delta
			if _path_follow.progress_ratio >= 1.0:
				_reach_end()
			# Walk-bob tick. Gated on visual fields so enemies with bob
			# disabled (amplitude 0 + squash 0) skip the per-frame redraw.
			if data != null and data.visual != null:
				var v: UnitVisualData = data.visual
				if v.walk_bob_amplitude > 0.0 or v.walk_squash > 0.0:
					_walk_t += delta
					queue_redraw()
		State.COMBAT:
			_combat_tick(delta)
		State.STUNNED, State.STEALTHED, State.DYING:
			pass


func engage_combat(blocker: Node) -> bool:
	# Soldiers AND heroes block ground enemies. Any number of blockers are
	# allowed; this function appends to _blockers and returns true iff the
	# blocker was newly registered. Per-blocker capacity is enforced by the
	# caller against its own data.max_block_targets.
	if state == State.DYING or blocker == null:
		return false
	# Phase 45f: bypass archetypes (Rushing-Monkey equivalent) refuse every
	# engagement. Blocker still sees false and won't register this enemy,
	# so the enemy keeps walking past soldier and hero lines alike.
	if data != null and "bypass_engagement" in data and data.bypass_engagement:
		return false
	if _blockers.has(blocker):
		return false
	_blockers.append(blocker)
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed) if data != null else 1.0
	if state != State.COMBAT:
		change_state(State.COMBAT)
	return true


func release_combat(blocker: Node = null) -> void:
	# Remove a specific blocker or all blockers when called with null.
	# Drops back to WALKING once the list empties.
	if blocker == null:
		_blockers.clear()
	else:
		_blockers.erase(blocker)
	if _blockers.is_empty():
		_combat_cooldown = 0.0
		if state == State.COMBAT:
			change_state(State.WALKING)


func _combat_tick(delta: float) -> void:
	# Prune stale / dead blockers each tick so an engager that was freed
	# (soldier died, hero respawned elsewhere) doesn't hold the slot.
	_prune_blockers()
	if _blockers.is_empty() or data == null:
		release_combat()
		return
	var prev: float = _combat_cooldown
	_combat_cooldown -= delta
	# Repaint while the telegraph arc is visible so its thickness animates.
	if prev > 0.0 and prev <= ATTACK_TELEGRAPH_DURATION:
		queue_redraw()
	if _combat_cooldown > 0.0:
		return
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	var focus: Node = _blockers[0]
	if focus == null or not is_instance_valid(focus) or not focus.has_method("take_damage"):
		return
	var splash_r: float = data.attack_splash_radius if "attack_splash_radius" in data else 0.0
	if splash_r <= 0.0:
		focus.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)
		return
	# AoE swing: every blocker whose body sits inside splash_r of the focus
	# eats the full counter-attack. Designed counter to rally-stack surrounds.
	var origin: Vector2 = focus.global_position
	var r2: float = splash_r * splash_r
	for b in _blockers:
		if b == null or not is_instance_valid(b) or not b.has_method("take_damage"):
			continue
		if b.global_position.distance_squared_to(origin) <= r2:
			b.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)


func _prune_blockers() -> void:
	var keep: Array[Node] = []
	for b in _blockers:
		if b != null and is_instance_valid(b):
			keep.append(b)
	if keep.size() != _blockers.size():
		_blockers = keep


func apply_status_effect(effect) -> void:
	# effect: StatusEffect subclass (SlowEffect / StunEffect / etc.)
	# Untyped param so this compiles before Godot indexes systems/*.gd class_names.
	if effect == null or state == State.DYING:
		return
	_effects[effect.id] = effect
	effect.apply(self)
	if effect.id == "stun" and state != State.STUNNED:
		change_state(State.STUNNED)
	queue_redraw()


func _tick_effects(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired: Array[String] = []
	for id in _effects.keys():
		var e = _effects[id]
		e.duration -= delta
		if e.duration <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		var e = _effects[id]
		e.remove(self)
		_effects.erase(id)
		if id == "stun" and state == State.STUNNED:
			change_state(State.WALKING)
	queue_redraw()


func _effective_speed() -> float:
	var s: float = data.move_speed
	if _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	return s


func take_damage(amount: float, type: int, source: Node = null) -> float:
	if state == State.DYING or data == null:
		return 0.0
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	# Cap to remaining HP so stat tracking isn't inflated by overkill.
	var actual: float = minf(final, float(current_health))
	# Phase 46: attribute damage to the source for the victory-screen
	# leaderboard. record_round_damage filters by class (tower/hero/soldier).
	GameState.record_round_damage(source, actual)
	current_health -= int(ceil(final))
	if final > 0.0:
		_hit_flash_t = HIT_FLASH_DURATION
		EventBus.hit_landed.emit(self, source, final, type)
		EventBus.enemy_damaged.emit(self, final, type)
	if source != null:
		_last_damage_source = source
	# Floating damage number — shows raw hit, not capped, so players see
	# the full impact of their tower's power.
	if final > 0.0:
		var parent: Node = get_tree().current_scene
		if parent != null:
			_FloatingTextScript.spawn(parent, str(int(ceil(final))), Color(1.0, 0.3, 0.2), global_position + Vector2(0, -50), 28)
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()
	return actual


func heal(amount: float) -> void:
	if state == State.DYING or data == null:
		return
	if current_health >= data.max_health:
		return
	var before: int = current_health
	current_health = mini(data.max_health, current_health + int(ceil(amount)))
	if current_health != before:
		queue_redraw()
		print("[Enemy/heal] %s %d → %d" % [data.enemy_name, before, current_health])


func _die() -> void:
	# Guard: a lethal hit landing on the exact frame an enemy reaches path
	# end would otherwise double-emit (die + reach_end), duplicating gold and
	# lives deltas. First transition to DYING wins; any re-entry is a no-op.
	if state == State.DYING:
		return
	change_state(State.DYING)
	# Last-hit XP: only the hero earns XP, towers don't.
	if _last_damage_source != null and is_instance_valid(_last_damage_source) \
			and _last_damage_source is BaseHero and data.xp_worth > 0:
		_last_damage_source.gain_xp(data.xp_worth)
	# Fire ON_DEATH abilities (explode, summon, buff allies, etc.) BEFORE
	# despawn so they can read our position / iterate the enemies group
	# while we're still valid.
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.enemy_died.emit(self, data.gold_worth)
	_despawn()


func _reach_end() -> void:
	if state == State.DYING:
		return
	change_state(State.DYING)
	EventBus.enemy_reached_end.emit(self, data.lives_worth)
	_despawn()


func _despawn() -> void:
	if is_instance_valid(_path_follow):
		_path_follow.queue_free()
	queue_free()


func _draw() -> void:
	var inhale: Vector2 = _inhale_offset()
	var body_offset: Vector2 = inhale
	var body_scale: Vector2 = Vector2.ONE
	# Walk-bob + squash applied only while walking — stationary (COMBAT /
	# STUNNED / DYING) bodies stay still so the tell reads clearly.
	if data != null and data.visual != null and state == State.WALKING:
		var anim: Dictionary = UnitVisualDrawer.compute_walk_anim(data.visual, _walk_t, _walk_phase)
		body_offset += anim.offset
		body_scale = anim.scale
	if data != null and data.visual != null:
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
	else:
		draw_circle(Vector2.ZERO, 35.0, Color(0.75, 0.2, 0.2))
		draw_arc(Vector2.ZERO, 35.0, 0, TAU, 24, Color(0.15, 0.05, 0.05), 2.0)
	# Status-effect overlay rings — dashed + rotating so active effects read as
	# animated rather than static. Stun is outermost and spins opposite to slow.
	var ring_r: float = (data.visual.radius if data != null and data.visual != null else 35.0) + 12.0
	if _effects.has("slow"):
		UnitVisualDrawer.draw_status_ring(self, ring_r, Color(0.2, 0.7, 1.0), 8, _status_ring_t * 1.5, 5.0)
	if _effects.has("stun"):
		UnitVisualDrawer.draw_status_ring(self, ring_r + 10.0, Color(1.0, 0.95, 0.2), 6, -_status_ring_t * 2.0, 5.0)
	_draw_attack_telegraph(ring_r)
	_draw_health_bar()


# Body pulls back slightly in the last 150 ms before a counter-attack strike,
# so the forward lunge reads as release. Returns zero outside the telegraph
# window or when no valid focus exists.
func _inhale_offset() -> Vector2:
	if state != State.COMBAT or _blockers.is_empty():
		return Vector2.ZERO
	if _combat_cooldown <= 0.0 or _combat_cooldown > ATTACK_TELEGRAPH_DURATION:
		return Vector2.ZERO
	var focus: Node = _blockers[0]
	if focus == null or not is_instance_valid(focus):
		return Vector2.ZERO
	var dir: Vector2 = focus.global_position - global_position
	if dir.length_squared() < 0.01:
		return Vector2.ZERO
	var t: float = smoothstep(ATTACK_TELEGRAPH_DURATION, 0.0, _combat_cooldown)
	return -dir.normalized() * 4.0 * t


# Red warning arc drawn on the side of the enemy facing its blocker during
# the last ATTACK_TELEGRAPH_DURATION of the cooldown. Gives the player a
# visual "tell" before each counter-attack lands. Thickness grows as the
# strike approaches so the moment of impact is obvious.
func _draw_attack_telegraph(base_ring_r: float) -> void:
	if state != State.COMBAT or _blockers.is_empty():
		return
	var focus: Node = _blockers[0]
	if focus == null or not is_instance_valid(focus):
		return
	if _combat_cooldown <= 0.0 or _combat_cooldown > ATTACK_TELEGRAPH_DURATION:
		return
	var progress: float = 1.0 - (_combat_cooldown / ATTACK_TELEGRAPH_DURATION)
	var dir: Vector2 = (focus.global_position - global_position)
	if dir.length_squared() < 0.01:
		return
	var angle: float = dir.angle()
	var span: float = PI / 2.5
	var r: float = base_ring_r + 4.0
	var width: float = 3.0 + progress * 6.0
	var alpha: float = 0.35 + progress * 0.5
	draw_arc(Vector2.ZERO, r, angle - span * 0.5, angle + span * 0.5, 20, Color(1.0, 0.25, 0.2, alpha), width)


# Drawn by every enemy subclass at the end of its _draw() override.
# Visible whenever current_health < max_health (plus during the pre-despawn
# redraw, where current_health has just hit 0). Hidden at full HP so an
# untouched enemy is uncluttered.
func _draw_health_bar() -> void:
	if data == null or data.max_health <= 0:
		return
	if current_health >= data.max_health:
		return
	var zs: float = _get_zoom_scale()
	var bar_size: Vector2 = HP_BAR_SIZE * zs
	var bar_y: float = HP_BAR_Y_OFFSET * zs
	var pct: float = clampf(float(current_health) / float(data.max_health), 0.0, 1.0)
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
