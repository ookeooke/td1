extends Node

# Phase 34: central index of ALL authored content. Every system that needs
# "what content exists" reads from here — encyclopedia, loadout, shop,
# loot tables, endless wave generator.
#
# Adding new content: one preload() line in the matching array.
# No scanning, no directory walks — explicit, mobile-safe, export-safe.

var enemies: Array[Resource] = [
	preload("res://enemies/data/enemy_basic.tres"),
	preload("res://enemies/data/enemy_flying.tres"),
	preload("res://enemies/data/enemy_healer.tres"),
	preload("res://enemies/data/enemy_armored.tres"),
	preload("res://enemies/data/enemy_scout.tres"),
	preload("res://enemies/data/boss_orc_warlord.tres"),
]

var towers: Array[Resource] = [
	preload("res://towers/data/tower_archer.tres"),
	preload("res://towers/data/tower_barracks.tres"),
	preload("res://towers/data/tower_mage.tres"),
	preload("res://towers/data/tower_artillery.tres"),
]

var heroes: Array[Resource] = [
	preload("res://heroes/data/hero_warrior.tres"),
	preload("res://heroes/data/hero_mage.tres"),
]

var spells: Array[Resource] = [
	preload("res://spells/data/spell_fireball.tres"),
	preload("res://spells/data/spell_reinforcements.tres"),
]

var upgrades: Array[Resource] = []  # populated by UpgradeTree scene (inline sub_resources)


func _ready() -> void:
	print("[ContentRegistry] loaded — %d enemies, %d towers, %d heroes, %d spells" % [
		enemies.size(), towers.size(), heroes.size(), spells.size(),
	])
	_validate_ids()


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


# Lookup helpers — return null if not found.
func find_enemy(id: String) -> Resource:
	for e in enemies:
		if e != null and "enemy_id" in e and e.enemy_id == id:
			return e
	return null


func find_tower(id: String) -> Resource:
	for t in towers:
		if t != null and t.tower_id == id:
			return t
	return null


func find_hero(id: String) -> Resource:
	for h in heroes:
		if h != null and h.hero_id == id:
			return h
	return null
