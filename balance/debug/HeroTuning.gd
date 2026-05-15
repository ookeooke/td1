extends Control

# Phase 3R-followup-3 — dedicated hero + skill tuning panel reachable from a
# WorldMap button. Promotes hero balance from the catch-all BalanceSliders
# screen into a focused workspace that also exposes per-skill stats (damage,
# cooldown, range, AoE radius) which BalanceSliders didn't surface.
#
# All overrides write through BalanceOverrides — same persistence path as
# tower/enemy sliders (user://debug_balance.json). Bake walks the hero +
# skill deltas and writes them onto the authored .tres files via
# ResourceSaver, then resets the runtime overrides so the next session sees
# the new authored numbers as the new default.
#
# Debug-only: BalanceOverrides.is_active() short-circuits in release builds,
# so every read at runtime returns identity multipliers and the bake button
# is hidden via OS.is_debug_build() at the WorldMap entry.

const _BalanceOverrides := preload("res://balance/debug/BalanceOverrides.gd")

const _HERO_STAT_DEFS: Array = [
	{"key": "hp_mult",            "mode": "mult", "label": "HP",         "prop": "max_health"},
	{"key": "armor_add",          "mode": "add",  "label": "Armor",      "prop": "armor"},
	{"key": "mag_res_add",        "mode": "add",  "label": "MagRes",     "prop": "magic_resist"},
	{"key": "speed_mult",         "mode": "mult", "label": "MoveSpeed",  "prop": "move_speed"},
	{"key": "attack_speed_mult",  "mode": "mult", "label": "AtkSpeed",   "prop": "attack_speed"},
	{"key": "damage_mult",        "mode": "mult", "label": "Damage",     "prop": "attack_damage"},
	{"key": "range_mult",         "mode": "mult", "label": "Range",      "prop": "attack_range"},
	{"key": "engage_range_mult",  "mode": "mult", "label": "EngageRng",  "prop": "detection_radius_px"},
]

# Skill stat keys parallel SkillData fields. aoe_radius is subclass-specific
# (ShieldBashSkillData / FalconStormSkillData) — the row only renders when
# the field exists on that particular skill.
const _SKILL_STAT_DEFS: Array = [
	{"key": "damage_mult",       "mode": "mult", "label": "Damage",   "prop": "damage"},
	{"key": "cooldown_mult",     "mode": "mult", "label": "Cooldown", "prop": "cooldown"},
	{"key": "range_mult",        "mode": "mult", "label": "Range",    "prop": "skill_range"},
	{"key": "aoe_radius_mult",   "mode": "mult", "label": "AoE",      "prop": "aoe_radius"},
]

const _SECTION_HEADER_COLOR: Color = Color(0.6, 1.0, 0.7, 1.0)
const _SUB_HEADER_COLOR: Color = Color(0.85, 1.0, 0.92, 1.0)
const _SKILL_HEADER_COLOR: Color = Color(0.95, 0.85, 0.55, 1.0)

var _selected_hero_id: String = ""
var _hero_section: VBoxContainer = null
var _skill_section: VBoxContainer = null
var _hero_picker_row: HBoxContainer = null
var _live_stats_section: VBoxContainer = null

# Stats shown in the Effective Stats panel. (key, label, formatter) tuples.
# Order = display order. The formatter returns the displayed string given a
# raw current_stats float. baseline_at_one indicates "1.0 means no change"
# (skill_power, xp_gain_mult) — those format as "+N%" relative to 1.0.
const _LIVE_STAT_DEFS: Array = [
	{"key": "max_health",        "label": "Max HP",       "fmt": "int"},
	{"key": "damage",            "label": "Damage",       "fmt": "decimal_1"},
	{"key": "attack_speed",      "label": "Attack Speed", "fmt": "decimal_2_per_s"},
	{"key": "move_speed",        "label": "Move Speed",   "fmt": "int"},
	{"key": "attack_range",      "label": "Attack Range", "fmt": "int"},
	{"key": "melee_engage_range","label": "Melee Eng Rng","fmt": "int"},
	{"key": "armor",             "label": "Armor",        "fmt": "percent"},
	{"key": "magic_resist",      "label": "Magic Resist", "fmt": "percent"},
	{"key": "health_regen",      "label": "HP Regen",     "fmt": "decimal_1_per_s"},
	{"key": "cooldown_reduction","label": "CDR",          "fmt": "percent"},
	{"key": "skill_power",       "label": "Skill Power",  "fmt": "delta_pct_above_one"},
	{"key": "xp_gain_mult",      "label": "XP Gain",      "fmt": "delta_pct_above_one"},
]


func _ready() -> void:
	_build_layout()
	if ContentRegistry.heroes.size() > 0 and ContentRegistry.heroes[0] != null:
		_selected_hero_id = String(ContentRegistry.heroes[0].hero_id)
	_refresh()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.14, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 32)
	root.add_theme_constant_override("margin_right", 32)
	root.add_theme_constant_override("margin_top", 24)
	root.add_theme_constant_override("margin_bottom", 24)
	add_child(root)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	root.add_child(v)

	# ── Top bar — title + Back / Bake / Reset ─────────────────────────────
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	v.add_child(top)

	var title := Label.new()
	title.text = "Hero Tuning"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", _SECTION_HEADER_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	var bake_btn := Button.new()
	bake_btn.text = "Bake to .tres"
	bake_btn.tooltip_text = "Writes current hero + skill overrides into authored .tres files. Then resets the runtime overrides so the next session reads the new defaults."
	bake_btn.pressed.connect(_on_bake_pressed)
	top.add_child(bake_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.tooltip_text = "Clears all hero + skill runtime overrides without baking. Authored .tres values remain untouched."
	reset_btn.pressed.connect(_on_reset_pressed)
	top.add_child(reset_btn)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.pressed.connect(_on_back_pressed)
	top.add_child(back_btn)

	# ── Hero picker — one button per hero, highlights the selected one ────
	_hero_picker_row = HBoxContainer.new()
	_hero_picker_row.add_theme_constant_override("separation", 8)
	v.add_child(_hero_picker_row)

	# ── Two-column body — hero stats LEFT, skills RIGHT ───────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 32)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_hero_section = VBoxContainer.new()
	_hero_section.add_theme_constant_override("separation", 6)
	_hero_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_section.size_flags_stretch_ratio = 1.0
	body.add_child(_hero_section)

	_skill_section = VBoxContainer.new()
	_skill_section.add_theme_constant_override("separation", 6)
	_skill_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_section.size_flags_stretch_ratio = 1.4
	body.add_child(_skill_section)

	# Live effective-stats readout — third column. Reads passives + capstones
	# + items + slider overrides + level growth all together so the designer
	# sees what the player will actually have in-level. Updates on every
	# slider change.
	_live_stats_section = VBoxContainer.new()
	_live_stats_section.add_theme_constant_override("separation", 4)
	_live_stats_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_stats_section.size_flags_stretch_ratio = 1.0
	body.add_child(_live_stats_section)


func _refresh() -> void:
	_build_hero_picker()
	_build_hero_stats()
	_build_skill_stats()
	_build_live_stats()


func _build_hero_picker() -> void:
	for c in _hero_picker_row.get_children():
		c.queue_free()
	for hero in ContentRegistry.heroes:
		if hero == null or not ("hero_id" in hero):
			continue
		var hid: String = String(hero.hero_id)
		var hname: String = String(hero.hero_name) if "hero_name" in hero else hid
		var btn := Button.new()
		btn.text = hname
		btn.toggle_mode = true
		btn.button_pressed = (hid == _selected_hero_id)
		btn.pressed.connect(_on_hero_picked.bind(hid))
		_hero_picker_row.add_child(btn)


func _on_hero_picked(hero_id: String) -> void:
	_selected_hero_id = hero_id
	_refresh()


func _build_hero_stats() -> void:
	for c in _hero_section.get_children():
		c.queue_free()
	var heading := Label.new()
	heading.text = "HERO STATS"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", _SUB_HEADER_COLOR)
	_hero_section.add_child(heading)
	var hero: Resource = ContentRegistry.find_hero(_selected_hero_id)
	if hero == null:
		var msg := Label.new()
		msg.text = "(no hero selected)"
		msg.modulate = Color(0.6, 0.6, 0.6)
		_hero_section.add_child(msg)
		return
	for stat_def in _HERO_STAT_DEFS:
		var prop: String = String(stat_def.prop)
		if not (prop in hero):
			continue
		var authored: float = float(hero.get(prop))
		_add_hero_slider(stat_def, authored)


func _add_hero_slider(stat_def: Dictionary, authored: float) -> void:
	var stat_key: String = String(stat_def.key)
	var mode: String = String(stat_def.mode)
	var label: String = String(stat_def.label)
	if mode == "mult" and authored <= 0.0:
		_add_inert_row(_hero_section, label, "—  (no authored value)")
		return
	var current_override: float = _BalanceOverrides.get_hero_mult(_selected_hero_id, stat_key)
	var slider_info: Dictionary = _slider_bounds(mode, stat_key, authored, current_override)
	var hb: HBoxContainer = _make_slider_row(label, slider_info, mode, stat_key,
		func(v: float):
			var ov: float = _override_for_value(mode, authored, v)
			_BalanceOverrides.set_hero_mult(_selected_hero_id, stat_key, ov)
			_refresh_live_stats())
	_hero_section.add_child(hb)


func _build_skill_stats() -> void:
	for c in _skill_section.get_children():
		c.queue_free()
	var heading := Label.new()
	heading.text = "SKILL STATS"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", _SUB_HEADER_COLOR)
	_skill_section.add_child(heading)
	var hero: Resource = ContentRegistry.find_hero(_selected_hero_id)
	if hero == null or not ("skills" in hero):
		var msg := Label.new()
		msg.text = "(no skills authored)"
		msg.modulate = Color(0.6, 0.6, 0.6)
		_skill_section.add_child(msg)
		return
	for skill in hero.skills:
		if skill == null or not ("skill_id" in skill):
			continue
		_add_skill_subgroup(skill)


func _add_skill_subgroup(skill: Resource) -> void:
	var sid: String = String(skill.skill_id)
	var sname: String = String(skill.skill_name) if "skill_name" in skill else sid
	var hdr := Label.new()
	hdr.text = "▸ %s   (%s)" % [sname, sid]
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.add_theme_color_override("font_color", _SKILL_HEADER_COLOR)
	_skill_section.add_child(hdr)
	for stat_def in _SKILL_STAT_DEFS:
		var prop: String = String(stat_def.prop)
		if not (prop in skill):
			continue
		var authored: float = float(skill.get(prop))
		_add_skill_slider(skill, stat_def, authored)


func _add_skill_slider(skill: Resource, stat_def: Dictionary, authored: float) -> void:
	var stat_key: String = String(stat_def.key)
	var mode: String = String(stat_def.mode)
	var label: String = "    " + String(stat_def.label)
	var sid: String = String(skill.skill_id)
	if mode == "mult" and authored <= 0.0:
		_add_inert_row(_skill_section, label, "—  (no authored value)")
		return
	var current_override: float = _BalanceOverrides.get_skill_mult(sid, stat_key)
	var slider_info: Dictionary = _slider_bounds(mode, stat_key, authored, current_override)
	var hb: HBoxContainer = _make_slider_row(label, slider_info, mode, stat_key,
		func(v: float):
			var ov: float = _override_for_value(mode, authored, v)
			_BalanceOverrides.set_skill_mult(sid, stat_key, ov)
			_refresh_live_stats())
	_skill_section.add_child(hb)


# ── Live effective stats (Phase 3R-followup-3 follow-up A) ──────────────
#
# The designer-facing answer to "what does this hero ACTUALLY have right now,
# with my passives + capstones + items + sliders all combined." Mirrors what
# BaseHero._seed_base_stats / recompute_stats produce on spawn, but computed
# in-tool without instantiating a hero. Recomputed on every slider change
# (slider closures call _refresh_live_stats after writing the override).

func _build_live_stats() -> void:
	for c in _live_stats_section.get_children():
		c.queue_free()
	var heading := Label.new()
	heading.text = "EFFECTIVE STATS"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", _SUB_HEADER_COLOR)
	_live_stats_section.add_child(heading)
	var sub := Label.new()
	sub.text = "Includes: HeroData base · level growth · slider overrides · purchased capstones · equipped passives · equipped items"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live_stats_section.add_child(sub)
	var hero: Resource = ContentRegistry.find_hero(_selected_hero_id)
	if hero == null:
		var msg := Label.new()
		msg.text = "(no hero)"
		msg.modulate = Color(0.6, 0.6, 0.6)
		_live_stats_section.add_child(msg)
		return
	var stats: Dictionary = _compute_simulated_stats(hero)
	for stat_def in _LIVE_STAT_DEFS:
		var key: String = String(stat_def.key)
		var value: float = float(stats.get(key, 0.0))
		var fmt: String = String(stat_def.fmt)
		var label: String = String(stat_def.label)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = label
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		name_lbl.custom_minimum_size = Vector2(140, 0)
		hb.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = _format_live_value(fmt, value)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(val_lbl)
		_live_stats_section.add_child(hb)


# Recompute every visible value without rebuilding the rows. Cheap and
# avoids a flicker when sliders move.
func _refresh_live_stats() -> void:
	if _live_stats_section == null:
		return
	# Simplest: rebuild rows. Row count is small (~11) and the rebuild keeps
	# the formatter logic in one place.
	_build_live_stats()


# Mirrors BaseHero.compute_stats_for but ALSO folds in the selected hero's
# equipped passives + purchased capstones — the two ability sources that
# EquipmentScreen's compute_stats_for skips because it only previews item
# changes. Slider overrides come in via compute_base_stats which already
# reads BalanceOverrides.
func _compute_simulated_stats(hero: Resource) -> Dictionary:
	var hero_id: String = String(hero.hero_id)
	var level: int = MetaProgression.get_hero_level(hero_id)
	var base: Dictionary = BaseHero.compute_base_stats(hero, level)
	var mods: Array = []
	# Equipped item abilities.
	if has_node("/root/InventoryManager"):
		for inst in InventoryManager.get_all_equipped(hero_id):
			if inst == null:
				continue
			for ab in inst.build_runtime_abilities(ContentRegistry):
				if ab != null:
					mods.append(ab)
	# Equipped passives — walk the tree the same way BaseHero._apply_equipped_passives does.
	var tree: Resource = ContentRegistry.find_skill_tree(hero_id)
	if tree != null:
		var equipped: Array[String] = LoadoutState.get_equipped_passives(hero_id)
		for passive_id in equipped:
			if passive_id == "":
				continue
			var rank: int = MetaProgression.get_purchased_passive_rank(hero_id, passive_id)
			if rank <= 0:
				continue
			for node in tree.nodes_for_target(passive_id):
				if node == null or not ("kind" in node):
					continue
				if int(node.kind) != HeroSkillNodeData.Kind.PASSIVE_RANK:
					continue
				if int(node.rank) > rank:
					continue
				if node.ability != null:
					mods.append(node.ability)
		# Capstones — purchased = active.
		for node in tree.nodes:
			if node == null or not ("kind" in node):
				continue
			if int(node.kind) != HeroSkillNodeData.Kind.CAPSTONE:
				continue
			if MetaProgression.get_purchased_rank(hero_id, String(node.node_id)) < int(node.rank):
				continue
			if node.ability != null:
				mods.append(node.ability)
	return BaseHero.apply_modifiers(base, mods)


func _format_live_value(fmt: String, value: float) -> String:
	match fmt:
		"int":
			return "%d" % int(round(value))
		"decimal_1":
			return "%.1f" % value
		"decimal_2_per_s":
			return "%.2f /s" % value
		"decimal_1_per_s":
			return "%.1f /s" % value
		"percent":
			return "%d%%" % int(round(value * 100.0))
		"delta_pct_above_one":
			# 1.0 = baseline. Show as "+N%" delta. Negative possible if a debuff
			# reduces the multiplier (e.g. Glass Cannon for max_health_pct, but
			# none of the keys in this table currently go below 1.0).
			var d: float = (value - 1.0) * 100.0
			return "%+d%%" % int(round(d))
	return "%.2f" % value


# ── Slider plumbing ─────────────────────────────────────────────────────

func _slider_bounds(mode: String, stat_key: String, authored: float, override: float) -> Dictionary:
	if mode == "mult":
		return {
			"min": 0.0,
			"max": maxf(authored * 3.0, authored + 1.0),
			"step": _step_for(stat_key, authored),
			"current": authored * override,
			"override": override,
		}
	# add mode (armor / magic_resist) — slider in absolute clamp 0..0.95.
	return {
		"min": 0.0,
		"max": 0.95,
		"step": 0.05,
		"current": clampf(authored + override, 0.0, 0.95),
		"override": override,
	}


func _step_for(stat_key: String, authored: float) -> float:
	match stat_key:
		"hp_mult":            return 1.0 if authored < 50.0 else 5.0
		"speed_mult":         return 5.0
		"damage_mult":        return 0.25 if authored < 10.0 else 0.5
		"range_mult":         return 5.0 if authored < 100.0 else 10.0
		"engage_range_mult":  return 5.0 if authored < 100.0 else 10.0
		"attack_speed_mult":  return 0.05
		"cooldown_mult":      return 0.5
		"aoe_radius_mult":    return 5.0
	return 1.0


func _override_for_value(mode: String, authored: float, value: float) -> float:
	if mode == "mult":
		return (value / authored) if authored > 0.0 else 1.0
	return value - authored


func _make_slider_row(label_text: String, info: Dictionary, mode: String, stat_key: String, on_change: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	hb.add_child(name_lbl)
	var sld := HSlider.new()
	sld.min_value = float(info.min)
	sld.max_value = float(info.max)
	sld.step = float(info.step)
	sld.value = float(info.current)
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sld.custom_minimum_size = Vector2(220, 0)
	hb.add_child(sld)
	var val_lbl := Label.new()
	val_lbl.text = _format_value(stat_key, mode, float(info.current), float(info.override))
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.custom_minimum_size = Vector2(150, 0)
	hb.add_child(val_lbl)
	sld.value_changed.connect(func(v: float):
		on_change.call(v)
		var new_ov: float = _override_for_value(mode, _authored_from_info(info, mode), v)
		val_lbl.text = _format_value(stat_key, mode, v, new_ov))
	return hb


func _authored_from_info(info: Dictionary, mode: String) -> float:
	# Reverse the slider-bounds math to recover the authored value at row
	# build time. _slider_bounds stores override + current; authored is
	# implicit. For mult mode, current = authored × override → authored =
	# current / override. For add mode, authored = current - override.
	if mode == "mult":
		var cur: float = float(info.current)
		var ov: float = float(info.override)
		return (cur / ov) if absf(ov) > 0.0001 else cur
	return float(info.current) - float(info.override)


func _format_value(stat_key: String, mode: String, absolute: float, override: float) -> String:
	if mode == "add":
		return "%.2f  (%+.2f)" % [absolute, override]
	match stat_key:
		"hp_mult":           return "%d  (×%.2f)" % [int(round(absolute)), override]
		"damage_mult":       return "%.1f  (×%.2f)" % [absolute, override]
		"range_mult":        return "%d  (×%.2f)" % [int(round(absolute)), override]
		"speed_mult":        return "%d  (×%.2f)" % [int(round(absolute)), override]
		"attack_speed_mult": return "%.2f  (×%.2f)" % [absolute, override]
		"cooldown_mult":     return "%.1fs  (×%.2f)" % [absolute, override]
		"aoe_radius_mult":   return "%d  (×%.2f)" % [int(round(absolute)), override]
	return "%.2f  (×%.2f)" % [absolute, override]


func _add_inert_row(parent: VBoxContainer, label: String, text: String) -> void:
	var hb := HBoxContainer.new()
	var nl := Label.new()
	nl.text = label
	nl.add_theme_font_size_override("font_size", 13)
	nl.custom_minimum_size = Vector2(180, 0)
	var vl := Label.new()
	vl.text = text
	vl.add_theme_font_size_override("font_size", 13)
	vl.modulate = Color(0.55, 0.60, 0.68)
	hb.add_child(nl)
	hb.add_child(vl)
	parent.add_child(hb)


# ── Bake / Reset / Back ─────────────────────────────────────────────────

func _on_bake_pressed() -> void:
	var hero_deltas: Array = _collect_hero_deltas()
	var skill_deltas: Array = _collect_skill_deltas()
	if hero_deltas.is_empty() and skill_deltas.is_empty():
		Toast.show_message("No hero/skill overrides to bake")
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Bake hero + skill overrides?"
	var bits: PackedStringArray = []
	if not hero_deltas.is_empty():
		bits.append("%d field(s) across %d hero(es)" % [hero_deltas.size(), _unique_hero_count(hero_deltas)])
	if not skill_deltas.is_empty():
		bits.append("%d field(s) across %d skill(s)" % [skill_deltas.size(), _unique_skill_count(skill_deltas)])
	dlg.dialog_text = "%s will be written into res:// .tres files.\n\nThis modifies authored content. Use git to review or revert.\n\nProceed?" % " and ".join(bits)
	dlg.ok_button_text = "Bake"
	dlg.confirmed.connect(func():
		if not hero_deltas.is_empty():
			_apply_hero_bake(hero_deltas)
		if not skill_deltas.is_empty():
			_apply_skill_bake(skill_deltas)
		_refresh()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


func _on_reset_pressed() -> void:
	_BalanceOverrides.reset_hero_overrides()
	_BalanceOverrides.reset_skill_overrides()
	_refresh()


func _on_back_pressed() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


# ── Bake helpers ────────────────────────────────────────────────────────

func _collect_hero_deltas() -> Array:
	var out: Array = []
	for hero in ContentRegistry.heroes:
		if hero == null or not ("hero_id" in hero):
			continue
		for stat_def in _HERO_STAT_DEFS:
			var stat_key: String = String(stat_def.key)
			var mode: String = String(stat_def.mode)
			var prop: String = String(stat_def.prop)
			if not (prop in hero):
				continue
			var override: float = _BalanceOverrides.get_hero_mult(String(hero.hero_id), stat_key)
			var default: float = 0.0 if mode == "add" else 1.0
			if absf(override - default) < 0.0001:
				continue
			var authored: float = float(hero.get(prop))
			var new_val: float
			if mode == "mult":
				if authored <= 0.0:
					continue
				new_val = authored * override
			else:
				new_val = clampf(authored + override, 0.0, 0.95)
			out.append({
				"target": hero, "property": prop, "mode": mode,
				"override": override, "authored": authored, "new_value": new_val,
				"id": String(hero.hero_id),
			})
	return out


func _collect_skill_deltas() -> Array:
	var out: Array = []
	# Walk every skill referenced by any hero. A skill .tres is shared by
	# reference, so iterating heroes' skill arrays + dedup-by-resource_path
	# avoids visiting the same .tres twice.
	var seen_paths: Dictionary = {}
	for hero in ContentRegistry.heroes:
		if hero == null or not ("skills" in hero):
			continue
		for skill in hero.skills:
			if skill == null or not ("skill_id" in skill):
				continue
			var path: String = String(skill.resource_path)
			if path == "" or seen_paths.has(path):
				continue
			seen_paths[path] = true
			for stat_def in _SKILL_STAT_DEFS:
				var stat_key: String = String(stat_def.key)
				var prop: String = String(stat_def.prop)
				if not (prop in skill):
					continue
				var override: float = _BalanceOverrides.get_skill_mult(String(skill.skill_id), stat_key)
				if absf(override - 1.0) < 0.0001:
					continue
				var authored: float = float(skill.get(prop))
				if authored <= 0.0:
					continue
				out.append({
					"target": skill, "property": prop, "mode": "mult",
					"override": override, "authored": authored,
					"new_value": authored * override,
					"id": String(skill.skill_id),
				})
	return out


func _unique_hero_count(deltas: Array) -> int:
	var seen: Dictionary = {}
	for d in deltas:
		seen[d.id] = true
	return seen.size()


func _unique_skill_count(deltas: Array) -> int:
	var seen: Dictionary = {}
	for d in deltas:
		seen[d.id] = true
	return seen.size()


func _apply_hero_bake(deltas: Array) -> void:
	_apply_bake(deltas, ["max_health"])
	_BalanceOverrides.reset_hero_overrides()


func _apply_skill_bake(deltas: Array) -> void:
	# All current skill props (damage / cooldown / skill_range / aoe_radius)
	# are floats — no int rounding.
	_apply_bake(deltas, [])
	_BalanceOverrides.reset_skill_overrides()


# Generic bake step: write each delta's new_value into target.<property>,
# rounding to int for any property listed in `int_props`. Resource saves
# are deduped by resource_path.
func _apply_bake(deltas: Array, int_props: Array) -> void:
	var touched: Dictionary = {}
	var summary: PackedStringArray = []
	for d in deltas:
		var target: Resource = d.target
		if target == null:
			continue
		var prop: String = String(d.property)
		var new_val: float = float(d.new_value)
		var authored: float = float(d.authored)
		if prop in int_props:
			var iv: int = int(round(new_val))
			target.set(prop, iv)
			summary.append("  %s %s  %d → %d (%s %.2f)" % [
				d.id, prop, int(round(authored)), iv,
				"+" if d.mode == "add" else "×", float(d.override),
			])
		else:
			target.set(prop, new_val)
			summary.append("  %s %s  %.2f → %.2f (%s %.2f)" % [
				d.id, prop, authored, new_val,
				"+" if d.mode == "add" else "×", float(d.override),
			])
		var path: String = String(target.resource_path)
		if path != "":
			touched[path] = target
	for path in touched.keys():
		var err: int = ResourceSaver.save(touched[path], path)
		if err != OK:
			push_warning("[HeroTuning/Bake] save failed for %s (err %d)" % [path, err])
	print("[HeroTuning/Bake] wrote %d field(s) across %d resource(s)" % [deltas.size(), touched.size()])
	for line in summary:
		print(line)
