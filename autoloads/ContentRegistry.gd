extends Node

# Phase 34: central index of ALL authored content. Every system that needs
# "what content exists" reads from here — encyclopedia, loadout, shop,
# loot tables, endless wave generator.
#
# Phase 48 / CORE RULE 16: catalogs are populated via `load()` at _ready(),
# NOT `preload()` at class body. Class-body preload() triggers Godot 4.4+
# bug #105021 where the first item in any array whose resources share a
# class_name-registered script (e.g. TowerData.gd across 5 tower .tres
# files) comes back as a bare Resource with no script attached. Load() runs
# after every autoload has compiled — no race possible. Cost ~10ms at boot.

const _ENEMY_PATHS: Array[String] = [
	"res://enemies/data/enemy_basic.tres",
	"res://enemies/data/enemy_flying.tres",
	"res://enemies/data/enemy_healer.tres",
	"res://enemies/data/enemy_armored.tres",
	"res://enemies/data/enemy_scout.tres",
	"res://enemies/data/boss_orc_warlord.tres",
]

const _TOWER_PATHS: Array[String] = [
	"res://towers/data/tower_archer.tres",
	"res://towers/data/tower_barracks.tres",
	"res://towers/data/tower_mage.tres",
	"res://towers/data/tower_artillery.tres",
	"res://towers/data/tower_ice.tres",
]

const _HERO_PATHS: Array[String] = [
	"res://heroes/data/hero_warrior.tres",
	"res://heroes/data/hero_mage.tres",
]

const _SPELL_PATHS: Array[String] = [
	"res://spells/data/spell_fireball.tres",
	"res://spells/data/spell_reinforcements.tres",
]

# Phase 48 — loot system content. ItemBase templates back all dropped
# ItemInstance runtime objects; AffixData templates are rolled into
# instances at drop time; AffixPool groups affixes into pool_id buckets.
const _ITEM_BASE_PATHS: Array[String] = [
	"res://items/bases/base_starter_sword.tres",
	"res://items/bases/base_starter_tunic.tres",
	"res://items/bases/base_starter_charm.tres",
	# Phase B rollable bases — MAGIC (iron_sword, chain_mail) + RARE (amulet)
	"res://items/bases/base_iron_sword.tres",
	"res://items/bases/base_chain_mail.tres",
	"res://items/bases/base_amulet_wisdom.tres",
	# Phase E2 — rarity spread across all 5 tiers
	"res://items/bases/base_wooden_sword.tres",    # 0 COMMON
	"res://items/bases/base_leather_cap.tres",     # 1 MAGIC
	"res://items/bases/base_steel_sword.tres",     # 2 RARE
	"res://items/bases/base_plate_armor.tres",     # 2 RARE
	"res://items/bases/base_elven_blade.tres",     # 3 EPIC
	"res://items/bases/base_demon_core.tres",      # 4 LEGENDARY
]

const _AFFIX_POOL_PATHS: Array[String] = [
	"res://items/pools/pool_universal.tres",
	"res://items/pools/pool_weapon_offensive.tres",
	"res://items/pools/pool_armor_defensive.tres",
]

const _AFFIX_PATHS: Array[String] = [
	# Flat-value affixes
	"res://items/affixes/affix_damage_flat.tres",
	"res://items/affixes/affix_lifesteal.tres",
	"res://items/affixes/affix_on_hit_bonus.tres",
	"res://items/affixes/affix_hp_flat.tres",
	"res://items/affixes/affix_armor_flat.tres",
	"res://items/affixes/affix_regen.tres",
	# Phase E1 — percentage-based affixes (display_scale=100)
	"res://items/affixes/affix_damage_pct.tres",
	"res://items/affixes/affix_hp_pct.tres",
	"res://items/affixes/affix_attack_speed_pct.tres",
	"res://items/affixes/affix_move_speed_pct.tres",
	"res://items/affixes/affix_xp_gain_pct.tres",
]

var enemies: Array[Resource] = []
var towers: Array[Resource] = []
var heroes: Array[Resource] = []
var spells: Array[Resource] = []
var upgrades: Array[Resource] = []  # populated by UpgradeTree scene (inline sub_resources)
var item_bases: Array[Resource] = []
var affixes: Array[Resource] = []
var affix_pools: Array[Resource] = []


func _ready() -> void:
	enemies = _load_catalog(_ENEMY_PATHS, "enemies")
	towers = _load_catalog(_TOWER_PATHS, "towers")
	heroes = _load_catalog(_HERO_PATHS, "heroes")
	spells = _load_catalog(_SPELL_PATHS, "spells")
	item_bases = _load_catalog(_ITEM_BASE_PATHS, "item_bases")
	affixes = _load_catalog(_AFFIX_PATHS, "affixes")
	affix_pools = _load_catalog(_AFFIX_POOL_PATHS, "affix_pools")
	print("[ContentRegistry] loaded — %d enemies, %d towers, %d heroes, %d spells, %d item_bases, %d affixes, %d pools" % [
		enemies.size(), towers.size(), heroes.size(), spells.size(),
		item_bases.size(), affixes.size(), affix_pools.size(),
	])
	_validate_ids()


# Loads each path, drops nulls with an error. Missing files are fatal-visible
# (loud push_error) rather than silently skipped so content drift surfaces
# on the very first boot.
func _load_catalog(paths: Array[String], label: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for p in paths:
		var r: Resource = load(p)
		if r == null:
			push_error("[ContentRegistry] failed to load %s: %s" % [label, p])
			continue
		out.append(r)
	return out


# Phase 46c: boot-time assertion that each .tres's `*_id` field matches its
# filename basename. Drift here is a silent-bug class — see the hero/tower
# "mage" collision that hid the Mage tower from the build ring until a
# diagnostic print revealed it. Warnings (not errors) so existing drift
# doesn't block the game; fix at your pace.
func _validate_ids() -> void:
	_assert_ids(enemies, "enemy_id")
	_assert_ids(towers, "tower_id")
	_assert_ids(heroes, "hero_id")
	_assert_ids(spells, "spell_id")
	_assert_ids(item_bases, "base_id")
	_assert_ids(affixes, "affix_id")
	_assert_ids(affix_pools, "pool_id")


func _assert_ids(arr: Array, field: String) -> void:
	for r in arr:
		if r == null:
			continue
		if not (field in r):
			print("[ContentRegistry/DRIFT] %s has no %s field" % [r.resource_path, field])
			continue
		var id: String = r.get(field)
		var base: String = r.resource_path.get_file().get_basename()
		if id == "":
			print("[ContentRegistry/DRIFT] %s has empty %s" % [r.resource_path, field])
		elif id != base:
			print("[ContentRegistry/DRIFT] %s: %s=\"%s\" should match filename \"%s\"" % [r.resource_path, field, id, base])


# Lookup helpers — return null if not found. Guards with `field in r` in case
# a .tres came back as a plain Resource (script failed to attach).
func find_enemy(id: String) -> Resource:
	for e in enemies:
		if e != null and "enemy_id" in e and e.enemy_id == id:
			return e
	return null


func find_tower(id: String) -> Resource:
	for t in towers:
		if t != null and "tower_id" in t and t.tower_id == id:
			return t
	return null


func find_hero(id: String) -> Resource:
	for h in heroes:
		if h != null and "hero_id" in h and h.hero_id == id:
			return h
	return null


func find_spell(id: String) -> Resource:
	for s in spells:
		if s != null and "spell_id" in s and s.spell_id == id:
			return s
	return null


func find_item_base(id: String) -> Resource:
	for b in item_bases:
		if b != null and "base_id" in b and b.base_id == id:
			return b
	return null


func find_affix(id: String) -> Resource:
	for a in affixes:
		if a != null and "affix_id" in a and a.affix_id == id:
			return a
	return null


func find_affix_pool(id: String) -> Resource:
	for p in affix_pools:
		if p != null and "pool_id" in p and p.pool_id == id:
			return p
	return null
