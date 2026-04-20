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
const _FloatingTextScript := preload("res://vfx/FloatingText.gd")
var _ability_host: RefCounted = null

@onready var attack_range_area: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var seek_range_area: Area2D = $SeekRange
@onready var seek_range_shape: CollisionShape2D = $SeekRange/CollisionShape2D


func _ready() -> void:
	if data == null:
		push_warning("[BaseHero] missing HeroData")
		return
	# Phase 48 — persistent hero level/XP. GameState owns the dictionary;
	# BaseHero reads it on spawn and delegates gain_xp back. Level is read
	# BEFORE _seed_base_stats so the level-growth multiplier is correct.
	level = GameState.get_hero_level(data.hero_id)
	current_xp = GameState.get_hero_xp(data.hero_id)
	_seed_base_stats()
	recompute_stats()
	current_health = _effective_max_health()
	var atk_circle := CircleShape2D.new()
	atk_circle.radius = data.attack_range
	attack_range_shape.shape = atk_circle
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
	if "talents" in data and data.hero_id in GameState.hero_talents:
		var purchased_ids: Array = GameState.hero_talents[data.hero_id]
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
	base_stats["damage"] = data.attack_damage * dmg_mult * GameState.get_upgrade_multiplier(GameState.MOD_HERO_DAMAGE)
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
# class drives both hero skill buttons and (Phase 22) spell buttons.
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
	# Face the target for the lunge visual on melee single-target casts.
	if target is Node2D:
		_start_lunge(target.global_position)
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
	# Phase 48: delegate to GameState which owns the persistent dict + the
	# level-up math (+ xp multiplier + hero_leveled_up signal). Then mirror
	# the results back so combat code doesn't re-read GameState each frame.
	# GameState.add_hero_xp already emits hero_xp_gained and hero_leveled_up
	# signals itself — don't re-emit them here.
	var old_level: int = level
	var new_level: int = GameState.add_hero_xp(data.hero_id, amount)
	level = new_level
	current_xp = GameState.get_hero_xp(data.hero_id)
	while old_level < new_level:
		old_level += 1
		_level_up_apply()


func _level_up_apply() -> void:
	# Runtime side of a level-up. GameState already emitted hero_leveled_up
	# and bumped the persistent entry; this method updates the live hero:
	# re-seed base, recompute modifiers, heal to full.
	_seed_base_stats()
	recompute_stats()
	current_health = _effective_max_health()
	queue_redraw()
	print("[Hero] %s reached level %d" % [data.hero_name, level])


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
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		queue_redraw()
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
		queue_redraw()
	_tick_skill_cooldowns(delta)
	if _ability_host != null:
		_ability_host.tick(delta)
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			_seek_target()
		State.MOVING:
			_move_step(delta)
		State.COMBAT:
			velocity = Vector2.ZERO
			_attack_step(delta)
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
		EventBus.hit_landed.emit(self, source, final, type)
		var parent: Node = get_tree().current_scene
		if parent != null:
			_FloatingTextScript.spawn(parent, str(int(ceil(final))), Color(1.0, 0.2, 0.2), global_position + Vector2(0, -60), 36)
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()


func _die() -> void:
	change_state(State.DEAD)
	velocity = Vector2.ZERO
	visible = false
	set_selected(false)
	_release_block()
	_target_enemy = null
	_seek_target_enemy = null
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.hero_died.emit()
	# Schedule respawn. HeroData.respawn_time (default 30s). Timer honors
	# the paused SceneTree (process_always defaults to false), so tactical
	# pause freezes the countdown — fair to the player.
	var wait: float = data.respawn_time if data != null and data.respawn_time > 0.0 else 30.0
	get_tree().create_timer(wait).timeout.connect(_respawn)


func _respawn() -> void:
	# Scene may have been reloaded (restart) while the timer was running.
	if not is_instance_valid(self) or data == null:
		return
	# Teleport back to the level's HeroSpawn marker (falls back if absent).
	var scene: Node = get_tree().current_scene
	var spawn_pos: Vector2 = global_position
	if scene != null:
		var lvl: Node = scene.get_node_or_null("Level1")
		if lvl != null and lvl.has_method("get_hero_spawn_position"):
			spawn_pos = lvl.get_hero_spawn_position()
	global_position = spawn_pos
	_rally_position = spawn_pos
	current_health = _effective_max_health()
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
	if enemy.engage_combat(self):
		_blocked_enemies.append(enemy)


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


# While engaged, sweep attack_range for extra enemies we could also be
# blocking — up to the hero's capacity. Runs every frame in _attack_step,
# which is cheap because Area2D overlap is O(n) in overlap size.
func _auto_engage_extras() -> void:
	var cap: int = data.max_block_targets if data != null else 1
	if _blocked_enemies.size() >= cap:
		return
	for a in attack_range_area.get_overlapping_areas():
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
	# Skill targeting range circle (Phase 20) — drawn first so the body
	# and selection ring sit on top of the faint fill.
	var zs: float = _get_zoom_scale()
	if _skill_range_preview > 0.0:
		draw_circle(Vector2.ZERO, _skill_range_preview, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, _skill_range_preview, 0.0, TAU, 48, Color(1.0, 0.9, 0.3, 0.85), 2.5 * zs)
	# Selection ring sits on the ground (no lunge) so it reads as a marker
	# under the unit, not as part of the body. Drawn first so the body
	# covers the inside of the ring.
	if is_selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(1.0, 0.95, 0.3, 0.85), 2.5 * zs)
	# Body + accent translated by the lunge offset.
	var off: Vector2 = _lunge_offset()
	if data != null and data.visual != null:
		UnitVisualDrawer.draw_unit(self, data.visual, off)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, off)
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / LUNGE_DURATION)
			UnitVisualDrawer.draw_swing_arc_trail(self, data.visual, _lunge_dir, t01)
	else:
		# Legacy fallback: color varies by damage type.
		if off != Vector2.ZERO:
			draw_set_transform(off, 0.0, Vector2.ONE)
		var is_magic: bool = data != null and data.damage_type == 1
		var body_color: Color = Color(0.3, 0.4, 0.85) if is_magic else Color(0.85, 0.7, 0.2)
		var outline_color: Color = Color(0.1, 0.12, 0.3) if is_magic else Color(0.2, 0.15, 0.05)
		var accent_color: Color = Color(0.6, 0.7, 1.0) if is_magic else Color(0.9, 0.9, 0.95)
		draw_rect(Rect2(-25, -25, 50, 50), body_color)
		draw_rect(Rect2(-25, -25, 50, 50), outline_color, false, 4.0)
		draw_line(Vector2(0, -25), Vector2(0, -40), accent_color, 5.0)
		if off != Vector2.ZERO:
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
	var bar_y: float = HP_BAR_Y_OFFSET * zs
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-bar_size.x * 0.5, bar_y)
	draw_rect(Rect2(origin, bar_size), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(bar_size.x * pct, bar_size.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0), false, 1.0)
