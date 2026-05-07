extends Control

# Supply vs Demand report — two-number balance dashboard.
#
# Headline: per level, player_supply vs level_demand → safety_ratio (color-
# banded). Drill-down: demand vector (flying/armored/magic-resist/boss/swarm/
# rush), supply vector (per-segment), bottleneck label, predicted-vs-observed
# from RunStats. Weight sliders at the bottom let designers tune the model
# live and see the table redraw immediately.
#
# Reachable from WorldMap when OS.is_debug_build() is true. See
# balance/BALANCE.md "Supply vs Demand".


const _CONFIG_PATH: String = "res://balance/balance_model_config.tres"

@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var save_button: Button = %SaveButton
@onready var content_vbox: VBoxContainer = %ContentVBox
@onready var slider_vbox: VBoxContainer = %SliderVBox

# Live config — loaded from .tres at boot, mutated by sliders, optionally
# saved back to disk via the Save button.
var _config: BalanceModelConfig
# Cached references to the sliders we built so refresh can read values.
var _slider_refs: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	refresh_button.pressed.connect(_refresh)
	save_button.pressed.connect(_on_save)
	_config = load(_CONFIG_PATH) as BalanceModelConfig
	if _config == null:
		_config = BalanceModelConfig.defaults()
	_build_sliders()
	_refresh()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_save() -> void:
	# Save current config state back to the .tres so values persist across
	# sessions. Debug-only — no-op in shipped builds (button is hidden).
	if _config == null:
		return
	var err: int = ResourceSaver.save(_config, _CONFIG_PATH)
	if err == OK:
		save_button.text = "Saved ✓"
	else:
		save_button.text = "Save FAILED (%d)" % err


func _refresh() -> void:
	for c in content_vbox.get_children():
		c.queue_free()
	var levels: Array = ContentRegistry.levels
	if levels.is_empty():
		_add_section("ContentRegistry has no levels (check level_list.tres)")
		return
	_render_legend()
	_render_levels_table(levels)
	_render_per_level_breakdowns(levels)


# ── Legend ───────────────────────────────────────────────────────────────
func _render_legend() -> void:
	_add_section("Legend")
	var c: BalanceModelConfig = _config
	_add_text(
		"safety_ratio = total_supply / total_demand. Bands: "
		+ "red < %.2f, orange < %.2f, green < %.2f, blue < %.2f, grey ≥ %.2f. " % [
			c.safety_ratio_red_max, c.safety_ratio_orange_max,
			c.safety_ratio_green_max, c.safety_ratio_blue_max,
			c.safety_ratio_blue_max,
		]
		+ "Sub-ratios identify the bottleneck (the axis where the player struggles). "
		+ "Predicted vs observed compares safety to RunStats win% and avg leaks "
		+ "across recent runs of the same level."
	)
	_add_text(
		"All weights default to 1.0 — never invent numbers; move them only "
		+ "when run-stats drift on ≥3 levels in the same direction. See "
		+ "balance/BALANCE.md 'Supply vs Demand'."
	)


# ── Top-level table ──────────────────────────────────────────────────────
func _render_levels_table(levels: Array) -> void:
	_add_section("Per-level Supply / Demand (%d levels)" % levels.size())
	var sorted_levels: Array = levels.duplicate()
	sorted_levels.sort_custom(func(a, b):
		var ao: int = int(a.unlock_order) if a != null and "unlock_order" in a else 0
		var bo: int = int(b.unlock_order) if b != null and "unlock_order" in b else 0
		return ao < bo)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.set("theme_override_constants/h_separation", 16)
	grid.set("theme_override_constants/v_separation", 4)
	_grid_header(grid, [
		"Level", "Supply", "Demand", "Safety", "Bottleneck",
		"Spike Wave", "Win%", "Avg Leaks", "Drift",
	])
	var history: Array = RunStats.get_history()
	for lvl in sorted_levels:
		_render_level_row(grid, lvl, history)
	content_vbox.add_child(grid)


func _render_level_row(grid: GridContainer, level_data: Resource, history: Array) -> void:
	if level_data == null:
		return
	var lvl_name: String = level_data.display_name if "display_name" in level_data else "?"
	var wave_path: String = level_data.wave_list_path if "wave_list_path" in level_data else ""
	var wave_list: Resource = load(wave_path) if wave_path != "" else null
	if wave_list == null:
		_grid_row(grid, [lvl_name, "?", "?", "?", "—", "—", "—", "—", "waves missing"])
		return
	var loadout: Array = LoadoutState.get_loadout_towers()
	var hero: HeroData = ContentRegistry.find_hero(LoadoutState.selected_hero_id) as HeroData
	var equipped_skills: Array = _resolve_equipped_skills(hero)
	var rep: Dictionary = BalanceCalculator.supply_demand_report(
		level_data, wave_list, loadout, hero, equipped_skills, _config)
	var safety: float = float(rep.get("safety_ratio", 0.0))
	var supply: float = float(rep.get("total_supply", 0.0))
	var demand: float = float(rep.get("total_demand", 0.0))
	var bottleneck: String = String(rep.get("bottleneck", "none"))
	var spike: int = int(rep.get("spike_wave_index", -1))
	var spike_label: String = ("W%d" % (spike + 1)) if spike >= 0 else "—"
	# Observed columns from RunStats
	var stats: Dictionary = _level_run_stats(level_data.level_id, history)
	var win_pct_label: String = "—"
	var avg_leaks_label: String = "—"
	var drift_label: String = "—"
	var drift_color: Color = Color.WHITE
	if stats.size() > 0 and int(stats.get("count", 0)) > 0:
		win_pct_label = "%d%%" % int(round(float(stats["win_pct"]) * 100.0))
		avg_leaks_label = "%.1f" % float(stats["avg_leaks"])
		drift_label = _drift_label(safety, stats)
		drift_color = _drift_color(safety, stats)
	_grid_cell(grid, lvl_name)
	_grid_cell(grid, "%d" % int(round(supply)))
	_grid_cell(grid, "%d" % int(round(demand)))
	_grid_cell(grid, "%.2f" % safety, BalanceCalculator.safety_color(safety, _config))
	_grid_cell(grid, bottleneck, _bottleneck_color(bottleneck))
	_grid_cell(grid, spike_label)
	_grid_cell(grid, win_pct_label)
	_grid_cell(grid, avg_leaks_label)
	_grid_cell(grid, drift_label, drift_color)


# ── Per-level drill-down ─────────────────────────────────────────────────
func _render_per_level_breakdowns(levels: Array) -> void:
	_add_section("Detail per level (vectors + sub-ratios)")
	var sorted_levels: Array = levels.duplicate()
	sorted_levels.sort_custom(func(a, b):
		var ao: int = int(a.unlock_order) if a != null and "unlock_order" in a else 0
		var bo: int = int(b.unlock_order) if b != null and "unlock_order" in b else 0
		return ao < bo)
	for lvl in sorted_levels:
		_render_one_level_detail(lvl)


func _render_one_level_detail(level_data: Resource) -> void:
	if level_data == null:
		return
	var wave_path: String = level_data.wave_list_path if "wave_list_path" in level_data else ""
	var wave_list: Resource = load(wave_path) if wave_path != "" else null
	if wave_list == null:
		return
	var loadout: Array = LoadoutState.get_loadout_towers()
	var hero: HeroData = ContentRegistry.find_hero(LoadoutState.selected_hero_id) as HeroData
	var equipped_skills: Array = _resolve_equipped_skills(hero)
	var rep: Dictionary = BalanceCalculator.supply_demand_report(
		level_data, wave_list, loadout, hero, equipped_skills, _config)
	var demand: Dictionary = rep.get("demand", {})
	var supply: Dictionary = rep.get("supply", {})
	var sub: Dictionary = rep.get("sub_ratios", {})
	var title := Label.new()
	title.text = "%s (%s)" % [level_data.display_name, level_data.level_id]
	title.set("theme_override_font_sizes/font_size", 18)
	title.modulate = Color(0.8, 0.95, 1.0)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	content_vbox.add_child(spacer)
	content_vbox.add_child(title)
	# Demand vector
	_add_text("Demand: total_ehp=%d  ground=%d  flying=%d  armored=%d  magic_res=%d  boss=%d  bypass=%d  ability_add=%d  block_cost=%d  max_density=%.2f  max_req_dps=%.1f" % [
		int(round(float(demand.get("total_ehp", 0.0)))),
		int(round(float(demand.get("ground_ehp", 0.0)))),
		int(round(float(demand.get("flying_ehp", 0.0)))),
		int(round(float(demand.get("armored_ehp", 0.0)))),
		int(round(float(demand.get("magic_resist_ehp", 0.0)))),
		int(round(float(demand.get("boss_ehp", 0.0)))),
		int(round(float(demand.get("bypass_pressure", 0.0)))),
		int(round(float(demand.get("ability_ehp_add", 0.0)))),
		int(round(float(demand.get("block_cost", 0.0)))),
		float(demand.get("max_density", 0.0)),
		float(demand.get("max_required_dps", 0.0)),
	])
	# Supply vector
	_add_text("Supply: tower=%d  hero=%d  skills=%d  control=%d  block=%d  | phys=%d  magic=%d  anti_air=%d  aoe=%d  | dpg=%.4f  eff:theo=%.2f" % [
		int(round(float(supply.get("segment_tower", 0.0)))),
		int(round(float(supply.get("segment_hero", 0.0)))),
		int(round(float(supply.get("segment_skills", 0.0)))),
		int(round(float(supply.get("segment_control", 0.0)))),
		int(round(float(supply.get("segment_blocking", 0.0)))),
		int(round(float(supply.get("physical_supply", 0.0)))),
		int(round(float(supply.get("magic_supply", 0.0)))),
		int(round(float(supply.get("anti_air_supply", 0.0)))),
		int(round(float(supply.get("aoe_supply", 0.0)))),
		float(supply.get("avg_dps_per_gold", 0.0)),
		float(supply.get("effective_to_theoretical_dps_ratio", 0.0)),
	])
	# Sub-ratios
	if sub.is_empty():
		_add_text("Sub-ratios: (none — level has no archetype-specific demand)")
	else:
		var parts: Array[String] = []
		for k in sub.keys():
			parts.append("%s=%.2f" % [String(k), float(sub[k])])
		_add_text("Sub-ratios: " + "   ".join(parts))


# ── Sliders for live tuning ──────────────────────────────────────────────
func _build_sliders() -> void:
	for c in slider_vbox.get_children():
		c.queue_free()
	_slider_refs.clear()
	var groups: Array = [
		{"label": "Per-Tier Tower Weights", "rows": [
			["tier_l1_weight", 0.0, 2.0, 0.05],
			["tier_l2_weight", 0.0, 2.0, 0.05],
			["tier_l3_linear_weight", 0.0, 2.0, 0.05],
			["tier_branch_weight", 0.0, 2.0, 0.05],
		]},
		{"label": "Enemy Archetype Demand Weights", "rows": [
			["flying_demand_weight", 0.0, 5.0, 0.05],
			["armored_demand_weight", 0.0, 5.0, 0.05],
			["magic_resist_demand_weight", 0.0, 5.0, 0.05],
			["boss_demand_weight", 0.0, 5.0, 0.05],
			["bypass_demand_weight", 0.0, 5.0, 0.05],
		]},
		{"label": "Enemy Ability Demand", "rows": [
			["regen_score_weight", 0.0, 5.0, 0.05],
			["heal_aura_score_weight", 0.0, 5.0, 0.05],
		]},
		{"label": "Player Supply Segment Weights", "rows": [
			["segment_tower_weight", 0.0, 2.0, 0.05],
			["segment_hero_weight", 0.0, 2.0, 0.05],
			["segment_skills_weight", 0.0, 2.0, 0.05],
			["segment_control_weight", 0.0, 2.0, 0.05],
			["segment_blocking_weight", 0.0, 2.0, 0.05],
		]},
		{"label": "Player Estimates", "rows": [
			["hero_active_time_pct", 0.0, 1.0, 0.05],
			["skill_uptime_pct", 0.0, 1.0, 0.05],
			["effective_to_theoretical_dps_ratio", 0.1, 1.0, 0.01],
		]},
		{"label": "Control", "rows": [
			["slow_dps_multiplier", 1.0, 3.0, 0.05],
			["stun_dps_multiplier", 1.0, 5.0, 0.05],
			["control_stack_cap", 0.0, 1.0, 0.05],
		]},
	]
	for g in groups:
		_add_slider_group(String(g["label"]), g["rows"])


func _add_slider_group(label: String, rows: Array) -> void:
	var heading := Label.new()
	heading.text = label
	heading.set("theme_override_font_sizes/font_size", 16)
	heading.modulate = Color(1.0, 0.85, 0.5)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	slider_vbox.add_child(sp)
	slider_vbox.add_child(heading)
	for row in rows:
		var prop_name: String = String(row[0])
		var rmin: float = float(row[1])
		var rmax: float = float(row[2])
		var rstep: float = float(row[3])
		_add_slider(prop_name, rmin, rmax, rstep)


func _add_slider(prop_name: String, rmin: float, rmax: float, rstep: float) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = prop_name
	name_lbl.set("theme_override_font_sizes/font_size", 13)
	name_lbl.custom_minimum_size = Vector2(280, 0)
	var sld := HSlider.new()
	sld.min_value = rmin
	sld.max_value = rmax
	sld.step = rstep
	sld.value = float(_config.get(prop_name)) if prop_name in _config else rmin
	sld.custom_minimum_size = Vector2(220, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % sld.value
	val_lbl.set("theme_override_font_sizes/font_size", 13)
	val_lbl.custom_minimum_size = Vector2(60, 0)
	sld.value_changed.connect(func(v: float):
		_config.set(prop_name, v)
		val_lbl.text = "%.2f" % v
		_refresh())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	slider_vbox.add_child(hb)
	_slider_refs[prop_name] = sld


# ── Helpers ──────────────────────────────────────────────────────────────
func _resolve_equipped_skills(hero: HeroData) -> Array:
	var out: Array = []
	if hero == null:
		return out
	var ids: Array[String] = LoadoutState.get_equipped_skills(hero.hero_id)
	for sid in ids:
		if sid == "":
			continue
		for s in hero.skills:
			if s != null and "skill_id" in s and s.skill_id == sid:
				out.append(s)
				break
	return out


func _level_run_stats(level_id: String, history: Array) -> Dictionary:
	var wins: int = 0
	var losses: int = 0
	var leak_total: int = 0
	var leak_count: int = 0
	for entry in history:
		if not (entry is Dictionary):
			continue
		if String(entry.get("level_id", "")) != level_id:
			continue
		var outcome: String = String(entry.get("outcome", ""))
		if outcome == "victory":
			wins += 1
		elif outcome == "defeat":
			losses += 1
		var per_wave: Array = entry.get("lives_lost_per_wave", [])
		var sum_leaks: int = 0
		for v in per_wave:
			sum_leaks += int(v)
		leak_total += sum_leaks
		leak_count += 1
	if wins + losses == 0:
		return {}
	return {
		"count": wins + losses,
		"wins": wins,
		"losses": losses,
		"win_pct": float(wins) / float(wins + losses),
		"avg_leaks": float(leak_total) / float(max(1, leak_count)),
	}


# Drift label + color compares predicted safety to observed win%.
# safety > 1.4 (predicted easy) but win% < 0.5 = model wrong (under-predicting hardness).
# safety < 1.0 (predicted hard) but win% > 0.85 = model wrong (over-predicting hardness).
func _drift_label(safety: float, stats: Dictionary) -> String:
	var win_pct: float = float(stats.get("win_pct", 0.0))
	if safety >= _config.safety_ratio_green_max and win_pct < 0.5:
		return "⚠ harder"
	if safety < _config.safety_ratio_red_max and win_pct > 0.85:
		return "⚠ easier"
	return "✓"


func _drift_color(safety: float, stats: Dictionary) -> Color:
	var label: String = _drift_label(safety, stats)
	if label.begins_with("⚠"):
		return Color(0.95, 0.55, 0.45)
	return Color(0.5, 0.95, 0.5)


func _bottleneck_color(bottleneck: String) -> Color:
	if bottleneck == "none":
		return Color(0.7, 0.95, 0.7)
	return Color(0.95, 0.75, 0.4)


# ── Layout helpers (mirror LevelAudit / BalanceReport patterns) ───────────
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
	l.set("theme_override_font_sizes/font_size", 14)
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
