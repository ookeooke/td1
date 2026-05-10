class_name WaveDamageSimulator
extends RefCounted

# Realistic wave damage simulator — Phase 2 of the coverage-weighted
# balance plan. Builds tower tier profiles, computes per-(spot, tier, wave)
# realistic damage, and runs a greedy gold-spend simulator to answer:
# "how much damage can the player realistically buy with G gold on this map?"
#
# All static. Owns no state besides a tier-profile cache.
#
# Damage model:
#   raw = tower.dps * seconds_in_range * count
#   raw *= damage_type_multiplier(tower, enemy)   # armor/magic_resist/true
#   raw *= 0.0 if (enemy.is_flying and !targets_flying) else 1.0
#   raw *= aoe_factor(tower, density)
#
# Where seconds_in_range = covered_length_px / enemy.move_speed.
#
# AoE factor v1 (per GPT plan, deliberately conservative):
#   single-target  → 1.0
#   AoE            → clamp(1.0 + density * 0.5, 1.0, 2.5)
#   density        → min(spawn_count_on_path, 4) / 4
# TODO: replace density approximation with a real overlap sample once the
# rest of the pipeline has earned trust.

const DAMAGE_TYPE_PHYSICAL: int = 0
const DAMAGE_TYPE_MAGIC: int = 1
const DAMAGE_TYPE_TRUE: int = 2

const AOE_FACTOR_MAX: float = 2.5

# Cached tower-tier profiles: ContentRegistry signature → Array[Dictionary]
static var _profiles_cache: Array = []
static var _profiles_cache_signature: String = ""


# ── Tower tier profiles ──────────────────────────────────────────────────

# Returns a flat Array of profile Dictionaries. One row per (tower × tier).
# Tiers: l1, l2, then either l3_main (no branches) OR branch_0/branch_1.
# Profile keys:
#   tower_id, tier_key, cost (cumulative), step_cost,
#   damage, attack_speed, attack_range, dps,
#   damage_type, targets_flying, aoe_radius, splash_pct,
#   on_hit_slow_factor, on_hit_slow_duration, on_hit_stun_duration,
#   is_barracks
static func build_tower_profiles() -> Array:
	var sig: String = _content_signature()
	if sig == _profiles_cache_signature and not _profiles_cache.is_empty():
		return _profiles_cache

	var out: Array = []
	for tower in ContentRegistry.towers:
		if tower == null:
			continue
		var td: Resource = tower
		# L1 is the base TowerData itself.
		out.append(_make_profile(td, "l1", td, td.cost, td.cost))

		var ups: Array = td.level_upgrades if "level_upgrades" in td else []
		var l2_up: Resource = ups[0] if ups.size() >= 1 else null
		var l2_step: int = int(l2_up.cost) if l2_up != null else 0
		var l2_cum: int = td.cost + l2_step
		if l2_up != null:
			out.append(_make_profile(td, "l2", l2_up, l2_cum, l2_step))

		var branches: Array = td.level_3_branches if "level_3_branches" in td else []
		if branches.size() > 0:
			for i in range(branches.size()):
				var br: Resource = branches[i]
				if br == null:
					continue
				var step: int = int(br.cost)
				out.append(_make_profile(td, "branch_%d" % i, br, l2_cum + step, step))
		elif ups.size() >= 2 and ups[1] != null:
			var l3: Resource = ups[1]
			var step3: int = int(l3.cost)
			out.append(_make_profile(td, "l3_main", l3, l2_cum + step3, step3))

	_profiles_cache = out
	_profiles_cache_signature = sig
	return out


# Build one profile from base + (possibly null) upgrade overrides. A 0/empty
# field on the override falls back to the base TowerData value, mirroring
# TowerUpgradeData.get_preview_stats inheritance.
static func _make_profile(base: Resource, tier_key: String, source: Resource, cum_cost: int, step_cost: int) -> Dictionary:
	var dmg: float = float(source.damage) if source != null and source.damage > 0.0 else float(base.damage)
	var rng: float = float(source.attack_range) if source != null and source.attack_range > 0.0 else float(base.attack_range)
	var spd: float = float(source.attack_speed) if source != null and source.attack_speed > 0.0 else float(base.attack_speed)
	var aoe: float = float(source.aoe_radius) if source != null and "aoe_radius" in source and source.aoe_radius > 0.0 else float(base.aoe_radius)
	var splash: float = float(source.splash_damage_pct) if source != null and "splash_damage_pct" in source and source.splash_damage_pct > 0.0 else float(base.splash_damage_pct)
	var slow_f: float = float(source.on_hit_slow_factor) if source != null and "on_hit_slow_factor" in source and source.on_hit_slow_factor > 0.0 else float(base.on_hit_slow_factor)
	var slow_d: float = float(source.on_hit_slow_duration) if source != null and "on_hit_slow_duration" in source and source.on_hit_slow_duration > 0.0 else float(base.on_hit_slow_duration)
	var stun_d: float = float(source.on_hit_stun_duration) if source != null and "on_hit_stun_duration" in source and source.on_hit_stun_duration > 0.0 else float(base.on_hit_stun_duration)
	var is_barracks: bool = base.is_barracks() if base.has_method("is_barracks") else false
	return {
		"tower_id": String(base.tower_id),
		"tier_key": tier_key,
		"cost": cum_cost,
		"step_cost": step_cost,
		"damage": dmg,
		"attack_speed": spd,
		"attack_range": rng,
		"dps": dmg * spd,
		"damage_type": int(base.damage_type),
		"targets_flying": bool(base.targets_flying),
		"aoe_radius": aoe,
		"splash_pct": splash,
		"on_hit_slow_factor": slow_f,
		"on_hit_slow_duration": slow_d,
		"on_hit_stun_duration": stun_d,
		"is_barracks": is_barracks,
	}


# Content registry signature so the profile cache invalidates if the
# tower list or .tres files change in editor.
static func _content_signature() -> String:
	var n: int = ContentRegistry.towers.size() if ContentRegistry.towers else 0
	return "%d" % n


# ── Realistic damage per candidate ────────────────────────────────────────

# Damage one (spot, tower_profile) pair would deal across one wave, given
# the level's coverage matrix. Returns 0.0 if the tower is a barracks
# (those don't directly map to damage in this model) or has zero coverage.
static func candidate_wave_damage(spot_id: String, profile: Dictionary, wave: WaveData, coverage_matrix: Dictionary) -> float:
	if profile.get("is_barracks", false):
		return 0.0
	if wave == null or wave.spawns.is_empty():
		return 0.0
	var spots: Dictionary = coverage_matrix.get("spots", {})
	if not spots.has(spot_id):
		return 0.0
	var spot_entry: Dictionary = spots[spot_id]
	var key: String = "%s:%s" % [profile["tower_id"], profile["tier_key"]]
	var per_path: Dictionary = spot_entry.get(key, {})
	if per_path.is_empty():
		return 0.0

	var total_path_count_for_density: Dictionary = {}
	for s in wave.spawns:
		if s == null or s.path_id == "":
			continue
		total_path_count_for_density[s.path_id] = int(total_path_count_for_density.get(s.path_id, 0)) + int(s.count)

	var dps: float = float(profile["dps"])
	var aoe_radius: float = float(profile["aoe_radius"])
	var damage_type: int = int(profile["damage_type"])
	var targets_flying: bool = bool(profile["targets_flying"])

	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0 or spawn.enemy_scene == null:
			continue
		var enemy_data: Resource = CoverageAnalyzer.enemy_data_for(spawn.enemy_scene)
		if enemy_data == null:
			continue
		var path_id: String = String(spawn.path_id)
		if not per_path.has(path_id):
			continue
		var cov: Dictionary = per_path[path_id]
		var covered_px: float = float(cov.get("covered_length_px", 0.0))
		if covered_px <= 0.0:
			continue
		var move_speed: float = float(enemy_data.move_speed)
		if move_speed <= 0.0:
			continue
		# Flying enemy + ground-only tower → 0 contribution.
		if bool(enemy_data.is_flying) and not targets_flying:
			continue
		var seconds_in_range: float = covered_px / move_speed
		var per_enemy: float = dps * seconds_in_range * _damage_type_multiplier(damage_type, enemy_data)
		# AoE factor — see header for v1 formula caveat. Apply the multiplier
		# before the EHP cap so AoE can increase throughput across a pack, but
		# never report more damage than this spawn group's enemies can absorb.
		var density_norm: float = clamp(float(total_path_count_for_density.get(path_id, 0)) / 4.0, 0.0, 1.0)
		var aoe_factor: float = 1.0
		if aoe_radius > 0.0:
			aoe_factor = clamp(1.0 + density_norm * 0.5, 1.0, AOE_FACTOR_MAX)
		var ehp: float = _enemy_effective_hp(enemy_data, damage_type)
		per_enemy = min(per_enemy * aoe_factor, ehp)
		total += per_enemy * float(spawn.count)
	return total


# Total realistic damage achievable for one wave with `gold_budget`,
# computed via greedy spend across all spots in the coverage matrix.
static func realistic_wave_supply(wave: WaveData, gold_budget: int, coverage_matrix: Dictionary, profiles: Array) -> Dictionary:
	var result: Dictionary = greedy_spend([wave], gold_budget, coverage_matrix, profiles)
	return result


# Aggregate damage for one wave that arises from a placement plan
# (used by the greedy ranker to score options and by the report).
static func wave_damage_for_placements(wave: WaveData, placements: Array, coverage_matrix: Dictionary) -> float:
	var total: float = 0.0
	for p in placements:
		total += candidate_wave_damage(String(p["spot_id"]), p["profile"] as Dictionary, wave, coverage_matrix)
	return total


# ── Greedy spend ─────────────────────────────────────────────────────────

# Greedy gold-spend simulator. Plays a build-and-upgrade game on the
# coverage matrix, picking the highest damage-per-gold candidate at each
# step until no affordable option remains. Considers upgrades on already-
# placed spots (paying step_cost from current tier to next tier).
#
# Returns:
#   {
#     "total_damage":  float,
#     "gold_spent":    int,
#     "gold_left":     int,
#     "placements":    [ {spot_id, tower_id, tier_key, profile, damage, cost, efficiency} ]
#   }
#
# Scoring uses summed damage across all input waves.
static func greedy_spend(waves: Array, gold_budget: int, coverage_matrix: Dictionary, profiles: Array) -> Dictionary:
	var spots: Dictionary = coverage_matrix.get("spots", {})
	# spot_id -> {tower_id, tier_key, profile, damage}
	var current: Dictionary = {}
	var gold: int = gold_budget
	var step_log: Array = []
	var safety: int = 1024

	# Pre-sum candidate damage cache: "spot|tower|tier" → summed damage across waves.
	var dmg_cache: Dictionary = {}
	var dmg_for = func(spot_id: String, profile: Dictionary) -> float:
		var k: String = "%s|%s|%s" % [spot_id, profile["tower_id"], profile["tier_key"]]
		if dmg_cache.has(k):
			return dmg_cache[k]
		var sum_d: float = 0.0
		for w in waves:
			sum_d += candidate_wave_damage(spot_id, profile, w, coverage_matrix)
		dmg_cache[k] = sum_d
		return sum_d

	while safety > 0:
		safety -= 1
		var best_score: float = 0.0
		var best_action: Dictionary = {}
		for spot_id in spots:
			var occupied: Dictionary = current.get(spot_id, {})
			if occupied.is_empty():
				# Build candidates: every L1 profile fits on an empty spot.
				for p in profiles:
					if p.get("is_barracks", false):
						continue
					if p["tier_key"] != "l1":
						continue
					var step_cost: int = int(p["step_cost"])
					if step_cost > gold or step_cost <= 0:
						continue
					var dmg: float = dmg_for.call(spot_id, p)
					if dmg <= 0.0:
						continue
					var eff: float = dmg / float(step_cost)
					if eff > best_score:
						best_score = eff
						best_action = {
							"kind": "build",
							"spot_id": spot_id,
							"profile": p,
							"step_cost": step_cost,
							"damage": dmg,
						}
			else:
				# Upgrade candidates: any profile on the same tower_id with
				# higher cumulative cost than the current tier and step_cost ≤ gold.
				var cur_profile: Dictionary = occupied["profile"]
				var cur_cum: int = int(cur_profile["cost"])
				for p in profiles:
					if p.get("is_barracks", false):
						continue
					if p["tower_id"] != cur_profile["tower_id"]:
						continue
					if not _can_upgrade_to(cur_profile, p):
						continue
					if int(p["cost"]) <= cur_cum:
						continue
					var step_cost: int = int(p["cost"]) - cur_cum
					if step_cost > gold or step_cost <= 0:
						continue
					var new_dmg: float = dmg_for.call(spot_id, p)
					var cur_dmg: float = float(occupied.get("damage", 0.0))
					var delta: float = new_dmg - cur_dmg
					if delta <= 0.0:
						continue
					var eff: float = delta / float(step_cost)
					if eff > best_score:
						best_score = eff
						best_action = {
							"kind": "upgrade",
							"spot_id": spot_id,
							"profile": p,
							"step_cost": step_cost,
							"damage": new_dmg,
							"delta": delta,
						}
		if best_action.is_empty():
			break
		# Apply the best action.
		var sid: String = best_action["spot_id"]
		var prof: Dictionary = best_action["profile"]
		gold -= int(best_action["step_cost"])
		current[sid] = {
			"tower_id": prof["tower_id"],
			"tier_key": prof["tier_key"],
			"profile": prof,
			"damage": float(best_action["damage"]),
		}
		step_log.append({
			"spot_id": sid,
			"tower_id": prof["tower_id"],
			"tier_key": prof["tier_key"],
			"kind": best_action["kind"],
			"cost": int(best_action["step_cost"]),
			"damage": float(best_action["damage"]),
			"efficiency": best_score,
		})

	var total_damage: float = 0.0
	for spot_id in current:
		total_damage += float(current[spot_id]["damage"])

	# Final placements list: one entry per occupied spot at its final tier.
	var placements: Array = []
	for spot_id in current:
		var occ: Dictionary = current[spot_id]
		placements.append({
			"spot_id": spot_id,
			"tower_id": occ["tower_id"],
			"tier_key": occ["tier_key"],
			"profile": occ["profile"],
			"damage": occ["damage"],
		})

	return {
		"total_damage": total_damage,
		"gold_spent": gold_budget - gold,
		"gold_left": gold,
		"placements": placements,
		"steps": step_log,
	}


# Marginal-gold-usefulness curve. For each gold value in `gold_values`,
# run greedy spend and return (gold, total_damage). Caller can plot
# the line and the per-100g marginal as bars.
static func marginal_gold_curve(waves: Array, gold_values: Array, coverage_matrix: Dictionary, profiles: Array) -> Array:
	var out: Array = []
	for g in gold_values:
		var r: Dictionary = greedy_spend(waves, int(g), coverage_matrix, profiles)
		out.append({"gold": int(g), "damage": float(r["total_damage"])})
	return out


# Saturation gold — the smallest gold value where the marginal damage per
# step falls below `plateau_threshold` × peak_marginal. "When does extra
# gold stop buying damage?" Returns the curve's last gold value if the
# threshold is never crossed (no plateau within the search range).
#
# Used by BalanceSliders' LevelOverviewChart to overlay a horizontal marker
# on the cumulative-gold curve, showing the wave at which the player's
# wallet exceeds saturation.
static func saturation_gold(waves: Array, coverage_matrix: Dictionary, profiles: Array,
		plateau_threshold: float = 0.05, max_gold: int = 3000, step: int = 100) -> int:
	if waves.is_empty() or coverage_matrix.is_empty() or profiles.is_empty():
		return 0
	var gold_values: Array = []
	var g: int = 0
	while g <= max_gold:
		gold_values.append(g)
		g += step
	var curve: Array = marginal_gold_curve(waves, gold_values, coverage_matrix, profiles)
	if curve.size() < 2:
		return 0
	# Find the peak per-step marginal first.
	var peak: float = 0.0
	for i in range(1, curve.size()):
		var delta: float = float(curve[i]["damage"]) - float(curve[i - 1]["damage"])
		if delta > peak:
			peak = delta
	if peak <= 0.0:
		return int(curve[-1]["gold"])
	var threshold: float = peak * plateau_threshold
	# Walk forward; first step whose marginal drops below threshold AFTER
	# we've already seen a non-trivial gain marks the plateau onset.
	var seen_gain: bool = false
	for i in range(1, curve.size()):
		var delta: float = float(curve[i]["damage"]) - float(curve[i - 1]["damage"])
		if delta >= peak * 0.5:
			seen_gain = true
		if seen_gain and delta < threshold:
			return int(curve[i]["gold"])
	return int(curve[-1]["gold"])


# ── Per-wave demand ──────────────────────────────────────────────────────

static func _can_upgrade_to(current: Dictionary, candidate: Dictionary) -> bool:
	var cur_tier: String = String(current.get("tier_key", ""))
	var next_tier: String = String(candidate.get("tier_key", ""))
	if cur_tier == "l1":
		return next_tier == "l2"
	if cur_tier == "l2":
		return next_tier == "l3_main" or next_tier.begins_with("branch_")
	return false


# Wraps BalanceCalculator.wave_required_damage so callers can stay inside
# this module. Returns 0 on any failure to load BalanceCalculator.
static func wave_demand_damage(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	# BalanceCalculator is a class_name — call statically.
	return BalanceCalculator.wave_required_damage(wave)


static func level_demand_damage(waves: Array) -> float:
	var total: float = 0.0
	for w in waves:
		total += wave_demand_damage(w)
	return total


# ── Coverage-weighted per-wave pressure (canonical for Tuning Console) ──

# Returns one Dictionary per wave with the CANONICAL pressure model. Used by
# BalanceSliders' overview + per-wave headers. See plan
# `BalanceSliders → Tuning Console`.
#
# Per row:
#   {
#     "actual": float,         # demand_i / max(1, supply_i)
#     "target": float,         # 0.0 = unauthored
#     "drift":  float,         # signed (actual - target) / target; 0.0 if no target
#     "supply": float,         # greedy spend total damage at gold_at_wave_start
#     "demand": float,         # wave's physical EHP sum
#     "gold_at_start": int,    # cumulative authored gold at start of this wave
#     "reason":  String,       # short text reason when verdict is bad; "" otherwise
#   }
#
# Cumulative gold at wave i = starting_gold + Σ over j<i of (wave_j.bounty +
# Σ enemy.gold_worth × count). Authored numbers only — does NOT apply per-emitter
# count overrides; matches CoverageReport's authored-gold path.
static func pressure_per_wave(waves: Array, level_data: Resource, scene_path: String, starting_gold: int) -> Array:
	var out: Array = []
	if waves.is_empty() or scene_path == "":
		return out

	var profiles: Array = build_tower_profiles()
	if profiles.is_empty():
		return out
	var coverage_rows: Array = []
	for p in profiles:
		coverage_rows.append({
			"tower_id": p["tower_id"],
			"tier_key": p["tier_key"],
			"range": p["attack_range"],
		})
	var coverage_matrix: Dictionary = CoverageAnalyzer.build_coverage_matrix(scene_path, coverage_rows)
	if coverage_matrix.is_empty():
		return out

	# Authored pressure targets (size-matched to wave count, 0.0 sentinel
	# for unauthored). Mirrors BalanceCalculator._normalized_pressure_targets.
	var n_waves: int = waves.size()
	var targets: Array = []
	if level_data != null and "wave_pressure_targets" in level_data:
		var raw: Array = level_data.wave_pressure_targets
		if raw.size() == n_waves:
			for v in raw:
				targets.append(float(v))
	if targets.is_empty():
		for i in range(n_waves):
			targets.append(0.0)

	# Pre-compute saturation gold for the level (used by reason picker).
	var sat_gold: int = saturation_gold(waves, coverage_matrix, profiles)

	# Walk waves; gold accumulates from authored bounty + per-enemy gold_worth.
	var cumul_gold: int = max(0, starting_gold)
	for i in range(n_waves):
		var wave: WaveData = waves[i]
		var gold_at_start: int = cumul_gold
		var demand: float = wave_demand_damage(wave)
		var greedy: Dictionary = greedy_spend([wave], gold_at_start, coverage_matrix, profiles)
		var supply: float = float(greedy.get("total_damage", 0.0))
		var actual: float = demand / max(1.0, supply)
		var target: float = float(targets[i])
		var drift: float = 0.0
		if target > 0.0:
			drift = (actual - target) / target
		var reason: String = ""
		if drift > 0.10 or (target <= 0.0 and actual > 1.05):
			reason = _pick_pressure_reason(wave, gold_at_start, sat_gold, coverage_matrix, profiles)
		# Concrete fix suggestion — only when there's an authored target and
		# the wave is meaningfully off (|drift| > 0.10). Skipped when target
		# is unauthored (no number to chase) and when the wave is already
		# on target (nothing to fix).
		var fix: String = ""
		if target > 0.0 and absf(drift) > 0.10:
			fix = suggest_pressure_fix(
				wave, actual, target, demand, supply,
				coverage_matrix, profiles, gold_at_start, waves)
		out.append({
			"actual": actual,
			"target": target,
			"drift": drift,
			"supply": supply,
			"demand": demand,
			"gold_at_start": gold_at_start,
			"reason": reason,
			"fix": fix,
		})

		# Advance cumulative gold for the next wave.
		var wave_gold: int = int(wave.bounty) if wave != null and "bounty" in wave else 0
		if wave != null:
			for spawn in wave.spawns:
				if spawn == null or spawn.count <= 0 or spawn.enemy_scene == null:
					continue
				var ed: Resource = CoverageAnalyzer.enemy_data_for(spawn.enemy_scene)
				if ed == null:
					continue
				var per_g: int = int(ed.gold_worth) if "gold_worth" in ed else 0
				wave_gold += per_g * int(spawn.count)
		cumul_gold += wave_gold
	return out


# Verdict band for a pressure-vs-target drift. Returns {label, color}.
# Matches the bands documented in the Tuning Console plan.
static func drift_verdict(actual: float, target: float) -> Dictionary:
	if target <= 0.0:
		return {"label": "no target", "color": Color(0.65, 0.65, 0.70), "has_target": false}
	var drift: float = (actual - target) / target
	if drift <= -0.25:
		return {"label": "too easy", "color": Color(0.50, 0.75, 0.95), "has_target": true}
	elif drift <= -0.10:
		return {"label": "comfortable", "color": Color(0.55, 0.85, 0.85), "has_target": true}
	elif drift <= 0.10:
		return {"label": "on target", "color": Color(0.55, 0.85, 0.55), "has_target": true}
	elif drift <= 0.25:
		return {"label": "dangerous", "color": Color(0.95, 0.65, 0.30), "has_target": true}
	else:
		return {"label": "likely unfair", "color": Color(0.95, 0.35, 0.35), "has_target": true}


# Suggest 1–3 concrete fixes that bring this wave's pressure to its target.
# Returns a single human-readable string like:
#   "−8 scout count, OR −25% HP, OR +320 gold"
# Empty string if there's no obvious target (target ≤ 0) or no meaningful drift.
#
# Math: target_demand = supply × target_pressure. delta_factor = target/actual
# (< 1 → reduce demand; > 1 → increase). Per-emitter count delta picks the
# largest-EHP emitter; HP delta is the same factor; gold delta is found via
# binary search on greedy_spend within [0..3000g] to bring supply to target.
static func suggest_pressure_fix(wave: WaveData, actual: float, target: float,
		demand: float, _supply: float,
		coverage_matrix: Dictionary, profiles: Array, gold_at_start: int,
		all_waves: Array = []) -> String:
	if wave == null or target <= 0.0 or actual <= 0.0 or demand <= 0.0:
		return ""
	var drift: float = (actual - target) / target
	if absf(drift) < 0.10:
		return ""  # already on target
	var delta_factor: float = target / actual  # < 1 → cut, > 1 → grow

	var parts: Array[String] = []

	# 1) Per-emitter count nudge — pick the largest-EHP emitter and propose
	# scaling its count by delta_factor. Most readable when one emitter
	# dominates the wave's EHP.
	var top_emitter: Dictionary = _largest_emitter_by_ehp(wave)
	if not top_emitter.is_empty():
		var cur_count: int = int(top_emitter["count"])
		var new_count: int = int(round(float(cur_count) * delta_factor))
		new_count = max(0, new_count)
		if new_count != cur_count:
			var arrow: String = "→"
			parts.append("%s count %d %s %d" % [
				String(top_emitter["class"]), cur_count, arrow, new_count
			])

	# 2) Global HP nudge — same factor applied to enemy HP via the
	# global hp_mult slider. Simple, always applicable.
	var hp_pct: int = int(round((delta_factor - 1.0) * 100.0))
	if hp_pct != 0:
		parts.append("HP %+d%%" % hp_pct)

	# 3) Gold nudge — only meaningful when the wave is too hard. Binary-search
	# for the gold value at which greedy supply matches target_demand. Skip
	# when too easy (we'd have to REMOVE gold, an awkward suggestion).
	if drift > 0.0 and not all_waves.is_empty() and not coverage_matrix.is_empty() and not profiles.is_empty():
		var target_supply: float = demand / target
		var gold_needed: int = _gold_for_supply(wave, target_supply, gold_at_start, coverage_matrix, profiles)
		if gold_needed > 0 and gold_needed > gold_at_start:
			parts.append("starting gold +%d" % (gold_needed - gold_at_start))

	if parts.is_empty():
		return ""
	return "Fix → " + ", OR ".join(parts)


# Find the spawn emitter whose count × per-enemy EHP is largest. Returns
# {class, count, idx} or {} when the wave has no spawns.
static func _largest_emitter_by_ehp(wave: WaveData) -> Dictionary:
	if wave == null or wave.spawns.is_empty():
		return {}
	var best: Dictionary = {}
	var best_ehp: float = 0.0
	for i in range(wave.spawns.size()):
		var s = wave.spawns[i]
		if s == null or s.count <= 0 or s.enemy_scene == null:
			continue
		var ed: Resource = CoverageAnalyzer.enemy_data_for(s.enemy_scene)
		if ed == null:
			continue
		var hp: float = float(ed.max_health) if "max_health" in ed else 0.0
		var armor: float = float(ed.armor) if "armor" in ed else 0.0
		var ehp_each: float = hp / max(0.05, 1.0 - armor)
		var total: float = ehp_each * float(s.count)
		if total > best_ehp:
			best_ehp = total
			# Heuristic class label from scene path — same scheme as
			# WaveTimelineChart._enemy_class_for, kept loose.
			var path: String = String(s.enemy_scene.resource_path).to_lower()
			var cls: String = "enemy"
			for k in ["boss", "brute", "armored", "flying", "healer", "scout", "basic"]:
				if path.contains(k):
					cls = k
					break
			best = {"class": cls, "count": int(s.count), "idx": i}
	return best


# Binary search for the smallest gold budget where greedy supply >= target.
# Returns 0 on failure / no convergence within [0..3000].
static func _gold_for_supply(wave: WaveData, target_supply: float, lower_bound: int,
		coverage_matrix: Dictionary, profiles: Array) -> int:
	var lo: int = max(0, lower_bound)
	var hi: int = 3000
	# Quick exit: if even max gold can't hit target, no useful suggestion.
	var max_supply: float = float(greedy_spend([wave], hi, coverage_matrix, profiles).get("total_damage", 0.0))
	if max_supply < target_supply:
		return 0
	for _i in range(12):  # 12 iters → ±1g precision
		if hi - lo <= 25:
			break
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		var s: float = float(greedy_spend([wave], mid, coverage_matrix, profiles).get("total_damage", 0.0))
		if s >= target_supply:
			hi = mid
		else:
			lo = mid
	return hi


# Cheap deterministic reason-picker for the WaveTimelineChart header tag.
# v1 surfaces ONE reason — over-saturation, coverage gap, or armor mismatch —
# in priority order. Empty string means "no obvious cause." Replace with
# real chips when the v2 chip widget lands.
static func _pick_pressure_reason(wave: WaveData, gold_at_start: int, sat_gold: int,
		coverage_matrix: Dictionary, profiles: Array) -> String:
	if wave == null:
		return ""
	# 1. Over-saturation: this wave starts with more gold than the map can absorb.
	if sat_gold > 0 and gold_at_start > sat_gold:
		return "over-sat"
	# 2. Coverage gap: any spawn path has < 30% best-affordable coverage from any spot.
	var spots: Dictionary = coverage_matrix.get("spots", {})
	var paths_used: Dictionary = {}
	for s in wave.spawns:
		if s == null or s.path_id == "":
			continue
		paths_used[String(s.path_id)] = true
	for path_id in paths_used:
		var best_pct: float = 0.0
		for spot_id in spots:
			var spot_entry: Dictionary = spots[spot_id]
			for key in spot_entry.keys():
				if key == "position":
					continue
				var per_path: Dictionary = spot_entry[key]
				if not per_path.has(path_id):
					continue
				var pct: float = float((per_path[path_id] as Dictionary).get("coverage_pct", 0.0))
				if pct > best_pct:
					best_pct = pct
		if best_pct < 0.30:
			return "coverage gap on %s" % path_id
	# 3. Armored-dominant wave with mostly physical profiles → armor mismatch.
	var armored_count: int = 0
	var total_count: int = 0
	for s in wave.spawns:
		if s == null or s.count <= 0 or s.enemy_scene == null:
			continue
		var ed: Resource = CoverageAnalyzer.enemy_data_for(s.enemy_scene)
		if ed == null:
			continue
		total_count += int(s.count)
		if "armor" in ed and float(ed.armor) >= 0.30:
			armored_count += int(s.count)
	if total_count > 0 and float(armored_count) / float(total_count) >= 0.50:
		var phys_profiles: int = 0
		for p in profiles:
			if int(p.get("damage_type", 0)) == DAMAGE_TYPE_PHYSICAL:
				phys_profiles += 1
		if profiles.size() > 0 and float(phys_profiles) / float(profiles.size()) >= 0.5:
			return "armor mismatch"
	return ""


# ── Helpers ──────────────────────────────────────────────────────────────

static func _damage_type_multiplier(damage_type: int, enemy_data: Resource) -> float:
	match damage_type:
		DAMAGE_TYPE_PHYSICAL:
			return clamp(1.0 - float(enemy_data.armor), 0.05, 1.0)
		DAMAGE_TYPE_MAGIC:
			return clamp(1.0 - float(enemy_data.magic_resist), 0.05, 1.0)
		_:
			return 1.0


static func _enemy_effective_hp(enemy_data: Resource, damage_type: int) -> float:
	var hp: float = float(enemy_data.max_health)
	var mult: float = _damage_type_multiplier(damage_type, enemy_data)
	if mult <= 0.0:
		return hp * 1000.0  # immune-ish; massive ceiling
	return hp / mult


# Verdict bands for pressure = demand / supply. Matches GPT's plan.
static func pressure_verdict(pressure: float) -> Dictionary:
	if pressure < 0.50:
		return {"label": "trivial", "color": Color(0.55, 0.85, 0.55)}
	elif pressure < 0.80:
		return {"label": "comfortable", "color": Color(0.50, 0.75, 0.95)}
	elif pressure < 1.05:
		return {"label": "good", "color": Color(0.85, 0.85, 0.85)}
	elif pressure < 1.30:
		return {"label": "dangerous", "color": Color(0.95, 0.65, 0.30)}
	else:
		return {"label": "likely unfair", "color": Color(0.95, 0.35, 0.35)}


static func clear_cache() -> void:
	_profiles_cache.clear()
	_profiles_cache_signature = ""
