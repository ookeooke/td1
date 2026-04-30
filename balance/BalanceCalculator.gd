extends RefCounted
class_name BalanceCalculator

# Hardness score for any wave or level. Pure-function utility — call from
# @tool-marked level scripts to validate authored levels against the target
# curve documented in the balance plan, or from runtime/telemetry to record
# expected-vs-actual difficulty.
#
# Score formula per enemy:
#   score = W_EHP * EHP + W_LIVES * lives_worth + W_SPEED * move_speed
#   EHP   = max_health / max(0.05, 1.0 - armor)
#
# Magic resist is intentionally not folded into EHP — most player damage is
# physical; folding both would double-count. Resist-heavy enemies still raise
# total score via their HP and speed.

const W_EHP: float = 2.0
const W_LIVES: float = 50.0
const W_SPEED: float = 0.02  # 2.0 / 100.0 — speed 140 contributes 2.8

# PackedScene → EnemyData lookup cache. Avoids re-instantiating the scene
# on every score call; a 5-wave level resolves the same handful of scenes
# repeatedly. Call clear_cache() when reloading content in editor.
static var _scene_data_cache: Dictionary = {}

static func clear_cache() -> void:
	_scene_data_cache.clear()

static func enemy_score(data: EnemyData) -> float:
	if data == null:
		return 0.0
	var ehp: float = float(data.max_health) / max(0.05, 1.0 - data.armor)
	return W_EHP * ehp + W_LIVES * float(data.lives_worth) + W_SPEED * data.move_speed

static func score_wave(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		total += enemy_score(ed) * float(spawn.count)
	return total

static func score_level(wave_list: WaveList, starting_gold: int = 100) -> float:
	if wave_list == null:
		return 0.0
	var total: float = 0.0
	for w in wave_list.waves:
		total += score_wave(w)
	return total - 0.5 * float(starting_gold)

# Verbose form — returns a dictionary with per-wave breakdown for editor
# logging. Used by Level scripts in @tool mode to print authoring readouts.
static func score_level_breakdown(wave_list: WaveList, starting_gold: int = 100) -> Dictionary:
	var per_wave: Array = []
	var per_wave_gold: Array = []
	var per_wave_density: Array = []
	var total: float = 0.0
	var total_gold: int = 0
	var total_countdown: float = 0.0
	if wave_list != null:
		for w in wave_list.waves:
			var s := score_wave(w)
			per_wave.append(s)
			per_wave_gold.append(wave_gold(w))
			per_wave_density.append(wave_density(w))
			total += s
			total_gold += wave_gold(w)
			total_countdown += w.countdown
	# Natural budget = starting + kills + bounties (let every wave auto-start).
	# Max budget = natural + every countdown called immediately (1s = 1g per KR).
	var natural_budget: int = starting_gold + total_gold
	var max_budget: int = natural_budget + int(ceil(total_countdown))
	return {
		"per_wave": per_wave,
		"per_wave_gold": per_wave_gold,
		"per_wave_density": per_wave_density,
		"wave_total": total,
		"starting_gold": starting_gold,
		"net_score": total - 0.5 * float(starting_gold),
		"gold_natural": natural_budget,
		"gold_max_with_early_calls": max_budget,
		"early_call_swing": max_budget - natural_budget,
		"tier": tier_for_score(total - 0.5 * float(starting_gold)),
	}


# Per-wave gold = Σ(enemy.gold_worth × spawn.count) + wave.bounty.
# Reads EnemyData via the same scene cache as enemy_score().
static func wave_gold(wave: WaveData) -> int:
	if wave == null:
		return 0
	var total: int = wave.bounty
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		total += ed.gold_worth * spawn.count
	return total


# Spawn-window duration of a wave: time from wave_started to last spawn fired.
# Each emitter runs serially: start_delay + (count - 1) × interval.
# Wave window = max across emitters. Used to compute density (pressure metric).
static func wave_duration(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var longest: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var t: float = spawn.start_delay + float(maxi(0, spawn.count - 1)) * spawn.interval
		if t > longest:
			longest = t
	return longest


# Density = enemies per second of spawn window. Higher = more pressure on the
# player's defense. 10 enemies in 10s reads very differently from 10 in 60s
# even at equal EHP — this surfaces that gap. BALANCE.md sets baseline bands.
static func wave_density(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total_count: int = 0
	for spawn in wave.spawns:
		if spawn != null:
			total_count += maxi(0, spawn.count)
	var dur: float = wave_duration(wave)
	if dur <= 0.5:
		return float(total_count) * 2.0  # instant-burst: cap at 2× per-half-sec
	return float(total_count) / dur


# Text label on top of a raw hardness score. Bands match BALANCE.md target
# curve. Used for WorldMap card display ("Hardness 6530 (Easy)").
static func tier_for_score(score: float) -> String:
	if score < 4000.0:
		return "Tutorial"
	if score < 7000.0:
		return "Easy"
	if score < 11000.0:
		return "Medium"
	if score < 16000.0:
		return "Hard"
	return "Brutal"

# Total physical EHP the player must remove to clear a wave with zero leak.
# Σ (max_health / max(0.05, 1 - armor)) × count. Magic EHP intentionally
# excluded — author's "is this gear-gated for magic towers?" question is
# answered separately by inspecting magic_resist on enemies in the wave.
static func wave_required_damage(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		var ehp: float = float(ed.max_health) / max(0.05, 1.0 - ed.armor)
		total += ehp * float(spawn.count)
	return total


# DPS floor needed to clear the wave's spawn window with zero leak.
# Use as a sanity check: compare against achievable DPS given wave-start gold
# and the cheapest tower g/DPS available. Below the floor → gear-gated.
static func wave_required_dps(wave: WaveData) -> float:
	var dur: float = wave_duration(wave)
	if dur < 1.0:
		dur = 1.0
	return wave_required_damage(wave) / dur


# Stinginess metric: gold awarded per damage point required.
# Lower = stingier (have to invest gold for little payback).
# Higher = generous (kills fund the next wave's buys).
# Healthy band ~0.10–0.25; below 0.08 = brutal, above 0.30 = trivial.
static func wave_gold_per_damage(wave: WaveData) -> float:
	var req: float = wave_required_damage(wave)
	if req <= 0.0:
		return 0.0
	return float(wave_gold(wave)) / req


# ============================================================================
# Authored-economy distribution — derive per-wave gold + time from the
# share arrays on LevelNodeData. The shares sum to 1.0; per-wave value =
# total × share. Empty/wrong-size shares fall back to uniform distribution
# so authoring partial data still produces valid output.
# ============================================================================

# Per-wave gold targets in absolute integers, summing to gold_budget_total.
static func level_gold_distribution(level_data: LevelNodeData, wave_count: int) -> Array[int]:
	var out: Array[int] = []
	if level_data == null or wave_count <= 0:
		return out
	var shares: Array[float] = _normalized_shares(level_data.wave_gold_shares, wave_count)
	for i in range(wave_count):
		out.append(int(round(float(level_data.gold_budget_total) * shares[i])))
	return out


# Per-wave time slices in seconds, summing to target_duration_sec.
# Convention: countdown ≈ 35% of slice, spawn_window ≈ 65%. Author can split
# differently in the wave .tres — these are *targets* the author shoots for.
static func level_time_distribution(level_data: LevelNodeData, wave_count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if level_data == null or wave_count <= 0:
		return out
	var shares: Array[float] = _normalized_shares(level_data.wave_time_shares, wave_count)
	for i in range(wave_count):
		var total: float = level_data.target_duration_sec * shares[i]
		out.append({
			"total": total,
			"countdown": total * 0.35,
			"spawn_window": total * 0.65,
		})
	return out


static func _normalized_shares(shares: Array[float], wave_count: int) -> Array[float]:
	var out: Array[float] = []
	# Empty or wrong size → uniform.
	if shares.size() != wave_count:
		var uniform: float = 1.0 / float(wave_count)
		for i in range(wave_count):
			out.append(uniform)
		return out
	# Normalize to sum 1.0 — tolerates author drift like [0.10, 0.11, 0.16, 0.23, 0.41].
	var s: float = 0.0
	for v in shares:
		s += v
	if s <= 0.0:
		return _normalized_shares([], wave_count)
	for v in shares:
		out.append(v / s)
	return out


# DPS the player can afford to buy with `gold` gold, using the cheapest
# available tower's damage-per-gold-per-second. Default 0.096 = Archer L1
# (4.8 DPS / 50g). Pass a different value if the player's loadout doesn't
# include Archer-equivalent (e.g. early-level loadout restrictions).
static func affordable_dps(gold: int, dps_per_gold: float = 0.096) -> float:
	if gold <= 0 or dps_per_gold <= 0.0:
		return 0.0
	return float(gold) * dps_per_gold


# Gear pressure for one wave: required_dps / affordable_dps.
#   <0.5  trivial — too much gold, towers idle
#   0.5–0.8 comfortable — has buy options, mistakes survivable
#   0.8–1.0 tight — must commit to right damage type, no slack
#   >1.0  gear-gated — Naked Baseline at risk
# Pass cumulative gold available at the start of THIS wave (start_gold +
# Σ wave_gold[0..i-1]).
static func wave_pressure(wave: WaveData, cumul_gold: int,
		dps_per_gold: float = 0.096) -> float:
	var afford: float = affordable_dps(cumul_gold, dps_per_gold)
	if afford <= 0.0:
		return 0.0
	return wave_required_dps(wave) / afford


# Drift-checked planning report. Per-wave actual vs authored gold + pressure
# targets. Warnings populated when actual deviates >15% from target. Soft
# prints — caller never escalates to push_warning / push_error.
static func level_pressure_report(wave_list: WaveList, level_data: LevelNodeData,
		starting_gold: int, dps_per_gold: float = 0.096) -> Dictionary:
	var report: Dictionary = { "per_wave": [], "warnings": [] }
	if wave_list == null or level_data == null:
		return report
	var wave_count: int = wave_list.waves.size()
	var gold_targets: Array[int] = level_gold_distribution(level_data, wave_count)
	var pressure_targets: Array[float] = _normalized_pressure_targets(
		level_data.wave_pressure_targets, wave_count)
	var cumul: int = starting_gold
	var total_actual_gold: int = 0
	for i in range(wave_count):
		var w: WaveData = wave_list.waves[i]
		var actual_gold: int = wave_gold(w)
		var actual_pressure: float = wave_pressure(w, cumul, dps_per_gold)
		var pressure_target: float = pressure_targets[i]
		var gold_target: int = gold_targets[i]
		var entry: Dictionary = {
			"wave": i + 1,
			"actual_gold": actual_gold,
			"target_gold": gold_target,
			"gold_drift_pct": _drift_pct(float(actual_gold), float(gold_target)),
			"actual_pressure": actual_pressure,
			"target_pressure": pressure_target,
			"pressure_drift_pct": _drift_pct(actual_pressure, pressure_target),
			"cumul_gold_at_start": cumul,
			"affordable_dps": affordable_dps(cumul, dps_per_gold),
			"required_dps": wave_required_dps(w),
		}
		report.per_wave.append(entry)
		# Flag drift >15% — gold OR pressure off target.
		if absf(entry.gold_drift_pct) > 15.0:
			report.warnings.append("W%d gold actual=%dg vs target=%dg (%+.0f%%)" %
				[i + 1, actual_gold, gold_target, entry.gold_drift_pct])
		if pressure_target > 0.0 and absf(entry.pressure_drift_pct) > 15.0:
			report.warnings.append("W%d pressure actual=%.2f vs target=%.2f (%+.0f%%)" %
				[i + 1, actual_pressure, pressure_target, entry.pressure_drift_pct])
		cumul += actual_gold
		total_actual_gold += actual_gold
	# Level-wide gold drift: actual sum vs gold_budget_total.
	report["total_actual_gold"] = total_actual_gold
	report["total_target_gold"] = level_data.gold_budget_total
	report["total_drift_pct"] = _drift_pct(float(total_actual_gold), float(level_data.gold_budget_total))
	if absf(report.total_drift_pct) > 15.0:
		report.warnings.append("total gold actual=%dg vs target=%dg (%+.0f%%)" %
			[total_actual_gold, level_data.gold_budget_total, report.total_drift_pct])
	return report


static func _normalized_pressure_targets(targets: Array[float], wave_count: int) -> Array[float]:
	# Pressure targets DON'T sum to 1.0 — they're absolute per-wave values.
	# Empty / wrong size → 0.0 sentinel (skips drift check for that wave).
	var out: Array[float] = []
	if targets.size() != wave_count:
		for i in range(wave_count):
			out.append(0.0)
		return out
	for v in targets:
		out.append(v)
	return out


# ============================================================================
# Tower damage-per-gold — load-bearing for setting per-wave gold budgets.
#
# A tower's value isn't its DPS or its cost in isolation — it's how much
# damage 1 gold can buy over a wave window. That ratio sets the floor for
# how much gold a wave should award: too little and the wave is gear-gated,
# too much and the player wins on idle gold (last run: 863g unspent of
# 1140g earned = 26% spend efficiency, 3-star with 0 leaks).
#
# Formula:
#   damage_per_gold = (DPS at tier × wave_window_sec) / cumulative_cost_to_tier
#
# Use:
#   1. Compute dmg/g for each unlocked tower at L1, L2, L3 main, L3 branches.
#   2. The CHEAPEST dmg/g across all available L1 towers sets the player's
#      best-case efficiency early in a level.
#   3. Wave required gold = wave_required_damage / cheapest_dmg_per_gold.
#      Wave gold should be ~1.5–2.0× this (headroom for sub-optimal play).
# ============================================================================

# DPS at a given tier of a tower (0=L1, 1=L2, 2=L3 main, 3+ = branches).
# Reads damage × attack_speed from TowerData (L1) or TowerUpgradeData (L2+).
# Returns 0.0 for non-attacking tiers (e.g. base barracks data with damage=0).
static func tower_dps_at_tier(tower_data: TowerData, tier: int) -> float:
	if tower_data == null:
		return 0.0
	if tier == 0:
		return tower_data.damage * tower_data.attack_speed
	# L2 lives at level_upgrades[0]; L3 main at level_upgrades[1]; branches
	# at level_3_branches[idx-2] when set. Mirrors TowerRadialMenu logic.
	if tier == 1 and tower_data.level_upgrades.size() >= 1:
		var l2: TowerUpgradeData = tower_data.level_upgrades[0]
		return l2.damage * l2.attack_speed
	if tier == 2:
		# L3 main if no branches authored, else assume branches handled by tier>=2
		if tower_data.level_3_branches.is_empty() and tower_data.level_upgrades.size() >= 2:
			var l3: TowerUpgradeData = tower_data.level_upgrades[1]
			return l3.damage * l3.attack_speed
		if not tower_data.level_3_branches.is_empty():
			# tier=2 maps to first branch; explicit branch lookup is via tier 3+
			var b: TowerUpgradeData = tower_data.level_3_branches[0]
			return b.damage * b.attack_speed
	if tier >= 3 and not tower_data.level_3_branches.is_empty():
		var idx: int = tier - 2
		if idx < tower_data.level_3_branches.size():
			var br: TowerUpgradeData = tower_data.level_3_branches[idx]
			return br.damage * br.attack_speed
	return 0.0


# Cumulative gold spent to reach a tier from a fresh build slot.
static func tower_cumul_cost(tower_data: TowerData, tier: int) -> int:
	if tower_data == null:
		return 0
	var cost: int = tower_data.cost
	if tier >= 1 and tower_data.level_upgrades.size() >= 1:
		cost += tower_data.level_upgrades[0].cost
	if tier == 2 and tower_data.level_3_branches.is_empty() and tower_data.level_upgrades.size() >= 2:
		cost += tower_data.level_upgrades[1].cost
	if tier >= 2 and not tower_data.level_3_branches.is_empty():
		var idx: int = maxi(0, tier - 2)
		if idx < tower_data.level_3_branches.size():
			cost += tower_data.level_3_branches[idx].cost
	return cost


# Damage per gold for a tower tier over a given wave window. Higher = better.
# Compare against per-wave required_damage / cheapest_dmg_per_gold to see how
# much gold a wave actually demands.
static func tower_damage_per_gold(tower_data: TowerData, tier: int, window_sec: float) -> float:
	if tower_data == null or window_sec <= 0.0:
		return 0.0
	var dps: float = tower_dps_at_tier(tower_data, tier)
	var cost: int = tower_cumul_cost(tower_data, tier)
	if cost <= 0 or dps <= 0.0:
		return 0.0
	return dps * window_sec / float(cost)


# Best dmg-per-gold across an array of available towers at a given tier.
# Set tier=0 to compare L1 placements (the relevant case for early waves).
# Pass non-attacking towers (Barracks) — they're skipped (dps=0 → 0.0).
static func best_damage_per_gold(towers: Array, tier: int, window_sec: float) -> float:
	var best: float = 0.0
	for t in towers:
		if t is TowerData:
			var v: float = tower_damage_per_gold(t, tier, window_sec)
			if v > best:
				best = v
	return best


# Required gold to clear a wave given a damage-per-gold efficiency.
# Add headroom (1.5× rule of thumb) when setting the wave's authored budget.
static func wave_required_gold(wave: WaveData, dmg_per_gold: float) -> int:
	if wave == null or dmg_per_gold <= 0.0:
		return 0
	return int(ceil(wave_required_damage(wave) / dmg_per_gold))


# ============================================================================
# Spawn timeline + dead-air detector. KR rule of thumb: never let player
# "what do I do now" exceed ~5 seconds. Long gaps between spawns make waves
# feel hollow even when total enemy count is right. Surface gaps in editor
# so authors can re-stagger emitters before shipping.
# ============================================================================

const DEAD_AIR_THRESHOLD_SEC: float = 5.0

# Merged sorted spawn timestamps + gap analysis for one wave. Ignores
# enemy walk-out time (only when spawns *fire*, not when enemies leak/die).
static func wave_spawn_timeline(wave: WaveData) -> Dictionary:
	var events: Array[float] = []
	if wave == null:
		return { "events": events, "gaps": [], "max_gap": 0.0, "dead_air": 0.0 }
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		for i in range(spawn.count):
			events.append(spawn.start_delay + float(i) * spawn.interval)
	events.sort()
	var gaps: Array[float] = []
	var max_gap: float = 0.0
	var dead_air: float = 0.0
	for i in range(1, events.size()):
		var g: float = events[i] - events[i - 1]
		gaps.append(g)
		if g > max_gap:
			max_gap = g
		if g > DEAD_AIR_THRESHOLD_SEC:
			dead_air += g - DEAD_AIR_THRESHOLD_SEC
	return {
		"events": events,
		"gaps": gaps,
		"max_gap": max_gap,
		"dead_air": dead_air,
	}


static func _drift_pct(actual: float, target: float) -> float:
	if target <= 0.0:
		return 0.0
	return (actual - target) / target * 100.0


static func _data_from_scene(scene: PackedScene) -> EnemyData:
	if scene == null:
		return null
	if _scene_data_cache.has(scene):
		return _scene_data_cache[scene]
	var inst: Node = scene.instantiate()
	var ed: EnemyData = null
	if "data" in inst:
		ed = inst.data
	inst.free()
	_scene_data_cache[scene] = ed
	return ed
