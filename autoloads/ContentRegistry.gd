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

var enemies: Array[Resource] = []
var towers: Array[Resource] = []
var heroes: Array[Resource] = []
var spells: Array[Resource] = []
var upgrades: Array[Resource] = []  # populated by UpgradeTree scene (inline sub_resources)


func _ready() -> void:
	enemies = _load_catalog(_ENEMY_PATHS, "enemies")
	towers = _load_catalog(_TOWER_PATHS, "towers")
	heroes = _load_catalog(_HERO_PATHS, "heroes")
	spells = _load_catalog(_SPELL_PATHS, "spells")
	print("[ContentRegistry] loaded — %d enemies, %d towers, %d heroes, %d spells" % [
		enemies.size(), towers.size(), heroes.size(), spells.size(),
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
