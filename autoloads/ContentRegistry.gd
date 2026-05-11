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
	"res://enemies/data/enemy_brute.tres",
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
	"res://heroes/data/hero_ranger.tres",
]

# Phase 1 — per-hero skill trees (node-graph progression). Filename basename
# matches hero_id so _assert_ids catches drift.
const _SKILL_TREE_PATHS: Array[String] = [
	"res://heroes/data/skill_trees/hero_warrior.tres",
	"res://heroes/data/skill_trees/hero_mage.tres",
	"res://heroes/data/skill_trees/hero_ranger.tres",
]

# Phase 48 — loot system content. ItemBase templates back all dropped
# ItemInstance runtime objects; AffixData templates are rolled into
# instances at drop time; AffixPool groups affixes into pool_id buckets.
#
# Phase 49 — directory-globbed (was a hand-maintained Array[String]). Drop
# any new .tres into the matching folder and it loads on next boot — no
# autoload edit. Filenames sort lexicographically for deterministic load
# order across machines / file systems. Loaded via _load_catalog_dir below.
# CORE RULE 16's load() vs preload() rationale still applies: every file is
# load()'d inside _ready(), never preloaded at class-body scope.
const _ITEM_BASE_DIR: String = "res://items/bases/"
const _AFFIX_DIR: String = "res://items/affixes/"
const _AFFIX_POOL_DIR: String = "res://items/pools/"

var enemies: Array[Resource] = []
var towers: Array[Resource] = []
var heroes: Array[Resource] = []
var skill_trees: Array[Resource] = []  # Phase 1 — one HeroSkillTreeData per hero
var upgrades: Array[Resource] = []  # populated by UpgradeTree scene (inline sub_resources)
var item_bases: Array[Resource] = []
var affixes: Array[Resource] = []
var affix_pools: Array[Resource] = []
# Phase 49 — campaign levels. Loaded from level_list.tres (a LevelList
# wrapper holding Array[Resource] of LevelNodeData). Single source of
# truth for WorldMap, BalanceSliders, LevelAudit, and Main.gd. Future
# multi-world support: extend _load_levels to concatenate per-world files;
# consumers don't change.
var levels: Array[Resource] = []

const _LEVEL_LIST_PATH: String = "res://ui/world_map/level_list.tres"


func _ready() -> void:
	enemies = _load_catalog(_ENEMY_PATHS, "enemies")
	towers = _load_catalog(_TOWER_PATHS, "towers")
	heroes = _load_catalog(_HERO_PATHS, "heroes")
	skill_trees = _load_catalog(_SKILL_TREE_PATHS, "skill_trees")
	item_bases = _load_catalog_dir(_ITEM_BASE_DIR, "item_bases")
	affixes = _load_catalog_dir(_AFFIX_DIR, "affixes")
	affix_pools = _load_catalog_dir(_AFFIX_POOL_DIR, "affix_pools")
	levels = _load_levels()
	print("[ContentRegistry] loaded — %d enemies, %d towers, %d heroes, %d trees, %d item_bases, %d affixes, %d pools, %d levels" % [
		enemies.size(), towers.size(), heroes.size(), skill_trees.size(),
		item_bases.size(), affixes.size(), affix_pools.size(), levels.size(),
	])
	_validate_ids()


# Levels live inside level_list.tres as a LevelList wrapper resource; we
# unwrap the container and store the inner array. Future: extend to
# concatenate multiple per-world files into one flat catalog.
func _load_levels() -> Array[Resource]:
	var out: Array[Resource] = []
	var registry: Resource = load(_LEVEL_LIST_PATH)
	if registry == null:
		push_error("[ContentRegistry] failed to load levels: %s" % _LEVEL_LIST_PATH)
		return out
	if not ("levels" in registry):
		push_error("[ContentRegistry] %s has no `levels` field" % _LEVEL_LIST_PATH)
		return out
	# Iterate element-wise into a fresh Array[Resource] so we don't pin to
	# whatever container type LevelList's @export currently uses.
	for entry in registry.levels:
		if entry != null:
			out.append(entry)
	return out


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


# Directory-glob loader. Lists every .tres in `dir`, sorts filenames
# lexicographically (deterministic across platforms), and loads each.
# Skips .import / .uid sidecars implicitly via the suffix filter. Adding
# a new authored file requires zero autoload edits.
func _load_catalog_dir(dir: String, label: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		push_error("[ContentRegistry] failed to open %s dir: %s" % [label, dir])
		return out
	var files: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".tres"):
			files.append(f)
	files.sort()
	for f in files:
		var p: String = dir + f
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
	_assert_ids(skill_trees, "hero_id")
	_assert_ids(item_bases, "base_id")
	_assert_ids(affixes, "affix_id")
	_assert_ids(affix_pools, "pool_id")
	_assert_level_ids()


# Levels are sub_resources inside level_list.tres (not standalone files), so
# the filename-matches-id rule from _assert_ids doesn't apply. Instead check
# that every entry has a non-empty level_id and that ids are unique across
# the catalog — id collisions would silently break find_level / save state.
func _assert_level_ids() -> void:
	var seen: Dictionary = {}
	for r in levels:
		if r == null:
			continue
		if not ("level_id" in r):
			print("[ContentRegistry/DRIFT] level entry has no level_id field")
			continue
		var id: String = r.level_id
		if id == "":
			print("[ContentRegistry/DRIFT] level entry has empty level_id")
			continue
		if seen.has(id):
			print("[ContentRegistry/DRIFT] duplicate level_id \"%s\"" % id)
		seen[id] = true


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


func find_skill_tree(hero_id: String) -> Resource:
	for t in skill_trees:
		if t != null and "hero_id" in t and t.hero_id == hero_id:
			return t
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


func find_level(id: String) -> Resource:
	for lvl in levels:
		if lvl != null and "level_id" in lvl and lvl.level_id == id:
			return lvl
	return null
