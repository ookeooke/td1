extends Control

# Hero Hall hub.
#
# Layout:
#   TopBar      : Close button (✕, always exits to WorldMap) + title + meta gold
#   HeroSidebar : compact 140-px column — hero portrait buttons (top, scroll),
#                 divider, three page-nav buttons (bottom): Overview / Equip / Skills.
#                 (Skills tab is unified — absorbed the prior Talents tab.)
#   MainStack:
#     HeroHallView — big procedural portrait + name/level/XP, POWER /
#                    READY CHECK / PASSIVES summary panel
#     SubView      — swapped in when a nav button is tapped. Skills =
#                    HeroSkillsPage (active loadout + passive loadout + tree).
#                    Equipment = EquipmentScreen. Both embedded scenes.
#
# Sidebar stays visible inside sub-views so the player can switch hero
# without backing out. Switching hero in any view emits `hero_selected`,
# which the embedded screens already listen for.

const _HeroSidebarButtonScript := preload("res://ui/HeroSidebarButton.gd")
# Preload so the Kind enum is resolvable regardless of class_name registry
# order. Matches the pattern used in MetaProgression / LoadoutState.
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

# State machine: "" = Hero Hall, otherwise "equipment"|"skills".
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
	# Skills equipped via HeroSkillsPage — refresh the sidebar badge counter.
	# HeroSkillsPage rebuilds itself on the same signal; we don't need to
	# touch the embedded page from here.
	EventBus.hero_skill_equipped.connect(func(_h, _s, _id) -> void:
		_refresh_nav_state()
	)
	# Skill-points changed (level-up grant, tree purchase) — the Skills
	# nav badge surfaces unspent ★ as a call-to-action and must refresh
	# when the count moves. Without this, buying a node leaves the badge
	# stale at the pre-buy value until something else nudges _refresh_nav_state.
	EventBus.hero_skill_points_changed.connect(func(_h, _p) -> void:
		_refresh_nav_state()
		_refresh_hero_hall()  # READY CHECK "Points" line reads the same source
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
# Three nav buttons under the divider: Overview / Equip / Skills.
# Pressing a nav button calls _open_sub_view; Overview maps to the
# empty-string sub_view (= back to Hero Hall).

const _NAV_ENTRIES: Array = [
	["",         "overview",  "Overview"],
	["equipment","equipment", "Equip"],
	["skills",   "skills",    "Skills"],
]

# kind ("" / "equipment" / "skills") → _NavButton
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
	# Per-hero skill points — NOT global meta-upgrade stars. The badge is
	# meant to call attention to a tree purchase the *selected* hero can
	# make. Using get_available_stars() (account-wide campaign upgrade stars)
	# would flash "spendable!" on a hero who actually has 0 unspent points.
	var skill_points: int = 0
	if has_node("/root/MetaProgression"):
		skill_points = int(MetaProgression.get_skill_points(LoadoutState.selected_hero_id))
	# Unified Skills tab absorbed the old Talents tab. Surface unspent ★ when
	# there's something to spend (call-to-action); fall back to equipped/cap
	# count when the tree purchases are done.
	var skills_badge: String = "%d★" % skill_points if skill_points > 0 \
		else "%d/%d" % [skill_count, LoadoutState.get_active_slot_cap(LoadoutState.selected_hero_id)]
	_set_nav_badge("skills", skills_badge)
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
	# Embedded sub-views (HeroSkillsPage / EquipmentScreen) listen to
	# hero_selected directly and rebuild themselves.


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
	#   └──────────────────────────────────────┴─────────────────────┘
	#
	# Nav (Equip / Skills) lives in the sidebar — no in-view action row.
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

	# Phase 51 — sidebar is the single source of page nav (Equip / Skills).
	# Counts surface as nav-button badges.
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
	# Phase 3 — damage type follows the equipped weapon (compute_stats_for
	# exposes "damage_type"); fall back to HeroData when unset (byte-identical).
	var dmg_type: String = "Magic" if int(stats.get("damage_type", int(hero_data.damage_type))) == 1 else "Physical"
	_hall_stats_label.text = "%s\nHP   %d\nDMG  %d\nRNG  %d\nSPD  %.2f\nARM  %d%%" % [
		dmg_type,
		int(round(float(stats.get("max_health", 0.0)))),
		int(round(float(stats.get("damage", 0.0)))),
		int(round(float(stats.get("attack_range", 0.0)))),
		float(stats.get("attack_speed", 0.0)),
		int(round(float(stats.get("armor", 0.0)) * 100.0)),
	]
	# Phase 3 — weapon-family affinity teaching line. Empty for heroes with
	# no authored affinities (byte-identical: no extra text appended).
	var aff_line: String = HeroAffinityPreview.overview_line(hid)
	if aff_line != "":
		_hall_stats_label.text += "\n" + aff_line
	# READY CHECK lines — equipment slot fill, equipped skill count, unspent
	# skill points to spend in the tree. Slot total honors per-hero
	# equipment_slots override (Dragon's 3 slots vs humanoid 6).
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
		# Per-hero skill points (unspent ★ on the selected hero's tree), NOT
		# the global account-wide meta-upgrade stars. Earlier this called
		# get_available_stars(), which counts campaign-level upgrade stars
		# and falsely advertised hero progression on a hero with 0 points.
		var skill_points: int = 0
		if has_node("/root/MetaProgression"):
			skill_points = int(MetaProgression.get_skill_points(hid))
		_hall_ready_label.text = "Equipment   %d / %d\nSkills      %d / %d\nPoints      %d ★" % [
			equipped_items, total_slots,
			skill_count, LoadoutState.get_active_slot_cap(hid),
			skill_points,
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
	# Tear down anything currently in SubView. Embedded screens disconnect
	# their own signals via _exit_tree (see Preventive Bug Rule 3).
	for child in sub_view.get_children():
		child.queue_free()

	_current_sub = kind
	hero_hall_view.visible = false
	sub_view.visible = true
	# Phase 51 — sidebar is compact (140 px), stays visible on every page.
	_set_active_nav(kind)
	# Phase 55e — back button is now a fixed "✕ close to WorldMap" affordance,
	# no longer context-sensitive. Sub-view navigation uses the sidebar
	# Overview button to return to the Hero Hall root.
	title_label.text = _title_for_sub(kind)
	# Build the sub-view body.
	match kind:
		"skills":
			# Unified Skills page: active loadout + passive loadout + tree
			# purchases (with tab filter) + side inspector. Replaced both the
			# prior inline drag-grid (active picker) and the embedded skill
			# tree screen ("Talents") with one screen.
			_embed_screen("res://ui/HeroSkillsPage.tscn")
		"equipment":
			_embed_screen("res://ui/EquipmentScreen.tscn")
		_:
			pass


func _close_sub_view() -> void:
	for child in sub_view.get_children():
		child.queue_free()
	_current_sub = ""
	sub_view.visible = false
	hero_hall_view.visible = true
	title_label.text = "HERO HALL"
	_set_active_nav("")
	# Sub-views can mutate equipment / skills; refresh the Hero Hall
	# READY CHECK + nav badges so values are current when the player returns.
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
