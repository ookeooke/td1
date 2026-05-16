extends GutTest

# Phase 1 — HeroItemAffinityData grant contract.
#
# Tests the pure matcher BaseHero._affinities_to_grant(affinities, tag_set,
# rank): a hero gains an affinity's bonus_abilities iff its rank is met AND
# every required_item_tag is present among equipped items' tags. Off-affinity
# items still work (they just never satisfy a required-tag set). No affinities
# authored ⇒ no grant (byte-identical backward compat).
#
# Phase 6 / R1 — parity regression lock: compute_stats_for (the display
# path: HeroStats.effective_for / EquipmentScreen / HeroesHub) MUST include
# affinity-granted stat bonuses, else the dressing room shows lower numbers
# than the live hero (Preventive Bug Rule 1). These tests FAIL before the R1
# fix and PASS after; the no-affinity branch locks value-identical backward
# compat.

var _added_bases: Array = []


func after_each() -> void:
	# Restore ContentRegistry.item_bases (R1 parity tests append a temp base).
	for b in _added_bases:
		ContentRegistry.item_bases.erase(b)
	_added_bases.clear()


func _register_base(base_id: String, tags: Array) -> ItemBase:
	var b := ItemBase.new()
	b.base_id = base_id
	b.slot = 0
	var it: Array[String] = []
	for t in tags:
		it.append(t)
	b.item_tags = it
	ContentRegistry.item_bases.append(b)
	_added_bases.append(b)
	return b


func _instance(base_id: String) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.base_id = base_id
	return inst


func _stat_mod(dmg_flat: float) -> StatModifierAbility:
	var m := StatModifierAbility.new()
	m.damage_flat = dmg_flat
	return m

func _affinity(req: Array, abilities: Array, min_rank: int = 1) -> HeroItemAffinityData:
	var a := HeroItemAffinityData.new()
	a.affinity_id = "aff_test"
	var rt: Array[String] = []
	for t in req:
		rt.append(t)
	a.required_item_tags = rt
	var ba: Array[Resource] = []
	for ab in abilities:
		ba.append(ab)
	a.bonus_abilities = ba
	a.min_affinity_rank = min_rank
	return a


func _ability() -> AbilityData:
	return AbilityData.new()


func _tags(arr: Array) -> Dictionary:
	var d: Dictionary = {}
	for t in arr:
		d[t] = true
	return d


# ── Backward compat ─────────────────────────────────────────────────────

func test_backward_compat_no_affinities_grants_nothing() -> void:
	assert_eq(BaseHero._affinities_to_grant([], _tags(["sword"]), 1).size(), 0,
		"no authored affinities → zero grants (byte-identical default)")


# ── Grant / no-grant matching ───────────────────────────────────────────

func test_warrior_sword_grants_bonus() -> void:
	var ab := _ability()
	var aff := _affinity(["sword"], [ab])
	var got: Array = BaseHero._affinities_to_grant([aff], _tags(["sword"]), 1)
	assert_eq(got.size(), 1, "sword affinity satisfied by an equipped sword")
	assert_eq(got[0], ab, "the affinity's authored bonus ability is returned")


func test_mage_sword_no_mastery() -> void:
	# Mage has NO sword affinity authored — equipping a sword grants no mastery
	# (its stats still apply elsewhere; that is not this matcher's concern).
	assert_eq(BaseHero._affinities_to_grant([], _tags(["sword"]), 1).size(), 0,
		"hero without a matching affinity gets no bonus from a sword")


func test_unequip_detaches() -> void:
	var aff := _affinity(["sword"], [_ability()])
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword"]), 1).size(), 1,
		"granted while sword equipped")
	assert_eq(BaseHero._affinities_to_grant([aff], _tags([]), 1).size(), 0,
		"removed once sword unequipped (empty tag set)")


func test_partial_tags_no_grant() -> void:
	var aff := _affinity(["sword", "shield"], [_ability()])
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword"]), 1).size(), 0,
		"ALL required tags must be present — sword alone is not enough")
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword", "shield"]), 1).size(), 1,
		"granted when both sword and shield are present")


func test_empty_required_tags_never_grants() -> void:
	var aff := _affinity([], [_ability()])
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword"]), 1).size(), 0,
		"an affinity with no required tags never qualifies (would be a stat item)")


# ── Rank gate (Phase 2 wires real ranks; default rank 1) ────────────────

func test_rank_gate_blocks_higher_rank() -> void:
	var aff := _affinity(["sword"], [_ability()], 2)
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword"]), 1).size(), 0,
		"rank-2 affinity dormant at rank 1")
	assert_eq(BaseHero._affinities_to_grant([aff], _tags(["sword"]), 2).size(), 1,
		"granted once rank requirement met")


# ── R1 parity regression lock — compute_stats_for includes affinities ───

func test_compute_stats_for_includes_affinity_bonus() -> void:
	# FAILS before R1 (compute_stats_for ignored affinities), PASSES after.
	_register_base("base_test_sword", ["sword"])
	var aff := _affinity(["sword"], [_stat_mod(5.0)])  # +5 flat damage
	var hd := HeroData.new()
	hd.hero_id = "hero_parity"
	hd.attack_damage = 10.0
	var ia: Array[Resource] = [aff]
	hd.item_affinities = ia
	var stats: Dictionary = BaseHero.compute_stats_for(hd, 1, [_instance("base_test_sword")])
	assert_almost_eq(float(stats.get("damage", 0.0)), 15.0, 0.001,
		"display must include affinity +5 (10 base) — Preventive Bug Rule 1")


func test_compute_stats_for_no_affinity_value_identical() -> void:
	# Backward-compat branch: no affinity authored ⇒ exactly base damage.
	_register_base("base_test_plain", ["sword"])
	var hd := HeroData.new()
	hd.hero_id = "hero_plain"
	hd.attack_damage = 10.0
	# hd.item_affinities left empty (default)
	var stats: Dictionary = BaseHero.compute_stats_for(hd, 1, [_instance("base_test_plain")])
	assert_almost_eq(float(stats.get("damage", 0.0)), 10.0, 0.001,
		"no affinity ⇒ value-identical to pre-R1 (no extra mods)")


func test_compute_stats_for_affinity_unsatisfied_no_bonus() -> void:
	# Item tag doesn't satisfy the affinity ⇒ no bonus (parity with runtime).
	_register_base("base_test_staff", ["staff"])
	var aff := _affinity(["sword"], [_stat_mod(5.0)])
	var hd := HeroData.new()
	hd.hero_id = "hero_unsat"
	hd.attack_damage = 10.0
	var ia: Array[Resource] = [aff]
	hd.item_affinities = ia
	var stats: Dictionary = BaseHero.compute_stats_for(hd, 1, [_instance("base_test_staff")])
	assert_almost_eq(float(stats.get("damage", 0.0)), 10.0, 0.001,
		"staff doesn't satisfy a sword affinity ⇒ no bonus (matches runtime)")
