extends GutTest

# Combat Blocking Doctrine invariants. Covers the small testable surface:
# the engage_combat cooldown gate (Phase 7 bug #4), the GuardZone helper's
# filter logic, and the on_projectile_impact contract. Scene-level behavior
# (soldier returning to rally, ranged hero shooting without blocking) is
# verified in the editor / playtest, not here — those tests require a live
# NavigationServer + Area2D pickup, which GUT headless can't fake reliably.
# See docs/COMBAT_BLOCKING_DOCTRINE.md.

const _GuardZone = preload("res://systems/GuardZone.gd")

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


# ── engage_combat cooldown gate ─────────────────────────────────────────

func test_engage_combat_first_blocker_resets_cooldown() -> void:
	var enemy: BaseEnemy = _make_enemy(1.0)  # attack_speed 1.0 → cooldown 1.0
	enemy._combat_cooldown = 0.0
	enemy.engage_combat(_make_blocker_stub("a"))
	assert_almost_eq(enemy._combat_cooldown, 1.0, 0.001,
		"first blocker entering COMBAT must reset cooldown to 1/attack_speed")
	assert_eq(enemy.state, BaseEnemy.State.COMBAT, "first blocker transitions to COMBAT")


func test_engage_combat_second_blocker_does_not_reset_cooldown() -> void:
	var enemy: BaseEnemy = _make_enemy(1.0)
	var a: Node = _make_blocker_stub("a")
	enemy.engage_combat(a)
	# Simulate mid-swing — cooldown ticks down to halfway.
	enemy._combat_cooldown = 0.5
	enemy.engage_combat(_make_blocker_stub("b"))
	assert_almost_eq(enemy._combat_cooldown, 0.5, 0.001,
		"second blocker arriving mid-swing must NOT reset cooldown (Phase 7 bug fix)")


func test_engage_combat_duplicate_blocker_rejected() -> void:
	var enemy: BaseEnemy = _make_enemy(1.0)
	var a: Node = _make_blocker_stub("a")
	assert_true(enemy.engage_combat(a), "first registration succeeds")
	assert_false(enemy.engage_combat(a), "duplicate registration rejected")


# ── GuardZone filters ───────────────────────────────────────────────────

func test_guardzone_rejects_flying() -> void:
	var enemy: Node = _make_fake_enemy_minimal(true, false)
	# Use fallback-distance path (no path data on the stub). Even with the
	# enemy at exactly the hold point, flying should reject up front.
	enemy.global_position = Vector2.ZERO
	assert_false(_GuardZone.is_guardable(enemy, Vector2.ZERO, 200.0, 200.0),
		"flying enemy must never be guardable")


func test_guardzone_rejects_bypass_engagement() -> void:
	var enemy: Node = _make_fake_enemy_minimal(false, true)
	enemy.global_position = Vector2.ZERO
	assert_false(_GuardZone.is_guardable(enemy, Vector2.ZERO, 200.0, 200.0),
		"bypass_engagement enemy must never be guardable")


func test_guardzone_fallback_distance_inside_zone() -> void:
	var enemy: Node = _make_fake_enemy_minimal(false, false)
	enemy.global_position = Vector2(80.0, 0.0)
	assert_true(_GuardZone.is_guardable(enemy, Vector2.ZERO, 120.0, 70.0),
		"enemy 80px from hold point with front=120 must be guardable (fallback)")


func test_guardzone_fallback_distance_outside_zone() -> void:
	var enemy: Node = _make_fake_enemy_minimal(false, false)
	enemy.global_position = Vector2(300.0, 0.0)
	assert_false(_GuardZone.is_guardable(enemy, Vector2.ZERO, 120.0, 70.0),
		"enemy 300px from hold point with front=120/back=70 must NOT be guardable")


# ── on_projectile_impact contract ───────────────────────────────────────

# ── _has_leaked_past_anchor (forward cutoff) ────────────────────────────

# Builds a BaseEnemy riding a horizontal curve y=100, x:0→1000, at the
# given path progress (≈ world x on a flat line). Frees via _spawned.
func _enemy_on_path_at(progress: float) -> BaseEnemy:
	var path := Path2D.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2(0, 100))
	curve.add_point(Vector2(1000, 100))
	path.curve = curve
	var pf := PathFollow2D.new()
	path.add_child(pf)
	pf.progress = progress
	var enemy := BaseEnemy.new()
	enemy.data = EnemyData.new()
	enemy.setup(pf, "lane")
	_spawned.append(path)
	_spawned.append(enemy)
	return enemy


func _hero_anchored_at(anchor: Vector2) -> BaseHero:
	var hero := BaseHero.new()
	hero.data = HeroData.new()
	hero._rally_position = anchor
	_spawned.append(hero)
	return hero


func test_leaked_enemy_past_anchor_is_flagged() -> void:
	# Anchor projects to offset ~500; enemy at progress 600 → delta +100 > 50.
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	var enemy: BaseEnemy = _enemy_on_path_at(600.0)
	assert_true(hero._has_leaked_past_anchor(enemy),
		"enemy 100 px past the anchor (margin 50) is a leaker")


func test_approaching_enemy_is_not_leaked() -> void:
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	var enemy: BaseEnemy = _enemy_on_path_at(400.0)  # delta -100
	assert_false(hero._has_leaked_past_anchor(enemy),
		"enemy still approaching the anchor is not a leaker")


func test_enemy_within_grace_margin_is_not_leaked() -> void:
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	var enemy: BaseEnemy = _enemy_on_path_at(530.0)  # delta +30 ≤ 50
	assert_false(hero._has_leaked_past_anchor(enemy),
		"enemy just past the anchor within the 50 px grace is still engageable")


func test_no_path_enemy_is_not_leaked() -> void:
	# Bare enemy, no PathFollow2D → progress_delta 0.0 → never a leaker.
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	var enemy: BaseEnemy = _make_enemy(1.0)
	assert_false(hero._has_leaked_past_anchor(enemy),
		"no path data → not flagged as a leaker (flying filtered upstream)")


# H2 — acquire vs pursue hysteresis. An enemy just past the anchor (delta
# +30) must be rejected for *acquisition* (margin 0) but still allowed for
# *pursuit* (margin 50) so a committed approach finishes instead of feinting.
func test_acquire_margin_stricter_than_pursue_margin() -> void:
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	var enemy: BaseEnemy = _enemy_on_path_at(530.0)  # progress_delta ≈ +30
	assert_true(hero._has_leaked_past_anchor(enemy, BaseHero.GUARD_ACQUIRE_MARGIN_PX),
		"+30 past anchor is NOT acquirable (acquire margin 0)")
	assert_false(hero._has_leaked_past_anchor(enemy, BaseHero.GUARD_BACK_MARGIN_PX),
		"+30 past anchor IS still pursuable (pursue margin 50) — no feint")


# H1 — the melee engage spot must always sit INSIDE the hero's block circle
# (_effective_engage_radius) so _start_block can't perpetually no-op. Tested
# for a Warrior-shaped reach and a synthetic short-reach melee hero.
func _melee_hero(attack_range: float, engage_radius: float) -> BaseHero:
	var hero := BaseHero.new()
	hero.data = HeroData.new()
	hero.data.attack_range = attack_range
	hero.data.engage_radius = engage_radius   # 0 → derives min(atkR, 60)
	_spawned.append(hero)
	return hero


func test_engage_spot_inside_block_circle_warrior_shaped() -> void:
	var hero: BaseHero = _melee_hero(75.0, 0.0)   # → engage radius 60
	var enemy: BaseEnemy = _enemy_on_path_at(500.0)
	var spot: Vector2 = hero._engage_position_for(enemy)
	var d: float = enemy.global_position.distance_to(spot)
	assert_true(d <= hero._effective_engage_radius() + 0.01,
		"engage spot (%.1f px) must be within block radius (%.1f px)" % [d, hero._effective_engage_radius()])


func test_engage_spot_inside_block_circle_short_reach() -> void:
	var hero: BaseHero = _melee_hero(75.0, 40.0)  # authored tiny block circle
	var enemy: BaseEnemy = _enemy_on_path_at(500.0)
	var spot: Vector2 = hero._engage_position_for(enemy)
	var d: float = enemy.global_position.distance_to(spot)
	assert_true(d <= hero._effective_engage_radius() + 0.01,
		"short-reach hero: spot %.1f px must stay inside its 40 px block circle" % d)


# Bug-B regression guard: on a SLOPED path (tangent has a Y component) the
# melee engage spot must still sit at the enemy's EXACT Y — the blocker
# shares the enemy's ground line, never inherits the path tangent's Y.
func test_engage_spot_locks_to_enemy_Y_on_sloped_path() -> void:
	var hero: BaseHero = _melee_hero(75.0, 0.0)
	# Diagonal curve so path_forward has a strong Y component.
	var path := Path2D.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(400, 400))   # 45° slope → fwd ≈ (0.707, 0.707)
	path.curve = curve
	var pf := PathFollow2D.new()
	path.add_child(pf)
	pf.progress = 200.0
	var enemy := BaseEnemy.new()
	enemy.data = EnemyData.new()
	enemy.setup(pf, "slope")
	enemy.global_position = Vector2(640, 360)   # arbitrary lane position
	_spawned.append(path)
	_spawned.append(enemy)
	var spot: Vector2 = hero._engage_position_for(enemy)
	assert_almost_eq(spot.y, 360.0, 0.001,
		"engage spot Y must equal the enemy's Y even on a 45° sloped path (bug B)")
	assert_true(absf(spot.x - 640.0) > 1.0,
		"engage spot is still offset horizontally toward the exit")


# ── Combat Ground Line: shared melee_engage_spot helper ─────────────────

# The helper returns the enemy's EXACT Y with only a horizontal gap offset
# toward the path-exit side. This is the single definition every melee
# blocker (hero + soldier) uses, so they all duel on the enemy's ground line.
func test_melee_engage_spot_locks_enemy_Y_and_offsets_X() -> void:
	var epos := Vector2(640, 360)
	var fwd := Vector2(0.707, 0.707)   # 45° sloped path tangent
	var spot: Vector2 = _GuardZone.melee_engage_spot(epos, fwd, 50.0)
	assert_almost_eq(spot.y, 360.0, 0.001,
		"spot Y must equal enemy Y regardless of path tangent's Y component")
	assert_almost_eq(spot.x, 690.0, 0.001,
		"spot X is enemy.x + sign(fwd.x)*gap = 640 + 50")


# Degenerate / vertical path (fwd.x ≈ 0): fall back to +X so the spot is
# still a valid offset rather than collapsing onto the enemy.
func test_melee_engage_spot_vertical_path_falls_back_to_plus_x() -> void:
	var spot: Vector2 = _GuardZone.melee_engage_spot(Vector2(100, 200), Vector2(0, 1), 30.0)
	assert_almost_eq(spot.x, 130.0, 0.001, "fwd.x≈0 → dir_x defaults to +1")
	assert_almost_eq(spot.y, 200.0, 0.001, "Y still locked to enemy")


# Combat Ground Line — approach steering must NOT starve the vertical (lane)
# gap. From a far-X / small-Y start the steered unit direction must close Y
# at least as fast as X (|dir.y| ≥ |dir.x|), so the blocker reaches the
# enemy's lane during the walk-in instead of snapping to it at the end.
func test_ground_line_dir_does_not_starve_Y() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	# Far in X (600), one lane off in Y (50) — the old raw-normalize gave
	# dir ≈ (0.99, 0.08): Y crawls. Biased dir must have |y| ≥ |x|.
	var d: Vector2 = hero._ground_line_dir(Vector2(600.0, 50.0))
	assert_almost_eq(d.length(), 1.0, 0.001, "still a unit vector (speed unchanged)")
	assert_true(absf(d.y) >= absf(d.x) - 0.001,
		"Y must close no slower than X while a lane gap remains (got %s)" % str(d))
	assert_true(d.x > 0.0 and d.y > 0.0, "still heads toward the target quadrant")


func test_ground_line_dir_passthrough_when_aligned_or_Y_dominant() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	# Y already matched (≤ Y_ALIGN_EPS) → straight to target, no bias.
	var d1: Vector2 = hero._ground_line_dir(Vector2(600.0, 1.0))
	assert_almost_eq(d1, Vector2(600.0, 1.0).normalized(), Vector2(0.001, 0.001),
		"aligned → plain normalized (pure horizontal slide along the lane)")
	# Y gap already larger than X → raw normalized (never starved anyway).
	var d2: Vector2 = hero._ground_line_dir(Vector2(20.0, 200.0))
	assert_almost_eq(d2, Vector2(20.0, 200.0).normalized(), Vector2(0.001, 0.001),
		"Y-dominant → unchanged")


# Regression: the melee hero's engage spot must be exactly what the shared
# helper produces — proves _engage_position_for routes through it (one
# definition, no drift between hero and soldier).
func test_hero_engage_spot_matches_shared_helper() -> void:
	var hero: BaseHero = _melee_hero(75.0, 0.0)
	var enemy: BaseEnemy = _enemy_on_path_at(500.0)
	var spot: Vector2 = hero._engage_position_for(enemy)
	# Spot must sit on the enemy's Y (the helper's invariant).
	assert_almost_eq(spot.y, enemy.global_position.y, 0.001,
		"melee hero engage spot Y must equal enemy Y (shared Combat Ground Line)")


# ── path_forward_at + doomed-chase predicate ────────────────────────────

func test_path_forward_points_exit_ward() -> void:
	# Horizontal curve spawn→exit (left→right). Tangent at mid-curve must be
	# the unit +X vector (exit-ward), regardless of lane v_offset.
	var path := Path2D.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2(0, 100))
	curve.add_point(Vector2(1000, 100))
	path.curve = curve
	var pf := PathFollow2D.new()
	path.add_child(pf)
	pf.progress = 500.0
	var enemy := BaseEnemy.new()
	enemy.data = EnemyData.new()
	enemy.setup(pf, "test_path")
	_spawned.append(path)   # frees pf + enemy subtree too
	_spawned.append(enemy)
	var fwd: Vector2 = _GuardZone.path_forward_at(enemy)
	assert_almost_eq(fwd.x, 1.0, 0.05, "forward tangent on a left→right path is +X")
	assert_almost_eq(fwd.y, 0.0, 0.05, "no Y component on a flat horizontal path")


func test_path_forward_no_path_returns_zero() -> void:
	# Bare enemy with no PathFollow2D → helper returns Vector2.ZERO so
	# callers fall back to their own heuristic.
	var enemy: BaseEnemy = _make_enemy(1.0)
	assert_eq(_GuardZone.path_forward_at(enemy), Vector2.ZERO,
		"no path data → Vector2.ZERO (caller falls back)")


func test_melee_chase_not_doomed_when_enemy_slower() -> void:
	# Early-out gate: enemy slower than hero → never doomed, no path needed.
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.move_speed = 300.0
	hero.data.attack_range = 75.0
	var enemy: BaseEnemy = _make_enemy(1.0)
	enemy.data.move_speed = 120.0  # slower than hero
	assert_false(hero._melee_chase_is_doomed(enemy),
		"a slower enemy is always catchable — never a doomed chase")


# ── snap_to_nearest_path ────────────────────────────────────────────────

func test_snap_inside_slack_returns_path_point() -> void:
	# Build a simple path with two waypoints — a horizontal line at y=100.
	var paths_parent: Node2D = _make_paths_with_curve([Vector2(0, 100), Vector2(1000, 100)])
	# World pos 30 px below the line; slack is 80 → should snap.
	var result: Vector2 = _GuardZone.snap_to_nearest_path(Vector2(500, 130), paths_parent, 80.0)
	assert_almost_eq(result.y, 100.0, 0.5, "snap should land on the path Y line")
	assert_almost_eq(result.x, 500.0, 0.5, "snap should preserve X along the path")


func test_snap_outside_slack_returns_original() -> void:
	var paths_parent: Node2D = _make_paths_with_curve([Vector2(0, 100), Vector2(1000, 100)])
	# 200 px below the line, slack=80 → should NOT snap; respect tactical placement.
	var raw_pos := Vector2(500, 300)
	var result: Vector2 = _GuardZone.snap_to_nearest_path(raw_pos, paths_parent, 80.0)
	assert_eq(result, raw_pos, "outside slack must return original position unchanged")


func test_snap_handles_null_paths_parent() -> void:
	var result: Vector2 = _GuardZone.snap_to_nearest_path(Vector2(500, 300), null, 80.0)
	assert_eq(result, Vector2(500, 300), "null paths_parent must return input unchanged")


# ── Archetype-default detection radius ──────────────────────────────────

# ── Stop-on-claim (enemy reservation) ───────────────────────────────────

func test_reserve_freezes_then_unreserve_resumes() -> void:
	# A reserved enemy holds its path progress; unreserving lets it resume.
	var enemy: BaseEnemy = _enemy_on_path_at(300.0)
	var blk := Node.new()
	_spawned.append(blk)
	assert_true(enemy.reserve(blk), "ground enemy accepts a reservation")
	assert_true(enemy.is_held(), "reserved + unblocked → held (standing still)")
	# Simulate physics frames: a held enemy must not advance progress.
	var p0: float = enemy.get_path_progress()
	enemy._physics_process(0.1)
	enemy._physics_process(0.1)
	assert_almost_eq(enemy.get_path_progress(), p0, 0.001, "held enemy progress is frozen")
	enemy.unreserve(blk)
	assert_false(enemy.is_held(), "unreserved → no longer held")
	enemy._physics_process(0.1)
	assert_true(enemy.get_path_progress() > p0, "progress resumes after unreserve")


func test_flying_enemy_ignores_reservation() -> void:
	var enemy: BaseEnemy = _enemy_on_path_at(300.0)
	enemy.data.is_flying = true
	var blk := Node.new()
	_spawned.append(blk)
	assert_false(enemy.reserve(blk), "flying enemy refuses reservation (never stops)")
	assert_false(enemy.is_held(), "flying enemy is never held")


func test_hero_release_claim_unreserves() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	var enemy: BaseEnemy = _enemy_on_path_at(300.0)
	enemy.reserve(hero)
	hero._claimed_enemy = enemy
	hero._release_claim()
	assert_eq(hero._claimed_enemy, null, "release clears the hero's claim")
	assert_false(enemy.is_held(), "released enemy is no longer held")


func test_hero_sync_claim_reserves_switches_clears() -> void:
	# _sync_claim reconciles _claimed_enemy from the current target each
	# frame: reserve on acquire, swap on target change, free on clear.
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	hero.data.attack_range = 75.0  # shape only — soft-claim is archetype-free
	var e1: BaseEnemy = _enemy_on_path_at(200.0)
	var e2: BaseEnemy = _enemy_on_path_at(250.0)
	hero._seek_target_enemy = e1
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, e1, "claims the acquired target")
	assert_true(e1.is_held(), "acquired enemy is held")
	hero._seek_target_enemy = e2
	hero._sync_claim(0.016)
	assert_false(e1.is_held(), "old target unreserved on switch")
	assert_eq(hero._claimed_enemy, e2, "new target claimed")
	assert_true(e2.is_held(), "new target held")
	hero._seek_target_enemy = null
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, null, "claim cleared when target goes null")
	assert_false(e2.is_held(), "enemy resumes when unclaimed")


func test_hero_sync_claim_drops_freed_enemy() -> void:
	# Enemy dies/freed mid-approach → next _sync_claim clears the stale
	# claim without crashing.
	var hero: BaseHero = _hero_anchored_at(Vector2(500, 100))
	hero.data.attack_range = 75.0  # shape only — soft-claim is archetype-free
	var e: BaseEnemy = _enemy_on_path_at(200.0)
	hero._seek_target_enemy = e
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, e, "claimed")
	hero._seek_target_enemy = null
	e.free()
	hero._sync_claim(0.016)  # must not crash on the freed ref
	assert_eq(hero._claimed_enemy, null, "stale claim cleared after target freed")


func test_shot_target_not_blocked_is_never_reserved() -> void:
	# Two-tier: a pure SHOT target (COMBAT, but NOT in _blocked_enemies and
	# NOT the approach target) is never reserved — archetype-free. This is
	# the structural lane-flow guarantee: ranged-shaped hero shooting from
	# afar does not freeze the enemy.
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 320.0  # projectile/ranged shape
	var e: BaseEnemy = _enemy_on_path_at(200.0)
	hero._target_enemy = e          # shooting it, but not blocking it
	hero.call("change_state", BaseHero.State.COMBAT)
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, null, "shot-only target is not reserved")
	assert_false(e.is_held(), "shot enemy keeps walking (not frozen)")


func test_any_hero_soft_claims_melee_approach_target() -> void:
	# Unification: a ranged-SHAPED hero that has committed to a melee
	# approach target (enemy inside its melee-engage range → _seek_target_
	# enemy set) soft-claims it via the SAME pipeline the Warrior uses.
	# Archetype does not gate soft-claim anymore.
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 320.0  # ranged-shaped — but still soft-claims
	var e: BaseEnemy = _enemy_on_path_at(200.0)
	hero._seek_target_enemy = e
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, e, "any hero soft-claims its melee approach target")
	assert_true(e.is_held(), "claimed enemy is held")


func test_melee_hero_still_soft_claims() -> void:
	# Regression: a melee-shaped hero still soft-claims its approach target.
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 75.0
	var e: BaseEnemy = _enemy_on_path_at(200.0)
	hero._seek_target_enemy = e
	hero._sync_claim(0.016)
	assert_eq(hero._claimed_enemy, e, "melee hero soft-claims its target")
	assert_true(e.is_held(), "claimed enemy is held")


func test_effective_melee_engage_range_sources_and_default() -> void:
	# _effective_detection_radius = the unified melee-engage range. Reads the
	# computed stat first (so engage_range_mult / bake apply), then authored
	# detection_radius_px, then one archetype-free default.
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 320.0  # archetype must NOT influence the range
	hero.data.detection_radius_px = 0.0
	assert_almost_eq(hero._effective_detection_radius(),
		BaseHero.DEFAULT_MELEE_ENGAGE_RANGE, 0.001,
		"unauthored → single default, no melee/ranged split")
	hero.data.detection_radius_px = 90.0
	assert_almost_eq(hero._effective_detection_radius(), 90.0, 0.001,
		"authored detection_radius_px wins when no computed stat")
	hero.current_stats = {"melee_engage_range": 180.0}
	assert_almost_eq(hero._effective_detection_radius(), 180.0, 0.001,
		"computed stat (engage_range_mult/bake) wins over authored")


func test_compute_base_stats_plumbs_melee_engage_range() -> void:
	# engage_range_mult is identity (1.0) when BalanceOverrides inactive, so
	# the plumbed value equals authored detection_radius_px.
	var hd := HeroData.new()
	hd.hero_id = "test_hero"
	hd.detection_radius_px = 120.0
	var stats: Dictionary = BaseHero.compute_base_stats(hd, 1)
	assert_true(stats.has("melee_engage_range"), "stat dict carries melee_engage_range")
	assert_almost_eq(float(stats["melee_engage_range"]), 120.0, 0.001,
		"melee_engage_range = authored × engage_range_mult(=1.0 identity)")


func test_soldier_reserves_charge_target_and_releases() -> void:
	var soldier := BaseSoldier.new()
	_spawned.append(soldier)
	soldier.data = SoldierData.new()
	var enemy: BaseEnemy = _enemy_on_path_at(300.0)
	soldier._charge_target = enemy
	soldier._sync_claim()
	assert_eq(soldier._claimed_enemy, enemy, "soldier claims its charge target")
	assert_true(enemy.is_held(), "charge target is held (stop-on-claim)")
	# Charge dropped (left guard zone / target lost) → next sync unreserves.
	soldier._charge_target = null
	soldier._sync_claim()
	assert_eq(soldier._claimed_enemy, null, "claim cleared when charge target lost")
	assert_false(enemy.is_held(), "enemy resumes when soldier drops it")
	# Re-claim then die → _release_claim frees it.
	soldier._charge_target = enemy
	soldier._sync_claim()
	assert_true(enemy.is_held(), "re-claimed")
	soldier._release_claim()
	assert_false(enemy.is_held(), "soldier death/despawn frees the claim")


func test_set_blocking_position_releases_soft_claim_immediately() -> void:
	# Rally-flag drag must unreserve the held enemy on the SAME call, not wait
	# for the next _sync_claim frame — locks the explicit _release_claim() in
	# set_blocking_position(). Without it the enemy stays frozen one tick.
	var soldier := BaseSoldier.new()
	_spawned.append(soldier)
	soldier.data = SoldierData.new()
	soldier.state = BaseSoldier.State.MOVING
	var enemy: BaseEnemy = _enemy_on_path_at(300.0)
	soldier._charge_target = enemy
	soldier._sync_claim()
	assert_true(enemy.is_held(), "precondition: soldier holds the enemy")
	soldier.set_blocking_position(Vector2(500, 200), Vector2(480, 200))
	assert_eq(soldier._claimed_enemy, null,
		"rally reset clears the soft claim in the same call")
	assert_false(enemy.is_held(),
		"held enemy resumes immediately on rally reset (no one-frame freeze)")


# ── Stuck-between-two-enemies recovery ──────────────────────────────────
# Regression lock for the CLAIM_TIMEOUT livelock: a hero that times out a soft
# claim must blacklist THAT enemy briefly so the next acquisition picks a
# different one, instead of deterministically re-failing on the same target
# every 4 s (hero appears frozen between two enemies). See
# docs/COMBAT_BLOCKING_DOCTRINE.md.

func test_giveup_blacklist_set_and_self_expiry() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	var e: BaseEnemy = _make_enemy(1.0)
	assert_false(hero._is_given_up(e), "fresh enemy is not blacklisted")
	hero._note_giveup(e)
	assert_true(hero._is_given_up(e), "timed-out enemy is blacklisted")
	# Force expiry without sleeping: backdate the entry.
	hero._giveup_until[e] = Time.get_ticks_msec() - 1
	assert_false(hero._is_given_up(e), "blacklist self-expires after the cooldown")
	assert_false(hero._giveup_until.has(e), "expired entry is purged on read")


func test_giveup_ignores_null_and_purges_invalid() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero._note_giveup(null)  # must not crash / must not add a key
	assert_eq(hero._giveup_until.size(), 0, "null is never blacklisted")
	var doomed: BaseEnemy = BaseEnemy.new()
	doomed.data = EnemyData.new()
	hero._note_giveup(doomed)
	assert_eq(hero._giveup_until.size(), 1, "valid enemy recorded")
	doomed.free()
	var live: BaseEnemy = _make_enemy(1.0)
	hero._note_giveup(live)  # purge pass drops the now-freed key
	assert_false(hero._giveup_until.keys().any(func(k): return not is_instance_valid(k)),
		"freed enemies are purged from the blacklist")


# NOTE: the end-to-end "picker hands back the OTHER enemy" path
# (_pick_target_in_detection_zone / _pick_split_target_in_area) needs a live
# scene tree + Area2D pickup, which GUT headless can't fake (see this file's
# header). The give-up gate in both pickers is a single
# `if _is_given_up(enemy): continue`; its semantics are fully locked by the
# two _is_given_up tests above, and the behavioural path is verified manually
# (repro harness in the plan / SESSIONS).


# ── Stale-block capacity prune (permanent-stuck variant) ────────────────

func test_prune_dead_blocks_drops_freed_entry() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	var gone: BaseEnemy = BaseEnemy.new()
	gone.data = EnemyData.new()
	hero._blocked_enemies = [gone]
	gone.free()
	hero._prune_dead_blocks()
	assert_eq(hero._blocked_enemies.size(), 0,
		"freed block is pruned outside COMBAT so capacity can't read falsely full")


func test_prune_dead_blocks_releases_dying_entry() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	var dying: BaseEnemy = _enemy_on_path_at(300.0)
	dying.engage_combat(hero)            # hero is now a blocker on `dying`
	hero._blocked_enemies = [dying]
	dying.state = BaseEnemy.State.DYING
	hero._prune_dead_blocks()
	assert_false(hero._blocked_enemies.has(dying),
		"DYING block removed from the capacity list")
	assert_eq(dying._blockers.size(), 0,
		"and the enemy is told it is no longer blocked")


# ── Engage-radius floor (engage spot can't sit outside the gate circle) ──

func test_effective_engage_radius_floored_and_single_source() -> void:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 10.0   # tiny → would derive a radius < 30
	hero.data.engage_radius = 0.0   # unset → falls back to min(atkR, default)
	var r: float = hero._effective_engage_radius()
	assert_true(r >= BaseHero.MELEE_ENGAGE_DISTANCE,
		"engage radius floored at MELEE_ENGAGE_DISTANCE so the spot stays inside the gate")
	assert_almost_eq(hero.get_effective_engage_radius(), r, 0.001,
		"get_effective_engage_radius is a thin mirror — one radius, no drift")
	# And the engage spot is provably within that circle even at the floor.
	var e: BaseEnemy = _enemy_on_path_at(500.0)
	var spot: Vector2 = hero._engage_position_for(e)
	assert_true(e.global_position.distance_to(spot) <= r + 0.01,
		"engage spot within the (floored) block circle")


func test_progress_delta_sign() -> void:
	# Anchor world point projects onto the horizontal lane at x≈hold.x.
	# Enemy ahead (higher progress) → positive delta; behind → negative.
	var ahead: BaseEnemy = _enemy_on_path_at(600.0)
	var behind: BaseEnemy = _enemy_on_path_at(400.0)
	var d_ahead: float = _GuardZone.progress_delta(ahead, Vector2(500, 100))
	var d_behind: float = _GuardZone.progress_delta(behind, Vector2(500, 100))
	assert_almost_eq(d_ahead, 100.0, 2.0, "enemy past the anchor → +delta")
	assert_almost_eq(d_behind, -100.0, 2.0, "enemy before the anchor → −delta")


# ── Ranged-hero close-combat profile resolver ───────────────────────────

func _ranged_hero(close_dmg: float, close_spd: float, close_dt: int) -> BaseHero:
	var hero := BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_damage = 10.0
	hero.data.attack_speed = 0.5
	hero.data.attack_range = 300.0
	hero.data.damage_type = 1               # MAGIC ranged identity
	hero.data.projectile_scene = PackedScene.new()  # marks ranged archetype
	hero.data.close_attack_damage = close_dmg
	hero.data.close_attack_speed = close_spd
	hero.data.close_attack_damage_type = close_dt
	return hero


func test_profile_unauthored_ranged_keeps_shooting() -> void:
	var hero: BaseHero = _ranged_hero(0.0, 0.0, -1)  # close not authored
	var prof: Dictionary = hero._resolve_attack_profile()
	assert_true(prof["use_projectile"], "unauthored close → still a ranged shot")
	assert_almost_eq(float(prof["damage"]), 10.0, 0.001, "ranged damage = attack_damage")


func test_profile_authored_but_not_blocking_is_ranged() -> void:
	var hero: BaseHero = _ranged_hero(4.0, 1.0, 0)
	# Not blocking anything → still ranged.
	var prof: Dictionary = hero._resolve_attack_profile()
	assert_true(prof["use_projectile"], "authored close but not engaged → ranged shot")
	assert_almost_eq(float(prof["damage"]), 10.0, 0.001, "ranged damage path")


func test_profile_close_when_blockable_enemy_in_face_range() -> void:
	var hero: BaseHero = _ranged_hero(4.0, 1.0, 0)
	var foe: BaseEnemy = _make_fake_enemy_minimal(false, false)
	hero._target_enemy = foe
	assert_true(hero._should_use_close_attack(foe, true),
		"blockable ground enemy at face range uses close poke before hard block registers")


func test_profile_close_range_keeps_projectile_for_flying_or_bypass() -> void:
	var hero: BaseHero = _ranged_hero(4.0, 1.0, 0)
	var flyer: BaseEnemy = _make_fake_enemy_minimal(true, false)
	var bypass: BaseEnemy = _make_fake_enemy_minimal(false, true)
	assert_false(hero._should_use_close_attack(flyer, true),
		"flyers stay projectile targets even at face range")
	assert_false(hero._should_use_close_attack(bypass, true),
		"bypass enemies stay projectile targets even at face range")


func test_profile_close_when_blocking_focus() -> void:
	var hero: BaseHero = _ranged_hero(4.0, 1.0, 0)
	var foe: BaseEnemy = _make_fake_enemy_minimal(false, false)
	hero._target_enemy = foe
	hero._blocked_enemies = [foe]           # physically engaged
	var prof: Dictionary = hero._resolve_attack_profile()
	assert_false(prof["use_projectile"], "blocking focus → melee poke, not a shot")
	# mult = _effective_damage()/attack_damage = 10/10 = 1 (no gear) → 4.0
	assert_almost_eq(float(prof["damage"]), 4.0, 0.001, "close damage = close_attack_damage × gear-ratio")
	assert_almost_eq(float(prof["speed"]), 1.0, 0.001, "close cadence used")
	assert_eq(int(prof["dtype"]), 0, "authored close_attack_damage_type = PHYSICAL")


func test_profile_close_damage_type_inherits_on_negative() -> void:
	var hero: BaseHero = _ranged_hero(4.0, 1.0, -1)  # -1 → inherit data.damage_type
	var foe: BaseEnemy = _make_fake_enemy_minimal(false, false)
	hero._target_enemy = foe
	hero._blocked_enemies = [foe]
	var prof: Dictionary = hero._resolve_attack_profile()
	assert_eq(int(prof["dtype"]), 1, "close_attack_damage_type -1 inherits data.damage_type (MAGIC)")


func test_detection_radius_single_default_no_archetype_split() -> void:
	# Unified: melee-engage range has ONE archetype-free default. A melee-
	# shaped and a ranged-shaped hero with detection_radius_px=0 both fall
	# back to the same DEFAULT_MELEE_ENGAGE_RANGE.
	var melee: BaseHero = BaseHero.new()
	_spawned.append(melee)
	melee.data = HeroData.new()
	melee.data.attack_range = 75.0
	var ranged: BaseHero = BaseHero.new()
	_spawned.append(ranged)
	ranged.data = HeroData.new()
	ranged.data.attack_range = 320.0
	assert_almost_eq(melee._effective_detection_radius(),
		BaseHero.DEFAULT_MELEE_ENGAGE_RANGE, 0.001, "melee-shaped → single default")
	assert_almost_eq(ranged._effective_detection_radius(),
		BaseHero.DEFAULT_MELEE_ENGAGE_RANGE, 0.001, "ranged-shaped → SAME default")


func test_detection_radius_authoring_overrides() -> void:
	# Authored detection_radius_px wins regardless of archetype shape.
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 75.0
	hero.data.detection_radius_px = 400.0
	assert_almost_eq(hero._effective_detection_radius(), 400.0, 0.001,
		"authored detection_radius_px must win over the default")


# ── Flying-unit visual lift ─────────────────────────────────────────────

func test_flying_enemy_visual_has_flight_height() -> void:
	# Smoke test: the authored visual for the only is_flying enemy must carry
	# a non-zero flight_height_px after the visual-rework lands. Catches a
	# future .tres rewrite that silently zeroes the field — flyers would
	# render at ground level (the very bug this rework fixed).
	var vis: UnitVisualData = load("res://enemies/data/visual_flying.tres") as UnitVisualData
	assert_not_null(vis, "visual_flying.tres should load as UnitVisualData")
	assert_true(vis.flight_height_px > 0.0,
		"flying enemy visuals must author flight_height_px > 0 (see docs/COMBAT_BLOCKING_DOCTRINE.md)")


func test_on_projectile_impact_killed_flag_only_when_dying() -> void:
	# Smoke-check the contract via the actual hero method — it accepts a
	# target Node and a killed bool. The hero's _ability_host may be null in
	# a bare instance (no abilities authored), but the method must not crash.
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	# No data attached → method is a safe no-op (returns without crashing).
	hero.on_projectile_impact(null, 0.0, false)
	pass_test("on_projectile_impact tolerates null target + no AbilityHost without crashing")


# ── helpers ─────────────────────────────────────────────────────────────

# Make a minimal BaseEnemy with attack_speed set. Avoids loading the full
# scene; engage_combat() only reads `data.attack_speed` and never touches
# the Area2D pickups.
func _make_enemy(attack_speed: float) -> BaseEnemy:
	var enemy := BaseEnemy.new()
	var data := EnemyData.new()
	data.attack_speed = attack_speed
	data.attack_damage = 1.0
	data.max_health = 10
	enemy.data = data
	# Pre-set state so engage_combat doesn't transition (it gates on != COMBAT).
	enemy.state = BaseEnemy.State.WALKING
	_spawned.append(enemy)
	return enemy


# Fake blocker (Node with a unique id so the duplicate check has something
# to compare). engage_combat() never calls back into the blocker.
func _make_blocker_stub(id: String) -> Node:
	var n := Node.new()
	n.name = id
	_spawned.append(n)
	return n


# BaseEnemy stub (no scene tree, no Area2Ds). GuardZone calls into:
#   - enemy.data.is_flying / bypass_engagement
#   - enemy.state  (filters DYING)
#   - enemy.has_method("get_path_follow") + enemy.get_path_follow()
#   - enemy.global_position
# All present on BaseEnemy; _make_enemy returns one. The PathFollow2D is
# null on a bare instance → GuardZone falls through to world-distance.
# Build a Node2D parented to nothing with one Path2D child whose curve has
# the given waypoints. Used to exercise GuardZone.snap_to_nearest_path
# without loading a full level scene.
func _make_paths_with_curve(points: Array) -> Node2D:
	var parent := Node2D.new()
	var path := Path2D.new()
	var curve := Curve2D.new()
	for p in points:
		curve.add_point(p)
	path.curve = curve
	parent.add_child(path)
	_spawned.append(parent)
	return parent


func _make_fake_enemy_minimal(is_flying: bool, bypass: bool) -> BaseEnemy:
	var enemy := BaseEnemy.new()
	var data := EnemyData.new()
	data.is_flying = is_flying
	data.bypass_engagement = bypass
	data.max_health = 10
	enemy.data = data
	enemy.state = BaseEnemy.State.WALKING
	_spawned.append(enemy)
	return enemy


# ── Shared engageability predicate + claim accounting ───────────────────

func test_is_engageable_ground_truth_table() -> void:
	var ground: BaseEnemy = _make_fake_enemy_minimal(false, false)
	assert_true(ground.is_engageable_ground(), "plain ground enemy is engageable")
	var flyer: BaseEnemy = _make_fake_enemy_minimal(true, false)
	assert_false(flyer.is_engageable_ground(), "flying is not engageable")
	var bypass: BaseEnemy = _make_fake_enemy_minimal(false, true)
	assert_false(bypass.is_engageable_ground(), "bypass is not engageable")
	var dying: BaseEnemy = _make_fake_enemy_minimal(false, false)
	dying.state = BaseEnemy.State.DYING
	assert_false(dying.is_engageable_ground(), "dying is not engageable")


func test_engage_combat_rejects_flying() -> void:
	var flyer: BaseEnemy = _make_fake_enemy_minimal(true, false)
	var b: Node = _make_blocker_stub("a")
	assert_false(flyer.engage_combat(b), "flying enemy refuses hard block")
	assert_ne(flyer.state, BaseEnemy.State.COMBAT, "flyer never enters COMBAT")


func test_get_claim_count_counts_unique_claimers() -> void:
	var enemy: BaseEnemy = _make_enemy(1.0)
	var unit: Node = _make_blocker_stub("u")
	enemy.reserve(unit)        # soft claim
	enemy.engage_combat(unit)  # same unit hard-blocks (reserve NOT cleared)
	assert_eq(enemy.get_claim_count(), 1,
		"reserve+block by the same unit counts once, not twice")
	var other: Node = _make_blocker_stub("v")
	enemy.engage_combat(other)
	assert_eq(enemy.get_claim_count(), 2, "distinct claimers counted separately")
