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
# Combat Blocking Doctrine — Hero on the Path. Spawn / respawn positions
# auto-snap to the nearest level Path2D within this slack so the hero
# stands on the road regardless of HeroSpawn marker placement. Player
# tap-to-move uses a tighter slack (TAP_SNAP_SLACK) so deliberate off-path
# tactical placement is still respected.
const SPAWN_SNAP_SLACK: float = 80.0
const TAP_SNAP_SLACK: float = 40.0
# Detection zone — circle of this radius around the hero's anchor
# (_rally_position). When an enemy enters the zone, hero leaves the anchor,
# walks to the engage spot (approach phase = State.MOVING), aligns Y with
# the enemy, then starts the duel. Authored per hero via
# HeroData.detection_radius_px; single default below when authored=0.
# Unified across archetypes — there is one melee pipeline; the only per-hero
# difference is THIS range (big for the Warrior, small for casters). See
# COMBAT_BLOCKING_DOCTRINE.md.
const DEFAULT_MELEE_ENGAGE_RANGE: float = 160.0
# How close the hero must be to the engage spot before the swing starts.
# Below this, hero is "in position" → State.COMBAT. Above, hero keeps walking.
const ENGAGE_ARRIVAL_TOLERANCE: float = 18.0
# Combat Blocking Doctrine — how far (px of path progress) past the anchor
# an enemy may be and still get engaged. Lets the hero finish a near-leaker
# right at the line (small grace); beyond it the enemy has "won" the
# position and is left to the towers. Also acts as chase/return hysteresis:
# once an enemy is this far past, it's dropped and won't re-acquire.
const GUARD_BACK_MARGIN_PX: float = 50.0
# Acquire-side leak margin (hysteresis). The hero only *starts* an approach
# on an enemy still at/before the anchor (0 = no grace); once committed it
# may follow through up to GUARD_BACK_MARGIN_PX. Asymmetric so the hero
# never lurches toward an enemy that's about to leak. Tunable: a small
# positive value lets it grab something right at its feet.
const GUARD_ACQUIRE_MARGIN_PX: float = 0.0
# Safety shrink so the melee engage spot always lands INSIDE the hero's
# block circle (_effective_engage_radius). Without this, a short-reach
# melee hero would walk to a spot outside its own engage radius and
# _start_block would perpetually no-op.
const ENGAGE_GAP_SAFETY: float = 6.0

# Default block-claim radius when HeroData.engage_radius is unset (0).
# Clamped down by attack_range so a tiny-reach hero doesn't claim blocks
# past its own swing. See HeroData.engage_radius for the rationale.
const DEFAULT_ENGAGE_RADIUS: float = 60.0
# Combat Ground Line — approach steering bias. While walking in to a melee
# engage spot, the vertical (lane) gap must close at least as fast as the
# horizontal one (|dir.y| ≥ |dir.x| × 1/this until aligned) so the blocker
# reaches the enemy's Y *during* the walk-in instead of snapping to it in a
# fast end-of-approach burst when COMBAT triggers early off-Y. 1.0 = Y closes
# no slower than X (smooth 45°-max diagonal onto the lane, then straight in).
# Higher = even more Y-priority. See docs/COMBAT_BLOCKING_DOCTRINE.md.
const APPROACH_Y_PRIORITY: float = 1.0
# Below this |Δy| the lane is considered matched — no Y bias applied.
const Y_ALIGN_EPS: float = 2.0
# Hero will not chase enemies that are farther than this from its current
# rally point. The rally point is the HeroSpawn marker at start and updates
# to the tap position on every player-issued move command.
const LEASH_RADIUS: float = 400.0
# Stop returning to the rally point once within this distance of it.
const LEASH_RETURN_TOLERANCE: float = 20.0
const COMBAT_DEBUG_FONT_SIZE: int = 12

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
# Assist-in-lull: true while approaching/finishing a lone straggler
# acquired via the combat lull (outside the normal detection zone).
# Lowest-priority — a normal in-zone target, a player move order, or the
# lull ending all preempt it. See docs/COMBAT_BLOCKING_DOCTRINE.md.
const ASSIST_MAX_DIST: float = 1100.0
var _assisting: bool = false
var _in_lull: bool = false
# Auto-seek: enemy the hero is walking toward (not yet in attack range).
var _seek_target_enemy: Node = null
var _nav_repath_timer: float = 0.0
# Combat Blocking Doctrine — stop-on-claim. The hero reserves the enemy it
# has committed to (approach target, or COMBAT focus) so it halts and waits
# while the hero walks over. _sync_claim() reconciles this every frame from
# the current target; _claim_age drops a claim that never reaches contact
# (pathing failure) so an enemy can't be frozen forever.
var _claimed_enemy: Node = null
var _claim_age: float = 0.0
const CLAIM_TIMEOUT: float = 4.0
# Stuck-recovery: enemies the soft claim timed out on (never reached contact).
# Skipped by the MELEE pickers for GIVEUP_COOLDOWN so the hero acquires a
# DIFFERENT enemy instead of re-failing on the same one every CLAIM_TIMEOUT
# (the "stuck between two enemies" livelock). Keyed by enemy instance →
# Time.get_ticks_msec() expiry. Ranged shooting is unaffected.
const GIVEUP_COOLDOWN_MS: int = 2500
var _giveup_until: Dictionary = {}

var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_t: float = 0.0
# Swing duration captured at strike start so the normalization stays stable
# even if attack_speed changes mid-swing. Cadence-scaled (see swing_duration).
var _lunge_dur: float = LUNGE_DURATION
var _lunge_visual: String = "melee"
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
# Pre-cast wind-up — when a skill is cast, the projectile / VFX spawn is
# deferred by this many seconds so the staff orb gets to charge first.
# Cooldown commits immediately on initiation; only the apply() call is
# deferred. UI validates target shape upfront, so deferred apply rarely
# no-ops on invalid input.
const CAST_WIND_DURATION: float = 0.15
var _cast_wind_t: float = 0.0
var _pending_skill_idx: int = -1
var _pending_skill_target = null
# Idle breathing — small Y squish pulse while IDLE / COMBAT so a stationary
# hero doesn't read as frozen.
var _breath_t: float = 0.0
# Facing direction for direction-aware eyes. Updated from velocity when the
# hero moves, falls back to the active target / lunge direction otherwise.
var _facing_dir: Vector2 = Vector2.RIGHT
# Smoothed facing that the drawer reads. Eases toward `_facing_dir` over
# ~0.15s so direction changes animate (body pivots through the turn)
# instead of snapping in a single frame. Premium drawers (NECROMANCER)
# use this for hood / robe / cape / staff-side pose.
var _face_dir_smoothed: Vector2 = Vector2.RIGHT
var _cape_lag_x: float = 0.0
# Phase 3 — spring (not linear lerp) easing for face + cape so turns and
# stops overshoot slightly and settle, instead of gliding in robotically.
# Velocity state lives here on the host; the drawer stays stateless.
var _face_vel: Vector2 = Vector2.ZERO
var _cape_lag_vel: float = 0.0
# Slightly under-damped (zeta ≈ 0.9) — crisp with a hint of overshoot.
const FACE_SPRING_K: float = 180.0
const FACE_SPRING_D: float = 24.0
# Softer + whippier (zeta ≈ 0.63) — the cape trails and rebounds more.
const CAPE_SPRING_K: float = 90.0
const CAPE_SPRING_D: float = 12.0


# Semi-implicit (symplectic) damped-spring step. Returns
# Vector2(new_value, new_velocity). Stable for k·dt² ≪ 1 at 60 Hz.
static func _spring1(cur: float, vel: float, target: float, k: float, d: float, dt: float) -> Vector2:
	var accel: float = k * (target - cur) - d * vel
	var nv: float = vel + accel * dt
	return Vector2(cur + nv * dt, nv)
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

# Phase 49 — fractional regen accumulator. health_regen is rolled in HP/sec
# (typically 1..3); _physics_process accumulates rate*delta and heals an int
# step whenever the accumulator crosses 1.0. Fractional remainder rolls over
# so a 0.7/sec roll still heals 1 HP every ~1.4s, not zero.
var _health_regen_accum: float = 0.0
# Phase 3R-followup — out-of-combat gate for regen. take_damage() resets to 0;
# _tick_health_regen accumulates delta and only heals once this exceeds the
# threshold. Prevents melee heroes from out-regenerating sustained damage,
# which was making them feel too strong vs the design intent of "kite a
# little to recover, soak hits if you have armor."
const REGEN_OUT_OF_COMBAT_DELAY: float = 3.0
var _seconds_since_damage: float = 999.0

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
const _HeroSkillNodeDataScript := preload("res://heroes/HeroSkillNodeData.gd")
const _MuzzleFlashScript := preload("res://vfx/MuzzleFlashVFX.gd")
const _GuardZoneScript := preload("res://systems/GuardZone.gd")
# Phase 3R-followup-3 — debug-only slider overrides. is_active() short-circuits
# in release builds, so the multiplications below are identity at zero cost.
const _BalanceOverrides := preload("res://balance/debug/BalanceOverrides.gd")
var _ability_host: RefCounted = null
# Phase 1 — abilities currently granted by satisfied HeroItemAffinityData.
# Tracked so _resolve_affinities() can detach stale grants and re-attach
# cleanly (idempotent re-entrant resolve).
var _affinity_abilities: Array = []
# Phase 3 — active WeaponProfileAbility (Pure-B). null ⇒ unarmed: every
# _profile_* helper falls back to HeroData (byte-identical default).
var _weapon_profile = null
var _death_tween: Tween = null

# Melee-combat debug — why the nearest enemy was NOT acquired by
# _pick_target_in_detection_zone this frame. Populated read-only by
# _dbg_scan_rejections() and surfaced in _draw_combat_debug (debug builds
# only). Answers "the enemy is right next to the hero, why won't it fight".
var _dbg_reject_enemy: Node = null
var _dbg_reject: String = ""

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
	atk_circle.radius = get_effective_attack_range()
	attack_range_shape.shape = atk_circle
	# EngageRange — block-claim radius (see _effective_engage_radius). Decoupled
	# from attack_range so ranged heroes attack at distance without locking
	# every enemy at the edge of their projectile reach.
	var engage_circle := CircleShape2D.new()
	engage_circle.radius = _effective_engage_radius()
	engage_range_shape.shape = engage_circle
	# SeekRange — hero auto-walks toward enemies in this larger radius.
	var seek_circle := CircleShape2D.new()
	seek_circle.radius = get_effective_attack_range() * SEEK_RANGE_MULTIPLIER
	seek_range_shape.shape = seek_circle
	_skill_cooldowns.resize(data.skills.size())
	_skill_cooldowns.fill(0.0)
	_ability_host = _AbilityHostScript.new(self)
	if "abilities" in data:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	# Phase 1 — push every PASSIVE_RANK node ability for each equipped passive.
	# Cumulative tree: if the player owns R1 + R2 of a passive, both abilities
	# stack on the host. Each ability is duplicate()d so per-hero state (e.g.
	# RegenAbility's tick timer) is isolated.
	#
	# Legacy talents (Phase 40) are auto-migrated to skill-tree nodes by
	# SaveManager._migrate_v4_to_v5 on first v5 load, so MetaProgression.
	# hero_talents is empty in steady state — no need to read it here.
	_apply_equipped_passives()
	# Phase 48: push equipped items' abilities through AbilityHost.equip_ability
	# so ON_EQUIP fires, StatModifierAbility joins the modifier stack, and
	# recompute_stats rebuilds current_stats with item contributions.
	for inst in InventoryManager.get_all_equipped(data.hero_id):
		if inst == null:
			continue
		for ab in inst.build_runtime_abilities(ContentRegistry):
			_ability_host.equip_ability(ab)
	# Phase 1 — grant weapon-family affinity bonuses for the equipped item set.
	_resolve_affinities()
	# Re-seed current_health AFTER items so spawns start at full (item-boosted) HP.
	current_health = _effective_max_health()
	# Seed the rally point from the spawn position, snapped to the nearest
	# Path2D within SPAWN_SNAP_SLACK so the hero stands on the road regardless
	# of the HeroSpawn marker's exact placement (Combat Blocking Doctrine —
	# "Hero on the path"). Player can reseat by tapping to move.
	_rally_position = _snap_to_ground_line(global_position, SPAWN_SNAP_SLACK)
	global_position = _rally_position
	_walk_phase = randf() * TAU
	_prev_pos = global_position
	# Listen for confirmed taps from GameCamera's gesture classifier.
	EventBus.map_tap_confirmed.connect(_on_map_tap)
	if not EventBus.combat_lull_changed.is_connected(_on_combat_lull_changed):
		EventBus.combat_lull_changed.connect(_on_combat_lull_changed)
	# Deferred so sibling nodes (HUD, Main) have finished _ready() and
	# connected to hero_spawned before we fire it. Without this, Main.tscn
	# sibling-order has HUD readying AFTER the hero, so the initial Lv/XP
	# payload never reaches the HUD label.
	EventBus.hero_spawned.emit.call_deferred(self)


func _seed_base_stats() -> void:
	# Called on ready and whenever a permanent base value changes (level-up,
	# permanent upgrade purchase). Delegates to compute_base_stats so the
	# dressing-room preview (EquipmentScreen) and the runtime hero compute
	# the same numbers from the same code.
	if data == null:
		base_stats.clear()
		return
	base_stats = compute_base_stats(data, level)


func _apply_equipped_passives() -> void:
	# Phase 1 — walk the hero's skill tree, for each equipped passive_id push
	# the abilities of every PASSIVE_RANK node whose rank has been purchased.
	# Cumulative: R1 + R2 owned + R3 not owned → push R1's ability + R2's
	# ability, skip R3. Each ability is duplicated so two heroes equipping
	# the same passive don't share mutable per-instance state.
	if _ability_host == null or data == null:
		return
	if not has_node("/root/ContentRegistry"):
		return
	var tree: Resource = ContentRegistry.find_skill_tree(data.hero_id)
	if tree == null:
		return
	var equipped: Array[String] = LoadoutState.get_equipped_passives(data.hero_id)
	for passive_id in equipped:
		if passive_id == "":
			continue
		var purchased_rank: int = MetaProgression.get_purchased_passive_rank(data.hero_id, passive_id)
		if purchased_rank <= 0:
			continue
		for node in tree.nodes_for_target(passive_id):
			if node == null or not ("kind" in node):
				continue
			if int(node.kind) != _HeroSkillNodeDataScript.Kind.PASSIVE_RANK:
				continue
			if int(node.rank) > purchased_rank:
				continue
			if node.ability == null:
				continue
			_ability_host.add_ability(node.ability.duplicate())
	# Phase 3K — CAPSTONES are always-on once purchased, no equip slot needed.
	# Walk the tree, push every CAPSTONE node whose rank is purchased.
	for node in tree.nodes:
		if node == null or not ("kind" in node):
			continue
		if int(node.kind) != _HeroSkillNodeDataScript.Kind.CAPSTONE:
			continue
		if MetaProgression.get_purchased_rank(data.hero_id, String(node.node_id)) < int(node.rank):
			continue
		if node.ability == null:
			continue
		_ability_host.add_ability(node.ability.duplicate())


func _resize_range_shapes() -> void:
	# Push current_stats range values back onto the Area2D collision shapes.
	# Without this, an item with attack_range_pct lifts the number reported
	# by get_stats_line() but the AttackRange / SeekRange / EngageRange Area2D
	# radii stay at the L1 baked size — the stats card lies. Called whenever
	# the modifier stack changes (equip / unequip / level-up).
	var atk_range: float = get_effective_attack_range()
	if attack_range_shape != null and attack_range_shape.shape is CircleShape2D:
		(attack_range_shape.shape as CircleShape2D).radius = atk_range
	if seek_range_shape != null and seek_range_shape.shape is CircleShape2D:
		(seek_range_shape.shape as CircleShape2D).radius = atk_range * SEEK_RANGE_MULTIPLIER
	if engage_range_shape != null and engage_range_shape.shape is CircleShape2D:
		(engage_range_shape.shape as CircleShape2D).radius = get_effective_engage_radius()


func register_modifier_source(m) -> void:
	if m == null or _modifier_sources.has(m):
		return
	_modifier_sources.append(m)


func unregister_modifier_source(m) -> void:
	_modifier_sources.erase(m)


func _refresh_health_after_modifier_change() -> void:
	# Max HP went up or down — clamp current_health so equipping a +HP item
	# doesn't auto-heal and unequipping one doesn't leave health above max.
	# Also resize the Area2D radii so range/engage modifiers actually move
	# the physical reach circles, not just the stats card.
	if data == null:
		return
	var max_hp: int = _effective_max_health()
	if current_health > max_hp:
		current_health = max_hp
	_resize_range_shapes()


func recompute_stats() -> void:
	# Rebuild current_stats from base + modifier stack. Order is fixed so the
	# same modifier set always yields the same current value: additive flats
	# apply first, then multiplicative pcts as a product of (1 + pct).
	current_stats = apply_modifiers(base_stats, _modifier_sources)


# Phase 3 — WeaponProfileAbility lifecycle (mirrors register_modifier_source).
# LAST-WINS: only the WEAPON slot equips a profile-carrying item at a time so
# this is moot in practice; documented deterministic for the edge case of a
# non-weapon item authoring one.
func set_weapon_profile(p) -> void:
	_weapon_profile = p
	# Weapon owns reach — push the (possibly new) range onto the Area2D
	# shapes. _resize_range_shapes is null-safe so this is safe even when
	# called from the _ready() equip loop before nodes settle.
	_resize_range_shapes()


func clear_weapon_profile(p) -> void:
	# Identity-checked so a stale ability's ON_UNEQUIP can't wipe a profile
	# that a newer equip already replaced.
	if _weapon_profile == p:
		_weapon_profile = null
		_resize_range_shapes()


func get_weapon_profile():
	return _weapon_profile


# ── Profile fallback helpers ────────────────────────────────────────────
# Each returns the weapon's value when a profile is active and that facet is
# set, else the HeroData value (today's literal). With no profile every one
# is byte-identical to the pre-Phase-3 expression.

func _profile_uses_projectile() -> bool:
	if _weapon_profile != null:
		return _weapon_profile.projectile_scene != null
	return data != null and data.projectile_scene != null


func _profile_projectile_scene() -> PackedScene:
	if _weapon_profile != null and _weapon_profile.projectile_scene != null:
		return _weapon_profile.projectile_scene
	return data.projectile_scene if data != null else null


func _profile_damage_type() -> int:
	if _weapon_profile != null and _weapon_profile.weapon_damage_type >= 0:
		return _weapon_profile.weapon_damage_type
	return data.damage_type if data != null else 0


# Base-replace damage: apply the StatModifier affix stack as a RATIO over the
# hero's authored base so item +damage% is counted exactly once (mirrors the
# proven close-combat ratio). weapon_base_damage <= 0 ⇒ keep hero base ⇒
# returns _effective_damage() unchanged (byte-identical).
# CONTRACT: damage CARRIES affixes (this ratio) — deliberately UNLIKE
# weapon range/speed which are absolute overrides. See WeaponProfileAbility.gd.
func _profile_damage() -> float:
	if _weapon_profile == null or _weapon_profile.weapon_base_damage <= 0.0:
		return _effective_damage()
	var hero_base: float = maxf(0.01, data.attack_damage) if data != null else 0.01
	var mult: float = _effective_damage() / hero_base
	return _weapon_profile.weapon_base_damage * mult


func _profile_close_damage() -> float:
	if _weapon_profile != null and _weapon_profile.close_attack_damage > 0.0:
		return _weapon_profile.close_attack_damage
	return data.close_attack_damage if data != null else 0.0


func _profile_close_speed() -> float:
	if _weapon_profile != null and _weapon_profile.close_attack_speed > 0.0:
		return _weapon_profile.close_attack_speed
	return data.close_attack_speed if data != null else 0.0


func _profile_close_damage_type() -> int:
	if _weapon_profile != null and _weapon_profile.close_attack_damage > 0.0:
		return _weapon_profile.close_attack_damage_type
	return data.close_attack_damage_type if data != null else -1


# Phase 4 — body-profile targeting bias. Added to an enemy's claim count in
# the existing pickers' comparator so a de-prioritized class loses ties but
# is still selectable when alone (bias < the 1<<30 "no candidate" sentinel).
# NEAREST (default / DEFAULT_HUMANOID) ⇒ always 0 ⇒ byte-identical order.
# Pure comparator tweak: does NOT touch is_engageable_ground() or the
# targets_flying gate (Blocker invariants #1, #2 preserved verbatim).
const _TARGETING_DEPRIORITIZE: int = 1 << 20

func _targeting_bias(enemy) -> int:
	if data == null:
		return 0
	var tp: int = data.get_body_profile().targeting_priority
	if tp == HeroBodyProfile.TargetingPriority.NEAREST:
		return 0
	if enemy == null or not (enemy is BaseEnemy) or enemy.data == null:
		return 0
	var flying: bool = enemy.data.is_flying
	if tp == HeroBodyProfile.TargetingPriority.GROUND_FIRST and flying:
		return _TARGETING_DEPRIORITIZE
	if tp == HeroBodyProfile.TargetingPriority.AIR_FIRST and not flying:
		return _TARGETING_DEPRIORITIZE
	return 0


# Phase 2 — hero affinity rank: pure function of hero level via the level
# curve. Unauthored curve ⇒ rank 1 at every level (rank-1 affinities
# always-on, higher ranks dormant — byte-identical to Phase 1 default).
func _affinity_rank() -> int:
	if data == null or not data.has_method("get_level_curve"):
		return 1
	return data.get_level_curve().affinity_rank_for_level(level)


# Phase 1 — grant/revoke HeroItemAffinityData bonus abilities for the current
# equipped item set. Called ONCE from _ready() (line ~361). That is correct
# and sufficient because gear is locked at level spawn — there is no mid-run
# equip. The idempotent re-entrant design (fully detach then re-attach) is
# forward-looking insurance for a future mid-level gear-swap, not a current
# code path. With no item_affinities authored this is a no-op (byte-
# identical). Owner-agnostic per CORE RULE 11 — the
# attached abilities are plain AbilityData duplicated so the shared authored
# resource is never mutated (mirrors equipped-passive / item-ability pattern).
func _resolve_affinities() -> void:
	if _ability_host == null or data == null:
		return
	# Detach previous affinity grants first (re-entrant safety).
	for ab in _affinity_abilities:
		_ability_host.unequip_ability(ab)
	_affinity_abilities.clear()
	var affinities: Array = data.item_affinities if "item_affinities" in data else []
	if affinities.is_empty():
		return
	# Union of item_tags across every equipped instance (shared static helper
	# — compute_stats_for uses the SAME one so display == runtime, R1).
	var tag_set: Dictionary = _collect_equipped_item_tags(InventoryManager.get_all_equipped(data.hero_id))
	for ability in _affinities_to_grant(affinities, tag_set, _affinity_rank()):
		var dup: Resource = ability.duplicate(true)
		_ability_host.equip_ability(dup)
		_affinity_abilities.append(dup)


# Pure matcher (no scene / no autoload deps) so the affinity-grant contract is
# unit-testable without spawning a hero. Returns the flat list of authored
# bonus AbilityData whose owning affinity is satisfied: rank met AND every
# required tag present in tag_set. Empty required tags never qualify (an
# always-on affinity would be a stat item, not an affinity).
static func _affinities_to_grant(affinities: Array, tag_set: Dictionary, rank: int) -> Array:
	var out: Array = []
	for aff in affinities:
		if aff == null or not ("required_item_tags" in aff):
			continue
		if rank < int(aff.min_affinity_rank):
			continue
		var required: Array = aff.required_item_tags
		if required.is_empty():
			continue
		var satisfied: bool = true
		for t in required:
			if not tag_set.has(t):
				satisfied = false
				break
		if not satisfied:
			continue
		for ability in aff.bonus_abilities:
			if ability != null:
				out.append(ability)
	return out


# Union of item_tags across an equipped ItemInstance array. Shared by the
# runtime (_resolve_affinities) and the display path (compute_stats_for) so
# affinity resolution is single-source — display can never disagree with the
# live hero (R1, Preventive Bug Rule 1). Resolves bases via ContentRegistry.
static func _collect_equipped_item_tags(equipped: Array) -> Dictionary:
	var tag_set: Dictionary = {}
	for inst in equipped:
		if inst == null:
			continue
		var base: Resource = ContentRegistry.find_item_base(inst.base_id)
		if base == null or not ("item_tags" in base):
			continue
		for t in base.item_tags:
			tag_set[t] = true
	return tag_set


# ---------------------------------------------------------------------------
# Pure stat math — usable from a static context so EquipmentScreen and any
# future dressing-room UI can preview "what stats WOULD be" without spawning
# a BaseHero instance. The runtime _seed_base_stats / recompute_stats above
# both delegate here so there is exactly one definition of the math.
# ---------------------------------------------------------------------------

static func compute_base_stats(hero_data: HeroData, level_arg: int) -> Dictionary:
	# HeroData + level → permanent base values (per-level growth + account-
	# wide upgrade multipliers baked in). No modifier stack here.
	if hero_data == null:
		return {}
	# Phase 2 — growth rates come from the hero's level curve. Unauthored
	# curve returns the same constants below (byte-identical). The consts are
	# retained as the documented default source (HeroLevelCurveData defaults
	# mirror them).
	var _lc: HeroLevelCurveData = hero_data.get_level_curve()
	var hp_mult: float = 1.0 + float(level_arg - 1) * _lc.health_pct_per_level
	var dmg_mult: float = 1.0 + float(level_arg - 1) * _lc.damage_pct_per_level
	# Phase 3R-followup-3 — debug slider overrides. Identity in release builds
	# (BalanceOverrides.get_hero_mult returns 1.0 / 0.0 when is_active is false).
	var hid: String = String(hero_data.hero_id)
	var bo_hp: float = _BalanceOverrides.get_hero_mult(hid, "hp_mult")
	var bo_dmg: float = _BalanceOverrides.get_hero_mult(hid, "damage_mult")
	var bo_rng: float = _BalanceOverrides.get_hero_mult(hid, "range_mult")
	var bo_spd: float = _BalanceOverrides.get_hero_mult(hid, "speed_mult")
	var bo_atk_spd: float = _BalanceOverrides.get_hero_mult(hid, "attack_speed_mult")
	var bo_armor: float = _BalanceOverrides.get_hero_mult(hid, "armor_add")
	var bo_mag: float = _BalanceOverrides.get_hero_mult(hid, "mag_res_add")
	var bo_eng: float = _BalanceOverrides.get_hero_mult(hid, "engage_range_mult")
	# Unified melee-engage range — the single per-hero distance at which ANY
	# hero commits to the shared melee pipeline. Authored on
	# HeroData.detection_radius_px (0 = derive a default at runtime). Carried
	# through the stat dict so the dev balance UI (engage_range_mult) + bake
	# apply, exactly like attack_range. See COMBAT_BLOCKING_DOCTRINE.md.
	var raw_eng: float = 0.0
	if "detection_radius_px" in hero_data:
		raw_eng = float(hero_data.detection_radius_px)
	return {
		"max_health": float(hero_data.max_health) * hp_mult * bo_hp,
		"damage": hero_data.attack_damage * dmg_mult * MetaProgression.get_upgrade_multiplier(MetaProgression.MOD_HERO_DAMAGE) * bo_dmg,
		"armor": clampf(hero_data.armor + bo_armor, 0.0, 0.95),
		"magic_resist": clampf(hero_data.magic_resist + bo_mag, 0.0, 0.95),
		"attack_speed": hero_data.attack_speed * bo_atk_spd,
		"move_speed": hero_data.move_speed * bo_spd,
		"attack_range": hero_data.attack_range * bo_rng,
		"melee_engage_range": raw_eng * bo_eng,
		"xp_gain_mult": 1.0,
		"skill_power": 1.0,
		# Phase 49 — additive stats. Reflective apply_modifiers() picks up
		# `<key>_flat` from each modifier source. Default 0.0 so unequipped
		# heroes regen nothing and have no CDR.
		"health_regen": 0.0,
		"cooldown_reduction": 0.0,
	}


static func apply_modifiers(base: Dictionary, modifier_sources: Array) -> Dictionary:
	# base stats + ordered modifier sources → derived stats.
	# Each source exposes optional `<key>_flat` / `<key>_pct` fields; reflection
	# auto-discovers them. Adding a new stat key in compute_base_stats and a
	# matching field on StatModifierAbility wires modifier paths up with no
	# changes here.
	var current: Dictionary = {}
	for key in base.keys():
		var flat_field: String = "%s_flat" % key
		var pct_field: String = "%s_pct" % key
		var v: float = float(base[key])
		var pct_product: float = 1.0
		for m in modifier_sources:
			if m == null:
				continue
			if flat_field in m:
				v += float(m.get(flat_field))
			if pct_field in m:
				pct_product *= 1.0 + float(m.get(pct_field))
		current[key] = v * pct_product
	return current


static func compute_stats_for(hero_data: HeroData, level_arg: int, equipped: Array) -> Dictionary:
	# Dressing-room preview convenience: build full live stats from hero_data
	# + level + equipped item instances. EquipmentScreen calls this; the
	# runtime hero uses the two-step seed/recompute path above instead.
	var base: Dictionary = compute_base_stats(hero_data, level_arg)
	var mods: Array = []
	var wprof = null  # last WeaponProfileAbility among equipped (LAST-WINS)
	for inst in equipped:
		if inst == null:
			continue
		for ab in inst.build_runtime_abilities(ContentRegistry):
			if ab == null:
				continue
			mods.append(ab)
			if ab is WeaponProfileAbility:
				wprof = ab
	# Phase 6 / R1 — affinities contribute to DISPLAY too, via the SAME two
	# static helpers the live hero's _resolve_affinities uses. Display ==
	# runtime by construction (Preventive Bug Rule 1). Empty affinities or
	# unsatisfied tags ⇒ no extra mods ⇒ value-identical (backward compat).
	if hero_data != null:
		var affs: Array = hero_data.item_affinities if "item_affinities" in hero_data else []
		if not affs.is_empty():
			var tag_set: Dictionary = _collect_equipped_item_tags(equipped)
			var rank: int = hero_data.get_level_curve().affinity_rank_for_level(level_arg)
			for ab in _affinities_to_grant(affs, tag_set, rank):
				if ab != null:
					mods.append(ab)
	var current: Dictionary = apply_modifiers(base, mods)
	# Phase 3 — weapon owns the attack profile for DISPLAY too (Preventive
	# Bug Rule 1: the dressing room must not lie). Mirror the runtime
	# get_effective_* fallback rules. No weapon ⇒ values unchanged. NOTE:
	# the two keys below are now always present (shape-additive); this is
	# value-identical, not byte-identical at the dict-shape level — benign,
	# every reader uses .get() with a default, none compares dict keys.
	current["damage_type"] = int(hero_data.damage_type) if hero_data != null else 0
	current["uses_projectile"] = hero_data != null and hero_data.projectile_scene != null
	if wprof != null:
		if wprof.weapon_attack_range > 0.0:
			current["attack_range"] = wprof.weapon_attack_range
		if wprof.weapon_attack_speed > 0.0:
			current["attack_speed"] = wprof.weapon_attack_speed
		if wprof.weapon_base_damage > 0.0:
			var hbase: float = maxf(0.01, float(hero_data.attack_damage))
			current["damage"] = wprof.weapon_base_damage * (float(current.get("damage", 0.0)) / hbase)
		if wprof.weapon_damage_type >= 0:
			current["damage_type"] = wprof.weapon_damage_type
		current["uses_projectile"] = wprof.projectile_scene != null
	# Derived DPS — kept here so dressing-room and any future "build summary"
	# preview share the same definition of "DPS".
	current["dps"] = float(current.get("damage", 0.0)) * float(current.get("attack_speed", 0.0))
	return current


func _effective_max_health() -> int:
	if data == null:
		return 0
	var v: float = float(current_stats.get("max_health", float(data.max_health)))
	return int(ceil(v))


func _effective_damage() -> float:
	if data == null:
		return 0.0
	return float(current_stats.get("damage", data.attack_damage))


# Combat Blocking Doctrine — ranged-hero close combat. A ranged hero
# (projectile_scene set) swaps to an authored melee poke when a blockable
# ground target is at face-contact range. It does not have to be hard-blocked
# yet; the close visual/attack mode is separate from the enemy stop lock.
# Opt-in: heroes with close_attack_damage == 0 keep shooting point-blank.
func _has_close_attack() -> bool:
	# Phase 3 — close-attack values come from the active weapon profile when
	# present, else HeroData (byte-identical with no profile).
	return _profile_close_damage() > 0.0


func _should_use_close_attack(enemy: Node, in_close_range: bool) -> bool:
	return _profile_uses_projectile() \
		and _has_close_attack() \
		and enemy != null and is_instance_valid(enemy) \
		and in_close_range \
		and enemy.has_method("is_engageable_ground") \
		and enemy.is_engageable_ground()


func _in_close_combat() -> bool:
	var in_close_range: bool = _target_enemy != null and _target_enemy in _blocked_enemies
	if not in_close_range and _target_enemy != null and engage_range_area != null:
		in_close_range = _target_enemy in engage_range_area.get_overlapping_areas()
	return _should_use_close_attack(_target_enemy, in_close_range)


# Returns {damage, speed, dtype, use_projectile}. Pure given the predicates
# above — unit-testable without a scene. Close damage scales by the same
# gear/talent multiplier the ranged shot gets so equipment still matters.
func _resolve_attack_profile() -> Dictionary:
	if _in_close_combat():
		# Gear ratio is over the hero's authored base (intentional — the close
		# poke scales with gear like the ranged shot). Close facets come from
		# the weapon profile when present, else HeroData (byte-identical).
		var base: float = maxf(0.01, data.attack_damage)
		var mult: float = _effective_damage() / base
		var dt: int = _profile_close_damage_type()
		if dt < 0:
			dt = _profile_damage_type()
		return {
			"damage": _profile_close_damage() * mult,
			"speed": maxf(0.01, _profile_close_speed()),
			"dtype": dt,
			"use_projectile": false,
		}
	return {
		"damage": _profile_damage(),
		"speed": get_effective_attack_speed(),
		"dtype": _profile_damage_type(),
		"use_projectile": _profile_uses_projectile(),
	}


# ---------------------------------------------------------------------------
# Public Hero Indicator Interface — mirrors the Tower Indicator Interface
# (CORE RULE 14). UI, DamageCalculator, and any cross-system reader call these
# accessors instead of touching `data.X` directly. Each modifier-aware getter
# returns `current_stats[key]` with a fallback to the authored baseline so a
# parse-time/orphan hero (no _seed_base_stats yet) still returns sensible
# numbers. Don't shadow these with `has_method` fallbacks at call sites — the
# interface is guaranteed.
# ---------------------------------------------------------------------------

func get_effective_max_health() -> int:
	return _effective_max_health()


func get_current_health() -> int:
	return current_health


func get_effective_damage() -> float:
	# Phase 3 — weapon base-replace (byte-identical when no weapon base set:
	# _profile_damage returns _effective_damage()).
	return _profile_damage()


func get_effective_attack_speed() -> float:
	if data == null:
		return 0.0
	# ABSOLUTE override: weapon speed wins flat; item attack_speed_pct affixes
	# are intentionally void here (contract — see WeaponProfileAbility.gd).
	if _weapon_profile != null and _weapon_profile.weapon_attack_speed > 0.0:
		return _weapon_profile.weapon_attack_speed
	return float(current_stats.get("attack_speed", data.attack_speed))


func get_effective_attack_range() -> float:
	if data == null:
		return 0.0
	# Weapon owns reach. ABSOLUTE override: item attack_range_pct affixes are
	# intentionally void while a weapon sets range (contract — see
	# WeaponProfileAbility.gd). No weapon range ⇒ unchanged (current_stats
	# keeps the attack_range_pct stack — byte-identical).
	if _weapon_profile != null and _weapon_profile.weapon_attack_range > 0.0:
		return _weapon_profile.weapon_attack_range
	return float(current_stats.get("attack_range", data.attack_range))


func get_preview_range() -> float:
	# RangePreview polymorphism — towers expose this name, heroes mirror it.
	return get_effective_attack_range()


func get_effective_armor() -> float:
	if data == null:
		return 0.0
	# Clamp at 0.95 to match BaseEnemy.get_effective_armor — without this cap,
	# stacked flat + pct armor from gear/passives/capstones could reach 1.0
	# (full immunity to physical damage). DamageCalculator does its own 0..1
	# clamp; the 0.95 here keeps the *visible* hero stat capped too so the
	# stats card shows the truthful number.
	return clampf(float(current_stats.get("armor", data.armor)), 0.0, 0.95)


func get_effective_magic_resist() -> float:
	if data == null:
		return 0.0
	# Same 0.95 cap as armor / enemy mitigation. Prevents Mystic Resilience
	# stacked with future MR gear from making the hero magic-immune.
	return clampf(float(current_stats.get("magic_resist", data.magic_resist)), 0.0, 0.95)


func get_effective_move_speed() -> float:
	if data == null:
		return 0.0
	return float(current_stats.get("move_speed", data.move_speed))


func get_effective_engage_radius() -> float:
	return _effective_engage_radius()


func get_effective_xp_gain_mult() -> float:
	return float(current_stats.get("xp_gain_mult", 1.0))


func get_effective_skill_power() -> float:
	return float(current_stats.get("skill_power", 1.0))


func get_effective_health_regen() -> float:
	return float(current_stats.get("health_regen", 0.0))


# Capped at 0.5 (50%) so the largest possible loadout can't drop a 5s
# cooldown below 2.5s. Items roll additive 0.03..0.08; 6 sources × 0.08
# would otherwise yield a free-cast build.
func get_effective_cooldown_reduction() -> float:
	return clampf(float(current_stats.get("cooldown_reduction", 0.0)), 0.0, 0.5)


func get_level() -> int:
	return level


func get_xp_progress() -> Dictionary:
	return {
		"level": level,
		"xp": current_xp,
		"xp_needed": _xp_needed_for_next_level(),
		"max_level": data.max_level if data != null else 0,
	}


func get_stats_line() -> String:
	# Live, modifier-aware stats row. Mirrors TowerData.get_stats_line() field
	# spacing (three spaces) so heroes and towers feel like one card style.
	if data == null:
		return ""
	var dmg: int = int(round(get_effective_damage()))
	var rng: int = int(round(get_effective_attack_range()))
	var spd: float = get_effective_attack_speed()
	var hp: int = get_current_health()
	var max_hp: int = get_effective_max_health()
	var arm: int = int(round(get_effective_armor() * 100.0))
	var mr: int = int(round(get_effective_magic_resist() * 100.0))
	var line: String = "Dmg %d   Rng %d   Spd %.1f   HP %d/%d   Arm %d%%" % [
		dmg, rng, spd, hp, max_hp, arm
	]
	if mr > 0:
		line += "   MR %d%%" % mr
	return line


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


func _tick_health_regen(delta: float) -> void:
	if data == null:
		return
	# Phase 3R-followup — track time since last damage AND gate regen on it.
	# Tick the timer regardless (capped at a sane upper bound); skip healing
	# while the hero is still in the recently-hit window.
	_seconds_since_damage = minf(_seconds_since_damage + delta, 1e6)
	if _seconds_since_damage < REGEN_OUT_OF_COMBAT_DELAY:
		return
	var rate: float = get_effective_health_regen()
	if rate <= 0.0:
		return
	_health_regen_accum += rate * delta
	if _health_regen_accum < 1.0:
		return
	var max_hp: int = _effective_max_health()
	if current_health >= max_hp:
		_health_regen_accum = 0.0
		return
	var heal_step: int = int(_health_regen_accum)
	_health_regen_accum -= float(heal_step)
	current_health = mini(max_hp, current_health + heal_step)
	queue_redraw()


func get_skill_data(idx: int) -> Resource:
	if data == null or idx < 0 or idx >= data.skills.size():
		return null
	return data.skills[idx] as Resource


func get_skill_cooldown_fraction(idx: int) -> float:
	# 0.0 = ready, 1.0 = just cast. UI radial overlay maps this to arc coverage.
	# Uses the rank-scaled cooldown so the radial fills correctly when the
	# player has bought R2/R3 (faster cycles).
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return 0.0
	var cd: float = get_skill_effective_cooldown(idx)
	if cd <= 0.0:
		return 0.0
	if idx >= _skill_cooldowns.size():
		return 0.0
	return clampf(_skill_cooldowns[idx] / cd, 0.0, 1.0)


# Phase 2 — rank-scaled + mod-scaled cooldown. Reads MetaProgression for the
# purchased ACTIVE_RANK and LoadoutState for the chosen MOD; both fold into
# `cooldown_mult` on the cast ctx. UI radial overlay AND the actual timer
# both go through this so they always agree.
func get_skill_effective_cooldown(idx: int) -> float:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return 0.0
	if data == null:
		return float(skill.cooldown)
	var ctx: Dictionary = _build_skill_ctx(skill)
	# Item-rolled cooldown reduction stacks on top of rank/mod scaling.
	# Same chokepoint drives both the timer and the radial-overlay display,
	# so they can't disagree.
	var cdr: float = get_effective_cooldown_reduction()
	return maxf(0.01, float(skill.cooldown) * float(ctx.get("cooldown_mult", 1.0)) * (1.0 - cdr))


# Build the cast-time context dict for a skill: rank-scaling deltas + chosen
# mod's scaling. Single source of truth used by cast_skill AND
# get_skill_effective_cooldown so the displayed cooldown matches the
# applied cooldown.
func _build_skill_ctx(skill: Resource) -> Dictionary:
	if skill == null or data == null:
		return {}
	var rank: int = MetaProgression.get_purchased_skill_rank(data.hero_id, String(skill.skill_id))
	var ctx: Dictionary = skill.get_effective_scaling(rank)
	# Mod merge runs only when a mod is actually chosen; skill_power fold-in
	# runs unconditionally below so unmodded skills still benefit from gear /
	# passives / capstone skill_power. (Earlier draft had a `return ctx` here
	# that skipped the fold-in for unmodded skills — fixed.)
	var chosen_mod_id: String = LoadoutState.get_chosen_mod(data.hero_id, String(skill.skill_id))
	if chosen_mod_id != "":
		var mod: Resource = LoadoutState.find_skill_mod(data.hero_id, chosen_mod_id)
		if mod != null and "scaling" in mod:
			for key in mod.scaling:
				if String(key).ends_with("_mult"):
					ctx[key] = float(ctx.get(key, 1.0)) * float(mod.scaling[key])
				else:
					ctx[key] = mod.scaling[key]
	# Phase 3R-followup-2 — fold skill_power into damage_mult. Items / passives
	# / Mage capstone author skill_power_pct on StatModifierAbility, which
	# raises current_stats["skill_power"] above the 1.0 baseline. Every skill
	# already reads damage_mult from ctx, so multiplying skill_power in here
	# is the single chokepoint that turns "staff +20% skill power" into a
	# real 20% boost to Fireball / Meteor / Frost Nova damage — regardless of
	# whether a mod is selected.
	var sp: float = get_effective_skill_power()
	if not is_equal_approx(sp, 1.0):
		ctx["damage_mult"] = float(ctx.get("damage_mult", 1.0)) * sp
	# 2026-05-14 — also expose skill_power as its own ctx key so non-damage
	# skills can scale outputs that aren't damage (heal, summon lifetime,
	# buff duration, slow duration, bless health). The damage_mult fold above
	# remains the chokepoint for damage skills; non-damage subclasses opt in
	# by reading skill_power_mult. Default 1.0 = identity, so subclasses that
	# don't read it stay unchanged.
	ctx["skill_power_mult"] = sp
	# Phase 3R-followup-3 — debug slider overrides for per-skill stats. Each
	# value is identity (1.0) in release builds via BalanceOverrides.is_active
	# short-circuit, so the multiplications are free when not actively used.
	# range_mult is excluded here — it's consumed pre-cast (targeting
	# preview), not via ctx; see get_skill_effective_range.
	var skill_id: String = String(skill.skill_id)
	for k in ["damage_mult", "cooldown_mult", "aoe_radius_mult"]:
		var sv: float = _BalanceOverrides.get_skill_mult(skill_id, k)
		if not is_equal_approx(sv, 1.0):
			ctx[k] = float(ctx.get(k, 1.0)) * sv
	return ctx


# CooldownButton provider contract — generic names so the same button
# class can drive any future cooldown-gated cast surface, not just hero skills.
func cooldown_fraction(idx: int) -> float:
	return get_skill_cooldown_fraction(idx)


func display_name(idx: int) -> String:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return "?"
	return skill.skill_name


func pictogram(idx: int) -> String:
	var skill: Resource = get_skill_data(idx)
	if skill == null or not ("pictogram" in skill):
		return ""
	return String(skill.pictogram)


func get_skill_effective_range(idx: int) -> float:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return 0.0
	# Phase 3R-followup-3 — slider override (identity 1.0 in release).
	var rng_mult: float = _BalanceOverrides.get_skill_mult(String(skill.skill_id), "range_mult")
	if skill.skill_range > 0.0:
		return skill.skill_range * rng_mult
	return get_effective_attack_range() * rng_mult


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
	# Returns true if the cast was initiated (not on cooldown). Apply runs
	# CAST_WIND_DURATION seconds later so the staff orb gets to charge.
	if not can_cast_skill(idx):
		return false
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return false
	var effective_cd: float = get_skill_effective_cooldown(idx)
	_skill_cooldowns[idx] = effective_cd
	EventBus.hero_skill_used.emit(skill.skill_name)
	EventBus.skill_cooldown_started.emit(skill.skill_name, effective_cd)
	# Defer the skill apply by CAST_WIND_DURATION. _physics_process detects
	# wind expiration and fires `skill.apply()` then.
	_pending_skill_idx = idx
	_pending_skill_target = target
	_cast_wind_t = CAST_WIND_DURATION
	# Cast pose — arm raised + body stretch for CAST_ANIM_DURATION so the
	# skill activation reads as a deliberate cast rather than a silent
	# instant. The cast direction faces the target when there is one.
	# Extended by CAST_WIND_DURATION so the post-cast aftermath plays AFTER
	# the wind-up + apply boundary.
	_cast_t = CAST_ANIM_DURATION + CAST_WIND_DURATION
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


# Fires the deferred skill.apply() at the boundary between cast wind-up and
# cast aftermath. Called from _physics_process when _cast_wind_t crosses 0.
func _apply_pending_skill() -> void:
	if _pending_skill_idx < 0:
		return
	# Audit fix #2: never resolve a wind-up that outlived the caster. If the
	# hero died (or data went away) during CAST_WIND_DURATION, drop the
	# pending skill instead of firing it on respawn.
	if state == State.DEAD or data == null:
		_pending_skill_idx = -1
		_pending_skill_target = null
		return
	var skill: Resource = get_skill_data(_pending_skill_idx)
	if skill != null:
		var ctx: Dictionary = _build_skill_ctx(skill)
		skill.apply(self, _pending_skill_target, ctx)
	_pending_skill_idx = -1
	_pending_skill_target = null


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
	# level-up math (+ account-wide xp multiplier + hero_leveled_up signal). Then
	# mirror the results back so combat code doesn't re-read MetaProgression each
	# frame. MetaProgression.add_hero_xp already emits hero_xp_gained and
	# hero_leveled_up — don't re-emit here.
	#
	# Two distinct multipliers stack here intentionally:
	#   - get_effective_xp_gain_mult() = transient run-scoped buffs from items /
	#     equipped passives (joins the modifier stack via current_stats).
	#   - MOD_HERO_XP inside MetaProgression.add_hero_xp = permanent account-wide
	#     meta upgrade (different seam, applied once at the call site there).
	# Multiplying both isn't double-counting — they're different sources.
	var scaled: int = int(ceil(float(amount) * get_effective_xp_gain_mult()))
	if scaled <= 0:
		return
	var old_level: int = level
	var new_level: int = MetaProgression.add_hero_xp(data.hero_id, scaled)
	level = new_level
	current_xp = MetaProgression.get_hero_xp(data.hero_id)
	while old_level < new_level:
		old_level += 1
		_level_up_apply()


func _level_up_apply() -> void:
	# Runtime side of a level-up. MetaProgression already emitted hero_leveled_up
	# and bumped the persistent entry; this method updates the live hero:
	# re-seed base, recompute modifiers, resize range shapes (so the next-level
	# growth on attack_range/engage_radius reaches the Area2Ds, not just the
	# stats card), heal to full.
	_seed_base_stats()
	recompute_stats()
	_resize_range_shapes()
	current_health = _effective_max_health()
	queue_redraw()
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
	# enemy we were blocking AND drop the soft claim immediately (don't
	# wait a frame for _sync_claim) so the reserved enemy resumes at once.
	_release_block()
	_release_claim()
	_seek_target_enemy = null
	_target_enemy = null
	_attack_cooldown = 0.0
	# Player tap reseats the rally point — the hero will leash to wherever
	# the player sent it, not back to the original spawn. Tap snaps to the
	# nearest path within TAP_SNAP_SLACK so casual mis-taps near the road
	# still land on the road; deliberate off-path taps are respected outside
	# the slack (Combat Blocking Doctrine — Hero on the Path).
	var dest: Vector2 = _snap_to_ground_line(world_pos, TAP_SNAP_SLACK)
	_rally_position = dest
	nav_agent.target_position = dest
	# Move-order marker — arm the destination ring at the SNAPPED target so
	# the player sees where the hero will actually land. Sits here so it only
	# fires for orders that pass the DEAD/data gate above; HeroInputManager
	# already filters illegal taps (tower spots, unselected hero) before
	# we get here, so reaching this line means the order is legitimate.
	_move_marker_pos = dest
	_move_marker_t = 1.0
	# Auto-deselect on move command — Option B. Next stray tap won't re-move
	# the hero until the player taps the body to re-arm.
	if is_selected:
		set_selected(false)
	_assisting = false  # player order overrides assist
	change_state(State.MOVING)


func _on_combat_lull_changed(in_lull: bool) -> void:
	_in_lull = in_lull
	# Lull ended (more enemies arrived). If we were only ASSISTING (not yet
	# hard-blocking), drop it and head back to the anchor so normal
	# block-many duty resumes. A hero already blocking stays — it's a
	# normal block now and the split rule handles the rest.
	if not in_lull and _assisting and _blocked_enemies.is_empty():
		_assisting = false
		if _seek_target_enemy != null and _claimed_enemy == _seek_target_enemy:
			_release_claim()
		_seek_target_enemy = null
		_target_enemy = null
		nav_agent.target_position = _rally_position
		if state != State.DEAD:
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
	if _cast_wind_t > 0.0:
		var prev_wind: float = _cast_wind_t
		_cast_wind_t = maxf(0.0, _cast_wind_t - delta)
		queue_redraw()
		# Fire the deferred skill apply on the falling edge so wind-up VFX
		# (orb charge, rune brighten) has played for the full window first.
		if _cast_wind_t == 0.0 and prev_wind > 0.0:
			_apply_pending_skill()
	if _move_marker_t > 0.0:
		_move_marker_t = maxf(0.0, _move_marker_t - delta / MOVE_MARKER_DURATION)
		queue_redraw()
	_tick_skill_cooldowns(delta)
	_tick_health_regen(delta)
	if _ability_host != null:
		_ability_host.tick(delta)
	_sync_claim(delta)
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			_prune_dead_blocks()
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
			# Two-tier: only acquire a melee target here if combat has no
			# active target. A pure ranged-shot target is intentionally not
			# hard-blocked, and must keep shooting/drop normally instead of
			# being hijacked into a chase by some other enemy near the anchor.
			if _target_enemy == null:
				var m: Node = _pick_target_in_detection_zone()
				if m != null:
					_target_enemy = m
					_seek_target_enemy = m
					nav_agent.target_position = _engage_position_for(m)
					_nav_repath_timer = 0.0
					_sync_claim(0.0)
					change_state(State.MOVING)
					return
			# Settle onto the enemy's exact lane-Y, then plant. The claimed
			# enemy is reserved (stop-on-claim) so it's frozen; if the
			# proximity-block fired while the hero was still off-Y (entered
			# engage_radius mid-stride), finish closing the short remaining
			# gap to the Y-locked spot at move_speed — continuous, never a
			# teleport (Combat Ground Line). Archetype-free: gated on actually
			# hard-blocking this enemy (a pure shot target never settles).
			if _target_enemy != null and is_instance_valid(_target_enemy) \
					and _target_enemy in _blocked_enemies:
				var csp: Vector2 = _engage_position_for(_target_enemy)
				var to_csp: Vector2 = csp - global_position
				if to_csp.length() > 4.0:
					# Safety net only (the Y-biased approach normally lands
					# aligned). Same Y-priority dir so if it does fire it
					# still slides in, never a pure-Y full-speed snap.
					velocity = _ground_line_dir(to_csp) * get_effective_move_speed()
			_attack_step(delta)
			_breath_t += delta
			queue_redraw()
	# Facing direction follows this frame's intended velocity, not last
	# frame's position delta. That keeps side-turn visuals from lagging behind
	# quick left/right move orders.
	if velocity.length_squared() > 0.001:
		_facing_dir = velocity.normalized()
	elif state == State.COMBAT and _target_enemy != null and is_instance_valid(_target_enemy):
		var to_t: Vector2 = (_target_enemy.global_position - global_position)
		if to_t.length_squared() > 0.001:
			_facing_dir = to_t.normalized()
	_prev_pos = global_position
	if absf(_face_dir_smoothed.x) > 0.20 and absf(_facing_dir.x) > 0.20 \
			and signf(_face_dir_smoothed.x) != signf(_facing_dir.x):
		_face_dir_smoothed.x = 0.0
		_face_vel.x = 0.0  # drop stale spring velocity on a hard L↔R snap
	var fx: Vector2 = _spring1(_face_dir_smoothed.x, _face_vel.x, _facing_dir.x, FACE_SPRING_K, FACE_SPRING_D, delta)
	var fy: Vector2 = _spring1(_face_dir_smoothed.y, _face_vel.y, _facing_dir.y, FACE_SPRING_K, FACE_SPRING_D, delta)
	_face_dir_smoothed = Vector2(fx.x, fy.x)
	_face_vel = Vector2(fx.y, fy.y)
	var cape_target: float = 0.0
	if velocity.length_squared() > 0.001:
		cape_target = -clampf(velocity.normalized().x, -1.0, 1.0)
	else:
		cape_target = -clampf(_facing_dir.x, -1.0, 1.0) * 0.20
	var cape_step: Vector2 = _spring1(_cape_lag_x, _cape_lag_vel, cape_target, CAPE_SPRING_K, CAPE_SPRING_D, delta)
	_cape_lag_x = cape_step.x
	_cape_lag_vel = cape_step.y
	move_and_slide()


func _start_lunge(target_world_pos: Vector2, visual_mode: String = "melee", attack_speed: float = -1.0) -> void:
	var dir: Vector2 = target_world_pos - global_position
	if dir.length_squared() < 0.01:
		return
	_lunge_dir = dir.normalized()
	_lunge_visual = visual_mode
	# Swing fills ~70% of the attack cooldown (clamped) so it never truncates
	# into a twitch nor drags into slow-motion. Captured per-swing so the
	# normalization stays stable if attack_speed changes mid-animation.
	var atk_speed: float = attack_speed if attack_speed > 0.0 else (get_effective_attack_speed() if data != null else 1.0)
	_lunge_dur = UnitVisualDrawer.swing_duration(atk_speed)
	_lunge_t = _lunge_dur
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	if _lunge_visual == "ranged":
		return Vector2.ZERO
	# Eased rear-back → fast commit → settle. Shared envelope with the soldier
	# (UnitVisualDrawer.lunge_offset_scale) so both read identically. Adds
	# perceived weight to every swing without changing attack cadence.
	var t: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
	return _lunge_dir * (LUNGE_DISTANCE * UnitVisualDrawer.lunge_offset_scale(t))


func _projectile_spawn_position(target_world_pos: Vector2, aim_angle: float) -> Vector2:
	var fallback: Vector2 = global_position + Vector2.from_angle(aim_angle) * 18.0
	if data == null or data.visual == null:
		return fallback
	var v: UnitVisualData = data.visual
	var body_r: float = v.radius if v.shape == UnitVisualData.Shape.CIRCLE else maxf(v.body_size.x, v.body_size.y) * 0.5
	var visual_offset: Vector2 = _lunge_offset() + Vector2(0.0, -v.flight_height_px)
	var face_x: float = clampf(_face_dir_smoothed.x, -1.0, 1.0)
	if absf(face_x) < 0.08:
		var aim_x: float = target_world_pos.x - global_position.x
		face_x = signf(aim_x) if absf(aim_x) > 1.0 else 0.0
	if v.render_profile == UnitVisualData.RenderProfile.NECROMANCER_PREMIUM:
		var depth_shift: float = face_x * body_r * 0.16
		var staff_tip_local: Vector2 = Vector2(body_r * 0.69 - depth_shift * 0.55, -body_r * 2.05)
		return global_position + visual_offset + staff_tip_local
	if v.render_profile == UnitVisualData.RenderProfile.MAGE_PREMIUM:
		var mage_staff_tip_local: Vector2 = Vector2(body_r * 0.52 + face_x * body_r * 0.10, -body_r * 2.35)
		return global_position + visual_offset + mage_staff_tip_local
	if v.render_profile == UnitVisualData.RenderProfile.DRAGON_PREMIUM:
		var dragon_mouth_local: Vector2 = Vector2(face_x * body_r * 1.64, -body_r * 0.04)
		return global_position + visual_offset + dragon_mouth_local
	if v.weapon_type == UnitVisualData.WeaponType.STAFF:
		var generic_staff_tip_local: Vector2 = Vector2(body_r * 0.62, -body_r * 1.50)
		return global_position + visual_offset + generic_staff_tip_local
	return fallback


# Combat Ground Line — unit steering direction toward a melee target that
# never lets the vertical (lane) gap close slower than the horizontal one.
# Until |Δy| ≤ Y_ALIGN_EPS, the X component of the direction is capped to
# |Δy| × APPROACH_Y_PRIORITY, so the blocker rises onto the enemy's lane-Y
# *during* the walk-in (at most a 45° diagonal), then continues straight
# along the line to the gap-offset spot. Eliminates the fast end-of-approach
# Y "snap" the old raw-normalize produced when COMBAT triggered early off-Y.
# Speed is unchanged (caller multiplies by move_speed) — only direction.
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


func _move_step(delta: float) -> void:
	# Drop freed/DYING blocks before anything reads capacity — _start_block
	# below would otherwise reject every new block while a stale entry fills
	# max_block_targets (permanent stuck). _prune_blocks_out_of_range only
	# runs in COMBAT, so MOVING needs its own validity sweep.
	_prune_dead_blocks()
	# While auto-seeking, repath toward the moving enemy's engage slot.
	# Combat Blocking Doctrine — abort chases that exit the guard zone /
	# auto-seek radius. The hero is a guard, not a hunter.
	if _seek_target_enemy != null:
		# Assist deliberately ignores the zone/leash + doomed cancels (the
		# straggler is outside the zone by definition). Death/invalidity
		# still cancels; lull-end is handled by _on_combat_lull_changed.
		var _seek_lost: bool = not is_instance_valid(_seek_target_enemy) \
				or _seek_target_enemy.state == BaseEnemy.State.DYING
		if not _assisting:
			_seek_lost = _seek_lost \
					or not _can_pursue(_seek_target_enemy) \
					or _melee_chase_is_doomed(_seek_target_enemy)
		if _seek_lost:
			# Drop the approach and walk home when the target leaves the
			# melee-engage range, dies, or out-runs the hero exit-ward. The
			# _can_pursue zone-boundary check is the backstop; the doomed
			# check bails BEFORE a long in-zone chase even starts. Archetype-
			# free — every hero approaches melee identically.
			if _claimed_enemy == _seek_target_enemy:
				_release_claim()
			if _target_enemy == _seek_target_enemy:
				_target_enemy = null
			_seek_target_enemy = null
			_assisting = false
			nav_agent.target_position = _rally_position
		else:
			_nav_repath_timer -= delta
			if _nav_repath_timer <= 0.0:
				_nav_repath_timer = NAV_REPATH_INTERVAL
				nav_agent.target_position = _engage_position_for(_seek_target_enemy)
			# UNIFIED melee-start gate (every hero). COMBAT only starts on a
			# real overlap/block claim. Reaching the engage spot alone is not
			# enough, because the enemy may have moved or the blocker slot may
			# be unavailable; stay in MOVING until the claim succeeds.
			if _seek_target_enemy in engage_range_area.get_overlapping_areas():
				_target_enemy = _seek_target_enemy
				_attack_cooldown = 0.0
				if _start_block(_target_enemy):
					_seek_target_enemy = null
					_assisting = false  # hard block now — a normal engagement
					change_state(State.COMBAT)
				return
			# Not in range yet → close DIRECTLY on the Y-locked engage
			# spot (Combat Ground Line), NOT the raw enemy centre. The
			# enemy is reserved (stop-on-claim) so the spot is stationary;
			# steering at it lands the hero on the enemy's exact Y instead
			# of proximity-blocking ~30 px off-Y while walking in at a
			# diagonal. Same definition the soldier charge uses. Soldier
			# model / CORE RULE 13 — straight vector, nav-agent only for
			# the no-target "return to anchor" path below.
			var to_spot: Vector2 = _engage_position_for(_seek_target_enemy) - global_position
			if to_spot.length_squared() > 1.0:
				# Y-priority: reach the enemy's lane-Y during the walk-in so
				# COMBAT never inherits a residual Y to burst through.
				velocity = _ground_line_dir(to_spot) * get_effective_move_speed()
			else:
				velocity = Vector2.ZERO
			return
	# Follow nav agent path.
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		_seek_target_enemy = null
		change_state(State.IDLE)
		return
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	velocity = (next_pos - global_position).normalized() * get_effective_move_speed()


# RANGED target selection. Same split priority as the melee picker, but the
# engageability gate is the RANGED rule, NOT is_engageable_ground():
#   - skip DYING (no point shooting a corpse)
#   - skip flying ONLY when this hero can't hit air (not data.targets_flying)
#   - bypass_engagement enemies ARE shootable — they just can't be blocked
# Casters (Mage/Ranger/Necromancer) MUST be able to fire at flyers/bypass;
# is_engageable_ground() is a MELEE-claim predicate and rejects both, which
# silently made ranged heroes useless vs air. See COMBAT_BLOCKING_DOCTRINE.md
# "ranged-vs-melee target-picker contract".
func _pick_shootable_target_in_area(area: Area2D) -> Node:
	var enemies: Array = []
	for a in area.get_overlapping_areas():
		if a is BaseEnemy:
			enemies.append(a)
	return _pick_shootable_from(enemies)


# Pure scan extracted from the area wrapper so the ranged gate is
# unit-testable without a live physics frame (Preventive Bug Rule #4).
# Gate: skip DYING, skip flyers only when this hero can't hit air. Bypass
# enemies pass — they're shootable, just not blockable.
func _pick_shootable_from(enemies: Array) -> Node:
	var allow_flying: bool = data != null and data.targets_flying
	var best: Node = null
	var best_block: int = 1 << 30
	var best_progress: float = -INF
	var best_d2: float = INF
	for enemy in enemies:
		if not (enemy is BaseEnemy):
			continue
		if enemy.data == null or enemy.state == BaseEnemy.State.DYING:
			continue
		if enemy.data.is_flying and not allow_flying:
			continue
		var bc: int = enemy.get_claim_count() if enemy.has_method("get_claim_count") else enemy._blockers.size()
		var prog: float = enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		var pri: int = bc + _targeting_bias(enemy)
		if pri < best_block \
				or (pri == best_block and prog > best_progress) \
				or (pri == best_block and prog == best_progress and d2 < best_d2):
			best_block = pri
			best_progress = prog
			best_d2 = d2
			best = enemy
	return best


# Combat Blocking Doctrine target selection: prefers the enemy with the
# FEWEST current blockers (so friendlies spread across incoming threats),
# tie-broken by HIGHEST path progress (the closer-to-exit threat is more
# urgent), tie-broken by nearest distance. Same rule the soldier uses.
# Filters DYING, flying-when-disallowed.
func _pick_split_target_in_area(area: Area2D) -> Node:
	var best: Node = null
	var best_block: int = 1 << 30
	var best_progress: float = -INF
	var best_d2: float = INF
	for a in area.get_overlapping_areas():
		if not (a is BaseEnemy):
			continue
		var enemy: BaseEnemy = a
		# Melee claim: ALWAYS skip flying/bypass/dying (can't block them).
		# targets_flying governs RANGED shooting only, never melee picks —
		# that conflation was the "close/chasing/not attacking" bug.
		if not enemy.is_engageable_ground():
			continue
		# Skip enemies the soft claim recently timed out on (stuck-recovery).
		if _is_given_up(enemy):
			continue
		var bc: int = enemy.get_claim_count() if enemy.has_method("get_claim_count") else enemy._blockers.size()
		var prog: float = enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		var pri: int = bc + _targeting_bias(enemy)
		if pri < best_block \
				or (pri == best_block and prog > best_progress) \
				or (pri == best_block and prog == best_progress and d2 < best_d2):
			best_block = pri
			best_progress = prog
			best_d2 = d2
			best = enemy
	return best


func _seek_target() -> void:
	# Combat Blocking Doctrine — hero anchors at _rally_position. When an
	# enemy enters the detection zone (circle of detection_radius_px around
	# the anchor), hero walks to the engage spot (approach phase), aligns Y
	# with the enemy on the path, then duels. After release/leak, hero
	# walks back to the anchor. See docs/COMBAT_BLOCKING_DOCTRINE.md.
	var target: Node = _pick_target_in_detection_zone()
	if target != null:
		_assisting = false  # a real in-zone target preempts assist
		_target_enemy = target
		_seek_target_enemy = target
		_sync_claim(0.0)
		var engage_spot: Vector2 = _engage_position_for(target)
		var dist_to_spot: float = global_position.distance_to(engage_spot)
		if dist_to_spot <= ENGAGE_ARRIVAL_TOLERANCE:
			# Already at the engage spot — start the duel immediately.
			_attack_cooldown = 0.0
			if _start_block(target):
				_seek_target_enemy = null
				change_state(State.COMBAT)
			else:
				nav_agent.target_position = engage_spot
				_nav_repath_timer = 0.0
				change_state(State.MOVING)
		else:
			# Approach phase — walk to the engage spot before swinging.
			nav_agent.target_position = engage_spot
			_nav_repath_timer = 0.0
			change_state(State.MOVING)
		return
	# RANGED-SHOOT TIER. No enemy inside the melee-engage range, but if this
	# hero has a projectile and an enemy is within attack_range, shoot it from
	# where it stands — the enemy KEEPS WALKING (never reserved: _seek_target_
	# enemy stays null and it won't be in _blocked_enemies). Casters keep
	# being ranged DPS; melee only ever triggers via the tier above.
	if _profile_uses_projectile():
		var shoot: Node = _pick_shootable_target_in_area(attack_range_area)
		if shoot != null and _within_leash(shoot):
			_target_enemy = shoot
			_seek_target_enemy = null
			_attack_cooldown = 0.0
			change_state(State.COMBAT)
			return
	# Assist-in-lull (lowest priority): nothing in zone / shootable AND only
	# the last engageable enemy remains AND we're not already blocking.
	# Approach + engage it like a normal target, but the detection-zone /
	# leak gate is bypassed (it's outside the zone by definition); the
	# _can_pursue cancel in _move_step is skipped while _assisting.
	if _in_lull and _blocked_enemies.is_empty():
		var lone: Node = WaveManager.lone_enemy()
		if lone != null and is_instance_valid(lone) and lone is BaseEnemy \
				and lone.is_engageable_ground() \
				and global_position.distance_to(lone.global_position) <= ASSIST_MAX_DIST:
			_assisting = true
			_target_enemy = lone
			_seek_target_enemy = lone
			_sync_claim(0.0)
			nav_agent.target_position = _engage_position_for(lone)
			_nav_repath_timer = 0.0
			change_state(State.MOVING)
			return
	# No valid target — if drifted from anchor, walk back.
	if global_position.distance_to(_rally_position) > LEASH_RETURN_TOLERANCE:
		_seek_target_enemy = null
		nav_agent.target_position = _rally_position
		change_state(State.MOVING)


# Combat Blocking Doctrine — pick the most urgent enemy inside the detection
# zone (circle of _effective_detection_radius around _rally_position). Same
# split rule as soldier: fewest blockers → highest path progress → nearest
# (world distance from hero, not anchor — biases toward the closer threat
# once the hero is already moving).
# A hero only pursues a melee target if it can actually block it: positive
# block capacity AND its body profile permits ground blocking. No-block
# bodies (flying Dragon, future sniper archetypes) skip melee acquisition
# entirely and fall straight through to the RANGED-SHOOT tier in
# _seek_target — they never walk at a ground enemy they can't lock and
# jitter (P1 fix). Default heroes (max_block_targets >= 1, humanoid body)
# return true → byte-identical, no behavior change. Pure read, no scene
# deps — unit-testable.
func _can_block_ground() -> bool:
	if data == null:
		return false
	var cap: int = int(data.max_block_targets) if "max_block_targets" in data else 1
	if cap <= 0:
		return false
	if data.has_method("get_body_profile"):
		var bp = data.get_body_profile()
		if bp != null and "blocks_ground" in bp and not bp.blocks_ground:
			return false
	return true


func _pick_target_in_detection_zone() -> Node:
	if data == null:
		return null
	# No-block bodies never acquire a melee target (P1 — Dragon was walking
	# at ground enemies it could never _start_block, wasting time/jitter).
	if not _can_block_ground():
		return null
	var zone_radius: float = _effective_detection_radius()
	if zone_radius <= 0.0:
		return null
	var zone_r2: float = zone_radius * zone_radius
	var best: Node = null
	var best_block: int = 1 << 30
	var best_progress: float = -INF
	var best_d2: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is BaseEnemy):
			continue
		var enemy: BaseEnemy = node
		# Melee acquisition: ALWAYS skip flying/bypass/dying via the shared
		# predicate (targets_flying is RANGED-only and must not let a flyer
		# become a melee-seek target the hero can never block).
		if not enemy.is_engageable_ground():
			continue
		# Stuck-recovery: don't re-acquire an enemy we just timed out on.
		if _is_given_up(enemy):
			continue
		if _rally_position.distance_squared_to(enemy.global_position) > zone_r2:
			continue
		if _has_leaked_past_anchor(enemy, GUARD_ACQUIRE_MARGIN_PX):
			# Acquire-side hysteresis: only START an approach on an enemy
			# still at/before the anchor. Once committed, _can_pursue uses
			# the wider GUARD_BACK_MARGIN_PX for follow-through. Prevents
			# the hero lurching toward an enemy that's about to leak.
			continue
		var bc: int = enemy.get_claim_count() if enemy.has_method("get_claim_count") else enemy._blockers.size()
		var prog: float = enemy.get_path_progress() if enemy.has_method("get_path_progress") else 0.0
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		var pri: int = bc + _targeting_bias(enemy)
		if pri < best_block \
				or (pri == best_block and prog > best_progress) \
				or (pri == best_block and prog == best_progress and d2 < best_d2):
			best_block = pri
			best_progress = prog
			best_d2 = d2
			best = enemy
	return best


# Unified melee-engage range — the single per-hero distance at which ANY hero
# commits to the shared melee pipeline (walk out → reserve → fight on enemy Y).
# Reads the computed stat (so the dev balance slider engage_range_mult + bake
# apply), falling back to authored HeroData.detection_radius_px, then one
# archetype-free default. NOT split by attack_range — every hero uses the same
# pipeline; only this number differs. See COMBAT_BLOCKING_DOCTRINE.md.
func _effective_detection_radius() -> float:
	if data == null:
		return 0.0
	var v: float = float(current_stats.get("melee_engage_range", 0.0))
	if v <= 0.0 and "detection_radius_px" in data:
		v = float(data.detection_radius_px)
	if v > 0.0:
		return v
	return DEFAULT_MELEE_ENGAGE_RANGE


# True if the target sits within LEASH_RADIUS of the current rally point.
# Safety cap — pursuit must also pass _can_pursue (guard zone / auto-seek).
func _within_leash(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.global_position.distance_to(_rally_position) <= LEASH_RADIUS


# Combat Blocking Doctrine — may this hero step out of the anchor to pursue
# this enemy? True iff enemy is inside the detection zone AND within the
# safety leash. Used by _move_step to abort chases that exit the zone.
func _can_pursue(enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if not _within_leash(enemy):
		return false
	if data == null:
		return false
	var zone_r: float = _effective_detection_radius()
	if zone_r <= 0.0:
		return false
	if _has_leaked_past_anchor(enemy, _back_margin()):
		return false
	return enemy.global_position.distance_to(_rally_position) <= zone_r


# Combat Blocking Doctrine — true if `enemy` has leaked past the hero's
# anchor by more than the grace margin, measured along the enemy's OWN path
# (not world distance). The hero never chases leakers backward — they're
# the towers' problem now. progress_delta returns 0.0 when there's no path
# data (flying / off-path), so those are never treated as leakers here
# (flying is already filtered upstream anyway). Pure → unit-testable.
# Back follow-through / drop margin. Data-driven: a hero with an authored
# HeroData.guard_back_px covers passers that far past its anchor; 0 falls
# back to the shared default. (Acquire-side stays GUARD_ACQUIRE_MARGIN_PX —
# separate concern, not the "block those who passed" lever.)
func _back_margin() -> float:
	if data != null and "guard_back_px" in data and data.guard_back_px > 0.0:
		return data.guard_back_px
	return GUARD_BACK_MARGIN_PX


func _has_leaked_past_anchor(enemy, margin: float = GUARD_BACK_MARGIN_PX) -> bool:
	return _GuardZoneScript.progress_delta(enemy, _rally_position) > margin


# Combat Blocking Doctrine — stop-on-claim reconciliation. Once per frame:
# reserve whatever the hero is currently committed to (COMBAT focus, else
# the approach target) and unreserve anything else, so a claimed enemy
# halts and waits while the hero walks over. Single choke-point — covers
# every place _seek_target_enemy / _target_enemy changes without touching
# each site. A claim that never reaches contact (pathing failure) is
# dropped after CLAIM_TIMEOUT so an enemy can't be frozen forever.
func _sync_claim(delta: float) -> void:
	# Unified, archetype-free. Soft-claim (reserve = halt the enemy BEFORE
	# contact so the blocker can walk to it) fires for EVERY hero whenever it
	# is committed to a MELEE engagement: the approach target (melee tier,
	# within melee-engage range) or the enemy it currently hard-blocks. A
	# pure ranged SHOT target is in _target_enemy but is NOT _seek_target_enemy
	# and NOT in _blocked_enemies → not reserved → the shot enemy keeps
	# walking (the lane is only ever stopped by a hero standing in it, never
	# from afar). The lane-flow guarantee is now structural, not an
	# archetype if. See docs/COMBAT_BLOCKING_DOCTRINE.md Core Rule 1.
	var desired: Node = null
	if _seek_target_enemy != null:
		desired = _seek_target_enemy
	elif state == State.COMBAT and _target_enemy != null and _target_enemy in _blocked_enemies:
		desired = _target_enemy
	if desired != null and not is_instance_valid(desired):
		desired = null
	if desired != _claimed_enemy:
		if _claimed_enemy != null and is_instance_valid(_claimed_enemy) \
				and _claimed_enemy.has_method("unreserve"):
			_claimed_enemy.unreserve(self)
		_claimed_enemy = desired
		_claim_age = 0.0
		if _claimed_enemy != null and _claimed_enemy.has_method("reserve"):
			_claimed_enemy.reserve(self)
	if _claimed_enemy != null and state != State.COMBAT:
		_claim_age += delta
		if _claim_age > CLAIM_TIMEOUT:
			# Contact never made within CLAIM_TIMEOUT. Blacklist THIS enemy for
			# a short cooldown so the next acquisition picks a DIFFERENT one
			# instead of deterministically re-failing on the same target every
			# 4 s — the "stuck between two enemies" livelock. If every nearby
			# enemy ends up blacklisted the pickers return null and the hero
			# cleanly holds the anchor (free), never the no-op loop.
			_note_giveup(_claimed_enemy)
			if OS.is_debug_build() and is_instance_valid(_claimed_enemy):
				var er: float = _effective_engage_radius()
				var dd: float = global_position.distance_to(_claimed_enemy.global_position)
				var ov: bool = _claimed_enemy in engage_range_area.get_overlapping_areas()
				print("[BaseHero/STUCK] %s gave up on %s — engage_r=%.1f dist=%.1f overlap=%s" % [
					_debug_node_label(self), _debug_node_label(_claimed_enemy), er, dd, str(ov)])
			if is_instance_valid(_claimed_enemy) and _claimed_enemy.has_method("unreserve"):
				_claimed_enemy.unreserve(self)
			_claimed_enemy = null
			_seek_target_enemy = null
			nav_agent.target_position = _rally_position
			change_state(State.MOVING)
	else:
		_claim_age = 0.0


# Combat Blocking Doctrine — release any held claim (death / respawn). Safe
# to call when nothing is claimed. _physics_process early-returns while DEAD
# so _sync_claim can't reconcile then — _die() must clear explicitly.
func _release_claim() -> void:
	if _claimed_enemy != null and is_instance_valid(_claimed_enemy) \
			and _claimed_enemy.has_method("unreserve"):
		_claimed_enemy.unreserve(self)
	_claimed_enemy = null
	_claim_age = 0.0


# Stuck-recovery — blacklist an enemy the soft claim timed out on. Purges
# expired/invalid entries opportunistically so the dict can't grow unbounded.
func _note_giveup(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var now: int = Time.get_ticks_msec()
	for k in _giveup_until.keys():
		if not is_instance_valid(k) or _giveup_until[k] <= now:
			_giveup_until.erase(k)
	_giveup_until[enemy] = now + GIVEUP_COOLDOWN_MS


# True while `enemy` is on the post-timeout cooldown. The MELEE pickers skip
# these so the hero commits to a different threat instead of re-failing on
# the same one. Self-expiring; ranged shooting never consults this.
func _is_given_up(enemy: Node) -> bool:
	if enemy == null or not _giveup_until.has(enemy):
		return false
	if _giveup_until[enemy] <= Time.get_ticks_msec():
		_giveup_until.erase(enemy)
		return false
	return true


# Combat Blocking Doctrine — snap a world position to the nearest level
# Path2D within `slack` px so the hero stands on the road. Outside slack,
# returns the original position so deliberate off-path placement
# (tactical taps, fortress side spawns) is respected. Looks up the
# level's "Paths" Node2D parent on each call — cheap relative to the
# call frequency (spawn/respawn/tap, not per-frame).
func _snap_to_ground_line(pos: Vector2, slack: float) -> Vector2:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return pos
	var paths_parent: Node = scene.get_node_or_null("Paths")
	if paths_parent == null:
		return pos
	return _GuardZoneScript.snap_to_nearest_path(pos, paths_parent, slack)


# Combat Blocking Doctrine change 4 — true if a melee hero should NOT start
# (or continue) an approach toward this enemy because it's faster than the
# hero AND moving exit-ward away from it: the hero can never close the gap,
# so chasing just looks silly. Returns false when the enemy is slower, or
# faster but still heading toward the hero (a closing duel is winnable).
func _melee_chase_is_doomed(enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var enemy_spd: float = enemy._effective_speed() if enemy.has_method("_effective_speed") else 0.0
	if enemy_spd <= get_effective_move_speed():
		return false
	# Enemy is faster. Only doomed if it's pulling AWAY (path-forward roughly
	# agrees with the hero→enemy vector — enemy is ahead and accelerating off).
	var fwd: Vector2 = _enemy_path_forward(enemy)
	if fwd == Vector2.ZERO:
		return false
	var to_enemy: Vector2 = enemy.global_position - global_position
	if to_enemy.length_squared() < 1.0:
		return false
	return fwd.dot(to_enemy.normalized()) > 0.25


# Combat Blocking Doctrine — unit tangent of the enemy's path at its
# current progress, pointing exit-ward. Falls back to the enemy's facing
# (a Node2D it exposes) then Vector2.RIGHT when no path data is available.
func _enemy_path_forward(enemy: Node) -> Vector2:
	var fwd: Vector2 = _GuardZoneScript.path_forward_at(enemy)
	if fwd != Vector2.ZERO:
		return fwd
	if enemy != null and is_instance_valid(enemy) and "_facing_dir" in enemy:
		var f: Vector2 = enemy._facing_dir
		if f.length_squared() > 0.0001:
			return f.normalized()
	return Vector2.RIGHT


# Where the hero should stand to MELEE the given enemy. Unified for every
# hero (the melee pipeline is archetype-free now — ranged heroes that drop
# into melee within their melee-engage range close to this exact spot too;
# their ranged shooting happens in place via the shoot tier and never calls
# this). One body-gap AHEAD of the enemy along the path (exit-ward) so the
# hero blocks the road instead of tackling from behind; Y LOCKED to the
# enemy's lane-Y via the shared Combat Ground Line helper so every blocker
# (hero + BaseSoldier) duels on the enemy's exact Y.
func _engage_position_for(enemy: Node) -> Vector2:
	var epos: Vector2 = enemy.global_position
	var fwd: Vector2 = _enemy_path_forward(enemy)
	# Gap is bounded by the block circle so the spot is always inside
	# _effective_engage_radius — guarantees _start_block registers
	# regardless of how short the hero's reach is authored.
	var gap: float = minf(MELEE_ENGAGE_GAP_X, _effective_engage_radius() - ENGAGE_GAP_SAFETY)
	gap = maxf(gap, MELEE_ENGAGE_DISTANCE)
	var slot: int = enemy.block_slot_for(self) if enemy.has_method("block_slot_for") else 0
	return _GuardZoneScript.melee_engage_spot(epos, fwd, gap, slot)


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
	# Combat Blocking Doctrine — enemy left attack range. KR rule: detection
	# ≠ combat, and a hero is a blocker, not a hunter. Only REPOSITION after
	# a near-leaker if the hero was *physically blocking* this enemy (it is
	# in _blocked_enemies — a real melee lock that may follow through within
	# the guard zone). A pure RANGED SHOT target (never blocked/reserved)
	# that walks out is simply dropped — the hero must NOT start chasing
	# something it was only shooting. Capture the flag BEFORE the release
	# (which clears _blocked_enemies).
	if not (enemy in attack_range_area.get_overlapping_areas()):
		var was_blocking: bool = _blocked_enemies.has(enemy)
		_release_block_of(enemy)
		_target_enemy = null
		if was_blocking and _can_pursue(enemy):
			# Real melee lock + still inside the guard zone → walk to the
			# engage spot and re-lock (finish a near-leaker at the line).
			_seek_target_enemy = enemy
			nav_agent.target_position = _engage_position_for(enemy)
			_nav_repath_timer = 0.0
			change_state(State.MOVING)
		else:
			# Was only shooting it (or it leaked past the guard zone): drop
			# it. IDLE → _seek_target re-acquires the next shoot/melee target
			# or walks back to the anchor. No chase.
			_seek_target_enemy = null
			change_state(State.IDLE)
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
	# Combat Blocking Doctrine — resolve which attack to use this swing.
	# Ranged heroes with a blockable focus enemy at face-contact range switch
	# to an authored melee poke (use_projectile=false); everyone else uses
	# their normal profile.
	var prof: Dictionary = _resolve_attack_profile()
	_attack_cooldown = 1.0 / maxf(0.01, float(prof["speed"]))
	var visual_mode: String = "melee"
	if bool(prof["use_projectile"]) \
			and data != null and data.visual != null \
			and (
				data.visual.render_profile == UnitVisualData.RenderProfile.MAGE_PREMIUM
				or data.visual.render_profile == UnitVisualData.RenderProfile.DRAGON_PREMIUM
			):
		visual_mode = "ranged"
	_start_lunge(enemy.global_position, visual_mode, float(prof["speed"]))
	var dmg: float = float(prof["damage"])
	var dtype: int = int(prof["dtype"])
	var dying: bool = enemy.state == BaseEnemy.State.DYING
	# Phase 3R-followup-3 — Ranger-style projectile firing. When the profile
	# resolves use_projectile (ranged shot, not a close poke), spawn an Arrow
	# targeting the enemy. Damage lands on projectile arrival (Arrow._on_hit).
	#
	# Combat Blocking Doctrine Phase 7 — projectile ON_HIT_DEALT / ON_KILL
	# fire from Arrow._on_hit via on_projectile_impact(). The instant-hit
	# branch (Warrior melee AND ranged-hero close poke) fires them inline
	# since impact is simultaneous with the swing.
	if bool(prof["use_projectile"]):
		var parent: Node = get_tree().current_scene
		if parent != null:
			var proj: Node2D = _profile_projectile_scene().instantiate()
			parent.add_child(proj)
			var aim: Vector2 = enemy.global_position - global_position
			var aim_angle: float = aim.angle() if aim.length_squared() > 0.0001 else 0.0
			proj.global_position = _projectile_spawn_position(enemy.global_position, aim_angle)
			if proj.has_method("setup"):
				proj.setup(enemy, dmg, dtype, self)
			# Muzzle flash, tinted by projectile color so each hero's archetype
			# (green ranger arrow, future arcane bolt, etc.) reads at the
			# launch point too. Skipped on clean_view.
			if not VFXSpawner.clean_view:
				var flash_color: Color = proj.proj_color if "proj_color" in proj else Color(1.0, 0.95, 0.6)
				_MuzzleFlashScript.spawn(parent, proj.global_position, aim_angle, flash_color)
	else:
		enemy.take_damage(dmg, dtype, self)
		# Instant-hit path — Warrior melee OR ranged-hero close poke. Ability
		# triggers fire inline since impact is synchronous with the swing.
		if _ability_host != null:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": dmg})
			if not dying and enemy.state == BaseEnemy.State.DYING:
				_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


# Combat Blocking Doctrine Phase 7 — projectile callback. Fired by Arrow
# on impact so ON_HIT_DEALT / ON_KILL passives score off the real arrival,
# not the launch frame. `killed` is true iff THIS arrow's hit transitioned
# the target into DYING.
func on_projectile_impact(target: Node, amount: float, killed: bool) -> void:
	if _ability_host == null:
		return
	if target != null and is_instance_valid(target):
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": target, "amount": amount})
		if killed:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": target})


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
		# Phase 3R-followup — reset the regen out-of-combat timer. Health
		# regen pauses for REGEN_OUT_OF_COMBAT_DELAY seconds after every hit
		# landed; the hero must disengage to start ticking HP back up.
		_seconds_since_damage = 0.0
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
	# Free any claimed enemy so it resumes walking — _physics_process early-
	# returns while DEAD so _sync_claim can't reconcile this.
	_release_claim()
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
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween().set_parallel(true)
	_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_death_tween.tween_property(self, "rotation", drift_dir * deg_to_rad(75.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(self, "position:y", position.y + 28.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.30).set_delay(0.10)
	_death_tween.chain().tween_callback(_on_death_drift_done)
	# Schedule respawn. HeroData.respawn_time (default 30s). Pass
	# process_always=false so the timer freezes with the paused SceneTree —
	# tactical pause and GameOverScreen pause both halt the countdown.
	# (Godot 4.6 default for create_timer's second arg is TRUE — without
	# this explicit false, the respawn would keep ticking through pause and
	# the hero could respawn on the GameOver screen.)
	var wait: float = data.respawn_time if data != null and data.respawn_time > 0.0 else 30.0
	get_tree().create_timer(wait, false).timeout.connect(_respawn)


func _on_death_drift_done() -> void:
	if state != State.DEAD:
		return
	visible = false
	rotation = 0.0
	modulate.a = 1.0
	_death_tween = null


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
	# Snap respawn position to the nearest path so the hero comes back on the
	# road, same as the initial spawn (Combat Blocking Doctrine — Hero on the Path).
	spawn_pos = _snap_to_ground_line(spawn_pos, SPAWN_SNAP_SLACK)
	global_position = spawn_pos
	_rally_position = spawn_pos
	current_health = _effective_max_health()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	# Reset any leftover state from the death-drift tween in case respawn
	# fires before the drift's 0.4s completion (short respawn_time edge case).
	rotation = 0.0
	modulate.a = 1.0
	visible = true
	_attack_cooldown = 0.0
	# Skill cooldowns — respawning is a fresh start. Without this, cooldowns
	# freeze during DEAD (because _physics_process early-returns on DEAD)
	# and resume from the same value on respawn, so the respawn time costs
	# zero cooldown progress. Reset to 0.0 and re-emit skill_ready for any
	# slot that was on cooldown so future ready-glow listeners still fire.
	for i in _skill_cooldowns.size():
		if _skill_cooldowns[i] > 0.0:
			_skill_cooldowns[i] = 0.0
			EventBus.skill_ready.emit(i)
	# Audit fix #1: respawn is a clean slate. Without this the hero comes
	# back still "pursuing" whatever it chased at death (ghost pursuit with
	# no player input) and the enemies it had blocked stay frozen waiting
	# for a hero that is now across the map (breaks split-rule balancing).
	# Release blocks/claims so those enemies resume immediately, then clear
	# every combat/seek/assist/skill/anim latch. (_in_lull is signal-owned
	# by WaveManager — left alone so it stays truthful.)
	_release_block()
	_release_claim()
	_seek_target_enemy = null
	_target_enemy = null
	_assisting = false
	_pending_skill_idx = -1
	_pending_skill_target = null
	_cast_wind_t = 0.0
	_cast_t = 0.0
	_lunge_t = 0.0
	_lunge_visual = "melee"
	_flinch_t = 0.0
	_hit_flash_t = 0.0
	_skill_range_preview = 0.0
	_walk_t = 0.0
	change_state(State.IDLE)
	queue_redraw()
	EventBus.hero_respawned.emit()


# Claim one more enemy's blocker slot, up to data.max_block_targets. Flying
# enemies skip engagement entirely. Unlike the old single-slot version,
# this does NOT release an existing block — both can coexist so the hero
# can tank multiple enemies side-by-side.
func _start_block(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	# Same shared predicate as every other melee path (also rejects
	# bypass/DYING, not just flying — last direct-field read removed).
	if not enemy.is_engageable_ground():
		return false
	if _blocked_enemies.has(enemy):
		return true
	var cap: int = data.max_block_targets if data != null else 1
	if _blocked_enemies.size() >= cap:
		return false
	# Engage gate — block claim only fires when the enemy is within the
	# hero's engage radius. attack_range can be much wider for ranged heroes;
	# this lets the mage shoot at 350 px while only locking enemies that
	# walk into face contact. Distant call sites still call _start_block
	# unconditionally (move_step, seek_target) — the gate makes them no-op
	# until _auto_engage_extras catches the enemy crossing into engage range.
	if not (enemy in engage_range_area.get_overlapping_areas()):
		return false
	if enemy.engage_combat(self):
		_blocked_enemies.append(enemy)
		return true
	return false


# Effective block-claim radius. Reads HeroData.engage_radius; when unset (0),
# falls back to the smaller of attack_range and DEFAULT_ENGAGE_RADIUS so a
# narrow-reach hero never claims past its own swing.
#
# Floored at MELEE_ENGAGE_DISTANCE: _engage_position_for clamps the approach
# gap UP to MELEE_ENGAGE_DISTANCE, so a radius below that would place the
# engage spot OUTSIDE this same circle — the _start_block overlap gate could
# then never become true and the hero would never reach COMBAT. The floor
# keeps the spot provably inside the gate circle for every hero. Single
# source: get_effective_engage_radius() just returns this, and the EngageRange
# Area2D shape is set from it (one radius, no drift).
func _effective_engage_radius() -> float:
	var r: float = DEFAULT_ENGAGE_RADIUS
	if data != null:
		var authored: float = float(data.engage_radius) if "engage_radius" in data else 0.0
		r = authored if authored > 0.0 else minf(get_effective_attack_range(), DEFAULT_ENGAGE_RADIUS)
	return maxf(r, MELEE_ENGAGE_DISTANCE)


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
	# Pick extra blocks by the SAME split priority as primary acquisition
	# (fewest claims → highest progress → nearest) instead of raw Area2D
	# overlap order, so a multi-block hero grabs the most urgent enemies.
	# guard caps the loop: once `pick` is blocked its claim count rises so
	# the next pick differs; a repeat means nothing better is left.
	var guard: int = 0
	while _blocked_enemies.size() < cap and guard < 8:
		guard += 1
		var pick: Node = _pick_split_target_in_area(engage_range_area)
		if pick == null or _blocked_enemies.has(pick):
			return
		if not _start_block(pick):
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


# Validity-only sweep of _blocked_enemies — drops freed / DYING entries with
# NO Area2D query. _prune_blocks_out_of_range only runs inside _attack_step
# (COMBAT); a non-focus block whose enemy died/leaked while the hero is in
# MOVING/IDLE would otherwise linger and falsely fill the max_block_targets
# capacity, so _start_block rejects every new block and the hero can never
# enter COMBAT (a permanent stuck, distinct from the CLAIM_TIMEOUT livelock).
# Cheap enough to call every frame outside COMBAT.
func _prune_dead_blocks() -> void:
	if _blocked_enemies.is_empty():
		return
	for i in range(_blocked_enemies.size() - 1, -1, -1):
		var e: Node = _blocked_enemies[i]
		if e == null or not is_instance_valid(e):
			_blocked_enemies.remove_at(i)
		elif e.state == BaseEnemy.State.DYING:
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
	# Phase 3R-followup-3 — attack-range ring for ranged heroes. A faint
	# always-on ring at get_effective_attack_range() so the player can read
	# Mage (350) / Ranger (280) reach at a glance. Melee heroes (≤ ranged
	# threshold) skip the ring — Knight at 75px doesn't need a visible
	# circle around his swing. Cheap to draw (one arc) and queue_redraw
	# already fires every frame for the hero in IDLE/COMBAT/MOVING.
	var atk_r: float = get_effective_attack_range() if data != null else 0.0
	if atk_r >= RANGED_ATTACK_RANGE_THRESHOLD:
		draw_arc(Vector2.ZERO, atk_r, 0.0, TAU, 64,
			Color(0.85, 0.92, 1.0, 0.22), 1.2 * zs)
	# Always-visible melee-engage ring — THE per-hero "range where melee
	# combat starts" (the unified melee-engage range, == the balance tunable
	# engage_range_mult). An enemy crossing this triggers the shared melee
	# pipeline for every hero. Faint warm tint so it reads as a melee danger
	# zone, distinct from the cool attack-range ring above.
	if data != null:
		var eng_r: float = _effective_detection_radius()
		if eng_r > 1.0:
			# Centered on the guard ANCHOR (_rally_position): the acquisition
			# zone is measured from the anchor in _pick_target_in_detection_
			# zone, so the ring must sit there or it lies when the hero steps
			# off the anchor to intercept (auto guard-move). EXCEPTION: during
			# a PLAYER-commanded relocation (MOVING with no auto seek target)
			# the anchor has already snapped to the tap destination; drawing
			# at the body instead lets the zone visually travel WITH the hero
			# to its new post instead of teleporting ahead of it. On arrival
			# the hero == _rally_position so the two coincide seamlessly.
			var anchor: Vector2 = to_local(_rally_position)
			if state == State.MOVING and _seek_target_enemy == null:
				anchor = Vector2.ZERO
			# Faint warm fill so the zone reads as an area, plus a clearly
			# visible solid stroke. Drawn under the body shadow/sprite below.
			draw_circle(anchor, eng_r, Color(1.0, 0.45, 0.30, 0.06))
			draw_arc(anchor, eng_r, 0.0, TAU, 64,
				Color(1.0, 0.50, 0.30, 0.55), 2.0 * zs)
	# Skill targeting range circle (Phase 20) — drawn first.
	if _skill_range_preview > 0.0:
		draw_circle(Vector2.ZERO, _skill_range_preview, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, _skill_range_preview, 0.0, TAU, 48, Color(1.0, 0.9, 0.3, 0.85), 2.5 * zs)
	# Selection ring sits on the ground, drawn before the shadow so the
	# shadow can darken it slightly where they overlap.
	if is_selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(1.0, 0.95, 0.3, 0.85), 2.5 * zs)
	# Phase 3N — buff aura. While any time-limited ability is active on the
	# host (Hunter's Stance, Mana Shield, Bless self-cast), pulse a faint
	# golden ring around the hero so the buff state is legible even when
	# the player isn't watching the SkillBar cooldowns. Permanent passives
	# / talents / capstones have duration = 0 and skip the aura.
	if _ability_host != null and _ability_host.has_temp_buff():
		var pulse: float = 0.7 + 0.3 * sin(_breath_t * 4.0)
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS - 8.0, 0, TAU, 24,
			Color(1.0, 0.85, 0.35, 0.55 * pulse), 1.5 * zs)
	# Ground shadow under the hero — anchored, doesn't bob with the body.
	# Race-independent: Dragon (race==NONE, flight_height_px=44) now gets a
	# small faint road shadow instead of reading as floating. Visual-only.
	if data != null and data.visual != null:
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
		var lt: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
		if lt > 0.32 and lt < 0.64:
			var sq: float = sin((lt - 0.32) / 0.32 * PI) * 0.18
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
		ctx["face"] = _face_dir_smoothed
		if walk_rotation != 0.0:
			ctx["walk_rotation"] = walk_rotation
		var max_hp: int = _effective_max_health()
		if max_hp > 0 and float(current_health) / float(max_hp) < 0.30:
			ctx["low_hp"] = true
		# Premium drawers (NECROMANCER) read these for richer idle/hit animation.
		# Always populate — drawer gates by render_profile so the cost is zero
		# for shared-path units that never read them.
		ctx["breath_t"] = _breath_t
		ctx["cape_lag"] = _cape_lag_x
		# Normalised travel speed (0 = still, 1 = full move speed) so the
		# premium walk can scale stride length with how fast we actually move.
		var _ems: float = get_effective_move_speed()
		ctx["move_speed01"] = clampf(velocity.length() / _ems, 0.0, 1.0) if _ems > 0.0 else 0.0
		if _flinch_t > 0.0:
			ctx["flinch_t"] = _flinch_t / FLINCH_DURATION
			ctx["flinch_dir"] = _flinch_dir
		# Attack wind-up + strike sweep via the shared phase mapping (single
		# source of truth — soldier + hero stay in lockstep). The held weapon
		# follows the body offset through the swing.
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
			ctx["attack_visual"] = _lunge_visual
			if _lunge_visual == "ranged" and (
					data.visual.render_profile == UnitVisualData.RenderProfile.MAGE_PREMIUM
					or data.visual.render_profile == UnitVisualData.RenderProfile.DRAGON_PREMIUM
			):
				ctx["wind_t"] = 1.0
				ctx["cast_t"] = clampf(1.0 - t01, 0.0, 1.0)
				ctx["strike_dir"] = _lunge_dir
			else:
				ctx.merge(UnitVisualDrawer.swing_phase(t01))
				if ctx.has("strike_t"):
					ctx["strike_dir"] = _lunge_dir
		# Cast pose — force arm raised and pointing at the cast direction.
		# Two phases:
		#   wind-up:   _cast_wind_t > 0 → arm fully raised, staff orb charges
		#   aftermath: _cast_wind_t == 0 and _cast_t > 0 → arm lowers, release flash
		if _cast_t > 0.0:
			ctx["strike_dir"] = _cast_dir
			if _cast_wind_t > 0.0:
				# Wind-up: hold arm raised at full, staff finial swells.
				ctx["wind_t"] = 1.0
				ctx["cast_wind_t"] = clampf(_cast_wind_t / CAST_WIND_DURATION, 0.0, 1.0)
				ctx["cast_t"] = 0.0
			else:
				# Aftermath: existing release-flash curve over CAST_ANIM_DURATION.
				var ct2: float = clampf(1.0 - (_cast_t / CAST_ANIM_DURATION), 0.0, 1.0)
				var raise_amount: float = sin(ct2 * PI) * 0.85 + 0.15
				ctx["wind_t"] = clampf(raise_amount, 0.0, 1.0)
				# Staff finial release-flash strength: 1 right after the shot,
				# 0 at the end of the cast animation.
				ctx["cast_t"] = clampf(_cast_t / CAST_ANIM_DURATION, 0.0, 1.0)

	# Body draw.
	if data != null and data.visual != null:
		var walk_t_arg: float = _walk_t if state == State.MOVING else -1.0
		UnitVisualDrawer.draw_unit(self, data.visual, body_offset, body_scale, walk_t_arg, _walk_phase, ctx)
		if _hit_flash_t > 0.0:
			UnitVisualDrawer.draw_hit_flash(self, data.visual, _hit_flash_t / HIT_FLASH_DURATION, body_offset, body_scale)
		if _lunge_t > 0.0:
			var t01: float = 1.0 - (_lunge_t / maxf(0.0001, _lunge_dur))
			if _lunge_visual != "ranged":
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
	_draw_combat_debug()


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


func _draw_combat_debug() -> void:
	if not OS.is_debug_build():
		return
	_prune_debug_refs()
	if not (is_selected or state != State.IDLE or _target_enemy != null \
			or _seek_target_enemy != null or not _blocked_enemies.is_empty()):
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = COMBAT_DEBUG_FONT_SIZE
	var lines: Array[String] = []
	lines.append("H %s cd %.2f" % [_state_name(state), _attack_cooldown])
	lines.append("t:%s s:%s c:%s" % [
		_debug_node_label(_target_enemy),
		_debug_node_label(_seek_target_enemy),
		_debug_node_label(_claimed_enemy),
	])
	lines.append("blk:%d claimAge:%.1f" % [_blocked_enemies.size(), _claim_age])
	var inspect_enemy = _seek_target_enemy if _seek_target_enemy != null else _target_enemy
	if inspect_enemy != null and is_instance_valid(inspect_enemy):
		var in_engage: bool = inspect_enemy in engage_range_area.get_overlapping_areas()
		var in_attack: bool = inspect_enemy in attack_range_area.get_overlapping_areas()
		var hard_block: bool = inspect_enemy in _blocked_enemies
		var claim_count: int = inspect_enemy.get_claim_count() if inspect_enemy.has_method("get_claim_count") else -1
		lines.append("atk:%s eng:%s hard:%s claims:%d" % [
			"Y" if in_attack else "n",
			"Y" if in_engage else "n",
			"Y" if hard_block else "n",
			claim_count,
		])
		lines.append("d:%.0f leak:%.1f can:%s doom:%s" % [
			global_position.distance_to(inspect_enemy.global_position),
			_GuardZoneScript.progress_delta(inspect_enemy, _rally_position),
			"Y" if _can_pursue(inspect_enemy) else "n",
			"Y" if _melee_chase_is_doomed(inspect_enemy) else "n",
		])
		if _seek_target_enemy != null:
			var spot: Vector2 = _engage_position_for(_seek_target_enemy)
			draw_line(Vector2.ZERO, to_local(spot), Color(1.0, 0.9, 0.1, 0.75), 2.0)
			draw_circle(to_local(spot), 5.0, Color(1.0, 0.9, 0.1, 0.85))
	else:
		# No target acquired — explain why the nearest enemy was skipped.
		_dbg_scan_rejections()
		if _dbg_reject_enemy != null and is_instance_valid(_dbg_reject_enemy):
			lines.append("NEAR %s d:%.0f" % [
				_debug_node_label(_dbg_reject_enemy),
				global_position.distance_to(_dbg_reject_enemy.global_position),
			])
			lines.append("skip: %s" % _dbg_reject)
			# Red line to the ignored enemy + the leak margin reference.
			var col := Color(0.95, 0.35, 0.35, 0.7) if _dbg_reject != "OK" else Color(0.4, 0.95, 0.4, 0.7)
			draw_line(Vector2.ZERO, to_local(_dbg_reject_enemy.global_position), col, 2.0)
	_draw_debug_lines(font, lines, Vector2(-92.0, -112.0), fs)


# Read-only mirror of _pick_target_in_detection_zone's filter chain. Finds
# the world-nearest enemy and records the FIRST rule that rejected it, so the
# overlay can explain why a close enemy is being ignored. Touches no combat
# state; debug-build only (called from _draw_combat_debug). Reasons:
#   flying / bypass — never blockable by this hero
#   out-of-zone     — beyond _effective_detection_radius from the anchor
#   leaked          — past the anchor by > GUARD_ACQUIRE_MARGIN_PX (the
#                     common cause of "it walked past me and I won't hit it")
#   OK              — would be acquired (no rejection)
func _dbg_scan_rejections() -> void:
	_dbg_reject_enemy = null
	_dbg_reject = ""
	if data == null:
		return
	var zone_r2: float = _effective_detection_radius()
	zone_r2 = zone_r2 * zone_r2
	var best_d2: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is BaseEnemy):
			continue
		var enemy: BaseEnemy = node
		if enemy.state == BaseEnemy.State.DYING or enemy.data == null:
			continue
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if d2 >= best_d2:
			continue
		var reason: String = "OK"
		# This mirrors the MELEE acquisition gate (_pick_target_in_detection_
		# zone → is_engageable_ground), which rejects flyers UNCONDITIONALLY.
		# data.targets_flying is the RANGED-shoot rule and must NOT soften this
		# label, or the overlay tells a Mage/Ranger/Necro "OK" for a flyer it
		# can never melee-acquire (it only shoots it). See the ranged-vs-melee
		# target-picker contract in COMBAT_BLOCKING_DOCTRINE.md.
		if enemy.data.is_flying:
			reason = "flying"
		elif "bypass_engagement" in enemy.data and enemy.data.bypass_engagement:
			reason = "bypass"
		elif _rally_position.distance_squared_to(enemy.global_position) > zone_r2:
			reason = "out-of-zone"
		elif _has_leaked_past_anchor(enemy, GUARD_ACQUIRE_MARGIN_PX):
			reason = "leaked %.0f>%.0f" % [
				_GuardZoneScript.progress_delta(enemy, _rally_position),
				GUARD_ACQUIRE_MARGIN_PX,
			]
		best_d2 = d2
		_dbg_reject_enemy = enemy
		_dbg_reject = reason


func _draw_debug_lines(font: Font, lines: Array[String], origin: Vector2, fs: int) -> void:
	if lines.is_empty():
		return
	var max_w: float = 0.0
	for line in lines:
		max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var line_h: float = float(fs) + 3.0
	var bg := Rect2(origin + Vector2(-4.0, -float(fs) - 4.0), Vector2(max_w + 8.0, line_h * lines.size() + 8.0))
	draw_rect(bg, Color(0.02, 0.025, 0.03, 0.78))
	draw_rect(bg, Color(1.0, 0.7, 0.25, 0.85), false, 1.0)
	for i in range(lines.size()):
		draw_string(font, origin + Vector2(0.0, float(i) * line_h), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1.0, 0.95, 0.75))


func _prune_debug_refs() -> void:
	if _target_enemy != null and not is_instance_valid(_target_enemy):
		_target_enemy = null
	if _seek_target_enemy != null and not is_instance_valid(_seek_target_enemy):
		_seek_target_enemy = null
	if _claimed_enemy != null and not is_instance_valid(_claimed_enemy):
		_claimed_enemy = null
	for i in range(_blocked_enemies.size() - 1, -1, -1):
		var e = _blocked_enemies[i]
		if e == null or not is_instance_valid(e):
			_blocked_enemies.remove_at(i)


func _debug_node_label(n) -> String:
	if n == null or not is_instance_valid(n):
		return "-"
	if n is BaseEnemy and (n as BaseEnemy).data != null:
		return (n as BaseEnemy).data.enemy_id
	return n.name


func _state_name(s: int) -> String:
	match s:
		State.IDLE:
			return "IDLE"
		State.MOVING:
			return "MOVING"
		State.COMBAT:
			return "COMBAT"
		State.DEAD:
			return "DEAD"
	return str(s)
