extends RefCounted
class_name BalanceLogger

# Editor + runtime hardness readout. Loads BalanceCalculator dynamically and
# prints per-wave breakdowns, gold-vs-need ratios, dead-air audit, tower
# damage-per-gold, and pressure drift warnings.
#
# Lives under res://balance/ so it ships out of production exports along with
# the rest of the design-time tooling. Called from BaseLevel._ready (debug
# builds only) — extracted out of BaseLevel so the level script stays focused
# on rendering + spot registration.
#
# Uses load() (not preload / class_name) on BalanceCalculator and LevelList
# per CORE RULE 16 — avoids Godot 4.4+ class_name preload race.

static func print_hardness_readout(_level: Node, level_id: String, wave_path: String, display_tag: String) -> void:
	if not OS.is_debug_build():
		return
	if wave_path == "":
		return
	var wl: WaveList = load(wave_path)
	if wl == null:
		return
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return
	var b: Dictionary = bc.score_level_breakdown(wl, RunState.STARTING_GOLD)
	var per: String = ""
	var pw: Array = b.per_wave
	var pg: Array = b.per_wave_gold
	var pd: Array = b.per_wave_density
	for i in range(pw.size()):
		per += "  W%d=%d (%dg, %.1fe/s)" % [i + 1, int(pw[i]), int(pg[i]), float(pd[i])]
	print("[%s/Balance] %s net=%d (waves=%d, start=%dg)%s" % [
		display_tag, String(b.tier), int(b.net_score), int(b.wave_total), int(b.starting_gold), per
	])
	print("[%s/Budget] natural=%dg  max_with_early_calls=%dg  swing=+%dg" % [
		display_tag, int(b.gold_natural), int(b.gold_max_with_early_calls), int(b.early_call_swing)
	])
	# Damage/cost ratios — the load-bearing hardness diagnostic.
	# req_dmg = total physical EHP to clear the wave with zero leak.
	# req_dps = DPS floor over the spawn window.
	# g/dmg   = gold-awarded ÷ damage-required (stinginess: <0.08 brutal,
	#           0.10–0.25 healthy, >0.30 trivial).
	var ratio_line: String = ""
	var total_req_dmg: float = 0.0
	for i in range(wl.waves.size()):
		var w: WaveData = wl.waves[i]
		var req_dmg: float = bc.wave_required_damage(w)
		var req_dps: float = bc.wave_required_dps(w)
		var gpd: float = bc.wave_gold_per_damage(w)
		ratio_line += "  W%d=%d req_dps=%.1f g/dmg=%.2f" % [i + 1, int(req_dmg), req_dps, gpd]
		total_req_dmg += req_dmg
	var level_gpd: float = 0.0
	if total_req_dmg > 0.0:
		level_gpd = float(b.gold_natural) / total_req_dmg
	print("[%s/Ratios] req_dmg=%d  natural_g/dmg=%.2f%s" % [
		display_tag, int(total_req_dmg), level_gpd, ratio_line
	])
	# Tower damage-per-gold table — 1 gold buys X damage over 60s, by tier.
	var towers: Array = ContentRegistry.towers if ContentRegistry != null else []
	var window_sec: float = 60.0
	print("[%s/Towers] dmg per gold over %.0fs window:" % [display_tag, window_sec])
	var best_l1: float = 0.0
	for t in towers:
		if not (t is TowerData) or t.damage <= 0.0:
			continue
		var l1: float = bc.tower_damage_per_gold(t, 0, window_sec)
		var l2: float = bc.tower_damage_per_gold(t, 1, window_sec)
		var l3: float = bc.tower_damage_per_gold(t, 2, window_sec)
		print("  %s  L1=%.2f  L2=%.2f  L3=%.2f" % [String(t.tower_name), l1, l2, l3])
		if l1 > best_l1:
			best_l1 = l1
	if best_l1 > 0.0:
		var req_line: String = "  best_L1=%.2f dmg/g  →" % best_l1
		for i in range(wl.waves.size()):
			var w: WaveData = wl.waves[i]
			var rg: int = bc.wave_required_gold(w, best_l1)
			req_line += "  W%d_need=%dg/got=%dg" % [i + 1, rg, int(b.per_wave_gold[i])]
		print("[%s/GoldVsNeed]%s" % [display_tag, req_line])
	# Dual-EHP audit — flags waves biased against magic or physical damage.
	# Bias = (magic_ehp - physical_ehp) / physical_ehp. Positive = magic-
	# resistant cluster (Mage builds struggle); negative = armor-heavy
	# cluster (Archer/Mage flips would win). |bias| > 25% triggers ⚠.
	# Surfaces the gap left by the unified hardness score, which folds only
	# armor and silently hides magic-resist clustering.
	var ehp_line: String = ""
	for i in range(wl.waves.size()):
		var w_e: WaveData = wl.waves[i]
		var p: float = bc.wave_ehp_physical(w_e)
		var m: float = bc.wave_ehp_magic(w_e)
		var bias: float = 0.0
		if p > 0.0:
			bias = (m - p) / p * 100.0
		var bias_flag: String = " ⚠" if absf(bias) > 25.0 else ""
		ehp_line += "  W%d phys=%d mag=%d bias=%+.0f%%%s" % [i + 1, int(p), int(m), bias, bias_flag]
	print("[%s/EHP]%s" % [display_tag, ehp_line])
	# Dead-air audit — flag spawn gaps >5s.
	var dead_line: String = ""
	for i in range(wl.waves.size()):
		var w: WaveData = wl.waves[i]
		var t: Dictionary = bc.wave_spawn_timeline(w)
		var flag: String = " ⚠" if float(t.max_gap) > 5.0 else ""
		dead_line += "  W%d max=%.1fs dead=%.1fs%s" % [
			i + 1, float(t.max_gap), float(t.dead_air), flag
		]
	print("[%s/DeadAir]%s" % [display_tag, dead_line])
	# Pressure block — actual gold/pressure vs target. Drift > 15% triggers WARN.
	var ld: LevelNodeData = _find_level_data(level_id)
	if ld == null:
		return
	var rep: Dictionary = bc.level_pressure_report(wl, ld, RunState.STARTING_GOLD)
	var pressure_line: String = ""
	for entry in rep.per_wave:
		pressure_line += "  W%d g=%d/%d p=%.2f/%.2f" % [
			int(entry.wave),
			int(entry.actual_gold), int(entry.target_gold),
			float(entry.actual_pressure), float(entry.target_pressure),
		]
	print("[%s/Pressure] total=%d/%dg (%+.0f%%)%s" % [
		display_tag, int(rep.total_actual_gold), int(rep.total_target_gold),
		float(rep.total_drift_pct), pressure_line
	])
	for w in rep.warnings:
		print("[%s/DRIFT] WARN %s" % [display_tag, String(w)])
	# Authored floor time vs target_duration_sec — supports BALANCE.md's
	# 10-minute rule (L4+). Floor is countdowns + spawn windows; target is
	# the desired actual play time. Healthy authoring lands floor ~30-50%
	# above target so a fast player finishes near target. Just informational
	# — no flag at this layer; per-level drift flags happen in BalanceReport
	# against telemetry, not authored numbers.
	var floor_sec: float = bc.level_floor_time(wl)
	var target_sec: float = ld.target_duration_sec
	var gap_str: String = "—"
	if target_sec > 0.0:
		var gap_pct: float = (floor_sec - target_sec) / target_sec * 100.0
		gap_str = "%+.0f%%" % gap_pct
	print("[%s/Duration] floor=%ds target=%ds gap=%s" % [
		display_tag, int(floor_sec), int(target_sec), gap_str
	])


# Look up a level's authored targets from level_list.tres. Returns null if
# the registry is missing or the level_id isn't found.
static func _find_level_data(level_id: String) -> LevelNodeData:
	# Avoid `as LevelList` cast — class_name registration may race with the
	# editor's class index (CORE RULE 16). Untyped Resource access works
	# because the loaded resource has the LevelList script attached.
	var registry: Resource = load("res://ui/world_map/level_list.tres")
	if registry == null:
		return null
	var levels: Array = registry.levels
	for entry in levels:
		if entry is LevelNodeData and entry.level_id == level_id:
			return entry
	return null
