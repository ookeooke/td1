extends GutTest

# Phase 1 — HeroItemAffinityData grant contract.
#
# Tests the pure matcher BaseHero._affinities_to_grant(affinities, tag_set,
# rank): a hero gains an affinity's bonus_abilities iff its rank is met AND
# every required_item_tag is present among equipped items' tags. Off-affinity
# items still work (they just never satisfy a required-tag set). No affinities
# authored ⇒ no grant (byte-identical backward compat).

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
