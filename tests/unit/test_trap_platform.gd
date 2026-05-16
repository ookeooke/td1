extends GutTest

# Phase 5 — Trap platform.
#
# Trap is script-driven (no .tscn) so the risky logic is unit-testable:
# radius+engageable filtering, DamageCalculator-routed detonation, arm/
# lifetime stepping. Flyers are excluded via the SHARED is_engageable_
# ground() gate (never re-derived — Blocker invariant #1). Tree-dependent
# placement (navmesh snap, max_active free-oldest) is editor-verified, like
# SummonSoldiers scene behavior (see test_combat_blocking.gd note).

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _enemy(is_flying: bool, hp: int = 100) -> BaseEnemy:
	var e := BaseEnemy.new()
	var d := EnemyData.new()
	d.is_flying = is_flying
	d.max_health = hp
	e.data = d
	e.current_health = hp
	e.state = BaseEnemy.State.WALKING
	_spawned.append(e)
	return e


func _trap(radius: float = 80.0, dmg: float = 20.0) -> Trap:
	var t := Trap.new()
	var td := TrapData.new()
	td.trap_id = "trap_test"
	td.radius = radius
	td.damage = dmg
	td.damage_type = 0
	td.arm_time = 0.5
	td.lifetime = 10.0
	t.setup(td, null)
	_spawned.append(t)
	return t


# ── TrapData sanity ─────────────────────────────────────────────────────

func test_trap_data_defaults_sane() -> void:
	var td := TrapData.new()
	assert_gt(td.max_active, 0, "max_active >= 1")
	assert_gt(td.lifetime, td.arm_time, "lifetime must exceed arm_time")
	assert_gt(td.radius, 0.0, "radius > 0")


# ── Radius + engageable filter (shared gate, flyers excluded) ───────────

func test_engageable_in_radius_includes_near_ground() -> void:
	var t: Trap = _trap(80.0)
	t.global_position = Vector2.ZERO
	var g: BaseEnemy = _enemy(false)
	g.global_position = Vector2(50, 0)
	assert_eq(t._engageable_in_radius([g]), [g], "near ground enemy is in range")


func test_engageable_in_radius_excludes_far() -> void:
	var t: Trap = _trap(80.0)
	t.global_position = Vector2.ZERO
	var g: BaseEnemy = _enemy(false)
	g.global_position = Vector2(500, 0)
	assert_eq(t._engageable_in_radius([g]).size(), 0, "far enemy excluded")


func test_engageable_in_radius_excludes_flyer() -> void:
	var t: Trap = _trap(80.0)
	t.global_position = Vector2.ZERO
	var f: BaseEnemy = _enemy(true)
	f.global_position = Vector2(20, 0)
	assert_eq(t._engageable_in_radius([f]).size(), 0,
		"flyer excluded via shared is_engageable_ground() (invariant #1)")


# ── Detonation routes damage through take_damage / DamageCalculator ─────

func test_detonate_damages_ground_enemy() -> void:
	var t: Trap = _trap(80.0, 20.0)
	var g: BaseEnemy = _enemy(false, 100)
	t.detonate([g])
	assert_lt(g.current_health, 100, "trap dealt damage via take_damage")
	assert_true(t._spent, "trap is one-shot — spent after detonation")


func test_detonate_is_one_shot() -> void:
	var t: Trap = _trap()
	var g: BaseEnemy = _enemy(false, 100)
	t.detonate([g])
	var hp_after_first: int = g.current_health
	t.detonate([g])  # second call must be a no-op (already spent)
	assert_eq(g.current_health, hp_after_first, "spent trap cannot detonate again")


# ── Arm / lifetime stepping ─────────────────────────────────────────────

func test_tick_arms_after_arm_time() -> void:
	var t: Trap = _trap()  # arm_time 0.5
	t.tick(0.3)
	assert_false(t._armed, "not armed before arm_time")
	t.tick(0.3)  # total 0.6 >= 0.5
	assert_true(t._armed, "armed after arm_time elapsed")


func test_tick_despawns_at_lifetime() -> void:
	var t: Trap = _trap()  # lifetime 10.0
	add_child_autofree(t)  # in-tree so queue_free is observable
	t.tick(11.0)
	assert_true(t.is_queued_for_deletion(),
		"trap auto-despawns once lifetime elapses")
