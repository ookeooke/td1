extends Node

# Cross-run progression — survives runs, restarts, scene transitions. Only
# cleared by SaveManager.delete_save() (Reset Progress) or save migration.
# Persisted to disk by SaveManager via flat top-level keys.
#
# Holds: stars per level, mode-completion flags (heroic/iron), purchased
# meta-upgrades + cached modifiers, per-hero talents, per-hero XP/level,
# per-level best times + endless high scores, encyclopedia (discovered
# content), endless leaderboard, meta_gold (sell-loop currency),
# unlocked_content (IAP/star-gate unlock cache).
#
# Cross-domain reads:
#   - submit_endless_score takes wave: int as a parameter (caller supplies
#     RunState.wave_number) so this autoload doesn't read RunState directly.
#   - record_stars takes mode/level_id/stars as parameters from RunState.

# Mirrors UpgradeData.EffectType so call sites don't use magic ints.
# Values must match the enum in progression/UpgradeData.gd exactly.
const MOD_ARCHER_DAMAGE: int = 0
const MOD_TOWER_RANGE: int = 1
const MOD_HERO_HEALTH: int = 2
const MOD_HERO_DAMAGE: int = 3
const MOD_HERO_XP: int = 4
# 5 is `_RETIRED_SPELL_COOLDOWN` on UpgradeData.EffectType — slot kept so
# STARTING_GOLD = 6 and SOLDIER_HEALTH = 7 stay at the values existing
# .tres files serialize. Don't fill 5 with a new effect; pick the next
# free integer (8) for additions.
const MOD_STARTING_GOLD: int = 6
const MOD_SOLDIER_HEALTH: int = 7

const LEADERBOARD_MAX_ENTRIES: int = 20

# Preloaded so the Kind enum is accessible from autoload code that compiles
# before the class_name registry (autoloads load before scene scripts).
const _HeroSkillNodeDataScript = preload("res://heroes/HeroSkillNodeData.gd")

# Progression state — survives level restarts and scene transitions. Only
# cleared by a full reset(). SaveManager (Phase 27) reads/writes these
# dictionaries on boot / on level-complete.
var level_stars: Dictionary = {"level_1": 0}     # level_id → best campaign star count (0–3)
var levels_unlocked: Dictionary = {"level_1": true}  # level_id → true
# Phase 31: challenge mode completions (per level).
var heroic_complete: Dictionary = {}   # level_id → true
var iron_complete: Dictionary = {}     # level_id → true
var purchased_upgrades: Array[String] = []
var encyclopedia_unlocked: Array[String] = []  # content IDs unlocked by first encounter
var unlocked_content: Array[String] = []       # explicitly unlocked (IAP, star-gate, event)
# Per-hero purchased talents: hero_id → Array[String] of talent_ids.
var hero_talents: Dictionary = {}
var endless_best_score: int = 0
# WorldMap unlock-celebration handoff. SaveManager._try_unlock_next_level
# stores the just-unlocked level_id here; WorldMap._build_level_entries reads
# it on entry, plays the road-reveal + marker-pop animation, then clears it.
# Persisted so a force-quit between unlock and the next WorldMap visit still
# triggers the celebration. Empty string means no pending celebration.
var pending_unlock_celebration_id: String = ""
# Persistent meta-currency for the inventory sell loop. Earned by selling
# unwanted items; future Town phases (Buy / Smith) will spend it. Distinct
# from `gold`, which is per-run and resets every level.
var meta_gold: int = 0
# Per-level fastest completion time (campaign mode only). Seconds as float.
# Only wall-time spent in the level is counted; pause doesn't add (Main.gd
# accumulates process_delta which stops during PAUSE_MODE_STOP).
var level_best_times: Dictionary = {}    # level_id -> seconds (float)
# Per-level endless high score. Extension of the single endless_best_score
# so each map's endless mode can be compared independently.
var level_endless_best_scores: Dictionary = {}   # level_id -> int
# Phase 48 — persistent hero XP/level. Keyed by hero_id. Each entry:
# { "level": int, "xp": int }. Previously per-run on BaseHero — migrated here
# so progression survives runs. SaveManager persists the whole dict.
var hero_progress: Dictionary = {}
# Phase 1 — per-hero skill-point pool. +1 granted on every level-up; spent on
# HeroSkillNodeData purchases. Keyed by hero_id → unspent int.
var hero_skill_points: Dictionary = {}
# Phase 1 — per-hero purchased node ranks. {hero_id → {node_id: rank_purchased}}.
# `rank_purchased` is the rank value of the highest-rank node bought for that
# id. Cumulative tree: R2 implies R1, so a runtime ability stacker iterates all
# tree nodes whose `rank` <= purchased rank.
var hero_skill_nodes: Dictionary = {}
# Local leaderboard — top 20 entries, sorted descending. Each entry:
# { "name": String, "score": int, "wave": int }
# Phase 33 online: replace with HTTP fetch from a leaderboard service.
var endless_leaderboard: Array = []

# Precomputed modifier cache — rebuilt by rebuild_upgrade_cache() after any
# purchase. Game systems call get_upgrade_multiplier() / get_upgrade_bonus().
var _upgrade_mult_cache: Dictionary = {}   # EffectType (int) → float product
var _upgrade_add_cache: Dictionary = {}    # EffectType (int) → float sum
var _spent_stars_cache: int = 0


func _ready() -> void:
	# Phase 34: auto-unlock encyclopedia on first encounter.
	EventBus.enemy_spawned.connect(_on_enemy_spawned_for_encyclopedia)
	EventBus.tower_built.connect(_on_tower_built_for_encyclopedia)
	EventBus.hero_spawned.connect(_on_hero_spawned_for_encyclopedia)
	print("[MetaProgression] loaded — %d levels tracked" % level_stars.size())


# Bundles SaveManager.save_game() so every mutator on this autoload persists
# immediately. Mirrors InventoryManager._persist() (Preventive Bug Rule 2 in
# CLAUDE.md). Missing this on MetaProgression was the root cause of the
# 2026-05-14 save-loss bug: XP gain, level-ups, tree-node purchases, and
# meta-gold changes were updating state in-memory but never reaching disk,
# so closing Godot rolled the hero back to the last externally-triggered
# save (LoadoutPicker / WorldMap celebration / etc.). Test Range guard
# inside SaveManager.save_game already prevents sandbox runs from clobbering
# the production save, so this is safe to call freely.
func _persist() -> void:
	if has_node("/root/SaveManager"):
		SaveManager.save_game()


func reset() -> void:
	# Full wipe — called from Reset Progress. Clears every persistent dict
	# and rebuilds the upgrade cache from a zero state.
	level_stars = {"level_1": 0}
	levels_unlocked = {"level_1": true}
	heroic_complete = {}
	iron_complete = {}
	purchased_upgrades = []
	_upgrade_mult_cache.clear()
	_upgrade_add_cache.clear()
	_spent_stars_cache = 0
	endless_best_score = 0
	endless_leaderboard = []
	meta_gold = 0
	pending_unlock_celebration_id = ""
	encyclopedia_unlocked = []
	unlocked_content = []
	hero_talents = {}
	hero_progress = {}
	hero_skill_points = {}
	hero_skill_nodes = {}
	level_best_times = {}
	level_endless_best_scores = {}


# ── Encyclopedia ────────────────────────────────────────────────────────

func try_unlock_encyclopedia(content_id: String) -> void:
	if content_id == "" or content_id in encyclopedia_unlocked:
		return
	encyclopedia_unlocked.append(content_id)
	EventBus.encyclopedia_entry_unlocked.emit(content_id)
	_persist()


func _on_enemy_spawned_for_encyclopedia(enemy: Node, _path_id: String) -> void:
	if enemy != null and "data" in enemy and enemy.data != null and "enemy_id" in enemy.data:
		try_unlock_encyclopedia(enemy.data.enemy_id)


func _on_tower_built_for_encyclopedia(tower: Node, _spot_id: String) -> void:
	if tower != null and "data" in tower and tower.data != null:
		try_unlock_encyclopedia(tower.data.tower_id)


func _on_hero_spawned_for_encyclopedia(hero: Node) -> void:
	if hero != null and "data" in hero and hero.data != null:
		try_unlock_encyclopedia(hero.data.hero_id)


# ── Endless leaderboard ─────────────────────────────────────────────────

# `wave` is RunState.wave_number at submission time — caller passes it so
# this autoload doesn't read RunState directly.
func submit_endless_score(player_name: String, final_score: int, wave: int) -> void:
	var entry: Dictionary = {
		"name": player_name,
		"score": final_score,
		"wave": wave,
	}
	endless_leaderboard.append(entry)
	endless_leaderboard.sort_custom(func(a, b): return a.score > b.score)
	if endless_leaderboard.size() > LEADERBOARD_MAX_ENTRIES:
		endless_leaderboard.resize(LEADERBOARD_MAX_ENTRIES)
	EventBus.leaderboard_score_submitted.emit(final_score)
	_persist()


# ── Best-time / endless-best-score tracking ─────────────────────────────

# Phase 48 — best-time tracking. Returns true iff this was a new best
# (either the level had no prior time or the new time is faster).
func try_record_best_time(level_id: String, seconds: float) -> bool:
	if level_id == "" or seconds <= 0.0:
		return false
	var prev: float = float(level_best_times.get(level_id, -1.0))
	if prev < 0.0 or seconds < prev:
		level_best_times[level_id] = seconds
		_persist()
		return true
	return false


func get_best_time(level_id: String) -> float:
	return float(level_best_times.get(level_id, -1.0))


# Per-level endless high score. Returns true iff new best.
func try_record_endless_score(level_id: String, run_score: int) -> bool:
	if level_id == "" or run_score <= 0:
		return false
	var prev: int = int(level_endless_best_scores.get(level_id, 0))
	if run_score > prev:
		level_endless_best_scores[level_id] = run_score
		_persist()
		return true
	return false


func get_endless_best_score(level_id: String) -> int:
	return int(level_endless_best_scores.get(level_id, 0))


# ── Stars / mode completion ─────────────────────────────────────────────

# Caller (RunState consumer in GameOverScreen) passes mode + level_id +
# stars from the run. This avoids MetaProgression reading RunState.
func record_stars(mode: String, level_id: String, stars: int) -> void:
	# Persist the better of current run vs. previous best into the in-memory
	# progression dictionary, then flush to disk via _persist().
	# All three branches require stars > 0 — a 0-star "result" is a defeat,
	# which should never flip heroic/iron completion bools or bump campaign
	# stars. Defense in depth: the caller (GameOverScreen._on_continue_pressed)
	# already gates by stars_earned > 0, but a stray future call site that
	# forgets the outer gate can't pollute progression because of this guard.
	if stars <= 0:
		return
	if mode == "campaign":
		var prev: int = level_stars.get(level_id, 0)
		level_stars[level_id] = maxi(prev, stars)
	elif mode == "heroic":
		heroic_complete[level_id] = true
	elif mode == "iron":
		iron_complete[level_id] = true
	_persist()


func is_heroic_unlocked(level_id: String) -> bool:
	return level_stars.get(level_id, 0) >= 3


func is_iron_unlocked(level_id: String) -> bool:
	return heroic_complete.get(level_id, false)


# Returns the level_id of the highest-unlock_order level the player has
# unlocked. Empty string if no levels are unlocked (fresh save with the
# default level_1 entry should still return "level_1"). Used by WorldMap
# to auto-scroll to the player's "next" content on open. CORE RULE 16:
# load() the registry, never preload — class_name shared resources race.
func get_highest_unlocked_level_id() -> String:
	var registry: Resource = load("res://ui/world_map/level_list.tres")
	if registry == null:
		return ""
	var best_id: String = ""
	var best_order: int = -1
	for ld in registry.levels:
		if ld == null:
			continue
		if not levels_unlocked.get(ld.level_id, false):
			continue
		if int(ld.unlock_order) > best_order:
			best_order = int(ld.unlock_order)
			best_id = String(ld.level_id)
	return best_id


func calculate_total_stars_for_level(level_id: String) -> int:
	var total: int = level_stars.get(level_id, 0)  # 0–3 campaign
	if heroic_complete.get(level_id, false):
		total += 1
	if iron_complete.get(level_id, false):
		total += 1
	return total  # 0–5


func get_total_stars() -> int:
	var total: int = 0
	for id in level_stars.keys():
		total += calculate_total_stars_for_level(id)
	return total


func get_spent_stars() -> int:
	# Requires access to UpgradeData costs. Since MetaProgression doesn't
	# hold the upgrade registry, the UpgradeTree scene passes the cost sum
	# here when it loads. For between-scene use, we cache the total cost.
	return _spent_stars_cache


func get_spent_talent_stars() -> int:
	# Caller must pass talent data to compute cost. For simplicity,
	# we iterate all heroes' talents via ContentRegistry.
	var total: int = 0
	for hero_data in ContentRegistry.heroes:
		if hero_data == null or not ("talents" in hero_data):
			continue
		var purchased: Array = hero_talents.get(hero_data.hero_id, [])
		for talent in hero_data.talents:
			if talent != null and talent.talent_id in purchased:
				total += int(talent.star_cost)
	return total


func get_available_stars() -> int:
	return get_total_stars() - get_spent_stars() - get_spent_talent_stars()


func set_spent_stars_cache(amount: int) -> void:
	_spent_stars_cache = amount


# ── Meta-upgrade modifier API ───────────────────────────────────────────

# UpgradeData.EffectType values are used as keys.
# MULT types: product of all purchased (default 1.0).
# BONUS types: sum of all purchased (default 0.0).
func get_upgrade_multiplier(effect_type: int) -> float:
	return _upgrade_mult_cache.get(effect_type, 1.0)


func get_upgrade_bonus(effect_type: int) -> float:
	return _upgrade_add_cache.get(effect_type, 0.0)


func rebuild_upgrade_cache(all_upgrades: Array) -> void:
	_upgrade_mult_cache.clear()
	_upgrade_add_cache.clear()
	var total_cost: int = 0
	for data in all_upgrades:
		if data == null or not (data.upgrade_id in purchased_upgrades):
			continue
		total_cost += int(data.star_cost)
		var etype: int = int(data.effect_type)
		# STARTING_GOLD_BONUS is additive; everything else multiplicative.
		if etype == MOD_STARTING_GOLD:
			_upgrade_add_cache[etype] = _upgrade_add_cache.get(etype, 0.0) + data.effect_value
		else:
			_upgrade_mult_cache[etype] = _upgrade_mult_cache.get(etype, 1.0) * data.effect_value
	_spent_stars_cache = total_cost


# ── Meta-currency ───────────────────────────────────────────────────────

func add_meta_gold(amount: int) -> void:
	if amount == 0:
		return
	meta_gold += amount
	EventBus.meta_gold_changed.emit(meta_gold)
	_persist()


func spend_meta_gold(amount: int) -> bool:
	if amount > meta_gold:
		return false
	meta_gold -= amount
	EventBus.meta_gold_changed.emit(meta_gold)
	_persist()
	return true


# ── Hero XP / level ─────────────────────────────────────────────────────

# Phase 48 — persistent hero progression helpers. Level-up math lives here
# (not on BaseHero) so XP survives runs. BaseHero reads level/XP on spawn
# and delegates gain_xp back into add_hero_xp.
func get_hero_level(hero_id: String) -> int:
	if not hero_progress.has(hero_id):
		return 1
	return int(hero_progress[hero_id].get("level", 1))


func get_hero_xp(hero_id: String) -> int:
	if not hero_progress.has(hero_id):
		return 0
	return int(hero_progress[hero_id].get("xp", 0))


func _ensure_hero_progress_entry(hero_id: String) -> void:
	if not hero_progress.has(hero_id):
		hero_progress[hero_id] = {"level": 1, "xp": 0, "last_synced_level": 1}
	# Backfill the cursor on entries that were created before the field was
	# added (post-load v4-migrated saves). Sync_hero_progression_to_level
	# is idempotent, so leaving this at 0 wouldn't crash, but seeding to the
	# current level matches the "this is a fresh entry, no catch-up needed"
	# invariant for newly-discovered heroes.
	var entry: Dictionary = hero_progress[hero_id]
	if not entry.has("last_synced_level"):
		entry["last_synced_level"] = int(entry.get("level", 1))


# ── Hero skill-tree progression ─────────────────────────────────────────
#
# Phase 1 — node graph progression. One point per level-up, spent on
# HeroSkillNodeData entries authored on the hero's HeroSkillTreeData. Two
# state dicts (hero_skill_points, hero_skill_nodes) are persisted by
# SaveManager; this section is the only writer. Cumulative tree: buying R2
# implies R1, so runtime stack iterators check `rank_purchased >= node.rank`.

func get_skill_points(hero_id: String) -> int:
	return int(hero_skill_points.get(hero_id, 0))


func add_hero_skill_points(hero_id: String, count: int) -> void:
	if hero_id == "" or count == 0:
		return
	hero_skill_points[hero_id] = get_skill_points(hero_id) + count
	EventBus.hero_skill_points_changed.emit(hero_id, get_skill_points(hero_id))
	_persist()


# Same dict mutation + signal emit as add_hero_skill_points, but skips
# _persist(). Used inside add_hero_xp / sync_hero_progression_to_level loops
# so the save flushes ONCE after the whole batch (level + xp + points +
# auto-slot-unlocks) is consistent. Without this, a mid-loop save could
# write the new skill points before hero_progress.level/xp catch up — a
# process kill in that window leaves the player with phantom points and
# stale XP/level on next boot.
# Phase 2 — points granted when `hero_id` reaches `lvl`, read from the
# hero's level curve. Default curve ⇒ +1 (historical). Resolved per-call so
# no per-hero state and no save reshape (CORE RULE 20).
func _points_for_level(hero_id: String, lvl: int) -> int:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null or not hero_data.has_method("get_level_curve"):
		return 1
	return hero_data.get_level_curve().points_for_level(lvl)


func _grant_skill_points_silent(hero_id: String, count: int) -> void:
	if hero_id == "" or count == 0:
		return
	hero_skill_points[hero_id] = get_skill_points(hero_id) + count
	EventBus.hero_skill_points_changed.emit(hero_id, get_skill_points(hero_id))


func get_purchased_rank(hero_id: String, node_id: String) -> int:
	if not hero_skill_nodes.has(hero_id):
		return 0
	var d: Dictionary = hero_skill_nodes[hero_id]
	return int(d.get(node_id, 0))


# Highest purchased rank across all PASSIVE_RANK nodes that target this
# passive_id. BaseHero uses this to decide how many ranks of the stacked
# ability to push onto AbilityHost on spawn.
func get_purchased_passive_rank(hero_id: String, passive_id: String) -> int:
	return _highest_purchased_rank(hero_id, _HeroSkillNodeDataScript.Kind.PASSIVE_RANK, passive_id)


# Phase 2 — same shape, ACTIVE_RANK nodes. BaseHero uses this to look up
# rank scaling on SkillData at cast time. R1 is implicit (every authored
# skill is at rank 1 by default), so a hero who never bought any ACTIVE_RANK
# nodes still gets at least 1.
func get_purchased_skill_rank(hero_id: String, skill_id: String) -> int:
	return maxi(1, _highest_purchased_rank(hero_id, _HeroSkillNodeDataScript.Kind.ACTIVE_RANK, skill_id))


# Internal: highest rank purchased across all nodes of `kind` matching
# `target_id`. Returns 0 if nothing matches (caller decides whether to clamp
# to 1 for R1-implicit semantics).
func _highest_purchased_rank(hero_id: String, kind: int, target_id: String) -> int:
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null:
		return 0
	var best: int = 0
	for n in tree.nodes:
		if n == null or not ("kind" in n):
			continue
		if int(n.kind) != kind:
			continue
		if String(n.target_id) != target_id:
			continue
		if get_purchased_rank(hero_id, String(n.node_id)) >= int(n.rank):
			best = maxi(best, int(n.rank))
	return best


# Inspectable purchase check — returns {ok, reason} so the UI can dim the
# BUY button AND tooltip the rejection reason ("0 points available",
# "Reach Lv 4 first", "Buy Rank 1 first").
func can_purchase_node(hero_id: String, node_id: String) -> Dictionary:
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null:
		return {"ok": false, "reason": "no skill tree"}
	var node: Resource = tree.find_node(node_id)
	if node == null:
		return {"ok": false, "reason": "unknown node"}
	if get_purchased_rank(hero_id, node_id) >= int(node.rank):
		return {"ok": false, "reason": "already purchased"}
	if get_skill_points(hero_id) < int(node.point_cost):
		return {"ok": false, "reason": "not enough points"}
	if get_hero_level(hero_id) < int(node.level_required):
		return {"ok": false, "reason": "level too low"}
	# Gate ACTIVE_RANK / MOD nodes by the target skill's own level_required —
	# without this, players can spend ★ on e.g. rally_cry_r2 at L3 while
	# Rally Cry itself unlocks at L6, wasting the point on an unusable skill.
	# Other Kinds (PASSIVE_RANK / CAPSTONE / SLOT_UNLOCK) don't target a
	# SkillData so this gate doesn't apply.
	var kind: int = int(node.kind)
	if kind == _HeroSkillNodeDataScript.Kind.ACTIVE_RANK \
			or kind == _HeroSkillNodeDataScript.Kind.MOD:
		var target_skill: Resource = _find_hero_skill(hero_id, String(node.target_id))
		if target_skill != null and "level_required" in target_skill:
			var skill_lvl_req: int = int(target_skill.level_required)
			if get_hero_level(hero_id) < skill_lvl_req:
				return {"ok": false, "reason": "skill unlocks at Lv %d" % skill_lvl_req}
	for pid in node.prerequisite_ids:
		if get_purchased_rank(hero_id, String(pid)) < 1:
			return {"ok": false, "reason": "missing prerequisite"}
	return {"ok": true, "reason": ""}


# Looks up the SkillData resource on a hero by skill_id. Returns null on miss
# (unknown hero / skill_id, or registry not yet ready). Used by
# can_purchase_node to gate tree-node purchases by their target skill's
# level_required.
func _find_hero_skill(hero_id: String, skill_id: String) -> Resource:
	if hero_id == "" or skill_id == "":
		return null
	if not has_node("/root/ContentRegistry"):
		return null
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null or not ("skills" in hero_data):
		return null
	for skill in hero_data.skills:
		if skill != null and "skill_id" in skill and String(skill.skill_id) == skill_id:
			return skill
	return null


# Phase 3R-followup — catch-up sync for heroes loaded from saves whose
# level outpaces the per-level grants (talent migration v4→v5, or any path
# where hero_progress.level was bumped without firing add_hero_xp's loop).
# Tracked via `last_synced_level` cursor inside the hero_progress entry so
# the discriminator persists and re-syncing is idempotent. Call from
# SaveManager.load_game once per hero after hero_progress restores.
func sync_hero_progression_to_level(hero_id: String) -> void:
	if hero_id == "" or not hero_progress.has(hero_id):
		return
	if not has_node("/root/ContentRegistry"):
		return  # tree lookup needs registry; defer until autoloads are ready
	var entry: Dictionary = hero_progress[hero_id]
	var target: int = int(entry.get("level", 1))
	var cursor: int = int(entry.get("last_synced_level", 0))
	if cursor >= target:
		return
	var granted: int = 0
	while cursor < target:
		cursor += 1
		# L1 is the starting level; no per-level grant. Per-level grants
		# begin at level 2 to match add_hero_xp's level-up loop semantics.
		# Use the silent variant — we want the entry["last_synced_level"]
		# write below to land in the SAME save as the granted points, not a
		# mid-loop flush that could leave the cursor stale on a process kill.
		if cursor > 1:
			var pts: int = _points_for_level(hero_id, cursor)
			_grant_skill_points_silent(hero_id, pts)
			granted += pts
		_auto_purchase_slot_unlocks_at_level(hero_id, cursor)
	entry["last_synced_level"] = cursor
	if granted > 0:
		print("[MetaProgression] catch-up synced %s through L%d (+%d points)" % [hero_id, target, granted])
	# Persist once at the end so cursor + points + auto-slot-unlocks all
	# hit disk together. Skip if nothing changed (early-return above already
	# covers the cursor-unchanged case, but defensively gate by granted > 0
	# so a no-grant SLOT_UNLOCK-only catch-up still saves the cursor).
	_persist()


# Phase 3P — auto-grant SLOT_UNLOCK nodes whose level threshold is met.
# These are point_cost=0 progression markers; the slot caps in LoadoutState
# already gate by hero level, so this just synchronises the tree UI's
# PURCHASED state. Idempotent — already-recorded nodes are skipped.
func _auto_purchase_slot_unlocks_at_level(hero_id: String, current_level: int) -> void:
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree == null:
		return
	if not hero_skill_nodes.has(hero_id):
		hero_skill_nodes[hero_id] = {}
	var d: Dictionary = hero_skill_nodes[hero_id]
	for n in tree.nodes:
		if n == null or not ("kind" in n):
			continue
		if int(n.kind) != _HeroSkillNodeDataScript.Kind.SLOT_UNLOCK:
			continue
		if int(n.level_required) > current_level:
			continue
		var nid: String = String(n.node_id)
		if d.has(nid):
			continue
		d[nid] = int(n.rank)
		EventBus.hero_node_purchased.emit(hero_id, nid)


func purchase_node(hero_id: String, node_id: String) -> bool:
	var check: Dictionary = can_purchase_node(hero_id, node_id)
	if not check.ok:
		return false
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	var node: Resource = tree.find_node(node_id)
	hero_skill_points[hero_id] = get_skill_points(hero_id) - int(node.point_cost)
	if not hero_skill_nodes.has(hero_id):
		hero_skill_nodes[hero_id] = {}
	hero_skill_nodes[hero_id][node_id] = int(node.rank)
	EventBus.hero_node_purchased.emit(hero_id, node_id)
	EventBus.hero_skill_points_changed.emit(hero_id, get_skill_points(hero_id))
	_persist()
	return true


func add_hero_xp(hero_id: String, amount: int) -> int:
	# Returns the new level (possibly unchanged). Caller reads hero_progress
	# afterward for the new xp value. Handles multi-level catch-up if amount
	# is huge.
	if hero_id == "" or amount <= 0:
		return get_hero_level(hero_id)
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null:
		return 1
	_ensure_hero_progress_entry(hero_id)
	var entry: Dictionary = hero_progress[hero_id]
	var lvl: int = int(entry.get("level", 1))
	var xp: int = int(entry.get("xp", 0))
	var scaled: int = int(ceil(float(amount) * get_upgrade_multiplier(MOD_HERO_XP)))
	xp += scaled
	# Tally per-run XP for the GameOverScreen recap (actual XP banked, post
	# MOD_HERO_XP — what the player's hero progress dict received).
	if has_node("/root/RunState"):
		RunState.record_round_xp(scaled)
	# Emit the scaled amount so the in-level floating "+N XP" text matches
	# the GameOverScreen recap totals. Previously emitting raw `amount` made
	# a MOD_HERO_XP>1 player see e.g. "+10 XP" pop while the recap showed
	# "+12 XP banked" — same kill, two numbers, confusing.
	EventBus.hero_xp_gained.emit(scaled)
	while lvl < hero_data.max_level:
		var idx: int = lvl - 1
		if idx < 0 or idx >= hero_data.xp_per_level.size():
			break
		var needed: int = hero_data.xp_per_level[idx]
		if needed <= 0 or xp < needed:
			break
		xp -= needed
		lvl += 1
		EventBus.hero_leveled_up.emit(lvl)
		# Phase 1/2 — per-level hero points from the hero's level curve
		# (default ⇒ +1, historical). Granted via the silent variant so we
		# don't flush a partial save while entry["level"] / ["xp"] are still
		# mid-loop. The single _persist() after the loop commits consistently.
		_grant_skill_points_silent(hero_id, _points_for_level(hero_id, lvl))
		# Phase 3P — auto-purchase SLOT_UNLOCK nodes whose threshold is now met.
		# Slot caps already gate by hero level in LoadoutState; this just keeps
		# the skill-tree UI visibly in sync (the player sees "★ Slot Unlocked"
		# rows transition from locked to purchased as they hit thresholds).
		_auto_purchase_slot_unlocks_at_level(hero_id, lvl)
		# Phase 3R-followup — bump the catch-up cursor inline so a save loaded
		# fresh after this run won't re-grant points via sync_hero_progression.
		entry["last_synced_level"] = lvl
	if lvl >= hero_data.max_level:
		xp = 0
	entry["level"] = lvl
	entry["xp"] = xp
	# Persist after the level-up loop so multi-level catch-ups save once,
	# not N times. add_hero_skill_points (called inside the loop) also
	# triggers _persist, but those writes are idempotent — same dict, same
	# file. Fine in practice; if profiling flags it, gate _persist to fire
	# only when level/xp actually changed.
	_persist()
	return lvl
