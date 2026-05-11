extends RefCounted
class_name RunStatsDigest

# Pure read-only aggregator over the run_stats.json history (schema 1..5).
# Returns structured dictionaries — no UI, no side effects. Consumers:
#   1. balance/report/BalanceReport.gd (UI screen) — can call any of these to
#      surface more detail without owning the rollup logic.
#   2. headless audits / GUT tests — can assert on win rates per level.
#   3. balance-scout sessions — read user://run_stats.json, run the digest,
#      reason about drift without re-deriving the numbers each time.
#
# Schema 5 fields drive the most useful new outputs (boss_events, wave-level
# damage/leaks, peak_concurrent_enemies_global, level_hardness/target_ppt,
# tower_events timeline, skill_casts). Older records still aggregate cleanly
# — missing fields default to neutral values.


# Overall summary across every run in `runs`.
static func summarize(runs: Array) -> Dictionary:
	var out: Dictionary = {
		"n": runs.size(),
		"victories": 0,
		"defeats": 0,
		"baseline_runs": 0,
		"baseline_victories": 0,
		"by_level": {},
	}
	for r in runs:
		var lvl: String = String(r.get("level_id", ""))
		var win: bool = String(r.get("outcome", "")) == "victory"
		if win:
			out.victories += 1
		else:
			out.defeats += 1
		if bool(r.get("naked_baseline", false)):
			out.baseline_runs += 1
			if win:
				out.baseline_victories += 1
		var per: Dictionary = out.by_level.get(lvl, {"n": 0, "wins": 0})
		per.n += 1
		if win:
			per.wins += 1
		out.by_level[lvl] = per
	return out


# Filter runs to a single level. Returns the same array shape, oldest → newest.
static func runs_for_level(runs: Array, level_id: String, last_n: int = -1) -> Array:
	var out: Array = []
	for r in runs:
		if String(r.get("level_id", "")) == level_id:
			out.append(r)
	if last_n > 0 and out.size() > last_n:
		out = out.slice(out.size() - last_n, out.size())
	return out


# Per-level digest. `opts.naked_only` filters to Naked Baseline runs, `opts.last_n`
# truncates to the most recent N runs.
static func level_digest(runs: Array, level_id: String, opts: Dictionary = {}) -> Dictionary:
	var filtered: Array = runs_for_level(runs, level_id, int(opts.get("last_n", -1)))
	if bool(opts.get("naked_only", false)):
		filtered = filtered.filter(func(r): return bool(r.get("naked_baseline", false)))
	var d: Dictionary = {
		"level_id": level_id,
		"n_runs": filtered.size(),
		"victories": 0,
		"defeats": 0,
		"win_pct": 0.0,
		"hero_picks": {},
		"tower_picks": {},
		"skill_picks": {},
		"avg_duration_s": 0.0,
		"avg_final_gold": 0.0,
		"avg_early_call_count": 0.0,
		"per_wave": [],
		"leakiest_wave": -1,
		"hardest_wave_by_damage": -1,
		"peak_concurrent_global_avg": 0.0,
		"level_hardness_seen": [],
		"level_target_ppt_seen": [],
		"boss_summary": {"n_spawns": 0, "n_killed": 0, "kill_pct": 0.0, "avg_ttk_s": 0.0, "by_id": {}},
		"skill_casts_top": [],
		"tower_events_kinds": {"built": 0, "upgraded": 0, "branch": 0, "sold": 0},
		"defeat_reasons": {},
		"final_wave_dist": {},
		"avg_game_speed": 0.0,
		"tower_efficiency": {},  # tower_id -> {n, hits[], damage[], lifetime[]} accumulator; finalized to Array below.
	}
	if filtered.is_empty():
		return d
	var dur_sum: float = 0.0
	var gold_sum: float = 0.0
	var ec_sum: float = 0.0
	var peak_sum: float = 0.0
	var per_wave_acc: Dictionary = {} # wave -> {damage:[], clear:[], leak:[], n}
	var boss_ttk_sum: float = 0.0
	var boss_ttk_n: int = 0
	var skill_cast_acc: Dictionary = {}
	for r in filtered:
		if String(r.get("outcome", "")) == "victory":
			d.victories += 1
		else:
			d.defeats += 1
		dur_sum += float(r.get("duration_s", 0.0))
		gold_sum += float(r.get("final_gold", 0.0))
		ec_sum += float(r.get("early_call_count", 0.0))
		peak_sum += float(r.get("peak_concurrent_enemies_global", 0.0))
		_inc(d.hero_picks, String(r.get("hero_id", "")))
		var loadout: Dictionary = r.get("loadout", {})
		for tid in loadout.get("tower_ids", []):
			_inc(d.tower_picks, String(tid))
		for sid in loadout.get("equipped_skills", []):
			_inc(d.skill_picks, String(sid))
		var lh: float = float(r.get("level_hardness", -1.0))
		if lh >= 0.0:
			d.level_hardness_seen.append(lh)
		var lp: int = int(r.get("level_target_ppt", -1))
		if lp > 0:
			d.level_target_ppt_seen.append(lp)
		var waves: Array = r.get("waves", [])
		for w in waves:
			var wn: int = int(w.get("wave", -1))
			if wn <= 0:
				continue
			var acc: Dictionary = per_wave_acc.get(wn, {
				"damage": [], "clear": [], "leak": [], "peak_wave": [],
				"dmg_hero": [], "dmg_soldiers": [], "dmg_towers": [],
				"leaked_by_id": {},
			})
			acc.damage.append(float(w.get("damage_total", 0.0)))
			acc.clear.append(float(w.get("clear_time_s", -1.0)))
			acc.leak.append(int(w.get("lives_lost", 0)))
			acc.peak_wave.append(int(w.get("peak_concurrent_enemies", 0)))
			var dbs: Dictionary = w.get("damage_by_source", {})
			acc.dmg_hero.append(float(dbs.get("hero", 0.0)))
			acc.dmg_soldiers.append(float(dbs.get("soldiers", 0.0)))
			acc.dmg_towers.append(float(dbs.get("towers", 0.0)))
			var ebi: Dictionary = w.get("enemies_by_id", {})
			for eid in ebi.keys():
				var leaked: int = int(ebi[eid].get("leaked", 0))
				if leaked > 0:
					acc.leaked_by_id[eid] = int(acc.leaked_by_id.get(eid, 0)) + leaked
			per_wave_acc[wn] = acc
		var boss_events: Array = r.get("boss_events", [])
		d.boss_summary.n_spawns += boss_events.size()
		for be in boss_events:
			var bid: String = String(be.get("boss_id", ""))
			var by_id: Dictionary = d.boss_summary.by_id.get(bid, {"spawns": 0, "killed": 0, "leaked": 0})
			by_id.spawns += 1
			if String(be.get("ended", "")) == "killed":
				by_id.killed += 1
				d.boss_summary.n_killed += 1
				var spawn_ms: int = int(be.get("spawn_t_ms", -1))
				var end_ms: int = int(be.get("end_t_ms", -1))
				if spawn_ms >= 0 and end_ms >= spawn_ms:
					boss_ttk_sum += float(end_ms - spawn_ms) / 1000.0
					boss_ttk_n += 1
			else:
				by_id.leaked += 1
			d.boss_summary.by_id[bid] = by_id
		var casts: Dictionary = r.get("skill_casts", {})
		for k in casts.keys():
			skill_cast_acc[k] = int(skill_cast_acc.get(k, 0)) + int(casts[k])
		var events: Array = r.get("tower_events", [])
		for ev in events:
			var kind: String = String(ev.get("type", ""))
			if d.tower_events_kinds.has(kind):
				d.tower_events_kinds[kind] = int(d.tower_events_kinds[kind]) + 1
		_inc(d.defeat_reasons, String(r.get("defeat_reason", "")))
		_inc(d.final_wave_dist, String(r.get("final_wave_reached", 0)))
		d.avg_game_speed += float(r.get("game_speed", 1.0))
		var trs: Array = r.get("tower_runtime_stats", [])
		for ts in trs:
			_tower_eff_acc(d.tower_efficiency, ts)
	d.win_pct = (float(d.victories) / float(filtered.size())) * 100.0
	d.avg_duration_s = dur_sum / float(filtered.size())
	d.avg_final_gold = gold_sum / float(filtered.size())
	d.avg_early_call_count = ec_sum / float(filtered.size())
	d.peak_concurrent_global_avg = peak_sum / float(filtered.size())
	d.avg_game_speed = float(d.avg_game_speed) / float(filtered.size())
	if boss_ttk_n > 0:
		d.boss_summary.avg_ttk_s = boss_ttk_sum / float(boss_ttk_n)
	if d.boss_summary.n_spawns > 0:
		d.boss_summary.kill_pct = (float(d.boss_summary.n_killed) / float(d.boss_summary.n_spawns)) * 100.0
	# Per-wave medians + leakiest / hardest.
	var max_leak: int = -1
	var max_dmg: float = -1.0
	var wave_keys: Array = per_wave_acc.keys()
	wave_keys.sort()
	for wn in wave_keys:
		var acc: Dictionary = per_wave_acc[wn]
		var leaked_by_id: Dictionary = acc.get("leaked_by_id", {})
		var top_leaked_id: String = ""
		var top_leaked_count: int = 0
		for eid in leaked_by_id.keys():
			if int(leaked_by_id[eid]) > top_leaked_count:
				top_leaked_count = int(leaked_by_id[eid])
				top_leaked_id = eid
		var entry: Dictionary = {
			"wave": wn,
			"n_samples": acc.damage.size(),
			"median_damage": _median(acc.damage),
			"median_clear_s": _median_filtered(acc.clear),
			"median_lives_lost": _median(acc.leak),
			"total_lives_lost": _sum_int(acc.leak),
			"median_peak_wave": _median(acc.peak_wave),
			"median_damage_hero": _median(acc.get("dmg_hero", [])),
			"median_damage_soldiers": _median(acc.get("dmg_soldiers", [])),
			"median_damage_towers": _median(acc.get("dmg_towers", [])),
			"top_leaked_enemy_id": top_leaked_id,
			"top_leaked_count": top_leaked_count,
		}
		d.per_wave.append(entry)
		if entry.total_lives_lost > max_leak:
			max_leak = entry.total_lives_lost
			d.leakiest_wave = wn
		if entry.median_damage > max_dmg:
			max_dmg = entry.median_damage
			d.hardest_wave_by_damage = wn
	# Top skills cast.
	var skill_list: Array = []
	for k in skill_cast_acc.keys():
		skill_list.append({"skill_id": k, "casts": int(skill_cast_acc[k])})
	skill_list.sort_custom(func(a, b): return int(a.casts) > int(b.casts))
	d.skill_casts_top = skill_list
	# Finalize tower_efficiency — emit medians per tower_id.
	var eff_out: Array = []
	var eff_dict: Dictionary = d.tower_efficiency if d.tower_efficiency is Dictionary else {}
	for tid in eff_dict.keys():
		var bucket: Dictionary = eff_dict[tid]
		eff_out.append({
			"tower_id": tid,
			"n_instances": int(bucket.get("n", 0)),
			"median_hits": _median(bucket.get("hits", [])),
			"median_damage": _median(bucket.get("damage", [])),
			"median_lifetime_s": _median(bucket.get("lifetime", [])),
		})
	eff_out.sort_custom(func(a, b): return float(a.median_damage) > float(b.median_damage))
	d.tower_efficiency = eff_out
	return d


# Format a level digest as a human-readable text block.
static func format_level_digest(digest: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Level: %s  (%d runs, %d wins, %d losses, win %.1f%%)" % [
		String(digest.get("level_id", "?")),
		int(digest.get("n_runs", 0)),
		int(digest.get("victories", 0)),
		int(digest.get("defeats", 0)),
		float(digest.get("win_pct", 0.0)),
	])
	lines.append("Avg duration: %.1fs   Avg final gold: %.0f   Avg early-calls: %.1f" % [
		float(digest.get("avg_duration_s", 0.0)),
		float(digest.get("avg_final_gold", 0.0)),
		float(digest.get("avg_early_call_count", 0.0)),
	])
	var lh: Array = digest.get("level_hardness_seen", [])
	if not lh.is_empty():
		lines.append("Authored hardness seen: %s   Target PPT seen: %s" % [
			str(lh), str(digest.get("level_target_ppt_seen", [])),
		])
	lines.append("Peak concurrent enemies (global avg): %.1f" % float(digest.get("peak_concurrent_global_avg", 0.0)))
	lines.append("Hero picks: %s" % _format_dict(digest.get("hero_picks", {})))
	lines.append("Tower picks: %s" % _format_dict(digest.get("tower_picks", {})))
	lines.append("Skill picks: %s" % _format_dict(digest.get("skill_picks", {})))
	lines.append("")
	lines.append("Per-wave medians:")
	lines.append("  W#   dmg     dmg_T   dmg_H   dmg_S   clear_s  leak  peak  top_leak           n")
	for entry in digest.get("per_wave", []):
		var top: String = ""
		var tlc: int = int(entry.get("top_leaked_count", 0))
		if tlc > 0:
			top = "%s×%d" % [String(entry.get("top_leaked_enemy_id", "")), tlc]
		lines.append("  %-4d %-7.0f %-7.0f %-7.0f %-7.0f %-8.1f %-5d %-5d %-18s %d" % [
			int(entry.wave),
			float(entry.median_damage),
			float(entry.get("median_damage_towers", 0.0)),
			float(entry.get("median_damage_hero", 0.0)),
			float(entry.get("median_damage_soldiers", 0.0)),
			float(entry.median_clear_s),
			int(entry.median_lives_lost),
			int(entry.median_peak_wave),
			top,
			int(entry.n_samples),
		])
	lines.append("Leakiest wave: W%d (total %d lives)   Hardest by median damage: W%d" % [
		int(digest.get("leakiest_wave", -1)),
		_leakiest_total(digest),
		int(digest.get("hardest_wave_by_damage", -1)),
	])
	var boss: Dictionary = digest.get("boss_summary", {})
	if int(boss.get("n_spawns", 0)) > 0:
		lines.append("Bosses: %d spawned, %d killed (%.0f%%), avg TTK %.1fs" % [
			int(boss.n_spawns), int(boss.n_killed),
			float(boss.kill_pct), float(boss.avg_ttk_s),
		])
		for bid in boss.get("by_id", {}).keys():
			var b: Dictionary = boss.by_id[bid]
			lines.append("  %s: %d spawns, %d killed, %d leaked" % [
				String(bid), int(b.spawns), int(b.killed), int(b.leaked),
			])
	var casts: Array = digest.get("skill_casts_top", [])
	if not casts.is_empty():
		var top_strs: PackedStringArray = PackedStringArray()
		for c in casts.slice(0, mini(5, casts.size())):
			top_strs.append("%s×%d" % [String(c.skill_id), int(c.casts)])
		lines.append("Top skill casts: %s" % ", ".join(top_strs))
	var tev: Dictionary = digest.get("tower_events_kinds", {})
	lines.append("Tower events: built=%d upgraded=%d branch=%d sold=%d" % [
		int(tev.get("built", 0)), int(tev.get("upgraded", 0)),
		int(tev.get("branch", 0)), int(tev.get("sold", 0)),
	])
	var eff: Array = digest.get("tower_efficiency", [])
	if not eff.is_empty():
		lines.append("Tower efficiency (median per instance):")
		lines.append("  tower_id              n  hits   dmg     lifetime_s")
		for row in eff:
			lines.append("  %-20s  %-2d %-6d %-7.0f %.1f" % [
				String(row.tower_id),
				int(row.n_instances),
				int(row.median_hits),
				float(row.median_damage),
				float(row.median_lifetime_s),
			])
	lines.append("Defeat reasons: %s   Final wave reached: %s   Avg game_speed: %.2f" % [
		_format_dict(digest.get("defeat_reasons", {})),
		_format_dict(digest.get("final_wave_dist", {})),
		float(digest.get("avg_game_speed", 1.0)),
	])
	return "\n".join(lines)


# ---- internal ----

static func _inc(d: Dictionary, key: String) -> void:
	if key.is_empty():
		return
	d[key] = int(d.get(key, 0)) + 1


static func _median(values) -> float:
	var arr: Array = []
	for v in values:
		arr.append(float(v))
	if arr.is_empty():
		return 0.0
	arr.sort()
	var n: int = arr.size()
	if n % 2 == 1:
		return arr[n / 2]
	return (arr[n / 2 - 1] + arr[n / 2]) * 0.5


# Median that ignores sentinel -1 values (clear_time_s uses -1 when unknown).
static func _median_filtered(values) -> float:
	var arr: Array = []
	for v in values:
		var f: float = float(v)
		if f >= 0.0:
			arr.append(f)
	return _median(arr)


static func _sum_int(values) -> int:
	var total: int = 0
	for v in values:
		total += int(v)
	return total


static func _format_dict(d: Dictionary) -> String:
	if d.is_empty():
		return "(none)"
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		parts.append("%s×%d" % [String(k), int(d[k])])
	return ", ".join(parts)


static func _tower_eff_acc(eff, ts: Dictionary) -> void:
	if not eff is Dictionary:
		return
	var tid: String = String(ts.get("tower_id", ""))
	if tid.is_empty():
		return
	var bucket: Dictionary = eff.get(tid, {"n": 0, "hits": [], "damage": [], "lifetime": []})
	bucket.n = int(bucket.get("n", 0)) + 1
	bucket.hits.append(int(ts.get("total_hits", 0)))
	bucket.damage.append(float(ts.get("damage_total", 0.0)))
	bucket.lifetime.append(float(ts.get("lifetime_s", 0.0)))
	eff[tid] = bucket


static func _leakiest_total(digest: Dictionary) -> int:
	var wn: int = int(digest.get("leakiest_wave", -1))
	if wn < 0:
		return 0
	for entry in digest.get("per_wave", []):
		if int(entry.wave) == wn:
			return int(entry.total_lives_lost)
	return 0
