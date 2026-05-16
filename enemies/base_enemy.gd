extends Area2D
class_name BaseEnemy

const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")

enum State { WALKING, COMBAT, STEALTHED, DYING }

const HP_BAR_SIZE: Vector2 = Vector2(70.0, 10.0)
const HP_BAR_Y_OFFSET: float = -65.0
const COMBAT_DEBUG_FONT_SIZE: int = 11
# Phase 44: brief white overlay on damage so hits read visually.
const HIT_FLASH_DURATION: float = 0.08
# Last 150 ms of the melee cooldown renders a red telegraph arc on the
# side of the enemy facing its blocker — gives the player a visible "tell"
# before each counter-attack lands.
const ATTACK_TELEGRAPH_DURATION: float = 0.15
# Strike animation — ticks AFTER damage applies. Enemy lunges forward then
# eases back, mirroring the hero lunge so counter-attacks have visible
# follow-through, not just an invisible damage event.
const STRIKE_ANIM_DURATION: float = 0.18
const STRIKE_BACK_DIST: float = 6.0   # pulled back during anticipation
const STRIKE_PUSH_DIST: float = 18.0  # forward at peak commit
# Hit-stop — both attacker and defender freeze for a few frames on every
# successful hit. Applies to BaseEnemy._physics_process and BaseHero
# (mirrored there). Universal action-game readability device.
const HIT_STOP_DURATION: float = 0.0

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
# Combat Blocking Doctrine — stop-on-claim. A blocker that COMMITS to this
# enemy (picks it as its approach target) reserves it: the enemy halts in
# place (soft-stop) and waits, but does NOT counter-attack until a blocker
# physically reaches it (engage_combat → _blockers → hard-fight). Flying /
# bypass_engagement enemies ignore reservations (they never stop).
var _reservers: Array[Node] = []
var _combat_cooldown: float = 0.0
# Strike animation state — set by _start_strike(); decays in _physics_process.
# While > 0, body lunges forward toward _strike_dir then eases back.
var _strike_t: float = 0.0
var _strike_dir: Vector2 = Vector2.ZERO
# Hit-stop accumulator — when > 0, _physics_process bails early so all
# motion freezes for a moment after the hit lands.
var _hit_stop_t: float = 0.0

# Last source that dealt damage — used by _die() to award XP to the hero
# when the hero landed the killing blow (last-hit semantics). Towers get
# gold, not XP.
var _last_damage_source: Node = null
# Per-instance HP multiplier — used by endless wave scaling to make later
# waves tougher without mutating the shared EnemyData resource. Set BEFORE
# add_child so _ready picks up the scaled current_health. Default 1.0 for
# campaign / heroic / iron / Test Range — those keep the authored values.
var _hp_scale: float = 1.0
# Seconds remaining on the on-hit white flash (decays in _physics_process).
var _hit_flash_t: float = 0.0
# Accumulates while any status effect is active so the dashed rings rotate.
var _status_ring_t: float = 0.0
# Accumulates while in WALKING so body bob + squash animate. Randomized phase
# per-enemy so a swarm doesn't step in sync. Driven by UnitVisualData fields.
var _walk_t: float = 0.0
# Foot-plant tracking — index of the half-cycle the walker is currently in.
# Plants happen at theta = N*PI, so a change in `int(theta / PI)` is a
# foot-plant transition. -999 = uninitialized; first observed value seeds it
# without spawning dust (avoids a spurious puff at the spawn frame).
var _last_plant_index: int = -999
var _walk_phase: float = 0.0
# Hurt flinch: brief recoil away from the damage source on each hit. Reads as
# a physical reaction to complement the white hit-flash overlay.
const FLINCH_DURATION: float = 0.0
const FLINCH_DISTANCE: float = 0.0
var _flinch_t: float = 0.0
var _flinch_dir: Vector2 = Vector2.ZERO
# Idle breathing: stationary enemies (COMBAT / stunned) torso pulses ~3% so
# they don't look frozen when not walking. Not used during WALKING (walk-bob
# already provides aliveness) or DYING. Stun is a behavior gate, not a state
# (see apply_status_effect) — engaged enemies stay in COMBAT through stun.
var _breath_t: float = 0.0
# Direction the enemy is facing along its path. Sampled from PathFollow2D
# position deltas in _physics_process. Used for direction-aware eye shift.
var _facing_dir: Vector2 = Vector2.RIGHT
var _prev_pos: Vector2 = Vector2.ZERO
# Per-enemy spawn variation — small randomized tweaks so a wave of grunts
# reads as individuals not clones. Set once in _ready, never changes.
var _skin_tint: Color = Color.WHITE
# Slowed-enemy ghost trail: stores the world position from ~0.2s ago so we
# can draw a translucent silhouette behind a slowed enemy.
const SLOW_GHOST_LAG: float = 0.20
var _slow_pos_history: Array[Vector2] = []
var _slow_time_history: Array[float] = []

# Phase 20.5: per-unit ability dispatcher. Populated from data.abilities
# in _ready(); ticked each physics frame; triggered on death so
# abilities like ExplodeOnDeath or SummonOnDeath can hook in.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
const _StatusApplyScript := preload("res://vfx/StatusApplyVFX.gd")
const _WalkDustScript := preload("res://vfx/WalkDustVFX.gd")
var _ability_host: RefCounted = null


func _ready() -> void:
	# Debug-only balance override (BalanceOverrides). Multiplies into
	# _hp_scale BEFORE current_health is computed so per-enemy HP reflects
	# the slider panel's HP %. No-op in production.
	_hp_scale *= BalanceOverrides.get_hp_mult()
	# Debug-only per-level HP multiplier (compounds with the global one).
	# Lets the designer dial up only L4's enemies without touching L1-L3.
	if RunState.current_level_id != "":
		_hp_scale *= BalanceOverrides.get_level_float(RunState.current_level_id, "hp_mult", 1.0)
	# Per-enemy HP multiplier — applies on top of the global + level mults so
	# the designer can dial up only Brutes without touching everything else.
	if data != null and data.enemy_id != "":
		_hp_scale *= BalanceOverrides.get_enemy_mult(data.enemy_id, "hp_mult")
	if data:
		current_health = _effective_max_health()
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
	# Per-spawn variation: slight skin-tint shift (±5%) so a wave of identical
	# enemies reads as individuals rather than clones. Hue stays near body
	# color — only luminance/saturation drift.
	var v_seed: float = randf()
	var tint_amount: float = (v_seed - 0.5) * 0.10  # -0.05 .. +0.05
	_skin_tint = Color(1.0 + tint_amount, 1.0 + tint_amount * 0.6, 1.0 + tint_amount * 0.3, 1.0)
	_prev_pos = global_position
	queue_redraw()


func setup(path_follow: PathFollow2D, path_id: String) -> void:
	_path_follow = path_follow
	_path_id = path_id


# Combat Blocking Doctrine — public path accessors. Used by blocker guard-zone
# checks to compare an enemy's path progress against the projected position of
# a hero hold-point / soldier rally. Hero/soldier code must use these instead
# of reaching into _path_follow directly. See docs/COMBAT_BLOCKING_DOCTRINE.md.
func get_path_id() -> String:
	return _path_id


func get_path_progress() -> float:
	if _path_follow == null:
		return 0.0
	return _path_follow.progress


func get_path_progress_ratio() -> float:
	if _path_follow == null:
		return 0.0
	return _path_follow.progress_ratio


func get_path_follow() -> PathFollow2D:
	return _path_follow


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if _path_follow == null or data == null:
		return
	# Hit-stop: freeze all motion for a few frames after every successful
	# hit (universal action-game readability). Decrement here and bail —
	# state machine, cooldowns, animations all hold their last frame.
	if _hit_stop_t > 0.0:
		_hit_stop_t = maxf(0.0, _hit_stop_t - delta)
		return
	if _strike_t > 0.0:
		_strike_t = maxf(0.0, _strike_t - delta)
		queue_redraw()
	_tick_effects(delta)
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
		queue_redraw()
	if _flinch_t > 0.0:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		queue_redraw()
	if not _effects.is_empty():
		_status_ring_t += delta
		queue_redraw()
	if _ability_host != null:
		_ability_host.tick(delta)
	# Facing direction. While engaged (COMBAT, halted) the enemy turns to
	# face its oldest blocker so the body agrees with the swing animation
	# (which already aims at _blockers[0]) instead of staying frozen on the
	# last path heading — fixes the "face forward, punch backward" read.
	# Otherwise sampled from world-position delta so it survives any
	# path/lane configuration and matches what the player sees move.
	if state == State.COMBAT and not _blockers.is_empty():
		var b: Node = _blockers[0]
		if b != null and is_instance_valid(b) and b is Node2D:
			var to_b: Vector2 = (b as Node2D).global_position - global_position
			if to_b.length_squared() > 0.05:
				_facing_dir = to_b.normalized()
	else:
		var dp: Vector2 = global_position - _prev_pos
		if dp.length_squared() > 0.05:
			_facing_dir = dp.normalized()
	_prev_pos = global_position
	# Slow-ghost trail history: only sampled while the slow effect is active
	# so we don't burn memory on every enemy. Records {pos, time}; older than
	# SLOW_GHOST_LAG seconds get trimmed. Skip while stunned — position is
	# frozen so the trail would just stack identical samples.
	if _effects.has("slow") and state == State.WALKING and not _effects.has("stun"):
		var now: float = Time.get_ticks_msec() / 1000.0
		_slow_pos_history.append(global_position)
		_slow_time_history.append(now)
		while _slow_time_history.size() > 0 and (now - _slow_time_history[0]) > SLOW_GHOST_LAG * 1.5:
			_slow_pos_history.pop_front()
			_slow_time_history.pop_front()
		queue_redraw()
	elif not _slow_pos_history.is_empty():
		_slow_pos_history.clear()
		_slow_time_history.clear()
	# Stun gate: frozen for the duration, but the underlying state (WALKING /
	# COMBAT) is preserved. Lets blockers stay engaged through the stun and
	# resume hitting the moment it expires — no change_state ping-pong.
	if _effects.has("stun"):
		_breath_t += delta
		queue_redraw()
		return
	match state:
		State.WALKING:
			# Combat Blocking Doctrine — stop-on-claim. Prune stale reservers,
			# then freeze in place while reserved (a blocker has committed and
			# is walking over). Stays in WALKING so it resumes the instant the
			# claim is released; no counter-attack (that needs _blockers).
			if not _reservers.is_empty():
				var live: Array[Node] = []
				for r in _reservers:
					if r != null and is_instance_valid(r):
						live.append(r)
				if live.size() != _reservers.size():
					_reservers = live
			if not _reservers.is_empty():
				# Held only freezes path progress + walk anim. Status effects,
				# ability host, hit-stop and death all tick ABOVE this match
				# (so a held enemy still takes damage, dies, and burns
				# slow/stun duration — holding does NOT pause debuffs; this
				# is a deliberate design decision, see COMBAT_BLOCKING_DOCTRINE).
				_breath_t += delta
				queue_redraw()
				return
			_path_follow.progress += _effective_speed() * delta
			if _path_follow.progress_ratio >= 1.0:
				_reach_end()
			if data != null and data.visual != null:
				var v: UnitVisualData = data.visual
				if v.walk_bob_amplitude > 0.0 or v.walk_squash > 0.0:
					_walk_t += delta
					queue_redraw()
					# Foot-plant dust — fires when theta crosses a multiple
					# of PI. Plants alternate L/R via the parity of the index
					# so dust pops on the planting side, not always centered.
					if v.walk_bob_amplitude > 0.0 and not VFXSpawner.clean_view:
						var theta: float = _walk_t * v.walk_bob_speed + _walk_phase
						var plant_idx: int = int(floor(theta / PI))
						if _last_plant_index == -999:
							_last_plant_index = plant_idx
						elif plant_idx != _last_plant_index:
							_spawn_walk_dust(plant_idx)
							_last_plant_index = plant_idx
		State.COMBAT:
			_combat_tick(delta)
			# Idle breathing while engaged — small scale pulse so the enemy
			# reads as alive while standing still.
			_breath_t += delta
			queue_redraw()
		State.STEALTHED, State.DYING:
			pass


func engage_combat(blocker: Node) -> bool:
	# Soldiers AND heroes block ground enemies. Any number of blockers are
	# allowed; this function appends to _blockers and returns true iff the
	# blocker was newly registered. Per-blocker capacity is enforced by the
	# caller against its own data.max_block_targets.
	# Reject DYING / null / bypass AND flying via the shared predicate
	# (flying was previously NOT rejected here — only reserve() was, an
	# asymmetry that let a flyer be hard-blocked through the assist path).
	if blocker == null or not is_engageable_ground():
		return false
	if _blockers.has(blocker):
		return false
	# Combat Blocking Doctrine bug fix — only reset the swing cooldown when
	# the enemy is *entering* COMBAT (first blocker joins). A second blocker
	# arriving mid-swing must not delay the strike against the existing
	# focus, or the focused soldier gets a free moment every time another
	# friendly piles on. See docs/COMBAT_BLOCKING_DOCTRINE.md Phase 7.
	var was_combat: bool = state == State.COMBAT
	_blockers.append(blocker)
	if not was_combat:
		_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed) if data != null else 1.0
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


# Combat Blocking Doctrine — stop-on-claim (soft stop). A blocker that
# commits to this enemy reserves it; while reserved the enemy freezes its
# path progress (see the WALKING gate) but does NOT counter-attack until a
# blocker physically engages it. Flying / bypass enemies never stop, so
# reservation is a no-op for them. Returns true iff newly reserved.
func reserve(by: Node) -> bool:
	if by == null or state == State.DYING:
		return false
	if data != null:
		if "is_flying" in data and data.is_flying:
			return false
		if "bypass_engagement" in data and data.bypass_engagement:
			return false
	if _reservers.has(by):
		return false
	_reservers.append(by)
	return true


func unreserve(by: Node) -> void:
	_reservers.erase(by)


func is_held() -> bool:
	# Reserved but not yet in physical COMBAT → standing still, waiting.
	return not _reservers.is_empty() and _blockers.is_empty()


# Single source of truth for "can a melee blocker claim/block/assist this?".
# Every melee path (engage_combat, hero/soldier MELEE pickers
# _pick_split_target_in_area / _pick_target_in_detection_zone, assist, the
# lull registry) routes through this so the flying/bypass/dying rules can
# never drift apart across call sites again. Ranged shooting MUST NOT use
# this — it has its own gate in BaseHero._pick_shootable_target_in_area
# (DYING + targets_flying only; bypass is shootable). Enforced by
# tests/unit/test_hero_targeting.gd so the two gates can't re-converge.
func is_engageable_ground() -> bool:
	if data == null:
		return false
	if "is_flying" in data and data.is_flying:
		return false
	if "bypass_engagement" in data and data.bypass_engagement:
		return false
	return state != State.DYING


func get_claim_count() -> int:
	# Soft reservations and hard blockers both mean "some defender is already
	# responsible for this enemy". Target picking uses this to spread blockers
	# across a pack before every unit dogpiles the same not-yet-contacted enemy.
	var live_reservers: Array[Node] = []
	for r in _reservers:
		if r != null and is_instance_valid(r):
			live_reservers.append(r)
	if live_reservers.size() != _reservers.size():
		_reservers = live_reservers
	_prune_blockers()
	# Count UNIQUE claimers. A unit that reserved (soft) and then hard-
	# blocked is in BOTH lists; reserve→block does not unreserve, so a
	# naive size()+size() double-counts it and the spread logic thinks an
	# enemy with one defender has two — making a free blocker skip it.
	var unique: Dictionary = {}
	for r in _reservers:
		unique[r] = true
	for b in _blockers:
		unique[b] = true
	return unique.size()


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
	# Snapshot strike direction before damage applies — focus may die or
	# walk away during take_damage / hit-stop, but the swing animation
	# should still play out toward where the strike was aimed.
	_start_strike(focus)
	var splash_r: float = data.attack_splash_radius if "attack_splash_radius" in data else 0.0
	var dmg: float = _effective_attack_damage()
	if splash_r <= 0.0:
		focus.take_damage(dmg, DamageCalculator.DamageType.PHYSICAL, self)
		return
	# AoE swing: every blocker whose body sits inside splash_r of the focus
	# eats the full counter-attack. Designed counter to rally-stack surrounds.
	var origin: Vector2 = focus.global_position
	var r2: float = splash_r * splash_r
	for b in _blockers:
		if b == null or not is_instance_valid(b) or not b.has_method("take_damage"):
			continue
		if b.global_position.distance_squared_to(origin) <= r2:
			b.take_damage(dmg, DamageCalculator.DamageType.PHYSICAL, self)


# Per-strike damage including global + per-enemy debug multipliers. No-op in
# production. Centralized so future strike sites stay consistent.
func _effective_attack_damage() -> float:
	var d: float = data.attack_damage * BalanceOverrides.get_damage_mult()
	if data != null and data.enemy_id != "":
		d *= BalanceOverrides.get_enemy_mult(data.enemy_id, "damage_mult")
	return d


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
	# If the same id is already active, give the old instance a chance to
	# clean up (visuals, stat modifiers) before the replacement takes over.
	# remove() is currently empty for slow/stun, but future effects may not be.
	var refresh: bool = _effects.has(effect.id)
	if refresh:
		_effects[effect.id].remove(self)
	_effects[effect.id] = effect
	effect.apply(self)
	# First-application VFX — single ring pop in the effect's color so the
	# moment the slow/stun lands reads. Skipped on refresh (the persistent
	# rotating status ring already signals "still active") and on clean_view.
	if not refresh and not VFXSpawner.clean_view:
		var radius: float = 18.0
		if data != null and data.visual != null:
			radius = data.visual.radius
		_StatusApplyScript.spawn(get_tree().current_scene, global_position, radius, _status_apply_color(effect.id))
	# Stun is a behavior gate (see _physics_process), not a state transition.
	# Keeps enemies in COMBAT through stun so blockers remain engaged.
	queue_redraw()


func _status_apply_color(effect_id: String) -> Color:
	match effect_id:
		"slow":
			return Color(0.55, 0.85, 1.00)
		"stun":
			return Color(1.00, 0.85, 0.30)
		"marked":
			return Color(1.00, 0.40, 0.20)
	return Color(1.00, 1.00, 1.00)


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
	queue_redraw()


func _effective_speed() -> float:
	var s: float = data.move_speed
	if _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	# Debug-only balance override. No-op in production. Per-enemy mult layered
	# on top of the global so a single enemy class can be tuned independently.
	s *= BalanceOverrides.get_speed_mult()
	if data != null and data.enemy_id != "":
		s *= BalanceOverrides.get_enemy_mult(data.enemy_id, "speed_mult")
	return s


# DamageCalculator hooks: returns per-enemy override-adjusted armor / mag-res.
# Existing global Enemy armor+ / mag-res+ sliders apply uniformly; per-enemy
# adders layer on top so the designer can give Armored more armor without
# affecting basics. All values clamped 0..0.95 by DamageCalculator.
func get_effective_armor() -> float:
	if data == null:
		return 0.0
	var a: float = data.armor + BalanceOverrides.get_armor_add()
	if data.enemy_id != "":
		a += BalanceOverrides.get_enemy_mult(data.enemy_id, "armor_add")
	return clampf(a, 0.0, 0.95)


# Phase 3L — Marked-status amplifier. Returns the damage_taken_mult of the
# active "marked" status effect, or 1.0 if no mark is active. DamageCalculator
# applies this AFTER armor / magic_resist so the mark amplifies post-mitigation
# damage uniformly across damage types.
func get_damage_taken_mult() -> float:
	if _effects.has("marked"):
		return float(_effects["marked"].damage_taken_mult)
	return 1.0


func get_effective_magic_resist() -> float:
	if data == null:
		return 0.0
	var m: float = data.magic_resist + BalanceOverrides.get_mag_res_add()
	if data.enemy_id != "":
		m += BalanceOverrides.get_enemy_mult(data.enemy_id, "mag_res_add")
	return clampf(m, 0.0, 0.95)


func take_damage(amount: float, type: int, source: Node = null) -> float:
	if state == State.DYING or data == null:
		return 0.0
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	# Cap to remaining HP so stat tracking isn't inflated by overkill.
	var actual: float = minf(final, float(current_health))
	# Phase 46: attribute damage to the source for the victory-screen
	# leaderboard. record_round_damage filters by class (tower/hero/soldier).
	RunState.record_round_damage(source, actual)
	current_health -= int(ceil(final))
	if final > 0.0:
		_hit_flash_t = HIT_FLASH_DURATION
		# Hit-stop — both this enemy and the attacker freeze briefly so the
		# moment of impact reads as weighty rather than instantaneous.
		_hit_stop_t = HIT_STOP_DURATION
		if source != null and is_instance_valid(source) and "_hit_stop_t" in source:
			source._hit_stop_t = HIT_STOP_DURATION
		# Flinch away from damage source — direction inferred from source
		# global_position when available, else random small kick.
		_flinch_t = FLINCH_DURATION
		var src_pos: Vector2 = Vector2.ZERO
		var have_src_pos: bool = false
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
		EventBus.enemy_damaged.emit(self, final, type)
	if source != null:
		_last_damage_source = source
	# Damage number is spawned by VFXSpawner via EventBus.hit_landed (CORE RULE 2).
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()
	return actual


# Effective max HP for this instance — applies _hp_scale on top of the
# authored data.max_health. Endless mode sets _hp_scale before _ready so
# later waves are tougher without mutating the shared EnemyData resource.
func _effective_max_health() -> int:
	if data == null:
		return 0
	return int(round(float(data.max_health) * _hp_scale))


func heal(amount: float) -> void:
	if state == State.DYING or data == null:
		return
	if current_health >= _effective_max_health():
		return
	var before: int = current_health
	current_health = mini(_effective_max_health(), current_health + int(ceil(amount)))
	if current_health != before:
		queue_redraw()


func _die() -> void:
	# Guard: a lethal hit landing on the exact frame an enemy reaches path
	# end would otherwise double-emit (die + reach_end), duplicating gold and
	# lives deltas. First transition to DYING wins; any re-entry is a no-op.
	if state == State.DYING:
		return
	change_state(State.DYING)
	# Last-hit XP: the hero earns XP directly; hero-summoned soldiers funnel
	# kill credit back to their summoner (a Knight's Summon Soldiers cast).
	# Barracks soldiers stay neutral — towers don't have XP, and the soldier
	# has _summoner == null in that case. Tower-direct hits earn no XP either.
	var xp_recipient: Node = null
	if _last_damage_source != null and is_instance_valid(_last_damage_source):
		if _last_damage_source is BaseHero:
			xp_recipient = _last_damage_source
		elif _last_damage_source is BaseSoldier \
				and "_summoner" in _last_damage_source \
				and _last_damage_source._summoner != null \
				and is_instance_valid(_last_damage_source._summoner):
			xp_recipient = _last_damage_source._summoner
	if xp_recipient != null and data.xp_worth > 0:
		xp_recipient.gain_xp(data.xp_worth)
	# Fire ON_DEATH abilities (explode, summon, buff allies, etc.) BEFORE
	# despawn so they can read our position / iterate the enemies group
	# while we're still valid.
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	# Per-enemy gold multiplier — affects every consumer of the signal
	# (RunState bounty payout, LootDropper drop chance via gold_worth, etc.).
	var bounty: int = int(round(float(data.gold_worth) * BalanceOverrides.get_enemy_mult(data.enemy_id, "gold_mult")))
	EventBus.enemy_died.emit(self, bounty)
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


# Spawn a small dust puff at the foot-plant position. Side-alternates
# horizontally by plant parity so left/right feet leave dust on their own
# side. Anchored at the texture's bottom edge (or shadow position for
# procedural enemies) so the dust reads as ground contact, not body height.
func _spawn_walk_dust(plant_idx: int) -> void:
	if data == null or data.visual == null:
		return
	# Flying enemies don't touch the ground — no foot-plant dust on harpies
	# and other airborne types. Their bob still drives tilt/squash visually.
	if data.is_flying:
		return
	var v: UnitVisualData = data.visual
	var feet_y: float = v.radius * 0.95
	if v.texture != null and v.texture_size.y > 0.0:
		feet_y = v.texture_size.y * 0.45
	var side: float = 1.0 if (plant_idx % 2 == 0) else -1.0
	var x_off: float = side * v.radius * 0.20
	var pos: Vector2 = global_position + Vector2(x_off, feet_y)
	_WalkDustScript.spawn(get_tree().current_scene, pos)


func _draw() -> void:
	# 1. Ground shadow — fixed under feet, ignores walk-bob / breath / flinch.
	if data != null and data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		UnitVisualDrawer.draw_ground_shadow(self, data.visual)

	# 2. Slow-ghost trail at the lagged position (behind a slowed enemy).
	if data != null and data.visual != null and not _slow_pos_history.is_empty():
		var lag_world: Vector2 = _slow_pos_history[0]
		var lag_local: Vector2 = lag_world - global_position
		UnitVisualDrawer.draw_slow_ghost(self, data.visual, lag_local, 0.30)

	# 3. Compose body offset + scale.
	var strike_off: Vector2 = _strike_offset()
	var body_offset: Vector2 = strike_off
	var body_scale: Vector2 = Vector2.ONE
	var walk_rotation: float = 0.0
	if data != null and data.visual != null and state == State.WALKING:
		var anim: Dictionary = UnitVisualDrawer.compute_walk_anim(data.visual, _walk_t, _walk_phase)
		body_offset += anim.offset
		body_scale = anim.scale
		walk_rotation = anim.get("rotation", 0.0)
	# Hurt flinch — recoil from damage source, eases out over FLINCH_DURATION.
	if _flinch_t > 0.0:
		var fa: float = _flinch_t / FLINCH_DURATION
		body_offset += _flinch_dir * FLINCH_DISTANCE * fa
	# Idle breathing — small Y squish pulse while stationary.
	if state == State.COMBAT or _effects.has("stun"):
		var breath: float = sin(_breath_t * 2.5) * 0.025
		body_scale.x *= 1.0 + breath
		body_scale.y *= 1.0 - breath

	# Impact squash — attacker briefly compresses vertically and stretches
	# horizontally at the peak of the strike commit (~the moment damage
	# applied). Reads as weight transfer landing.
	if _strike_t > 0.0:
		var s: float = 1.0 - (_strike_t / STRIKE_ANIM_DURATION)
		# Squash window is narrow around the impact frame (s ≈ 0.45).
		if s > 0.30 and s < 0.65:
			var sq: float = sin((s - 0.30) / 0.35 * PI) * 0.18
			body_scale.x *= 1.0 + sq
			body_scale.y *= 1.0 - sq

	# 4. Build ctx for the drawer (variant + state hooks).
	var ctx: Dictionary = {}
	if data != null and data.visual != null:
		ctx["skin_tint"] = _skin_tint
		ctx["face"] = _facing_dir
		if walk_rotation != 0.0:
			ctx["walk_rotation"] = walk_rotation
		var max_hp: int = _effective_max_health()
		if max_hp > 0 and float(current_health) / float(max_hp) < 0.30:
			ctx["low_hp"] = true
		# Attack wind-up — arm raises during anticipation window.
		if state == State.COMBAT and not _blockers.is_empty() and _combat_cooldown > 0.0 and _combat_cooldown <= ATTACK_TELEGRAPH_DURATION:
			ctx["wind_t"] = smoothstep(ATTACK_TELEGRAPH_DURATION, 0.0, _combat_cooldown)
		# Strike commit — arm sweeps through the swing arc.
		if _strike_t > 0.0:
			ctx["strike_t"] = 1.0 - (_strike_t / STRIKE_ANIM_DURATION)
			ctx["strike_dir"] = _strike_dir

	# 5. Body draw.
	if data != null and data.visual != null:
		var walk_t_arg: float = _walk_t if state == State.WALKING else -1.0
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale, walk_t_arg, _walk_phase, ctx)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
		# Swing-arc trail — weapon swooshing through the air during the
		# strike commit. Same helper heroes use, so the visual is consistent.
		if _strike_t > 0.0:
			var t01: float = 1.0 - (_strike_t / STRIKE_ANIM_DURATION)
			UnitVisualDrawer.draw_swing_arc_trail(self, data.visual, _strike_dir, t01)
	else:
		draw_circle(Vector2.ZERO, 35.0, Color(0.75, 0.2, 0.2))
		draw_arc(Vector2.ZERO, 35.0, 0, TAU, 24, Color(0.15, 0.05, 0.05), 2.0)

	# 6. Stun stars — orbit the head while stunned.
	if _effects.has("stun") and data != null and data.visual != null:
		UnitVisualDrawer.draw_stun_stars(self, data.visual, _status_ring_t)

	# 7. Status rings: slow + stun + marked overlays. Marked uses an outer
	# orange-red ring with 4 segments to read distinct from the existing
	# slow (8-seg blue) and stun (6-seg yellow). Phase 3L addition.
	var ring_r: float = (data.visual.radius if data != null and data.visual != null else 35.0) + 12.0
	if _effects.has("slow"):
		UnitVisualDrawer.draw_status_ring(self, ring_r, Color(0.2, 0.7, 1.0), 8, _status_ring_t * 1.5, 5.0)
	if _effects.has("stun"):
		UnitVisualDrawer.draw_status_ring(self, ring_r + 10.0, Color(1.0, 0.95, 0.2), 6, -_status_ring_t * 2.0, 5.0)
	if _effects.has("marked"):
		# Phase 48 polish — skull glyph above the head replaces the old generic
		# orange dashed ring. Positional cue (above body, not color-on-ring) so
		# the curse reads against any enemy palette and at any zoom.
		var body_top_y: float = -(data.visual.radius if data != null and data.visual != null else 35.0)
		UnitVisualDrawer.draw_marked_skull(self, body_top_y, _status_ring_t)
	_draw_attack_telegraph(ring_r)
	_draw_health_bar()
	_draw_combat_debug()


# Cache the strike direction the moment the counter-attack fires, so the
# follow-through animation completes even if the focus dies / drifts away.
func _start_strike(focus: Node) -> void:
	if focus == null or not is_instance_valid(focus) or not (focus is Node2D):
		_strike_dir = Vector2.RIGHT
	else:
		var d: Vector2 = (focus as Node2D).global_position - global_position
		_strike_dir = d.normalized() if d.length_squared() > 0.001 else Vector2.RIGHT
	_strike_t = STRIKE_ANIM_DURATION


# Body offset combining anticipation (telegraph window before strike) +
# commit + recoil (after strike fires). Replaces the old _inhale_offset —
# enemies now have visible follow-through, not just a silent pull-back.
#   Anticipation: cooldown ∈ (0, ATTACK_TELEGRAPH_DURATION], offset goes
#                 from 0 → -STRIKE_BACK_DIST along strike_dir.
#   Commit:       _strike_t in (~0.45, 1] of normalized strike progress,
#                 offset peaks at +STRIKE_PUSH_DIST forward.
#   Recoil:       _strike_t < 0.45, offset eases from peak back to 0.
func _strike_offset() -> Vector2:
	# Anticipation — derive direction live from focus so a moving target
	# drags the pull-back with it. Strike phase uses the snapshot.
	if state == State.COMBAT and not _blockers.is_empty() and _combat_cooldown > 0.0 and _combat_cooldown <= ATTACK_TELEGRAPH_DURATION:
		var focus: Node = _blockers[0]
		if focus != null and is_instance_valid(focus) and focus is Node2D:
			var d: Vector2 = (focus as Node2D).global_position - global_position
			if d.length_squared() > 0.01:
				var t: float = smoothstep(ATTACK_TELEGRAPH_DURATION, 0.0, _combat_cooldown)
				return -d.normalized() * STRIKE_BACK_DIST * t
	# Commit + recoil. Normalized progress s = 1 at start, 0 at end (mirrors
	# the lunge curve: rear-back peak → forward peak → ease back to neutral).
	if _strike_t > 0.0 and _strike_dir.length_squared() > 0.001:
		var s: float = 1.0 - (_strike_t / STRIKE_ANIM_DURATION)
		var amount: float
		if s < 0.45:
			amount = lerp(-STRIKE_BACK_DIST, STRIKE_PUSH_DIST, s / 0.45)
		else:
			amount = lerp(STRIKE_PUSH_DIST, 0.0, (s - 0.45) / 0.55)
		return _strike_dir * amount
	return Vector2.ZERO


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
	var max_hp: int = _effective_max_health()
	if max_hp <= 0 or current_health >= max_hp:
		return
	var zs: float = _get_zoom_scale()
	var bar_size: Vector2 = HP_BAR_SIZE * zs
	# Multi-part bodies have a head above the torso; bar must clear the head.
	var bar_y_local: float = HP_BAR_Y_OFFSET
	if data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		var head_top: float = data.visual.head_y_offset * data.visual.radius - data.visual.head_radius_ratio * data.visual.radius
		bar_y_local = minf(HP_BAR_Y_OFFSET, head_top - 12.0)
	var bar_y: float = bar_y_local * zs
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-bar_size.x * 0.5, bar_y)
	draw_rect(Rect2(origin, bar_size), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(bar_size.x * pct, bar_size.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0), false, 1.0)


func _draw_combat_debug() -> void:
	if not OS.is_debug_build():
		return
	if _reservers.is_empty() and _blockers.is_empty() and state != State.COMBAT:
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = COMBAT_DEBUG_FONT_SIZE
	var lines: Array[String] = [
		"E %s hp:%d" % [_state_name(state), current_health],
		"res:%d blk:%d held:%s" % [
			_reservers.size(),
			_blockers.size(),
			"Y" if is_held() else "n",
		],
	]
	if not _blockers.is_empty():
		lines.append("focus:%s" % _debug_node_label(_blockers[0]))
	_draw_debug_lines(font, lines, Vector2(-56.0, -96.0), fs)


func _draw_debug_lines(font: Font, lines: Array[String], origin: Vector2, fs: int) -> void:
	if lines.is_empty():
		return
	var max_w: float = 0.0
	for line in lines:
		max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var line_h: float = float(fs) + 3.0
	var bg := Rect2(origin + Vector2(-3.0, -float(fs) - 3.0), Vector2(max_w + 6.0, line_h * lines.size() + 6.0))
	draw_rect(bg, Color(0.02, 0.02, 0.025, 0.72))
	draw_rect(bg, Color(0.4, 0.85, 1.0, 0.75), false, 1.0)
	for i in range(lines.size()):
		draw_string(font, origin + Vector2(0.0, float(i) * line_h), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0.75, 0.95, 1.0))


func _debug_node_label(n) -> String:
	if n == null or not is_instance_valid(n):
		return "-"
	var unit_data = n.get("data")
	if unit_data != null:
		if "hero_id" in unit_data:
			return unit_data.hero_id
		if "enemy_id" in unit_data:
			return unit_data.enemy_id
	return n.name


func _state_name(s: int) -> String:
	match s:
		State.WALKING:
			return "WALK"
		State.COMBAT:
			return "COMBAT"
		State.STEALTHED:
			return "STEALTH"
		State.DYING:
			return "DYING"
	return str(s)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
