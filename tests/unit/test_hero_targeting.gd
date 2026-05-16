extends GutTest

# Ranged-vs-melee target-picker contract (COMBAT_BLOCKING_DOCTRINE.md).
#
# Regression lock for the bug where ranged target acquisition routed through
# is_engageable_ground() (a MELEE-claim predicate) and silently made
# Mage/Ranger/Necromancer unable to shoot flying or bypass enemies.
#
# Two gates, kept deliberately distinct:
#   _pick_shootable_from(...)      — DYING + targets_flying only; bypass OK
#   BaseEnemy.is_engageable_ground — also rejects flying + bypass (MELEE gate,
#                                    used by _pick_split_target_in_area)
#
# The divergence IS the contract: a flyer this hero targets must be shootable
# yet never melee-engageable. If both gates ever return the same answer for a
# flyer/bypass enemy the bug is back.

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _enemy(is_flying: bool, bypass: bool, dying: bool = false) -> BaseEnemy:
	var e := BaseEnemy.new()
	var d := EnemyData.new()
	d.is_flying = is_flying
	d.bypass_engagement = bypass
	d.max_health = 10
	e.data = d
	e.state = BaseEnemy.State.DYING if dying else BaseEnemy.State.WALKING
	_spawned.append(e)
	return e


func _ranged_hero(targets_flying: bool) -> BaseHero:
	var h := BaseHero.new()
	h.data = HeroData.new()
	h.data.attack_range = 320.0
	h.data.projectile_scene = PackedScene.new()  # ranged archetype
	h.data.targets_flying = targets_flying
	_spawned.append(h)
	return h


# ── Shootable gate: the actual fix ──────────────────────────────────────

func test_shootable_picks_flyer_when_targets_flying() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var flyer: BaseEnemy = _enemy(true, false)
	assert_eq(hero._pick_shootable_from([flyer]), flyer,
		"ranged hero with targets_flying=true MUST be able to shoot a flying enemy")


func test_shootable_skips_flyer_when_not_targets_flying() -> void:
	var hero: BaseHero = _ranged_hero(false)
	var flyer: BaseEnemy = _enemy(true, false)
	assert_null(hero._pick_shootable_from([flyer]),
		"ranged hero with targets_flying=false must NOT pick a flying enemy")


func test_shootable_picks_bypass_enemy() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var byp: BaseEnemy = _enemy(false, true)
	assert_eq(hero._pick_shootable_from([byp]), byp,
		"bypass enemies are shootable (you just can't melee-block them)")


func test_shootable_skips_dying() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var corpse: BaseEnemy = _enemy(false, false, true)
	assert_null(hero._pick_shootable_from([corpse]),
		"no point shooting a DYING enemy")


func test_shootable_picks_ground_enemy() -> void:
	var hero: BaseHero = _ranged_hero(false)
	var ground: BaseEnemy = _enemy(false, false)
	assert_eq(hero._pick_shootable_from([ground]), ground,
		"plain ground enemy is always shootable")


# ── The gate divergence (melee gate must STAY strict) ───────────────────
# 2026-05-15 warrior-vs-flying fix guard: is_engageable_ground() (the melee
# picker's gate) rejects flyers/bypass regardless of targets_flying, while
# the shootable gate accepts them. The two must never agree on a flyer.

func test_flyer_shootable_but_not_melee_engageable() -> void:
	var hero: BaseHero = _ranged_hero(true)  # targets_flying must NOT leak into melee
	var flyer: BaseEnemy = _enemy(true, false)
	assert_eq(hero._pick_shootable_from([flyer]), flyer,
		"flyer is shootable for a targets_flying hero")
	assert_false(flyer.is_engageable_ground(),
		"same flyer is NEVER melee-engageable — gates must diverge")


func test_bypass_shootable_but_not_melee_engageable() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var byp: BaseEnemy = _enemy(false, true)
	assert_eq(hero._pick_shootable_from([byp]), byp,
		"bypass enemy is shootable")
	assert_false(byp.is_engageable_ground(),
		"bypass enemy is never melee-engageable — gates must diverge")


func test_ground_enemy_passes_both_gates() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var ground: BaseEnemy = _enemy(false, false)
	assert_eq(hero._pick_shootable_from([ground]), ground,
		"ground enemy shootable")
	assert_true(ground.is_engageable_ground(),
		"ground enemy also melee-engageable — both gates agree only here")


# ── Split priority preserved on the new picker ──────────────────────────

func test_shootable_prefers_fewer_blockers() -> void:
	var hero: BaseHero = _ranged_hero(true)
	var contested: BaseEnemy = _enemy(false, false)
	var free_e: BaseEnemy = _enemy(false, false)
	var b1 := Node.new()
	var b2 := Node.new()
	_spawned.append(b1)
	_spawned.append(b2)
	contested._blockers = [b1, b2]  # 2 claims
	assert_eq(hero._pick_shootable_from([contested, free_e]), free_e,
		"split rule intact: fewest-blockers enemy wins (spread, don't dogpile)")
