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

# Player Power Tier conversion — see balance/BALANCE.md "PPT". Each PPT
# point a level is balanced for is worth this much in raw hardness score.
#
# Recalibration history:
#   2026-05-03  L1 measured at ~14,878 (audit screen, post enemy-stat
#               rebalance commit f226988 on 2026-04-30). Factor bumped
#               to 7,500 → L1 (target_ppt=2) drift ≈ -1% ✓ green.
#   (initial)   3,000.0, calibrated against the stale 2026-04-28 baseline
#               of 6,530 before the enemy HP/armor bump landed.
#
# When enemy stats move materially, re-measure L1 in the audit and update
# this constant. Don't rebalance L1's wave file to chase the constant.
const PPT_TO_HARDNESS_FACTOR: float = 7500.0

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


# Damage-type-specific EHP. Used for the dual-EHP readout — surfaces waves
# that bias hard against magic builds (high magic_resist enemies clustered)
# or physical builds (high armor clustered). Existing enemy_score folds
# armor only and is the canonical hardness number; these are diagnostic.
static func enemy_ehp_physical(data: EnemyData) -> float:
	if data == null:
		return 0.0
	return float(data.max_health) / max(0.05, 1.0 - data.armor)

static func enemy_ehp_magic(data: EnemyData) -> float:
	if data == null:
		return 0.0
	return float(data.max_health) / max(0.05, 1.0 - data.magic_resist)

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


# Total physical/magic damage required to clear a wave assuming zero leak.
# Compare to wave_required_damage (which uses physical) — these isolate the
# bias so a "5000 phys / 1500 mag" wave reads as "Mage build will struggle".
static func wave_ehp_physical(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		total += enemy_ehp_physical(ed) * float(spawn.count)
	return total

static func wave_ehp_magic(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		total += enemy_ehp_magic(ed) * float(spawn.count)
	return total

static func score_level(wave_list: WaveList, starting_gold: int = 100) -> float:
	if wave_list == null:
		return 0.0
	var total: float = 0.0
	for w in wave_list.waves:
		total += score_wave(w)
	return total - 0.5 * float(starting_gold)


# Level-wide required damage — sum of wave_required_damage across the
# whole wave list. Headline number for the "gold per damage" KPI in the
# audit screen; lower than expected = stingy economy, higher = generous.
static func level_required_damage(wave_list: WaveList) -> float:
	if wave_list == null:
		return 0.0
	var total: float = 0.0
	for w in wave_list.waves:
		total += wave_required_damage(w)
	return total


# Drift % of actual hardness against PPT-implied expected hardness.
# Returns positive values when the level is harder than its target PPT
# expects (level over-tuned for the band), negative when easier. Audit
# screen color-codes ±15% green / ±25% yellow / beyond red.
static func score_for_ppt(wave_list: WaveList, target_ppt: int,
		starting_gold: int = 100) -> float:
	if wave_list == null or target_ppt <= 0:
		return 0.0
	var expected: float = float(target_ppt) * PPT_TO_HARDNESS_FACTOR
	var actual: float = score_level(wave_list, starting_gold)
	if expected <= 0.0:
		return 0.0
	return (actual - expected) / expected * 100.0

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


# Authored floor time (seconds) for a wave list. Sum of countdowns + spawn
# windows. Excludes the time enemies spend walking after their last spawn —
# that overlaps with the next wave in practice and is hard to estimate
# without the level's path geometry. The number lower-bounds how long an
# unaccelerated, no-early-call run will take. Used by the 10-minute rule
# (BALANCE.md): authored floor 800-900s ⇒ actual play near 600s after fast
# kills + early calls. Returns 0 on null input.
static func level_floor_time(wave_list: WaveList) -> float:
	if wave_list == null:
		return 0.0
	var total: float = 0.0
	for w in wave_list.waves:
		if w == null:
			continue
		total += float(w.countdown)
		total += wave_duration(w)
	return total


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


# ============================================================================
# Supply vs Demand model — see balance/BALANCE.md "Supply vs Demand".
#
# Two headline numbers:
#   player_supply  — total effective damage the player can produce over the
#                    level's authored duration, segmented by source.
#   level_demand   — total effective EHP the player must remove, plus
#                    archetype + density premiums.
#   safety_ratio   = supply / demand
#
# Drill-downs (sub-ratios) identify a bottleneck — *why* a level is hard:
# anti-air gap, armored EHP, swarm density, boss meat, blocker pressure,
# gold starvation. Each weight is exposed via BalanceModelConfig so
# designers can tune without code edits.
#
# Pure functions, no state. Pass a config; null falls back to defaults.
# ============================================================================


# Resolves a config; returns a defaults instance if null. Internal helper.
static func _cfg(config: BalanceModelConfig) -> BalanceModelConfig:
	if config != null:
		return config
	return BalanceModelConfig.defaults()


# Per-enemy ability EHP add. Closes the audit gap where regen + heal_aura
# were authored but never scored. Each healing tick during the wave's
# kill_window is converted to "EHP the player must do extra damage to remove."
#
# Returns 0 if no scoring abilities are present (the common case).
static func score_enemy_abilities(enemy: EnemyData, kill_window: float,
		config: BalanceModelConfig = null) -> float:
	if enemy == null or kill_window <= 0.0:
		return 0.0
	var c: BalanceModelConfig = _cfg(config)
	if enemy.abilities.is_empty():
		return 0.0
	var add: float = 0.0
	for ab in enemy.abilities:
		if ab == null:
			continue
		# RegenAbility — heals self each interval.
		if ab is RegenAbility:
			var r: RegenAbility = ab
			var interval: float = max(0.5, ab.interval)
			# heal_amount per interval × ticks within kill_window.
			add += r.heal_amount * (kill_window / interval) * c.regen_score_weight
		elif ab is HealAuraAbility:
			var h: HealAuraAbility = ab
			var hi: float = max(0.5, ab.interval)
			# Aura affects ~heal_aura_avg_targets allies per tick.
			add += h.heal_amount * float(c.heal_aura_avg_targets) \
				* (kill_window / hi) * c.heal_aura_score_weight
	return add


# Wave demand vector — how much damage the player must produce, broken
# into archetype categories so bottleneck detection has something to chew on.
# Returns a Dictionary; safe defaults for empty/null input.
static func wave_demand_vector(wave: WaveData, config: BalanceModelConfig = null) -> Dictionary:
	var out: Dictionary = {
		"total_ehp": 0.0,
		"ground_ehp": 0.0,
		"flying_ehp": 0.0,
		"armored_ehp": 0.0,
		"magic_resist_ehp": 0.0,
		"boss_ehp": 0.0,
		"bypass_pressure": 0.0,
		"ability_ehp_add": 0.0,
		"block_cost": 0.0,
		"enemy_count": 0,
		"density": 0.0,
		"kill_window": 1.0,
		"required_dps": 0.0,
	}
	if wave == null:
		return out
	var c: BalanceModelConfig = _cfg(config)
	var spawn_window: float = wave_duration(wave)
	# kill_window: floor at spawn_window; later we expand for path length
	# when level data is available (see level_demand_vector).
	var kw: float = max(1.0, spawn_window)
	out["kill_window"] = kw
	var total_count: int = 0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		var n: int = spawn.count
		total_count += n
		var ehp: float = float(ed.max_health) / max(0.05, 1.0 - ed.armor)
		var ehp_total: float = ehp * float(n)
		out["total_ehp"] += ehp_total
		# Archetype splits — same enemy can land in multiple buckets
		# (an armored flying enemy contributes to both flying_ehp and
		# armored_ehp). The bottleneck calc reads each bucket independently.
		if ed.is_flying:
			out["flying_ehp"] += ehp_total * c.flying_demand_weight
		else:
			out["ground_ehp"] += ehp_total
		if ed.armor > c.armor_classify_threshold:
			out["armored_ehp"] += ehp_total * c.armored_demand_weight
		if ed.magic_resist > c.magic_resist_classify_threshold:
			# Magic-resistant EHP uses the magic-side EHP formula so the
			# number reads as "damage a magic build must do to clear".
			var mehp: float = float(ed.max_health) / max(0.05, 1.0 - ed.magic_resist)
			out["magic_resist_ehp"] += mehp * float(n) * c.magic_resist_demand_weight
		if ed.is_boss:
			var phase_count: int = ed.boss_phases.size()
			var boss_mult: float = c.boss_demand_weight \
				* (1.0 + float(phase_count) * c.boss_phase_per_phase_bonus)
			out["boss_ehp"] += ehp_total * boss_mult
		if ed.bypass_engagement:
			out["bypass_pressure"] += ehp_total * c.bypass_demand_weight
		# Ability scoring — regen + heal_aura close the audit gap.
		out["ability_ehp_add"] += score_enemy_abilities(ed, kw, c) * float(n)
		# Block cost — soldiers/hero absorb damage instead of dealing it.
		# Approximation: each enemy spends some time engaged (fraction of
		# spawn_window). Pessimistic: 0.5 × spawn_window.
		var engage_time: float = kw * 0.5
		out["block_cost"] += ed.attack_damage * ed.attack_speed * engage_time \
			* float(n) * c.enemy_attack_dps_to_block_cost
	out["enemy_count"] = total_count
	out["density"] = (float(total_count) / spawn_window) if spawn_window > 0.5 \
		else float(total_count) * 2.0
	# required_dps includes the ability_ehp_add (regen/heal makes the wave
	# effectively bigger).
	out["required_dps"] = (out["total_ehp"] + out["ability_ehp_add"]) / kw
	return out


# Level demand vector — wave demands summed + level-wide aggregates. Used
# as the demand side of safety_ratio. spike_wave_index points at the wave
# with highest required_dps so the report can flag where pressure peaks.
static func level_demand_vector(wave_list: WaveList,
		config: BalanceModelConfig = null) -> Dictionary:
	var agg: Dictionary = {
		"total_ehp": 0.0, "ground_ehp": 0.0, "flying_ehp": 0.0,
		"armored_ehp": 0.0, "magic_resist_ehp": 0.0, "boss_ehp": 0.0,
		"bypass_pressure": 0.0, "ability_ehp_add": 0.0, "block_cost": 0.0,
		"enemy_count": 0, "max_density": 0.0, "max_required_dps": 0.0,
		"spike_wave_index": -1, "per_wave": [],
	}
	if wave_list == null:
		return agg
	var idx: int = 0
	for w in wave_list.waves:
		var v: Dictionary = wave_demand_vector(w, config)
		agg["per_wave"].append(v)
		agg["total_ehp"] += float(v.get("total_ehp", 0.0))
		agg["ground_ehp"] += float(v.get("ground_ehp", 0.0))
		agg["flying_ehp"] += float(v.get("flying_ehp", 0.0))
		agg["armored_ehp"] += float(v.get("armored_ehp", 0.0))
		agg["magic_resist_ehp"] += float(v.get("magic_resist_ehp", 0.0))
		agg["boss_ehp"] += float(v.get("boss_ehp", 0.0))
		agg["bypass_pressure"] += float(v.get("bypass_pressure", 0.0))
		agg["ability_ehp_add"] += float(v.get("ability_ehp_add", 0.0))
		agg["block_cost"] += float(v.get("block_cost", 0.0))
		agg["enemy_count"] += int(v.get("enemy_count", 0))
		var dens: float = float(v.get("density", 0.0))
		if dens > agg["max_density"]:
			agg["max_density"] = dens
		var rdps: float = float(v.get("required_dps", 0.0))
		if rdps > agg["max_required_dps"]:
			agg["max_required_dps"] = rdps
			agg["spike_wave_index"] = idx
		idx += 1
	return agg


# Tier-averaged DPS-per-gold for a single tower — weighted by per-tier
# weights from the config so designers can dial how much each tier "counts".
# Returns 0 for non-attacking towers (Barracks).
static func tower_avg_dps_per_gold(tower: TowerData,
		config: BalanceModelConfig = null) -> float:
	if tower == null:
		return 0.0
	var c: BalanceModelConfig = _cfg(config)
	var pairs: Array = []  # [(weight, dps/gold), ...]
	# L1
	var l1_dps: float = tower_dps_at_tier(tower, 0)
	var l1_cost: int = tower_cumul_cost(tower, 0)
	if l1_dps > 0.0 and l1_cost > 0:
		pairs.append([c.tier_l1_weight, l1_dps / float(l1_cost)])
	# L2
	if tower.level_upgrades.size() >= 1:
		var l2_dps: float = tower_dps_at_tier(tower, 1)
		var l2_cost: int = tower_cumul_cost(tower, 1)
		if l2_dps > 0.0 and l2_cost > 0:
			pairs.append([c.tier_l2_weight, l2_dps / float(l2_cost)])
	# L3 linear (only when no branches authored)
	if tower.level_3_branches.is_empty() and tower.level_upgrades.size() >= 2:
		var l3_dps: float = tower_dps_at_tier(tower, 2)
		var l3_cost: int = tower_cumul_cost(tower, 2)
		if l3_dps > 0.0 and l3_cost > 0:
			pairs.append([c.tier_l3_linear_weight, l3_dps / float(l3_cost)])
	# Branch picks (each branch contributes independently)
	for i in range(tower.level_3_branches.size()):
		var b_dps: float = tower_dps_at_tier(tower, 2 + i)
		var b_cost: int = tower_cumul_cost(tower, 2 + i)
		if b_dps > 0.0 and b_cost > 0:
			pairs.append([c.tier_branch_weight, b_dps / float(b_cost)])
	if pairs.is_empty():
		return 0.0
	var w_sum: float = 0.0
	var v_sum: float = 0.0
	for p in pairs:
		w_sum += float(p[0])
		v_sum += float(p[0]) * float(p[1])
	if w_sum <= 0.0:
		return 0.0
	return v_sum / w_sum


# Player supply vector — segmented damage budget over the level's duration.
# Reads a list of TowerData (loadout), HeroData, equipped skills (Array of
# SkillData). gold_budget_total + duration_sec come from LevelNodeData.
static func player_supply_vector(loadout_towers: Array, hero: HeroData,
		equipped_skills: Array, gold_budget_total: int, duration_sec: float,
		config: BalanceModelConfig = null) -> Dictionary:
	var out: Dictionary = {
		"segment_tower": 0.0, "segment_hero": 0.0, "segment_skills": 0.0,
		"segment_control": 0.0, "segment_blocking": 0.0,
		"physical_supply": 0.0, "magic_supply": 0.0,
		"anti_air_supply": 0.0, "aoe_supply": 0.0,
		"avg_dps_per_gold": 0.0,
		"total_supply": 0.0,
		"effective_to_theoretical_dps_ratio": 0.0,
	}
	var c: BalanceModelConfig = _cfg(config)
	var dur: float = max(1.0, duration_sec)
	var eff: float = c.effective_to_theoretical_dps_ratio
	out["effective_to_theoretical_dps_ratio"] = eff

	# ── Tower segment ────────────────────────────────────────────────────
	# Average DPS-per-gold across the loadout (skip non-attackers).
	# Then sub-tag by damage_type / targets_flying / aoe_radius.
	var dpg_total: float = 0.0
	var dpg_count: int = 0
	var anti_air_dpg: float = 0.0
	var anti_air_n: int = 0
	var aoe_dpg: float = 0.0
	var aoe_n: int = 0
	var phys_dpg: float = 0.0
	var phys_n: int = 0
	var mag_dpg: float = 0.0
	var mag_n: int = 0
	var control_capable_dpg: float = 0.0
	var control_capable_n: int = 0
	for t in loadout_towers:
		if not (t is TowerData):
			continue
		var tower: TowerData = t
		var dpg: float = tower_avg_dps_per_gold(tower, c)
		if dpg <= 0.0:
			continue  # Barracks have 0 dps — counted in blocking segment.
		dpg_total += dpg
		dpg_count += 1
		if tower.targets_flying:
			anti_air_dpg += dpg
			anti_air_n += 1
		if tower.aoe_radius > 0.0:
			aoe_dpg += dpg
			aoe_n += 1
		if tower.damage_type == 0:
			phys_dpg += dpg
			phys_n += 1
		else:
			mag_dpg += dpg
			mag_n += 1
		if tower.on_hit_slow_factor > 0.0 or tower.on_hit_stun_duration > 0.0 \
				or _tower_branch_has_control(tower):
			control_capable_dpg += dpg
			control_capable_n += 1
	var avg_dpg: float = (dpg_total / float(dpg_count)) if dpg_count > 0 else 0.0
	out["avg_dps_per_gold"] = avg_dpg
	# Damage produced over duration by spending all gold at avg_dpg.
	var tower_damage_budget: float = avg_dpg * float(gold_budget_total) * dur * eff
	out["segment_tower"] = tower_damage_budget * c.segment_tower_weight
	# Sub-tag supplies. Each sub-segment uses its own dpg average + a fraction
	# = (matching_count / dpg_count) so a loadout with 1 anti-air tower out
	# of 4 reports 25% of tower budget as anti-air.
	if anti_air_n > 0 and dpg_count > 0:
		var aa_dpg: float = anti_air_dpg / float(anti_air_n)
		var aa_share: float = float(anti_air_n) / float(dpg_count)
		out["anti_air_supply"] = aa_dpg * float(gold_budget_total) * aa_share \
			* dur * eff * c.segment_tower_weight
	if aoe_n > 0 and dpg_count > 0:
		var ao_dpg: float = aoe_dpg / float(aoe_n)
		var ao_share: float = float(aoe_n) / float(dpg_count)
		out["aoe_supply"] = ao_dpg * float(gold_budget_total) * ao_share \
			* dur * eff * c.segment_tower_weight
	if phys_n > 0 and dpg_count > 0:
		var ph_dpg: float = phys_dpg / float(phys_n)
		var ph_share: float = float(phys_n) / float(dpg_count)
		out["physical_supply"] = ph_dpg * float(gold_budget_total) * ph_share \
			* dur * eff * c.segment_tower_weight
	if mag_n > 0 and dpg_count > 0:
		var mg_dpg: float = mag_dpg / float(mag_n)
		var mg_share: float = float(mag_n) / float(dpg_count)
		out["magic_supply"] = mg_dpg * float(gold_budget_total) * mg_share \
			* dur * eff * c.segment_tower_weight
	# Hero-also-contributes-physical/anti-air will be added below.

	# ── Hero segment ─────────────────────────────────────────────────────
	if hero != null:
		var hero_dps: float = hero.attack_damage * hero.attack_speed
		var hero_dmg: float = hero_dps * dur * c.hero_active_time_pct * eff
		out["segment_hero"] = hero_dmg * c.segment_hero_weight
		# Hero also tags into sub-supplies.
		if hero.targets_flying:
			out["anti_air_supply"] += out["segment_hero"]
		if hero.damage_type == 0:
			out["physical_supply"] += out["segment_hero"]
		else:
			out["magic_supply"] += out["segment_hero"]

	# ── Skills segment ───────────────────────────────────────────────────
	for s in equipped_skills:
		if not (s is SkillData):
			continue
		var sk: SkillData = s
		if sk.cooldown <= 0.0 or sk.damage <= 0.0:
			continue
		var skill_dps: float = sk.damage / sk.cooldown
		var skill_dmg: float = skill_dps * dur * c.skill_uptime_pct * eff
		out["segment_skills"] += skill_dmg
		# Sub-tag.
		if sk.damage_type == 0:
			out["physical_supply"] += skill_dmg * c.segment_skills_weight
		else:
			out["magic_supply"] += skill_dmg * c.segment_skills_weight
	out["segment_skills"] *= c.segment_skills_weight

	# ── Control segment ──────────────────────────────────────────────────
	# CC-as-DPS-multiplier (NOT flat damage). Estimate that control-capable
	# towers extend their effective damage by (slow_dps_multiplier - 1)
	# during the affected window. Capped at control_stack_cap fraction of
	# the level duration so stacking can't run away.
	if control_capable_n > 0 and dpg_count > 0:
		var cc_dpg: float = control_capable_dpg / float(control_capable_n)
		var cc_share: float = float(control_capable_n) / float(dpg_count)
		var cc_uptime: float = clampf(c.control_stack_cap, 0.0, 1.0)
		var bonus_mult: float = max(0.0, c.slow_dps_multiplier - 1.0)
		out["segment_control"] = cc_dpg * float(gold_budget_total) * cc_share \
			* dur * eff * cc_uptime * bonus_mult * c.segment_control_weight

	# ── Blocking segment ─────────────────────────────────────────────────
	# Soldiers absorb damage; their value = (count × hp). Hero blocking
	# similarly. Converted to a damage budget via a coarse rate.
	var block_value: float = 0.0
	if hero != null:
		block_value += float(hero.max_block_targets) * float(hero.max_health)
	for t in loadout_towers:
		if not (t is TowerData):
			continue
		var tower: TowerData = t
		if tower.is_barracks() and tower.soldier_data != null:
			var sd: Resource = tower.soldier_data
			var sd_count: float = float(sd.max_count) if "max_count" in sd else 3.0
			var sd_hp: float = float(sd.max_health) if "max_health" in sd else 30.0
			block_value += sd_count * sd_hp
	# 0.5 = block-value-to-damage conversion rate (rough; tunable later).
	out["segment_blocking"] = block_value * 0.5 * c.segment_blocking_weight

	out["total_supply"] = out["segment_tower"] + out["segment_hero"] \
		+ out["segment_skills"] + out["segment_control"] + out["segment_blocking"]
	return out


# Helper: does any branch upgrade carry slow/stun? Used to tag a tower as
# "control-capable" even when its base form doesn't slow (e.g. Archer →
# Ranger branch adds slow at L3).
static func _tower_branch_has_control(tower: TowerData) -> bool:
	if tower == null:
		return false
	for b in tower.level_3_branches:
		if b == null:
			continue
		if b is TowerUpgradeData:
			var bd: TowerUpgradeData = b
			if bd.on_hit_slow_factor > 0.0 or bd.on_hit_stun_duration > 0.0:
				return true
	for u in tower.level_upgrades:
		if u == null:
			continue
		if u is TowerUpgradeData:
			var ud: TowerUpgradeData = u
			if ud.on_hit_slow_factor > 0.0 or ud.on_hit_stun_duration > 0.0:
				return true
	return false


# Top-level entry. Combines demand + supply, computes safety_ratio + every
# sub-ratio, identifies the bottleneck (key with min ratio < 1.0; "none" if
# all ≥ 1.0). Pass any Array of TowerData / Hero / equipped skills; the
# function tolerates empty/null inputs gracefully.
static func supply_demand_report(level_data: LevelNodeData, wave_list: WaveList,
		loadout_towers: Array, hero: HeroData, equipped_skills: Array,
		config: BalanceModelConfig = null) -> Dictionary:
	var c: BalanceModelConfig = _cfg(config)
	var demand: Dictionary = level_demand_vector(wave_list, c)
	var gold_budget: int = 0
	var duration: float = 600.0
	if level_data != null:
		gold_budget = int(level_data.gold_budget_total)
		duration = float(level_data.target_duration_sec)
	var supply: Dictionary = player_supply_vector(loadout_towers, hero,
		equipped_skills, gold_budget, duration, c)
	# Total demand = total_ehp + ability_ehp_add + block_cost (drain on supply)
	var total_demand: float = float(demand.get("total_ehp", 0.0)) \
		+ float(demand.get("ability_ehp_add", 0.0)) \
		+ float(demand.get("block_cost", 0.0))
	var total_supply: float = float(supply.get("total_supply", 0.0))
	var safety: float = (total_supply / total_demand) if total_demand > 0.0 else 0.0
	# Sub-ratios — each one's "demand" is the per-category number; supply is
	# the matching tagged supply. Lower = the player struggles in that axis.
	var avg_kw: float = duration / float(max(1, wave_list.waves.size())) \
		if wave_list != null and wave_list.waves.size() > 0 else duration
	var sub: Dictionary = {}
	# Anti-air
	var fly_demand: float = float(demand.get("flying_ehp", 0.0))
	if fly_demand > 0.0:
		var fly_dps_demand: float = fly_demand / avg_kw
		sub["anti_air"] = (float(supply.get("anti_air_supply", 0.0)) / duration) \
			/ max(0.001, fly_dps_demand)
	# Armored — physical builds need extra tower damage to chew through armor.
	var arm_demand: float = float(demand.get("armored_ehp", 0.0))
	if arm_demand > 0.0:
		sub["armored"] = float(supply.get("magic_supply", 0.0)) / arm_demand
	# Magic-resist — magic builds suffer; physical solves it.
	var mr_demand: float = float(demand.get("magic_resist_ehp", 0.0))
	if mr_demand > 0.0:
		sub["magic_res"] = float(supply.get("physical_supply", 0.0)) / mr_demand
	# Swarm pressure
	var max_dens: float = float(demand.get("max_density", 0.0))
	if max_dens > 0.0:
		sub["swarm"] = (float(supply.get("aoe_supply", 0.0)) / duration) \
			/ max(0.001, max_dens * c.density_pressure_weight)
	# Boss
	var boss_demand: float = float(demand.get("boss_ehp", 0.0))
	if boss_demand > 0.0:
		# Hero + skills carry boss kill weight more than gold spend does.
		sub["boss"] = (float(supply.get("segment_hero", 0.0))
			+ float(supply.get("segment_skills", 0.0))
			+ float(supply.get("segment_tower", 0.0)) * 0.3) / boss_demand
	# Rush — bypass enemies skip the soldier line.
	var rush_demand: float = float(demand.get("bypass_pressure", 0.0))
	if rush_demand > 0.0:
		sub["rush"] = float(supply.get("segment_blocking", 0.0)) / rush_demand
	# Gold — does spend rate cover required DPS?
	var max_rdps: float = float(demand.get("max_required_dps", 0.0))
	if max_rdps > 0.0:
		var afford: float = affordable_dps(gold_budget, c.dps_per_gold)
		sub["gold"] = afford / max_rdps
	# Bottleneck = lowest sub-ratio < 1.0.
	var bottleneck: String = "none"
	var bottleneck_ratio: float = INF
	for k in sub.keys():
		var r: float = float(sub[k])
		if r < 1.0 and r < bottleneck_ratio:
			bottleneck = String(k)
			bottleneck_ratio = r
	return {
		"safety_ratio": safety,
		"total_supply": total_supply,
		"total_demand": total_demand,
		"supply": supply,
		"demand": demand,
		"sub_ratios": sub,
		"bottleneck": bottleneck,
		"bottleneck_ratio": bottleneck_ratio if bottleneck != "none" else 0.0,
		"spike_wave_index": int(demand.get("spike_wave_index", -1)),
	}


# Color band for a safety_ratio per BalanceModelConfig thresholds.
# Colors mirror the report's column conventions:
#   red    — < red_max     (impossible/tight)
#   orange — < orange_max  (very hard)
#   green  — < green_max   (good challenge)
#   blue   — < blue_max    (comfortable)
#   grey   — ≥ blue_max    (too easy)
static func safety_color(ratio: float, config: BalanceModelConfig = null) -> Color:
	var c: BalanceModelConfig = _cfg(config)
	if ratio < c.safety_ratio_red_max:
		return Color(0.95, 0.45, 0.45)
	if ratio < c.safety_ratio_orange_max:
		return Color(0.95, 0.70, 0.40)
	if ratio < c.safety_ratio_green_max:
		return Color(0.5, 0.95, 0.5)
	if ratio < c.safety_ratio_blue_max:
		return Color(0.5, 0.75, 1.0)
	return Color(0.7, 0.7, 0.7)


# Calibrate effective:theoretical DPS ratio from RunStats history. Computes
# (avg damage_by_tower_total) / (theoretical_dps × duration) across runs of
# the matching level_id. Returns 0.0 if no qualifying runs exist.
static func observed_effective_dps_ratio(level_id: String, history: Array,
		config: BalanceModelConfig = null) -> float:
	if history.is_empty():
		return 0.0
	var c: BalanceModelConfig = _cfg(config)
	var ratios: Array[float] = []
	for entry in history:
		if not (entry is Dictionary):
			continue
		if String(entry.get("level_id", "")) != level_id:
			continue
		var dur: float = float(entry.get("duration_s", 0.0))
		if dur <= 0.0:
			continue
		var src: Dictionary = entry.get("damage_by_source", {})
		var towers_total: float = float(src.get("towers_total", 0.0))
		var gold: int = int(entry.get("starting_gold", 100))
		# Theoretical: gold × dps_per_gold × duration. Crude but consistent.
		var theoretical: float = float(gold) * c.dps_per_gold * dur
		if theoretical <= 0.0:
			continue
		ratios.append(towers_total / theoretical)
	if ratios.is_empty():
		return 0.0
	var s: float = 0.0
	for r in ratios:
		s += r
	return s / float(ratios.size())
