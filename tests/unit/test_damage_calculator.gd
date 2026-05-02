extends GutTest

const TestHelpers = preload("res://tests/unit/test_helpers.gd")

# Damage math invariants. DamageCalculator is the single math gate for every
# damage source — towers, heroes, soldiers, status effects all flow through
# calculate_damage(amount, type, target). These tests pin the three damage
# types, the armor clamp, and the null-safety paths.

var _targets: Array[Node] = []


func after_each() -> void:
	# Synchronous free — queue_free defers past GUT's orphan check and the
	# fake targets aren't in any tree, so it's safe to free immediately.
	for t in _targets:
		if is_instance_valid(t):
			t.free()
	_targets.clear()


func _make_target(armor: float, magic_resist: float) -> Node:
	var target: Node = TestHelpers.make_fake_target(armor, magic_resist)
	_targets.append(target)
	return target


func test_physical_damage_applies_armor() -> void:
	var target: Node = _make_target(0.3, 0.0)
	var dealt: float = DamageCalculator.calculate_damage(100.0, DamageCalculator.DamageType.PHYSICAL, target)
	assert_almost_eq(dealt, 70.0, 0.001, "100 PHYSICAL into 0.3 armor should deal 70")


func test_magic_damage_applies_resist() -> void:
	var target: Node = _make_target(0.0, 0.5)
	var dealt: float = DamageCalculator.calculate_damage(100.0, DamageCalculator.DamageType.MAGIC, target)
	assert_almost_eq(dealt, 50.0, 0.001, "100 MAGIC into 0.5 magic_resist should deal 50")


func test_true_damage_ignores_resistances() -> void:
	var target: Node = _make_target(1.0, 1.0)
	var dealt: float = DamageCalculator.calculate_damage(100.0, DamageCalculator.DamageType.TRUE, target)
	assert_almost_eq(dealt, 100.0, 0.001, "TRUE damage ignores armor + resist")


func test_armor_clamps_to_zero_floor() -> void:
	# Over-resist (armor=1.5) clamps to 1.0 so PHYSICAL dealt is 0, never negative.
	# Defensive guard — never grant healing via over-resist.
	var target: Node = _make_target(1.5, 0.0)
	var dealt: float = DamageCalculator.calculate_damage(100.0, DamageCalculator.DamageType.PHYSICAL, target)
	assert_eq(dealt, 0.0, "armor=1.5 clamps to 1.0; PHYSICAL dealt should be 0")
	assert_true(dealt >= 0.0, "damage must never be negative")


func test_negative_amount_and_null_target_are_safe() -> void:
	# Negative amount short-circuits to 0 — never used in production but the
	# guard prevents healing via a sign-flipped damage source.
	var target: Node = _make_target(0.0, 0.0)
	assert_eq(DamageCalculator.calculate_damage(-10.0, DamageCalculator.DamageType.PHYSICAL, target), 0.0)
	# Null target is unmitigated (armor=0, resist=0) and must not crash.
	assert_almost_eq(DamageCalculator.calculate_damage(50.0, DamageCalculator.DamageType.PHYSICAL, null), 50.0, 0.001)
