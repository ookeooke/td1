extends RefCounted
class_name BalanceVerdict

# Computes the post-run "Balance Verdict" from a finished RunStats record:
# pulls authored targets from LevelNodeData / wave_list, derives metric rows
# (duration drift, gold hoarding, top-tower share, hero share, lives loss),
# emits flags (tower_domination, gold_hoarding, duration_drift, leak_spike,
# hero_carry, naked_fail, unused_tower), and includes a Δ-vs-prior comparison
# block when ≥2 prior runs of the same level + mode exist in history.
#
# Pure read; no .tres mutation, no signal connections, no scene writes.
# Debug-only — GameOverScreen gates the entire VerdictPanel on
# OS.is_debug_build() before calling compute().
#
# Returns a Dictionary shaped:
#   {
#     "metrics": [{label, value_str, delta_str_or_empty}],
#     "flags":   [{id, label, severity}],   # severity ∈ "warn" | "info"
#     "history_n": int,                     # prior runs available for delta
#   }

const _COMPARE_HISTORY: int = 5
const _FLAG_TOWER_DOMINATION_PCT: float = 60.0
const _FLAG_HERO_CARRY_PCT: float = 50.0
const _FLAG_GOLD_HOARDING_PCT: float = 30.0  # final_gold > 30% of (starting + budget) → hoarding
const _FLAG_DURATION_DRIFT_PCT: float = 25.0
const _FLAG_LEAK_SPIKE_PCT: float = 40.0     # one wave > 40% of total leaks
const _FLAG_UNUSED_TOWER_PCT: float = 5.0    # built tower < 5% damage share
const _FLAG_NAKED_PPT_CEIL: float = 1.5


static func compute(record: Dictionary, level_data: Resource, wave_list: Resource, history: Array) -> Dictionary:
	var metrics: Array = []
	var flags: Array = []

	var outcome: String = String(record.get("outcome", "?"))
	var stars: int = int(record.get("stars_earned", 0))
	metrics.append(_metric("Outcome", "%s · %d★" % [outcome.capitalize(), stars], ""))

	# Duration vs target_duration_sec.
	var dur: float = float(record.get("duration_s", 0.0))
	var target_dur: float = float(level_data.target_duration_sec) if level_data != null and "target_duration_sec" in level_data else 0.0
	var dur_str: String = "%.0fs" % dur
	if target_dur > 0.0:
		var dur_pct: float = (dur - target_dur) / target_dur * 100.0
		dur_str += "  (target %.0fs, %+.0f%%)" % [target_dur, dur_pct]
		if absf(dur_pct) > _FLAG_DURATION_DRIFT_PCT:
			flags.append(_flag("duration_drift",
				"Duration off target by %+.0f%%" % dur_pct,
				"warn"))
	metrics.append(_metric("Duration", dur_str, _delta_str_for(history, "duration_s", dur, "%.0fs", false)))

	# Lives lost.
	var lives_lost_arr: Array = record.get("lives_lost_per_wave", [])
	var lives_lost: int = 0
	var max_wave_leak: int = 0
	for v in lives_lost_arr:
		var n: int = int(v)
		lives_lost += n
		if n > max_wave_leak:
			max_wave_leak = n
	var starting_lives: int = int(record.get("starting_lives", 0))
	metrics.append(_metric(
		"Lives lost",
		"%d / %d" % [lives_lost, starting_lives],
		_delta_str_for(history, "lives_lost_total", float(lives_lost), "%.0f", false),
	))
	if lives_lost > 0 and max_wave_leak > 0:
		var spike_share: float = float(max_wave_leak) / float(lives_lost) * 100.0
		if spike_share > _FLAG_LEAK_SPIKE_PCT and lives_lost >= 3:
			flags.append(_flag("leak_spike",
				"One wave caused %.0f%% of leaks" % spike_share,
				"warn"))

	# Gold hoarding: did the player sit on a fortune at the end?
	var final_gold: int = int(record.get("final_gold", 0))
	var starting_gold: int = int(record.get("starting_gold", 0))
	var budget_total: int = int(level_data.gold_budget_total) if level_data != null and "gold_budget_total" in level_data else 0
	var max_gold: int = starting_gold + budget_total
	var hoard_pct: float = (float(final_gold) / float(max_gold) * 100.0) if max_gold > 0 else 0.0
	metrics.append(_metric(
		"Gold remaining",
		"%dg  (%.0f%% of %dg max)" % [final_gold, hoard_pct, max_gold],
		_delta_str_for(history, "final_gold", float(final_gold), "%.0fg", false),
	))
	if hoard_pct > _FLAG_GOLD_HOARDING_PCT and outcome == "victory":
		flags.append(_flag("gold_hoarding",
			"Sat on %.0f%% of available gold" % hoard_pct,
			"info"))

	# Damage attribution.
	var dbs: Dictionary = record.get("damage_by_source", {})
	var hero_dmg: float = float(dbs.get("hero", 0.0))
	var sold_dmg: float = float(dbs.get("soldiers", 0.0))
	var tow_dmg: float = float(dbs.get("towers_total", 0.0))
	var grand_total: float = hero_dmg + sold_dmg + tow_dmg
	if grand_total > 0.0:
		var hero_pct: float = hero_dmg / grand_total * 100.0
		metrics.append(_metric(
			"Hero damage",
			"%.0f%%  (%s)" % [hero_pct, _fmt_n(hero_dmg)],
			"",
		))
		if hero_pct > _FLAG_HERO_CARRY_PCT:
			flags.append(_flag("hero_carry",
				"Hero dealt %.0f%% of damage" % hero_pct,
				"info"))
		# Top tower share + dom flag.
		var rows: Array = record.get("damage_by_tower", [])
		if not rows.is_empty():
			rows.sort_custom(func(a, b): return float(a.get("damage", 0.0)) > float(b.get("damage", 0.0)))
			var top: Dictionary = rows[0]
			var top_share: float = float(top.get("damage", 0.0)) / grand_total * 100.0
			metrics.append(_metric(
				"Top tower",
				"%s  %.0f%%" % [String(top.get("name", "?")), top_share],
				"",
			))
			if top_share > _FLAG_TOWER_DOMINATION_PCT:
				flags.append(_flag("tower_domination",
					"%s carried %.0f%% of damage" % [String(top.get("name", "?")), top_share],
					"warn"))
			# Unused-tower flag — any built-and-still-standing tower below 5%.
			# Sold towers are excluded (they're in tower_sells but rows only
			# carry the ones that survived to finalize). Fires per offender.
			for r in rows:
				var share: float = float(r.get("damage", 0.0)) / grand_total * 100.0
				if share < _FLAG_UNUSED_TOWER_PCT:
					flags.append(_flag("unused_tower",
						"%s contributed %.1f%% — consider re-tuning" % [String(r.get("name", "?")), share],
						"info"))

	# Naked Baseline failure — defeat with low loadout PPT means the level is
	# gear-gated, which violates the BALANCE.md invariant.
	var loadout: Dictionary = record.get("loadout", {})
	var ppt: float = float(loadout.get("effective_ppt", -1.0))
	if outcome == "defeat" and ppt > 0.0 and ppt < _FLAG_NAKED_PPT_CEIL:
		flags.append(_flag("naked_fail",
			"Defeat at PPT %.1f — Naked Baseline floor breached" % ppt,
			"warn"))

	# Hardness drift vs target_ppt — needs the wave_list + BalanceCalculator.
	if level_data != null and wave_list != null and "target_ppt" in level_data and int(level_data.target_ppt) > 0:
		var bc: GDScript = load("res://balance/BalanceCalculator.gd")
		if bc != null:
			var hardness: float = bc.score_level(wave_list, max(starting_gold, 100))
			var expected: float = float(level_data.target_ppt) * bc.PPT_TO_HARDNESS_FACTOR
			var drift_pct: float = (hardness - expected) / expected * 100.0 if expected > 0.0 else 0.0
			metrics.append(_metric(
				"Hardness drift",
				"%.0f vs %.0f expected  (%+.0f%%)" % [hardness, expected, drift_pct],
				"",
			))

	return {
		"metrics": metrics,
		"flags": flags,
		"history_n": history.size(),
	}


# Filter `RunStats.get_history()` to recent runs of same level + mode (excluding
# the just-finished record). Caller passes the full history and the active record.
static func recent_comparable(history: Array, level_id: String, mode: String, exclude_run_id: String) -> Array:
	var out: Array = []
	# Walk newest-first; history is appended in chronological order.
	for i in range(history.size() - 1, -1, -1):
		var r = history[i]
		if not (r is Dictionary):
			continue
		if String(r.get("level_id", "")) != level_id:
			continue
		if String(r.get("mode", "")) != mode:
			continue
		if String(r.get("run_id", "")) == exclude_run_id:
			continue
		out.append(r)
		if out.size() >= _COMPARE_HISTORY:
			break
	return out


static func _metric(label: String, value_str: String, delta_str: String) -> Dictionary:
	return {"label": label, "value_str": value_str, "delta_str": delta_str}


static func _flag(id: String, label: String, severity: String) -> Dictionary:
	return {"id": id, "label": label, "severity": severity}


# Δ-vs-history string for a numeric metric. Compares to mean of `history`
# entries' value at `key`. Returns empty string when comparison can't be made
# (need ≥2 prior entries for a meaningful average).
static func _delta_str_for(history: Array, key: String, current: float, fmt: String, _higher_is_better: bool) -> String:
	if history.size() < 2:
		return ""
	var sum: float = 0.0
	var n: int = 0
	for r in history:
		if not (r is Dictionary):
			continue
		# Special key: lives_lost_total isn't a record field — compute on the fly.
		var v: float = 0.0
		if key == "lives_lost_total":
			var arr: Array = r.get("lives_lost_per_wave", [])
			for x in arr:
				v += float(int(x))
		else:
			if not r.has(key):
				continue
			v = float(r.get(key, 0.0))
		sum += v
		n += 1
	if n < 2:
		return ""
	var avg: float = sum / float(n)
	var delta: float = current - avg
	# Arrow shows trend direction; severity-coloring is the panel's job.
	var arrow: String = "→"
	if delta > 0.0:
		arrow = "↑"
	elif delta < 0.0:
		arrow = "↓"
	return "%s %s vs avg" % [arrow, fmt % delta]


static func _fmt_n(n: float) -> String:
	var i: int = int(round(n))
	if i < 1000:
		return str(i)
	var s: String = str(i)
	var out: String = ""
	var c: int = 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		c += 1
		if c % 3 == 0 and k > 0:
			out = "," + out
	return out
