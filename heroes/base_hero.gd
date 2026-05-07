extends CharacterBody2D
class_name BaseHero

# Phase 18+42: Kingdom Rush-style hero with NavigationAgent2D pathfinding.
# One hero per level (Phase 30 wires selection in HeroRoom).
#
# States:
#   IDLE     → standing, scans SeekRange for enemies to auto-walk toward
#   MOVING   → nav-pathing toward tap target or auto-seek enemy
#   COMBAT   → melee: face-to-face; ranged: attack from distance
#   DEAD     → death anim placeholder, ignored by _physics_process
#
# Auto-seek: hero scans a large SeekRange (2.5x attack_range). When an
# enemy enters, the hero nav-paths toward it. Melee heroes walk right up
# (within MELEE_ENGAGE_DISTANCE); ranged heroes stop at attack_range edge.
# If an enemy leaves attack range during combat, the hero chases.
# Player tap-to-move always overrides auto-seek and combat.

enum State { IDLE, MOVING, COMBAT, DEAD }

const HP_BAR_SIZE: Vector2 = Vector2(90.0, 13.0)
const HP_BAR_Y_OFFSET: float = -55.0
const MOVE_REACHED_TOLERANCE: float = 10.0
# Tap-to-select hit radius around the hero body (slightly larger than the
# 50×50 visual square so it's finger-friendly).
const SELECT_TAP_RADIUS: float = 55.0
const SELECTION_RING_RADIUS: float = 45.0
const HIT_FLASH_DURATION: float = 0.08
# Move-order marker — small expanding ring drawn at the destination of an
# accepted move_to() command. Confirms the order landed before the hero
# has visibly turned, the way RTS click-feedback markers do.
const MOVE_MARKER_DURATION: float = 0.5
const MOVE_MARKER_BASE_RADIUS: float = 6.0
const MOVE_MARKER_EXPAND: float = 14.0
# Lunge animation — hero hops a few px toward its target on every attack
# tick and snaps back. Triangle-wave easing computed analytically; no Tween
# node allocated (cheaper, and a new attack just resets the clock).
const LUNGE_DURATION: float = 0.12
const LUNGE_DISTANCE: float = 18.0
# Auto-seek: hero walks toward enemies within this multiplied range.
const SEEK_RANGE_MULTIPLIER: float = 2.5
# Throttle repathing toward a moving seek target (mobile perf).
const NAV_REPATH_INTERVAL: float = 0.5
# Melee heroes walk up this close before entering COMBAT face-to-face.
const MELEE_ENGAGE_DISTANCE: float = 30.0
# Side-by-side combat spacing. Melee heroes navigate to a slot offset
# horizontally by this much from the enemy, sharing the enemy's Y — so the
# two units end up lined up instead of overlapping bodies.
const MELEE_ENGAGE_GAP_X: float = 55.0
# Attack_range threshold that separates melee from ranged behavior. Melee
# uses MELEE_ENGAGE_GAP_X side-by-side; ranged stops at 80 % of attack_range
# along the approach vector.
const RANGED_ATTACK_RANGE_THRESHOLD: float = 150.0
# Default block-claim radius when HeroData.engage_radius is unset (0).
# Clamped down by attack_range so a tiny-reach hero doesn't claim blocks
# past its own swing. See HeroData.engage_radius for the rationale.
const DEFAULT_ENGAGE_RADIUS: float = 60.0
# Hero will not chase enemies that are farther than this from its current
# rally point. The rally point is the HeroSpawn marker at start and updates
# to the tap position on every player-issued move command.
const LEASH_RADIUS: float = 400.0
# Stop returning to the rally point once within this distance of it.
const LEASH_RETURN_TOLERANCE: float = 20.0

@export var data: HeroData

var state: int = State.IDLE
var current_health: int = 0
# Option B selection: tap hero → armed (ring on). Issuing a move command
# (or dying) auto-clears it so a later stray tap doesn't re-move the hero.
var is_selected: bool = false

# Phase 19 — XP / leveling. current_xp resets to 0 after each level-up and
# ticks toward data.xp_per_level[level - 1] (the cost of the next level).
# Per level we add +15% max_health (and heal to full) and +10% damage.
var level: int = 1
var current_xp: int = 0
const LEVEL_HEALTH_GROWTH: float = 0.15
const LEVEL_DAMAGE_GROWTH: float = 0.10

var _target_enemy: Node = null
var _attack_cooldown: float = 0.0
# Enemies this hero currently blocks. Capped at data.max_block_targets.
# Tracked so we release cleanly on state changes / death / retarget.
# Mirrors the multi-blocker array on BaseEnemy.
var _blocked_enemies: Array[Node] = []
# Auto-seek: enemy the hero is walking toward (not yet in attack range).
var _seek_target_enemy: Node = null
var _nav_repath_timer: float = 0.0

var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_t: float = 0.0
var _hit_flash_t: float = 0.0
# Move-order marker — world-space destination of the last accepted move_to,
# plus a 1.0→0.0 fade timer. Drawn in _draw() via to_local().
var _move_marker_pos: Vector2 = Vector2.ZERO
var _move_marker_t: float = 0.0
# Hurt flinch — body recoil away from damage source on each hit. Mirrors
# the BaseEnemy flinch so combat readability is consistent across units.
const FLINCH_DURATION: float = 0.12
const FLINCH_DISTANCE: float = 6.0
var _flinch_t: float = 0.0
var _flinch_dir: Vector2 = Vector2.ZERO
# Walk-bob accumulator and per-hero phase. Driven by the same UnitVisualData
# fields enemies use; ticks while MOVING.
var _walk_t: float = 0.0
var _walk_phase: float = 0.0
# Hit-stop — freezes _physics_process for a few frames after every hit
# (mirrors the BaseEnemy device). Set in take_damage and externally
# (BaseEnemy.take_damage looks up this property by name on its source).
const HIT_STOP_DURATION: float = 0.05
var _hit_stop_t: float = 0.0
# Skill cast pose — when cast_skill fires, arm raises + body briefly
# stretches for CAST_ANIM_DURATION so casts don't feel instant. The skill
# effect itself still applies immediately; this is purely cosmetic on top.
const CAST_ANIM_DURATION: float = 0.25
var _cast_t: float = 0.0
var _cast_dir: Vector2 = Vector2.RIGHT
# Idle breathing — small Y squish pulse while IDLE / COMBAT so a stationary
# hero doesn't read as frozen.
var _breath_t: float = 0.0
# Facing direction for direction-aware eyes. Updated from velocity when the
# hero moves, falls back to the active target / lunge direction otherwise.
var _facing_dir: Vector2 = Vector2.RIGHT
var _prev_pos: Vector2 = Vector2.ZERO
# Rally point — world position the hero leashes to. Seeded from the spawn
# marker in _ready() and reseeded on each player-commanded move. Enemies
# outside LEASH_RADIUS of this point are ignored; when idle, the hero
# walks back to the rally.
var _rally_position: Vector2 = Vector2.ZERO

# Phase 20: parallel to data.skills — seconds of cooldown remaining per
# slot. Sized in _ready(). The skill resource is shared; only the cooldown
# state is per-hero, which is why it lives here and not on SkillData.
var _skill_cooldowns: Array[float] = []

# Phase 20 targeting overlay — non-zero radius when the SkillBar has an
# armed skill. Drawn as a yellow range circle under the hero so the
# player can see the cast reach. Reset to 0 on cancel / cast.
var _skill_range_preview: float = 0.0

# Phase 48 — Base + Modifier Stack stat pipeline (Unreal GAS-style).
# `base_stats` holds permanent values (seeded from HeroData + level growth +
# account-wide upgrade multipliers). `_modifier_sources` is the live stack of
# contributing sources — equipped items, temporary buffs, talent-granted
# auras. `current_stats` is the cached derived value, rebuilt by
# `recompute_stats()` on any stack change or base mutation. Never mutate
# current_stats directly; never diff-revert. Concurrent buffs survive equip
# swaps, and float drift is impossible.
var base_stats: Dictionary = {}
var current_stats: Dictionary = {}
var _modifier_sources: Array = []

# Phase 20.5: passive-ability dispatcher. Populated from data.abilities in
# _ready; ticked each _physics_process; triggered on hit-dealt/taken/kill/
# death so passives like "on-kill: +5% damage for 3 s" can hook in later.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
var _ability_host: RefCounted = null

@onready var attack_range_area: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D
@onready var engage_range_area: Area2D = $EngageRange
@onready var engage_range_shape: CollisionShape2D = $EngageRange/CollisionShape2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var seek_range_area: Area2D = $SeekRange
@onready var seek_range_shape: CollisionShape2D = $SeekRange/CollisionShape2D


func _ready() -> void:
	if data == null:
		push_warning("[BaseHero] missing HeroData")
		return
	# Phase 48 — persistent hero level/XP. MetaProgression owns the dictionary;
	# BaseHero reads it on spawn and delegates gain_xp back. Level is read
	# BEFORE _seed_base_stats so the level-growth multiplier is correct.
	level = MetaProgression.get_hero_level(data.hero_id)
	current_xp = MetaProgression.get_hero_xp(data.hero_id)
	_seed_base_stats()
	recompute_stats()
	current_health = _effective_max_health()
	var atk_circle := CircleShape2D.new()
	atk_circle.radius = data.attack_range
	attack_range_shape.shape = atk_circle
	# EngageRange — block-claim radius (see _effective_engage_radius). Decoupled
	# from attack_range so ranged heroes attack at distance without locking
	# every enemy at the edge of their projectile reach.
	var engage_circle := CircleShape2D.new()
	engage_circle.radius = _effective_engage_radius()
	engage_range_shape.shape = engage_circle
	# SeekRange — hero auto-walks toward enemies in this larger radius.
	var seek_circle := CircleShape2D.new()
	seek_circle.radius = data.attack_range * SEEK_RANGE_MULTIPLIER
	seek_range_shape.shape = seek_circle
	_skill_cooldowns.resize(data.skills.size())
	_skill_cooldowns.fill(0.0)
	_ability_host = _AbilityHostScript.new(self)
	if "abilities" in data:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	# Phase 40: push purchased talents' abilities onto the hero.
	if "talents" in data and data.hero_id in MetaProgression.hero_talents:
		var purchased_ids: Array = MetaProgression.hero_talents[data.hero_id]
		for talent in data.talents:
			if talent != null and talent.talent_id in purchased_ids and talent.ability != null:
				_ability_host.add_ability(talent.ability.duplicate())
	# Phase 48: push equipped items' abilities through AbilityHost.equip_ability
	# so ON_EQUIP fires, StatModifierAbility joins the modifier stack, and
	# recompute_stats rebuilds current_stats with item contributions.
	for inst in InventoryManager.get_all_equipped(data.hero_id):
		if inst == null:
			continue
		for ab in inst.build_runtime_abilities(ContentRegistry):
			_ability_host.equip_ability(ab)
	# Re-seed current_health AFTER items so spawns start at full (item-boosted) HP.
	current_health = _effective_max_health()
	# Seed the rally point from the spawn position; the player can reseat it
	# by tapping to move. Position is already set by Main._spawn_hero before
	# add_child, so global_position here is the HeroSpawn marker.
	_rally_position = global_position
	_walk_phase = randf() * TAU
	_prev_pos = global_position
	# Listen for confirmed taps from GameCamera's gesture classifier.
	EventBus.map_tap_confirmed.connect(_on_map_tap)
	# Deferred so sibling nodes (HUD, Main) have finished _ready() and
	# connected to hero_spawned before we fire it. Without this, Main.tscn
	# sibling-order has HUD readying AFTER the hero, so the initial Lv/XP
	# payload never reaches the HUD label.
	EventBus.hero_spawned.emit.call_deferred(self)


func _seed_base_stats() -> void:
	# Called on ready and whenever a permanent base value changes (level-up,
	# permanent upgrade purchase). Seeds base_stats from HeroData with the
	# per-level growth curves and account-wide upgrade multipliers already
	# baked in — those are "permanent" sources and don't belong in the
	# modifier stack.
	if data == null:
		base_stats.clear()
		return
	var hp_mult: float = 1.0 + float(level - 1) * LEVEL_HEALTH_GROWTH
	var dmg_mult: float = 1.0 + float(level - 1) * LEVEL_DAMAGE_GROWTH
	base_stats["max_health"] = float(data.max_health) * hp_mult
	base_stats["damage"] = data.attack_damage * dmg_mult * MetaProgression.get_upgrade_multiplier(MetaProgression.MOD_HERO_DAMAGE)
	base_stats["armor"] = data.armor
	base_stats["attack_speed"] = data.attack_speed
	base_stats["move_speed"] = data.move_speed
	base_stats["xp_gain_mult"] = 1.0


func register_modifier_source(m) -> void:
	if m == null or _modifier_sources.has(m):
		return
	_modifier_sources.append(m)


func unregister_modifier_source(m) -> void:
	_modifier_sources.erase(m)


func _refresh_health_after_modifier_change() -> void:
	# Max HP went up or down — clamp current_health so equipping a +HP item
	# doesn't auto-heal and unequipping one doesn't leave health above max.
	if data == null:
		return
	var max_hp: int = _effective_max_health()
	if current_health > max_hp:
		current_health = max_hp


func recompute_stats() -> void:
	# Rebuild current_stats from base + modifier stack. Additive flats apply
	# first, then multiplicative pcts (product of (1 + pct)). Order is fixed
	# so the same modifier set always yields the same current value.
	current_stats.clear()
	for key in base_stats.keys():
		var flat_field: String = "%s_flat" % key
		var pct_field: String = "%s_pct" % key
		var v: float = float(base_stats[key])
		var pct_product: float = 1.0
		for m in _modifier_sources:
			if m == null:
				continue
			if flat_field in m:
				v += float(m.get(flat_field))
			if pct_field in m:
				pct_product *= 1.0 + float(m.get(pct_field))
		v *= pct_product
		current_stats[key] = v


func _effective_max_health() -> int:
	if data == null:
		return 0
	var v: float = float(current_stats.get("max_health", float(data.max_health)))
	return int(ceil(v))


func _effective_damage() -> float:
	if data == null:
		return 0.0
	return float(current_stats.get("damage", data.attack_damage))


func _tick_skill_cooldowns(delta: float) -> void:
	for i in _skill_cooldowns.size():
		if _skill_cooldowns[i] <= 0.0:
			continue
		var before: float = _skill_cooldowns[i]
		_skill_cooldowns[i] = maxf(0.0, _skill_cooldowns[i] - delta)
		if before > 0.0 and _skill_cooldowns[i] <= 0.0:
			var skill: Resource = get_skill_data(i)
			if skill != null:
				EventBus.skill_ready.emit(skill.skill_name)


func get_skill_data(idx: int) -> Resource:
	if data == null or idx < 0 or idx >= data.skills.size():
		return null
	return data.skills[idx] as Resource


func get_skill_cooldown_fraction(idx: int) -> float:
	# 0.0 = ready, 1.0 = just cast. UI radial overlay maps this to arc coverage.
	var skill: Resource = get_skill_data(idx)
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	if idx >= _skill_cooldowns.size():
		return 0.0
	return clampf(_skill_cooldowns[idx] / skill.cooldown, 0.0, 1.0)


# CooldownButton provider contract — generic names so the same button
# class can drive any future cooldown-gated cast surface, not just hero skills.
func cooldown_fraction(idx: int) -> float:
	return get_skill_cooldown_fraction(idx)


func display_name(idx: int) -> String:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return "?"
	return skill.skill_name


func get_skill_effective_range(idx: int) -> float:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return 0.0
	if skill.skill_range > 0.0:
		return skill.skill_range
	return data.attack_range


func set_skill_range_preview(radius: float) -> void:
	if is_equal_approx(_skill_range_preview, radius):
		return
	_skill_range_preview = radius
	queue_redraw()


func can_cast_skill(idx: int) -> bool:
	if state == State.DEAD or data == null:
		return false
	if idx < 0 or idx >= _skill_cooldowns.size():
		return false
	return _skill_cooldowns[idx] <= 0.0


func cast_skill(idx: int, target) -> bool:
	# target: Node (for SINGLE), Vector2 (for AREA), or null (for SELF).
	# Returns true if the skill actually fired (not on cooldown / valid target).
	if not can_cast_skill(idx):
		return false
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return false
	skill.apply(self, target)
	_skill_cooldowns[idx] = skill.cooldown
	EventBus.hero_skill_used.emit(skill.skill_name)
	EventBus.skill_cooldown_started.emit(skill.skill_name, skill.cooldown)
	# Cast pose — arm raised + body stretch for CAST_ANIM_DURATION so the
	# skill activation reads as a deliberate cast rather than a silent
	# instant. The cast direction faces the target when there is one.
	_cast_t = CAST_ANIM_DURATION
	if target is Node2D:
		var d: Vector2 = (target as Node2D).global_position - global_position
		_cast_dir = d.normalized() if d.length_squared() > 0.001 else Vector2.RIGHT
		# Single-target melee cast also gets the standard lunge.
		_start_lunge(target.global_position)
	elif target is Vector2:
		var d2: Vector2 = (target as Vector2) - global_position
		_cast_dir = d2.normalized() if d2.length_squared() > 0.001 else _facing_dir
	else:
		_cast_dir = _facing_dir
	return true


func _xp_needed_for_next_level() -> int:
	if data == null or level >= data.max_level:
		return 0
	var idx: int = level - 1
	if idx < 0 or idx >= data.xp_per_level.size():
		return 0
	return data.xp_per_level[idx]


func gain_xp(amount: int) -> void:
	if state == State.DEAD or data == null or amount <= 0:
		return
	if level >= data.max_level:
		return
	# Phase 48: delegate to MetaProgression which owns the persistent dict + the
	# level-up math (+ xp multiplier + hero_leveled_up signal). Then mirror
	# the results back so combat code doesn't re-read MetaProgression each frame.
	# MetaProgression.add_hero_xp already emits hero_xp_gained and hero_leveled_up
	# signals itself — don't re-emit them here.
	var old_level: int = level
	var new_level: int = MetaProgression.add_hero_xp(data.hero_id, amount)
	level = new_level
	current_xp = MetaProgression.get_hero_xp(data.hero_id)
	while old_level < new_level:
		old_level += 1
		_level_up_apply()


func _level_up_apply() -> void:
	# Runtime side of a level-up. MetaProgression already emitted hero_leveled_up
	# and bumped the persistent entry; this method updates the live hero:
	# re-seed base, recompute modifiers, heal to full.
	_seed_base_stats()
	recompute_stats()
	current_health = _effective_max_health()
	queue_redraw()
	print("[Hero] %s reached level %d" % [data.hero_name, level])
	# Detect any skill whose level_required matches this new level. Fire
	# the signal + a Toast — the player still has to equip it manually
	# from Heroes → Skills (not auto-equipped, that defeats the choice).
	# Toast.show_message kills the prior tween on every call, so multiple
	# unlocks at the same level (or across levels in an XP-catchup) would
	# only ever surface the LAST message. Combine into one toast.
	var unlocked: Array[String] = LoadoutState.get_skills_unlocked_at_level(data.hero_id, level)
	for skill_id in unlocked:
		EventBus.hero_skill_unlocked.emit(data.hero_id, skill_id)
	if unlocked.size() == 1:
		var sd: Resource = _find_skill_data_by_id(unlocked[0])
		var nm: String = sd.skill_name if sd != null else unlocked[0]
		Toast.show_message("New skill: %s — equip from Heroes → Skills" % nm)
	elif unlocked.size() > 1:
		Toast.show_message("%d new skills unlocked — equip from Heroes → Skills" % unlocked.size())


func _find_skill_data_by_id(skill_id: String) -> Resource:
	if data == null or skill_id == "":
		return null
	for skill in data.skills:
		if skill != null and skill.skill_id == skill_id:
			return skill
	return null


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func move_to(world_pos: Vector2) -> void:
	if state == State.DEAD or data == null:
		return
	# Explicit move overrides any active engagement or auto-seek. Free any
	# enemy we were blocking so it resumes walking.
	_release_block()
	_seek_target_enemy = null
	_target_enemy = null
	_attack_cooldown = 0.0
	# Player tap reseats the rally point — the hero will leash to wherever
	# the player sent it, not back to the original spawn.
	_rally_position = world_pos
	nav_agent.target_position = world_pos
	# Move-order marker — arm the destination ring. Sits here so it only
	# fires for orders that pass the DEAD/data gate above; HeroInputManager
	# already filters illegal taps (tower spots, unselected hero) before
	# we get here, so reaching this line means the order is legitimate.
	_move_marker_pos = world_pos
	_move_marker_t = 1.0
	# Auto-deselect on move command — Option B. Next stray tap won't re-move
	# the hero until the player taps the body to re-arm.
	if is_selected:
		set_selected(false)
	change_state(State.MOVING)


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	queue_redraw()


func _on_map_tap(screen_pos: Vector2, claim: RefCounted) -> void:
	# Tap-on-hero distance check. Connected after SpotInputManager so tower
	# spots claim the tap first when the hero stands on/near a spot.
	if claim.claimed:
		return
	if state == State.DEAD:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
	var zoom_scale: float = _get_zoom_scale()
	if local.length() > SELECT_TAP_RADIUS * zoom_scale:
		return
	set_selected(not is_selected)
	claim.claimed = true


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x


func _physics_process(delta: float) -> void:
	if state == State.DEAD or data == null:
		return
	# Hit-stop — universal freeze on hit. Decrement and bail before any
	# state machine / movement / animation tick so the world holds frame.
	if _hit_stop_t > 0.0:
		_hit_stop_t = maxf(0.0, _hit_stop_t - delta)
		return
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		queue_redraw()
	if _cast_t > 0.0:
		_cast_t = maxf(0.0, _cast_t - delta)
		queue_redraw()
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
		queue_redraw()
	if _flinch_t > 0.0:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		queue_redraw()
	if _move_marker_t > 0.0:
		_move_marker_t = maxf(0.0, _move_marker_t - delta / MOVE_MARKER_DURATION)
		queue_redraw()
	# Facing direction — sampled from world delta. Falls back to active
	# target direction when the hero is stationary so eyes still face the
	# enemy during combat.
	var dp: Vector2 = global_position - _prev_pos
	if dp.length_squared() > 0.05:
		_facing_dir = dp.normalized()
	elif state == State.COMBAT and _target_enemy != null and is_instance_valid(_target_enemy):
		var to_t: Vector2 = (_target_enemy.global_position - global_position)
		if to_t.length_squared() > 0.001:
			_facing_dir = to_t.normalized()
	_prev_pos = global_position
	_tick_skill_cooldowns(delta)
	if _ability_host != null:
		_ability_host.tick(delta)
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			_seek_target()
			_breath_t += delta
			queue_redraw()
		State.MOVING:
			_move_step(delta)
			# Walk-bob tick — gated on visual fields so heroes with bob
			# disabled skip the per-frame redraw.
			if data != null and data.visual != null:
				var v: UnitVisualData = data.visual
				if v.walk_bob_amplitude > 0.0 or v.walk_squash > 0.0:
					_walk_t += delta
					queue_redraw()
		State.COMBAT:
			velocity = Vector2.ZERO
			_attack_step(delta)
			_breath_t += delta
			queue_redraw()
	move_and_slide()


func _start_lunge(target_world_pos: Vector2) -> void:
	var dir: Vector2 = target_world_pos - global_position
	if dir.length_squared() < 0.01:
		return
	_lunge_dir = dir.normalized()
	# Cap duration so very fast attack_speed values don't truncate the lunge
	# mid-animation — we want each swing's lunge to fully complete before
	# the next one starts (would look like the hero stuttering forward).
	var cooldown: float = 1.0 / maxf(0.01, data.attack_speed) if data != null else LUNGE_DURATION
	_lunge_t = minf(LUNGE_DURATION, cooldown * 0.9)
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	# Wind-up curve: rear back, commit forward, ease back.
	#   [0.00, 0.25]:  0   → -0.3 LUNGE_DISTANCE  (anticipation)
	#   [0.25, 0.75]: -0.3 → +1.0                 (strike commits)
	#   [0.75, 1.00]: +1.0 → 0                    (recovery)
	# Adds perceived weight to every swing without changing attack cadence.
	var t: float = 1.0 - (_lunge_t / LUNGE_DURATION)
	var offset_scale: float = 0.0
	if t < 0.25:
		offset_scale = -0.3 * (t / 0.25)
	elif t < 0.75:
		offset_scale = -0.3 + 1.3 * ((t - 0.25) / 0.5)
	else:
		offset_scale = 1.0 - ((t - 0.75) / 0.25)
	return _lunge_dir * (LUNGE_DISTANCE * offset_scale)


func _move_step(delta: float) -> void:
	# While auto-seeking, repath toward the moving enemy's engage slot.
	# Abort chases that exit the leash — the hero is not a lawnmower.
	if _seek_target_enemy != null:
		if not _within_leash(_seek_target_enemy) \
				or not is_instance_valid(_seek_target_enemy) \
				or _seek_target_enemy.state == BaseEnemy.State.DYING:
			_seek_target_enemy = null
			nav_agent.target_position = _rally_position
		else:
			_nav_repath_timer -= delta
			if _nav_repath_timer <= 0.0:
				_nav_repath_timer = NAV_REPATH_INTERVAL
				nav_agent.target_position = _engage_position_for(_seek_target_enemy)
			# Check if enemy entered attack range while we walk toward it.
			var atk_target: Node = _find_nearest_enemy_in_area(attack_range_area)
			if atk_target != null and _within_leash(atk_target):
				var dist: float = global_position.distance_to(atk_target.global_position)
				if dist <= MELEE_ENGAGE_DISTANCE or atk_target in attack_range_area.get_overlapping_areas():
					_target_enemy = atk_target
					_seek_target_enemy = null
					_attack_cooldown = 0.0
					_start_block(atk_target)
					change_state(State.COMBAT)
					return
	# Follow nav agent path.
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		_seek_target_enemy = null
		change_state(State.IDLE)
		return
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	velocity = (next_pos - global_position).normalized() * data.move_speed


func _find_nearest_enemy_in_area(area: Area2D) -> Node:
	return _pick_split_target_in_area(area)


# Split-rule picker: prefers the enemy with the FEWEST current blockers so
# friendlies spread across incoming threats instead of piling on one. Ties
# resolved by distance. Enforces the standard filters (DYING, flying when
# data.targets_flying is false, within-leash).
func _pick_split_target_in_area(area: Area2D) -> Node:
	var best: Node = null
	var best_block: int = 1 << 30
	var best_d2: float = INF
	for a in area.get_overlapping_areas():
		if not (a is BaseEnemy):
			continue
		var enemy: BaseEnemy = a
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if enemy.data == null:
			continue
		if enemy.data.is_flying and not data.targets_flying:
			continue
		var bc: int = enemy._blockers.size()
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if bc < best_block or (bc == best_block and d2 < best_d2):
			best_block = bc
			best_d2 = d2
			best = enemy
	return best


func _seek_target() -> void:
	# Phase 1: check attack range — immediate combat. Leash-gated so the
	# hero never engages enemies that would pull it far from the rally.
	var nearest_attack: Node = _find_nearest_enemy_in_area(attack_range_area)
	if nearest_attack != null and _within_leash(nearest_attack):
		_target_enemy = nearest_attack
		_seek_target_enemy = null
		_attack_cooldown = 0.0
		_start_block(nearest_attack)
		change_state(State.COMBAT)
		return
	# Phase 2: check seek range — auto-walk toward enemy via nav agent.
	var nearest_seek: Node = _find_nearest_enemy_in_area(seek_range_area)
	if nearest_seek != null and _within_leash(nearest_seek) and nearest_seek != _seek_target_enemy:
		_seek_target_enemy = nearest_seek
		nav_agent.target_position = _engage_position_for(nearest_seek)
		_nav_repath_timer = 0.0
		change_state(State.MOVING)
		return
	# Phase 3: no valid enemy + drifted from rally → walk back.
	if global_position.distance_to(_rally_position) > LEASH_RETURN_TOLERANCE:
		_seek_target_enemy = null
		nav_agent.target_position = _rally_position
		change_state(State.MOVING)


# True if the target sits within LEASH_RADIUS of the current rally point.
func _within_leash(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.global_position.distance_to(_rally_position) <= LEASH_RADIUS


# Where the hero should stand to attack the given enemy.
#   Melee (attack_range < threshold): side-by-side — same Y as the enemy,
#     offset horizontally by MELEE_ENGAGE_GAP_X on whichever side the hero
#     is currently on. Produces the "line up next to each other" look.
#   Ranged: keep 80 % of attack_range between hero and enemy, along the
#     hero's current approach vector, so casters don't walk into melee.
func _engage_position_for(enemy: Node) -> Vector2:
	var epos: Vector2 = enemy.global_position
	if data.attack_range < RANGED_ATTACK_RANGE_THRESHOLD:
		var dx: float = global_position.x - epos.x
		var side: float = signf(dx) if absf(dx) > 5.0 else 1.0
		return Vector2(epos.x + side * MELEE_ENGAGE_GAP_X, epos.y)
	var to_hero: Vector2 = global_position - epos
	if to_hero.length_squared() < 1.0:
		to_hero = Vector2.RIGHT
	return epos + to_hero.normalized() * (data.attack_range * 0.8)


func _attack_step(delta: float) -> void:
	if _target_enemy == null or not is_instance_valid(_target_enemy):
		_release_block()
		_target_enemy = null
		change_state(State.IDLE)
		return
	var enemy: BaseEnemy = _target_enemy
	if enemy.state == BaseEnemy.State.DYING:
		_release_block()
		_target_enemy = null
		change_state(State.IDLE)
		return
	# Enemy walked out of attack range — chase if still in leash, else drop.
	if not (enemy in attack_range_area.get_overlapping_areas()):
		_release_block_of(enemy)
		_target_enemy = null
		if _within_leash(enemy):
			_seek_target_enemy = enemy
			nav_agent.target_position = _engage_position_for(enemy)
			_nav_repath_timer = 0.0
			change_state(State.MOVING)
		else:
			_seek_target_enemy = null
			nav_agent.target_position = _rally_position
			change_state(State.MOVING)
		return
	# Capacity-aware multi-block: while in combat with _target_enemy, scan
	# for additional unblocked enemies overlapping attack range and claim
	# them too, up to data.max_block_targets. Uses the split-rule picker
	# so we grab the next-neediest target, not just the nearest.
	_auto_engage_extras()
	# Prune blocks on enemies that have since died or wandered out of range
	# so enemies don't stay frozen when the hero no longer "holds" them.
	_prune_blocks_out_of_range()
	# Reciprocal damage is driven by enemy._combat_tick while this hero
	# occupies one of its _blockers slots — see _start_block() below. No
	# extra timer needed here.
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	_start_lunge(enemy.global_position)
	var dmg: float = _effective_damage()
	var dying: bool = enemy.state == BaseEnemy.State.DYING
	enemy.take_damage(dmg, data.damage_type, self)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": dmg})
		# Kill is inferred by post-hit state transition. BaseEnemy enters
		# DYING inside take_damage when HP drops to 0.
		if not dying and enemy.state == BaseEnemy.State.DYING:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


func heal(amount: float) -> void:
	if state == State.DEAD or data == null:
		return
	var max_hp: int = _effective_max_health()
	if current_health >= max_hp:
		return
	current_health = mini(max_hp, current_health + int(ceil(amount)))
	queue_redraw()


func take_damage(amount: float, type: int, source: Node = null) -> void:
	if state == State.DEAD or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if final > 0.0:
		_hit_flash_t = HIT_FLASH_DURATION
		# Hit-stop on both this hero and the source (universal action-game
		# device — adds weight to every hit landed on the hero).
		_hit_stop_t = HIT_STOP_DURATION
		if source != null and is_instance_valid(source) and "_hit_stop_t" in source:
			source._hit_stop_t = HIT_STOP_DURATION
		# Flinch — recoil away from damage source for a brief window.
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


func _die() -> void:
	# Idempotent: future ability/effect code paths may call _die() outside
	# the take_damage guard; double-firing would emit hero_died twice and
	# schedule two respawn timers.
	if state == State.DEAD:
		return
	change_state(State.DEAD)
	velocity = Vector2.ZERO
	set_selected(false)
	_release_block()
	_target_enemy = null
	_seek_target_enemy = null
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.hero_died.emit()
	# Death drift — rotate to a side, drop, fade, then hide. _physics_process
	# bails on State.DEAD so move_and_slide won't fight the position tween.
	# TWEEN_PAUSE_PROCESS so a death that triggers game_over still finishes
	# the animation past the pause.
	var drift_dir: float = 1.0 if randf() > 0.5 else -1.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "rotation", drift_dir * deg_to_rad(75.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y + 28.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.30).set_delay(0.10)
	tween.chain().tween_callback(_on_death_drift_done)
	# Schedule respawn. HeroData.respawn_time (default 30s). Timer honors
	# the paused SceneTree (process_always defaults to false), so tactical
	# pause freezes the countdown — fair to the player.
	var wait: float = data.respawn_time if data != null and data.respawn_time > 0.0 else 30.0
	get_tree().create_timer(wait).timeout.connect(_respawn)


func _on_death_drift_done() -> void:
	visible = false
	rotation = 0.0
	modulate.a = 1.0


func _respawn() -> void:
	# Scene may have been reloaded (restart) while the timer was running.
	if not is_instance_valid(self) or data == null:
		return
	# Teleport back to the level's HeroSpawn marker (falls back if absent).
	# Main.gd instantiates the level scene dynamically (Level1/Level2/...)
	# and exposes it as `level`. Reading that property keeps respawn working
	# on any level — never hardcode a per-level node name here.
	var scene: Node = get_tree().current_scene
	var spawn_pos: Vector2 = global_position
	var lvl: Node = null
	if scene != null:
		if "level" in scene:
			lvl = scene.level
		if lvl == null or not lvl.has_method("get_hero_spawn_position"):
			# Fallback for non-Main scene roots (tests, isolated runs).
			for child in scene.get_children():
				if child.has_method("get_hero_spawn_position"):
					lvl = child
					break
		if lvl != null and lvl.has_method("get_hero_spawn_position"):
			spawn_pos = lvl.get_hero_spawn_position()
	global_position = spawn_pos
	_rally_position = spawn_pos
	current_health = _effective_max_health()
	# Reset any leftover state from the death-drift tween in case respawn
	# fires before the drift's 0.4s completion (short respawn_time edge case).
	rotation = 0.0
	modulate.a = 1.0
	visible = true
	_attack_cooldown = 0.0
	change_state(State.IDLE)
	queue_redraw()
	EventBus.hero_respawned.emit()


# Claim one more enemy's blocker slot, up to data.max_block_targets. Flying
# enemies skip engagement entirely. Unlike the old single-slot version,
# this does NOT release an existing block — both can coexist so the hero
# can tank multiple enemies side-by-side.
func _start_block(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.data == null or enemy.data.is_flying:
		return
	if _blocked_enemies.has(enemy):
		return
	var cap: int = data.max_block_targets if data != null else 1
	if _blocked_enemies.size() >= cap:
		return
	# Engage gate — block claim only fires when the enemy is within the
	# hero's engage radius. attack_range can be much wider for ranged heroes;
	# this lets the mage shoot at 350 px while only locking enemies that
	# walk into face contact. Distant call sites still call _start_block
	# unconditionally (move_step, seek_target) — the gate makes them no-op
	# until _auto_engage_extras catches the enemy crossing into engage range.
	if not (enemy in engage_range_area.get_overlapping_areas()):
		return
	if enemy.engage_combat(self):
		_blocked_enemies.append(enemy)


# Effective block-claim radius. Reads HeroData.engage_radius; when unset (0),
# falls back to the smaller of attack_range and DEFAULT_ENGAGE_RADIUS so a
# narrow-reach hero never claims past its own swing.
func _effective_engage_radius() -> float:
	if data == null:
		return DEFAULT_ENGAGE_RADIUS
	var authored: float = float(data.engage_radius) if "engage_radius" in data else 0.0
	if authored > 0.0:
		return authored
	return minf(data.attack_range, DEFAULT_ENGAGE_RADIUS)


# Drop every blocker claim we hold. Called on state exits from COMBAT,
# player-commanded move, death, and respawn.
func _release_block() -> void:
	for e in _blocked_enemies:
		if e != null and is_instance_valid(e):
			e.release_combat(self)
	_blocked_enemies.clear()


# Drop a single blocker claim (used when one specific target dies / leaves
# range while the hero keeps blocking the rest).
func _release_block_of(enemy: Node) -> void:
	if enemy == null:
		return
	if is_instance_valid(enemy):
		enemy.release_combat(self)
	_blocked_enemies.erase(enemy)


# While engaged, sweep engage_range for extra enemies we could also be
# blocking — up to the hero's capacity. Runs every frame in _attack_step,
# which is cheap because Area2D overlap is O(n) in overlap size. Iterates
# engage_range_area (not attack_range) so ranged heroes don't claim distant
# enemies that haven't actually closed to face contact yet.
func _auto_engage_extras() -> void:
	var cap: int = data.max_block_targets if data != null else 1
	if _blocked_enemies.size() >= cap:
		return
	for a in engage_range_area.get_overlapping_areas():
		if not (a is BaseEnemy):
			continue
		var enemy: BaseEnemy = a
		if enemy.state == BaseEnemy.State.DYING or enemy.data == null or enemy.data.is_flying:
			continue
		if _blocked_enemies.has(enemy):
			continue
		_start_block(enemy)
		if _blocked_enemies.size() >= cap:
			return


# Release blocker slots on enemies that have died or walked outside the
# attack range. Keeps `_blocked_enemies` honest so enemies never stay
# frozen after the hero has drifted off them.
func _prune_blocks_out_of_range() -> void:
	if _blocked_enemies.is_empty():
		return
	var in_range: Array = attack_range_area.get_overlapping_areas()
	# Reverse iteration so in-place removal stays valid. Freed references
	# are stripped directly (can't round-trip through a typed Array[Node]);
	# valid-but-disengaging ones go through _release_block_of to notify the
	# enemy that it's no longer being blocked.
	for i in range(_blocked_enemies.size() - 1, -1, -1):
		var e: Node = _blocked_enemies[i]
		if e == null or not is_instance_valid(e):
			_blocked_enemies.remove_at(i)
			continue
		if e.state == BaseEnemy.State.DYING or not in_range.has(e):
			_release_block_of(e)


func _draw() -> void:
	var zs: float = _get_zoom_scale()
	# Move-order marker — expanding ring at the destination of the last
	# accepted move_to(). Drawn first so it sits under the skill preview /
	# selection ring / shadow / body.
	if _move_marker_t > 0.0:
		var local_target: Vector2 = to_local(_move_marker_pos)
		var t_inv: float = 1.0 - _move_marker_t  # 0 → 1 as the ring expands
		var radius: float = (MOVE_MARKER_BASE_RADIUS + MOVE_MARKER_EXPAND * t_inv) * zs
		var alpha: float = _move_marker_t * 0.85
		draw_arc(local_target, radius, 0.0, TAU, 24,
			Color(0.4, 1.0, 0.45, alpha), 2.0 * zs)
	# Skill targeting range circle (Phase 20) — drawn first.
	if _skill_range_preview > 0.0:
		draw_circle(Vector2.ZERO, _skill_range_preview, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, _skill_range_preview, 0.0, TAU, 48, Color(1.0, 0.9, 0.3, 0.85), 2.5 * zs)
	# Selection ring sits on the ground, drawn before the shadow so the
	# shadow can darken it slightly where they overlap.
	if is_selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(1.0, 0.95, 0.3, 0.85), 2.5 * zs)
	# Ground shadow under the hero — anchored, doesn't bob with the body.
	if data != null and data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		UnitVisualDrawer.draw_ground_shadow(self, data.visual)

	# Compose body offset + scale.
	var lunge_off: Vector2 = _lunge_offset()
	var body_offset: Vector2 = lunge_off
	var body_scale: Vector2 = Vector2.ONE
	var walk_rotation: float = 0.0
	if data != null and data.visual != null and state == State.MOVING:
		var anim: Dictionary = UnitVisualDrawer.compute_walk_anim(data.visual, _walk_t, _walk_phase)
		body_offset += anim.offset
		body_scale = anim.scale
		walk_rotation = anim.get("rotation", 0.0)
	if _flinch_t > 0.0:
		var fa: float = _flinch_t / FLINCH_DURATION
		body_offset += _flinch_dir * FLINCH_DISTANCE * fa
	if state == State.IDLE or state == State.COMBAT:
		var breath: float = sin(_breath_t * 2.5) * 0.025
		body_scale.x *= 1.0 + breath
		body_scale.y *= 1.0 - breath
	# Impact squash on attack commit — peaks around the strike frame
	# (lunge curve t01 ≈ 0.5). Reads as weight transfer at impact.
	if _lunge_t > 0.0:
		var lt: float = 1.0 - (_lunge_t / LUNGE_DURATION)
		if lt > 0.30 and lt < 0.65:
			var sq: float = sin((lt - 0.30) / 0.35 * PI) * 0.18
			body_scale.x *= 1.0 + sq
			body_scale.y *= 1.0 - sq
	# Cast pose — slight Y stretch so the hero "rears up" when channelling.
	if _cast_t > 0.0:
		var ct: float = 1.0 - (_cast_t / CAST_ANIM_DURATION)
		var pulse: float = sin(ct * PI) * 0.10
		body_scale.x *= 1.0 - pulse * 0.4
		body_scale.y *= 1.0 + pulse

	# Build ctx for the drawer.
	var ctx: Dictionary = {}
	if data != null and data.visual != null:
		ctx["face"] = _facing_dir
		if walk_rotation != 0.0:
			ctx["walk_rotation"] = walk_rotation
		var max_hp: int = _effective_max_health()
		if max_hp > 0 and float(current_health) / float(max_hp) < 0.30:
			ctx["low_hp"] = true
		# Attack wind-up + strike sweep — derived from the same lunge curve
		# so the held weapon follows the body offset through the swing.
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / LUNGE_DURATION)
			if t01 < 0.30:
				ctx["wind_t"] = clampf(t01 / 0.30, 0.0, 1.0)
			else:
				# Map [0.30, 0.95] of the lunge to [0, 1] of the strike arc
				# so the weapon sweeps overhead → through target → low.
				ctx["strike_t"] = clampf((t01 - 0.30) / 0.65, 0.0, 1.0)
				ctx["strike_dir"] = _lunge_dir
		# Cast pose — force arm raised and pointing at the cast direction.
		# Overrides any walk swing for the duration. Drops back to wind-up
		# control after _cast_t hits 0.
		if _cast_t > 0.0:
			var ct2: float = clampf(1.0 - (_cast_t / CAST_ANIM_DURATION), 0.0, 1.0)
			# Ramp to 1 in first half, hold, then ramp back so the arm
			# returns smoothly to rest after the pose ends.
			var raise_amount: float = sin(ct2 * PI) * 0.85 + 0.15
			ctx["wind_t"] = clampf(raise_amount, 0.0, 1.0)
			ctx["strike_dir"] = _cast_dir

	# Body draw.
	if data != null and data.visual != null:
		var walk_t_arg: float = _walk_t if state == State.MOVING else -1.0
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale, walk_t_arg, _walk_phase, ctx)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / LUNGE_DURATION)
			UnitVisualDrawer.draw_swing_arc_trail(self, data.visual, _lunge_dir, t01)
	else:
		# Legacy fallback: color varies by damage type.
		if body_offset != Vector2.ZERO:
			draw_set_transform(body_offset, 0.0, body_scale)
		var is_magic: bool = data != null and data.damage_type == 1
		var body_color: Color = Color(0.3, 0.4, 0.85) if is_magic else Color(0.85, 0.7, 0.2)
		var outline_color: Color = Color(0.1, 0.12, 0.3) if is_magic else Color(0.2, 0.15, 0.05)
		var accent_color: Color = Color(0.6, 0.7, 1.0) if is_magic else Color(0.9, 0.9, 0.95)
		draw_rect(Rect2(-25, -25, 50, 50), body_color)
		draw_rect(Rect2(-25, -25, 50, 50), outline_color, false, 4.0)
		draw_line(Vector2(0, -25), Vector2(0, -40), accent_color, 5.0)
		if body_offset != Vector2.ZERO:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar()


func _draw_health_bar() -> void:
	if data == null:
		return
	var max_hp: int = _effective_max_health()
	if max_hp <= 0:
		return
	if current_health >= max_hp:
		return
	var zs: float = _get_zoom_scale()
	var bar_size: Vector2 = HP_BAR_SIZE * zs
	# Head sits above the torso when race != NONE — bump the bar so it
	# clears the head + hat. minf picks the more-negative (higher) value.
	var bar_y_local: float = HP_BAR_Y_OFFSET
	if data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		var torso_r: float = data.visual.radius if data.visual.shape == UnitVisualData.Shape.CIRCLE else maxf(data.visual.body_size.x, data.visual.body_size.y) * 0.5
		var head_top: float = data.visual.head_y_offset * torso_r - data.visual.head_radius_ratio * torso_r
		bar_y_local = minf(HP_BAR_Y_OFFSET, head_top - 14.0)
	var bar_y: float = bar_y_local * zs
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-bar_size.x * 0.5, bar_y)
	draw_rect(Rect2(origin, bar_size), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(bar_size.x * pct, bar_size.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0), false, 1.0)
