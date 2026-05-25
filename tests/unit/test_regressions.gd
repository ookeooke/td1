extends GutTest

# Incident-locks. Each test references the SESSIONS.md phase that documented
# the bug being prevented. New regressions on these code paths must be loud
# and obvious.

const _TowerStatsCardScript: GDScript = preload("res://ui/TowerStatsCard.gd")

var _spawned: Array[Node] = []
var _saved_round_damage_towers: Dictionary
var _saved_round_damage_hero: float
var _saved_round_damage_soldiers: float
var _saved_runstats_current: Dictionary
var _saved_runstats_start_time_msec: int
var _saved_runstats_latest_wave_num: int
var _saved_runstats_last_gold: int
var _saved_runstats_pre_wave_gold_spent: int


func before_each() -> void:
	_saved_round_damage_towers = RunState.round_damage_towers.duplicate(true)
	_saved_round_damage_hero = RunState.round_damage_hero
	_saved_round_damage_soldiers = RunState.round_damage_soldiers
	_saved_runstats_current = RunStats._current.duplicate(true)
	_saved_runstats_start_time_msec = RunStats._start_time_msec
	_saved_runstats_latest_wave_num = RunStats._latest_wave_num
	_saved_runstats_last_gold = RunStats._last_gold
	_saved_runstats_pre_wave_gold_spent = RunStats._pre_wave_gold_spent


func after_each() -> void:
	RunState.round_damage_towers = _saved_round_damage_towers
	RunState.round_damage_hero = _saved_round_damage_hero
	RunState.round_damage_soldiers = _saved_round_damage_soldiers
	RunStats._current = _saved_runstats_current
	RunStats._start_time_msec = _saved_runstats_start_time_msec
	RunStats._latest_wave_num = _saved_runstats_latest_wave_num
	RunStats._last_gold = _saved_runstats_last_gold
	RunStats._pre_wave_gold_spent = _saved_runstats_pre_wave_gold_spent
	# Synchronous free for any node not added via add_child_autofree —
	# queue_free defers past GUT's orphan check.
	for n in _spawned:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()
	_spawned.clear()


func _track(n: Node) -> Node:
	_spawned.append(n)
	return n


# Phase 47d-20: a lethal hit on the exact frame an enemy reached the path
# end could double-fire (die + reach_end), duplicating gold and lives. Fix
# was a state==DYING short-circuit at the top of _die() / _reach_end().
func test_enemy_die_double_call_emits_once() -> void:
	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	assert_not_null(enemy.data, "fixture: enemy_basic must be in registry")
	add_child_autofree(enemy)

	# Lambda captures are by-value; use a 1-element array as a mutable cell.
	var emit_count: Array[int] = [0]
	var listener: Callable = func(_e: Node, _gold: int) -> void:
		emit_count[0] += 1
	EventBus.enemy_died.connect(listener)

	enemy._die()
	enemy._die()  # second call must be a no-op (state == DYING)

	EventBus.enemy_died.disconnect(listener)
	assert_eq(emit_count[0], 1, "enemy_died must fire exactly once across two _die() calls")


# Damage tally caps at remaining HP, so a 5 HP enemy taking a 100-damage hit
# attributes 5 (not 100) to the source. Prevents inflated leaderboard
# numbers when overkill happens.
func test_round_damage_attribution_capped_at_actual() -> void:
	# RunState.record_round_damage receives `actual` (already capped by the
	# caller in BaseEnemy.take_damage). Test the contract: we pass an
	# already-capped value and confirm it's stored verbatim.
	RunState.round_damage_towers = {}
	var tower: BaseTower = _track(BaseTower.new())
	# Caller's cap rule: actual = minf(final_damage, current_health).
	var current_health: float = 5.0
	var raw_final: float = 100.0
	var actual: float = minf(raw_final, current_health)
	RunState.record_round_damage(tower, actual)
	var entry: Dictionary = RunState.round_damage_towers[tower.get_instance_id()]
	assert_almost_eq(float(entry["total"]), 5.0, 0.001,
		"overkill must store actual (capped to remaining HP), not raw final")


# Phase 13+: status effects keyed by id. Reapplying same id REPLACES (refreshes
# duration). It does NOT stack — reapplying SlowEffect(0.5, 5.0) over an
# existing SlowEffect(0.5, 1.0) results in one entry with duration 5.0.
func test_status_effect_reapply_refreshes_not_stacks() -> void:
	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy)

	var slow1: SlowEffect = SlowEffect.new(0.5, 1.0)
	var slow2: SlowEffect = SlowEffect.new(0.5, 5.0)

	enemy.apply_status_effect(slow1)
	enemy.apply_status_effect(slow2)

	assert_eq(enemy._effects.size(), 1, "reapplying same status_id replaces, not stacks")
	assert_eq(enemy._effects["slow"].duration, 5.0, "duration matches the latest reapply")


# Code review 2026-05-25: BaseEnemy must tick DoT effects, not only expire
# their duration. Hero/soldier carriers already did this; enemies need the
# same contract for tower/hero-applied burn or poison.
func test_enemy_dot_effect_ticks_damage() -> void:
	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	assert_not_null(enemy.data, "fixture: enemy_basic must be in registry")
	add_child_autofree(enemy)
	enemy.current_health = 100

	var burn: BurnEffect = BurnEffect.new(10.0, 1.0, null, DamageCalculator.DamageType.TRUE)
	enemy.apply_status_effect(burn)
	enemy._tick_effects(0.5)

	assert_eq(enemy.current_health, 95, "enemy DoT tick deals dps * tick_interval damage")


# Phase 47d-9: TowerUpgradeData fields default to 0 (sentinel for "not
# overridden"); upgrade-time merge falls back to base TowerData. Without the
# fallback, upgrading a tower whose base had a slow trait silently lost it.
func test_tower_upgrade_data_inherits_slow_from_base() -> void:
	# Local script aliases — avoid SHADOWED_GLOBAL_IDENTIFIER on the class names.
	var UpgradeScript: GDScript = preload("res://towers/TowerUpgradeData.gd")
	var BaseScript: GDScript = preload("res://towers/TowerData.gd")

	var base: TowerData = BaseScript.new()
	base.on_hit_slow_factor = 0.4
	base.on_hit_slow_duration = 2.0
	base.damage = 10.0
	base.attack_range = 200.0
	base.attack_speed = 1.0

	var upgrade: Resource = UpgradeScript.new()
	# Upgrade leaves slow fields at 0.0 → inherits base.
	upgrade.damage = 15
	upgrade.attack_range = 220
	upgrade.attack_speed = 1.2

	var rows: Array = upgrade.get_preview_stats(base)
	# Find the "Slow" row in the preview — proves the inherited field surfaced.
	var found_slow: bool = false
	for row in rows:
		if row.get("label", "") == "Slow":
			found_slow = true
			# 0.4 base * 100 = 40 (% display)
			assert_almost_eq(float(row.get("value", 0.0)), 40.0, 0.001)
	assert_true(found_slow, "Slow row should inherit from base when upgrade leaves it 0")


# TowerStatsCard._diff_line builds the upgrade-preview arrow format
# documented in CLAUDE.md ("Dmg 4→7   Rng 400→437   Spd 1.2→1.35"). The
# format is mobile-readable + has been the spec since Phase 47d-2.
func test_tower_stats_card_diff_line_format() -> void:
	var card: Node = _track(_TowerStatsCardScript.new())
	# _diff_line is pure string math — does not touch @onready members.
	var diff: String = card._diff_line("Dmg 4   Rng 400   Spd 1.2", "Dmg 7   Rng 437   Spd 1.35")
	assert_eq(diff, "Dmg 4→7   Rng 400→437   Spd 1.2→1.35")


# Phase 46c style fallback: querying an unknown id through a type-scoped
# unlock check returns false safely. The fix moved the dispatch to type-
# specific find_*() so an unknown id can't accidentally resolve to a
# wrongly-typed Resource.
func test_unlock_unknown_id_returns_false_safely() -> void:
	# Avoid pollution from prior tests.
	var saved: Array[String] = MetaProgression.unlocked_content.duplicate()
	MetaProgression.unlocked_content = []
	var saved_thresholds: Dictionary = UnlockManager._star_thresholds.duplicate(true)
	UnlockManager._star_thresholds = {}

	assert_false(UnlockManager.is_tower_unlocked("tower_does_not_exist_xyz"))
	assert_false(UnlockManager.is_hero_unlocked("hero_does_not_exist_xyz"))

	MetaProgression.unlocked_content = saved
	UnlockManager._star_thresholds = saved_thresholds


# Bundle B: stun is a behavior gate, not a state. An enemy in COMBAT with a
# blocker, stunned and then un-stunned, must remain in COMBAT — the old
# implementation forced State.STUNNED on apply and State.WALKING on expiry,
# silently dropping the engagement while blockers were still in _blockers.
func test_stunned_blocked_enemy_stays_in_combat() -> void:
	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	assert_not_null(enemy.data, "fixture: enemy_basic must be in registry")
	add_child_autofree(enemy)

	# Stand-in blocker — engage_combat only checks instance validity, not type.
	var blocker: Node = _track(Node.new())
	add_child_autofree(blocker)
	assert_true(enemy.engage_combat(blocker), "fixture: blocker must engage")
	assert_eq(enemy.state, BaseEnemy.State.COMBAT, "fixture: enemy enters COMBAT")

	var stun: StunEffect = StunEffect.new(0.05)
	enemy.apply_status_effect(stun)
	assert_eq(enemy.state, BaseEnemy.State.COMBAT,
		"applying stun must NOT swap COMBAT for a stun state")
	assert_true(enemy._effects.has("stun"), "stun effect tracked in _effects")

	# Force the effect past its duration and tick — stun should clear,
	# blocker should still be engaged, state stays COMBAT.
	enemy._effects["stun"].duration = -0.01
	enemy._tick_effects(0.0)
	assert_false(enemy._effects.has("stun"), "stun expired and removed")
	assert_eq(enemy.state, BaseEnemy.State.COMBAT,
		"stun expiry must NOT downgrade COMBAT to WALKING")
	assert_true(enemy._blockers.has(blocker), "blocker must still be engaged")


# Bundle A: BaseHero._die() must be idempotent. Without the State.DEAD
# short-circuit, a second call (from an ability ON_DEATH path, an effect
# tick, etc.) would emit hero_died twice and schedule two respawn timers.
# Mirror of test_enemy_die_double_call_emits_once.
func test_hero_die_double_call_emits_once() -> void:
	var hero: BaseHero = _track(BaseHero.new())
	_add_hero_required_children(hero)
	add_child_autofree(hero)
	# Keep data null until after _ready() so this narrow idempotency fixture
	# does not schedule BaseHero's deferred hero_spawned signal and wake
	# encyclopedia/VFX autoload listeners after GUT frees the temporary node.
	await get_tree().process_frame
	hero.data = ContentRegistry.find_hero("hero_warrior")
	assert_not_null(hero.data, "fixture: hero_warrior must be in registry")
	hero.current_health = 1

	var emit_count: Array[int] = [0]
	var listener: Callable = func() -> void:
		emit_count[0] += 1
	EventBus.hero_died.connect(listener)

	hero._die()
	hero._die()  # second call must be a no-op (state == DEAD)

	EventBus.hero_died.disconnect(listener)
	assert_eq(emit_count[0], 1, "hero_died must fire exactly once across two _die() calls")


# L5 balance telemetry depends on this: with early-call overlap, enemies from
# wave N can leak after wave N+1 starts. RunStats must attribute leaks by the
# enemy's spawn wave_index, not by one shared "current wave" counter.
func test_runstats_lives_lost_per_wave_uses_enemy_wave_index() -> void:
	RunStats._start_time_msec = Time.get_ticks_msec()
	RunStats._current = {
		"lives_lost_per_wave": [],
		"_pending_wave_leak_by_wave": {},
		"gold_timeline": [],
		"waves": [],
	}

	RunStats._on_wave_started(5, [])
	RunStats._on_wave_started(6, [])

	var wave5_enemy: Node = _track(Node.new())
	wave5_enemy.set_meta("wave_index", 4)
	var wave6_enemy: Node = _track(Node.new())
	wave6_enemy.set_meta("wave_index", 5)

	RunStats._on_enemy_reached_end(wave5_enemy, 2)
	RunStats._on_enemy_reached_end(wave6_enemy, 1)
	RunStats._on_wave_completed(6)
	RunStats._on_wave_completed(5)

	var leaks: Array = RunStats._current["lives_lost_per_wave"]
	assert_eq(leaks.size(), 6, "array must preserve 1-based wave slots even when waves clear out of order")
	assert_eq(int(leaks[4]), 2, "wave 5 leak is stored in slot 5")
	assert_eq(int(leaks[5]), 1, "wave 6 leak is stored in slot 6")


func test_runstats_wave_block_tracks_pressure_and_economy() -> void:
	RunState.gold = 100
	RunStats._start_time_msec = Time.get_ticks_msec()
	RunStats._latest_wave_num = 0
	RunStats._last_gold = 100
	RunStats._pre_wave_gold_spent = 0
	RunStats._current = {
		"lives_lost_per_wave": [],
		"_pending_wave_leak_by_wave": {},
		"gold_timeline": [],
		"waves": [],
	}

	RunState.gold = 70
	RunStats._on_gold_changed(70) # pre-W1 build spend should attach to W1.
	RunStats._on_wave_started(1, [])

	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	assert_not_null(enemy.data, "fixture: enemy_basic must be in registry")
	# hit_landed fires after BaseEnemy.take_damage subtracts ceil(final). A
	# 5 HP enemy hit for 100 damage is therefore at -95 when RunStats sees it.
	enemy.current_health = -95
	enemy.set_meta("wave_index", 0)
	RunStats._on_enemy_spawned(enemy, "main")
	RunStats._on_hit_landed(enemy, null, 100.0, 0)
	RunStats._on_enemy_reached_end(enemy, 1)
	RunStats._on_wave_completed(1)

	var waves: Array = RunStats._current["waves"]
	assert_eq(waves.size(), 1)
	var w: Dictionary = waves[0]
	assert_eq(int(w["wave"]), 1)
	assert_eq(int(w["enemies_spawned"]), 1)
	assert_eq(int(w["enemies_leaked"]), 1)
	assert_eq(int(w["lives_lost"]), 1)
	assert_eq(int(w["gold_spent"]), 30)
	assert_eq(int(w["gold_on_clear"]), 70)
	assert_eq(int(w["peak_concurrent_enemies"]), 1)
	assert_almost_eq(float(w["damage_total"]), 5.0, 0.001, "per-wave damage should cap obvious overkill")
	var leak_events: Array = w["leaks"]
	assert_eq(leak_events.size(), 1)


# P1 (2026-05-26): a ranged hero whose focus shot target leaks out of
# attack_range while _auto_engage_extras had hard-blocked a *different*
# enemy used to drop to IDLE with that block stranded — frozen enemy, no
# fighter. The else-branch must promote the oldest valid _blocked_enemies
# entry to focus and stay in COMBAT instead of orphaning the lock.
func test_hero_shot_loss_promotes_existing_block() -> void:
	var hero: BaseHero = _track(BaseHero.new())
	_add_hero_required_children(hero)
	add_child_autofree(hero)
	await get_tree().process_frame
	hero.data = ContentRegistry.find_hero("hero_mage")
	assert_not_null(hero.data, "fixture: hero_mage must be in registry")

	var enemy_a: BaseEnemy = _track(BaseEnemy.new())
	enemy_a.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy_a)
	var enemy_b: BaseEnemy = _track(BaseEnemy.new())
	enemy_b.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy_b)
	await get_tree().process_frame

	# Pure shot focus on A, hard block on B (mirrors _auto_engage_extras
	# committing to a second target while the focus is being shot from far).
	hero._target_enemy = enemy_a
	hero._blocked_enemies = [enemy_b]
	enemy_b.engage_combat(hero)
	hero.change_state(BaseHero.State.COMBAT)

	# attack_range_area has no overlapping areas in this fixture, so the
	# "enemy left attack range" branch fires for A. A was NOT in
	# _blocked_enemies → was_blocking is false → falls into the else branch,
	# which used to go straight to IDLE.
	hero._attack_step(0.0)

	assert_eq(hero._target_enemy, enemy_b,
		"hero must promote the existing block to focus instead of orphaning it")
	assert_eq(hero.state, BaseHero.State.COMBAT,
		"promoted block keeps the hero in COMBAT — not IDLE")
	assert_true(hero._blocked_enemies.has(enemy_b),
		"existing hard block must survive the focus drop")
	assert_true(enemy_b._blockers.has(hero),
		"enemy B must still register the hero as a blocker")


# P2 (2026-05-26): a soldier whose soft claim times out (path-blocked /
# unreachable straggler) used to release the claim and then immediately
# re-pick the same enemy on the next scan, looping forever. Mirror of the
# hero stuck-recovery blacklist. Doctrine invariant 4 — "watchdog must
# make progress, not just reset."
func test_soldier_giveup_blacklist_skips_re_acquire() -> void:
	var soldier: BaseSoldier = _track(BaseSoldier.new())
	var enemy: BaseEnemy = _track(BaseEnemy.new())
	enemy.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy)
	await get_tree().process_frame

	assert_false(soldier._is_given_up(enemy),
		"fixture: fresh enemy must not be blacklisted")
	soldier._note_giveup(enemy)
	assert_true(soldier._is_given_up(enemy),
		"watchdog must blacklist the timed-out enemy so the next scan picks a different one")
	# Expire the cooldown manually and confirm the blacklist self-purges.
	soldier._giveup_until[enemy] = Time.get_ticks_msec() - 1
	assert_false(soldier._is_given_up(enemy),
		"blacklist must self-expire so the soldier can re-acquire later")


# P3 (2026-05-26): soldier _sync_claim() swapped _claimed_enemy without
# resetting _claim_age, so a fresh target could inherit a near-expired
# timer and be dropped immediately. _release_claim had the same gap.
# Hero already reset; soldier must mirror.
func test_soldier_sync_claim_resets_claim_age() -> void:
	var soldier: BaseSoldier = _track(BaseSoldier.new())
	var enemy_a: BaseEnemy = _track(BaseEnemy.new())
	enemy_a.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy_a)
	var enemy_b: BaseEnemy = _track(BaseEnemy.new())
	enemy_b.data = ContentRegistry.find_enemy("enemy_basic")
	add_child_autofree(enemy_b)
	await get_tree().process_frame

	soldier._charge_target = enemy_a
	soldier._sync_claim()
	assert_eq(soldier._claimed_enemy, enemy_a, "fixture: initial claim is A")
	# Simulate the watchdog ticking up most of the timeout on A.
	soldier._claim_age = 3.5

	# Swap to B — the fresh target must get a fresh timer, otherwise the
	# next physics tick would push _claim_age past CLAIM_TIMEOUT and drop B
	# before the soldier can reach it.
	soldier._charge_target = enemy_b
	soldier._sync_claim()
	assert_eq(soldier._claimed_enemy, enemy_b, "claim must swap to B")
	assert_almost_eq(soldier._claim_age, 0.0, 0.0001,
		"_claim_age must reset to 0 when the claim swaps targets")

	# _release_claim must also reset, mirror of BaseHero.
	soldier._claim_age = 2.0
	soldier._release_claim()
	assert_almost_eq(soldier._claim_age, 0.0, 0.0001,
		"_claim_age must reset to 0 on _release_claim")


func _add_hero_required_children(hero: BaseHero) -> void:
	_add_area_with_shape(hero, "AttackRange")
	_add_area_with_shape(hero, "EngageRange")
	var nav_agent := NavigationAgent2D.new()
	nav_agent.name = "NavigationAgent2D"
	hero.add_child(nav_agent)
	_add_area_with_shape(hero, "SeekRange")


func _add_area_with_shape(parent: Node, area_name: String) -> void:
	var area := Area2D.new()
	area.name = area_name
	parent.add_child(area)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	area.add_child(shape)
