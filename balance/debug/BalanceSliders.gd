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

var _levels: Array = []   # Array[LevelNodeData], populated from level_list.tres
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
	_load_levels()
	_load_slider_values()
	_connect_sliders()
	_build_tower_section()
	_build_level_section()
	_refresh_readout()


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


func _on_armor_changed(v: float) -> void:
	BalanceOverrides.set_value("armor_add", v)
	_update_value_labels()
	_refresh_readout()


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
	# PPT drift — uses override if set, else loadout PPT
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
	var drift: float = BalanceCalculator.score_for_ppt(wave_list, target_ppt, 100)
	readout_ppt.text = "PPT:  target=%d  %s   →  drift %+.0f%%" % [
		target_ppt, ppt_label, drift,
	]


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_play() -> void:
	var level_data: Resource = _selected_level()
	if level_data == null:
		return
	# Stage the run as if it were started from WorldMap. RunState.reset_for_level
	# applies the override-adjusted starting_gold automatically on level launch.
	RunState.current_level_id = level_data.level_id
	RunState.current_mode = "campaign"
	SceneManager.goto(level_data.scene_path)


func _on_reset() -> void:
	BalanceOverrides.reset()
	_load_slider_values()
	# Rebuild the tower + level sections so their sliders snap to defaults.
	_build_tower_section()
	_build_level_section()
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
	group.add_child(hdr)
	group.add_child(body)
	level_section.add_child(group)


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
		val_lbl.text = "default" if iv < 0 else str(iv))
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
		val_lbl.text = "%.2f" % v)
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
	if tower == null:
		return {"dps": 0.0, "runs": 0}
	var key_name: String = _observed_name_for_tier(tower, tier_key)
	if key_name == "" or _history_cache.is_empty():
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
			if String(ent.get("name", "")) == key_name:
				matched += float(ent.get("damage", 0.0))
		if matched > 0.0:
			samples.append(matched / dur)
	if samples.is_empty():
		return {"dps": 0.0, "runs": 0}
	var sum_dps: float = 0.0
	for v in samples:
		sum_dps += v
	return {"dps": sum_dps / float(samples.size()), "runs": samples.size()}


# Map (tower, tier_key) → the "<name> L<level>" key used by RunStats.
# Branches share the L3 key with l3_linear (telemetry doesn't distinguish).
func _observed_name_for_tier(tower: TowerData, tier_key: String) -> String:
	if tower == null or tower.tower_name == "":
		return ""
	var lvl: int = 0
	match tier_key:
		"l1":
			lvl = 1
		"l2":
			lvl = 2
		"l3_linear", "branch_a", "branch_b":
			lvl = 3
	if lvl == 0:
		return ""
	return "%s L%d" % [tower.tower_name, lvl]


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
