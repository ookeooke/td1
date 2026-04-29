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
	_render_overall(runs)
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
