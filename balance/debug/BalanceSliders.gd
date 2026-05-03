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

var _levels: Array = []   # Array[LevelNodeData], populated from level_list.tres


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	play_button.pressed.connect(_on_play)
	reset_button.pressed.connect(_on_reset)
	_load_levels()
	_load_slider_values()
	_connect_sliders()
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
	_refresh_readout()
