extends Node

# Pre-level player picks — survives runs, persisted by SaveManager. Distinct
# from MetaProgression: a level "starts" when this state is locked in, and a
# new run reads it without resetting it.
#
# Holds: selected hero, selected tower loadout (4-of-6 slots), per-hero
# equipped-skills loadout. All authored skill_ids the hero hasn't yet
# unlocked are filtered out of the loadout at read time (level-gated).
#
# Cross-domain reads:
#   - get_unlocked_skill_ids reads MetaProgression.get_hero_level to filter
#     by skill.level_required.
#   - ContentRegistry is read for hero/tower lookups and skill-author lists.

# Phase 47d-2: tower loadout. The build ring always renders TOWER_SLOT_MAX
# slots; slots beyond `tower_slot_cap` render locked (future progression).
# `selected_tower_ids` is the ORDERED list of up-to-cap tower_ids; missing
# entries = empty slots. Defaults to the four launch towers so an
# uninitialised save still plays correctly.
const TOWER_SLOT_MAX: int = 6
# EQUIPPED_SKILL_SLOTS is the *maximum* — the per-hero cap is dynamic and
# grows with hero level (see get_active_slot_cap). Phase 3B bumped the
# absolute cap from 2 to 3 to support the L8 third-active-slot unlock.
const EQUIPPED_SKILL_SLOTS: int = 3
const ACTIVE_SLOT_UNLOCK_LEVELS: Array[int] = [1, 8]

# Preloaded so the Kind enum is accessible from autoload code that compiles
# before class_name registration completes (autoloads race the registry).
const _HeroSkillNodeDataScript = preload("res://heroes/HeroSkillNodeData.gd")

# Phase 1 — passive slot caps grow with hero level. Each threshold opens one
# slot, so the cap = number of thresholds <= current level. Lv 1 = 1 slot,
# Lv 4 = 2 slots, Lv 9 = 3 slots. Mirrors a SLOT_UNLOCK node grant in the
# skill-tree node graph (the threshold list is the same numbers the
# corresponding SLOT_UNLOCK nodes carry).
const PASSIVE_SLOT_UNLOCK_LEVELS: Array[int] = [1, 4, 9]

var selected_hero_id: String = "hero_warrior"
var tower_slot_cap: int = 4
var selected_tower_ids: Array[String] = [
	"tower_archer", "tower_barracks", "tower_mage", "tower_artillery",
]

# Phase 48 — per-hero equipped-skill loadout. Keyed by hero_id; each value
# is Array[String] of length EQUIPPED_SKILL_SLOTS, with "" for empty slots.
# Missing keys fall through to _default_equipped_for() (first N unlocked).
var hero_equipped_skills: Dictionary = {}
# Phase 1 — per-hero equipped passives. Keyed by hero_id; each value is
# Array[String] of length get_passive_slot_cap(hero_id), with "" for empty
# slots. Missing keys fall through to _default_equipped_passives_for() (first
# N owned passives in tree order). Mirrors hero_equipped_skills end-to-end.
var hero_equipped_passives: Dictionary = {}
# Phase 2C — per-hero chosen skill mod, keyed (hero_id → {skill_id → mod_id}).
# A mod is "owned" when its MOD node is purchased; "chosen" when the player
# selects it as the active mod for that skill. Free toggle between owned
# mods. Missing key = no mod active. Self-heal drops mod_ids the tree no
# longer authors.
var hero_skill_mods: Dictionary = {}


func _ready() -> void:
	print("[LoadoutState] loaded — hero=%s towers=%s" % [selected_hero_id, str(selected_tower_ids)])


func reset() -> void:
	# Full wipe — called from Reset Progress. Restores defaults so a fresh
	# save plays correctly.
	selected_hero_id = "hero_warrior"
	# 2026-04-29 audit fix — these were missing in the old GameState.reset(),
	# leading to stale state surviving Reset Progress + persisted leakage from
	# TestRange's tower_slot_cap = 6 / 5-tower override.
	tower_slot_cap = 4
	reset_loadout_to_default()
	hero_equipped_skills = {}
	hero_equipped_passives = {}
	hero_skill_mods = {}


# Returns the TowerData resources in loadout order for the unlocked slots.
# - Elements beyond `tower_slot_cap` are never returned (player can't use them).
# - Entries referencing a missing/locked tower are skipped (the slot will
#   render empty in the ring).
# - No fallback to "all unlocked towers" — that asymmetry made LoadoutScreen
#   look populated while the build ring + LoadoutPickerScreen showed empty
#   slots. SaveManager's load-time self-heal (in _apply_save_data) guarantees
#   selected_tower_ids has the 4 defaults whenever the saved state has zero
#   usable entries, so a fallback here is unnecessary.
func get_loadout_towers() -> Array:
	var out: Array = []
	var limit: int = mini(tower_slot_cap, selected_tower_ids.size())
	for i in range(limit):
		var tid: String = selected_tower_ids[i]
		if tid == "":
			continue
		var data: Resource = ContentRegistry.find_tower(tid)
		if data == null:
			continue
		if not UnlockManager.is_tower_unlocked(tid):
			continue
		out.append(data)
	return out


# Set a single loadout slot (0 <= slot_idx < tower_slot_cap). If `tower_id`
# is already in another slot, those two slots SWAP to enforce the
# no-duplicates rule without making the player lose a pick. Empty tower_id
# clears the slot. Returns true when state actually changed (so the UI can
# persist / redraw).
func set_loadout_slot(slot_idx: int, tower_id: String) -> bool:
	if slot_idx < 0 or slot_idx >= tower_slot_cap:
		return false
	# Grow the array to cover the slot — preserves sparse positions.
	while selected_tower_ids.size() <= slot_idx:
		selected_tower_ids.append("")
	if tower_id != "":
		var existing: int = selected_tower_ids.find(tower_id)
		if existing == slot_idx:
			return false
		if existing >= 0:
			selected_tower_ids[existing] = selected_tower_ids[slot_idx]
	selected_tower_ids[slot_idx] = tower_id
	return true


func reset_loadout_to_default() -> void:
	selected_tower_ids = [
		"tower_archer", "tower_barracks", "tower_mage", "tower_artillery",
	]


# Phase 48 — equipped-skills loadout. Skills with level_required > current
# hero level are considered locked and never appear in the loadout.

# Returns the ordered Array[String] of skill_ids slotted for this hero.
# Length is always EQUIPPED_SKILL_SLOTS; "" entries mean empty slot.
# Defaults to the first N unlocked skills in author order on first read.
#
# Self-heals stale entries: any saved skill_id that the hero no longer
# authors (e.g. left over from before a skill rename / removal in a
# content update) is silently dropped to "" on read AND persisted back
# so the dict converges to a clean state. The previous version returned
# the stale string verbatim, which surfaced in HeroesHub's Skills tab as
# raw skill_id text ("rally", "shield_bash") for the equipped row.
# Phase 3B — active-slot cap. Mirrors get_passive_slot_cap. L1+ = 2 slots,
# L8+ = 3 slots. The constant EQUIPPED_SKILL_SLOTS (3) is the absolute max;
# this returns the per-hero current cap.
func get_active_slot_cap(hero_id: String) -> int:
	if hero_id == "":
		return ACTIVE_SLOT_UNLOCK_LEVELS.size()  # default to max for safety
	var lvl: int = MetaProgression.get_hero_level(hero_id)
	# Phase 2 — unlock levels come from the hero's level curve; unauthored
	# curve returns [1, 8] == ACTIVE_SLOT_UNLOCK_LEVELS (byte-identical).
	var thresholds: Array = ACTIVE_SLOT_UNLOCK_LEVELS
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data != null and hero_data.has_method("get_level_curve"):
		thresholds = hero_data.get_level_curve().active_slot_unlock_levels
	var cap: int = 0
	for threshold in thresholds:
		if lvl >= int(threshold):
			cap += 1
	return maxi(1, cap)


func get_equipped_skills(hero_id: String) -> Array[String]:
	# Defense in depth — never cache a default for a malformed hero_id.
	# Without this guard, `WorldMap._refresh_heroes_button_dot` looping
	# over ContentRegistry.heroes could write a "" entry into the save
	# dict if a hero with empty id slipped through.
	if hero_id == "":
		var empty: Array[String] = []
		for _i in EQUIPPED_SKILL_SLOTS:
			empty.append("")
		return empty
	var cap: int = get_active_slot_cap(hero_id)
	if not hero_equipped_skills.has(hero_id):
		hero_equipped_skills[hero_id] = _default_equipped_for(hero_id)
	var raw: Array = hero_equipped_skills[hero_id]
	var authored: Array[String] = _authored_skill_ids(hero_id)
	var out: Array[String] = []
	var any_purged: bool = false
	for i in cap:
		var sid: String = str(raw[i]) if i < raw.size() else ""
		# Drop sids the hero no longer authors. Empty authored = ContentRegistry
		# isn't ready yet (e.g. very early boot); skip the purge in that case
		# so we don't wipe a valid loadout while waiting for the registry.
		if sid != "" and not authored.is_empty() and not (sid in authored):
			sid = ""
			any_purged = true
		out.append(sid)
	# Persist the cleaned form so subsequent reads (and the next save)
	# see the converged state rather than re-purging on every call. We size
	# storage to cap (not constant) so a level-up that grows the cap pads
	# with "" on the next read.
	if any_purged or raw.size() != cap:
		var stored: Array = []
		for s in out:
			stored.append(s)
		hero_equipped_skills[hero_id] = stored
	return out


# All skill_ids the hero authors today (regardless of level_required).
# Used by get_equipped_skills to drop stale entries pointing at skills
# that no longer exist on the hero.
func _authored_skill_ids(hero_id: String) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	for skill in hero_data.skills:
		if skill != null and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Returns all skill_ids on the hero with level_required <= current level.
# Order matches HeroData.skills (author order).
func get_unlocked_skill_ids(hero_id: String) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	var lvl: int = MetaProgression.get_hero_level(hero_id)
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr <= lvl and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Same shape as get_unlocked_skill_ids but only the ones unlocked exactly
# at `level` — used by BaseHero._level_up_apply() to fire the unlock toast.
func get_skills_unlocked_at_level(hero_id: String, level: int) -> Array[String]:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var out: Array[String] = []
	if hero_data == null or not ("skills" in hero_data):
		return out
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr == level and skill.skill_id != "":
			out.append(skill.skill_id)
	return out


# Set a single equipped slot. Mirrors set_loadout_slot's swap-on-duplicate
# rule: if `skill_id` is already in another slot, the two slots SWAP so the
# player doesn't lose a pick. Empty `skill_id` clears the slot. Returns
# true if state actually changed (so the UI persists / redraws).
func set_equipped_skill(hero_id: String, slot_idx: int, skill_id: String) -> bool:
	if hero_id == "" or slot_idx < 0 or slot_idx >= get_active_slot_cap(hero_id):
		return false
	# Reject locked skills — defense in depth; the UI should never offer them.
	if skill_id != "" and not (skill_id in get_unlocked_skill_ids(hero_id)):
		return false
	var current: Array[String] = get_equipped_skills(hero_id)
	# Track the swap source so we can emit a second signal for it. Listeners
	# that track per-slot state (vs full rebuilds) need to know BOTH slots
	# changed when a swap happens.
	var swap_from: int = -1
	if skill_id != "":
		var existing: int = current.find(skill_id)
		if existing == slot_idx:
			return false
		if existing >= 0:
			current[existing] = current[slot_idx]
			swap_from = existing
	current[slot_idx] = skill_id
	# Store back as untyped Array (Godot Dictionary loses Array[String] typing
	# on assignment anyway; get_equipped_skills coerces on read).
	var stored: Array = []
	for s in current:
		stored.append(s)
	hero_equipped_skills[hero_id] = stored
	EventBus.hero_skill_equipped.emit(hero_id, slot_idx, skill_id)
	if swap_from >= 0:
		EventBus.hero_skill_equipped.emit(hero_id, swap_from, current[swap_from])
	return true


# Returns true if the hero has any unlocked skill that isn't currently in
# their equipped loadout. Drives the WorldMap notification dot.
func has_unequipped_skills(hero_id: String) -> bool:
	var equipped: Array[String] = get_equipped_skills(hero_id)
	for sid in get_unlocked_skill_ids(hero_id):
		if not (sid in equipped):
			return true
	return false


func _default_equipped_for(hero_id: String) -> Array:
	# Resolves the hero's starter loadout. Two paths:
	#   1. HeroData.starter_skill_ids (authored explicit order) — preferred.
	#      Entries are filtered through unlocked_skill_ids so locked /
	#      renamed / removed ids drop silently. Order is preserved.
	#   2. Fallback: first N unlocked in author order. Mirrors the original
	#      implicit rule for heroes that haven't authored starter_skill_ids.
	# Pads with "" to the current active slot cap. Re-sizes naturally on
	# level-up because get_equipped_skills re-reads cap every call.
	var cap: int = get_active_slot_cap(hero_id)
	var unlocked: Array[String] = get_unlocked_skill_ids(hero_id)
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var authored: Array = []
	if hero_data != null and "starter_skill_ids" in hero_data:
		for sid in hero_data.starter_skill_ids:
			var s: String = String(sid)
			if s != "" and s in unlocked:
				authored.append(s)
	var source: Array = authored if not authored.is_empty() else unlocked
	var out: Array = []
	for i in cap:
		out.append(source[i] if i < source.size() else "")
	return out


# Called by the Skills page "Reset to default" button. Resolves the hero's
# starter loadout and writes it back, firing per-slot equip signals so the
# in-level SkillBar (if open) and any listening UI stays consistent. No-op
# if the resolved default already matches the current loadout.
func reset_active_loadout_to_default(hero_id: String) -> bool:
	if hero_id == "":
		return false
	var cap: int = get_active_slot_cap(hero_id)
	var defaults: Array = _default_equipped_for(hero_id)
	var current: Array[String] = get_equipped_skills(hero_id)
	var changed: bool = false
	for i in cap:
		var want: String = String(defaults[i]) if i < defaults.size() else ""
		var have: String = current[i] if i < current.size() else ""
		if want == have:
			continue
		if set_equipped_skill(hero_id, i, want):
			changed = true
	return changed


# ── Equipped passives (Phase 1) ─────────────────────────────────────────
#
# Same shape as equipped skills, but the slot cap is dynamic (grows with hero
# level) and the pool is the hero's HeroSkillTreeData.get_passive_ids(). A
# passive is "owned" when MetaProgression.get_purchased_passive_rank > 0 —
# only owned passives can occupy a slot.

func get_passive_slot_cap(hero_id: String) -> int:
	if hero_id == "":
		return 1
	var lvl: int = MetaProgression.get_hero_level(hero_id)
	var cap: int = 0
	for threshold in PASSIVE_SLOT_UNLOCK_LEVELS:
		if lvl >= threshold:
			cap += 1
	return maxi(1, cap)


# All passive_ids on the hero's tree (regardless of ownership). Used to
# self-heal stale entries pointing at passives the tree no longer authors.
func _authored_passive_ids(hero_id: String) -> Array[String]:
	if not has_node("/root/ContentRegistry"):
		return []
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null or not tree.has_method("get_passive_ids"):
		return []
	return tree.get_passive_ids()


func get_equipped_passives(hero_id: String) -> Array[String]:
	if hero_id == "":
		return []
	var cap: int = get_passive_slot_cap(hero_id)
	if not hero_equipped_passives.has(hero_id):
		hero_equipped_passives[hero_id] = _default_equipped_passives_for(hero_id, cap)
	var raw: Array = hero_equipped_passives[hero_id]
	var pool: Array[String] = _authored_passive_ids(hero_id)
	var out: Array[String] = []
	var any_purged: bool = false
	for i in cap:
		var pid: String = str(raw[i]) if i < raw.size() else ""
		# Drop pids the tree no longer authors. Empty pool = ContentRegistry
		# isn't ready yet (early boot); skip the purge so a valid loadout
		# isn't wiped while waiting for the registry.
		if pid != "" and not pool.is_empty() and not (pid in pool):
			pid = ""
			any_purged = true
		out.append(pid)
	if any_purged or raw.size() != cap:
		var stored: Array = []
		for s in out:
			stored.append(s)
		hero_equipped_passives[hero_id] = stored
	return out


func set_equipped_passive(hero_id: String, slot_idx: int, passive_id: String) -> bool:
	if hero_id == "":
		return false
	var cap: int = get_passive_slot_cap(hero_id)
	if slot_idx < 0 or slot_idx >= cap:
		return false
	# Defense in depth — never equip an unowned passive. UI should grey out
	# the entry already; this guards against stale callers.
	if passive_id != "" and MetaProgression.get_purchased_passive_rank(hero_id, passive_id) == 0:
		return false
	var current: Array[String] = get_equipped_passives(hero_id)
	var swap_from: int = -1
	if passive_id != "":
		var existing: int = current.find(passive_id)
		if existing == slot_idx:
			return false
		if existing >= 0:
			current[existing] = current[slot_idx]
			swap_from = existing
	current[slot_idx] = passive_id
	var stored: Array = []
	for s in current:
		stored.append(s)
	hero_equipped_passives[hero_id] = stored
	EventBus.hero_passive_equipped.emit(hero_id, slot_idx, passive_id)
	if swap_from >= 0:
		EventBus.hero_passive_equipped.emit(hero_id, swap_from, current[swap_from])
	return true


func _default_equipped_passives_for(hero_id: String, cap: int) -> Array:
	# First `cap` *owned* passives in tree order; pad with "". Owned = the
	# player has purchased the R1 node for that passive_id.
	var pool: Array[String] = _authored_passive_ids(hero_id)
	var owned: Array[String] = []
	for pid in pool:
		if MetaProgression.get_purchased_passive_rank(hero_id, pid) > 0:
			owned.append(pid)
	var out: Array = []
	for i in cap:
		out.append(owned[i] if i < owned.size() else "")
	return out


# ── Chosen skill mods (Phase 2C) ────────────────────────────────────────
#
# A mod is "owned" when the player has purchased its MOD node. "Chosen"
# when LoadoutState.hero_skill_mods[hero_id][skill_id] == mod_id. Buying a
# mod doesn't auto-select; the player taps an OWNED mod card to make it
# the active sidegrade for that skill. Free toggle between owned mods.

func get_chosen_mod(hero_id: String, skill_id: String) -> String:
	if hero_id == "" or skill_id == "":
		return ""
	if not hero_skill_mods.has(hero_id):
		return ""
	var per_hero: Dictionary = hero_skill_mods[hero_id]
	var mod_id: String = str(per_hero.get(skill_id, ""))
	if mod_id == "":
		return ""
	# Self-heal: if the chosen mod is no longer authored OR no longer owned,
	# drop it. Mirrors get_equipped_passives' purge-on-read pattern.
	if not _is_mod_owned(hero_id, mod_id):
		per_hero.erase(skill_id)
		return ""
	return mod_id


func set_chosen_mod(hero_id: String, skill_id: String, mod_id: String) -> bool:
	if hero_id == "" or skill_id == "":
		return false
	if mod_id != "" and not _is_mod_owned(hero_id, mod_id):
		return false
	if not hero_skill_mods.has(hero_id):
		hero_skill_mods[hero_id] = {}
	var per_hero: Dictionary = hero_skill_mods[hero_id]
	if str(per_hero.get(skill_id, "")) == mod_id:
		return false
	if mod_id == "":
		per_hero.erase(skill_id)
	else:
		per_hero[skill_id] = mod_id
	EventBus.hero_skill_mod_chosen.emit(hero_id, skill_id, mod_id)
	return true


# Find the SkillModData on the hero's tree for a given mod_id. The MOD node
# carries the SkillModData on its `ability` field (one Resource slot serves
# both kinds — see HeroSkillNodeData docstring). Returns null on miss.
func find_skill_mod(hero_id: String, mod_id: String) -> Resource:
	if hero_id == "" or mod_id == "":
		return null
	if not has_node("/root/ContentRegistry"):
		return null
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null:
		return null
	for node in tree.nodes:
		if node == null or not ("kind" in node):
			continue
		if int(node.kind) != _HeroSkillNodeDataScript.Kind.MOD:
			continue
		var mod: Resource = node.ability
		if mod == null or not ("mod_id" in mod):
			continue
		if String(mod.mod_id) == mod_id:
			return mod
	return null


# True if the player owns the MOD node carrying this mod_id (i.e. purchased
# the node at rank ≥ 1).
func _is_mod_owned(hero_id: String, mod_id: String) -> bool:
	if not has_node("/root/ContentRegistry"):
		return false
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null:
		return false
	for node in tree.nodes:
		if node == null or not ("kind" in node):
			continue
		if int(node.kind) != _HeroSkillNodeDataScript.Kind.MOD:
			continue
		var mod: Resource = node.ability
		if mod == null or not ("mod_id" in mod):
			continue
		if String(mod.mod_id) != mod_id:
			continue
		return MetaProgression.get_purchased_rank(hero_id, String(node.node_id)) >= 1
	return false


# ── Player Power Tier (PPT) ─────────────────────────────────────────────
#
# Single scalar summarizing the loadout's strength — see balance/BALANCE.md
# "Player Power Tier (PPT)". The audit screen compares per-level
# `target_ppt` against this. A Naked Baseline warrior (default everything,
# starter gear only) should compute close to ~1.0; mid-campaign loadouts
# trend toward 2–4; endgame toward 5+.
#
# Weights deliberately bias toward hero+gear (40%+30%) since those move the
# most across a campaign. Tower loadout contributes only 10% — towers are a
# *pick*, not a *power upgrade* (everyone has access from level 1).
const _PPT_W_HERO: float = 0.4
const _PPT_W_SKILLS: float = 0.2
const _PPT_W_ITEMS: float = 0.3
const _PPT_W_TOWERS: float = 0.1
const _PPT_BONUS_PER_TALENT: float = 0.1
const _PPT_BONUS_PER_UPGRADE: float = 0.1
# Bonus contributions cap so a player can't grind upgrades to infinity.
const _PPT_BONUS_CAP: float = 1.0


func get_effective_ppt() -> float:
	var total: float = 0.0
	# Hero
	var hero_data: Resource = ContentRegistry.find_hero(selected_hero_id)
	var hero_ppt: float = float(hero_data.power_tier) if hero_data != null and "power_tier" in hero_data else 1.0
	total += hero_ppt * _PPT_W_HERO
	# Equipped skills — average over slots, treat empty as 0
	var skills_total: float = 0.0
	var skills_count: int = 0
	if hero_data != null and "skills" in hero_data:
		var equipped: Array[String] = get_equipped_skills(selected_hero_id)
		for sid in equipped:
			if sid == "":
				continue
			for skill in hero_data.skills:
				if skill != null and skill.skill_id == sid:
					skills_total += float(skill.power_tier) if "power_tier" in skill else 1.0
					skills_count += 1
					break
	var skills_avg: float = (skills_total / float(skills_count)) if skills_count > 0 else 0.0
	total += skills_avg * _PPT_W_SKILLS
	# Equipped items — average over equipped instances, resolved via base
	var items_total: float = 0.0
	var items_count: int = 0
	if Engine.has_singleton("InventoryManager") or has_node("/root/InventoryManager"):
		var equipped_items: Array = InventoryManager.get_all_equipped(selected_hero_id)
		for inst in equipped_items:
			if inst == null:
				continue
			var base: Resource = ContentRegistry.find_item_base(inst.base_id)
			if base == null:
				continue
			items_total += float(base.resolve_power_tier()) if base.has_method("resolve_power_tier") else 1.0
			items_count += 1
	var items_avg: float = (items_total / float(items_count)) if items_count > 0 else 0.0
	total += items_avg * _PPT_W_ITEMS
	# Tower loadout — average power_tier across selected_tower_ids
	var towers_total: float = 0.0
	var towers_count: int = 0
	for tid in selected_tower_ids:
		if tid == "":
			continue
		var tower_data: Resource = ContentRegistry.find_tower(tid)
		if tower_data == null:
			continue
		towers_total += float(tower_data.power_tier) if "power_tier" in tower_data else 1.0
		towers_count += 1
	var towers_avg: float = (towers_total / float(towers_count)) if towers_count > 0 else 0.0
	total += towers_avg * _PPT_W_TOWERS
	# Bonus contributions from skill-tree purchases on the SELECTED hero, plus
	# legacy talents (zero post-migration but still counted for un-migrated
	# saves), plus meta upgrades. Scoped to selected_hero_id because PPT
	# represents the *current run* loadout power — Mage's capstone shouldn't
	# raise Knight's PPT when Knight is the selected hero. Nodes counted:
	# any PASSIVE_RANK / MOD / CAPSTONE the player has purchased on the
	# selected hero. SLOT_UNLOCK + bare ACTIVE_RANK don't count (they don't
	# change combat numbers themselves).
	var node_count: int = 0
	var talent_count: int = 0
	var upgrade_count: int = 0
	if has_node("/root/MetaProgression"):
		# Legacy talents — scoped to selected hero only (matches new behavior).
		var legacy_talents: Array = MetaProgression.hero_talents.get(selected_hero_id, [])
		talent_count = legacy_talents.size()
		upgrade_count = MetaProgression.purchased_upgrades.size()
		# Skill-tree nodes — selected hero only. Mirrors the purge-on-read
		# self-heal in get_equipped_skills: stale node_ids (renamed / removed
		# nodes, or any node_id for a hero whose tree was removed entirely)
		# are erased from MetaProgression so the dict converges instead of
		# accumulating forever. Boot guard: skip only when ContentRegistry
		# hasn't loaded any trees yet (true "registry not ready") — otherwise
		# a null per-hero tree means every stored node_id is definitively
		# stale and safe to purge.
		var per_hero: Dictionary = MetaProgression.hero_skill_nodes.get(selected_hero_id, {})
		var tree: Resource = ContentRegistry.find_skill_tree(selected_hero_id)
		var registry_cold: bool = ContentRegistry.skill_trees.is_empty()
		if not registry_cold and not per_hero.is_empty():
			var to_purge: Array[String] = []
			for node_id in per_hero.keys():
				var node: Resource = tree.find_node(String(node_id)) if tree != null else null
				if node == null:
					to_purge.append(String(node_id))
					continue
				var k: int = int(node.kind)
				if k == _HeroSkillNodeDataScript.Kind.PASSIVE_RANK \
						or k == _HeroSkillNodeDataScript.Kind.MOD \
						or k == _HeroSkillNodeDataScript.Kind.CAPSTONE:
					node_count += 1
			if not to_purge.is_empty():
				for stale_id in to_purge:
					per_hero.erase(stale_id)
				MetaProgression.hero_skill_nodes[selected_hero_id] = per_hero
				# Symmetry with get_equipped_skills' purge-on-read: write the
				# cleaned dict back to memory, but DON'T persist from a getter.
				# The next legitimate save site (node purchase, hero swap,
				# level end) will flush the cleaned form. Keeping disk I/O out
				# of read paths is what the audit smell flagged.
	var talent_bonus: float = minf(_PPT_BONUS_CAP, float(talent_count) * _PPT_BONUS_PER_TALENT)
	var node_bonus: float = minf(_PPT_BONUS_CAP, float(node_count) * _PPT_BONUS_PER_TALENT)
	var upgrade_bonus: float = minf(_PPT_BONUS_CAP, float(upgrade_count) * _PPT_BONUS_PER_UPGRADE)
	total += talent_bonus + node_bonus + upgrade_bonus
	return total
