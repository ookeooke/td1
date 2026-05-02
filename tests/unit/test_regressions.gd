extends GutTest

# Incident-locks. Each test references the SESSIONS.md phase that documented
# the bug being prevented. New regressions on these code paths must be loud
# and obvious.

const _TowerStatsCardScript: GDScript = preload("res://ui/TowerStatsCard.gd")

var _spawned: Array[Node] = []
var _saved_round_damage_towers: Dictionary
var _saved_round_damage_hero: float
var _saved_round_damage_soldiers: float


func before_each() -> void:
	_saved_round_damage_towers = RunState.round_damage_towers.duplicate(true)
	_saved_round_damage_hero = RunState.round_damage_hero
	_saved_round_damage_soldiers = RunState.round_damage_soldiers


func after_each() -> void:
	RunState.round_damage_towers = _saved_round_damage_towers
	RunState.round_damage_hero = _saved_round_damage_hero
	RunState.round_damage_soldiers = _saved_round_damage_soldiers
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
