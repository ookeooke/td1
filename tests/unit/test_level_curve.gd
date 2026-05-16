extends GutTest

# Phase 2 — HeroLevelCurveData contract.
#
# The curve makes per-level growth + skill-point pacing + slot-unlock levels
# + affinity ranks authorable. Default (unauthored) curve MUST reproduce the
# pre-Phase-2 hardcoded numbers exactly (byte-identical backward compat).

func _hero() -> HeroData:
	var h := HeroData.new()
	h.hero_id = "hero_test"
	h.max_health = 100.0
	h.attack_damage = 10.0
	return h


# ── Byte-identical default growth (consts: +15% HP, +10% dmg per level) ──

func test_default_curve_byte_identical_growth() -> void:
	var hd: HeroData = _hero()
	var l1: Dictionary = BaseHero.compute_base_stats(hd, 1)
	for lvl in [1, 5, 10]:
		var s: Dictionary = BaseHero.compute_base_stats(hd, lvl)
		# Ratio cancels upgrade/override multipliers — isolates growth.
		var hp_ratio: float = s["max_health"] / l1["max_health"]
		var dmg_ratio: float = s["damage"] / l1["damage"]
		assert_almost_eq(hp_ratio, 1.0 + float(lvl - 1) * 0.15, 0.0001,
			"L%d HP growth must equal legacy +15%%/level" % lvl)
		assert_almost_eq(dmg_ratio, 1.0 + float(lvl - 1) * 0.10, 0.0001,
			"L%d damage growth must equal legacy +10%%/level" % lvl)


func test_default_get_level_curve_never_null() -> void:
	assert_not_null(_hero().get_level_curve(),
		"get_level_curve() always returns a valid curve (shared default)")


# ── Skill points per level ──────────────────────────────────────────────

func test_points_default_one_per_level() -> void:
	var c := HeroLevelCurveData.new()
	assert_eq(c.points_for_level(1), 0, "L1 is the start — no grant")
	var total: int = 0
	for lvl in range(2, 11):
		assert_eq(c.points_for_level(lvl), 1, "default = +1 at L%d" % lvl)
		total += c.points_for_level(lvl)
	assert_eq(total, 9, "L1→10 grants 9 points total (historical)")


func test_authored_points_override() -> void:
	var c := HeroLevelCurveData.new()
	c.skill_points_by_level = {5: 3}
	assert_eq(c.points_for_level(5), 3, "authored level overrides to +3")
	assert_eq(c.points_for_level(4), 1, "unlisted levels keep historical +1")
	assert_eq(c.points_for_level(6), 1, "unlisted levels keep historical +1")


# ── Active-slot unlock levels ───────────────────────────────────────────

func test_slot_unlock_default_levels() -> void:
	var c := HeroLevelCurveData.new()
	assert_eq(c.active_slot_unlock_levels, [1, 8] as Array[int],
		"default unlock levels == legacy ACTIVE_SLOT_UNLOCK_LEVELS")


func test_slot_unlock_authored_levels() -> void:
	var c := HeroLevelCurveData.new()
	c.active_slot_unlock_levels = [1, 6] as Array[int]
	# Cap = count of thresholds <= level (mirrors LoadoutState.get_active_slot_cap).
	var cap_at := func(lvl: int) -> int:
		var n: int = 0
		for t in c.active_slot_unlock_levels:
			if lvl >= int(t):
				n += 1
		return maxi(1, n)
	assert_eq(cap_at.call(5), 1, "only L1 slot before L6")
	assert_eq(cap_at.call(6), 2, "3rd slot opens at L6, not L8")


# ── Affinity rank gate (closes Phase 1 min_affinity_rank) ───────────────

func test_affinity_rank_default_always_one() -> void:
	var c := HeroLevelCurveData.new()
	for lvl in [1, 5, 10]:
		assert_eq(c.affinity_rank_for_level(lvl), 1,
			"default ⇒ rank 1 at every level (Phase 1 behavior unchanged)")


func test_affinity_rank_authored_thresholds() -> void:
	var c := HeroLevelCurveData.new()
	c.affinity_rank_by_level = {1: 1, 5: 2, 9: 3}
	assert_eq(c.affinity_rank_for_level(4), 1, "rank 1 below L5")
	assert_eq(c.affinity_rank_for_level(5), 2, "rank 2 at L5")
	assert_eq(c.affinity_rank_for_level(12), 3, "rank 3 at/after L9")
