extends GutTest

# Phase 2 — new offensive affixes (crit / cleave / execute / vs-type).
# Two layers:
#   1. Wiring: each affix .tres produces the right AbilityData subclass with
#      the rolled value injected into the right property (AffixData spec).
#   2. Behaviour: apply(owner, {target, amount}) deals the expected secondary
#      take_damage packet against a real BaseEnemy (integration — autoloads
#      live in the GUT run).

const _AFFIX_DIR := "res://items/affixes/"

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _affix(id: String) -> AffixData:
	return load(_AFFIX_DIR + id + ".tres") as AffixData


func _enemy(max_hp: int, is_flying: bool = false, enemy_id: String = "enemy_basic") -> BaseEnemy:
	var e := BaseEnemy.new()
	var d := EnemyData.new()
	d.enemy_id = enemy_id
	d.max_health = max_hp
	d.is_flying = is_flying
	d.armor = 0.0
	d.magic_resist = 0.0
	e.data = d
	e.state = BaseEnemy.State.WALKING
	e.current_health = max_hp
	_spawned.append(e)
	return e


func _owner() -> Node2D:
	var o := Node2D.new()
	_spawned.append(o)
	return o


# ── Layer 1: .tres → ability wiring ─────────────────────────────────────

func test_affixes_exist_and_are_on_hit_dealt() -> void:
	for id in ["affix_crit", "affix_cleave", "affix_execute",
			"affix_vs_armored", "affix_vs_flying", "affix_vs_boss"]:
		var a: AffixData = _affix(id)
		assert_not_null(a, "%s loads as AffixData" % id)
		var ab: Resource = a.make_rolled_ability(a.value_max)
		assert_not_null(ab, "%s produces a rolled ability" % id)
		assert_eq(int(ab.trigger), AbilityData.Trigger.ON_HIT_DEALT,
			"%s ability triggers ON_HIT_DEALT" % id)


func test_crit_rolls_into_crit_chance_keeps_fixed_mult() -> void:
	var a: AffixData = _affix("affix_crit")
	var ab = a.make_rolled_ability(0.12)
	assert_true(ab is CritStrikeAbility, "crit affix → CritStrikeAbility")
	assert_almost_eq(ab.crit_chance, 0.12, 0.0001, "rolled value → crit_chance")
	assert_almost_eq(ab.crit_mult, 1.5, 0.0001, "crit_mult stays fixed at 1.5")


func test_conditional_flavours_set_distinct_match_fields() -> void:
	var arm = _affix("affix_vs_armored").make_rolled_ability(0.2)
	var fly = _affix("affix_vs_flying").make_rolled_ability(0.2)
	var bos = _affix("affix_vs_boss").make_rolled_ability(0.2)
	assert_eq(String(arm.match_enemy_id), "armored", "vs_armored matches enemy id")
	assert_true(fly.match_flying, "vs_flying matches flying")
	assert_true(bos.match_boss, "vs_boss matches boss")
	assert_almost_eq(arm.bonus_pct, 0.2, 0.0001, "rolled value → bonus_pct")


func test_offensive_pool_includes_new_affixes() -> void:
	var pool: Resource = load("res://items/pools/pool_weapon_offensive.tres")
	var ids: Array = []
	for a in pool.affixes:
		ids.append(a.affix_id)
	for want in ["affix_crit", "affix_cleave", "affix_execute",
			"affix_vs_armored", "affix_vs_flying", "affix_vs_boss"]:
		assert_true(ids.has(want), "offensive pool carries %s" % want)


# ── Layer 2: behaviour ──────────────────────────────────────────────────

func test_crit_guaranteed_deals_mult_minus_one_times_hit() -> void:
	var ab := CritStrikeAbility.new()
	ab.crit_chance = 1.0
	ab.crit_mult = 2.0
	var e := _enemy(100)
	ab.apply(_owner(), {"target": e, "amount": 10.0})
	# bonus = (2.0-1.0)*10 = 10 physical, armor 0 → -10
	assert_eq(e.current_health, 90, "guaranteed crit dealt (mult-1)*amount")


func test_crit_zero_chance_no_damage() -> void:
	var ab := CritStrikeAbility.new()
	ab.crit_chance = 0.0
	var e := _enemy(100)
	ab.apply(_owner(), {"target": e, "amount": 10.0})
	assert_eq(e.current_health, 100, "0% crit chance never procs")


func test_execute_finishes_low_hp_non_boss() -> void:
	var ab := ExecuteAbility.new()
	ab.hp_threshold = 0.15
	var e := _enemy(100)
	e.current_health = 10  # 10% ≤ 15% threshold
	ab.apply(_owner(), {"target": e, "amount": 5.0})
	assert_true(e.current_health <= 0, "execute finishes a sub-threshold non-boss")


func test_execute_ignores_healthy_target() -> void:
	var ab := ExecuteAbility.new()
	ab.hp_threshold = 0.15
	var e := _enemy(100)
	e.current_health = 80  # 80% > 15%
	ab.apply(_owner(), {"target": e, "amount": 5.0})
	assert_eq(e.current_health, 80, "execute does nothing above threshold")


func test_conditional_vs_flying_only_hits_flyers() -> void:
	var ab := ConditionalDamageAbility.new()
	ab.bonus_pct = 0.5
	ab.match_flying = true
	var flyer := _enemy(100, true)
	ab.apply(_owner(), {"target": flyer, "amount": 10.0})
	assert_eq(flyer.current_health, 95, "vs_flying bonus = 0.5*10 on a flyer")
	var ground := _enemy(100, false)
	ab.apply(_owner(), {"target": ground, "amount": 10.0})
	assert_eq(ground.current_health, 100, "vs_flying does nothing to ground")


func test_cleave_splashes_nearby_excludes_primary() -> void:
	# NOTE: BaseEnemy._ready() recomputes current_health = _effective_max_health()
	# (which BalanceOverrides debug scales by 0.95), so HP/positions MUST be set
	# AFTER the node enters the tree, then read back as the baseline.
	var holder := _owner()
	add_child_autofree(holder)
	var primary := _enemy(100)
	var near := _enemy(100)
	var far := _enemy(100)
	add_child_autofree(primary)
	add_child_autofree(near)
	add_child_autofree(far)
	primary.add_to_group("enemies")
	near.add_to_group("enemies")
	far.add_to_group("enemies")
	primary.global_position = Vector2(0, 0)
	near.global_position = Vector2(40, 0)     # within radius 85
	far.global_position = Vector2(400, 0)     # outside
	primary.current_health = 100
	near.current_health = 100
	far.current_health = 100
	var ab := CleaveOnHitAbility.new()
	ab.cleave_pct = 0.5
	ab.radius = 85.0
	ab.max_targets = 2
	ab.apply(holder, {"target": primary, "amount": 10.0})
	assert_eq(primary.current_health, 100, "cleave never re-hits the primary")
	assert_eq(near.current_health, 95, "cleave splashed the in-radius enemy (0.5*10)")
	assert_eq(far.current_health, 100, "cleave skipped the out-of-radius enemy")
