extends Control

# Hero Hall hub.
#
# Layout:
#   TopBar      : Close button (✕, always exits to WorldMap) + title + meta gold
#   HeroSidebar : compact 140-px column — hero portrait buttons (top, scroll),
#                 divider, page-nav buttons (bottom): Overview / Equip / Skills / Talents
#   MainStack:
#     HeroHallView — big procedural portrait + name/level/XP, POWER /
#                    READY CHECK / PASSIVES summary panel
#     SubView      — swapped in when a nav button is tapped. Equipment /
#                    Talents = embedded scenes; Skills = built inline
#                    (drag-and-drop only).
#
# Sidebar stays visible inside sub-views so the player can switch hero
# without backing out. Switching hero in any view emits `hero_selected`,
# which the embedded screens already listen for.

const _HeroSidebarButtonScript := preload("res://ui/HeroSidebarButton.gd")
# Phase 3R-followup — preload so the Kind enum is resolvable regardless of
# class_name registry order. Matches the pattern used in MetaProgression /
# LoadoutState / HeroSkillTreeScreen.
const _HeroSkillNodeDataScript := preload("res://heroes/HeroSkillNodeData.gd")
# HeroStats interface (Preventive Bug Rule, CLAUDE.md): the canonical way
# for UI to read effective hero stats with gear modifiers applied. Preload
# so the script is resolvable regardless of Godot's class_name scan order.
const _HeroStats := preload("res://heroes/HeroStats.gd")

# Phase 51 — sidebar size system. The 140-px sidebar replaces the prior
# 304-px RosterRail; nav buttons and hero buttons share the touch-target
# floor enforced by NAV_BUTTON_SIZE / HERO_BUTTON_SIZE.
const SIDEBAR_W: float = 140.0
const SIDEBAR_COLLAPSE_WIDTH: float = 1450.0  # reserved for future tight mode
const HERO_BUTTON_SIZE: Vector2 = Vector2(120, 112)
const NAV_BUTTON_SIZE: Vector2 = Vector2(120, 80)

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var meta_gold_label: Label = %MetaGoldLabel
@onready var hero_sidebar: VBoxContainer = %HeroSidebar
@onready var hero_scroll: ScrollContainer = %HeroScroll
@onready var hero_button_list: VBoxContainer = %HeroButtonList
@onready var page_nav: VBoxContainer = %PageNav
@onready var hero_hall_view: Control = %HeroHallView
@onready var sub_view: Control = %SubView

# State machine: "" = Hero Hall, otherwise "stats"|"equipment"|"skills"|"talents".
var _current_sub: String = ""

# Cached widgets — cards by hero_id, action tiles by kind.
var _hero_cards: Dictionary = {}

# Hero Hall view widgets — built once in _build_hero_hall, refreshed in _refresh_hero_hall.
var _hall_portrait: Control = null
var _hall_name_label: Label = null
var _hall_level_label: Label = null
var _hall_xp_bar: ProgressBar = null
var _hall_xp_label: Label = null
var _hall_stats_label: Label = null
var _hall_ready_label: Label = null
var _hall_passives_label: Label = null

# Skills sub-view state — drag-and-drop participants.
var _skills_equipped_slots: Array = []
var _skills_available_grid: HFlowContainer = null
var _skills_locked_grid: HFlowContainer = null
var _skills_header_label: Label = null
# Phase 3R-followup — picker redesign. Inspector panel on the right of the
# tile grid; tracks the currently-inspected skill_id so the panel can
# re-render on rank / mod / equip / passive changes without rebuilding the
# whole sub-view. Selection survives slot equips / unequips.
var _skills_inspector_panel: VBoxContainer = null
var _selected_skill_id: String = ""
# Phase 3R-followup — connected once and reused across sub-view rebuilds.
# Tracked so we can re-disconnect on _close_sub_view; otherwise rebuilding
# the Skills page would stack signal connections.
var _skills_signals_connected: bool = false

const _PORTRAIT_DRAW_SCALE: float = 5.5
const _PORTRAIT_ANCHOR_FRACTION: float = 0.82
const _PORTRAIT_BG: Color = Color(0.07, 0.09, 0.12, 1.0)
const _PORTRAIT_BORDER: Color = Color(0.25, 0.30, 0.40, 1.0)
const _PORTRAIT_FLOOR: Color = Color(0.13, 0.16, 0.22, 1.0)


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	# Defensive: if the save's selected_hero_id is empty / stale (renamed
	# hero, fresh save, etc.), fall back to the first unlocked hero so the
	# hub never opens to a "No hero" wasteland.
	_ensure_hero_selected()
	_build_hero_sidebar()
	_build_page_nav()
	_build_hero_hall()
	_refresh_meta_gold()
	_refresh_hero_hall()
	_set_active_nav("")
	_connect_events()


func _ensure_hero_selected() -> void:
	if not has_node("/root/ContentRegistry"):
		return
	var current: String = LoadoutState.selected_hero_id
	if current != "":
		var hero: Resource = ContentRegistry.find_hero(current)
		if hero != null:
			var unlocked: bool = true
			if "requires_unlock" in hero and hero.requires_unlock:
				unlocked = UnlockManager.is_hero_unlocked(current)
			if unlocked:
				return
	for hero in ContentRegistry.heroes:
		if hero == null or not ("hero_id" in hero):
			continue
		var hid: String = String(hero.hero_id)
		var ok: bool = true
		if "requires_unlock" in hero and hero.requires_unlock:
			ok = UnlockManager.is_hero_unlocked(hid)
		if ok:
			LoadoutState.selected_hero_id = hid
			EventBus.hero_selected.emit(hid)
			return


func _connect_events() -> void:
	EventBus.hero_selected.connect(_on_hero_selected)
	EventBus.hero_skill_equipped.connect(func(_h, _s, _id) -> void:
		_refresh_nav_state()
		if _current_sub == "skills":
			_refresh_skills_subview()
	)
	EventBus.meta_gold_changed.connect(func(_v) -> void: _refresh_meta_gold())
	EventBus.hero_xp_gained.connect(func(_v) -> void:
		_refresh_hero_hall()
		_refresh_roster_progress()
	)
	EventBus.hero_leveled_up.connect(func(_v) -> void:
		_refresh_hero_hall()
		_refresh_roster_progress()
	)
	EventBus.inventory_changed.connect(_refresh_nav_state)
	EventBus.item_equipped.connect(func(_h, _s, _i) -> void: _refresh_hero_hall())
	EventBus.item_unequipped.connect(func(_h, _s, _i) -> void: _refresh_hero_hall())


# --- Hero sidebar (Phase 51) ---------------------------------------------
# Compact 120×112 portrait buttons, vertically scrolling. Replaces the
# prior 304-px RosterRail of 280-wide HeroCards. Public API of the button
# (setup / set_selected / get_hero_id) is identical so the rest of the
# hub doesn't care which widget is in the list.

func _build_hero_sidebar() -> void:
	for child in hero_button_list.get_children():
		child.queue_free()
	_hero_cards.clear()
	if not has_node("/root/ContentRegistry"):
		return
	var heroes: Array = ContentRegistry.heroes
	for hero in heroes:
		if hero == null or not ("hero_id" in hero):
			continue
		var btn: Button = _HeroSidebarButtonScript.new()
		hero_button_list.add_child(btn)
		btn.setup(hero)
		btn.set_selected(String(hero.hero_id) == LoadoutState.selected_hero_id)
		btn.pressed.connect(_on_card_pressed.bind(btn))
		_hero_cards[String(hero.hero_id)] = btn


func _on_card_pressed(card: Button) -> void:
	var hid: String = card.get_hero_id()
	if hid == "" or hid == LoadoutState.selected_hero_id:
		return
	if not UnlockManager.is_hero_unlocked(hid):
		return
	LoadoutState.selected_hero_id = hid
	EventBus.hero_selected.emit(hid)


func _refresh_roster_progress() -> void:
	for hid in _hero_cards.keys():
		var btn: Button = _hero_cards[hid]
		if btn != null and btn.has_method("setup"):
			btn.setup(ContentRegistry.find_hero(hid))
			btn.set_selected(hid == LoadoutState.selected_hero_id)


# --- Sidebar page nav (Phase 51) ------------------------------------------
# Four nav buttons under the divider: Overview / Equip / Skills / Talents.
# Pressing a nav button calls _open_sub_view; Overview maps to the
# empty-string sub_view (= back to Hero Hall).

const _NAV_ENTRIES: Array = [
	["",         "overview",  "Overview"],
	["equipment","equipment", "Equip"],
	["skills",   "skills",    "Skills"],
	["talents",  "talents",   "Talents"],
]

# kind ("" / "stats" / "equipment" / "skills" / "talents") → _NavButton
var _nav_buttons: Dictionary = {}


func _build_page_nav() -> void:
	for child in page_nav.get_children():
		child.queue_free()
	_nav_buttons.clear()
	for entry in _NAV_ENTRIES:
		var kind: String = String(entry[0])
		var glyph: String = String(entry[1])
		var label: String = String(entry[2])
		var btn := _NavButton.new()
		btn.setup(kind, glyph, label)
		btn.pressed.connect(_on_nav_pressed.bind(kind))
		page_nav.add_child(btn)
		_nav_buttons[kind] = btn


func _on_nav_pressed(kind: String) -> void:
	# Overview = leave any open sub-view (returns to Hero Hall).
	if kind == "":
		if _current_sub != "":
			_close_sub_view()
		return
	_open_sub_view(kind)


func _set_active_nav(kind: String) -> void:
	for k in _nav_buttons.keys():
		var nb = _nav_buttons[k]
		if nb != null and nb.has_method("set_active"):
			nb.set_active(String(k) == kind)


func _refresh_nav_badges() -> void:
	# Same data path as _refresh_nav_state — count surfacing.
	var equipped_items: int = 0
	var total_slots: int = 6
	if has_node("/root/InventoryManager"):
		equipped_items = InventoryManager.get_all_equipped(LoadoutState.selected_hero_id).size()
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data != null and "equipment_slots" in hero_data and hero_data.equipment_slots is Array and hero_data.equipment_slots.size() > 0:
		total_slots = hero_data.equipment_slots.size()
	_set_nav_badge("equipment", "%d/%d" % [equipped_items, total_slots])
	var equipped: Array[String] = LoadoutState.get_equipped_skills(LoadoutState.selected_hero_id)
	var skill_count: int = 0
	for s in equipped:
		if s != "":
			skill_count += 1
	_set_nav_badge("skills", "%d/%d" % [skill_count, LoadoutState.get_active_slot_cap(LoadoutState.selected_hero_id)])
	var stars: int = 0
	if has_node("/root/MetaProgression") and MetaProgression.has_method("get_available_stars"):
		stars = int(MetaProgression.get_available_stars())
	_set_nav_badge("talents", "%d★" % stars if stars > 0 else "")
	_set_nav_badge("", "")


func _set_nav_badge(kind: String, text: String) -> void:
	if not _nav_buttons.has(kind):
		return
	var nb = _nav_buttons[kind]
	if nb != null and nb.has_method("set_badge"):
		nb.set_badge(text)


func _on_hero_selected(hero_id: String) -> void:
	# Roster cards re-mark selected.
	for hid in _hero_cards.keys():
		var btn: Button = _hero_cards[hid]
		if btn != null:
			btn.set_selected(hid == hero_id)
	_refresh_hero_hall()
	_refresh_nav_state()
	# If a sub-view is open, refresh it (Skills rebuilds here; Equipment + Talents
	# listen to hero_selected directly).
	if _current_sub == "skills":
		_refresh_skills_subview()


# --- Hero Hall (main view) ------------------------------------------------

func _build_hero_hall() -> void:
	# Container-driven layout (replaces the prior absolute-anchor bento grid
	# which broke at non-1920×1080 aspect ratios). HeroHallView is a
	# VBoxContainer in the scene; we stack three children:
	#
	#   ┌────────────────────────────────────────────────────────────┐
	#   │ HeroHeader      Name              Lv X · ▓▓▓░░ XP a/b       │
	#   ├──────────────────────────────────────┬─────────────────────┤
	#   │ HeroBody     PortraitPanel (expand)  │ SummaryPanel (360)   │
	#   │              big procedural portrait │ Power · Passives     │
	#   ├──────────────────────────────────────┴─────────────────────┤
	#   │ ActionRow  [Stats] [Equipment] [Skills] [Talents]           │
	#   └────────────────────────────────────────────────────────────┘
	#
	# Each section uses size_flags so widths/heights flow from the
	# available space — a narrower window collapses gracefully.

	# --- HeroHeader (name on left, level + XP bar on right) ---
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 80)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 16)
	hero_hall_view.add_child(header)

	_hall_name_label = Label.new()
	_hall_name_label.text = "Hero"
	_hall_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hall_name_label.size_flags_vertical = Control.SIZE_FILL
	_hall_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hall_name_label.add_theme_font_size_override("font_size", 30)
	header.add_child(_hall_name_label)

	# Right-side level + XP block.
	var xp_block := VBoxContainer.new()
	xp_block.custom_minimum_size = Vector2(360, 0)
	xp_block.size_flags_vertical = Control.SIZE_FILL
	xp_block.alignment = BoxContainer.ALIGNMENT_CENTER
	xp_block.add_theme_constant_override("separation", 4)
	header.add_child(xp_block)

	_hall_level_label = Label.new()
	_hall_level_label.text = "Lv 1"
	_hall_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hall_level_label.add_theme_font_size_override("font_size", 16)
	_hall_level_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1.0))
	xp_block.add_child(_hall_level_label)

	_hall_xp_bar = ProgressBar.new()
	_hall_xp_bar.custom_minimum_size = Vector2(0, 14)
	_hall_xp_bar.show_percentage = false
	_hall_xp_bar.min_value = 0.0
	_hall_xp_bar.max_value = 1.0
	_hall_xp_bar.value = 0.0
	xp_block.add_child(_hall_xp_bar)

	_hall_xp_label = Label.new()
	_hall_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hall_xp_label.add_theme_font_size_override("font_size", 12)
	_hall_xp_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1.0))
	xp_block.add_child(_hall_xp_label)

	# --- HeroBody (portrait expand left, summary fixed right) ---
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	hero_hall_view.add_child(body)

	# Portrait panel — Control wrapper, expand to fill the rest of the row.
	var portrait_panel := _make_panel()
	portrait_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(portrait_panel)

	_hall_portrait = HallPortrait.new()
	_hall_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_panel.add_child(_hall_portrait)

	# Summary panel — fixed-width right side for power + passives.
	var summary_panel := _make_panel()
	summary_panel.custom_minimum_size = Vector2(360, 0)
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(summary_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_vbox.offset_left = 16
	stats_vbox.offset_top = 16
	stats_vbox.offset_right = -16
	stats_vbox.offset_bottom = -16
	stats_vbox.add_theme_constant_override("separation", 8)
	summary_panel.add_child(stats_vbox)

	var stats_title := Label.new()
	stats_title.text = "POWER"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(0.6, 0.66, 0.78, 1.0))
	stats_vbox.add_child(stats_title)

	_hall_stats_label = Label.new()
	_hall_stats_label.add_theme_font_size_override("font_size", 16)
	_hall_stats_label.text = ""
	stats_vbox.add_child(_hall_stats_label)

	# READY CHECK — at-a-glance "what's missing on this hero". Populated in
	# _refresh_hero_hall from InventoryManager / LoadoutState / MetaProgression
	# (same data sources the action-tile subtitles use; this surfaces it on
	# the landing screen so the player doesn't have to hover each tile).
	var ready_title := Label.new()
	ready_title.text = "READY CHECK"
	ready_title.add_theme_font_size_override("font_size", 14)
	ready_title.add_theme_color_override("font_color", Color(0.6, 0.66, 0.78, 1.0))
	stats_vbox.add_child(ready_title)

	_hall_ready_label = Label.new()
	_hall_ready_label.add_theme_font_size_override("font_size", 16)
	_hall_ready_label.text = ""
	stats_vbox.add_child(_hall_ready_label)

	var passives_title := Label.new()
	passives_title.text = "PASSIVES"
	passives_title.add_theme_font_size_override("font_size", 14)
	passives_title.add_theme_color_override("font_color", Color(0.6, 0.66, 0.78, 1.0))
	stats_vbox.add_child(passives_title)

	_hall_passives_label = Label.new()
	_hall_passives_label.add_theme_font_size_override("font_size", 14)
	_hall_passives_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
	_hall_passives_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hall_passives_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hall_passives_label.text = ""
	stats_vbox.add_child(_hall_passives_label)

	# Phase 51 — sidebar is the single source of page nav (Equip / Skills /
	# Talents). The duplicate ActionRow at the bottom of the Hero Hall has
	# been removed; counts surface as nav-button badges instead.
	_refresh_nav_state()


func _make_panel() -> Control:
	# Plain Control wrapper with a ColorRect background + 1-px border overlay.
	# Used for the portrait panel + summary card so they read as bento cards.
	# Sizing comes from size_flags / custom_minimum_size — caller controls.
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.13, 0.17, 0.23, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	var border := _BorderOverlay.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(border)
	return c


# Tiny outline helper — draws a 1-px border so panels read as cards.
class _BorderOverlay extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.30, 0.40, 1.0), false, 1.0)


# Sidebar page-nav button (Phase 51). 120×80 procedural button with a
# HubTabIcon glyph + label, optional small badge in the top-right corner,
# and a 4-px gold left strip when active.
class _NavButton extends Button:
	const _SIZE: Vector2 = Vector2(120, 80)
	const _BG_NORMAL: Color = Color(0.13, 0.17, 0.23, 1.0)
	const _BG_ACTIVE: Color = Color(0.20, 0.27, 0.40, 1.0)
	const _BORDER_NORMAL: Color = Color(0.28, 0.34, 0.46, 1.0)
	const _BORDER_ACTIVE: Color = Color(1.0, 0.85, 0.4, 1.0)
	const _LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
	const _GLYPH_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
	const _STRIP_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
	const _BADGE_BG: Color = Color(0.14, 0.18, 0.25, 1.0)
	const _BADGE_BORDER: Color = Color(1.0, 0.85, 0.4, 1.0)
	var _glyph_kind: String = ""
	var _label_text: String = ""
	var _badge_text: String = ""
	var _active: bool = false
	func _ready() -> void:
		custom_minimum_size = _SIZE
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func setup(_kind: String, glyph: String, label: String) -> void:
		_glyph_kind = glyph
		_label_text = label
		queue_redraw()
	func set_active(active: bool) -> void:
		if _active == active:
			return
		_active = active
		queue_redraw()
	func set_badge(t: String) -> void:
		if _badge_text == t:
			return
		_badge_text = t
		queue_redraw()
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg: Color = _BG_ACTIVE if _active else _BG_NORMAL
		var border: Color = _BORDER_ACTIVE if _active else _BORDER_NORMAL
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, 2.0 if _active else 1.0)
		# Active marker — 4-px gold strip on the left edge.
		if _active:
			draw_rect(Rect2(Vector2.ZERO, Vector2(4.0, size.y)), _STRIP_COLOR, true)
		# Glyph centered upper-half.
		var glyph_center := Vector2(size.x * 0.5, size.y * 0.36)
		HubTabIcon.draw(self, _glyph_kind, glyph_center, 16.0, _GLYPH_COLOR)
		# Label below glyph.
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var lbl_size := font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 13)
		var lbl_pos := Vector2((size.x - lbl_size.x) * 0.5, size.y * 0.82)
		draw_string(font, lbl_pos, _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, _LABEL_COLOR)
		# Badge (top-right corner).
		if _badge_text != "":
			var badge_size := font.get_string_size(_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11)
			var pad := Vector2(6.0, 3.0)
			var badge_rect := Rect2(
				Vector2(size.x - badge_size.x - pad.x * 2.0 - 4.0, 4.0),
				Vector2(badge_size.x + pad.x * 2.0, badge_size.y + pad.y * 2.0)
			)
			draw_rect(badge_rect, _BADGE_BG, true)
			draw_rect(badge_rect, _BADGE_BORDER, false, 1.0)
			var text_pos := badge_rect.position + Vector2(pad.x, badge_size.y + pad.y - 2.0)
			draw_string(font, text_pos, _badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, _LABEL_COLOR)


func _refresh_hero_hall() -> void:
	if _hall_name_label == null:
		return
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null:
		_hall_name_label.text = "No hero"
		_hall_level_label.text = ""
		_hall_xp_label.text = ""
		_hall_stats_label.text = ""
		if _hall_ready_label != null:
			_hall_ready_label.text = ""
		_hall_passives_label.text = ""
		_hall_xp_bar.value = 0.0
		if _hall_portrait != null and _hall_portrait.has_method("setup"):
			_hall_portrait.setup(null)
		return
	var hid: String = String(hero_data.hero_id)
	var lvl: int = MetaProgression.get_hero_level(hid)
	var xp: int = MetaProgression.get_hero_xp(hid)
	var max_lvl: int = int(hero_data.max_level) if "max_level" in hero_data else 10
	var need: int = 0
	if lvl - 1 >= 0 and lvl - 1 < hero_data.xp_per_level.size():
		need = int(hero_data.xp_per_level[lvl - 1])
	var dmg_type: String = "Magic" if int(hero_data.damage_type) == 1 else "Physical"
	_hall_name_label.text = String(hero_data.hero_name)
	_hall_level_label.text = "Lv %d" % lvl
	if lvl >= max_lvl or need <= 0:
		_hall_xp_bar.value = 1.0
		_hall_xp_label.text = "MAX LEVEL"
	else:
		_hall_xp_bar.value = clampf(float(xp) / float(need), 0.0, 1.0)
		_hall_xp_label.text = "XP %d / %d" % [xp, need]
	# Stats lines — effective stats including equipped gear, via HeroStats
	# (Preventive Bug Rule). Don't read hero_data.max_health / .attack_damage
	# etc. directly for display anywhere — those skip the modifier stack.
	var stats: Dictionary = _HeroStats.effective_for(hid)
	_hall_stats_label.text = "%s\nHP   %d\nDMG  %d\nRNG  %d\nSPD  %.2f\nARM  %d%%" % [
		dmg_type,
		int(round(float(stats.get("max_health", 0.0)))),
		int(round(float(stats.get("damage", 0.0)))),
		int(round(float(stats.get("attack_range", 0.0)))),
		float(stats.get("attack_speed", 0.0)),
		int(round(float(stats.get("armor", 0.0)) * 100.0)),
	]
	# READY CHECK lines — equipment slot fill, equipped skill count, talent
	# stars to spend. Slot total honors per-hero equipment_slots override
	# (Dragon's 3 slots vs humanoid 6).
	if _hall_ready_label != null:
		var equipped_items: int = 0
		var total_slots: int = 6
		if has_node("/root/InventoryManager"):
			equipped_items = InventoryManager.get_all_equipped(hid).size()
		if "equipment_slots" in hero_data and hero_data.equipment_slots is Array and hero_data.equipment_slots.size() > 0:
			total_slots = hero_data.equipment_slots.size()
		var equipped_skills: Array[String] = LoadoutState.get_equipped_skills(hid)
		var skill_count: int = 0
		for s in equipped_skills:
			if s != "":
				skill_count += 1
		var stars: int = 0
		if has_node("/root/MetaProgression") and MetaProgression.has_method("get_available_stars"):
			stars = int(MetaProgression.get_available_stars())
		_hall_ready_label.text = "Equipment   %d / %d\nSkills      %d / %d\nTalents     %d ★" % [
			equipped_items, total_slots,
			skill_count, LoadoutState.get_active_slot_cap(hid),
			stars,
		]
	# Passives — list ability names if authored.
	var passive_names: PackedStringArray = []
	if "abilities" in hero_data:
		for ab in hero_data.abilities:
			if ab == null:
				continue
			# Best-effort name extraction. AbilityData may have ability_name or
			# just resource_name; show whatever fits.
			var n: String = ""
			if "ability_name" in ab and String(ab.ability_name) != "":
				n = String(ab.ability_name)
			elif ab.resource_name != "":
				n = ab.resource_name
			else:
				n = ab.get_class()
			if n != "":
				passive_names.append("• " + n)
	if passive_names.is_empty():
		_hall_passives_label.text = "(none)"
	else:
		_hall_passives_label.text = "\n".join(passive_names)
	if _hall_portrait != null and _hall_portrait.has_method("setup"):
		_hall_portrait.setup(hero_data)


func _refresh_meta_gold() -> void:
	if meta_gold_label == null:
		return
	meta_gold_label.text = "💰 %d" % MetaProgression.meta_gold


# --- Sub-view routing -----------------------------------------------------

func _refresh_nav_state() -> void:
	# Sidebar nav-button badges + active-state are the single nav surface
	# now (the bottom action-tile row is gone).
	_refresh_nav_badges()


func _open_sub_view(kind: String) -> void:
	if _current_sub == kind:
		return
	# Tear down anything currently in SubView.
	for child in sub_view.get_children():
		child.queue_free()
	_skills_equipped_slots.clear()
	_skills_available_grid = null
	_skills_locked_grid = null
	_skills_header_label = null
	_skills_inspector_panel = null
	_selected_skill_id = ""
	_disconnect_skills_signals()

	_current_sub = kind
	hero_hall_view.visible = false
	sub_view.visible = true
	# Phase 51 — sidebar is compact (140 px), stays visible on every page.
	# No roster_rail.visible toggle anymore.
	_set_active_nav(kind)
	# Phase 55e — back button is now a fixed "✕ close to WorldMap" affordance,
	# no longer context-sensitive. Sub-view navigation uses the sidebar
	# Overview button to return to the Hero Hall root.
	title_label.text = _title_for_sub(kind)
	# Build the sub-view body.
	match kind:
		"skills":
			_build_skills_subview()
		"equipment":
			_embed_screen("res://ui/EquipmentScreen.tscn")
		"talents":
			# Phase 1 — sidebar tab still labeled "Talents" for muscle-memory;
			# embeds the skill-tree screen. Save-version bump v4→v5 migrated
			# legacy talent purchases into PASSIVE_RANK nodes on the tree.
			_embed_screen("res://ui/HeroSkillTreeScreen.tscn")
		_:
			pass


func _close_sub_view() -> void:
	for child in sub_view.get_children():
		child.queue_free()
	_skills_equipped_slots.clear()
	_skills_available_grid = null
	_skills_locked_grid = null
	_skills_header_label = null
	_skills_inspector_panel = null
	_selected_skill_id = ""
	_disconnect_skills_signals()
	_current_sub = ""
	sub_view.visible = false
	hero_hall_view.visible = true
	title_label.text = "HERO HALL"
	_set_active_nav("")
	# Sub-views can mutate equipment / skills / talents; refresh the Hero Hall
	# READY CHECK + action tiles so values are current when the player returns.
	_refresh_hero_hall()
	_refresh_nav_state()


# Phase 55e — back button always exits the hub. Previously this was
# context-sensitive (close sub-view → return to Hero Hall, then a second
# press to leave to WorldMap), which duplicated the sidebar's Overview
# button. The new "✕" is a fixed close affordance; sub-view-to-root
# navigation goes through Overview.
func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _title_for_sub(kind: String) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	var name_str: String = String(hero_data.hero_name) if hero_data != null else ""
	var base: String = ""
	match kind:
		"equipment":
			base = "EQUIPMENT"
		"skills":
			base = "SKILLS"
		"talents":
			base = "TALENTS"
		_:
			return "HERO HALL"
	if name_str == "":
		return base
	return "%s — %s" % [base, name_str]


func _embed_screen(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		# Don't leave the hub in a half-open state — reset _current_sub and
		# bring the Hero Hall back so the player isn't trapped in an empty
		# sub-view. (Without this reset, the next tap on the same tile would
		# hit the `_current_sub == kind` early-exit in _open_sub_view and
		# silently no-op.)
		push_warning("[HeroesHub] failed to load %s" % scene_path)
		_current_sub = ""
		sub_view.visible = false
		hero_hall_view.visible = true
		title_label.text = "HERO HALL"
		_set_active_nav("")
		return
	var screen: Control = packed.instantiate()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_view.add_child(screen)
	# Hide the embedded screen's own TopBar + Background — we provide both.
	var top: Control = screen.get_node_or_null("TopBar")
	if top != null:
		top.visible = false
	var bg: Control = screen.get_node_or_null("Background")
	if bg != null:
		bg.visible = false
	# Embed Body: pull up + drop horizontal margins. The hub's SafeAreaMargin
	# + ContentMargin already handles outer padding, so the embedded screen's
	# own 16px side margins are redundant and steal width that's expensive
	# (the inventory grid + paperdoll row needs every pixel when the roster
	# rail is also visible).
	var body: Control = screen.get_node_or_null("Body")
	if body != null:
		body.offset_left = 0.0
		body.offset_top = 8.0
		body.offset_right = 0.0
	# Hide redundant section headers that duplicate context the hub already
	# provides: the hub's TitleLabel says "EQUIPMENT — <Hero>" so internal
	# "Equipped" / "Stats" / "Details" labels are visual clutter and obscure
	# the back button. The values themselves (paperdoll, stat rows, details
	# panel content) stay visible — only the section title labels are hidden.
	for redundant_path in [
		"TopBar/HeroLabel",
		"Body/RightPanel/InventoryCard/VBox/HeaderRow/MetaGoldLabel",
	]:
		var node: Control = screen.get_node_or_null(redundant_path)
		if node != null:
			node.visible = false
	# Talent screen specific offsets.
	var stars: Control = screen.get_node_or_null("StarsLabel")
	if stars != null:
		stars.offset_top = 8.0
		stars.offset_bottom = 36.0
	var scroll: Control = screen.get_node_or_null("ScrollContainer")
	if scroll != null:
		scroll.offset_top = 48.0


# --- Skills sub-view (drag-and-drop) --------------------------------------

const _SKILL_TILE_SIZE: Vector2 = Vector2(180, 104)
const _SKILL_SLOT_SIZE: Vector2 = Vector2(180, 104)


func _build_skills_subview() -> void:
	# Phase 3R-followup — picker redesign:
	#   • equipped slots row (top, centered) — existing _SkillSlot
	#   • hint label
	#   • HBox body:
	#       LEFT: ScrollContainer wrapping AVAILABLE + LOCKED HFlowContainers
	#       RIGHT: _skills_inspector_panel (fixed 540 wide) showing full effective specs
	# Drag-and-drop continues to work through every tile / slot. Tile tap (no
	# drag) now also selects the tile for the inspector via _on_tile_selected.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 12)
	sub_view.add_child(vbox)

	_skills_header_label = Label.new()
	_skills_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skills_header_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_skills_header_label)

	var hint := Label.new()
	hint.text = "Tap a skill to inspect. Drag onto a slot or use the equip button."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1.0))
	vbox.add_child(hint)

	_add_section_label(vbox, "EQUIPPED")
	var equipped_row := HBoxContainer.new()
	equipped_row.alignment = BoxContainer.ALIGNMENT_CENTER
	equipped_row.add_theme_constant_override("separation", 16)
	vbox.add_child(equipped_row)
	# Phase 3B — render only the slots the current hero level has unlocked.
	# get_active_slot_cap returns 2 (L1-L7) or 3 (L8+).
	for slot_idx in LoadoutState.get_active_slot_cap(LoadoutState.selected_hero_id):
		var slot := _SkillSlot.new()
		slot.setup(slot_idx, self)
		equipped_row.add_child(slot)
		_skills_equipped_slots.append(slot)

	# Body: tile grid LEFT, inspector RIGHT.
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	vbox.add_child(body)

	# LEFT: scrollable VBox with AVAILABLE + LOCKED grids.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_scroll)
	var grid_vbox := VBoxContainer.new()
	grid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_vbox.add_theme_constant_override("separation", 12)
	grid_scroll.add_child(grid_vbox)
	_add_section_label(grid_vbox, "AVAILABLE")
	_skills_available_grid = HFlowContainer.new()
	_skills_available_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_available_grid.add_theme_constant_override("h_separation", 12)
	_skills_available_grid.add_theme_constant_override("v_separation", 12)
	grid_vbox.add_child(_skills_available_grid)
	_add_section_label(grid_vbox, "LOCKED")
	_skills_locked_grid = HFlowContainer.new()
	_skills_locked_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_locked_grid.add_theme_constant_override("h_separation", 12)
	_skills_locked_grid.add_theme_constant_override("v_separation", 12)
	grid_vbox.add_child(_skills_locked_grid)

	# RIGHT: inspector panel — fixed 540 wide. Filled lazily by _refresh_inspector
	# based on _selected_skill_id; until then renders a placeholder hint.
	_skills_inspector_panel = VBoxContainer.new()
	_skills_inspector_panel.custom_minimum_size = Vector2(540, 0)
	_skills_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_inspector_panel.add_theme_constant_override("separation", 6)
	body.add_child(_skills_inspector_panel)

	_connect_skills_signals()
	_refresh_skills_subview()


# Connect / disconnect EventBus refresh hooks. Connection state is tracked
# so rebuilding the sub-view doesn't stack identical connections (would
# fire _refresh_skills_subview multiple times per signal).
func _connect_skills_signals() -> void:
	if _skills_signals_connected:
		return
	_skills_signals_connected = true
	# Rank purchase / mod choice / equip swap → re-render tiles + inspector
	# so the "current rank" dots, mod chip, effective numbers stay live.
	EventBus.hero_node_purchased.connect(_on_skills_state_changed)
	EventBus.hero_skill_mod_chosen.connect(_on_skills_state_changed)
	EventBus.hero_skill_equipped.connect(_on_skills_state_changed)
	EventBus.hero_leveled_up.connect(_on_skills_state_changed)


func _disconnect_skills_signals() -> void:
	if not _skills_signals_connected:
		return
	_skills_signals_connected = false
	if EventBus.hero_node_purchased.is_connected(_on_skills_state_changed):
		EventBus.hero_node_purchased.disconnect(_on_skills_state_changed)
	if EventBus.hero_skill_mod_chosen.is_connected(_on_skills_state_changed):
		EventBus.hero_skill_mod_chosen.disconnect(_on_skills_state_changed)
	if EventBus.hero_skill_equipped.is_connected(_on_skills_state_changed):
		EventBus.hero_skill_equipped.disconnect(_on_skills_state_changed)
	if EventBus.hero_leveled_up.is_connected(_on_skills_state_changed):
		EventBus.hero_leveled_up.disconnect(_on_skills_state_changed)


# All four EventBus payloads collapse to the same UI refresh — varargs swallow
# whichever shape Godot delivers.
func _on_skills_state_changed(_a = null, _b = null, _c = null) -> void:
	if _skills_header_label == null:
		return
	_refresh_skills_subview()


func _refresh_skills_subview() -> void:
	if _skills_header_label == null:
		return
	var hid: String = LoadoutState.selected_hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hid)
	if hero_data == null:
		_skills_header_label.text = "No hero"
		return
	var lvl: int = MetaProgression.get_hero_level(hid)
	var xp: int = MetaProgression.get_hero_xp(hid)
	var need: int = 0
	if lvl - 1 >= 0 and lvl - 1 < hero_data.xp_per_level.size():
		need = int(hero_data.xp_per_level[lvl - 1])
	var max_lvl: int = int(hero_data.max_level)
	var xp_str: String = "MAX" if lvl >= max_lvl else "XP %d/%d" % [xp, need]
	_skills_header_label.text = "%s   Lv %d   %s" % [hero_data.hero_name, lvl, xp_str]

	# Equipped slots — fill from LoadoutState.
	var equipped: Array[String] = LoadoutState.get_equipped_skills(hid)
	for i in _skills_equipped_slots.size():
		var slot = _skills_equipped_slots[i]
		var sid: String = equipped[i] if i < equipped.size() else ""
		slot.set_skill(sid, hero_data)

	# Available — unlocked skills not currently equipped (still draggable to swap).
	for child in _skills_available_grid.get_children():
		child.queue_free()
	var unlocked: Array[String] = LoadoutState.get_unlocked_skill_ids(hid)
	for sid in unlocked:
		var tile := _SkillTile.new()
		var srank: int = MetaProgression.get_purchased_skill_rank(hid, sid)
		tile.setup(sid, _skill_name(hero_data, sid), false, srank, self)
		_skills_available_grid.add_child(tile)

	# Locked — skills not yet unlocked by level.
	for child in _skills_locked_grid.get_children():
		child.queue_free()
	for skill in hero_data.skills:
		if skill == null:
			continue
		var lr: int = int(skill.level_required) if "level_required" in skill else 1
		if lr <= lvl:
			continue
		var tile := _SkillTile.new()
		var lrank: int = MetaProgression.get_purchased_skill_rank(hid, String(skill.skill_id))
		tile.setup(String(skill.skill_id), "??? Lv %d" % lr, true, lrank, self)
		_skills_locked_grid.add_child(tile)

	# Phase 3R-followup — refresh selection outline + inspector contents.
	# Drop a stale _selected_skill_id that no longer belongs to this hero
	# (e.g. hero switched in sidebar while a tile was selected).
	if _selected_skill_id != "" and not _hero_owns_skill(hero_data, _selected_skill_id):
		_selected_skill_id = ""
	_refresh_skill_tile_selection()
	_refresh_inspector()


# True if the hero's authored skills array contains the given skill_id.
func _hero_owns_skill(hero_data: Resource, skill_id: String) -> bool:
	if hero_data == null or not ("skills" in hero_data):
		return false
	for skill in hero_data.skills:
		if skill != null and String(skill.skill_id) == skill_id:
			return true
	return false


# Called by _SkillTile on a tap (no drag). Selects the tile so the inspector
# shows its full effective specs; tapping the same tile a second time
# deselects (and the inspector returns to its placeholder).
func _on_skill_tile_selected(skill_id: String) -> void:
	if skill_id == _selected_skill_id:
		_selected_skill_id = ""
	else:
		_selected_skill_id = skill_id
	_refresh_skill_tile_selection()
	_refresh_inspector()


# Walk all tiles in both grids and update their selected outline so a fresh
# selection visually clears the prior highlight.
func _refresh_skill_tile_selection() -> void:
	for grid in [_skills_available_grid, _skills_locked_grid]:
		if grid == null:
			continue
		for child in grid.get_children():
			if child is _SkillTile:
				child.set_selected(child._skill_id == _selected_skill_id and _selected_skill_id != "")


# Populate the inspector panel based on _selected_skill_id. Re-runs on every
# refresh trigger so live changes (rank up, mod swap, equip) reflect.
func _refresh_inspector() -> void:
	if _skills_inspector_panel == null:
		return
	for child in _skills_inspector_panel.get_children():
		child.queue_free()
	var hid: String = LoadoutState.selected_hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hid)
	if hero_data == null:
		return
	if _selected_skill_id == "":
		var placeholder := Label.new()
		placeholder.text = "Tap a skill on the left to inspect."
		placeholder.add_theme_font_size_override("font_size", 14)
		placeholder.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_skills_inspector_panel.add_child(placeholder)
		return
	var skill: Resource = null
	for s in hero_data.skills:
		if s != null and String(s.skill_id) == _selected_skill_id:
			skill = s
			break
	if skill == null:
		return
	_inspector_show(skill, hid, hero_data)


# Build the inspector content for a single skill. Layout (top→bottom):
#   • Title row: skill name + rank dots
#   • Badges row: damage_type + target_type + level_required gate (if not met)
#   • Stat rows: Damage / Cooldown / Range / AoE (when present)
#   • Rank progression block: what each purchased / next rank does
#   • Mod chip + brief description (when chosen)
#   • Description prose
#   • Equip buttons (one per slot, disabled if locked)
func _inspector_show(skill: Resource, hid: String, _hero_data: Resource) -> void:
	var skill_id: String = String(skill.skill_id)
	var hero_level: int = MetaProgression.get_hero_level(hid)
	var rank: int = MetaProgression.get_purchased_skill_rank(hid, skill_id)
	var lvl_req: int = int(skill.level_required) if "level_required" in skill else 1
	var locked: bool = hero_level < lvl_req
	# Title row: name (bold) + rank dots
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	_skills_inspector_panel.add_child(title)
	var name_lbl := Label.new()
	name_lbl.text = String(skill.skill_name)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 0.85))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_lbl)
	var rank_lbl := Label.new()
	rank_lbl.text = _rank_dots_text(rank)
	rank_lbl.add_theme_font_size_override("font_size", 18)
	rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.add_child(rank_lbl)
	# Badges row: damage_type · target_type · (Lv gate if locked)
	var badge_strs: PackedStringArray = []
	if "damage_type" in skill:
		badge_strs.append("Magic" if int(skill.damage_type) == 1 else "Physical")
	if "target_type" in skill:
		match int(skill.target_type):
			0: badge_strs.append("SINGLE")
			1: badge_strs.append("AREA")
			2: badge_strs.append("SELF")
	if locked:
		badge_strs.append("Lv %d to unlock" % lvl_req)
	var badges := Label.new()
	badges.text = "  ·  ".join(badge_strs)
	badges.add_theme_font_size_override("font_size", 13)
	badges.add_theme_color_override("font_color", Color(0.65, 0.75, 0.90) if not locked else Color(0.85, 0.55, 0.55))
	_skills_inspector_panel.add_child(badges)
	# Effective stats — computed via the same ctx merge BaseHero.cast_skill uses.
	var ctx: Dictionary = skill.get_effective_scaling(rank)
	var mod_id: String = LoadoutState.get_chosen_mod(hid, skill_id)
	var mod: Resource = LoadoutState.find_skill_mod(hid, mod_id) if mod_id != "" else null
	if mod != null and "scaling" in mod:
		for k in mod.scaling:
			if String(k).ends_with("_mult"):
				ctx[k] = float(ctx.get(k, 1.0)) * float(mod.scaling[k])
			else:
				ctx[k] = mod.scaling[k]
	# Hero skill_power + CDR — read from the simulated full-stats dict so
	# items + passives + capstones all fold in (matches BaseHero._build_skill_ctx
	# behavior end-to-end).
	var full_stats: Dictionary = _compute_effective_stats_for(hid)
	var sp: float = float(full_stats.get("skill_power", 1.0))
	if not is_equal_approx(sp, 1.0):
		ctx["damage_mult"] = float(ctx.get("damage_mult", 1.0)) * sp
	var cdr: float = clampf(float(full_stats.get("cooldown_reduction", 0.0)), 0.0, 0.5)
	# Spacer.
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 4)
	_skills_inspector_panel.add_child(spacer1)
	# Stat rows — keys/labels conditional on the skill class having that field.
	var base_dmg: float = float(skill.damage) if "damage" in skill else 0.0
	if base_dmg > 0.0:
		var eff_dmg: float = base_dmg * float(ctx.get("damage_mult", 1.0))
		_inspector_add_stat_row("Damage", "%.1f" % eff_dmg, "×%.2f" % float(ctx.get("damage_mult", 1.0)))
	var base_cd: float = float(skill.cooldown) if "cooldown" in skill else 0.0
	if base_cd > 0.0:
		var cd_mult: float = float(ctx.get("cooldown_mult", 1.0))
		var eff_cd: float = base_cd * cd_mult * (1.0 - cdr)
		var cd_note: String = "×%.2f" % cd_mult
		if cdr > 0.0:
			cd_note += "  -%d%% CDR" % int(round(cdr * 100.0))
		_inspector_add_stat_row("Cooldown", "%.1fs" % eff_cd, cd_note)
	var base_rng: float = float(skill.skill_range) if "skill_range" in skill else 0.0
	if base_rng > 0.0:
		var rng_mult: float = float(ctx.get("range_mult", 1.0))
		_inspector_add_stat_row("Range", "%d" % int(round(base_rng * rng_mult)), "×%.2f" % rng_mult)
	if "aoe_radius" in skill and float(skill.aoe_radius) > 0.0:
		var aoe_mult: float = float(ctx.get("aoe_radius_mult", 1.0))
		var eff_aoe: float = float(skill.aoe_radius) * aoe_mult
		_inspector_add_stat_row("AoE", "%d" % int(round(eff_aoe)), "×%.2f" % aoe_mult)
	# Mod chip — visible only when a mod is owned + chosen for this skill.
	if mod != null:
		var spacer2 := Control.new()
		spacer2.custom_minimum_size = Vector2(0, 4)
		_skills_inspector_panel.add_child(spacer2)
		var mod_row := HBoxContainer.new()
		mod_row.add_theme_constant_override("separation", 8)
		_skills_inspector_panel.add_child(mod_row)
		var mod_lbl := Label.new()
		mod_lbl.text = "Mod"
		mod_lbl.add_theme_font_size_override("font_size", 13)
		mod_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
		mod_lbl.custom_minimum_size = Vector2(80, 0)
		mod_row.add_child(mod_lbl)
		var mod_name := Label.new()
		var mname: String = String(mod.mod_name) if "mod_name" in mod else String(mod.mod_id)
		mod_name.text = "◉ %s" % mname
		mod_name.add_theme_font_size_override("font_size", 14)
		mod_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		mod_row.add_child(mod_name)
		if "description" in mod and String(mod.description) != "":
			var mod_desc := Label.new()
			mod_desc.text = String(mod.description)
			mod_desc.add_theme_font_size_override("font_size", 12)
			mod_desc.add_theme_color_override("font_color", Color(0.78, 0.82, 0.90))
			mod_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_skills_inspector_panel.add_child(mod_desc)
	# Description prose (word-wrapped in the 540-px column).
	if "description" in skill and String(skill.description) != "":
		var spacer3 := Control.new()
		spacer3.custom_minimum_size = Vector2(0, 6)
		_skills_inspector_panel.add_child(spacer3)
		var desc := Label.new()
		desc.text = String(skill.description)
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_skills_inspector_panel.add_child(desc)
	# Equip buttons — one per active slot. Disabled if locked or already in
	# that slot. Click commits via the same path drag-and-drop uses, then
	# pushes the hub state save so quitting preserves the choice.
	var spacer4 := Control.new()
	spacer4.custom_minimum_size = Vector2(0, 10)
	_skills_inspector_panel.add_child(spacer4)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_skills_inspector_panel.add_child(btn_row)
	var equipped: Array[String] = LoadoutState.get_equipped_skills(hid)
	var cap: int = LoadoutState.get_active_slot_cap(hid)
	for slot_idx in cap:
		var btn := Button.new()
		var already_here: bool = (slot_idx < equipped.size() and equipped[slot_idx] == skill_id)
		if already_here:
			btn.text = "✓ slot %d" % (slot_idx + 1)
			btn.disabled = true
		elif locked:
			btn.text = "slot %d  (Lv %d)" % [slot_idx + 1, lvl_req]
			btn.disabled = true
		else:
			btn.text = "→ slot %d" % (slot_idx + 1)
		btn.pressed.connect(_on_inspector_equip.bind(slot_idx, skill_id))
		btn_row.add_child(btn)


func _inspector_add_stat_row(label: String, value: String, note: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_skills_inspector_panel.add_child(row)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
	name_lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	val_lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(val_lbl)
	var note_lbl := Label.new()
	note_lbl.text = note
	note_lbl.add_theme_font_size_override("font_size", 12)
	note_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	row.add_child(note_lbl)


func _on_inspector_equip(slot_idx: int, skill_id: String) -> void:
	# Defense in depth — re-validate locked state since the button could have
	# been re-enabled by a level-up between bind and click.
	var hid: String = LoadoutState.selected_hero_id
	if hid == "" or skill_id == "":
		return
	if not (skill_id in LoadoutState.get_unlocked_skill_ids(hid)):
		return
	LoadoutState.set_equipped_skill(hid, slot_idx, skill_id)
	SaveManager.save_game()
	# EventBus.hero_skill_equipped fires from set_equipped_skill →
	# _on_skills_state_changed → _refresh_skills_subview; no manual call needed.


# Rank-dot string for the title row. Empty rank renders three dim dots so
# the row stays the same width across heroes.
func _rank_dots_text(rank: int) -> String:
	var out: String = ""
	for i in 3:
		out += "★" if i < rank else "☆"
	return out


# Simulated effective stats including items + equipped passives + capstones.
# Mirrors BaseHero.compute_stats_for plus the tree-walk HeroTuning does in
# its _compute_simulated_stats. Read-only, no instance allocation.
func _compute_effective_stats_for(hid: String) -> Dictionary:
	if hid == "":
		return {}
	var hero_data: Resource = ContentRegistry.find_hero(hid)
	if hero_data == null:
		return {}
	var level: int = MetaProgression.get_hero_level(hid)
	var base: Dictionary = BaseHero.compute_base_stats(hero_data, level)
	var mods: Array = []
	if has_node("/root/InventoryManager"):
		for inst in InventoryManager.get_all_equipped(hid):
			if inst == null:
				continue
			for ab in inst.build_runtime_abilities(ContentRegistry):
				if ab != null:
					mods.append(ab)
	var tree: Resource = ContentRegistry.find_skill_tree(hid)
	if tree != null:
		# Equipped passives (mirrors BaseHero._apply_equipped_passives walk).
		var equipped_passives: Array[String] = LoadoutState.get_equipped_passives(hid)
		for passive_id in equipped_passives:
			if passive_id == "":
				continue
			var rank: int = MetaProgression.get_purchased_passive_rank(hid, passive_id)
			if rank <= 0:
				continue
			for node in tree.nodes_for_target(passive_id):
				if node == null or not ("kind" in node):
					continue
				if int(node.kind) != _HeroSkillNodeDataScript.Kind.PASSIVE_RANK:
					continue
				if int(node.rank) > rank:
					continue
				if node.ability != null:
					mods.append(node.ability)
		# Capstones — purchased = active.
		for node in tree.nodes:
			if node == null or not ("kind" in node):
				continue
			if int(node.kind) != _HeroSkillNodeDataScript.Kind.CAPSTONE:
				continue
			if MetaProgression.get_purchased_rank(hid, String(node.node_id)) < int(node.rank):
				continue
			if node.ability != null:
				mods.append(node.ability)
	return BaseHero.apply_modifiers(base, mods)


func _skill_name(hero_data: Resource, skill_id: String) -> String:
	if skill_id == "":
		return ""
	for skill in hero_data.skills:
		if skill != null and skill.skill_id == skill_id:
			return String(skill.skill_name)
	return skill_id


# Called by _SkillSlot._drop_data — applies the equip/swap/move and persists.
# `source` and `from_slot` are informational only; LoadoutState.set_equipped_skill
# already swap-on-duplicates so a drag from another equipped slot works the
# same as a drag from the available list.
func _apply_skill_drop(target_slot_idx: int, _source: String, sid: String, _from_slot: int) -> void:
	var hid: String = LoadoutState.selected_hero_id
	if hid == "" or sid == "":
		return
	if not (sid in LoadoutState.get_unlocked_skill_ids(hid)):
		return
	LoadoutState.set_equipped_skill(hid, target_slot_idx, sid)
	SaveManager.save_game()


func _clear_skill_slot(slot_idx: int) -> void:
	var hid: String = LoadoutState.selected_hero_id
	if hid == "":
		return
	LoadoutState.set_equipped_skill(hid, slot_idx, "")
	SaveManager.save_game()


func _add_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1.0))
	parent.add_child(lbl)


# --- Inner classes --------------------------------------------------------

class HallPortrait extends Control:
	# Big procedural portrait — same draw as HeroPortrait but bigger.
	const _DRAW_SCALE: float = 5.5
	# Vertical chest pivot. UnitVisualDrawer draws chest at the given offset;
	# legs extend ~_DRAW_SCALE*16 below and head/helmet ~_DRAW_SCALE*16 above.
	# 0.62 centers the figure with breathing room above the head and below
	# the floor disc on a tall panel; the older 0.85 buried the hero at the
	# bottom edge with a black void above.
	const _ANCHOR_FRACTION: float = 0.62
	const _BG_COLOR: Color = Color(0.07, 0.09, 0.12, 1.0)
	const _BORDER_COLOR: Color = Color(0.25, 0.30, 0.40, 1.0)
	const _FLOOR_COLOR: Color = Color(0.13, 0.16, 0.22, 1.0)
	var _visual: Resource = null
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func setup(hero_data: Resource) -> void:
		_visual = null
		if hero_data != null and "visual" in hero_data:
			_visual = hero_data.visual
		queue_redraw()
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, _BG_COLOR, true)
		draw_rect(rect, _BORDER_COLOR, false, 2.0)
		if _visual == null:
			return
		var center := Vector2(size.x * 0.5, size.y * _ANCHOR_FRACTION)
		var floor_y: float = center.y + _DRAW_SCALE * 16.0
		var floor_rx: float = size.x * 0.32
		var pts := PackedVector2Array()
		for i in 25:
			var a: float = TAU * float(i) / 24.0
			pts.append(Vector2(center.x + cos(a) * floor_rx, floor_y + sin(a) * 12.0))
		draw_colored_polygon(pts, _FLOOR_COLOR)
		UnitVisualDrawer.draw_unit(self, _visual, center, Vector2(_DRAW_SCALE, _DRAW_SCALE))


class _SkillTile extends Control:
	# Drag source — render as a clickable tile, return drag data when picked up.
	# Phase 3R-followup — also: rank-dot row below the name, a gold "selected"
	# outline driven by the hub's _selected_skill_id, and a tap-to-select
	# release-event callback into the hub so the inspector picks up the choice.
	const _SIZE: Vector2 = Vector2(180, 104)
	const _BG_NORMAL: Color = Color(0.18, 0.24, 0.34, 1.0)
	const _BG_LOCKED: Color = Color(0.10, 0.13, 0.18, 1.0)
	const _BORDER: Color = Color(0.45, 0.50, 0.62, 1.0)
	const _BORDER_LOCKED: Color = Color(0.30, 0.34, 0.42, 1.0)
	const _BORDER_SELECTED: Color = Color(1.0, 0.85, 0.4, 1.0)
	var _skill_id: String = ""
	var _name: String = ""
	var _locked: bool = false
	var _rank: int = 0
	var _selected: bool = false
	var _hub: Node = null
	func _init() -> void:
		custom_minimum_size = _SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	func setup(skill_id: String, display_name: String, locked: bool, rank: int = 0, hub: Node = null) -> void:
		_skill_id = skill_id
		_name = display_name
		_locked = locked
		_rank = rank
		_hub = hub
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if locked else Control.CURSOR_POINTING_HAND
		queue_redraw()
	func set_selected(v: bool) -> void:
		if _selected == v:
			return
		_selected = v
		queue_redraw()
	func _get_drag_data(_at: Vector2) -> Variant:
		if _locked or _skill_id == "":
			return null
		var preview := _SkillTile.new()
		preview.setup(_skill_id, _name, false, _rank, null)
		preview.size = _SIZE
		preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
		set_drag_preview(preview)
		return {"skill_id": _skill_id, "source": "available", "from_slot": -1}
	func _gui_input(event: InputEvent) -> void:
		# Tap (no drag) on a tile selects it for the inspector. Mirrors
		# _SkillSlot's release-event idiom — Godot's drag system consumes
		# release when drag fires, so a release reaching here means a clean
		# tap. Locked tiles still select (inspector shows their specs +
		# disabled equip buttons) so the player can plan ahead.
		if event is InputEventScreenTouch:
			if event.pressed:
				return
			if _skill_id != "" and _hub != null:
				_hub._on_skill_tile_selected(_skill_id)
				accept_event()
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg: Color = _BG_LOCKED if _locked else _BG_NORMAL
		var border: Color = _BORDER_SELECTED if _selected else (_BORDER_LOCKED if _locked else _BORDER)
		var bw: float = 2.5 if _selected else 1.5
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, bw)
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var col: Color = Color(0.55, 0.6, 0.7, 1.0) if _locked else Color.WHITE
		# Name (centered horizontally, slightly above center vertically so
		# the rank dots fit below).
		var label_size := font.get_string_size(_name, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16)
		var name_pos := Vector2((size.x - label_size.x) * 0.5, size.y * 0.5 - 2.0)
		draw_string(font, name_pos, _name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, col)
		# Rank dots — skip on locked tiles (the lock label already steals
		# the row). 0 dots renders three dim ☆ so the row stays the same
		# height across un-purchased / partially-purchased / fully-purchased.
		if not _locked:
			var dots: String = ""
			for i in 3:
				dots += "★" if i < _rank else "☆"
			var dot_size := font.get_string_size(dots, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 14)
			var dot_pos := Vector2((size.x - dot_size.x) * 0.5, size.y * 0.5 + 22.0)
			draw_string(font, dot_pos, dots, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.85, 0.4))


class _SkillSlot extends Control:
	# Drop target. Tap (no drag) on a filled slot clears it.
	# Phase 3R-followup — also renders the effective cooldown beneath the
	# skill name when filled. Mirrors the inspector's cooldown math so the
	# equipped row says exactly what the player will see in-level.
	const _SIZE: Vector2 = Vector2(180, 104)
	const _BG_EMPTY: Color = Color(0.10, 0.13, 0.18, 1.0)
	const _BG_FILLED: Color = Color(0.20, 0.30, 0.46, 1.0)
	const _BORDER_EMPTY: Color = Color(0.30, 0.34, 0.42, 1.0)
	const _BORDER_FILLED: Color = Color(1.0, 0.85, 0.4, 1.0)
	var _slot_idx: int = -1
	var _skill_id: String = ""
	var _name: String = ""
	var _rank: int = 0
	var _effective_cd: float = 0.0
	var _hub: Node = null
	func _init() -> void:
		custom_minimum_size = _SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func setup(slot_idx: int, hub: Node) -> void:
		_slot_idx = slot_idx
		_hub = hub
	func set_skill(skill_id: String, hero_data: Resource) -> void:
		_skill_id = skill_id
		_name = ""
		_rank = 0
		_effective_cd = 0.0
		if skill_id != "" and hero_data != null:
			var hid: String = String(hero_data.hero_id)
			_rank = MetaProgression.get_purchased_skill_rank(hid, skill_id)
			for skill in hero_data.skills:
				if skill != null and skill.skill_id == skill_id:
					_name = String(skill.skill_name)
					# Effective cooldown — same chain BaseHero._build_skill_ctx
					# does so the picker and the in-level radial agree.
					var ctx: Dictionary = skill.get_effective_scaling(_rank)
					var mod_id: String = LoadoutState.get_chosen_mod(hid, skill_id)
					var mod: Resource = LoadoutState.find_skill_mod(hid, mod_id) if mod_id != "" else null
					if mod != null and "scaling" in mod:
						for k in mod.scaling:
							if String(k).ends_with("_mult"):
								ctx[k] = float(ctx.get(k, 1.0)) * float(mod.scaling[k])
					var base_cd: float = float(skill.cooldown) if "cooldown" in skill else 0.0
					var cdr: float = 0.0
					if _hub != null and _hub.has_method("_compute_effective_stats_for"):
						var stats: Dictionary = _hub._compute_effective_stats_for(hid)
						cdr = clampf(float(stats.get("cooldown_reduction", 0.0)), 0.0, 0.5)
					_effective_cd = base_cd * float(ctx.get("cooldown_mult", 1.0)) * (1.0 - cdr)
					break
		queue_redraw()
	func _get_drag_data(_at: Vector2) -> Variant:
		# Pick up an equipped tile to drag it elsewhere (move/swap/clear via release outside).
		if _skill_id == "":
			return null
		var preview := _SkillTile.new()
		preview.setup(_skill_id, _name, false)
		preview.size = _SIZE
		preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
		set_drag_preview(preview)
		return {"skill_id": _skill_id, "source": "equipped", "from_slot": _slot_idx}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("skill_id")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _hub == null or not (data is Dictionary):
			return
		var sid: String = String(data.get("skill_id", ""))
		var src: String = String(data.get("source", "available"))
		var from_slot: int = int(data.get("from_slot", -1))
		_hub._apply_skill_drop(_slot_idx, src, sid, from_slot)
	func _gui_input(event: InputEvent) -> void:
		# Tap (no drag) on a filled slot clears it. We listen for RELEASE
		# (pressed=false), not press: when Godot's drag-and-drop fires
		# (_get_drag_data → drag in flight → _drop_data or cancel), the
		# release event is consumed by the drag system and never reaches
		# _gui_input. So if pressed=false reaches us, the user did NOT
		# drag — it's a clean tap, safe to clear. Acting on press would
		# nuke the slot the moment the user touched it, even when they
		# meant to drag the equipped tile elsewhere.
		# Touch-only per project rule (emulate_touch_from_mouse=true means
		# every PC click also fires a screen-touch event; handling both
		# would double-fire and clear the slot twice on PC).
		if event is InputEventScreenTouch:
			if event.pressed:
				return
			if _skill_id != "" and _hub != null:
				_hub._clear_skill_slot(_slot_idx)
				accept_event()
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var filled: bool = _skill_id != ""
		var bg: Color = _BG_FILLED if filled else _BG_EMPTY
		var border: Color = _BORDER_FILLED if filled else _BORDER_EMPTY
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, 2.0 if filled else 1.5)
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var label: String = _name if filled else "+ Empty"
		var col: Color = Color.WHITE if filled else Color(0.55, 0.6, 0.7, 1.0)
		# Name — slightly above center to make room for the cooldown / dots row.
		var name_y: float = size.y * 0.5 - 4.0 if filled else size.y * 0.5 + 6.0
		var lbl_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16)
		var pos := Vector2((size.x - lbl_size.x) * 0.5, name_y)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, col)
		if filled:
			# Sub-row: rank dots on the left, effective cooldown on the right.
			var dots: String = ""
			for i in 3:
				dots += "★" if i < _rank else "☆"
			var sub_y: float = size.y * 0.5 + 20.0
			draw_string(font, Vector2(12, sub_y), dots, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.85, 0.4))
			if _effective_cd > 0.0:
				var cd_str: String = "%.1fs" % _effective_cd
				var cd_size := font.get_string_size(cd_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 13)
				draw_string(font, Vector2(size.x - cd_size.x - 12, sub_y), cd_str,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.78, 0.88, 1.0))
