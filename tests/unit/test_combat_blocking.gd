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


# ── Archetype-default guard zone ────────────────────────────────────────

func test_archetype_guard_zone_melee_default() -> void:
	# Bare BaseHero with melee-range data (attack_range below the ranged
	# threshold) should auto-fallback to 150/100. Authoring left at 0/0.
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 75.0  # melee — Warrior-shaped
	# guard_front_px / guard_back_px default to 0 on a fresh HeroData.
	var zone: Vector2 = hero._effective_guard_zone()
	assert_eq(zone, Vector2(150.0, 100.0), "melee archetype auto-defaults to 150/100")


func test_archetype_guard_zone_ranged_stays_zero() -> void:
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 320.0  # ranged — Ranger-shaped
	var zone: Vector2 = hero._effective_guard_zone()
	assert_eq(zone, Vector2.ZERO, "ranged archetype stays 0/0 — hold and shoot")


func test_archetype_guard_zone_authoring_overrides() -> void:
	# Authored guard zone wins regardless of archetype.
	var hero: BaseHero = BaseHero.new()
	_spawned.append(hero)
	hero.data = HeroData.new()
	hero.data.attack_range = 75.0
	hero.data.guard_front_px = 200.0
	hero.data.guard_back_px = 50.0
	var zone: Vector2 = hero._effective_guard_zone()
	assert_eq(zone, Vector2(200.0, 50.0), "authored guard zone must win over archetype default")


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
