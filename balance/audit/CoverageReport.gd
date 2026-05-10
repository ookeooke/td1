class_name CoverageReport
extends Control

# Pending level hint — set by callers (e.g. a future "open heatmap" chip in
# BalanceSliders) so the screen lands on the relevant level instead of the
# default first-in-list. Cleared after consumption so a subsequent direct
# nav from WorldMap doesn't stick to a stale hint.
static var pending_level_id: String = ""


# Coverage Report — Phase 3 of the coverage-weighted balance plan.
# Debug screen; reachable from WorldMap when OS.is_debug_build() is true.
#
# Surfaces:
#   • Per-wave demand vs realistic supply with pressure verdict.
#   • Per-spot heat: best tower at current gold + path coverage breakdown.
#   • Gold usefulness curve — total damage vs gold spent, with marginal
#     per-100g step. The plateau answers "when does gold stop mattering?"
#   • Greedy placement explanation (what the simulator would buy).
#   • Map heatmap (CoverageHeatmap embed): paths colored by spot reach,
#     spots sized by best-affordable coverage.
#
# This screen does NOT mutate any save state or balance config.

const _DEFAULT_GOLD: int = 600
const _GOLD_SLIDER_MIN: int = 0
const _GOLD_SLIDER_MAX: int = 3000
const _GOLD_SLIDER_STEP: int = 50
const _GOLD_CURVE_STEP: int = 100

@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var controls_vbox: VBoxContainer = %ControlsVBox
@onready var content_vbox: VBoxContainer = %ContentVBox

var _level_selector: OptionButton
var _gold_slider: HSlider
var _gold_label: Label

var _selected_level: Resource = null
var _gold_value: int = _DEFAULT_GOLD

# Cached per-level work — avoid recomputing the marginal curve on each
# slider tick (greedy spend at every gold step is the expensive bit).
var _last_level_id: String = ""
var _cached_curve: Array = []


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	refresh_button.pressed.connect(_refresh)
	_build_controls()
	_pick_default_level()
	_refresh()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


# ── Left panel — controls ────────────────────────────────────────────────

func _build_controls() -> void:
	# Level selector.
	var lvl_label: Label = _make_label("Level", 16)
	controls_vbox.add_child(lvl_label)
	_level_selector = OptionButton.new()
	_level_selector.custom_minimum_size = Vector2(280, 40)
	for lvl in ContentRegistry.levels:
		if lvl == null:
			continue
		var disp: String = String(lvl.display_name) if "display_name" in lvl else String(lvl.level_id)
		_level_selector.add_item(disp)
	_level_selector.item_selected.connect(_on_level_selected)
	controls_vbox.add_child(_level_selector)

	# Gold slider.
	controls_vbox.add_child(_make_label("", 8))  # gap
	_gold_label = _make_label("Gold: %d" % _DEFAULT_GOLD, 16)
	controls_vbox.add_child(_gold_label)
	_gold_slider = HSlider.new()
	_gold_slider.min_value = _GOLD_SLIDER_MIN
	_gold_slider.max_value = _GOLD_SLIDER_MAX
	_gold_slider.step = _GOLD_SLIDER_STEP
	_gold_slider.value = _DEFAULT_GOLD
	_gold_slider.custom_minimum_size = Vector2(280, 32)
	_gold_slider.value_changed.connect(_on_gold_changed)
	controls_vbox.add_child(_gold_slider)

	# Hint text.
	controls_vbox.add_child(_make_label("", 8))
	var hint: Label = _make_label(
		"Drag the gold slider to see how realistic damage scales with gold "
		+ "available to spend on this map. Plateau on the curve = saturation.",
		12,
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.75, 0.75, 0.75)
	hint.custom_minimum_size = Vector2(280, 0)
	controls_vbox.add_child(hint)


func _pick_default_level() -> void:
	if ContentRegistry.levels.is_empty():
		return
	# Honor a pending level hint from a caller (e.g. BalanceSliders' future
	# drill chip). Hint is single-use — consume and clear so direct WorldMap
	# entry afterwards lands on the natural first-level default.
	if pending_level_id != "":
		var hint: String = pending_level_id
		pending_level_id = ""
		for i in range(ContentRegistry.levels.size()):
			var lvl: Resource = ContentRegistry.levels[i]
			if lvl != null and "level_id" in lvl and String(lvl.level_id) == hint:
				_selected_level = lvl
				_level_selector.select(i)
				return
	_selected_level = ContentRegistry.levels[0]
	_level_selector.select(0)


func _on_level_selected(idx: int) -> void:
	if idx < 0 or idx >= ContentRegistry.levels.size():
		return
	_selected_level = ContentRegistry.levels[idx]
	_refresh()


func _on_gold_changed(value: float) -> void:
	_gold_value = int(value)
	_gold_label.text = "Gold: %d" % _gold_value
	_refresh()


# ── Refresh / render ─────────────────────────────────────────────────────

func _refresh() -> void:
	for c in content_vbox.get_children():
		c.queue_free()
	if _selected_level == null:
		_add_section("No level selected.")
		return
	var scene_path: String = String(_selected_level.scene_path)
	var wave_list_path: String = String(_selected_level.wave_list_path)
	if scene_path == "" or wave_list_path == "":
		_add_section("Selected level missing scene_path or wave_list_path.")
		return

	var level: Dictionary = CoverageAnalyzer.parse_level(scene_path)
	if level.is_empty():
		_add_section("Failed to parse level scene.")
		return
	var wl: WaveList = load(wave_list_path) as WaveList
	if wl == null or wl.waves.is_empty():
		_add_section("Failed to load wave list at %s." % wave_list_path)
		return

	var profiles: Array = WaveDamageSimulator.build_tower_profiles()
	# We don't strictly need to call build_coverage_matrix here — the
	# simulator queries CoverageAnalyzer.spot_path_coverage on demand and
	# everything is cached. But we DO need a stable shape for callers, so
	# build the matrix once for the heatmap + spot table to share.
	var coverage_matrix: Dictionary = CoverageAnalyzer.build_coverage_matrix(scene_path, _profiles_to_coverage_rows(profiles))

	var headline_gold: int = _gold_value
	var greedy: Dictionary = WaveDamageSimulator.greedy_spend(wl.waves, headline_gold, coverage_matrix, profiles)

	# 1. Headline summary.
	_render_headline(level, wl, headline_gold, greedy, coverage_matrix, profiles)
	_render_diagnosis(wl, coverage_matrix, profiles, _selected_level)
	# 2. Wave table.
	_render_wave_table(wl, coverage_matrix, profiles, _selected_level)
	# 3. Map heatmap.
	_render_heatmap(level, profiles, headline_gold)
	# 4. Gold usefulness chart.
	_render_gold_curve(level, wl, coverage_matrix, profiles)
	# 5. Spot heat table.
	_render_spot_table(level, headline_gold, profiles, coverage_matrix, wl)
	# 6. Placement explanation.
	_render_placements(greedy)


func _render_headline(level: Dictionary, wl: WaveList, gold: int, greedy: Dictionary, coverage_matrix: Dictionary, profiles: Array) -> void:
	_add_section("Headline — %s @ %d gold" % [level.get("level_id", "?"), gold])
	var demand: float = WaveDamageSimulator.level_demand_damage(wl.waves)
	var supply: float = float(greedy.get("total_damage", 0.0))
	var pressure: float = (demand / max(1.0, supply))
	var verdict: Dictionary = WaveDamageSimulator.pressure_verdict(pressure)
	var spent: int = int(greedy.get("gold_spent", 0))
	var left: int = int(greedy.get("gold_left", 0))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	_add_grid_row(grid, ["Demand (EHP)", "Supply (greedy)", "Pressure (D/S)", "Verdict"], true)
	var verdict_color: Color = verdict["color"]
	var rows: Array = [
		"%d" % int(demand),
		"%d" % int(supply),
		"%.2f" % pressure,
		String(verdict["label"]),
	]
	_add_grid_row(grid, rows, false, [Color.WHITE, Color.WHITE, Color.WHITE, verdict_color])
	content_vbox.add_child(grid)

	_add_text("Greedy spend used %d / %d gold; %d gold left over (no further useful purchases). Best-case greedy estimate." % [spent, gold, left])


func _render_diagnosis(wl: WaveList, coverage_matrix: Dictionary, profiles: Array, level_data: Resource) -> void:
	_add_section("What this means")
	var gold_at_start: int = _starting_gold_for_level(level_data)
	var natural_final_gold: int = gold_at_start
	var trivial_count: int = 0
	var dangerous_count: int = 0
	var pressure_sum: float = 0.0
	var pressure_count: int = 0
	for w in wl.waves:
		if w == null:
			continue
		var demand: float = WaveDamageSimulator.wave_demand_damage(w)
		var single: Dictionary = WaveDamageSimulator.greedy_spend([w], gold_at_start, coverage_matrix, profiles)
		var supply: float = float(single.get("total_damage", 0.0))
		var pressure: float = demand / max(1.0, supply)
		pressure_sum += pressure
		pressure_count += 1
		if pressure < 0.50:
			trivial_count += 1
		elif pressure > 1.05:
			dangerous_count += 1
		natural_final_gold += BalanceCalculator.wave_gold(w)
	var avg_pressure: float = pressure_sum / float(max(1, pressure_count))
	var plateau_gold: int = _plateau_gold_for_level(wl, coverage_matrix, profiles)
	var msg: String = "%d/%d waves are trivial (<0.50 pressure), %d are dangerous (>1.05), avg pressure %.2f." % [
		trivial_count, pressure_count, dangerous_count, avg_pressure,
	]
	if plateau_gold >= 0:
		msg += " Damage stops meaningfully increasing around %dg; natural final budget is about %dg." % [
			plateau_gold, natural_final_gold,
		]
	_add_text(msg)
	if trivial_count >= max(1, int(ceil(float(pressure_count) * 0.5))):
		_add_text("Diagnosis: the player can buy too much effective damage too early. First knobs to try: lower wave gold/bounty or increase enemy count/density before touching tower stats.")
	elif dangerous_count > 0:
		_add_text("Diagnosis: at least one wave may be under-supplied with natural gold. Check that wave's paths and enemy type before adding global gold.")
	elif plateau_gold >= 0 and natural_final_gold > plateau_gold + 200:
		_add_text("Diagnosis: extra late gold is probably vanity. Add meaningful upgrade sinks, add/adjust tower spots, or reduce late-wave rewards.")
	else:
		_add_text("Diagnosis: pacing is in the useful band. Use playtest damage attribution to calibrate the model.")


func _render_wave_table(wl: WaveList, coverage_matrix: Dictionary, profiles: Array, level_data: Resource) -> void:
	_add_section("Per-wave — Natural Gold Pacing")
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	_add_grid_row(grid, ["Wave", "Gold@start", "Demand", "Possible", "Pressure", "Target", "Verdict"], true)
	var gold_at_start: int = _starting_gold_for_level(level_data)
	var pressure_targets: Array = level_data.wave_pressure_targets if level_data != null and "wave_pressure_targets" in level_data else []
	for i in range(wl.waves.size()):
		var w: WaveData = wl.waves[i]
		if w == null:
			continue
		var demand: float = WaveDamageSimulator.wave_demand_damage(w)
		var single: Dictionary = WaveDamageSimulator.greedy_spend([w], gold_at_start, coverage_matrix, profiles)
		var supply: float = float(single.get("total_damage", 0.0))
		var pressure: float = demand / max(1.0, supply)
		var v: Dictionary = WaveDamageSimulator.pressure_verdict(pressure)
		var target: String = "—"
		if i < pressure_targets.size():
			target = "%.2f" % float(pressure_targets[i])
		_add_grid_row(grid, [
			"W%d" % (i + 1),
			"%d g" % gold_at_start,
			"%d" % int(demand),
			"%d" % int(supply),
			"%.2f" % pressure,
			target,
			String(v["label"]),
		], false, [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, v["color"]])
		gold_at_start += BalanceCalculator.wave_gold(w)
	content_vbox.add_child(grid)
	_add_text("This table spends only the gold naturally available at each wave start. It is the pacing diagnostic; the slider and gold curve are sandbox views.")


func _render_heatmap(level: Dictionary, profiles: Array, gold: int) -> void:
	_add_section("Map heatmap — paths colored by reach, spots by best-tier coverage")
	# Recreate per-refresh; the children-clearout at the top of _refresh
	# already queue_freed any previous heatmap. Drawing is cheap; caching
	# would require excluding the heatmap from the clearout, which adds
	# branching that isn't worth the saved allocation.
	var hm: CoverageHeatmap = CoverageHeatmap.new()
	hm.custom_minimum_size = Vector2(640, 380)
	hm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(hm)
	hm.set_level(level, profiles, gold)


func _render_gold_curve(level: Dictionary, wl: WaveList, coverage_matrix: Dictionary, profiles: Array) -> void:
	_add_section("Gold usefulness — total damage vs gold spent")
	var key: String = String(level.get("level_id", ""))
	if _last_level_id != key:
		var gold_values: Array = []
		var g: int = 0
		while g <= _GOLD_SLIDER_MAX:
			gold_values.append(g)
			g += _GOLD_CURVE_STEP
		_cached_curve = WaveDamageSimulator.marginal_gold_curve(wl.waves, gold_values, coverage_matrix, profiles)
		_last_level_id = key
	var chart: Control = _make_gold_chart(_cached_curve, _gold_value)
	content_vbox.add_child(chart)


func _render_spot_table(level: Dictionary, gold: int, profiles: Array, coverage_matrix: Dictionary, wl: WaveList) -> void:
	_add_section("Per-spot heat at %d gold" % gold)
	var spots_dict: Dictionary = level.get("spots", {})
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	_add_grid_row(grid, ["Spot", "Best tower", "Cost", "Avg coverage", "Notes"], true)

	# Score each spot's best damage at the gold budget — pick the affordable
	# profile with highest summed damage across all waves.
	var sorted_spots: Array = []
	for spot_id in spots_dict:
		sorted_spots.append(String(spot_id))
	sorted_spots.sort()
	for spot_id in sorted_spots:
		var best: Dictionary = _best_profile_for_spot(spot_id, gold, profiles, coverage_matrix, wl)
		if best.is_empty():
			_add_grid_row(grid, [spot_id, "(none affordable)", "—", "—", ""], false)
			continue
		var prof: Dictionary = best["profile"]
		var pct: float = float(best["avg_coverage_pct"])
		var notes: String = best.get("notes", "")
		_add_grid_row(grid, [
			spot_id,
			"%s · %s" % [prof["tower_id"], prof["tier_key"]],
			"%d g" % int(prof["cost"]),
			"%d%%" % int(round(pct * 100.0)),
			notes,
		], false)
	content_vbox.add_child(grid)


func _render_placements(greedy: Dictionary) -> void:
	var steps: Array = greedy.get("steps", [])
	if steps.is_empty():
		_add_text("No placements (gold too low).")
		return
	_add_section("Greedy placement order at %d gold" % _gold_value)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	_add_grid_row(grid, ["#", "Spot", "Action", "Tower", "Cost", "Efficiency"], true)
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		_add_grid_row(grid, [
			"%d" % (i + 1),
			String(s["spot_id"]),
			String(s["kind"]),
			"%s · %s" % [s["tower_id"], s["tier_key"]],
			"%d g" % int(s["cost"]),
			"%.2f dmg/g" % float(s["efficiency"]),
		], false)
	content_vbox.add_child(grid)


# ── Helpers ──────────────────────────────────────────────────────────────

# Return only the (tower_id, tier_key, range) shape build_coverage_matrix needs.
func _profiles_to_coverage_rows(profiles: Array) -> Array:
	var out: Array = []
	for p in profiles:
		out.append({
			"tower_id": p["tower_id"],
			"tier_key": p["tier_key"],
			"range": p["attack_range"],
		})
	return out


# Best affordable profile for a spot (within gold) by summed damage across
# all waves. Returns empty dict if nothing affordable produces damage.
func _best_profile_for_spot(spot_id: String, gold: int, profiles: Array, coverage_matrix: Dictionary, wl: WaveList) -> Dictionary:
	var spots_dict: Dictionary = coverage_matrix.get("spots", {})
	if not spots_dict.has(spot_id):
		return {}
	var best_dmg: float = 0.0
	var best: Dictionary = {}
	for p in profiles:
		if p.get("is_barracks", false):
			continue
		if int(p["cost"]) > gold:
			continue
		var dmg: float = 0.0
		for w in wl.waves:
			dmg += WaveDamageSimulator.candidate_wave_damage(spot_id, p, w, coverage_matrix)
		if dmg > best_dmg:
			best_dmg = dmg
			# Compute average coverage % across all paths for this tier.
			var key: String = "%s:%s" % [p["tower_id"], p["tier_key"]]
			var per_path: Dictionary = (spots_dict[spot_id] as Dictionary).get(key, {})
			var sum_pct: float = 0.0
			var n: int = 0
			for path_id in per_path:
				sum_pct += float((per_path[path_id] as Dictionary).get("coverage_pct", 0.0))
				n += 1
			var avg_pct: float = (sum_pct / float(n)) if n > 0 else 0.0
			var notes: String = ""
			if dmg <= 0.0:
				notes = "no path coverage"
			best = {
				"profile": p,
				"damage": dmg,
				"avg_coverage_pct": avg_pct,
				"notes": notes,
			}
	return best


func _starting_gold_for_level(level_data: Resource) -> int:
	var starting: int = RunState.STARTING_GOLD
	if level_data == null:
		return starting
	var BO: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var level_id: String = String(level_data.level_id) if "level_id" in level_data else ""
	if BO != null and level_id != "":
		var per_level: int = BO.get_level_int(level_id, "starting_gold", -1)
		if per_level >= 0:
			return per_level
		starting += BO.get_starting_gold_add()
	starting += int(MetaProgression.get_upgrade_bonus(MetaProgression.MOD_STARTING_GOLD))
	return starting


func _plateau_gold_for_level(wl: WaveList, coverage_matrix: Dictionary, profiles: Array) -> int:
	var gold_values: Array = []
	var g: int = 0
	while g <= _GOLD_SLIDER_MAX:
		gold_values.append(g)
		g += _GOLD_CURVE_STEP
	var curve: Array = WaveDamageSimulator.marginal_gold_curve(wl.waves, gold_values, coverage_matrix, profiles)
	for i in range(1, curve.size()):
		var stable: bool = true
		for j in range(i, curve.size()):
			var prev: float = float(curve[j - 1]["damage"])
			var cur: float = float(curve[j]["damage"])
			if cur - prev > 1.0:
				stable = false
				break
		if stable:
			return int(curve[i - 1]["gold"])
	return -1


func _make_gold_chart(curve: Array, current_gold: int) -> Control:
	var ctrl: Control = Control.new()
	ctrl.custom_minimum_size = Vector2(640, 220)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.set_meta("curve", curve)
	ctrl.set_meta("current_gold", current_gold)
	ctrl.draw.connect(func(): _draw_gold_chart(ctrl))
	return ctrl


func _draw_gold_chart(ctrl: Control) -> void:
	var curve: Array = ctrl.get_meta("curve", [])
	var current_gold: int = int(ctrl.get_meta("current_gold", 0))
	var rect: Rect2 = Rect2(Vector2.ZERO, ctrl.size)
	ctrl.draw_rect(rect, Color(0.08, 0.10, 0.12), true)
	if curve.is_empty():
		return
	var pad_l: float = 56.0
	var pad_r: float = 16.0
	var pad_t: float = 16.0
	var pad_b: float = 28.0
	var inner: Rect2 = Rect2(
		Vector2(pad_l, pad_t),
		Vector2(rect.size.x - pad_l - pad_r, rect.size.y - pad_t - pad_b),
	)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var max_gold: float = float(curve[-1]["gold"])
	var max_dmg: float = 1.0
	for pt in curve:
		max_dmg = max(max_dmg, float(pt["damage"]))

	# Axes.
	ctrl.draw_line(inner.position + Vector2(0, inner.size.y), inner.end, Color(0.5, 0.5, 0.5), 1.0)
	ctrl.draw_line(inner.position, inner.position + Vector2(0, inner.size.y), Color(0.5, 0.5, 0.5), 1.0)

	# Marginal bars (per-step delta).
	for i in range(1, curve.size()):
		var prev: float = float(curve[i - 1]["damage"])
		var cur: float = float(curve[i]["damage"])
		var delta: float = max(0.0, cur - prev)
		var x_a: float = inner.position.x + inner.size.x * (float(curve[i - 1]["gold"]) / max_gold)
		var x_b: float = inner.position.x + inner.size.x * (float(curve[i]["gold"]) / max_gold)
		var bar_h: float = inner.size.y * (delta / max_dmg)
		var bar_rect := Rect2(Vector2(x_a, inner.end.y - bar_h), Vector2(max(1.0, x_b - x_a - 1.0), bar_h))
		ctrl.draw_rect(bar_rect, Color(0.30, 0.50, 0.85, 0.55), true)

	# Cumulative line.
	var prev_pt: Vector2 = Vector2.ZERO
	for i in range(curve.size()):
		var g: float = float(curve[i]["gold"])
		var d: float = float(curve[i]["damage"])
		var p: Vector2 = Vector2(
			inner.position.x + inner.size.x * (g / max_gold),
			inner.end.y - inner.size.y * (d / max_dmg),
		)
		if i > 0:
			ctrl.draw_line(prev_pt, p, Color(0.95, 0.85, 0.30), 2.0, true)
		prev_pt = p

	# Current-gold marker.
	if current_gold > 0:
		var x_cur: float = inner.position.x + inner.size.x * (clamp(float(current_gold) / max_gold, 0.0, 1.0))
		ctrl.draw_line(Vector2(x_cur, inner.position.y), Vector2(x_cur, inner.end.y), Color(0.95, 0.45, 0.45, 0.85), 1.5)

	# Labels.
	var f: Font = ThemeDB.fallback_font
	ctrl.draw_string(f, Vector2(inner.position.x - 48, inner.position.y + 12), "%d dmg" % int(max_dmg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
	ctrl.draw_string(f, Vector2(inner.position.x - 16, inner.end.y + 16), "0g", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
	ctrl.draw_string(f, Vector2(inner.end.x - 32, inner.end.y + 16), "%dg" % int(max_gold), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))


# ── UI primitives ────────────────────────────────────────────────────────

func _add_section(title: String) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	content_vbox.add_child(header)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = Color(0.85, 0.85, 0.85)
	content_vbox.add_child(lbl)


func _add_grid_row(grid: GridContainer, cells: Array, header: bool, colors: Array = []) -> void:
	for i in range(cells.size()):
		var lbl := Label.new()
		lbl.text = String(cells[i])
		lbl.add_theme_font_size_override("font_size", 14 if header else 13)
		if header:
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		elif i < colors.size():
			lbl.add_theme_color_override("font_color", colors[i])
		grid.add_child(lbl)


func _make_label(text: String, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl
