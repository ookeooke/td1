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
]

var towers: Array[Resource] = [
	preload("res://towers/data/tower_archer.tres"),
	preload("res://towers/data/tower_barracks.tres"),
]

var heroes: Array[Resource] = [
	preload("res://heroes/data/hero_warrior.tres"),
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
