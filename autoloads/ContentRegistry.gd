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

# Directory-globbed catalogs. Drop any new .tres into the matching folder
# and it loads on next boot — no autoload edit. Filenames sort
# lexicographically for deterministic load order across machines / file
# systems. Loaded via _load_catalog_dir below.
#
# CORE RULE 16's load() vs preload() rationale still applies: every file is
# load()'d inside _ready(), never preloaded at class-body scope.
#
# `enemies/data/` and `heroes/data/` contain `visual_*.tres` (UnitVisualData)
# alongside the unit data files; the `required_field` filter in
# _load_catalog_dir keeps only resources with the expected id field so
# foreign siblings are silently skipped.
const _ENEMY_DIR: String = "res://enemies/data/"
const _TOWER_DIR: String = "res://towers/data/"
const _HERO_DIR: String = "res://heroes/data/"
# Phase 1 — per-hero skill trees (node-graph progression). Own subdir so no
# foreign siblings; filter still applied for consistency.
const _SKILL_TREE_DIR: String = "res://heroes/data/skill_trees/"
# Phase 48 — loot system content. ItemBase templates back all dropped
# ItemInstance runtime objects; AffixData templates are rolled into
# instances at drop time; AffixPool groups affixes into pool_id buckets.
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
	enemies = _load_catalog_dir(_ENEMY_DIR, "enemies", "enemy_id")
	towers = _load_catalog_dir(_TOWER_DIR, "towers", "tower_id")
	heroes = _load_catalog_dir(_HERO_DIR, "heroes", "hero_id")
	skill_trees = _load_catalog_dir(_SKILL_TREE_DIR, "skill_trees", "hero_id")
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


# Directory-glob loader. Lists every .tres in `dir`, sorts filenames
# lexicographically (deterministic across platforms), and loads each.
# Skips .import / .uid sidecars implicitly via the suffix filter. Adding
# a new authored file requires zero autoload edits.
#
# `required_field` (optional): if set, resources lacking that property are
# silently skipped. Guards against foreign sibling .tres in the same dir
# (e.g. visual_*.tres UnitVisualData files living alongside enemy_*.tres /
# hero_*.tres). Empty string = accept everything.
func _load_catalog_dir(dir: String, label: String, required_field: String = "") -> Array[Resource]:
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
		if required_field != "" and not (required_field in r):
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
	_assert_affinities()
	_validate_enemy_class_keys()


# Boot-time check that every registered enemy resolves to a known class key
# in EnemyClassRegistry. Drift here ships as silent visual misclassification
# in the balance debug tools (charts color the new enemy as basic gray; the
# enemy section sorts it into the wrong bucket). Per Preventive Bug Rule 4
# this used to live as a comment ("don't forget to update the chart
# mappers") — now it's executable.
func _validate_enemy_class_keys() -> void:
	var EnemyClassRegistry = preload("res://enemies/EnemyClassRegistry.gd")
	for e in enemies:
		if e == null or not ("enemy_id" in e):
			continue
		var eid: String = String(e.enemy_id)
		if eid == "":
			continue
		var key: String = EnemyClassRegistry.class_key_for(eid)
		if key == "":
			print("[ContentRegistry/DRIFT] enemy \"%s\" has no recognized class key — add a substring match to EnemyClassRegistry._SUBSTRING_MATCHES (will fall back to \"basic\" in charts/sliders)" % eid)
			continue
		if not EnemyClassRegistry.COLORS.has(key):
			print("[ContentRegistry/DRIFT] enemy \"%s\" matches class_key \"%s\" but EnemyClassRegistry.COLORS has no entry — add the chart color" % [eid, key])
		if EnemyClassRegistry.KEYS_IN_PROGRESSION_ORDER.find(key) < 0:
			print("[ContentRegistry/DRIFT] enemy \"%s\" matches class_key \"%s\" but EnemyClassRegistry.KEYS_IN_PROGRESSION_ORDER is missing it — sort order broken" % [eid, key])
	_assert_curves()
	_assert_weapon_profiles()
	_assert_body_profiles()
	_assert_traps()


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


# Phase 1 — HeroItemAffinityData live on HeroData.item_affinities (not a
# standalone catalog). Assert every authored affinity is well-formed so a
# typo'd tag or a non-AbilityData bonus surfaces at boot, not as a silent
# never-granted mastery. Warnings only (consistent with _assert_ids).
func _assert_affinities() -> void:
	var seen: Dictionary = {}
	for h in heroes:
		if h == null or not ("item_affinities" in h):
			continue
		var hid: String = h.hero_id if "hero_id" in h else "?"
		for aff in h.item_affinities:
			if aff == null:
				print("[ContentRegistry/DRIFT] hero \"%s\" has a null item_affinities entry" % hid)
				continue
			if not ("affinity_id" in aff):
				print("[ContentRegistry/DRIFT] hero \"%s\" affinity is not a HeroItemAffinityData" % hid)
				continue
			var aid: String = aff.affinity_id
			if aid == "":
				print("[ContentRegistry/DRIFT] hero \"%s\" has an affinity with empty affinity_id" % hid)
			elif seen.has(aid):
				print("[ContentRegistry/DRIFT] duplicate affinity_id \"%s\"" % aid)
			seen[aid] = true
			if aff.required_item_tags.is_empty():
				print("[ContentRegistry/DRIFT] affinity \"%s\" has empty required_item_tags (never grants)" % aid)
			for ability in aff.bonus_abilities:
				if ability == null or not ("trigger" in ability):
					print("[ContentRegistry/DRIFT] affinity \"%s\" bonus_abilities has a non-AbilityData entry" % aid)


# Phase 2 — HeroLevelCurveData lives on HeroData.level_curve. Assert authored
# curves are sane so a negative growth or a slot-unlock list missing level 1
# surfaces at boot, not as silently-wrong progression. Warnings only.
func _assert_curves() -> void:
	for h in heroes:
		if h == null or not ("level_curve" in h):
			continue
		var lc = h.level_curve
		if lc == null:
			continue  # null ⇒ default curve, always valid
		var hid: String = h.hero_id if "hero_id" in h else "?"
		if not ("health_pct_per_level" in lc):
			print("[ContentRegistry/DRIFT] hero \"%s\" level_curve is not a HeroLevelCurveData" % hid)
			continue
		if lc.health_pct_per_level < 0.0 or lc.damage_pct_per_level < 0.0 \
				or lc.attack_speed_pct_per_level < 0.0:
			print("[ContentRegistry/DRIFT] hero \"%s\" level_curve has negative growth" % hid)
		if lc.active_slot_unlock_levels.is_empty() or int(lc.active_slot_unlock_levels[0]) != 1:
			print("[ContentRegistry/DRIFT] hero \"%s\" active_slot_unlock_levels must start at 1" % hid)
		var prev: int = -1
		for t in lc.active_slot_unlock_levels:
			if int(t) < prev:
				print("[ContentRegistry/DRIFT] hero \"%s\" active_slot_unlock_levels not sorted" % hid)
				break
			prev = int(t)


# Phase 3 — Naked Baseline executable guard (Preventive Bug Rule 4).
# Every hero's HeroData fallback must be attack-viable so a hero with NO
# weapon still fights (BALANCE.md invariant). Every WEAPON-slot item base
# carrying a WeaponProfileAbility must itself be attack-viable, and if it is
# hero-restricted, not regress that hero's authored damage. Warnings only.
func _assert_weapon_profiles() -> void:
	for h in heroes:
		if h == null or not ("attack_damage" in h):
			continue
		var hid: String = h.hero_id if "hero_id" in h else "?"
		var viable: bool = h.attack_damage > 0.0 and h.attack_speed > 0.0 \
			and (h.projectile_scene != null or h.attack_range > 0.0)
		if not viable:
			print("[ContentRegistry/DRIFT] hero \"%s\" fallback not attack-viable (Naked Baseline risk)" % hid)
	for b in item_bases:
		if b == null or not ("slot" in b) or int(b.slot) != 0:
			continue
		if not ("implicit_abilities" in b):
			continue
		for ab in b.implicit_abilities:
			if ab == null or not ("weapon_base_damage" in ab):
				continue  # not a WeaponProfileAbility
			var bid: String = b.base_id if "base_id" in b else b.resource_path
			var w_viable: bool = ab.projectile_scene != null or ab.weapon_attack_range > 0.0
			if not w_viable:
				print("[ContentRegistry/DRIFT] weapon \"%s\" profile not attack-viable (no projectile and no range)" % bid)
			for rid in b.hero_restriction:
				var hd: Resource = find_hero(rid)
				if hd != null and "attack_damage" in hd and ab.weapon_base_damage > 0.0 \
						and ab.weapon_base_damage < hd.attack_damage:
					print("[ContentRegistry/DRIFT] weapon \"%s\" damage %.2f < restricted hero \"%s\" base %.2f (regression)" % [bid, ab.weapon_base_damage, rid, hd.attack_damage])


# Phase 4 — body-profile consistency (Preventive Bug Rule 4: declarative
# flags must agree with the real mechanism, never a 2nd source of truth).
# A flying body must NOT block ground, and the only working never-block
# mechanism is HeroData.max_block_targets == 0 — assert the declaration
# matches it. Also assert role_tags agree with the profile. Warnings only.
func _assert_body_profiles() -> void:
	for h in heroes:
		if h == null or not ("body_profile" in h):
			continue
		var bp = h.body_profile
		if bp == null:
			continue  # null ⇒ DEFAULT_HUMANOID, always valid
		var hid: String = h.hero_id if "hero_id" in h else "?"
		if not ("is_flying" in bp):
			print("[ContentRegistry/DRIFT] hero \"%s\" body_profile is not a HeroBodyProfile" % hid)
			continue
		if bp.is_flying and bp.blocks_ground:
			print("[ContentRegistry/DRIFT] hero \"%s\" body is flying but blocks_ground=true (contradiction)" % hid)
		if bp.is_flying and "max_block_targets" in h and int(h.max_block_targets) != 0:
			print("[ContentRegistry/DRIFT] hero \"%s\" is flying but max_block_targets=%d (must be 0 — the real never-block mechanism)" % [hid, int(h.max_block_targets)])
		if not bp.blocks_ground and "max_block_targets" in h and int(h.max_block_targets) != 0:
			print("[ContentRegistry/DRIFT] hero \"%s\" blocks_ground=false but max_block_targets=%d (must be 0)" % [hid, int(h.max_block_targets)])
		var tags: Array = h.role_tags if "role_tags" in h else []
		if bp.is_flying and not tags.has("flying"):
			print("[ContentRegistry/DRIFT] hero \"%s\" body is flying but role_tags lacks \"flying\"" % hid)
		if (not bp.is_flying) and tags.has("flying"):
			print("[ContentRegistry/DRIFT] hero \"%s\" role_tags has \"flying\" but body is not flying" % hid)


# Phase 5 — TrapData lives on PlaceTrapSkillData (hero skills), not a
# standalone catalog. Validate any authored trap so a lifetime <= arm_time
# (never triggers) or max_active < 1 surfaces at boot. Warnings only. With
# no trap skill authored this iterates nothing (no-op, zero DRIFT).
func _assert_traps() -> void:
	for h in heroes:
		if h == null or not ("skills" in h):
			continue
		var hid: String = h.hero_id if "hero_id" in h else "?"
		for sk in h.skills:
			if sk == null or not ("trap_data" in sk):
				continue  # not a PlaceTrapSkillData
			var td = sk.trap_data
			if td == null:
				print("[ContentRegistry/DRIFT] hero \"%s\" trap skill has null trap_data" % hid)
				continue
			if not ("max_active" in td):
				print("[ContentRegistry/DRIFT] hero \"%s\" trap_data is not a TrapData" % hid)
				continue
			if int(td.max_active) < 1:
				print("[ContentRegistry/DRIFT] trap \"%s\" max_active < 1 (unusable)" % td.trap_id)
			if td.lifetime <= td.arm_time:
				print("[ContentRegistry/DRIFT] trap \"%s\" lifetime %.2f <= arm_time %.2f (never triggers)" % [td.trap_id, td.lifetime, td.arm_time])
			if td.radius <= 0.0:
				print("[ContentRegistry/DRIFT] trap \"%s\" radius <= 0 (hits nothing)" % td.trap_id)


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
