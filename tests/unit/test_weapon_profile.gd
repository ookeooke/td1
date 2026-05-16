extends GutTest

# Phase 3 — Pure-B: the equipped weapon owns the attack profile.
#
# _resolve_attack_profile() returns {damage, speed, dtype, use_projectile}.
# With no _weapon_profile every value falls back to HeroData (byte-identical).
# A WeaponProfileAbility overrides melee/ranged, projectile, damage, dtype.
# Damage is BASE-REPLACE via a ratio so the affix stack is counted once.

var _spawned: Array[Node] = []


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _hero(projectile: bool, dmg: float = 10.0, dtype: int = 0) -> BaseHero:
	var h := BaseHero.new()
	var d := HeroData.new()
	d.hero_id = "hero_test"
	d.attack_damage = dmg
	d.attack_speed = 1.0
	d.attack_range = 100.0
	d.damage_type = dtype
	if projectile:
		d.projectile_scene = PackedScene.new()
	h.data = d
	_spawned.append(h)
	return h


func _profile(proj: PackedScene, base_dmg: float = 0.0, dtype: int = -1, rng: float = 0.0) -> WeaponProfileAbility:
	var w := WeaponProfileAbility.new()
	w.projectile_scene = proj
	w.weapon_base_damage = base_dmg
	w.weapon_damage_type = dtype
	w.weapon_attack_range = rng
	return w


# ── Backward compat / Naked Baseline fallback ───────────────────────────

func test_backward_compat_melee_hero_no_profile() -> void:
	var h: BaseHero = _hero(false)
	var p: Dictionary = h._resolve_attack_profile()
	assert_false(p["use_projectile"], "no projectile_scene ⇒ melee (legacy)")
	assert_eq(p["dtype"], 0, "dtype falls back to HeroData.damage_type")
	assert_almost_eq(float(p["damage"]), 10.0, 0.001, "damage == effective (no profile)")


func test_backward_compat_ranged_hero_no_profile() -> void:
	var h: BaseHero = _hero(true)
	assert_true(h._resolve_attack_profile()["use_projectile"],
		"HeroData.projectile_scene set ⇒ ranged (legacy fallback)")


func test_naked_baseline_fallback() -> void:
	var h: BaseHero = _hero(false)
	assert_null(h.get_weapon_profile(), "unarmed by default")
	assert_false(h._resolve_attack_profile()["use_projectile"],
		"unarmed hero still attacks via HeroData fallback")


# ── Weapon owns melee/ranged ────────────────────────────────────────────

func test_ranger_with_sword_melees() -> void:
	var h: BaseHero = _hero(true)  # ranger archetype (HeroData projectile)
	h.set_weapon_profile(_profile(null))  # melee weapon (no projectile)
	assert_false(h._resolve_attack_profile()["use_projectile"],
		"sword profile (projectile_scene=null) ⇒ ranger MELEES, no arrow")


func test_mage_with_bow_fires_bow() -> void:
	var h: BaseHero = _hero(false)  # melee archetype
	var bow := PackedScene.new()
	h.set_weapon_profile(_profile(bow))
	assert_true(h._resolve_attack_profile()["use_projectile"],
		"bow profile ⇒ melee hero FIRES the bow")
	assert_eq(h._profile_projectile_scene(), bow,
		"resolved projectile is the weapon's, not HeroData's")


func test_weapon_overrides_damage_type() -> void:
	var h: BaseHero = _hero(true, 10.0, 0)  # PHYSICAL hero
	h.set_weapon_profile(_profile(PackedScene.new(), 0.0, 1))  # MAGIC weapon
	assert_eq(h._resolve_attack_profile()["dtype"], 1,
		"weapon damage type overrides hero's")


# ── Damage not double-counted (base-replace via ratio) ──────────────────

func test_damage_not_double_counted() -> void:
	var h: BaseHero = _hero(true, 10.0)
	h.current_stats = {"damage": 15.0}  # simulate a +50% affix stack
	h.set_weapon_profile(_profile(PackedScene.new(), 8.0))  # weapon base 8
	# Expected: weapon_base * (effective/hero_base) = 8 * (15/10) = 12, NOT
	# 8 + 15 (= 23) or 8 * 15 — affix counted exactly once.
	assert_almost_eq(float(h._resolve_attack_profile()["damage"]), 12.0, 0.001,
		"weapon damage = base × affix-ratio (counted once)")


func test_no_weapon_base_keeps_effective_damage() -> void:
	var h: BaseHero = _hero(true, 10.0)
	h.current_stats = {"damage": 15.0}
	h.set_weapon_profile(_profile(PackedScene.new(), 0.0))  # no weapon base
	assert_almost_eq(float(h._resolve_attack_profile()["damage"]), 15.0, 0.001,
		"weapon_base_damage<=0 ⇒ keep effective damage (byte-identical)")


# ── Lifecycle ───────────────────────────────────────────────────────────

func test_unequip_clears_profile() -> void:
	var h: BaseHero = _hero(true)
	var w: WeaponProfileAbility = _profile(PackedScene.new())
	w.apply(h, {})  # equip-ish
	assert_eq(h.get_weapon_profile(), w, "profile set on apply")
	w.apply(h, {"phase": AbilityData.Trigger.ON_UNEQUIP})
	assert_null(h.get_weapon_profile(), "ON_UNEQUIP clears the profile")


func test_clear_is_identity_checked() -> void:
	var h: BaseHero = _hero(true)
	var w1: WeaponProfileAbility = _profile(null)
	var w2: WeaponProfileAbility = _profile(PackedScene.new())
	h.set_weapon_profile(w1)
	h.clear_weapon_profile(w2)  # stale ability — must NOT wipe w1
	assert_eq(h.get_weapon_profile(), w1,
		"a stale ability's clear cannot drop a newer profile")


# ── Naked Baseline: every shipped hero's fallback is attack-viable ──────

func test_boot_check_all_shipped_heroes_viable() -> void:
	for h in ContentRegistry.heroes:
		if h == null:
			continue
		var viable: bool = h.attack_damage > 0.0 and h.attack_speed > 0.0 \
			and (h.projectile_scene != null or h.attack_range > 0.0)
		assert_true(viable,
			"%s fallback must be attack-viable (Naked Baseline)" % h.hero_id)
