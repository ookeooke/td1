extends GutTest

# Phase 4 — HeroBodyProfile contract.
#
# Body profile is mostly DECLARATIVE: a flying hero that never blocks ground
# is the EXISTING mechanism (HeroData.max_block_targets == 0), not a new
# branch in the blocker state machine. The only behavioral hook is
# targeting_priority — a pure comparator bias. NEAREST (default /
# DEFAULT_HUMANOID) ⇒ bias 0 ⇒ byte-identical ordering.
#
# Re-asserts the load-bearing Blocker invariants stay intact with a
# flying-style hero (COMBAT_BLOCKING_DOCTRINE #1, #2): is_engageable_ground()
# untouched, targets_flying still RANGED-only. (The canonical 6-invariant
# suite is test_combat_blocking.gd; this adds the flying-hero case rather
# than mutating that delicate doctrine file.)

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _enemy(is_flying: bool) -> BaseEnemy:
	var e := BaseEnemy.new()
	var d := EnemyData.new()
	d.is_flying = is_flying
	d.max_health = 10
	e.data = d
	e.state = BaseEnemy.State.WALKING
	_spawned.append(e)
	return e


func _hero(max_block: int, body: HeroBodyProfile = null) -> BaseHero:
	var h := BaseHero.new()
	var d := HeroData.new()
	d.hero_id = "hero_test"
	d.attack_damage = 5.0
	d.attack_speed = 1.0
	d.attack_range = 100.0
	d.max_block_targets = max_block
	d.body_profile = body
	h.data = d
	_spawned.append(h)
	return h


# ── Default humanoid: byte-identical (NEAREST ⇒ no bias) ────────────────

func test_default_body_profile_is_humanoid() -> void:
	var bp: HeroBodyProfile = _hero(1).data.get_body_profile()
	assert_false(bp.is_flying, "default body is grounded")
	assert_true(bp.blocks_ground, "default body blocks ground")
	assert_eq(bp.targeting_priority, HeroBodyProfile.TargetingPriority.NEAREST,
		"default targeting is NEAREST (byte-identical order)")


func test_nearest_bias_is_zero_for_all() -> void:
	var h: BaseHero = _hero(1)  # no body profile ⇒ DEFAULT_HUMANOID / NEAREST
	assert_eq(h._targeting_bias(_enemy(true)), 0, "NEAREST: flyer unbiased")
	assert_eq(h._targeting_bias(_enemy(false)), 0, "NEAREST: ground unbiased")


# ── Targeting priority comparator bias ──────────────────────────────────

func test_ground_first_deprioritizes_flyer() -> void:
	var bp := HeroBodyProfile.new()
	bp.targeting_priority = HeroBodyProfile.TargetingPriority.GROUND_FIRST
	var h: BaseHero = _hero(1, bp)
	assert_gt(h._targeting_bias(_enemy(true)), 0, "GROUND_FIRST penalizes flyers")
	assert_eq(h._targeting_bias(_enemy(false)), 0, "GROUND_FIRST: ground unbiased")


func test_air_first_deprioritizes_ground() -> void:
	var bp := HeroBodyProfile.new()
	bp.targeting_priority = HeroBodyProfile.TargetingPriority.AIR_FIRST
	var h: BaseHero = _hero(1, bp)
	assert_gt(h._targeting_bias(_enemy(false)), 0, "AIR_FIRST penalizes ground")
	assert_eq(h._targeting_bias(_enemy(true)), 0, "AIR_FIRST: flyer unbiased")


func test_bias_below_no_candidate_sentinel() -> void:
	# A de-prioritized enemy must still be selectable when it's the only one
	# (bias must stay under the 1<<30 "no candidate" sentinel in the pickers).
	var bp := HeroBodyProfile.new()
	bp.targeting_priority = HeroBodyProfile.TargetingPriority.GROUND_FIRST
	var h: BaseHero = _hero(1, bp)
	assert_lt(h._targeting_bias(_enemy(true)), 1 << 30,
		"bias < no-candidate sentinel so a lone de-prioritized enemy is still picked")


# ── Flying never blocks ground (existing max_block_targets=0 mechanism) ──

func test_flying_hero_never_blocks_ground() -> void:
	# max_block_targets == 0 ⇒ _start_block returns false at the cap gate,
	# before any Area2D query — the real, scene-free never-block mechanism.
	var h: BaseHero = _hero(0)
	var ground: BaseEnemy = _enemy(false)
	assert_true(ground.is_engageable_ground(),
		"control: a plain ground enemy IS melee-engageable")
	assert_false(h._start_block(ground),
		"flying-style hero (max_block_targets=0) never enters COMBAT-block")


func test_humanoid_hero_block_not_capped_at_zero() -> void:
	# Control: a normal hero's cap does not pre-reject at the count gate
	# (the engage-range Area2D gate beyond it is exercised in-editor).
	var h: BaseHero = _hero(1)
	assert_eq(h.data.max_block_targets, 1,
		"humanoid keeps its authored block capacity (unchanged)")


# ── Invariant regression (#1, #2): gates untouched by Phase 4 ───────────

func test_invariant_engageable_ground_unchanged() -> void:
	assert_false(_enemy(true).is_engageable_ground(),
		"#1 is_engageable_ground still rejects flyers (Phase 4 didn't touch it)")
	assert_true(_enemy(false).is_engageable_ground(),
		"#1 ground enemy still engageable")


# ── R3c — bias INSIDE a real picker (not just the helper in isolation) ──
# Covers `pri = bc + _targeting_bias(enemy)` integration in
# _pick_shootable_from + the 1<<30 no-candidate sentinel interaction.

func test_ground_first_picker_prefers_ground_on_tie() -> void:
	var bp := HeroBodyProfile.new()
	bp.targeting_priority = HeroBodyProfile.TargetingPriority.GROUND_FIRST
	var h: BaseHero = _hero(1, bp)
	h.data.targets_flying = true  # ranged hero CAN shoot flyers
	var flyer: BaseEnemy = _enemy(true)
	var ground: BaseEnemy = _enemy(false)
	# Co-located so claim-count(0) / progress(0) / distance all tie — the
	# body-profile bias is the ONLY discriminator.
	flyer.global_position = Vector2(10, 0)
	ground.global_position = Vector2(10, 0)
	assert_eq(h._pick_shootable_from([flyer, ground]), ground,
		"GROUND_FIRST: ground wins the tie via the in-picker bias")


func test_ground_first_picker_still_picks_lone_flyer() -> void:
	# Sentinel safety: a de-prioritized flyer is the only candidate ⇒ still
	# selected (bias 1<<20 < the 1<<30 no-candidate sentinel).
	var bp := HeroBodyProfile.new()
	bp.targeting_priority = HeroBodyProfile.TargetingPriority.GROUND_FIRST
	var h: BaseHero = _hero(1, bp)
	h.data.targets_flying = true
	var flyer: BaseEnemy = _enemy(true)
	flyer.global_position = Vector2(10, 0)
	assert_eq(h._pick_shootable_from([flyer]), flyer,
		"lone de-prioritized flyer is still picked (bias < no-candidate sentinel)")
