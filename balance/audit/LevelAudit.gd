extends Control

# Cross-level hardness audit — shows every level side by side with target
# PPT band, drift vs PPT_TO_HARDNESS_FACTOR × target_ppt, and gold/damage
# stinginess. Pure read of authored data — no .tres edits, no save reads.
#
# Reachable from WorldMap when OS.is_debug_build() is true. See
# balance/BALANCE.md "Player Power Tier (PPT)".

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
	var levels: Array = ContentRegistry.levels
	if levels.is_empty():
		_add_section("ContentRegistry has no levels (check level_list.tres)")
		return
	_render_legend()
	_render_levels_table(levels)
	_render_loadout_summary()


func _render_legend() -> void:
	_add_section("Legend")
	_add_text(
		"Drift = (actual hardness − target_ppt × %d) / (target_ppt × %d) × 100. " % [
			int(BalanceCalculator.PPT_TO_HARDNESS_FACTOR), int(BalanceCalculator.PPT_TO_HARDNESS_FACTOR),
		]
		+ "Green |drift| < 15%; yellow 15–25%; red > 25%. "
		+ "Gold/Dmg = gold_budget_total / level_required_damage. "
		+ "Bands: < 0.10 brutal, 0.10–0.15 tight, 0.15–0.25 healthy, > 0.25 generous."
	)


func _render_levels_table(levels: Array) -> void:
	_add_section("Per-level audit (%d levels)" % levels.size())
	# Sort by unlock_order ascending — campaign sequence
	var sorted_levels: Array = levels.duplicate()
	sorted_levels.sort_custom(func(a, b):
		var ao: int = int(a.unlock_order) if a != null and "unlock_order" in a else 0
		var bo: int = int(b.unlock_order) if b != null and "unlock_order" in b else 0
		return ao < bo)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.set("theme_override_constants/h_separation", 18)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, [
		"Level", "Hardness", "Tier", "Target PPT", "Min PPT", "Drift", "Gold/Dmg", "Notes",
	])
	for lvl in sorted_levels:
		_render_level_row(grid, lvl)
	content_vbox.add_child(grid)


func _render_level_row(grid: GridContainer, level_data: Resource) -> void:
	if level_data == null:
		return
	var lvl_name: String = level_data.display_name if "display_name" in level_data else "?"
	var target_ppt: int = int(level_data.target_ppt) if "target_ppt" in level_data else 0
	var min_ppt: int = int(level_data.min_ppt) if "min_ppt" in level_data else 0
	var wave_path: String = level_data.wave_list_path if "wave_list_path" in level_data else ""
	var wave_list: Resource = load(wave_path) if wave_path != "" else null
	if wave_list == null:
		_grid_row(grid, [
			name, "?", "?", str(target_ppt), str(min_ppt), "?", "?",
			"waves missing: " + wave_path,
		])
		return
	var hardness: float = BalanceCalculator.score_level(wave_list, 100)
	var tier: String = BalanceCalculator.tier_for_score(hardness)
	var drift: float = BalanceCalculator.score_for_ppt(wave_list, target_ppt, 100) if target_ppt > 0 else 0.0
	var req_dmg: float = BalanceCalculator.level_required_damage(wave_list)
	var gold_total: int = int(level_data.gold_budget_total) if "gold_budget_total" in level_data else 0
	var gpd: float = (float(gold_total) / req_dmg) if req_dmg > 0.0 else 0.0
	# Warnings — pull from per-wave pressure report when available
	var warnings: Array = []
	if "wave_pressure_targets" in level_data:
		var report: Dictionary = BalanceCalculator.level_pressure_report(wave_list, level_data, 100)
		warnings = report.get("warnings", [])
	var notes: String = "; ".join(warnings) if not warnings.is_empty() else "—"
	# Fill cells with appropriate coloring
	_grid_cell(grid, lvl_name)
	_grid_cell(grid, "%d" % int(round(hardness)))
	_grid_cell(grid, tier)
	_grid_cell(grid, str(target_ppt))
	_grid_cell(grid, str(min_ppt))
	_grid_cell(grid, "%+.0f%%" % drift, _drift_color(drift))
	_grid_cell(grid, "%.2f" % gpd, _gpd_color(gpd))
	_grid_cell(grid, notes)


func _drift_color(drift: float) -> Color:
	var d: float = absf(drift)
	if d < 15.0:
		return Color(0.5, 0.95, 0.5)   # green
	if d < 25.0:
		return Color(0.95, 0.85, 0.4)  # yellow
	return Color(0.95, 0.45, 0.45)     # red


func _gpd_color(gpd: float) -> Color:
	if gpd < 0.10 or gpd > 0.30:
		return Color(0.95, 0.45, 0.45)  # brutal or trivial
	if gpd >= 0.15 and gpd <= 0.25:
		return Color(0.5, 0.95, 0.5)    # healthy
	return Color(0.95, 0.85, 0.4)       # tight or slightly generous


func _render_loadout_summary() -> void:
	_add_section("Current loadout PPT")
	var ppt: float = LoadoutState.get_effective_ppt() if LoadoutState.has_method("get_effective_ppt") else 0.0
	_add_text(
		"Effective PPT = %.2f   (hero=%s, towers=%d, equipped skills slots=%d)" % [
			ppt,
			LoadoutState.selected_hero_id,
			LoadoutState.selected_tower_ids.size(),
			LoadoutState.get_active_slot_cap(LoadoutState.selected_hero_id),
		]
	)
	_add_text(
		"Adjust target_ppt on each LevelNodeData (in level_list.tres) to band the audit drift correctly. "
		+ "Naked Baseline target ≈ 1.0; mid-campaign 2–4; endgame 5+."
	)


# --- UI helpers (mirror BalanceReport.gd pattern) -------------------------

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
		_grid_cell(grid, String(c))


func _grid_cell(grid: GridContainer, text: String, color: Color = Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.set("theme_override_font_sizes/font_size", 16)
	if color != Color.WHITE:
		l.modulate = color
	grid.add_child(l)
