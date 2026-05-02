extends Control

# Phase B — Heroes hub with five tabs:
#   - Loadout   : hero picker (built inline below)
#   - Stats     : "coming soon" stub
#   - Equipment : embeds EquipmentScreen.tscn (TopBar/Background hidden)
#   - Skills    : per-hero skill loadout editor
#   - Talents   : embeds TalentScreen.tscn (TopBar/Background hidden)
#
# Single-row top bar holds Back + 5 segment pills + hero context (name /
# level + xp / gold). Replaces the old TopBar+TabContainer pair so all
# touch targets sit on one row at 64 px tall — better for mobile, and it
# frees ~50 px of vertical space for embedded content underneath.
#
# Embedded screens (Equipment / Talents) hide their own TopBar/Background
# in `_embed_screen` and pull their body offsets up so they fill the
# ContentArea cleanly.

@onready var hub_bar: HBoxContainer = %HubBar
@onready var back_button: Button = %BackButton
@onready var segment_group: HBoxContainer = %SegmentGroup
@onready var context_group: VBoxContainer = %ContextGroup
@onready var hero_name_label: Label = %HeroNameLabel
@onready var hero_level_label: Label = %HeroLevelLabel
@onready var hero_gold_label: Label = %HeroGoldLabel
@onready var content_area: Control = %ContentArea
@onready var loadout_tab: Control = %Loadout
@onready var stats_tab: Control = %Stats
@onready var equipment_tab: Control = %Equipment
@onready var skills_tab: Control = %Skills
@onready var talents_tab: Control = %Talents

# Loadout-tab UI built in script.
var _hero_label: Label
var _switch_button: Button

# --- Segment bar visual constants ------------------------------------------
const _HUB_BAR_HEIGHT: int = 80
const _SEGMENT_SIZE: Vector2 = Vector2(160, 64)
const _BACK_BUTTON_SIZE: Vector2 = Vector2(96, 64)
const _SEGMENT_GAP: int = 8
const _ACTIVE_FILL: Color = Color(0.18, 0.24, 0.34, 1.0)
const _INACTIVE_FILL: Color = Color(0.12, 0.16, 0.22, 1.0)
const _SEGMENT_BORDER: Color = Color(0.28, 0.34, 0.46, 1.0)
const _ACTIVE_UNDERLINE: Color = Color(1.0, 0.85, 0.4, 1.0)
const _LABEL_ACTIVE: Color = Color(1.0, 1.0, 1.0, 1.0)
const _LABEL_INACTIVE: Color = Color(0.6, 0.66, 0.78, 1.0)
const _GLYPH_ACTIVE: Color = Color(1.0, 0.85, 0.4, 1.0)
const _GLYPH_INACTIVE: Color = Color(0.65, 0.72, 0.85, 1.0)

const _SEGMENTS: Array = [
	{"id": "loadout",   "label": "Loadout",  "glyph": "loadout"},
	{"id": "stats",     "label": "Stats",    "glyph": "stats"},
	{"id": "equipment", "label": "Equip",    "glyph": "equipment"},
	{"id": "skills",    "label": "Skills",   "glyph": "skills"},
	{"id": "talents",   "label": "Talents",  "glyph": "talents"},
]

var _segment_buttons: Dictionary = {}   # id -> SegmentButton
var _tab_controls: Dictionary = {}      # id -> Control
var _active_segment: String = "loadout"

# Skills-tab state — armed-skill picker for tap-to-equip.
const _SKILLS_TILE_SIZE: Vector2 = Vector2(120.0, 80.0)
const _SKILLS_ARMED_COLOR: Color = Color(1.0, 0.85, 0.35, 1.0)
const _SKILLS_NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const _SKILLS_LOCKED_COLOR: Color = Color(0.55, 0.55, 0.6, 0.9)

var _skills_armed: String = ""
var _skills_header_label: Label = null
var _skills_equipped_row: HBoxContainer = null
var _skills_available_grid: HFlowContainer = null
var _skills_locked_grid: HFlowContainer = null


func _ready() -> void:
	back_button.pressed.connect(_on_back)

	_tab_controls = {
		"loadout": loadout_tab,
		"stats": stats_tab,
		"equipment": equipment_tab,
		"skills": skills_tab,
		"talents": talents_tab,
	}

	_build_segment_bar()
	_build_loadout_tab()
	_embed_screen(equipment_tab, "res://ui/EquipmentScreen.tscn")
	_build_coming_soon_tab(stats_tab, "Stats", "Strength · Stamina · Dexterity\n(future system)")
	_build_skills_tab(skills_tab)
	_embed_screen(talents_tab, "res://ui/TalentScreen.tscn")

	_refresh_context_group()
	_set_active_segment("loadout")

	# Listeners — context line refreshes on hero swap, gold change, xp gain.
	# Skills tab listens for the same hero swap + skill loadout edits.
	EventBus.hero_selected.connect(_on_hero_selected_changed)
	EventBus.hero_skill_equipped.connect(func(_h, _s, _id): _refresh_skills_tab())
	EventBus.meta_gold_changed.connect(func(_v): _refresh_context_group())
	EventBus.hero_xp_gained.connect(func(_v): _refresh_context_group())
	EventBus.hero_leveled_up.connect(func(_v): _refresh_context_group())


func _on_hero_selected_changed(_hero_id: String) -> void:
	_refresh_context_group()
	_refresh_loadout()
	_refresh_skills_tab()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


# --- Segment bar -----------------------------------------------------------

func _build_segment_bar() -> void:
	back_button.custom_minimum_size = _BACK_BUTTON_SIZE
	for entry in _SEGMENTS:
		var seg: SegmentButton = SegmentButton.new()
		seg.setup(String(entry["id"]), String(entry["label"]), String(entry["glyph"]))
		seg.custom_minimum_size = _SEGMENT_SIZE
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg.pressed.connect(_on_segment_pressed.bind(String(entry["id"])))
		segment_group.add_child(seg)
		_segment_buttons[String(entry["id"])] = seg


func _on_segment_pressed(id: String) -> void:
	_set_active_segment(id)


func _set_active_segment(id: String) -> void:
	if not _tab_controls.has(id):
		return
	_active_segment = id
	for tab_id in _tab_controls.keys():
		var tab: Control = _tab_controls[tab_id]
		if tab != null:
			tab.visible = (tab_id == id)
	for seg_id in _segment_buttons.keys():
		var seg: SegmentButton = _segment_buttons[seg_id]
		if seg != null:
			seg.set_active(seg_id == id)


# --- Hero context group ----------------------------------------------------

func _refresh_context_group() -> void:
	if hero_name_label == null:
		return
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null:
		hero_name_label.text = "No hero"
		hero_level_label.text = ""
		hero_gold_label.text = "💰 %d" % MetaProgression.meta_gold
		return
	var hid: String = hero_data.hero_id
	var lvl: int = MetaProgression.get_hero_level(hid)
	var xp: int = MetaProgression.get_hero_xp(hid)
	var need: int = 0
	if lvl - 1 >= 0 and lvl - 1 < hero_data.xp_per_level.size():
		need = hero_data.xp_per_level[lvl - 1]
	var xp_str: String = "MAX" if lvl >= int(hero_data.max_level) else "XP %d/%d" % [xp, need]
	hero_name_label.text = hero_data.hero_name
	hero_level_label.text = "Lv %d   %s" % [lvl, xp_str]
	hero_gold_label.text = "💰 %d" % MetaProgression.meta_gold


# --- Loadout tab (inline) ---------------------------------------------------

func _build_loadout_tab() -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set("theme_override_constants/separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_tab.add_child(vbox)

	_hero_label = Label.new()
	_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_label.set("theme_override_font_sizes/font_size", 18)
	vbox.add_child(_hero_label)

	_switch_button = Button.new()
	_switch_button.text = "◄  Switch Hero  ►"
	_switch_button.custom_minimum_size = Vector2(280, 60)
	_switch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_switch_button.set("theme_override_font_sizes/font_size", 20)
	_switch_button.pressed.connect(_on_switch_hero)
	vbox.add_child(_switch_button)

	_refresh_loadout()


func _refresh_loadout() -> void:
	if _hero_label == null:
		return
	var heroes: Array = ContentRegistry.heroes
	if heroes.is_empty():
		_hero_label.text = "No heroes available"
		_switch_button.disabled = true
		return
	var selected: Resource = null
	for h in heroes:
		if h.hero_id == LoadoutState.selected_hero_id and UnlockManager.is_hero_unlocked(h.hero_id):
			selected = h
			break
	if selected == null:
		for h in heroes:
			if UnlockManager.is_hero_unlocked(h.hero_id):
				selected = h
				break
	if selected == null:
		selected = heroes[0]
	LoadoutState.selected_hero_id = selected.hero_id

	var dmg_type: String = "Magic" if selected.damage_type == 1 else "Physical"
	var skill_names: PackedStringArray = []
	for s in selected.skills:
		if s != null and "skill_name" in s:
			skill_names.append(s.skill_name)
	_hero_label.text = "%s  (%s)\nHP %d   DMG %.0f   RNG %.0f   SPD %.1f\nSkills: %s" % [
		selected.hero_name, dmg_type, selected.max_health,
		selected.attack_damage, selected.attack_range, selected.attack_speed,
		", ".join(skill_names),
	]
	var unlocked_count: int = 0
	for h in heroes:
		if UnlockManager.is_hero_unlocked(h.hero_id):
			unlocked_count += 1
	_switch_button.disabled = unlocked_count <= 1


func _on_switch_hero() -> void:
	var heroes: Array = ContentRegistry.heroes
	if heroes.size() <= 1:
		return
	var current_idx: int = 0
	for i in heroes.size():
		if heroes[i].hero_id == LoadoutState.selected_hero_id:
			current_idx = i
			break
	for offset in range(1, heroes.size()):
		var try_idx: int = (current_idx + offset) % heroes.size()
		var candidate: Resource = heroes[try_idx]
		if UnlockManager.is_hero_unlocked(candidate.hero_id):
			LoadoutState.selected_hero_id = candidate.hero_id
			EventBus.hero_selected.emit(candidate.hero_id)
			_refresh_loadout()
			return


# --- Embed pattern for existing standalone screens --------------------------

func _embed_screen(tab: Control, scene_path: String) -> void:
	# Instance the screen scene as a child of the tab. Hide the screen's own
	# TopBar (back/title) and Background — the hub provides those — and reset
	# the body offset so content fills the tab area cleanly. The hub bar is
	# the clearance, so embedded body anchors start at y=0 of ContentArea.
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("[HeroesHub] failed to load %s" % scene_path)
		return
	var screen: Control = packed.instantiate()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_child(screen)

	var top_bar: Control = screen.get_node_or_null("TopBar")
	if top_bar != null:
		top_bar.visible = false

	var bg: Control = screen.get_node_or_null("Background")
	if bg != null:
		bg.visible = false

	# Equipment screen: HeroLabel lives inside the (now hidden) TopBar.
	# Hide it in embed mode — the hub's ContextGroup already shows hero name.
	var hero_label: Control = screen.get_node_or_null("TopBar/HeroLabel")
	if hero_label != null:
		hero_label.visible = false

	# Embedded screen body offset — small inner padding so the first row of
	# slots/items doesn't visually touch the segment bar above. Hub bar ends
	# at y=80, ContentArea starts at y=88; +16 here gives a 24-px gap.
	var body: Control = screen.get_node_or_null("Body")
	if body != null:
		body.offset_top = 16.0

	# Hide section headers that duplicate context already provided by
	# HeroesHub's segment bar ("Equipment" tab) and the relocated HeroLabel.
	for header_path in ["Body/LeftPanel/LeftTitle", "Body/LeftPanel/StatsTitle", "Body/LeftPanel/DetailsTitle"]:
		var header: Control = screen.get_node_or_null(header_path)
		if header != null:
			header.visible = false

	# Talent screen: pull StarsLabel + ScrollContainer toward the top of the
	# area, leaving the same 16-px inner padding as the Body offset above.
	var stars: Control = screen.get_node_or_null("StarsLabel")
	if stars != null:
		stars.offset_top = 16.0
		stars.offset_bottom = 44.0
	var scroll: Control = screen.get_node_or_null("ScrollContainer")
	if scroll != null:
		scroll.offset_top = 56.0


# --- Skills tab (per-hero loadout editor) ----------------------------------

func _build_skills_tab(tab: Control) -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set("theme_override_constants/separation", 16)
	vbox.add_child(vbox_margin_top(16))
	tab.add_child(vbox)

	_skills_header_label = Label.new()
	_skills_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skills_header_label.set("theme_override_font_sizes/font_size", 22)
	vbox.add_child(_skills_header_label)

	_add_section_label(vbox, "EQUIPPED  (tap to clear)")
	_skills_equipped_row = HBoxContainer.new()
	_skills_equipped_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_skills_equipped_row.set("theme_override_constants/separation", 16)
	vbox.add_child(_skills_equipped_row)

	_add_section_label(vbox, "AVAILABLE  (tap a skill, then tap an equipped slot)")
	_skills_available_grid = HFlowContainer.new()
	_skills_available_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_available_grid.set("theme_override_constants/h_separation", 12)
	_skills_available_grid.set("theme_override_constants/v_separation", 12)
	vbox.add_child(_skills_available_grid)

	_add_section_label(vbox, "LOCKED  (unlock by leveling)")
	_skills_locked_grid = HFlowContainer.new()
	_skills_locked_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_locked_grid.set("theme_override_constants/h_separation", 12)
	_skills_locked_grid.set("theme_override_constants/v_separation", 12)
	vbox.add_child(_skills_locked_grid)

	_refresh_skills_tab()


func _refresh_skills_tab() -> void:
	if _skills_header_label == null:
		return
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null:
		_skills_header_label.text = "No hero selected"
		_clear_children(_skills_equipped_row)
		_clear_children(_skills_available_grid)
		_clear_children(_skills_locked_grid)
		return
	var hid: String = hero_data.hero_id
	var lvl: int = MetaProgression.get_hero_level(hid)
	var xp: int = MetaProgression.get_hero_xp(hid)
	var need: int = 0
	if lvl - 1 >= 0 and lvl - 1 < hero_data.xp_per_level.size():
		need = hero_data.xp_per_level[lvl - 1]
	var xp_str: String = "MAX" if lvl >= int(hero_data.max_level) else "XP %d/%d" % [xp, need]
	_skills_header_label.text = "%s   Lv %d   %s" % [hero_data.hero_name, lvl, xp_str]

	_clear_children(_skills_equipped_row)
	var equipped: Array[String] = LoadoutState.get_equipped_skills(hid)
	for slot_idx in LoadoutState.EQUIPPED_SKILL_SLOTS:
		var sid: String = equipped[slot_idx] if slot_idx < equipped.size() else ""
		var tile: Button = _make_skill_button(_skill_name(hero_data, sid) if sid != "" else "(empty)",
			"", false, sid != "")
		tile.pressed.connect(_on_skills_equipped_slot_pressed.bind(slot_idx))
		_skills_equipped_row.add_child(tile)

	_clear_children(_skills_available_grid)
	var unlocked: Array[String] = LoadoutState.get_unlocked_skill_ids(hid)
	for sid in unlocked:
		var name_str: String = _skill_name(hero_data, sid)
		var armed: bool = (_skills_armed == sid)
		var tile: Button = _make_skill_button(name_str, "", armed, true)
		tile.pressed.connect(_on_skills_available_pressed.bind(sid))
		_skills_available_grid.add_child(tile)

	_clear_children(_skills_locked_grid)
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr <= lvl:
			continue
		var tile: Button = _make_skill_button("???", "Lv %d" % lr, false, false)
		tile.disabled = true
		_skills_locked_grid.add_child(tile)


func _make_skill_button(title: String, sub: String, armed: bool, enabled: bool) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = _SKILLS_TILE_SIZE
	btn.set("theme_override_font_sizes/font_size", 16)
	btn.text = title if sub == "" else "%s\n%s" % [title, sub]
	btn.modulate = _SKILLS_ARMED_COLOR if armed else (_SKILLS_NORMAL_COLOR if enabled else _SKILLS_LOCKED_COLOR)
	return btn


func _on_skills_equipped_slot_pressed(slot_idx: int) -> void:
	var hid: String = LoadoutState.selected_hero_id
	if _skills_armed != "":
		var sid: String = _skills_armed
		_skills_armed = ""
		LoadoutState.set_equipped_skill(hid, slot_idx, sid)
		SaveManager.save_game()
	else:
		LoadoutState.set_equipped_skill(hid, slot_idx, "")
		SaveManager.save_game()


func _on_skills_available_pressed(skill_id: String) -> void:
	if _skills_armed == skill_id:
		_skills_armed = ""
	else:
		_skills_armed = skill_id
	_refresh_skills_tab()


func _skill_name(hero_data: Resource, skill_id: String) -> String:
	if skill_id == "":
		return ""
	for skill in hero_data.skills:
		if skill != null and skill.skill_id == skill_id:
			return skill.skill_name
	return skill_id


func _clear_children(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _add_section_label(parent: Control, text: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set("theme_override_font_sizes/font_size", 14)
	lbl.modulate = Color(0.65, 0.72, 0.85, 1.0)
	parent.add_child(lbl)


func vbox_margin_top(px: int) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, px)
	return spacer


# --- "Coming soon" stub builder --------------------------------------------

func _build_coming_soon_tab(tab: Control, title: String, subtitle: String) -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set("theme_override_constants/separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab.add_child(vbox)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set("theme_override_font_sizes/font_size", 28)
	vbox.add_child(title_label)

	var subtitle_label: Label = Label.new()
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.modulate = Color(0.65, 0.72, 0.85, 1.0)
	subtitle_label.set("theme_override_font_sizes/font_size", 16)
	vbox.add_child(subtitle_label)

	var hint_label: Label = Label.new()
	hint_label.text = "Coming soon"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.modulate = Color(0.5, 0.55, 0.65, 1.0)
	hint_label.set("theme_override_font_sizes/font_size", 14)
	vbox.add_child(hint_label)


# --- SegmentButton — inline pill widget ------------------------------------

class SegmentButton extends Button:
	# A single segment in the hub's top bar. Draws its own chassis + glyph
	# + label so the pill style is consistent across all five tabs without
	# theming gymnastics. Active state shows a filled chassis and a 2-px
	# gold underline; inactive is hollow with muted text and glyph.

	const _LABEL_FONT_SIZE: int = 14
	const _GLYPH_RADIUS: float = 16.0
	const _UNDERLINE_HEIGHT: float = 2.0
	const _UNDERLINE_INSET_X: float = 18.0
	const _CORNER_RADIUS: float = 6.0
	const _ACTIVE_FILL_C: Color = Color(0.18, 0.24, 0.34, 1.0)
	const _INACTIVE_FILL_C: Color = Color(0.12, 0.16, 0.22, 1.0)
	const _BORDER_C: Color = Color(0.28, 0.34, 0.46, 1.0)
	const _UNDERLINE_C: Color = Color(1.0, 0.85, 0.4, 1.0)
	const _LABEL_ACTIVE_C: Color = Color(1.0, 1.0, 1.0, 1.0)
	const _LABEL_INACTIVE_C: Color = Color(0.6, 0.66, 0.78, 1.0)
	const _GLYPH_ACTIVE_C: Color = Color(1.0, 0.85, 0.4, 1.0)
	const _GLYPH_INACTIVE_C: Color = Color(0.65, 0.72, 0.85, 1.0)

	var _kind: String = ""
	var _segment_id: String = ""
	var _label_text: String = ""
	var _active: bool = false

	func setup(id: String, label: String, glyph: String) -> void:
		_segment_id = id
		_label_text = label
		_kind = glyph
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		queue_redraw()

	func set_active(active: bool) -> void:
		if _active == active:
			return
		_active = active
		queue_redraw()

	func _draw() -> void:
		var fill: Color = _ACTIVE_FILL_C if _active else _INACTIVE_FILL_C
		# Pill chassis: body rect + two side discs to fake rounded corners.
		var inset_x: float = _CORNER_RADIUS
		var body_rect := Rect2(Vector2(inset_x, 0.0), Vector2(size.x - inset_x * 2.0, size.y))
		draw_rect(body_rect, fill, true)
		var cap_y: float = size.y * 0.5
		draw_circle(Vector2(inset_x, cap_y), size.y * 0.5, fill)
		draw_circle(Vector2(size.x - inset_x, cap_y), size.y * 0.5, fill)
		# Border outline.
		draw_rect(body_rect, _BORDER_C, false, 1.0)
		draw_arc(Vector2(inset_x, cap_y), size.y * 0.5, PI * 0.5, PI * 1.5, 12, _BORDER_C, 1.0, true)
		draw_arc(Vector2(size.x - inset_x, cap_y), size.y * 0.5, -PI * 0.5, PI * 0.5, 12, _BORDER_C, 1.0, true)
		# Active underline.
		if _active:
			var u_rect := Rect2(
				Vector2(_UNDERLINE_INSET_X, size.y - 8.0 - _UNDERLINE_HEIGHT),
				Vector2(size.x - _UNDERLINE_INSET_X * 2.0, _UNDERLINE_HEIGHT)
			)
			draw_rect(u_rect, _UNDERLINE_C, true)
		# Glyph + label.
		var glyph_center := Vector2(size.x * 0.5, size.y * 0.36)
		var glyph_color: Color = _GLYPH_ACTIVE_C if _active else _GLYPH_INACTIVE_C
		HubTabIcon.draw(self, _kind, glyph_center, _GLYPH_RADIUS, glyph_color)
		var font := get_theme_default_font()
		if font != null:
			var label_color: Color = _LABEL_ACTIVE_C if _active else _LABEL_INACTIVE_C
			var size_str := font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, _LABEL_FONT_SIZE)
			var label_pos := Vector2(
				(size.x - size_str.x) * 0.5,
				size.y * 0.78,
			)
			draw_string(font, label_pos, _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _LABEL_FONT_SIZE, label_color)
