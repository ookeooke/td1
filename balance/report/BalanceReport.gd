extends Control

# Balance Report — reads user://run_stats.json (via RunStats.get_history),
# rolls up across runs, displays aggregates that drive balance decisions:
#   - Overall: runs, victory rate, avg duration, avg stars
#   - Tower usage: how often each tower is built, avg max level reached
#   - Wave leaks: which wave drains lives most often (the "where do players
#     fail?" question that pure stats files can't answer)
#
# Lives in balance/report/ — entire balance/ folder is stripped at export.
# WorldMap button gates this screen behind OS.is_debug_build().

@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var content_vbox: VBoxContainer = %ContentVBox


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	refresh_button.pressed.connect(_refresh)
	_refresh()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _refresh() -> void:
	for c in content_vbox.get_children():
		c.queue_free()
	var runs: Array = RunStats.get_history()
	if runs.is_empty():
		_add_section("No runs logged yet")
		_add_text("Play a Campaign / Heroic / Iron run to start collecting data.\nTest Range runs are not logged.")
		return
	var ld_index: Dictionary = _load_levels_index()
	_render_overall(runs)
	_render_per_level_health(runs, ld_index)
	_render_tower_meta_per_level(runs)
	_render_gold_pacing(runs, ld_index)
	_render_pair_synergy(runs)
	_render_tower_usage(runs)
	_render_wave_leaks(runs)
	_render_recent_runs(runs)


func _render_overall(runs: Array) -> void:
	_add_section("Overall — %d runs" % runs.size())
	var victories: int = 0
	var defeats: int = 0
	var total_duration: float = 0.0
	var total_stars: int = 0
	var mode_counts: Dictionary = {"campaign": 0, "heroic": 0, "iron": 0, "endless": 0}
	for run in runs:
		var outcome: String = run.get("outcome", "")
		if outcome == "victory":
			victories += 1
		elif outcome == "defeat":
			defeats += 1
		total_duration += float(run.get("duration_s", 0.0))
		total_stars += int(run.get("stars_earned", 0))
		var m: String = run.get("mode", "")
		if mode_counts.has(m):
			mode_counts[m] = int(mode_counts[m]) + 1
	var win_rate: float = 100.0 * float(victories) / float(runs.size())
	var avg_duration: float = total_duration / float(runs.size())
	var avg_stars: float = float(total_stars) / float(runs.size())
	_add_text("Victories: %d (%.0f%%)   Defeats: %d   Avg duration: %.1fs   Avg stars: %.1f" % [
		victories, win_rate, defeats, avg_duration, avg_stars,
	])
	_add_text("By mode: campaign=%d  heroic=%d  iron=%d  endless=%d" % [
		mode_counts.campaign, mode_counts.heroic, mode_counts.iron, mode_counts.endless,
	])


func _render_tower_usage(runs: Array) -> void:
	_add_section("Tower usage (%d runs)" % runs.size())
	# tower_id -> {built: int, runs_with: int, max_level_sum: int, branch_counts: {-1, 0, 1}}
	var stats: Dictionary = {}
	for run in runs:
		var seen_in_run: Dictionary = {}
		for placement in run.get("tower_placements", []):
			var tid: String = placement.get("id", "")
			if tid == "":
				continue
			if not stats.has(tid):
				stats[tid] = {
					"built": 0, "runs_with": 0, "max_level_sum": 0,
					"branch_main": 0, "branch_a": 0, "branch_b": 0,
				}
			stats[tid]["built"] = int(stats[tid]["built"]) + 1
			stats[tid]["max_level_sum"] = int(stats[tid]["max_level_sum"]) + int(placement.get("max_level", 1))
			match int(placement.get("branch", -1)):
				-1: stats[tid]["branch_main"] = int(stats[tid]["branch_main"]) + 1
				0: stats[tid]["branch_a"] = int(stats[tid]["branch_a"]) + 1
				1: stats[tid]["branch_b"] = int(stats[tid]["branch_b"]) + 1
			seen_in_run[tid] = true
		for tid in seen_in_run:
			stats[tid]["runs_with"] = int(stats[tid]["runs_with"]) + 1
	if stats.is_empty():
		_add_text("(no towers placed in any logged run)")
		return
	# Sort by total built desc.
	var ids: Array = stats.keys()
	ids.sort_custom(func(a, b): return int(stats[a]["built"]) > int(stats[b]["built"]))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.set("theme_override_constants/h_separation", 24)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, ["Tower", "Built", "% runs", "Avg max lvl", "Branch (M/A/B)"])
	for tid in ids:
		var s: Dictionary = stats[tid]
		var built: int = int(s["built"])
		var runs_with: int = int(s["runs_with"])
		var pct: float = 100.0 * float(runs_with) / float(runs.size())
		var avg_lvl: float = float(s["max_level_sum"]) / float(max(1, built))
		var name: String = _pretty_tower_name(tid)
		var branch_str: String = "%d/%d/%d" % [int(s["branch_main"]), int(s["branch_a"]), int(s["branch_b"])]
		_grid_row(grid, [name, str(built), "%.0f%%" % pct, "%.1f" % avg_lvl, branch_str])
	content_vbox.add_child(grid)


func _render_wave_leaks(runs: Array) -> void:
	_add_section("Lives lost per wave")
	# wave_idx (0-based) -> total leaks across all runs
	var leaks_by_wave: Dictionary = {}
	var max_wave: int = 0
	for run in runs:
		var arr: Array = run.get("lives_lost_per_wave", [])
		for i in range(arr.size()):
			leaks_by_wave[i] = int(leaks_by_wave.get(i, 0)) + int(arr[i])
			if i + 1 > max_wave:
				max_wave = i + 1
	if max_wave == 0:
		_add_text("(no waves recorded)")
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set("theme_override_constants/h_separation", 24)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, ["Wave", "Total leaks", "Avg per run"])
	for i in range(max_wave):
		var total: int = int(leaks_by_wave.get(i, 0))
		var avg: float = float(total) / float(runs.size())
		_grid_row(grid, ["W%d" % (i + 1), str(total), "%.2f" % avg])
	content_vbox.add_child(grid)


func _render_recent_runs(runs: Array) -> void:
	_add_section("Recent runs (last 10)")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.set("theme_override_constants/h_separation", 18)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, ["When", "Level", "Mode", "Outcome", "★", "Dur"])
	# runs is oldest→newest in the file; show last 10 newest first.
	var start: int = max(0, runs.size() - 10)
	for i in range(runs.size() - 1, start - 1, -1):
		var r: Dictionary = runs[i]
		_grid_row(grid, [
			String(r.get("timestamp", "")).substr(11, 5),
			String(r.get("level_id", "?")),
			String(r.get("mode", "?")),
			String(r.get("outcome", "?")),
			str(int(r.get("stars_earned", 0))),
			"%.0fs" % float(r.get("duration_s", 0.0)),
		])
	content_vbox.add_child(grid)


# --- New balance-loop sections (per-level health, tower meta, gold pacing) ---

# Loads level_list.tres into a {level_id: LevelNodeData} map so the report
# can compare per-run actuals against authored targets. Returns empty dict
# if the registry isn't reachable — sections gate on that.
func _load_levels_index() -> Dictionary:
	var out: Dictionary = {}
	var registry: Resource = load("res://ui/world_map/level_list.tres")
	if registry == null:
		return out
	var levels: Array = registry.levels
	for entry in levels:
		if entry is LevelNodeData and entry.level_id != "":
			out[entry.level_id] = entry
	return out


# Groups runs by level_id, preserving insertion order (oldest first).
func _group_runs_by_level(runs: Array) -> Dictionary:
	var out: Dictionary = {}
	for run in runs:
		var lid: String = String(run.get("level_id", ""))
		if lid == "":
			continue
		if not out.has(lid):
			out[lid] = []
		out[lid].append(run)
	return out


# Per-level health table — one row per level with ≥3 logged runs. Surfaces
# the headline diagnostic: are players clearing the level, where do they
# leak, what carries, and how does spending compare to the authored budget.
# Flags fire when BALANCE.md bands are violated.
func _render_per_level_health(runs: Array, ld_index: Dictionary) -> void:
	_add_section("Per-level health")
	var by_level: Dictionary = _group_runs_by_level(runs)
	if by_level.is_empty():
		_add_text("(no runs with level_id recorded)")
		return
	# Stable level order: follow level_list.tres order if available, else alphabetical.
	var ordered_ids: Array = ld_index.keys() if not ld_index.is_empty() else by_level.keys()
	if ld_index.is_empty():
		ordered_ids.sort()
	var grid := GridContainer.new()
	grid.columns = 11
	grid.set("theme_override_constants/h_separation", 18)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, ["Level", "Runs", "Win%", "Avg★", "Avg dur", "Climax leak", "Spend%", "Sells", "Early$", "Top tower", "Flags"])
	var rendered: int = 0
	for lid in ordered_ids:
		if not by_level.has(lid):
			continue
		var level_runs: Array = by_level[lid]
		if level_runs.size() < 3:
			continue
		rendered += 1
		var ld: LevelNodeData = ld_index.get(lid, null)
		var level_name: String = ld.display_name if ld != null else lid
		var n: int = level_runs.size()
		var victories: int = 0
		var stars_sum: int = 0
		var climax_leaks_sum: int = 0
		var spend_pct_sum: float = 0.0
		var spend_pct_n: int = 0
		var sells_sum: int = 0
		var early_call_gold_sum: int = 0
		var duration_sum: float = 0.0
		var dmg_share_by_tower: Dictionary = {}  # tower_name -> avg fraction across runs
		var dmg_share_runs: int = 0
		for run in level_runs:
			if String(run.get("outcome", "")) == "victory":
				victories += 1
			stars_sum += int(run.get("stars_earned", 0))
			sells_sum += int(run.get("tower_sells", 0))
			early_call_gold_sum += int(run.get("early_call_gold_earned", 0))
			duration_sum += float(run.get("duration_s", 0.0))
			# Climax = last authored wave. Use leaks array length as the wave
			# count — gold_timeline lengths can lag if a run defeated mid-wave.
			var leaks: Array = run.get("lives_lost_per_wave", [])
			if leaks.size() > 0:
				climax_leaks_sum += int(leaks[leaks.size() - 1])
			# Spend% = (start + earned - final) / budget. Without an explicit
			# earnings track, approximate with (final_gold - starting_gold +
			# wave_bounties+kill_gold). Use available proxy: starting_gold +
			# (sum of leaks penalty) — too noisy. Fall back to: 1 - final/budget.
			# Simpler proxy: final_gold / gold_budget_total. Lower = more spent.
			# This is "leftover ratio" — invert for display.
			if ld != null and ld.gold_budget_total > 0:
				var leftover: float = float(run.get("final_gold", 0)) / float(ld.gold_budget_total)
				spend_pct_sum += clampf(1.0 - leftover, 0.0, 1.0) * 100.0
				spend_pct_n += 1
			# Damage share per tower (avg of per-run shares, not sum-then-divide
			# so a single 1000-damage run doesn't dwarf a string of 100s).
			var tot: float = float(run.get("damage_by_source", {}).get("towers_total", 0.0))
			if tot > 0.0:
				dmg_share_runs += 1
				for ent in run.get("damage_by_tower", []):
					var nm: String = String(ent.get("name", ""))
					if nm == "":
						continue
					var share: float = float(ent.get("damage", 0.0)) / tot
					dmg_share_by_tower[nm] = float(dmg_share_by_tower.get(nm, 0.0)) + share
		var win_pct: float = 100.0 * float(victories) / float(n)
		var avg_stars: float = float(stars_sum) / float(n)
		var avg_climax_leak: float = float(climax_leaks_sum) / float(n)
		var avg_spend_pct: float = (spend_pct_sum / float(spend_pct_n)) if spend_pct_n > 0 else -1.0
		var avg_sells: float = float(sells_sum) / float(n)
		var avg_early_gold: float = float(early_call_gold_sum) / float(n)
		var avg_duration: float = duration_sum / float(n)
		var top_name: String = "—"
		var top_share: float = 0.0
		for nm in dmg_share_by_tower.keys():
			var s: float = float(dmg_share_by_tower[nm]) / float(max(1, dmg_share_runs))
			if s > top_share:
				top_share = s
				top_name = "%s %.0f%%" % [nm, s * 100.0]
		# Flags. Per BALANCE.md authoring workflow: spend 70-90% of budget,
		# top tower < 60% domination band. Naked Baseline must 1-star — we
		# can't detect Naked Baseline runs without loadout data on the run
		# record, so just flag <60% win rate as "level may be over-tuned".
		var flags: Array[String] = []
		if win_pct < 60.0:
			flags.append("hard")
		if top_share > 0.60:
			flags.append("dom %.0f%%" % (top_share * 100.0))
		if avg_spend_pct >= 0.0 and (avg_spend_pct < 50.0 or avg_spend_pct > 95.0):
			flags.append("spend%.0f" % avg_spend_pct)
		# >5 sells/run is the "build → ult → sell → rebuild" cycle that BALANCE
		# can't price properly even with a 50% sell tax. Surface it; only flag
		# if it's persistent (not a single salty playtest).
		if avg_sells > 5.0:
			flags.append("sells %.1f" % avg_sells)
		# 10-minute rule (BALANCE.md, L4+ only). L1-L3 are grandfathered at
		# their original 4-5 min design and skip the duration flag — column
		# stays informational.
		if ld != null and ld.unlock_order >= 4 and ld.target_duration_sec > 0.0:
			var dur_drift_pct: float = (avg_duration - ld.target_duration_sec) / ld.target_duration_sec * 100.0
			if absf(dur_drift_pct) > 25.0:
				flags.append("dur %+.0f%%" % dur_drift_pct)
		var flag_str: String = ("⚠ " + ", ".join(flags)) if flags.size() > 0 else "✓"
		var spend_str: String = ("%.0f%%" % avg_spend_pct) if avg_spend_pct >= 0.0 else "—"
		_grid_row(grid, [
			level_name, str(n), "%.0f%%" % win_pct, "%.1f" % avg_stars,
			"%.0fs" % avg_duration,
			"%.1f" % avg_climax_leak, spend_str,
			"%.1f" % avg_sells, "%.0f" % avg_early_gold,
			top_name, flag_str,
		])
	if rendered == 0:
		_add_text("(no level has ≥3 logged runs yet — keep playing)")
		return
	content_vbox.add_child(grid)


# Tower meta — last 10 runs per level. Domination check (BALANCE.md healthy
# band: top combo < 40% of top-100; we proxy that as pick% < 60% across the
# recent cohort) and branch split per tower.
func _render_tower_meta_per_level(runs: Array) -> void:
	_add_section("Tower meta — last 10 runs per level")
	var by_level: Dictionary = _group_runs_by_level(runs)
	if by_level.is_empty():
		_add_text("(no runs with level_id recorded)")
		return
	var ordered_ids: Array = by_level.keys()
	ordered_ids.sort()
	var rendered: int = 0
	for lid in ordered_ids:
		var level_runs: Array = by_level[lid]
		var start: int = max(0, level_runs.size() - 10)
		var recent: Array = level_runs.slice(start, level_runs.size())
		if recent.size() < 3:
			continue
		rendered += 1
		var sub: Label = Label.new()
		sub.text = "  %s — last %d runs" % [lid, recent.size()]
		sub.set("theme_override_font_sizes/font_size", 16)
		sub.modulate = Color(0.85, 0.85, 0.95)
		content_vbox.add_child(sub)
		# tid -> {runs_with, branch_main, branch_a, branch_b, dmg_share_sum, dmg_runs}
		var stats: Dictionary = {}
		for run in recent:
			var seen: Dictionary = {}
			for placement in run.get("tower_placements", []):
				var tid: String = placement.get("id", "")
				if tid == "":
					continue
				if not stats.has(tid):
					stats[tid] = {
						"runs_with": 0, "branch_main": 0, "branch_a": 0, "branch_b": 0,
						"dmg_share_sum": 0.0, "dmg_runs": 0,
					}
				match int(placement.get("branch", -1)):
					-1: stats[tid]["branch_main"] = int(stats[tid]["branch_main"]) + 1
					0: stats[tid]["branch_a"] = int(stats[tid]["branch_a"]) + 1
					1: stats[tid]["branch_b"] = int(stats[tid]["branch_b"]) + 1
				seen[tid] = true
			for tid in seen:
				stats[tid]["runs_with"] = int(stats[tid]["runs_with"]) + 1
			# Damage share per tower this run. Map tower name → tid via best effort
			# (tower_name comparison) since damage records are keyed by display name.
			var tot: float = float(run.get("damage_by_source", {}).get("towers_total", 0.0))
			if tot <= 0.0:
				continue
			for ent in run.get("damage_by_tower", []):
				var nm: String = String(ent.get("name", ""))
				var matched: String = _tower_id_for_name(nm)
				if matched == "" or not stats.has(matched):
					continue
				var share: float = float(ent.get("damage", 0.0)) / tot
				stats[matched]["dmg_share_sum"] = float(stats[matched]["dmg_share_sum"]) + share
				stats[matched]["dmg_runs"] = int(stats[matched]["dmg_runs"]) + 1
		if stats.is_empty():
			_add_text("    (no tower placements in recent runs)")
			continue
		var ids: Array = stats.keys()
		ids.sort_custom(func(a, b): return int(stats[a]["runs_with"]) > int(stats[b]["runs_with"]))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.set("theme_override_constants/h_separation", 18)
		grid.set("theme_override_constants/v_separation", 4)
		_grid_header(grid, ["Tower", "Pick%", "Branch (M/A/B)", "Avg dmg share", "Flags"])
		for tid in ids:
			var s: Dictionary = stats[tid]
			var pick_pct: float = 100.0 * float(s["runs_with"]) / float(recent.size())
			var dmg_share: float = float(s["dmg_share_sum"]) / float(max(1, int(s["dmg_runs"])))
			var branch_str: String = "%d/%d/%d" % [int(s["branch_main"]), int(s["branch_a"]), int(s["branch_b"])]
			var flags: Array[String] = []
			if pick_pct > 60.0:
				flags.append("dom")
			elif pick_pct < 20.0 and recent.size() >= 5:
				flags.append("unused")
			var flag_str: String = ("⚠ " + ", ".join(flags)) if flags.size() > 0 else ""
			var dmg_str: String = ("%.0f%%" % (dmg_share * 100.0)) if int(s["dmg_runs"]) > 0 else "—"
			_grid_row(grid, [_pretty_tower_name(tid), "%.0f%%" % pick_pct, branch_str, dmg_str, flag_str])
		content_vbox.add_child(grid)
	if rendered == 0:
		_add_text("(no level has ≥3 recent runs)")


# Per-wave gold pacing — actual avg start_gold per wave vs the authored
# cumulative income curve from BALANCE.md (wave_gold_shares × budget). Drift
# > ±25% flags retune. Limited to last 10 runs per level for recency.
func _render_gold_pacing(runs: Array, ld_index: Dictionary) -> void:
	_add_section("Per-wave gold pacing — last 10 runs per level")
	if ld_index.is_empty():
		_add_text("(level_list.tres unavailable — skipping)")
		return
	var by_level: Dictionary = _group_runs_by_level(runs)
	var ordered_ids: Array = ld_index.keys()
	var rendered: int = 0
	for lid in ordered_ids:
		if not by_level.has(lid):
			continue
		var level_runs: Array = by_level[lid]
		var start_idx: int = max(0, level_runs.size() - 10)
		var recent: Array = level_runs.slice(start_idx, level_runs.size())
		if recent.size() < 3:
			continue
		var ld: LevelNodeData = ld_index[lid]
		if ld.gold_budget_total <= 0 or ld.wave_gold_shares.is_empty():
			continue
		rendered += 1
		var sub := Label.new()
		sub.text = "  %s — last %d runs (budget %dg)" % [ld.display_name, recent.size(), ld.gold_budget_total]
		sub.set("theme_override_font_sizes/font_size", 16)
		sub.modulate = Color(0.85, 0.85, 0.95)
		content_vbox.add_child(sub)
		# Avg start_gold per wave across recent runs.
		var sum_by_wave: Dictionary = {}
		var n_by_wave: Dictionary = {}
		var starting_gold_sum: int = 0
		for run in recent:
			starting_gold_sum += int(run.get("starting_gold", 0))
			for entry in run.get("gold_timeline", []):
				var w: int = int(entry.get("wave", -1))
				if w <= 0:
					continue
				sum_by_wave[w] = int(sum_by_wave.get(w, 0)) + int(entry.get("start_gold", 0))
				n_by_wave[w] = int(n_by_wave.get(w, 0)) + 1
		var avg_starting: float = float(starting_gold_sum) / float(recent.size())
		var grid := GridContainer.new()
		grid.columns = 4
		grid.set("theme_override_constants/h_separation", 18)
		grid.set("theme_override_constants/v_separation", 4)
		_grid_header(grid, ["Wave", "Avg start gold", "Target", "Drift"])
		# Target start_gold of wave N = starting_gold + Σ shares[0..N-2] × budget.
		# Wave 1 target == starting gold (no income yet).
		var cumul_share: float = 0.0
		for i in range(ld.wave_gold_shares.size()):
			var wave_num: int = i + 1
			var target: float = avg_starting + cumul_share * float(ld.gold_budget_total)
			var avg_actual: float = -1.0
			if n_by_wave.has(wave_num):
				avg_actual = float(sum_by_wave[wave_num]) / float(n_by_wave[wave_num])
			var drift_str: String = "—"
			if avg_actual >= 0.0 and target > 0.0:
				var drift_pct: float = (avg_actual - target) / target * 100.0
				var marker: String = ""
				if absf(drift_pct) > 25.0:
					marker = " ⚠"
				drift_str = "%+.0f%%%s" % [drift_pct, marker]
			var actual_str: String = ("%.0f" % avg_actual) if avg_actual >= 0.0 else "—"
			_grid_row(grid, ["W%d" % wave_num, actual_str, "%.0f" % target, drift_str])
			# Advance cumulative share for next wave's target.
			cumul_share += float(ld.wave_gold_shares[i])
		content_vbox.add_child(grid)
	if rendered == 0:
		_add_text("(no level has ≥3 recent runs with budget data)")


# Tower pair synergy — flags pairs that disproportionately appear in
# zero-leak victories. The "Ice + Artillery" canary from BALANCE.md.
#
# Method: pair_zero_leak_rate / baseline_zero_leak_rate = "lift". Lift > 1.5
# with co_occur >= 3 = synergy worth investigating. Two-tower only — three-
# way combos are detectable with current data but the combinatorial bloat
# isn't worth it at 50-run cap. Bumps to N-way later if the cap raises.
#
# Limitations: doesn't account for level (a pair that only co-occurs on L4
# is over-weighted by L4's outcome distribution). Cross-level lift still
# surfaces the canary; per-level synergy is a future refinement if any
# pair lifts > 2.0 and you want to drill in.
func _render_pair_synergy(runs: Array) -> void:
	_add_section("Tower pair synergy")
	if runs.size() < 5:
		_add_text("(need ≥5 runs to compute meaningful synergy lift — keep playing)")
		return
	# Baseline: across all runs, what fraction are zero-leak victories?
	var total_runs: int = runs.size()
	var zero_leak_runs: int = 0
	for run in runs:
		if _is_zero_leak_victory(run):
			zero_leak_runs += 1
	if zero_leak_runs == 0:
		_add_text("(no zero-leak victories yet — synergy lift undefined)")
		return
	var baseline: float = float(zero_leak_runs) / float(total_runs)
	_add_text("Baseline zero-leak rate across %d runs: %.0f%%" % [total_runs, baseline * 100.0])
	# Pair tallies. Key = "tid_a|tid_b" with a < b alphabetically (unordered).
	var pair_co: Dictionary = {}        # pair_key → int
	var pair_zero_leak: Dictionary = {} # pair_key → int
	for run in runs:
		var ids: Array = _unique_tower_ids(run)
		if ids.size() < 2:
			continue
		var is_clean: bool = _is_zero_leak_victory(run)
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				var a: String = String(ids[i])
				var b: String = String(ids[j])
				var key: String = (a + "|" + b) if a < b else (b + "|" + a)
				pair_co[key] = int(pair_co.get(key, 0)) + 1
				if is_clean:
					pair_zero_leak[key] = int(pair_zero_leak.get(key, 0)) + 1
	if pair_co.is_empty():
		_add_text("(no run had ≥2 distinct towers built)")
		return
	# Compute lift; keep pairs with co_occur >= 3 to filter noise.
	var rows: Array = []
	for key in pair_co.keys():
		var co: int = int(pair_co[key])
		if co < 3:
			continue
		var zl: int = int(pair_zero_leak.get(key, 0))
		var pair_rate: float = float(zl) / float(co)
		var lift: float = pair_rate / baseline if baseline > 0.0 else 0.0
		var parts: PackedStringArray = key.split("|")
		var a: String = String(parts[0]) if parts.size() > 0 else ""
		var b: String = String(parts[1]) if parts.size() > 1 else ""
		rows.append({
			"a": _pretty_tower_name(a), "b": _pretty_tower_name(b),
			"co": co, "zl": zl, "rate": pair_rate, "lift": lift,
		})
	if rows.is_empty():
		_add_text("(no pair has ≥3 co-occurrences yet)")
		return
	rows.sort_custom(func(x, y): return float(x["lift"]) > float(y["lift"]))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.set("theme_override_constants/h_separation", 18)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, ["Tower A", "Tower B", "Co-runs", "Zero-leak", "Pair rate", "Lift"])
	# Show top 10 by lift.
	var shown: int = 0
	for r in rows:
		if shown >= 10:
			break
		shown += 1
		var lift_val: float = float(r["lift"])
		var marker: String = ""
		if lift_val > 1.5:
			marker = " ⚠"
		_grid_row(grid, [
			String(r["a"]), String(r["b"]),
			str(int(r["co"])), str(int(r["zl"])),
			"%.0f%%" % (float(r["rate"]) * 100.0),
			"%.2f×%s" % [lift_val, marker],
		])
	content_vbox.add_child(grid)


# A run counts as zero-leak only if it's a victory AND every recorded wave
# had zero leaked enemies. Defeats and partial-clear runs don't qualify
# even if they happen to leak 0 (e.g. died to overrun before leaking).
func _is_zero_leak_victory(run: Dictionary) -> bool:
	if String(run.get("outcome", "")) != "victory":
		return false
	var leaks: Array = run.get("lives_lost_per_wave", [])
	if leaks.is_empty():
		return false
	for v in leaks:
		if int(v) > 0:
			return false
	return true


# Distinct tower_ids built in a run. Multiple placements of the same tower
# count once — synergy is about which combinations of types were used.
func _unique_tower_ids(run: Dictionary) -> Array:
	var seen: Dictionary = {}
	for placement in run.get("tower_placements", []):
		var tid: String = String(placement.get("id", ""))
		if tid != "":
			seen[tid] = true
	return seen.keys()


# Reverse lookup: tower display name → tower_id, via ContentRegistry. Used
# in tower-meta to align damage records (keyed by name) with placements
# (keyed by id). Returns "" if no tower matches.
func _tower_id_for_name(display_name: String) -> String:
	if display_name == "" or ContentRegistry == null:
		return ""
	for t in ContentRegistry.towers:
		if t is TowerData and String(t.tower_name) == display_name:
			return String(t.tower_id)
	return ""


# --- UI helpers ---

func _add_section(title: String) -> void:
	var l := Label.new()
	l.text = title
	l.set("theme_override_font_sizes/font_size", 22)
	l.modulate = Color(1.0, 0.9, 0.5)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	content_vbox.add_child(spacer)
	content_vbox.add_child(l)


func _add_text(s: String) -> void:
	var l := Label.new()
	l.text = s
	l.set("theme_override_font_sizes/font_size", 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(l)


func _grid_header(grid: GridContainer, cells: Array) -> void:
	for c in cells:
		var l := Label.new()
		l.text = String(c)
		l.set("theme_override_font_sizes/font_size", 14)
		l.modulate = Color(0.7, 0.85, 1.0)
		grid.add_child(l)


func _grid_row(grid: GridContainer, cells: Array) -> void:
	for c in cells:
		var l := Label.new()
		l.text = String(c)
		l.set("theme_override_font_sizes/font_size", 16)
		grid.add_child(l)


func _pretty_tower_name(tid: String) -> String:
	var d: Resource = ContentRegistry.find_tower(tid)
	if d != null and "tower_name" in d:
		return d.tower_name
	return tid
