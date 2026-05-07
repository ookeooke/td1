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


func _build_tower_section() -> void:
	for c in tower_section.get_children():
		c.queue_free()
	_tower_value_labels.clear()
	var heading := Label.new()
	heading.text = "Tower overrides — per-tier multipliers (1.0 = no change)"
	heading.set("theme_override_font_sizes/font_size", 22)
	heading.modulate = Color(1.0, 0.9, 0.5, 1)
	tower_section.add_child(heading)
	for tower in ContentRegistry.towers:
		if tower == null or not ("tower_id" in tower) or tower.tower_id == "":
			continue
		_add_tower_subgroup(tower)


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
	for stat in _TOWER_STAT_KEYS:
		var authored: float = _authored_stat(tower, tier_key, stat)
		# Skip irrelevant stats (e.g. damage/speed on a barracks where
		# tower.damage = 0). Keeps the panel honest.
		if authored <= 0.0:
			continue
		_add_tower_slider(parent, tower.tower_id, tier_key, stat, authored)


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
		val_lbl.text = _format_stat_value(stat, v, m))
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
