extends GutTest

# Hero Item-First Platform — authored CONTENT validation. Asserts the
# shipped .tres (item tags, weapon profiles, per-hero starter weapons,
# Mastery affinities) and the HeroAffinityPreview teaching helper against
# the REAL ContentRegistry catalog — integration, not pure helpers.
#
# Each hero now has its OWN archetype starter weapon, which dissolved the
# old "starter sword must be profile-less" exception (ranged heroes no
# longer auto-equip a sword). EVERY weapon base now carries a profile.

const _WEAPON_BASES := [
	"base_starter_sword", "base_wooden_sword", "base_iron_sword",
	"base_steel_sword", "base_elven_blade", "base_hunter_bow",
	"base_apprentice_staff", "base_starter_staff", "base_starter_bow",
	"base_bone_relic",
]
const _SWORD_BASES := [
	"base_starter_sword", "base_wooden_sword", "base_iron_sword",
	"base_steel_sword", "base_elven_blade",
]
# Every weapon base now carries a WeaponProfileAbility (the exception is
# gone — each hero has its own archetype starter).
const _PROFILED_WEAPONS := [
	"base_starter_sword", "base_wooden_sword", "base_iron_sword",
	"base_steel_sword", "base_elven_blade", "base_hunter_bow",
	"base_apprentice_staff", "base_starter_staff", "base_starter_bow",
	"base_bone_relic",
]


func _base(id: String) -> Resource:
	return ContentRegistry.find_item_base(id)


func _weapon_profile(base: Resource) -> Resource:
	for ab in base.implicit_abilities:
		if ab != null and "weapon_base_damage" in ab:  # WeaponProfileAbility
			return ab
	return null


func _inst(base_id: String) -> ItemInstance:
	var i := ItemInstance.new()
	i.base_id = base_id
	return i


# ── Phase 1: item tags ──────────────────────────────────────────────────

func test_every_weapon_base_has_weapon_tag() -> void:
	for id in _WEAPON_BASES:
		var b: Resource = _base(id)
		assert_not_null(b, "%s exists in registry" % id)
		assert_true(b.item_tags.has("weapon"), "%s tagged 'weapon'" % id)


func test_every_sword_base_has_sword_tag() -> void:
	for id in _SWORD_BASES:
		assert_true(_base(id).item_tags.has("sword"), "%s tagged 'sword'" % id)


func test_bow_and_staff_family_tags() -> void:
	assert_true(_base("base_hunter_bow").item_tags.has("bow"), "bow tagged 'bow'")
	assert_true(_base("base_apprentice_staff").item_tags.has("staff"), "staff tagged 'staff'")


# ── Phase 1: weapon profiles ────────────────────────────────────────────

func test_profiled_weapons_are_attack_viable() -> void:
	for id in _PROFILED_WEAPONS:
		var wp: Resource = _weapon_profile(_base(id))
		assert_not_null(wp, "%s carries a WeaponProfileAbility" % id)
		var viable: bool = wp.projectile_scene != null or wp.weapon_attack_range > 0.0
		assert_true(viable, "%s profile attack-viable" % id)


func test_starter_sword_now_has_melee_profile() -> void:
	# Exception dissolved: each hero now has its own archetype starter, so
	# the starter sword is honest — a real melee weapon (Warrior only).
	var wp: Resource = _weapon_profile(_base("base_starter_sword"))
	assert_not_null(wp, "starter sword now carries a WeaponProfileAbility")
	assert_null(wp.projectile_scene, "starter sword is melee (no projectile)")
	assert_eq(int(wp.weapon_damage_type), 0, "starter sword is PHYSICAL")


func test_swords_are_melee_physical_profiles() -> void:
	for id in ["base_wooden_sword", "base_iron_sword", "base_steel_sword", "base_elven_blade"]:
		var wp: Resource = _weapon_profile(_base(id))
		assert_null(wp.projectile_scene, "%s sword profile is melee (no projectile)" % id)
		assert_eq(int(wp.weapon_damage_type), 0, "%s sword forces PHYSICAL" % id)


func test_bow_is_ranged_staff_is_magic() -> void:
	var bow: Resource = _weapon_profile(_base("base_hunter_bow"))
	assert_not_null(bow.projectile_scene, "bow profile fires a projectile")
	assert_eq(int(bow.weapon_damage_type), 0, "bow is PHYSICAL")
	var staff: Resource = _weapon_profile(_base("base_apprentice_staff"))
	assert_not_null(staff.projectile_scene, "staff profile fires a projectile")
	assert_eq(int(staff.weapon_damage_type), 1, "staff is MAGIC")


# ── Phase 2: Warrior Sword Mastery ──────────────────────────────────────

func _warrior() -> Resource:
	return ContentRegistry.find_hero("hero_warrior")


func test_warrior_has_sword_mastery_affinity() -> void:
	var w: Resource = _warrior()
	assert_eq(w.item_affinities.size(), 1, "Warrior has one authored affinity")
	var aff: Resource = w.item_affinities[0]
	assert_eq(aff.affinity_id, "aff_warrior_sword_mastery", "affinity id")
	assert_true(aff.required_item_tags.has("sword"), "requires 'sword'")
	assert_eq(aff.bonus_abilities.size(), 1, "one bonus ability")


func test_warrior_sword_grants_damage_in_compute_stats() -> void:
	# Real catalog: Warrior + iron sword. base 1.75, iron implicit +3 flat,
	# Sword Mastery +10% → (1.75+3.0)*1.10 ≈ 5.225.
	var w: Resource = _warrior()
	var with_sword: Dictionary = BaseHero.compute_stats_for(w, 1, [_inst("base_iron_sword")])
	assert_almost_eq(float(with_sword.get("damage", 0.0)), 5.225, 0.01,
		"Warrior+sword damage includes Sword Mastery +10%")


func test_mage_sword_gets_no_warrior_mastery() -> void:
	var m: Resource = ContentRegistry.find_hero("hero_mage")
	if m == null:
		pass_test("no mage in registry — skip")
		return
	var d: Dictionary = BaseHero.compute_stats_for(m, 1, [_inst("base_iron_sword")])
	# Mage has no affinities → only the +3 flat implicit, no ×1.10.
	var mage_base: Dictionary = BaseHero.compute_stats_for(m, 1, [])
	assert_almost_eq(float(d.get("damage", 0.0)),
		float(mage_base.get("damage", 0.0)) + 3.0, 0.01,
		"Mage+sword = base +3 implicit, NO Warrior mastery ×1.10")


# ── Phase 1 behavior: weapon owns attack for any hero ───────────────────

func test_mage_with_sword_melees_in_display() -> void:
	var m: Resource = ContentRegistry.find_hero("hero_mage")
	if m == null:
		pass_test("no mage — skip")
		return
	var d: Dictionary = BaseHero.compute_stats_for(m, 1, [_inst("base_iron_sword")])
	assert_false(bool(d.get("uses_projectile", true)),
		"Mage equipping a sword MELEES (sword profile, null projectile)")


func test_mage_with_bow_fires_projectile_in_display() -> void:
	var m: Resource = ContentRegistry.find_hero("hero_mage")
	if m == null:
		pass_test("no mage — skip")
		return
	var d: Dictionary = BaseHero.compute_stats_for(m, 1, [_inst("base_hunter_bow")])
	assert_true(bool(d.get("uses_projectile", false)),
		"Mage equipping a bow FIRES the bow (bow profile projectile)")


# ── Phase 3: HeroAffinityPreview teaching helper ────────────────────────

func test_preview_active_for_warrior_sword() -> void:
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_warrior", _base("base_iron_sword"), [])
	assert_true(bool(p.get("active", false)), "Warrior + sword ⇒ affinity active")
	assert_eq(String(p.get("title", "")), "Affinity Active", "active title")


func test_preview_inactive_for_mage_sword_but_allowed() -> void:
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_mage", _base("base_iron_sword"), [])
	assert_false(bool(p.get("active", true)), "Mage has no sword mastery")
	# Off-family must read as ALLOWED, never broken.
	var joined: String = " ".join(p.get("lines", []))
	assert_true(joined.to_lower().contains("apply"),
		"Mage + sword still says stats apply (allowed, not broken)")


func test_preview_offfamily_bow_on_warrior_allowed() -> void:
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_warrior", _base("base_hunter_bow"), [])
	assert_false(bool(p.get("active", true)),
		"bow is not a Warrior sword-family item ⇒ no mastery, still usable")


func test_overview_line_warrior_lists_best_with() -> void:
	var line: String = HeroAffinityPreview.overview_line("hero_warrior")
	assert_true(line.to_lower().contains("sword"),
		"Warrior overview advertises 'Best With: sword'")


# ── Per-hero starter weapon identity (the wiring) ───────────────────────

func _hero_starter_weapon(hero_id: String) -> Resource:
	# First slot-0 (weapon) item in the hero's authored starter_items.
	var hd: Resource = ContentRegistry.find_hero(hero_id)
	for it in hd.starter_items:
		if it != null and "slot" in it and int(it.slot) == 0:
			return it
	return null


func test_warrior_starter_is_melee() -> void:
	var wp: Resource = _weapon_profile(_hero_starter_weapon("hero_warrior"))
	assert_not_null(wp, "Warrior starter weapon has a profile")
	assert_null(wp.projectile_scene, "Warrior starts MELEE")


func test_mage_starter_is_magic_projectile() -> void:
	var sw: Resource = _hero_starter_weapon("hero_mage")
	assert_eq(sw.base_id, "base_starter_staff", "Mage starts with a staff, not a sword")
	var wp: Resource = _weapon_profile(sw)
	assert_not_null(wp.projectile_scene, "Mage starter fires a projectile")
	assert_eq(int(wp.weapon_damage_type), 1, "Mage starter is MAGIC")


func test_ranger_starter_is_arrow_projectile() -> void:
	var sw: Resource = _hero_starter_weapon("hero_ranger")
	assert_eq(sw.base_id, "base_starter_bow", "Ranger starts with a bow")
	var wp: Resource = _weapon_profile(sw)
	assert_not_null(wp.projectile_scene, "Ranger starter fires an arrow projectile")
	assert_eq(int(wp.weapon_damage_type), 0, "Ranger starter is PHYSICAL")


func test_necromancer_starter_is_magic_projectile() -> void:
	var sw: Resource = _hero_starter_weapon("hero_necromancer")
	assert_eq(sw.base_id, "base_bone_relic", "Necromancer starts with the Bone Relic")
	var wp: Resource = _weapon_profile(sw)
	assert_not_null(wp.projectile_scene, "Necro starter fires a soul projectile")
	assert_eq(int(wp.weapon_damage_type), 1, "Necro starter is MAGIC")


func test_no_ranged_hero_starts_with_a_sword() -> void:
	for hid in ["hero_mage", "hero_ranger", "hero_necromancer"]:
		var sw: Resource = _hero_starter_weapon(hid)
		assert_false(sw.item_tags.has("sword"),
			"%s must NOT auto-equip a sword at spawn (identity / Naked Baseline)" % hid)


# ── Mage / Ranger / Necro Mastery I affinities ──────────────────────────

func test_mage_staff_mastery_active_with_starter() -> void:
	var m: Resource = ContentRegistry.find_hero("hero_mage")
	assert_eq(m.item_affinities.size(), 1, "Mage has Staff Mastery")
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_mage", _base("base_starter_staff"), [])
	assert_true(bool(p.get("active", false)), "Mage + staff ⇒ Staff Mastery active")


func test_ranger_bow_mastery_active_with_starter() -> void:
	var r: Resource = ContentRegistry.find_hero("hero_ranger")
	assert_eq(r.item_affinities.size(), 1, "Ranger has Bow Mastery")
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_ranger", _base("base_starter_bow"), [])
	assert_true(bool(p.get("active", false)), "Ranger + bow ⇒ Bow Mastery active")


func test_necro_relic_mastery_active_with_starter() -> void:
	var n: Resource = ContentRegistry.find_hero("hero_necromancer")
	assert_eq(n.item_affinities.size(), 1, "Necro has Relic Mastery")
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_necromancer", _base("base_bone_relic"), [])
	assert_true(bool(p.get("active", false)), "Necro + relic ⇒ Relic Mastery active")


func test_mage_staff_mastery_grants_skill_power() -> void:
	# Staff Mastery I = +10% skill_power. Mage + starter staff vs no items.
	var m: Resource = ContentRegistry.find_hero("hero_mage")
	var bare: Dictionary = BaseHero.compute_stats_for(m, 1, [])
	var armed: Dictionary = BaseHero.compute_stats_for(m, 1, [_inst("base_starter_staff")])
	assert_gt(float(armed.get("skill_power", 0.0)), float(bare.get("skill_power", 0.0)),
		"Staff Mastery raises Mage skill_power above the bare baseline")


func test_cross_family_still_allowed_no_mastery() -> void:
	# Mage equipping a sword: melees (weapon owns attack), but NO Staff
	# Mastery (off-family) — freedom inside lanes, never broken.
	var d: Dictionary = BaseHero.compute_stats_for(
		ContentRegistry.find_hero("hero_mage"), 1, [_inst("base_iron_sword")])
	assert_false(bool(d.get("uses_projectile", true)),
		"Mage + sword melees (weapon owns the attack)")
	var p: Dictionary = HeroAffinityPreview.preview_for_item(
		"hero_mage", _base("base_iron_sword"), [])
	assert_false(bool(p.get("active", true)), "no Staff Mastery from a sword")
