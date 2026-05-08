extends Control

# Debug-only slider panel for balance testing — reachable from WorldMap when
# OS.is_debug_build() is true. Writes runtime overrides via BalanceOverrides
# (no .tres file edits, no save mutation). Live readout reflects what the
# next level launch will see.
#
# See balance/BALANCE.md "Player Power Tier (PPT)" + active plan.

const BalanceOverrides = preload("res://balance/debug/BalanceOverrides.gd")

@onready var back_button: Button = %BackButton
@onready var play_button: Button = %PlayButton
@onready var reset_button: Button = %ResetButton

@onready var level_picker: OptionButton = %LevelPicker
@onready var hp_slider: HSlider = %HpSlider
@onready var hp_value: Label = %HpValue
@onready var armor_slider: HSlider = %ArmorSlider
@onready var armor_value: Label = %ArmorValue
@onready var magres_slider: HSlider = %MagResSlider
@onready var magres_value: Label = %MagResValue
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_value: Label = %SpeedValue
@onready var damage_slider: HSlider = %DamageSlider
@onready var damage_value: Label = %DamageValue
@onready var gold_slider: HSlider = %GoldSlider
@onready var gold_value: Label = %GoldValue
@onready var ppt_slider: HSlider = %PptSlider
@onready var ppt_value: Label = %PptValue

@onready var readout_hardness: Label = %ReadoutHardness
@onready var readout_gold_dmg: Label = %ReadoutGoldDmg
@onready var readout_ppt: Label = %ReadoutPpt
@onready var tower_section: VBoxContainer = %TowerSection
@onready var level_section: VBoxContainer = %LevelSection

const _WaveTimelineChartScript := preload("res://balance/debug/WaveTimelineChart.gd")
const _LevelOverviewChartScript := preload("res://balance/debug/LevelOverviewChart.gd")

var _levels: Array = []   # Array[LevelNodeData], populated from level_list.tres
# WaveTimelineChart entries created per expanded level — refreshed on any
# slider change. Each entry: {chart, wave_index, level_data, wave_list,
# paths_in_level}. v1 only populates this for Level 5.
var _wave_charts: Array = []
# Enemy overrides section — created programmatically in _build_enemy_section
# and inserted into the same parent as %TowerSection. Keeping it out of the
# .tscn lets the BalanceSliders scene stay editor-portable.
var _enemy_section: VBoxContainer = null
# Per-tower-tier value labels keyed by "tower_id|tier|stat" so refresh after
# Reset can rewrite them in place without rebuilding the whole subtree.
var _tower_value_labels: Dictionary = {}
# Per-level value labels keyed by "level_id|key".
var _level_value_labels: Dictionary = {}
# Per-tier derived-metric labels (DPS / cumul / g/DPS / TTK / role / delta /
# compare / obs) keyed by "tower_id|tier_key" → Dictionary{label_key: Label}.
# Refreshed live by _refresh_all_metrics on any tower-slider change so the
# designer sees the impact of a stat tweak on g/DPS without reloading.
var _tier_metric_labels: Dictionary = {}
# Top-of-section summary grid (one row per tower-tier with DPS / g/DPS / role).
var _summary_grid: GridContainer = null
# RunStats.get_history() snapshot, refreshed once per _refresh_all_metrics so
# the file isn't re-read for every tower-tier label. Cleared on _build_tower_section
# so a fresh open of the panel re-pulls the latest run history.
var _history_cache: Array = []


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	play_button.pressed.connect(_on_play)
	reset_button.pressed.connect(_on_reset)
	_add_bake_button()
	_load_levels()
	_load_slider_values()
	_connect_sliders()
	_build_tower_section()
	_build_enemy_section()
	_build_level_section()
	_refresh_readout()


# Programmatically inject a "Bake to .tres" button next to Reset. Lives next
# to its semantic neighbor without touching the .tscn — keeps the scene file
# single-purpose and lets this debug-only button sit out of the layout when
# the BalanceSliders.tscn is opened in the editor.
func _add_bake_button() -> void:
	var bake := Button.new()
	bake.text = "Bake stats to .tres"
	bake.tooltip_text = "Writes the CURRENT tower-stat overrides into towers/data/*.tres files.\nClears tower overrides afterward — Reset will go to the just-baked values, not the original authored ones.\nDebug-only: ResourceSaver only writes to res:// in editor / debug builds."
	# Mirror the visual weight + spacing of the Reset button: same parent, same
	# theme inheritance, sit immediately after Reset in the row.
	var parent: Node = reset_button.get_parent()
	if parent == null:
		return
	parent.add_child(bake)
	parent.move_child(bake, reset_button.get_index() + 1)
	bake.pressed.connect(_on_bake_pressed)


func _load_levels() -> void:
	_levels = ContentRegistry.levels
	if _levels.is_empty():
		level_picker.add_item("(no levels)")
		level_picker.disabled = true
		return
	for lvl in _levels:
		if lvl == null:
			continue
		level_picker.add_item(lvl.display_name + "  [" + lvl.level_id + "]")
	level_picker.item_selected.connect(_on_level_changed)


func _load_slider_values() -> void:
	hp_slider.value = float(BalanceOverrides.get_value("hp_mult")) * 100.0
	armor_slider.value = float(BalanceOverrides.get_value("armor_add"))
	magres_slider.value = float(BalanceOverrides.get_value("mag_res_add"))
	speed_slider.value = float(BalanceOverrides.get_value("speed_mult")) * 100.0
	damage_slider.value = float(BalanceOverrides.get_value("damage_mult")) * 100.0
	gold_slider.value = float(BalanceOverrides.get_value("starting_gold_add"))
	ppt_slider.value = float(BalanceOverrides.get_value("ppt_override"))
	_update_value_labels()


func _connect_sliders() -> void:
	hp_slider.value_changed.connect(_on_hp_changed)
	armor_slider.value_changed.connect(_on_armor_changed)
	magres_slider.value_changed.connect(_on_magres_changed)
	speed_slider.value_changed.connect(_on_speed_changed)
	damage_slider.value_changed.connect(_on_damage_changed)
	gold_slider.value_changed.connect(_on_gold_changed)
	ppt_slider.value_changed.connect(_on_ppt_changed)


func _on_hp_changed(v: float) -> void:
	BalanceOverrides.set_value("hp_mult", v / 100.0)
	_update_value_labels()
	_refresh_readout()
	# Charts read per-enemy EHP through the override stack (incl. global
	# hp_mult), so a global HP slider tweak must redraw bar heights.
	_refresh_wave_charts()


func _on_armor_changed(v: float) -> void:
	BalanceOverrides.set_value("armor_add", v)
	_update_value_labels()
	_refresh_readout()
	_refresh_wave_charts()


func _on_magres_changed(v: float) -> void:
	BalanceOverrides.set_value("mag_res_add", v)
	_update_value_labels()
	_refresh_readout()


func _on_speed_changed(v: float) -> void:
	BalanceOverrides.set_value("speed_mult", v / 100.0)
	_update_value_labels()
	_refresh_readout()


func _on_damage_changed(v: float) -> void:
	BalanceOverrides.set_value("damage_mult", v / 100.0)
	_update_value_labels()
	_refresh_readout()


func _on_gold_changed(v: float) -> void:
	BalanceOverrides.set_value("starting_gold_add", int(v))
	_update_value_labels()
	_refresh_readout()
	# Charts use _compute_starting_gold for the supply line and gold curve,
	# both of which include this global add — redraw on slider change.
	_refresh_wave_charts()


func _on_ppt_changed(v: float) -> void:
	# -1 = auto (use loadout PPT), >=1 = forced override
	var ppt_int: int = int(round(v))
	BalanceOverrides.set_value("ppt_override", ppt_int)
	_update_value_labels()
	_refresh_readout()


func _on_level_changed(_idx: int) -> void:
	_refresh_readout()


func _update_value_labels() -> void:
	hp_value.text = "%d%%" % int(round(hp_slider.value))
	armor_value.text = "%+.2f" % armor_slider.value
	magres_value.text = "%+.2f" % magres_slider.value
	speed_value.text = "%d%%" % int(round(speed_slider.value))
	damage_value.text = "%d%%" % int(round(damage_slider.value))
	gold_value.text = "%+d" % int(round(gold_slider.value))
	var ppt_int: int = int(round(ppt_slider.value))
	ppt_value.text = "auto" if ppt_int < 1 else str(ppt_int)


func _selected_level() -> Resource:
	if _levels.is_empty():
		return null
	var idx: int = level_picker.selected
	if idx < 0 or idx >= _levels.size():
		return null
	return _levels[idx]


func _refresh_readout() -> void:
	var level_data: Resource = _selected_level()
	if level_data == null:
		readout_hardness.text = "Hardness: (no level)"
		readout_gold_dmg.text = ""
		readout_ppt.text = ""
		return
	var wave_list: Resource = load(level_data.wave_list_path)
	if wave_list == null:
		readout_hardness.text = "Hardness: (waves missing — %s)" % level_data.wave_list_path
		readout_gold_dmg.text = ""
		readout_ppt.text = ""
		return
	# Baseline hardness from authored data (no overrides folded in — overrides
	# affect runtime, not the static score). We display baseline AND an
	# estimate of effective hardness assuming HP mult dominates.
	var baseline: float = BalanceCalculator.score_level(wave_list, 100)
	var hp_mult: float = float(BalanceOverrides.get_value("hp_mult"))
	var effective: float = baseline * hp_mult
	var pct: float = (hp_mult - 1.0) * 100.0
	if absf(pct) < 0.5:
		readout_hardness.text = "Hardness:  %d  (baseline)" % int(round(baseline))
	else:
		readout_hardness.text = "Hardness:  %d → %d  (%+.0f%%)" % [
			int(round(baseline)), int(round(effective)), pct,
		]
	# Gold per damage required — economy stinginess metric.
	var req: float = BalanceCalculator.level_required_damage(wave_list)
	if req > 0.0:
		var gold_total: int = level_data.gold_budget_total + int(round(gold_slider.value))
		var gpd: float = float(gold_total) / (req * hp_mult)
		readout_gold_dmg.text = "Gold/Dmg:  %.2f   (gold=%dg, req_dmg=%d)" % [
			gpd, gold_total, int(round(req * hp_mult)),
		]
	else:
		readout_gold_dmg.text = "Gold/Dmg:  (no required damage)"
	# PPT drift — two flavors:
	#   target drift  = actual hardness vs authored target_ppt × HARDNESS_FACTOR
	#                   (the design-spec deviation; doesn't move when slider does)
	#   active drift  = actual hardness vs ppt_used × HARDNESS_FACTOR where
	#                   ppt_used = forced override if set, else loadout PPT
	#                   (answers "what does this drift look like at PPT=N?")
	# Showing both makes the slider visibly meaningful — moving it changes the
	# active drift number while the target drift stays put as a reference.
	var forced: int = int(round(ppt_slider.value))
	var target_ppt: int = int(level_data.target_ppt) if "target_ppt" in level_data else 2
	var ppt_used: float
	var ppt_label: String
	if forced >= 1:
		ppt_used = float(forced)
		ppt_label = "forced=%d" % forced
	else:
		ppt_used = LoadoutState.get_effective_ppt() if LoadoutState.has_method("get_effective_ppt") else float(target_ppt)
		ppt_label = "loadout=%.2f" % ppt_used
	var target_drift: float = BalanceCalculator.score_for_ppt(wave_list, target_ppt, 100)
	# score_for_ppt expects an int target — round ppt_used to the nearest int
	# for the active drift query, mirroring how the audit screen treats PPT
	# in integer bands.
	var active_drift: float = BalanceCalculator.score_for_ppt(wave_list, max(1, int(round(ppt_used))), 100)
	if absf(ppt_used - float(target_ppt)) < 0.05:
		# Slider sitting on the target PPT; one drift number is enough.
		readout_ppt.text = "PPT:  target=%d  %s   →  drift %+.0f%%" % [
			target_ppt, ppt_label, target_drift,
		]
	else:
		readout_ppt.text = "PPT:  target=%d (drift %+.0f%%)   %s (drift %+.0f%%)" % [
			target_ppt, target_drift, ppt_label, active_drift,
		]


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_play() -> void:
	var level_data: Resource = _selected_level()
	if level_data == null:
		return
	# Stage the run the same way LoadoutScreen / PauseMenu do: set the level id,
	# call reset_for_level so override-adjusted starting_gold + lives apply, then
	# go to Main.tscn (NOT the level scene directly — Main owns the HUD, camera,
	# spawn pipeline; loading the level scene alone leaves all of that absent).
	RunState.current_level_id = level_data.level_id
	RunState.current_mode = "campaign"
	RunState.reset_for_level()
	SceneManager.goto("res://main/Main.tscn")


func _on_reset() -> void:
	BalanceOverrides.reset()
	_load_slider_values()
	# Rebuild the tower + enemy + level sections so their sliders snap to defaults.
	_build_tower_section()
	_build_enemy_section()
	_build_level_section()
	_refresh_readout()


# ── Enemy overrides section ─────────────────────────────────────────────
# Per-enemy multipliers (HP / speed / damage / gold) and additives (armor /
# mag-res). Mirrors the per-tower section structure so the UX is identical.
# Stored under BalanceOverrides "enemy_overrides" sub-dict.

# Progression order (lightest / earliest → heaviest / boss). Used to sort the
# Enemy section so designers scan top-to-bottom in the order enemies are
# introduced in the campaign. Same constant duplicated in WaveTimelineChart
# and LevelOverviewChart for the stacked bar segment order — slider list and
# bar stack mirror each other.
const _ENEMY_PROGRESSION: Array[String] = [
	"basic", "scout", "flying", "healer", "armored", "brute", "boss",
]


# Returns the progression rank for a given class_key. Unknown keys sort last.
func _enemy_progression_rank(class_key: String) -> int:
	var idx: int = _ENEMY_PROGRESSION.find(class_key)
	return idx if idx >= 0 else _ENEMY_PROGRESSION.size()


const _ENEMY_STAT_DEFS: Array = [
	# {key, mode, label, prop} — mode "mult" or "add"; prop is the EnemyData field.
	{"key": "hp_mult",      "mode": "mult", "label": "HP",     "prop": "max_health"},
	{"key": "armor_add",    "mode": "add",  "label": "Armor",  "prop": "armor"},
	{"key": "mag_res_add",  "mode": "add",  "label": "MagRes", "prop": "magic_resist"},
	{"key": "speed_mult",   "mode": "mult", "label": "Speed",  "prop": "move_speed"},
	{"key": "damage_mult",  "mode": "mult", "label": "Damage", "prop": "attack_damage"},
	{"key": "gold_mult",    "mode": "mult", "label": "Gold",   "prop": "gold_worth"},
]


func _build_enemy_section() -> void:
	# Create the section container once, insert just below the tower section.
	if _enemy_section == null:
		_enemy_section = VBoxContainer.new()
		_enemy_section.set("theme_override_constants/separation", 4)
		var parent: Node = tower_section.get_parent()
		if parent != null:
			parent.add_child(_enemy_section)
			parent.move_child(_enemy_section, tower_section.get_index() + 1)
	for c in _enemy_section.get_children():
		c.queue_free()
	var heading := Label.new()
	heading.text = "Enemy overrides — per-enemy multipliers (1.0 = no change)"
	heading.set("theme_override_font_sizes/font_size", 22)
	heading.modulate = Color(1.0, 0.9, 0.5, 1)
	_enemy_section.add_child(heading)
	# Sort enemies by progression rank (basic first, boss last) so the
	# section reads top-to-bottom in campaign-introduction order.
	var sorted_enemies: Array = []
	for e in ContentRegistry.enemies:
		if e == null or not (e is EnemyData) or String(e.enemy_id) == "":
			continue
		sorted_enemies.append(e)
	sorted_enemies.sort_custom(func(a, b):
		return _enemy_progression_rank(_class_key_for_enemy_id(String(a.enemy_id))) \
			< _enemy_progression_rank(_class_key_for_enemy_id(String(b.enemy_id))))
	for enemy in sorted_enemies:
		_add_enemy_subgroup(enemy)


# Map an enemy_id string to a class-key matching the chart palette. Mirrors
# WaveTimelineChart._enemy_class_for which works off resource_path.
func _class_key_for_enemy_id(eid: String) -> String:
	var lower: String = eid.to_lower()
	if lower.contains("boss"):
		return "boss"
	if lower.contains("scout"):
		return "scout"
	if lower.contains("armor"):
		return "armored"
	if lower.contains("flying"):
		return "flying"
	if lower.contains("brute"):
		return "brute"
	if lower.contains("healer"):
		return "healer"
	return "basic"


func _add_enemy_subgroup(enemy: Resource) -> void:
	var group := VBoxContainer.new()
	group.set("theme_override_constants/separation", 2)
	var hdr := Button.new()
	var ename: String = String(enemy.enemy_name) if "enemy_name" in enemy else String(enemy.enemy_id)
	hdr.text = "▸ %s   (%s)" % [ename, enemy.enemy_id]
	hdr.flat = true
	hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.set("theme_override_font_sizes/font_size", 18)
	hdr.modulate = Color(0.85, 0.95, 1.0)
	var body := VBoxContainer.new()
	body.set("theme_override_constants/separation", 2)
	body.visible = false
	hdr.pressed.connect(func():
		body.visible = not body.visible
		hdr.text = ("▾ " if body.visible else "▸ ") + ename + "   (" + String(enemy.enemy_id) + ")")
	for stat_def in _ENEMY_STAT_DEFS:
		var prop: String = String(stat_def.prop)
		# Skip stats the enemy doesn't expose (defensive — all stats currently
		# exist on EnemyData, but this stays safe if EnemyData is trimmed).
		if not (prop in enemy):
			continue
		var authored: float = float(enemy.get(prop))
		_add_enemy_slider(body, String(enemy.enemy_id), stat_def, authored)
	group.add_child(hdr)
	group.add_child(body)
	_enemy_section.add_child(group)


func _add_enemy_slider(parent: VBoxContainer, enemy_id: String, stat_def: Dictionary, authored: float) -> void:
	var stat_key: String = String(stat_def.key)
	var mode: String = String(stat_def.mode)
	var label: String = String(stat_def.label)
	# When mode == "mult" but authored == 0 (e.g. basic enemy with attack_damage=0
	# can't earn meaningful damage_mult), show a static "—" row instead of a
	# slider that can't move. Designer can bake to .tres first to enable.
	if mode == "mult" and authored <= 0.0:
		var hb_skip := HBoxContainer.new()
		hb_skip.set("theme_override_constants/separation", 12)
		var nl := Label.new()
		nl.text = "        " + label
		nl.set("theme_override_font_sizes/font_size", 13)
		nl.custom_minimum_size = Vector2(220, 0)
		var vl := Label.new()
		vl.text = "—  (no authored value)"
		vl.set("theme_override_font_sizes/font_size", 13)
		vl.modulate = Color(0.55, 0.60, 0.68)
		hb_skip.add_child(nl)
		hb_skip.add_child(vl)
		parent.add_child(hb_skip)
		return
	var current_override: float = BalanceOverrides.get_enemy_mult(enemy_id, stat_key)
	var current_abs: float
	var sld_min: float
	var sld_max: float
	var sld_step: float
	if mode == "mult":
		current_abs = authored * current_override
		sld_min = 0.0
		sld_max = max(authored * 3.0, authored + 1.0)
		sld_step = _enemy_step_for(stat_key, authored)
	else:
		# Additive (armor / mag_res). Slider works in absolute clamp 0..0.95.
		current_abs = clampf(authored + current_override, 0.0, 0.95)
		sld_min = 0.0
		sld_max = 0.95
		sld_step = 0.05
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "        " + label
	name_lbl.set("theme_override_font_sizes/font_size", 13)
	name_lbl.custom_minimum_size = Vector2(220, 0)
	var sld := HSlider.new()
	sld.min_value = sld_min
	sld.max_value = sld_max
	sld.step = sld_step
	sld.value = current_abs
	sld.custom_minimum_size = Vector2(280, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = _format_enemy_value(stat_key, mode, current_abs, current_override)
	val_lbl.set("theme_override_font_sizes/font_size", 13)
	val_lbl.custom_minimum_size = Vector2(140, 0)
	sld.value_changed.connect(func(v: float):
		var ov: float
		if mode == "mult":
			ov = (v / authored) if authored > 0.0 else 1.0
		else:
			ov = v - authored
		BalanceOverrides.set_enemy_mult(enemy_id, stat_key, ov)
		val_lbl.text = _format_enemy_value(stat_key, mode, v, ov)
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	parent.add_child(hb)


func _enemy_step_for(stat_key: String, authored: float) -> float:
	match stat_key:
		"hp_mult":     return 1.0 if authored < 50.0 else 5.0
		"speed_mult":  return 5.0
		"damage_mult": return 0.5 if authored < 20.0 else 1.0
		"gold_mult":   return 1.0
	return 1.0


func _format_enemy_value(stat_key: String, mode: String, absolute: float, override: float) -> String:
	if mode == "add":
		return "%.2f  (%+.2f)" % [absolute, override]
	# mult-mode formatters per stat: HP int, speed int, damage one decimal, gold int.
	match stat_key:
		"hp_mult":     return "%d  (×%.2f)" % [int(round(absolute)), override]
		"speed_mult":  return "%d  (×%.2f)" % [int(round(absolute)), override]
		"damage_mult": return "%.1f  (×%.2f)" % [absolute, override]
		"gold_mult":   return "%d  (×%.2f)" % [int(round(absolute)), override]
	return "%.2f  (×%.2f)" % [absolute, override]


# ── Bake current tower overrides into authored .tres files ──────────────
# Walks every tower × tier × stat, applies non-identity multipliers to the
# underlying TowerData / TowerUpgradeData property, then ResourceSaver.save
# each touched .tres so the new value becomes the authored default. Tower
# overrides are then cleared (they're now baked, redundant). Reset
# afterward returns to the just-baked values, not the original authored ones.
#
# Debug-only: ResourceSaver only writes to res:// paths in editor / debug
# builds; production exports treat res:// as read-only. The button is also
# only visible in debug builds (parent panel gated on OS.is_debug_build).

const _STAT_TO_PROPERTY: Dictionary = {
	"damage_mult": "damage",
	"range_mult": "attack_range",
	"speed_mult": "attack_speed",
	"cost_mult": "cost",
}


func _on_bake_pressed() -> void:
	var tower_deltas: Array = _collect_bake_deltas()
	var enemy_deltas: Array = _collect_enemy_bake_deltas()
	var wave_deltas: Array = _collect_wave_bake_deltas()
	if tower_deltas.is_empty() and enemy_deltas.is_empty() and wave_deltas.is_empty():
		Toast.show_message("No overrides to bake — all sliders at default")
		return
	var bits: PackedStringArray = []
	if not tower_deltas.is_empty():
		bits.append("%d field(s) across %d tower(s)" % [
			tower_deltas.size(), _unique_tower_count(tower_deltas),
		])
	if not enemy_deltas.is_empty():
		bits.append("%d field(s) across %d enemy(ies)" % [
			enemy_deltas.size(), _unique_enemy_count(enemy_deltas),
		])
	if not wave_deltas.is_empty():
		bits.append("%d wave change(s) across %d wave-list(s)" % [
			wave_deltas.size(), _unique_wave_list_count(wave_deltas),
		])
	var dlg := ConfirmationDialog.new()
	dlg.title = "Bake stats?"
	dlg.dialog_text = "%s will be written into res:// .tres files.\n\nThis modifies authored content. Use git to review or revert.\n\nProceed?" % " and ".join(bits)
	dlg.ok_button_text = "Bake"
	dlg.confirmed.connect(func():
		if not tower_deltas.is_empty():
			_apply_bake(tower_deltas)
		if not enemy_deltas.is_empty():
			_apply_enemy_bake(enemy_deltas)
			# Drop cached EnemyData snapshots so post-bake reads pick up the
			# freshly-baked authored values. Without this the charts and
			# BalanceSliders' own gold helper still report the pre-bake EHP /
			# gold_worth (cache is keyed by scene_path, frozen at first read).
			_enemy_scene_data_cache.clear()
			for entry in _wave_charts:
				var chart: Control = entry.get("chart")
				if chart != null and is_instance_valid(chart) \
						and chart.has_method("clear_enemy_caches"):
					chart.clear_enemy_caches()
		if not wave_deltas.is_empty():
			_apply_wave_bake(wave_deltas)
		# Final UI rebuild — both sections snap back to defaults; the wave
		# charts pick up the new authored numbers via _refresh_wave_charts.
		_build_enemy_section()
		_refresh_wave_charts()
		_refresh_readout()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


# Collect every tower × tier × stat with a non-identity multiplier. Returns
# Array of {tower, tier_key, stat_mult_key, property, mult, authored_value}.
# The authored_value comes from the same _authored_stat() the slider reads,
# so the bake matches what the slider was showing.
func _collect_bake_deltas() -> Array:
	var out: Array = []
	for tower in ContentRegistry.towers:
		if tower == null or not (tower is TowerData):
			continue
		for tier_key in _TOWER_TIER_KEYS:
			# Skip tiers that don't exist on this tower (e.g. branches when
			# the tower has no L3 branches authored). _level_override_for
			# returns null in that case.
			if not _tier_exists(tower, tier_key):
				continue
			for stat in _TOWER_STAT_KEYS:
				var mult: float = BalanceOverrides.get_tower_mult(tower.tower_id, tier_key, stat)
				if absf(mult - 1.0) < 0.0001:
					continue
				var authored: float = _authored_stat(tower, tier_key, stat)
				if authored <= 0.0:
					continue  # nothing to multiply against; skip silently
				out.append({
					"tower": tower,
					"tier_key": tier_key,
					"stat": stat,
					"property": _bake_property_for(tower, stat),
					"mult": mult,
					"authored": authored,
					"new_value": authored * mult,
				})
	return out


# Resolve which authored field a stat-mult writes back to. The default
# `_STAT_TO_PROPERTY` map is correct for combat towers, but barracks store
# their range in `soldier_rally_range` (not `attack_range`, which stays 0).
# Without this override the bake silently writes the rally value into a
# field the runtime never reads, leaving barracks corrupted.
func _bake_property_for(tower: TowerData, stat: String) -> String:
	if stat == "range_mult" and tower.is_barracks():
		return "soldier_rally_range"
	return _STAT_TO_PROPERTY[stat]


# Resolve which tier exists on a given tower. L1 always exists; upgrades
# exist when the array slot is populated. Mirrors _bake_target_for so we
# never collect a delta we can't apply.
func _tier_exists(tower: TowerData, tier_key: String) -> bool:
	match tier_key:
		"l1":
			return true
		"l2":
			return tower.level_upgrades != null and tower.level_upgrades.size() > 0
		"l3_linear":
			# L3 linear is only meaningful when no branches exist (per CLAUDE.md
			# branches override the linear L3). Even when branches exist, the
			# l3_linear slider isn't shown — but check defensively here.
			return tower.level_upgrades != null and tower.level_upgrades.size() > 1 \
					and (tower.level_3_branches == null or tower.level_3_branches.is_empty())
		"branch_a":
			return tower.level_3_branches != null and tower.level_3_branches.size() > 0
		"branch_b":
			return tower.level_3_branches != null and tower.level_3_branches.size() > 1
	return false


# Returns the Resource that owns the property for a given tier_key. L1 is
# the TowerData itself; upgrades + branches are nested sub-resources.
func _bake_target_for(tower: TowerData, tier_key: String) -> Resource:
	match tier_key:
		"l1":
			return tower
		"l2":
			return tower.level_upgrades[0]
		"l3_linear":
			return tower.level_upgrades[1]
		"branch_a":
			return tower.level_3_branches[0]
		"branch_b":
			return tower.level_3_branches[1]
	return null


func _unique_tower_count(deltas: Array) -> int:
	var seen: Dictionary = {}
	for d in deltas:
		seen[d.tower.tower_id] = true
	return seen.size()


# Walk every enemy × stat with a non-default override. Mirrors the tower
# collector but operates on EnemyData (no nested sub-resources). Each delta
# is {enemy, stat_key, mode, property, override, authored, new_value}.
func _collect_enemy_bake_deltas() -> Array:
	var out: Array = []
	for enemy in ContentRegistry.enemies:
		if enemy == null or not (enemy is EnemyData) or String(enemy.enemy_id) == "":
			continue
		for stat_def in _ENEMY_STAT_DEFS:
			var stat_key: String = String(stat_def.key)
			var mode: String = String(stat_def.mode)
			var prop: String = String(stat_def.prop)
			if not (prop in enemy):
				continue
			var override: float = BalanceOverrides.get_enemy_mult(String(enemy.enemy_id), stat_key)
			var default: float = 0.0 if mode == "add" else 1.0
			if absf(override - default) < 0.0001:
				continue
			var authored: float = float(enemy.get(prop))
			var new_val: float
			if mode == "mult":
				if authored <= 0.0:
					continue  # nothing to multiply against
				new_val = authored * override
			else:
				new_val = clampf(authored + override, 0.0, 0.95)
			out.append({
				"enemy": enemy,
				"stat_key": stat_key,
				"mode": mode,
				"property": prop,
				"override": override,
				"authored": authored,
				"new_value": new_val,
			})
	return out


func _unique_enemy_count(deltas: Array) -> int:
	var seen: Dictionary = {}
	for d in deltas:
		seen[d.enemy.enemy_id] = true
	return seen.size()


func _apply_enemy_bake(deltas: Array) -> void:
	var enemies_touched: Dictionary = {}
	var summary_lines: PackedStringArray = []
	for d in deltas:
		var enemy: Resource = d.enemy
		if enemy == null:
			continue
		var prop: String = String(d.property)
		var authored: float = float(d.authored)
		var new_val: float = float(d.new_value)
		# max_health and gold_worth are int; the rest are float. Round ints.
		if prop == "max_health" or prop == "gold_worth":
			var iv: int = int(round(new_val))
			enemy.set(prop, iv)
			summary_lines.append("  %s %s  %d → %d (%s %.2f)" % [
				enemy.enemy_id, prop, int(round(authored)), iv,
				"+" if d.mode == "add" else "×", float(d.override),
			])
		else:
			enemy.set(prop, new_val)
			summary_lines.append("  %s %s  %.2f → %.2f (%s %.2f)" % [
				enemy.enemy_id, prop, authored, new_val,
				"+" if d.mode == "add" else "×", float(d.override),
			])
		enemies_touched[String(enemy.enemy_id)] = enemy
	var save_failures: PackedStringArray = []
	for eid in enemies_touched.keys():
		var enemy: Resource = enemies_touched[eid]
		var path: String = String(enemy.resource_path)
		if path == "":
			save_failures.append(eid + " (no resource_path)")
			continue
		var err: int = ResourceSaver.save(enemy, path)
		if err != OK:
			save_failures.append("%s (err %d)" % [eid, err])
	print("[BalanceSliders/Bake] Wrote %d enemy field(s) across %d enemy(ies):" % [
		deltas.size(), enemies_touched.size(),
	])
	for line in summary_lines:
		print(line)
	if not save_failures.is_empty():
		push_warning("[BalanceSliders/Bake] enemy save failures: " + ", ".join(save_failures))
	BalanceOverrides.reset_enemy_overrides()


# Walk every level × wave for active count or countdown overrides. Each delta
# resolves to a sub-resource (WaveSpawn for count, WaveData for countdown) on
# the level's wave_list, so a single wave_list save cascades all changes for
# that level. `kind` discriminator selects which property the apply step writes.
#
# Count delta: {kind:"count", wave_list, level_id, wave_idx, spawn_idx, spawn,
#               authored, mult, new_count}
# Countdown delta: {kind:"countdown", wave_list, level_id, wave_idx, wave,
#                   authored, new_seconds}
func _collect_wave_bake_deltas() -> Array:
	var out: Array = []
	for lvl in _levels:
		if lvl == null or not ("level_id" in lvl) or String(lvl.level_id) == "":
			continue
		var wl_path: String = String(lvl.wave_list_path) if "wave_list_path" in lvl else ""
		if wl_path == "":
			continue
		var wave_list: WaveList = load(wl_path)
		if wave_list == null:
			continue
		for wi in range(wave_list.waves.size()):
			var wave: WaveData = wave_list.waves[wi]
			if wave == null:
				continue
			# Count overrides per emitter.
			for si in range(wave.spawns.size()):
				var spawn: Resource = wave.spawns[si]
				if spawn == null:
					continue
				var mult: float = BalanceOverrides.get_wave_count_mult(
					String(lvl.level_id), wi, si
				)
				if absf(mult - 1.0) < 0.0001:
					continue
				var authored: int = int(spawn.count)
				if authored <= 0:
					continue
				out.append({
					"kind": "count",
					"wave_list": wave_list,
					"level_id": String(lvl.level_id),
					"wave_idx": wi,
					"spawn_idx": si,
					"spawn": spawn,
					"authored": authored,
					"mult": mult,
					"new_count": max(0, int(round(float(authored) * mult))),
				})
			# Countdown override (per wave). Stored as absolute seconds,
			# sentinel -1 means "use authored" (skip).
			var cd_ov: int = BalanceOverrides.get_wave_countdown(
				String(lvl.level_id), wi
			)
			if cd_ov >= 0:
				var authored_cd: int = int(wave.countdown) if "countdown" in wave else 0
				if cd_ov != authored_cd:
					out.append({
						"kind": "countdown",
						"wave_list": wave_list,
						"level_id": String(lvl.level_id),
						"wave_idx": wi,
						"wave": wave,
						"authored": authored_cd,
						"new_seconds": cd_ov,
					})
			# Per-wave early-call window override → bakes to
			# WaveData.early_call_window_sec (-1 = inherit level).
			var ec_ov: float = BalanceOverrides.get_wave_early_call_window(
				String(lvl.level_id), wi
			)
			if ec_ov >= 0.0:
				var authored_ec: float = -1.0
				if "early_call_window_sec" in wave:
					authored_ec = float(wave.early_call_window_sec)
				if absf(ec_ov - authored_ec) > 0.0001:
					out.append({
						"kind": "early_call",
						"wave_list": wave_list,
						"level_id": String(lvl.level_id),
						"wave_idx": wi,
						"wave": wave,
						"authored": authored_ec,
						"new_seconds": ec_ov,
					})
			# Interval + start_delay overrides per emitter (absolute seconds,
			# sentinel -1 = use authored).
			for si2 in range(wave.spawns.size()):
				var spawn2: Resource = wave.spawns[si2]
				if spawn2 == null:
					continue
				var int_ov: float = BalanceOverrides.get_wave_interval(
					String(lvl.level_id), wi, si2
				)
				if int_ov >= 0.0 and absf(int_ov - float(spawn2.interval)) > 0.0001:
					out.append({
						"kind": "interval",
						"wave_list": wave_list,
						"level_id": String(lvl.level_id),
						"wave_idx": wi,
						"spawn_idx": si2,
						"spawn": spawn2,
						"authored": float(spawn2.interval),
						"new_seconds": int_ov,
					})
				var dly_ov: float = BalanceOverrides.get_wave_delay(
					String(lvl.level_id), wi, si2
				)
				if dly_ov >= 0.0 and absf(dly_ov - float(spawn2.start_delay)) > 0.0001:
					out.append({
						"kind": "delay",
						"wave_list": wave_list,
						"level_id": String(lvl.level_id),
						"wave_idx": wi,
						"spawn_idx": si2,
						"spawn": spawn2,
						"authored": float(spawn2.start_delay),
						"new_seconds": dly_ov,
					})
	return out


func _unique_wave_list_count(deltas: Array) -> int:
	var seen: Dictionary = {}
	for d in deltas:
		seen[d.level_id] = true
	return seen.size()


func _apply_wave_bake(deltas: Array) -> void:
	var lists_touched: Dictionary = {}   # level_id → wave_list (for save)
	var summary_lines: PackedStringArray = []
	for d in deltas:
		var kind: String = String(d.get("kind", "count"))
		match kind:
			"count":
				var spawn: Resource = d.spawn
				if spawn == null:
					continue
				spawn.set("count", int(d.new_count))
				summary_lines.append("  %s W%d emitter[%d]  %d → %d (×%.2f)" % [
					String(d.level_id), int(d.wave_idx) + 1, int(d.spawn_idx),
					int(d.authored), int(d.new_count), float(d.mult),
				])
			"countdown":
				var wave: Resource = d.wave
				if wave == null:
					continue
				wave.set("countdown", float(d.new_seconds))
				summary_lines.append("  %s W%d countdown  %ds → %ds" % [
					String(d.level_id), int(d.wave_idx) + 1,
					int(d.authored), int(d.new_seconds),
				])
			"early_call":
				var wave_ec: Resource = d.wave
				if wave_ec == null:
					continue
				wave_ec.set("early_call_window_sec", float(d.new_seconds))
				var auth_str: String = "inherit" if float(d.authored) < 0.0 else "%.0fs" % float(d.authored)
				summary_lines.append("  %s W%d early-call window  %s → %.0fs" % [
					String(d.level_id), int(d.wave_idx) + 1,
					auth_str, float(d.new_seconds),
				])
			"interval":
				var spawn3: Resource = d.spawn
				if spawn3 == null:
					continue
				spawn3.set("interval", float(d.new_seconds))
				summary_lines.append("  %s W%d emitter[%d] interval  %.1fs → %.1fs" % [
					String(d.level_id), int(d.wave_idx) + 1, int(d.spawn_idx),
					float(d.authored), float(d.new_seconds),
				])
			"delay":
				var spawn4: Resource = d.spawn
				if spawn4 == null:
					continue
				spawn4.set("start_delay", float(d.new_seconds))
				summary_lines.append("  %s W%d emitter[%d] start_delay  %.1fs → %.1fs" % [
					String(d.level_id), int(d.wave_idx) + 1, int(d.spawn_idx),
					float(d.authored), float(d.new_seconds),
				])
		lists_touched[String(d.level_id)] = d.wave_list
	var save_failures: PackedStringArray = []
	for lid in lists_touched.keys():
		var wave_list: Resource = lists_touched[lid]
		var path: String = String(wave_list.resource_path)
		if path == "":
			save_failures.append(lid + " (no resource_path)")
			continue
		var err: int = ResourceSaver.save(wave_list, path)
		if err != OK:
			save_failures.append("%s (err %d)" % [lid, err])
	print("[BalanceSliders/Bake] Wrote %d wave change(s) across %d wave-list(s):" % [
		deltas.size(), lists_touched.size(),
	])
	for line in summary_lines:
		print(line)
	if not save_failures.is_empty():
		push_warning("[BalanceSliders/Bake] wave save failures: " + ", ".join(save_failures))
	BalanceOverrides.reset_wave_overrides()
	BalanceOverrides.reset_wave_countdown_overrides()
	BalanceOverrides.reset_wave_timing_overrides()
	BalanceOverrides.reset_wave_early_call_overrides()


func _apply_bake(deltas: Array) -> void:
	var towers_touched: Dictionary = {}
	var summary_lines: PackedStringArray = []
	for d in deltas:
		var target: Resource = _bake_target_for(d.tower, d.tier_key)
		if target == null:
			continue
		var prop: String = String(d.property)
		var mult: float = float(d.mult)
		var authored: float = float(d.authored)
		var new_val: float = authored * mult
		# cost is int; everything else float. Round cost to nearest int.
		if prop == "cost":
			var iv: int = int(round(new_val))
			target.set(prop, iv)
			summary_lines.append("  %s %s.%s  %d → %d (×%.2f)" % [
				d.tower.tower_id, d.tier_key, prop, int(round(authored)), iv, mult,
			])
		else:
			target.set(prop, new_val)
			summary_lines.append("  %s %s.%s  %.2f → %.2f (×%.2f)" % [
				d.tower.tower_id, d.tier_key, prop, authored, new_val, mult,
			])
		towers_touched[d.tower.tower_id] = d.tower
	# Save each touched TowerData. ResourceSaver cascades sub-resource writes
	# inline for resources that live as SubResource("...") in the parent .tres.
	var save_failures: PackedStringArray = []
	for tid in towers_touched.keys():
		var tower: TowerData = towers_touched[tid]
		var path: String = String(tower.resource_path)
		if path == "":
			save_failures.append(tid + " (no resource_path)")
			continue
		var err: int = ResourceSaver.save(tower, path)
		if err != OK:
			save_failures.append("%s (err %d)" % [tid, err])
	# Console summary — designer reads this to confirm what landed on disk.
	print("[BalanceSliders/Bake] Wrote %d field(s) across %d tower(s):" % [
		deltas.size(), towers_touched.size(),
	])
	for line in summary_lines:
		print(line)
	if not save_failures.is_empty():
		push_warning("[BalanceSliders/Bake] save failures: " + ", ".join(save_failures))
		Toast.show_message("Bake completed with %d save failure(s) — see console" % save_failures.size())
	else:
		Toast.show_message("Baked %d field(s) into %d .tres file(s)" % [
			deltas.size(), towers_touched.size(),
		])
	# Clear tower overrides — now baked into .tres, the multipliers are
	# redundant (and would re-apply on top of the new authored values).
	BalanceOverrides.reset_tower_overrides()
	# Rebuild the tower section so sliders snap back to ×1.00 against the
	# just-baked authored values. Summary grid + readout follow.
	_build_tower_section()
	_refresh_readout()


# ── Tower overrides section ──────────────────────────────────────────────
# Per-tower-tier multipliers for damage / range / speed / cost. Folded into
# BaseTower.get_effective_* + TowerPlacer build cost + TowerData display
# preview. See balance/debug/BalanceOverrides.gd "tower_overrides" sub-dict.

const _TOWER_TIER_KEYS := ["l1", "l2", "l3_linear", "branch_a", "branch_b"]
const _TOWER_STAT_KEYS := ["damage_mult", "range_mult", "speed_mult", "cost_mult"]

# Target g/DPS bands per tier — sourced from balance/BALANCE.md §"Per-tower
# g/DPS bands". Values inside the band paint green, ±20% paint yellow, beyond
# that paint red. Update both this table AND BALANCE.md when retuning.
const _TIER_GDPS_BANDS: Dictionary = {
	"l1":        Vector2(16.0, 22.0),
	"l2":        Vector2(10.0, 13.0),
	"l3_linear": Vector2( 7.0,  9.0),
	"branch_a":  Vector2( 8.0, 10.0),
	"branch_b":  Vector2( 8.0, 10.0),
}


func _build_tower_section() -> void:
	for c in tower_section.get_children():
		c.queue_free()
	_tower_value_labels.clear()
	_tier_metric_labels.clear()
	_summary_grid = null
	_history_cache = []
	var heading := Label.new()
	heading.text = "Tower overrides — per-tier multipliers (1.0 = no change)"
	heading.set("theme_override_font_sizes/font_size", 22)
	heading.modulate = Color(1.0, 0.9, 0.5, 1)
	tower_section.add_child(heading)
	_add_summary_grid(tower_section)
	for tower in ContentRegistry.towers:
		if tower == null or not ("tower_id" in tower) or tower.tower_id == "":
			continue
		_add_tower_subgroup(tower)
	# Initial paint of derived metrics — sliders haven't moved yet but the
	# header rows still need their first values.
	_refresh_all_metrics()


func _add_tower_subgroup(tower: TowerData) -> void:
	var group := VBoxContainer.new()
	group.set("theme_override_constants/separation", 2)
	# Header (tap to expand/collapse).
	var hdr := Button.new()
	hdr.text = "▸ %s   (%s)" % [tower.tower_name, tower.tower_id]
	hdr.flat = true
	hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.set("theme_override_font_sizes/font_size", 18)
	hdr.modulate = Color(0.85, 0.95, 1.0)
	var body := VBoxContainer.new()
	body.set("theme_override_constants/separation", 2)
	body.visible = false
	hdr.pressed.connect(func():
		body.visible = not body.visible
		hdr.text = ("▾ " if body.visible else "▸ ") + tower.tower_name + "   (" + tower.tower_id + ")")
	for tier_key in _TOWER_TIER_KEYS:
		if not _tower_has_tier(tower, tier_key):
			continue
		_add_tower_tier_block(body, tower, tier_key)
	group.add_child(hdr)
	group.add_child(body)
	tower_section.add_child(group)


# Returns true when the tower actually authors the given tier — skip absent
# tiers so we don't render meaningless sliders for, say, an L3 linear when
# the tower has branches authored instead.
func _tower_has_tier(tower: TowerData, tier_key: String) -> bool:
	if tower == null:
		return false
	match tier_key:
		"l1":
			return true
		"l2":
			return tower.level_upgrades.size() >= 1
		"l3_linear":
			return tower.level_3_branches.is_empty() and tower.level_upgrades.size() >= 2
		"branch_a":
			return tower.level_3_branches.size() >= 1
		"branch_b":
			return tower.level_3_branches.size() >= 2
	return false


func _add_tower_tier_block(parent: VBoxContainer, tower: TowerData, tier_key: String) -> void:
	var tier_label := Label.new()
	tier_label.text = "    " + _tier_display_name(tier_key)
	tier_label.set("theme_override_font_sizes/font_size", 14)
	tier_label.modulate = Color(0.8, 0.85, 0.8)
	parent.add_child(tier_label)
	_add_tier_header_row(parent, tower, tier_key)
	for stat in _TOWER_STAT_KEYS:
		var authored: float = _authored_stat(tower, tier_key, stat)
		# Skip irrelevant stats (e.g. damage/speed on a barracks where
		# tower.damage = 0). Keeps the panel honest.
		if authored <= 0.0:
			continue
		_add_tower_slider(parent, tower.tower_id, tier_key, stat, authored)
	_add_tier_footer_row(parent, tower, tier_key)


# Pretty tier label for the panel — "L1" reads better than "l1", etc.
func _tier_display_name(tier_key: String) -> String:
	match tier_key:
		"l1": return "L1"
		"l2": return "L2"
		"l3_linear": return "L3"
		"branch_a": return "L3 branch A"
		"branch_b": return "L3 branch B"
	return tier_key


# Authored value for a (tower, tier, stat) tuple. Mirrors the inheritance
# rules used by base_tower._level_override / TowerUpgradeData.get_preview_stats:
# upgrade overrides at 0 fall back to the base TowerData. Returns 0 when
# the stat is irrelevant for that tower (e.g. damage on a barracks).
func _authored_stat(tower: TowerData, tier_key: String, stat: String) -> float:
	if tower == null:
		return 0.0
	var ov: Resource = null
	match tier_key:
		"l2":
			if tower.level_upgrades.size() >= 1:
				ov = tower.level_upgrades[0]
		"l3_linear":
			if tower.level_upgrades.size() >= 2:
				ov = tower.level_upgrades[1]
		"branch_a":
			if tower.level_3_branches.size() >= 1:
				ov = tower.level_3_branches[0]
		"branch_b":
			if tower.level_3_branches.size() >= 2:
				ov = tower.level_3_branches[1]
	match stat:
		"damage_mult":
			if ov != null and ov.damage > 0.0:
				return ov.damage
			return tower.damage
		"range_mult":
			if tower.is_barracks():
				if ov != null and ov.soldier_rally_range > 0.0:
					return ov.soldier_rally_range
				return tower.soldier_rally_range
			if ov != null and ov.attack_range > 0.0:
				return ov.attack_range
			return tower.attack_range
		"speed_mult":
			if ov != null and ov.attack_speed > 0.0:
				return ov.attack_speed
			return tower.attack_speed
		"cost_mult":
			if ov != null:
				return float(ov.cost)
			return float(tower.cost)
	return 0.0


# Slider step appropriate for the stat's typical magnitude.
func _step_for_stat(stat: String, authored: float) -> float:
	match stat:
		"damage_mult":
			return 0.5 if authored < 20.0 else 1.0
		"range_mult":
			return 5.0
		"speed_mult":
			return 0.05
		"cost_mult":
			return 5.0 if authored >= 50.0 else 1.0
	return 1.0


# Format a stat's absolute value + multiplier for the value label.
func _format_stat_value(stat: String, absolute: float, mult: float) -> String:
	match stat:
		"damage_mult":
			return "%.1f  (×%.2f)" % [absolute, mult]
		"range_mult":
			return "%d  (×%.2f)" % [int(round(absolute)), mult]
		"speed_mult":
			return "%.2f  (×%.2f)" % [absolute, mult]
		"cost_mult":
			return "%d g  (×%.2f)" % [int(round(absolute)), mult]
	return "%.2f" % absolute


# Friendly label shown left of the slider — "Dmg" reads faster than "damage_mult".
func _stat_display_name(stat: String) -> String:
	match stat:
		"damage_mult": return "Dmg"
		"range_mult":  return "Rng"
		"speed_mult":  return "Spd"
		"cost_mult":   return "Cost"
	return stat


# Slider operates on absolute values (so you read "Dmg 7" not "1.4×"), but
# storage stays as multipliers — that way overrides scale automatically if
# you later rebalance authored .tres values. mult = absolute / authored.
func _add_tower_slider(parent: VBoxContainer, tower_id: String, tier_key: String,
		stat: String, authored: float) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "        " + _stat_display_name(stat)
	name_lbl.set("theme_override_font_sizes/font_size", 13)
	name_lbl.custom_minimum_size = Vector2(220, 0)
	var current_mult: float = BalanceOverrides.get_tower_mult(tower_id, tier_key, stat)
	var current_abs: float = authored * current_mult
	var sld := HSlider.new()
	sld.min_value = 0.0
	sld.max_value = authored * 3.0
	sld.step = _step_for_stat(stat, authored)
	sld.value = current_abs
	sld.custom_minimum_size = Vector2(280, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = _format_stat_value(stat, current_abs, current_mult)
	val_lbl.set("theme_override_font_sizes/font_size", 13)
	val_lbl.custom_minimum_size = Vector2(140, 0)
	sld.value_changed.connect(func(v: float):
		var m: float = (v / authored) if authored > 0.0 else 1.0
		BalanceOverrides.set_tower_mult(tower_id, tier_key, stat, m)
		val_lbl.text = _format_stat_value(stat, v, m)
		# Live recompute every tier's derived metrics + summary grid: a cost
		# tweak on Mage L2 changes its g/DPS AND can shift "best at L2" for
		# every other tower's footer comparator, so it's cheaper to refresh
		# everything than to track dependency edges.
		_refresh_all_metrics())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	parent.add_child(hb)
	_tower_value_labels[tower_id + "|" + tier_key + "|" + stat] = val_lbl


# ── Level overrides section ──────────────────────────────────────────────
# Per-level: starting_gold, starting_lives (sentinel -1 = no override),
# hp_mult (multiplied with global hp_mult). See BalanceOverrides.gd
# "level_overrides" sub-dict.

func _build_level_section() -> void:
	for c in level_section.get_children():
		c.queue_free()
	_level_value_labels.clear()
	_wave_charts.clear()
	var heading := Label.new()
	heading.text = "Level overrides"
	heading.set("theme_override_font_sizes/font_size", 22)
	heading.modulate = Color(1.0, 0.9, 0.5, 1)
	level_section.add_child(heading)
	for lvl in _levels:
		if lvl == null or not ("level_id" in lvl) or lvl.level_id == "":
			continue
		_add_level_subgroup(lvl)


func _add_level_subgroup(lvl: Resource) -> void:
	var group := VBoxContainer.new()
	group.set("theme_override_constants/separation", 2)
	var hdr := Button.new()
	hdr.text = "▸ %s   (%s)" % [lvl.display_name, lvl.level_id]
	hdr.flat = true
	hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.set("theme_override_font_sizes/font_size", 18)
	hdr.modulate = Color(0.85, 0.95, 1.0)
	var body := VBoxContainer.new()
	body.set("theme_override_constants/separation", 2)
	body.visible = false
	hdr.pressed.connect(func():
		body.visible = not body.visible
		hdr.text = ("▾ " if body.visible else "▸ ") + lvl.display_name + "   (" + lvl.level_id + ")")
	# Three rows: starting_gold (int with -1 sentinel), starting_lives, hp_mult.
	_add_level_int_slider(body, lvl.level_id, "starting_gold", -1, 2000, 25)
	_add_level_int_slider(body, lvl.level_id, "starting_lives", -1, 100, 1)
	_add_level_float_slider(body, lvl.level_id, "hp_mult", 0.5, 3.0, 0.05)
	# Early-call bonus window — caps `bonus = min(seconds_remaining, window)`.
	# Higher → bigger reward for early calls (more gold per skipped second).
	# 0 → early-call gives no gold (pure pressure / time-skip option).
	# Sentinel -1 = use level_data.early_call_window_sec (authored, default 10).
	_add_level_int_slider(body, lvl.level_id, "early_call_window", -1, 40, 1)
	# v1: wave-timeline charts only for Level 5. Removing the guard extends to
	# every level once the visual is validated.
	if String(lvl.level_id) == "level_5":
		_add_wave_timeline_block(body, lvl)
	group.add_child(hdr)
	group.add_child(body)
	level_section.add_child(group)


func _add_wave_timeline_block(parent: VBoxContainer, lvl: Resource) -> void:
	var wave_list: WaveList = load(String(lvl.wave_list_path)) if "wave_list_path" in lvl else null
	if wave_list == null or wave_list.waves.is_empty():
		return
	var paths: Array = _collect_paths(wave_list)
	# Collapsible toggle so the level group doesn't balloon by default.
	var toggle := Button.new()
	toggle.text = "        ▸ Show wave timelines (%d)" % wave_list.waves.size()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.set("theme_override_font_sizes/font_size", 14)
	toggle.modulate = Color(0.85, 0.95, 1.0)
	var charts_box := VBoxContainer.new()
	charts_box.set("theme_override_constants/separation", 6)
	charts_box.visible = false
	toggle.pressed.connect(func():
		charts_box.visible = not charts_box.visible
		toggle.text = ("        ▾ " if charts_box.visible else "        ▸ ") \
			+ "Show wave timelines (%d)" % wave_list.waves.size())
	parent.add_child(toggle)
	parent.add_child(charts_box)
	# Overview chart at the top — shows level-arc EHP bars + cumulative gold
	# curve so the spike-vs-rest pacing is visible at a glance before any
	# per-wave detail card is read.
	var overview: Control = _LevelOverviewChartScript.new()
	charts_box.add_child(overview)
	overview.set_data(wave_list, lvl, _compute_starting_gold(lvl))
	_wave_charts.append({
		"chart": overview, "is_overview": true,
		"wave_list": wave_list, "level_data": lvl,
	})
	# Level-wide cumulative gold ceiling — shared y-axis anchor for every
	# per-wave gold curve, so stacked cards form a continuous-looking line.
	var level_final_gold: int = _compute_level_final_gold(wave_list, lvl)
	# One detail chart per wave + a collapsible per-emitter editor below it.
	for i in range(wave_list.waves.size()):
		var wave: WaveData = wave_list.waves[i]
		if wave == null:
			continue
		var chart: Control = _WaveTimelineChartScript.new()
		charts_box.add_child(chart)
		var supply: float = _compute_l1_dmg_per_gold(wave)
		var gold: int = _compute_gold_at_wave_start(wave_list, i, lvl)
		chart.set_data(wave, lvl, i, supply, gold, paths, level_final_gold)
		_wave_charts.append({
			"chart": chart, "wave_index": i, "level_data": lvl,
			"wave_list": wave_list, "paths": paths,
		})
		_add_wave_emitter_editor(charts_box, wave, i, lvl)


# Per-wave emitter editor — collapsible row that lists each WaveSpawn with a
# count slider. Edits write to BalanceOverrides.wave_overrides; charts redraw
# live; Bake button writes back to the .tres. Read-only metadata (path_id,
# interval, start_delay) is surfaced beside each slider so the designer can
# see context without editing those fields (deferred to v2).
func _add_wave_emitter_editor(parent: VBoxContainer, wave: WaveData, wave_idx: int, lvl: Resource) -> void:
	if wave == null or wave.spawns.is_empty():
		return
	var toggle := Button.new()
	toggle.text = "        ▸ Edit emitters (%d)" % wave.spawns.size()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.set("theme_override_font_sizes/font_size", 13)
	toggle.modulate = Color(0.85, 0.95, 1.0)
	var body := VBoxContainer.new()
	body.set("theme_override_constants/separation", 2)
	body.visible = false
	toggle.pressed.connect(func():
		body.visible = not body.visible
		toggle.text = ("        ▾ " if body.visible else "        ▸ ") \
			+ "Edit emitters (%d)" % wave.spawns.size())
	parent.add_child(toggle)
	parent.add_child(body)
	# Countdown slider sits at the TOP of the emitter list — biggest pacing
	# knob, designer hits it first. Sentinel -1 = "use authored".
	_add_wave_countdown_slider(body, wave, lvl, wave_idx)
	# Per-wave early-call window override (KR-style — different windows per
	# wave intent). Sentinel -1 = "inherit level / authored chain".
	_add_wave_early_call_slider(body, wave, lvl, wave_idx)
	for spawn_idx in range(wave.spawns.size()):
		var spawn: Resource = wave.spawns[spawn_idx]
		if spawn == null:
			continue
		_add_emitter_slider(body, spawn, lvl, wave_idx, spawn_idx)


func _add_wave_countdown_slider(parent: VBoxContainer, wave: WaveData, lvl: Resource,
		wave_idx: int) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "            countdown"
	name_lbl.set("theme_override_font_sizes/font_size", 12)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	var authored: int = int(wave.countdown) if "countdown" in wave else 0
	var current: int = BalanceOverrides.get_wave_countdown(String(lvl.level_id), wave_idx)
	var sld := HSlider.new()
	sld.min_value = -1   # sentinel = use authored
	sld.max_value = 60
	sld.step = 1
	sld.value = current
	sld.custom_minimum_size = Vector2(240, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = ("default %ds" % authored) if current < 0 else "%ds  (authored %ds)" % [current, authored]
	val_lbl.set("theme_override_font_sizes/font_size", 12)
	val_lbl.custom_minimum_size = Vector2(160, 0)
	# Right-side context label so the row layout matches emitter rows.
	var meta_lbl := Label.new()
	meta_lbl.text = "−1 = use authored"
	meta_lbl.set("theme_override_font_sizes/font_size", 11)
	meta_lbl.modulate = Color(0.55, 0.60, 0.68)
	meta_lbl.custom_minimum_size = Vector2(220, 0)
	sld.value_changed.connect(func(v: float):
		var iv: int = int(v)
		BalanceOverrides.set_wave_countdown(String(lvl.level_id), wave_idx, iv)
		val_lbl.text = ("default %ds" % authored) if iv < 0 else "%ds  (authored %ds)" % [iv, authored]
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	hb.add_child(meta_lbl)
	parent.add_child(hb)


# Per-wave early-call window slider. Resolution chain (top wins):
#   1. This slider's value (sentinel -1 = inherit chain below).
#   2. WaveData.early_call_window_sec (per-wave authored, -1 = inherit).
#   3. Level slider override (BalanceSliders Level overrides group).
#   4. LevelNodeData.early_call_window_sec (authored, default 10s).
# The "authored fallback" value shown next to the slider is the
# already-resolved wave-or-level authored value — what the player would get
# if this slider stays at -1.
func _add_wave_early_call_slider(parent: VBoxContainer, wave: WaveData, lvl: Resource,
		wave_idx: int) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "            early-call window"
	name_lbl.set("theme_override_font_sizes/font_size", 12)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	# Resolved authored fallback: per-wave WaveData value if set, else level value.
	var fallback: float = float(lvl.early_call_window_sec) if "early_call_window_sec" in lvl else 10.0
	if "early_call_window_sec" in wave and wave.early_call_window_sec >= 0.0:
		fallback = float(wave.early_call_window_sec)
	var current: float = BalanceOverrides.get_wave_early_call_window(String(lvl.level_id), wave_idx)
	var sld := HSlider.new()
	sld.min_value = -1.0   # sentinel = inherit chain
	sld.max_value = 40.0
	sld.step = 1.0
	sld.value = current
	sld.custom_minimum_size = Vector2(240, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = ("inherit %.0fs" % fallback) if current < 0.0 else "%.0fs  (inherit %.0fs)" % [current, fallback]
	val_lbl.set("theme_override_font_sizes/font_size", 12)
	val_lbl.custom_minimum_size = Vector2(160, 0)
	var meta_lbl := Label.new()
	meta_lbl.text = "−1 = inherit (level / authored)"
	meta_lbl.set("theme_override_font_sizes/font_size", 11)
	meta_lbl.modulate = Color(0.55, 0.60, 0.68)
	meta_lbl.custom_minimum_size = Vector2(220, 0)
	sld.value_changed.connect(func(v: float):
		BalanceOverrides.set_wave_early_call_window(String(lvl.level_id), wave_idx, v)
		val_lbl.text = ("inherit %.0fs" % fallback) if v < 0.0 else "%.0fs  (inherit %.0fs)" % [v, fallback]
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	hb.add_child(meta_lbl)
	parent.add_child(hb)


func _add_emitter_slider(parent: VBoxContainer, spawn: Resource, lvl: Resource,
		wave_idx: int, spawn_idx: int) -> void:
	# Three rows per emitter: count (mult), rate (absolute s, sentinel-1), delay
	# (absolute s, sentinel -1). Class name + path on the count row only;
	# rate / delay rows indent further so the visual grouping is obvious.
	var class_key: String = "basic"
	if spawn.enemy_scene != null:
		var lower: String = String(spawn.enemy_scene.resource_path).to_lower()
		if lower.contains("boss"): class_key = "boss"
		elif lower.contains("scout"): class_key = "scout"
		elif lower.contains("armor"): class_key = "armored"
		elif lower.contains("flying"): class_key = "flying"
		elif lower.contains("brute"): class_key = "brute"
		elif lower.contains("healer"): class_key = "healer"
	_add_emitter_count_row(parent, spawn, lvl, wave_idx, spawn_idx, class_key)
	_add_emitter_rate_row(parent, spawn, lvl, wave_idx, spawn_idx)
	_add_emitter_delay_row(parent, spawn, lvl, wave_idx, spawn_idx)


func _add_emitter_count_row(parent: VBoxContainer, spawn: Resource, lvl: Resource,
		wave_idx: int, spawn_idx: int, class_key: String) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "            %s   count" % class_key
	name_lbl.set("theme_override_font_sizes/font_size", 12)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	var authored: int = int(spawn.count)
	var current_mult: float = BalanceOverrides.get_wave_count_mult(
		String(lvl.level_id), wave_idx, spawn_idx
	)
	var current_abs: int = max(0, int(round(float(authored) * current_mult)))
	var sld := HSlider.new()
	sld.min_value = 0
	sld.max_value = max(authored * 3, 50)
	sld.step = 1
	sld.value = current_abs
	sld.custom_minimum_size = Vector2(240, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = "%d  (×%.2f)" % [current_abs, current_mult]
	val_lbl.set("theme_override_font_sizes/font_size", 12)
	val_lbl.custom_minimum_size = Vector2(110, 0)
	# Path label on the count row only — emitter identity context.
	var meta_lbl := Label.new()
	meta_lbl.text = String(spawn.path_id)
	meta_lbl.set("theme_override_font_sizes/font_size", 11)
	meta_lbl.modulate = Color(0.55, 0.60, 0.68)
	meta_lbl.custom_minimum_size = Vector2(220, 0)
	sld.value_changed.connect(func(v: float):
		var iv: int = int(v)
		var m: float = (float(iv) / float(authored)) if authored > 0 else 1.0
		BalanceOverrides.set_wave_count_mult(String(lvl.level_id), wave_idx, spawn_idx, m)
		val_lbl.text = "%d  (×%.2f)" % [iv, m]
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	hb.add_child(meta_lbl)
	parent.add_child(hb)


func _add_emitter_rate_row(parent: VBoxContainer, spawn: Resource, lvl: Resource,
		wave_idx: int, spawn_idx: int) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "                 rate"
	name_lbl.set("theme_override_font_sizes/font_size", 12)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	var authored: float = float(spawn.interval)
	var current: float = BalanceOverrides.get_wave_interval(
		String(lvl.level_id), wave_idx, spawn_idx
	)
	var sld := HSlider.new()
	sld.min_value = -1.0   # sentinel = use authored
	sld.max_value = 15.0
	sld.step = 0.1
	sld.value = current
	sld.custom_minimum_size = Vector2(240, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = ("default %.1fs" % authored) if current < 0.0 else "%.1fs  (authored %.1fs)" % [current, authored]
	val_lbl.set("theme_override_font_sizes/font_size", 12)
	val_lbl.custom_minimum_size = Vector2(160, 0)
	var meta_lbl := Label.new()
	meta_lbl.text = "−1 = use authored"
	meta_lbl.set("theme_override_font_sizes/font_size", 11)
	meta_lbl.modulate = Color(0.55, 0.60, 0.68)
	meta_lbl.custom_minimum_size = Vector2(220, 0)
	sld.value_changed.connect(func(v: float):
		BalanceOverrides.set_wave_interval(String(lvl.level_id), wave_idx, spawn_idx, v)
		val_lbl.text = ("default %.1fs" % authored) if v < 0.0 else "%.1fs  (authored %.1fs)" % [v, authored]
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	hb.add_child(meta_lbl)
	parent.add_child(hb)


func _add_emitter_delay_row(parent: VBoxContainer, spawn: Resource, lvl: Resource,
		wave_idx: int, spawn_idx: int) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "                 delay"
	name_lbl.set("theme_override_font_sizes/font_size", 12)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	var authored: float = float(spawn.start_delay)
	var current: float = BalanceOverrides.get_wave_delay(
		String(lvl.level_id), wave_idx, spawn_idx
	)
	var sld := HSlider.new()
	sld.min_value = -1.0
	sld.max_value = 60.0
	sld.step = 0.5
	sld.value = current
	sld.custom_minimum_size = Vector2(240, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = ("default %.1fs" % authored) if current < 0.0 else "%.1fs  (authored %.1fs)" % [current, authored]
	val_lbl.set("theme_override_font_sizes/font_size", 12)
	val_lbl.custom_minimum_size = Vector2(160, 0)
	var meta_lbl := Label.new()
	meta_lbl.text = "−1 = use authored"
	meta_lbl.set("theme_override_font_sizes/font_size", 11)
	meta_lbl.modulate = Color(0.55, 0.60, 0.68)
	meta_lbl.custom_minimum_size = Vector2(220, 0)
	sld.value_changed.connect(func(v: float):
		BalanceOverrides.set_wave_delay(String(lvl.level_id), wave_idx, spawn_idx, v)
		val_lbl.text = ("default %.1fs" % authored) if v < 0.0 else "%.1fs  (authored %.1fs)" % [v, authored]
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	hb.add_child(meta_lbl)
	parent.add_child(hb)


# Total cumulative gold the player would hold at end-of-level if every enemy
# is killed and every bounty is collected. Anchors the gold-curve y-axis on
# the per-wave detail charts so stacked cards share a consistent scale.
# Override-aware via _override_aware_per_wave_gold (per-enemy gold_mult).
func _compute_level_final_gold(wave_list: WaveList, lvl: Resource) -> int:
	var base: int = _compute_starting_gold(lvl)
	var total: int = base
	for g in _override_aware_per_wave_gold(wave_list):
		total += int(g)
	return total


# Per-wave bounty + override-adjusted enemy gold drops. Walks each wave's
# spawns, looks up authored gold_worth (cached by scene_path), multiplies by
# the per-enemy gold_mult from BalanceOverrides. Result drives both
# _compute_gold_at_wave_start and _compute_level_final_gold so chart values
# stay in sync with the slider tweaks.
func _override_aware_per_wave_gold(wave_list: WaveList) -> Array:
	var out: Array = []
	if wave_list == null:
		return out
	for wave in wave_list.waves:
		if wave == null:
			out.append(0)
			continue
		var g: int = int(wave.bounty) if "bounty" in wave else 0
		for spawn in wave.spawns:
			if spawn == null or spawn.count <= 0 or spawn.enemy_scene == null:
				continue
			var info: Dictionary = _enemy_data_for_scene(spawn.enemy_scene)
			var raw: int = int(info.get("gold_worth", 0))
			if raw <= 0:
				continue
			var mult: float = BalanceOverrides.get_enemy_mult(String(info.get("id", "")), "gold_mult")
			g += int(round(float(spawn.count) * float(raw) * mult))
		out.append(g)
	return out


# Cache scene_path → {id, gold_worth} for the override-aware gold walk.
# Mirrors WaveTimelineChart's caching but at the BalanceSliders level so we
# don't pay another instantiate when the chart already did it. One
# instantiate per unique enemy scene per BalanceSliders session.
var _enemy_scene_data_cache: Dictionary = {}


func _enemy_data_for_scene(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {"id": "", "gold_worth": 0}
	var path: String = scene.resource_path
	if _enemy_scene_data_cache.has(path):
		return _enemy_scene_data_cache[path]
	var inst: Node = scene.instantiate()
	var info: Dictionary = {"id": "", "gold_worth": 0}
	if "data" in inst and inst.data != null:
		var d = inst.data
		info["id"] = String(d.enemy_id) if "enemy_id" in d else ""
		info["gold_worth"] = int(d.gold_worth) if "gold_worth" in d else 0
	inst.queue_free()
	_enemy_scene_data_cache[path] = info
	return info


# Walk a WaveList and collect path_ids in order of first appearance. Drives
# the per-path lane row order in WaveTimelineChart.
func _collect_paths(wave_list: WaveList) -> Array:
	var seen: Dictionary = {}
	var ordered: Array = []
	for w in wave_list.waves:
		if w == null:
			continue
		for spawn in w.spawns:
			if spawn == null:
				continue
			var pid: String = String(spawn.path_id)
			if not seen.has(pid):
				seen[pid] = true
				ordered.append(pid)
	return ordered


# Best L1 dmg-per-gold across the tower roster, evaluated over the wave's
# spawn window. Naked Baseline floor — the supply line a default-loadout
# player can theoretically buy. tower_damage_per_gold returns 0 for barracks.
#
# Folds in per-tower L1 BalanceOverrides (damage_mult / speed_mult /
# cost_mult) on top of the authored helper result, since
# bc.tower_damage_per_gold reads the .tres values directly. Without this,
# moving Archer L1 cost from 50→30 wouldn't lift the chart's supply line
# even though the in-game build path correctly uses the override.
func _compute_l1_dmg_per_gold(wave: WaveData) -> float:
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return 0.0
	var window_sec: float = max(20.0, bc.wave_duration(wave))
	var best: float = 0.0
	for t in ContentRegistry.towers:
		if not (t is TowerData) or t.damage <= 0.0:
			continue
		var v: float = bc.tower_damage_per_gold(t, 0, window_sec)
		if v <= 0.0 or t.tower_id == "":
			continue
		# Apply L1 overrides: dmg ↑ raises supply, spd ↑ raises supply,
		# cost ↓ raises supply (dmg/g denominator shrinks → quotient grows).
		var dmg_m: float = BalanceOverrides.get_tower_mult(t.tower_id, "l1", "damage_mult")
		var spd_m: float = BalanceOverrides.get_tower_mult(t.tower_id, "l1", "speed_mult")
		var cost_m: float = BalanceOverrides.get_tower_mult(t.tower_id, "l1", "cost_mult")
		v *= dmg_m * spd_m
		if cost_m > 0.0001:
			v /= cost_m
		if v > best:
			best = v
	return best


# Override-adjusted starting gold for `lvl`. Per-level override wins when set;
# otherwise falls back to RunState.STARTING_GOLD + the meta-progression
# starting-gold bonus + global starting_gold_add slider.
#
# Mirrors RunState.reset_for_level() exactly so the chart's gold curve
# matches what the runtime gives the player. Earlier the meta bonus was
# missing here — a player who spent meta-gold on +50 starting gold saw the
# chart anchored at 100g while the runtime started them at 150g.
func _compute_starting_gold(lvl: Resource) -> int:
	var per_level_g: int = BalanceOverrides.get_level_int(String(lvl.level_id), "starting_gold", -1)
	if per_level_g >= 0:
		return per_level_g
	return RunState.STARTING_GOLD \
		+ int(MetaProgression.get_upgrade_bonus(MetaProgression.MOD_STARTING_GOLD)) \
		+ BalanceOverrides.get_starting_gold_add()


# Cumulative natural gold available at the start of `wave_index`. Sums the
# starting gold plus the override-adjusted per-wave gold totals from earlier
# waves. wave_index 0 = just the starting_gold; wave_index N = starting + Σ
# wave_gold[0..N-1]. Replaces the prior score_level_breakdown call so that
# per-enemy gold_mult sliders are reflected in the chart's supply line.
func _compute_gold_at_wave_start(wave_list: WaveList, wave_index: int, lvl: Resource) -> int:
	var base: int = _compute_starting_gold(lvl)
	var per_wave: Array = _override_aware_per_wave_gold(wave_list)
	var total: int = base
	for i in range(min(wave_index, per_wave.size())):
		total += int(per_wave[i])
	return total


func _add_level_int_slider(parent: VBoxContainer, level_id: String, key: String,
		rmin: int, rmax: int, rstep: int) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "    " + key + " (-1 = default)"
	name_lbl.set("theme_override_font_sizes/font_size", 13)
	name_lbl.custom_minimum_size = Vector2(260, 0)
	var sld := HSlider.new()
	sld.min_value = rmin
	sld.max_value = rmax
	sld.step = rstep
	sld.value = float(BalanceOverrides.get_level_int(level_id, key, rmin))
	sld.custom_minimum_size = Vector2(280, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = "default" if int(sld.value) < 0 else str(int(sld.value))
	val_lbl.set("theme_override_font_sizes/font_size", 13)
	val_lbl.custom_minimum_size = Vector2(80, 0)
	sld.value_changed.connect(func(v: float):
		var iv: int = int(v)
		BalanceOverrides.set_level_value(level_id, key, iv)
		val_lbl.text = "default" if iv < 0 else str(iv)
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	parent.add_child(hb)
	_level_value_labels[level_id + "|" + key] = val_lbl


func _add_level_float_slider(parent: VBoxContainer, level_id: String, key: String,
		rmin: float, rmax: float, rstep: float) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = "    " + key + " (1.0 = identity)"
	name_lbl.set("theme_override_font_sizes/font_size", 13)
	name_lbl.custom_minimum_size = Vector2(260, 0)
	var sld := HSlider.new()
	sld.min_value = rmin
	sld.max_value = rmax
	sld.step = rstep
	sld.value = BalanceOverrides.get_level_float(level_id, key, 1.0)
	sld.custom_minimum_size = Vector2(280, 0)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % sld.value
	val_lbl.set("theme_override_font_sizes/font_size", 13)
	val_lbl.custom_minimum_size = Vector2(80, 0)
	sld.value_changed.connect(func(v: float):
		BalanceOverrides.set_level_value(level_id, key, v)
		val_lbl.text = "%.2f" % v
		_refresh_wave_charts())
	hb.add_child(name_lbl)
	hb.add_child(sld)
	hb.add_child(val_lbl)
	parent.add_child(hb)
	_level_value_labels[level_id + "|" + key] = val_lbl


# ── Derived-metric helpers (per-tier DPS / cumul / g/DPS / TTK / role) ──────
# All read effective stats = authored × per-tier override mult. They mirror
# how BaseTower folds in BalanceOverrides at runtime, so the panel readout
# matches what a placed tower will actually fire at.

# Effective absolute value for one (tower, tier_key, stat) tuple. Mirrors
# _authored_stat() but multiplies in the live BalanceOverrides multiplier.
func _effective_stat(tower: TowerData, tier_key: String, stat: String) -> float:
	var authored: float = _authored_stat(tower, tier_key, stat)
	if authored <= 0.0:
		return 0.0
	return authored * BalanceOverrides.get_tower_mult(tower.tower_id, tier_key, stat)


# Effective DPS = damage × attack_speed at the tier (after override mults).
# Returns 0 for barracks / non-attacking tiers.
func _effective_dps(tower: TowerData, tier_key: String) -> float:
	if tower == null or tower.is_barracks():
		return 0.0
	var dmg: float = _effective_stat(tower, tier_key, "damage_mult")
	var spd: float = _effective_stat(tower, tier_key, "speed_mult")
	if dmg <= 0.0 or spd <= 0.0:
		return 0.0
	return dmg * spd


# Cumulative gold to reach this tier from a fresh build slot, with per-tier
# cost overrides folded in. Mirrors BalanceCalculator.tower_cumul_cost shape:
#   l1        → just L1 cost
#   l2        → L1 + L2
#   l3_linear → L1 + L2 + L3 linear
#   branch_*  → L1 + L2 + branch
func _effective_cumul_cost(tower: TowerData, tier_key: String) -> int:
	if tower == null:
		return 0
	var total: float = _effective_stat(tower, "l1", "cost_mult")
	match tier_key:
		"l1":
			pass
		"l2":
			total += _effective_stat(tower, "l2", "cost_mult")
		"l3_linear":
			total += _effective_stat(tower, "l2", "cost_mult")
			total += _effective_stat(tower, "l3_linear", "cost_mult")
		"branch_a":
			total += _effective_stat(tower, "l2", "cost_mult")
			total += _effective_stat(tower, "branch_a", "cost_mult")
		"branch_b":
			total += _effective_stat(tower, "l2", "cost_mult")
			total += _effective_stat(tower, "branch_b", "cost_mult")
	return int(round(total))


# g/DPS = cumul cost / DPS. Lower is better. Returns 0 when DPS is 0
# (barracks, missing tier).
func _effective_gdps(tower: TowerData, tier_key: String) -> float:
	var dps: float = _effective_dps(tower, tier_key)
	if dps <= 0.0:
		return 0.0
	return float(_effective_cumul_cost(tower, tier_key)) / dps


# TTK against the standard `enemy_basic` baseline. Pipes per-hit damage
# through the same mitigation rule as DamageCalculator (armor for PHYSICAL,
# magic_resist for MAGIC, no mitigation for TRUE). Uses authored enemy
# armor/mag_res — this is a "static spec" readout, not "what hits the field
# during this run", so it ignores the global armor_add / mag_res_add sliders.
func _ttk_basic_enemy(tower: TowerData, tier_key: String) -> float:
	var dps: float = _effective_dps(tower, tier_key)
	if dps <= 0.0:
		return 0.0
	var basic: EnemyData = _basic_enemy()
	if basic == null or basic.max_health <= 0:
		return 0.0
	var mitig: float = 1.0
	match tower.damage_type:
		0: mitig = 1.0 - clampf(basic.armor, 0.0, 1.0)         # PHYSICAL
		1: mitig = 1.0 - clampf(basic.magic_resist, 0.0, 1.0)  # MAGIC
		_: mitig = 1.0                                          # TRUE
	var effective: float = dps * mitig
	if effective <= 0.0:
		return 0.0
	return float(basic.max_health) / effective


# Cached lookup of the baseline TTK target. Walked on demand; the catalog is
# small so a linear scan per refresh is fine.
func _basic_enemy() -> EnemyData:
	for e in ContentRegistry.enemies:
		if e is EnemyData and e.enemy_id == "enemy_basic":
			return e
	return null


# Color + status text for a g/DPS value vs its tier's target band. Inside band
# = green; ±20% off = yellow; further out = red. Mirrors the bands in
# balance/BALANCE.md §Per-tower g/DPS bands. Returns [Color, String].
func _gdps_color_and_status(gdps: float, tier_key: String) -> Array:
	var band: Vector2 = _TIER_GDPS_BANDS.get(tier_key, Vector2(7.0, 22.0))
	if gdps <= 0.0:
		return [Color(0.7, 0.7, 0.7), "n/a"]
	if gdps >= band.x and gdps <= band.y:
		return [Color(0.4, 0.95, 0.4), "in band"]
	var pct_off: float
	var direction: String
	if gdps < band.x:
		# Below band = TOO efficient (overpowered for the price).
		pct_off = (band.x - gdps) / band.x
		direction = "too cheap"
	else:
		# Above band = under-efficient (overpriced for the output).
		pct_off = (gdps - band.y) / band.y
		direction = "too pricey"
	if pct_off <= 0.20:
		return [Color(0.95, 0.85, 0.3), "%s %d%%" % [direction, int(round(pct_off * 100.0))]]
	return [Color(0.95, 0.45, 0.4), "%s %d%%" % [direction, int(round(pct_off * 100.0))]]


# Per-tier role tags — picks slow/stun from the upgrade override when set,
# else from the base TowerData (matches BaseTower's _build_on_hit_effect
# fallback rule). damage_type / aoe / targets_flying don't change between
# tiers so they read off the base tower.
func _role_tags_for_tier(tower: TowerData, tier_key: String) -> String:
	if tower == null:
		return ""
	if tower.is_barracks():
		return "block"
	var tags: Array[String] = []
	match tower.damage_type:
		0: tags.append("physical")
		1: tags.append("magic")
		_: tags.append("true")
	tags.append("splash" if tower.aoe_radius > 0.0 else "single")
	tags.append("anti-air" if tower.targets_flying else "ground-only")
	var slow_f: float = tower.on_hit_slow_factor
	var stun_d: float = tower.on_hit_stun_duration
	var upg: Resource = _tier_upgrade_resource(tower, tier_key)
	if upg != null:
		if upg.on_hit_slow_factor > 0.0:
			slow_f = upg.on_hit_slow_factor
		if upg.on_hit_stun_duration > 0.0:
			stun_d = upg.on_hit_stun_duration
	if slow_f > 0.0:
		tags.append("slow")
	if stun_d > 0.0:
		tags.append("stun")
	return " · ".join(tags)


# The TowerUpgradeData backing a tier_key, or null for L1 (which uses base
# TowerData directly). Used by _role_tags_for_tier to find tier-specific
# slow/stun overrides.
func _tier_upgrade_resource(tower: TowerData, tier_key: String) -> Resource:
	if tower == null:
		return null
	match tier_key:
		"l2":
			if tower.level_upgrades.size() >= 1:
				return tower.level_upgrades[0]
		"l3_linear":
			if tower.level_upgrades.size() >= 2:
				return tower.level_upgrades[1]
		"branch_a":
			if tower.level_3_branches.size() >= 1:
				return tower.level_3_branches[0]
		"branch_b":
			if tower.level_3_branches.size() >= 2:
				return tower.level_3_branches[1]
	return null


# Returns the tier_key directly below this one, used by the footer's "vs N"
# delta row. Branches both compare against L2 (their fork point), not L3
# linear — branches are sidegrades from L2, not from L3 main.
func _lower_tier_key(tier_key: String) -> String:
	match tier_key:
		"l2": return "l1"
		"l3_linear": return "l2"
		"branch_a": return "l2"
		"branch_b": return "l2"
	return ""


# Walk every tower at this tier; return the lowest g/DPS (best efficiency)
# along with the tower's name. Empty Dictionary if no tower attacks at the
# tier (e.g., everything is a barracks).
func _best_gdps_at_tier(tier_key: String) -> Dictionary:
	var best_g: float = INF
	var best_name: String = ""
	var best_id: String = ""
	for t in ContentRegistry.towers:
		if t == null or not (t is TowerData):
			continue
		if t.is_barracks():
			continue
		if not _tower_has_tier(t, tier_key):
			continue
		var g: float = _effective_gdps(t, tier_key)
		if g <= 0.0:
			continue
		if g < best_g:
			best_g = g
			best_name = t.tower_name
			best_id = t.tower_id
	if best_id == "":
		return {}
	return {"gdps": best_g, "tower_id": best_id, "tower_name": best_name}


# ── Header / footer row builders + live refresh ─────────────────────────────

# Header row sits above the four stat sliders. Renders DPS / cumul cost /
# g/DPS (color-coded) / TTK / role tags. All five labels are stored under
# `_tier_metric_labels` so _refresh_tier_metrics can rewrite them in place.
func _add_tier_header_row(parent: VBoxContainer, tower: TowerData, tier_key: String) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 14)
	var indent := Label.new()
	indent.text = "      "
	hb.add_child(indent)
	var dps_lbl := _make_metric_label(110)
	var cost_lbl := _make_metric_label(120)
	var gdps_lbl := _make_metric_label(220)
	var ttk_lbl := _make_metric_label(110)
	var cov_lbl := _make_metric_label(110)
	var clear_lbl := _make_metric_label(110)
	var obs_lbl := _make_metric_label(170)
	var role_lbl := _make_metric_label(260)
	hb.add_child(dps_lbl)
	hb.add_child(cost_lbl)
	hb.add_child(gdps_lbl)
	hb.add_child(ttk_lbl)
	hb.add_child(cov_lbl)
	hb.add_child(clear_lbl)
	hb.add_child(obs_lbl)
	hb.add_child(role_lbl)
	parent.add_child(hb)
	_tier_metric_labels[tower.tower_id + "|" + tier_key] = {
		"dps": dps_lbl,
		"cost": cost_lbl,
		"gdps": gdps_lbl,
		"ttk": ttk_lbl,
		"cov": cov_lbl,
		"clear": clear_lbl,
		"obs": obs_lbl,
		"role": role_lbl,
	}


# Footer row sits below the four stat sliders. Two labels:
#   delta:   "vs L1: DPS +6.0 (+71%)   Range +30   Cost +75g"
#   compare: "best at L2: 9.8g/DPS (Artillery)"
# delta is hidden on L1 (no lower tier).
func _add_tier_footer_row(parent: VBoxContainer, tower: TowerData, tier_key: String) -> void:
	var hb := HBoxContainer.new()
	hb.set("theme_override_constants/separation", 14)
	var indent := Label.new()
	indent.text = "      "
	hb.add_child(indent)
	var delta_lbl := _make_metric_label(420)
	delta_lbl.modulate = Color(0.85, 0.9, 0.95)
	var compare_lbl := _make_metric_label(360)
	compare_lbl.modulate = Color(0.85, 0.9, 0.95)
	hb.add_child(delta_lbl)
	hb.add_child(compare_lbl)
	parent.add_child(hb)
	var key: String = tower.tower_id + "|" + tier_key
	if not _tier_metric_labels.has(key):
		_tier_metric_labels[key] = {}
	_tier_metric_labels[key]["delta"] = delta_lbl
	_tier_metric_labels[key]["compare"] = compare_lbl


func _make_metric_label(min_w: int) -> Label:
	var l := Label.new()
	l.set("theme_override_font_sizes/font_size", 13)
	l.custom_minimum_size = Vector2(min_w, 0)
	return l


# Recompute all derived metrics for every visible tier block, plus the
# top-of-section summary grid. Cheap — labels just update text. The
# RunStats history is read once per refresh and cached so we don't re-read
# the file for every (tower, tier) pair.
func _refresh_all_metrics() -> void:
	_history_cache = RunStats.get_history()
	for key in _tier_metric_labels.keys():
		var parts: PackedStringArray = (key as String).split("|")
		if parts.size() != 2:
			continue
		var tower: TowerData = _tower_by_id(parts[0])
		if tower == null:
			continue
		_refresh_tier_metrics(tower, parts[1])
	_refresh_summary_grid()
	_refresh_wave_charts()


# Re-feeds each chart with the current override-adjusted supply/gold so a
# slider tweak (cost_mult, starting_gold, hp_mult, etc.) updates the chart
# in place without rebuilding the level section.
func _refresh_wave_charts() -> void:
	for entry in _wave_charts:
		var chart: Control = entry.get("chart")
		if chart == null or not is_instance_valid(chart):
			continue
		var wave_list: WaveList = entry.get("wave_list")
		var lvl: Resource = entry.get("level_data")
		if wave_list == null or lvl == null:
			continue
		# Overview chart has a different signature than per-wave detail charts —
		# branch so a single _wave_charts array can hold both kinds.
		if entry.get("is_overview", false):
			chart.set_data(wave_list, lvl, _compute_starting_gold(lvl))
			continue
		var idx: int = int(entry.get("wave_index", 0))
		var paths: Array = entry.get("paths", [])
		if idx >= wave_list.waves.size():
			continue
		var wave: WaveData = wave_list.waves[idx]
		if wave == null:
			continue
		chart.set_data(wave, lvl, idx, _compute_l1_dmg_per_gold(wave),
			_compute_gold_at_wave_start(wave_list, idx, lvl), paths,
			_compute_level_final_gold(wave_list, lvl))


func _refresh_tier_metrics(tower: TowerData, tier_key: String) -> void:
	var labels: Dictionary = _tier_metric_labels.get(tower.tower_id + "|" + tier_key, {})
	if labels.is_empty():
		return
	var dps: float = _effective_dps(tower, tier_key)
	var cost: int = _effective_cumul_cost(tower, tier_key)
	var gdps: float = _effective_gdps(tower, tier_key)
	var ttk: float = _ttk_basic_enemy(tower, tier_key)
	if labels.has("dps"):
		(labels["dps"] as Label).text = "DPS n/a" if dps <= 0.0 else "DPS %.1f" % dps
	if labels.has("cost"):
		(labels["cost"] as Label).text = "Cumul %dg" % cost
	if labels.has("gdps"):
		var gl: Label = labels["gdps"]
		var arr: Array = _gdps_color_and_status(gdps, tier_key)
		if gdps <= 0.0:
			gl.text = "g/DPS n/a"
			gl.modulate = arr[0]
		else:
			gl.text = "g/DPS %.1f  [%s]" % [gdps, arr[1]]
			gl.modulate = arr[0]
	if labels.has("ttk"):
		(labels["ttk"] as Label).text = "TTK n/a" if ttk <= 0.0 else "TTK %.1fs" % ttk
	if labels.has("cov"):
		var cov: float = _coverage_dps(tower, tier_key)
		(labels["cov"] as Label).text = "Cov n/a" if cov <= 0.0 else "Cov %.2f" % cov
	if labels.has("clear"):
		var cl: Array = _clear_ok_status(tower, tier_key, ttk)
		var cll: Label = labels["clear"]
		cll.text = cl[1]
		cll.modulate = cl[0]
	if labels.has("role"):
		(labels["role"] as Label).text = "Role: " + _role_tags_for_tier(tower, tier_key)
	if labels.has("delta"):
		(labels["delta"] as Label).text = _format_tier_delta(tower, tier_key)
	if labels.has("compare"):
		(labels["compare"] as Label).text = _format_tier_compare(tower, tier_key)
	if labels.has("obs"):
		var ol: Label = labels["obs"]
		var obs: Dictionary = _observed_dps_for_tier(tower, tier_key)
		var ratio: float = 0.0
		if dps > 0.0 and float(obs.get("dps", 0.0)) > 0.0:
			ratio = float(obs.dps) / dps
		var arr: Array = _obs_color_and_text(obs, ratio)
		ol.text = arr[1]
		ol.modulate = arr[0]


# "vs L1: DPS +6.0 (+71%)   Rng +30   Cost +75g". Empty when there is no
# lower tier (L1) or when stats are missing.
func _format_tier_delta(tower: TowerData, tier_key: String) -> String:
	var lower: String = _lower_tier_key(tier_key)
	if lower == "":
		return ""
	var dps_now: float = _effective_dps(tower, tier_key)
	var dps_low: float = _effective_dps(tower, lower)
	var rng_now: float = _effective_stat(tower, tier_key, "range_mult")
	var rng_low: float = _effective_stat(tower, lower, "range_mult")
	var cost_now: int = _effective_cumul_cost(tower, tier_key)
	var cost_low: int = _effective_cumul_cost(tower, lower)
	var bits: Array[String] = []
	if dps_low > 0.0 and dps_now > 0.0:
		var d: float = dps_now - dps_low
		var pct: float = (d / dps_low) * 100.0
		bits.append("DPS %+.1f (%+d%%)" % [d, int(round(pct))])
	if rng_low > 0.0 and rng_now > 0.0 and absf(rng_now - rng_low) >= 1.0:
		bits.append("Rng %+d" % int(round(rng_now - rng_low)))
	if cost_now != cost_low:
		bits.append("Cost %+dg" % (cost_now - cost_low))
	if bits.is_empty():
		return "vs %s: (no change)" % _tier_display_name(lower)
	return "vs %s: %s" % [_tier_display_name(lower), "   ".join(bits)]


# "best at L2: 9.8 g/DPS (Artillery)". Highlights when THIS tower is the
# best at its tier ("← this tower").
func _format_tier_compare(tower: TowerData, tier_key: String) -> String:
	var best: Dictionary = _best_gdps_at_tier(tier_key)
	if best.is_empty():
		return ""
	if best.tower_id == tower.tower_id:
		return "best at %s: %.1f g/DPS  ← this tower" % [
			_tier_display_name(tier_key), best.gdps,
		]
	return "best at %s: %.1f g/DPS (%s)" % [
		_tier_display_name(tier_key), best.gdps, best.tower_name,
	]


# Resolve a tower_id back to its TowerData. Used by _refresh_all_metrics
# when iterating the label-keys dictionary.
func _tower_by_id(tower_id: String) -> TowerData:
	for t in ContentRegistry.towers:
		if t is TowerData and t.tower_id == tower_id:
			return t
	return null


# ── Top-of-section summary grid ─────────────────────────────────────────────
# A compact spreadsheet view of every tower at every authored tier — Tower /
# Tier / DPS / Cumul / g/DPS (color-coded) / TTK / Role. Lets a designer
# spot outliers across the whole roster at a glance before drilling into a
# specific slider. Rebuilt on every refresh so it tracks live edits.

const _SUMMARY_HEADERS: Array[String] = ["Tower", "Tier", "DPS", "Cumul", "g/DPS", "TTK", "Cov", "Clear?", "Obs / ratio", "Role"]


func _add_summary_grid(parent: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "Tower roster — derived metrics (live)"
	heading.set("theme_override_font_sizes/font_size", 16)
	heading.modulate = Color(0.85, 0.95, 0.7)
	parent.add_child(heading)
	_summary_grid = GridContainer.new()
	_summary_grid.columns = _SUMMARY_HEADERS.size()
	_summary_grid.set("theme_override_constants/h_separation", 18)
	_summary_grid.set("theme_override_constants/v_separation", 2)
	parent.add_child(_summary_grid)
	# Spacer below the grid so the per-tower sliders aren't jammed against it.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	parent.add_child(spacer)


func _refresh_summary_grid() -> void:
	if _summary_grid == null:
		return
	for c in _summary_grid.get_children():
		c.queue_free()
	for h in _SUMMARY_HEADERS:
		var hl := Label.new()
		hl.text = h
		hl.set("theme_override_font_sizes/font_size", 12)
		hl.modulate = Color(1.0, 0.9, 0.5, 1)
		_summary_grid.add_child(hl)
	for tower in ContentRegistry.towers:
		if tower == null or not (tower is TowerData) or tower.tower_id == "":
			continue
		for tier_key in _TOWER_TIER_KEYS:
			if not _tower_has_tier(tower, tier_key):
				continue
			_add_summary_row(tower, tier_key)


func _add_summary_row(tower: TowerData, tier_key: String) -> void:
	var name_l := _make_metric_label(140)
	name_l.text = tower.tower_name
	var tier_l := _make_metric_label(80)
	tier_l.text = _tier_display_name(tier_key)
	var dps: float = _effective_dps(tower, tier_key)
	var cost: int = _effective_cumul_cost(tower, tier_key)
	var gdps: float = _effective_gdps(tower, tier_key)
	var ttk: float = _ttk_basic_enemy(tower, tier_key)
	var dps_l := _make_metric_label(70)
	dps_l.text = "—" if dps <= 0.0 else "%.1f" % dps
	var cost_l := _make_metric_label(70)
	cost_l.text = "%dg" % cost
	var gdps_l := _make_metric_label(110)
	var arr: Array = _gdps_color_and_status(gdps, tier_key)
	gdps_l.text = "—" if gdps <= 0.0 else "%.1f" % gdps
	gdps_l.modulate = arr[0]
	var ttk_l := _make_metric_label(70)
	ttk_l.text = "—" if ttk <= 0.0 else "%.1fs" % ttk
	var cov_v: float = _coverage_dps(tower, tier_key)
	var cov_l := _make_metric_label(70)
	cov_l.text = "—" if cov_v <= 0.0 else "%.2f" % cov_v
	var clear_arr: Array = _clear_ok_status(tower, tier_key, ttk)
	var clear_l := _make_metric_label(80)
	clear_l.text = clear_arr[1]
	clear_l.modulate = clear_arr[0]
	var obs_l := _make_metric_label(140)
	var obs_d: Dictionary = _observed_dps_for_tier(tower, tier_key)
	var ratio: float = 0.0
	if dps > 0.0 and float(obs_d.get("dps", 0.0)) > 0.0:
		ratio = float(obs_d.dps) / dps
	var obs_arr: Array = _obs_color_and_text(obs_d, ratio)
	obs_l.text = obs_arr[1]
	obs_l.modulate = obs_arr[0]
	var role_l := _make_metric_label(280)
	role_l.text = _role_tags_for_tier(tower, tier_key)
	_summary_grid.add_child(name_l)
	_summary_grid.add_child(tier_l)
	_summary_grid.add_child(dps_l)
	_summary_grid.add_child(cost_l)
	_summary_grid.add_child(gdps_l)
	_summary_grid.add_child(ttk_l)
	_summary_grid.add_child(cov_l)
	_summary_grid.add_child(clear_l)
	_summary_grid.add_child(obs_l)
	_summary_grid.add_child(role_l)


# ── Observed DPS from RunStats history ──────────────────────────────────────
# Reads `damage_by_tower` from each persisted run. The recorded format from
# RunState.record_round_damage is "<base tower_name> L<level>" (level being
# the tower's .level field — 1/2/3). For each run that actually saw this
# tower-tier in play, computes per-run DPS = damage / duration_s, then
# averages across qualifying runs. Empty result when no run data exists.
#
# **Branch limitation:** the recorded name uses base tower_name, so Archmage
# and Necromancer both surface as "Mage Tower L3". branch_a and branch_b
# return the SAME observed DPS — telemetry can't distinguish them today.
# Documented in CLAUDE.md / SESSIONS.md; future fix is to record branch_idx
# in the round_damage_towers entry.
func _observed_dps_for_tier(tower: TowerData, tier_key: String) -> Dictionary:
	# Phase 56+ records carry tower_id / level / branch_idx per damage_by_tower
	# row, so this lookup matches by structured fields. Branches resolve
	# distinctly: Archmage (level=3, branch_idx=0) and Necromancer (branch_idx=1)
	# get separate observed DPS instead of the old shared "Mage Tower L3" key.
	if tower == null or _history_cache.is_empty():
		return {"dps": 0.0, "runs": 0}
	var lvl: int = _observed_level_for_tier(tier_key)
	var want_branch: int = _observed_branch_for_tier(tier_key)
	var tid: String = String(tower.tower_id)
	if lvl == 0 or tid == "":
		return {"dps": 0.0, "runs": 0}
	var samples: Array[float] = []
	for run in _history_cache:
		if not (run is Dictionary):
			continue
		var dur: float = float(run.get("duration_s", 0.0))
		if dur <= 0.0:
			continue
		var dt: Array = run.get("damage_by_tower", [])
		var matched: float = 0.0
		for ent in dt:
			if String(ent.get("tower_id", "")) != tid:
				continue
			if int(ent.get("level", 0)) != lvl:
				continue
			# branch_idx absent on pre-Phase-56 records → defaults to -1 via
			# the fallback. Treated as l3_linear, NOT branches. Loses some
			# observed-DPS granularity for legacy runs but never crashes.
			if int(ent.get("branch_idx", -1)) != want_branch:
				continue
			matched += float(ent.get("damage", 0.0))
		if matched > 0.0:
			samples.append(matched / dur)
	if samples.is_empty():
		return {"dps": 0.0, "runs": 0}
	var sum_dps: float = 0.0
	for v in samples:
		sum_dps += v
	return {"dps": sum_dps / float(samples.size()), "runs": samples.size()}


# Tier_key → integer level value as recorded in damage_by_tower rows.
func _observed_level_for_tier(tier_key: String) -> int:
	match tier_key:
		"l1":
			return 1
		"l2":
			return 2
		"l3_linear", "branch_a", "branch_b":
			return 3
	return 0


# Tier_key → branch_idx to match. -1 = no branch (l3_linear / earlier),
# 0 = branch_a, 1 = branch_b.
func _observed_branch_for_tier(tier_key: String) -> int:
	match tier_key:
		"branch_a":
			return 0
		"branch_b":
			return 1
	return -1


# Color + display text for an observed-DPS reading. Ratio bands match the
# community-typical 50–80% effective-to-theoretical range called out in
# balance/BALANCE.md §"Track effective:theoretical DPS":
#   no data            → gray "Obs —"
#   ratio in [0.5, 0.8] → green (in band)
#   ratio in [0.3, 0.5) → yellow (under-utilized — out of range / dead targets)
#   ratio < 0.3         → red (very under-utilized, or the tower rarely hits)
#   ratio > 0.8         → blue (over-performing — small sample, or theoretical
#                                understates AoE / multi-target)
# Format: "Obs <dps> ×<ratio> [n=<runs>]" or "Obs —" when no data.
func _obs_color_and_text(obs: Dictionary, ratio: float) -> Array:
	var runs: int = int(obs.get("runs", 0))
	var dps: float = float(obs.get("dps", 0.0))
	if runs <= 0 or dps <= 0.0:
		return [Color(0.6, 0.6, 0.6), "Obs —"]
	var color: Color
	if ratio <= 0.0:
		color = Color(0.6, 0.6, 0.6)
	elif ratio > 0.8:
		color = Color(0.45, 0.75, 1.0)  # blue (over-performing — small sample or AoE)
	elif ratio >= 0.5:
		color = Color(0.4, 0.95, 0.4)   # green (in community-typical 50–80% band)
	elif ratio >= 0.3:
		color = Color(0.95, 0.85, 0.3)  # yellow (under-utilized)
	else:
		color = Color(0.95, 0.45, 0.4)  # red (very under)
	var ratio_text: String = ("×%.2f" % ratio) if ratio > 0.0 else "—"
	return [color, "Obs %.1f %s [n=%d]" % [dps, ratio_text, runs]]


# ── Range-dependent metrics (Cov + ClearOK) ─────────────────────────────────
# Range was previously shown as a slider value but never folded into any
# derived metric — two towers with identical g/DPS but different reach
# looked equivalent in the panel even though one covers ~3× the map. These
# two helpers expose that:
#   Coverage  — DPS delivered per unit map area (DPS / πr², ×1000 to keep
#               the number readable). Higher = better. Range-shrinking a
#               tower drives this UP, so the metric also catches "is this
#               tier's range too generous for the cost".
#   ClearOK   — can the tower kill `enemy_basic` in the time the enemy
#               spends inside its range? Approximates time-in-range as the
#               diameter (2r) divided by enemy move_speed — the BEST CASE
#               where the enemy's path bisects the range circle. Real-world
#               chord lengths are shorter, so ClearOK ✓ means "can clear in
#               the most favorable geometry"; ✗ means "physically can't,
#               even in best case". Designers should target ✓ on at least
#               one tower per damage type.

const _COVERAGE_AREA_UNIT: float = 1000.0  # px² scale factor — keeps the
                                           # printed number in readable range
                                           # (DPS / area is otherwise ~0.0001).


# DPS per πr² (in DPS per 1000 px²). Returns 0 for non-attacking tiers /
# zero range / barracks. Range here is the tower's attack range (not rally).
func _coverage_dps(tower: TowerData, tier_key: String) -> float:
	if tower == null or tower.is_barracks():
		return 0.0
	var dps: float = _effective_dps(tower, tier_key)
	if dps <= 0.0:
		return 0.0
	var r: float = _effective_stat(tower, tier_key, "range_mult")
	if r <= 0.0:
		return 0.0
	var area: float = PI * r * r
	if area <= 0.0:
		return 0.0
	return dps / area * _COVERAGE_AREA_UNIT


# Best-case time the basic enemy spends crossing this tower's range circle:
# diameter (2r) divided by move_speed. Real paths cross shorter chords, so
# this OVER-estimates the time available to the tower — making ClearOK a
# permissive check ("can clear in the most favorable geometry").
func _time_in_range_basic(tower: TowerData, tier_key: String) -> float:
	if tower == null or tower.is_barracks():
		return 0.0
	var r: float = _effective_stat(tower, tier_key, "range_mult")
	if r <= 0.0:
		return 0.0
	var basic: EnemyData = _basic_enemy()
	if basic == null or basic.move_speed <= 0.0:
		return 0.0
	return (2.0 * r) / basic.move_speed


# "✓" green when the tower can solo-kill the basic enemy before it walks
# out of range, "✗" red when it can't, "n/a" gray for non-attacking tiers
# or missing baseline. ttk is passed in (already computed by caller) to
# avoid recomputing.
func _clear_ok_status(tower: TowerData, tier_key: String, ttk: float) -> Array:
	if tower == null or tower.is_barracks():
		return [Color(0.6, 0.6, 0.6), "n/a"]
	if ttk <= 0.0:
		return [Color(0.6, 0.6, 0.6), "n/a"]
	var time_in: float = _time_in_range_basic(tower, tier_key)
	if time_in <= 0.0:
		return [Color(0.6, 0.6, 0.6), "n/a"]
	if ttk <= time_in:
		# Margin tells you HOW comfortably the kill happens — useful for
		# spotting "barely clears" cases that one stat tweak can break.
		var margin: float = (time_in - ttk) / time_in * 100.0
		return [Color(0.4, 0.95, 0.4), "✓ +%d%%" % int(round(margin))]
	var deficit: float = (ttk - time_in) / time_in * 100.0
	return [Color(0.95, 0.45, 0.4), "✗ -%d%%" % int(round(deficit))]
