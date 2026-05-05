extends Control

# Phase 50 — Hero Hall (replaces the prior 5-tab segment hub).
#
# Layout:
#   TopBar   : Back button (or "← Hall" chip in sub-views) + title + meta gold
#   RosterRail (left, scrollable): one HeroCard per hero in ContentRegistry
#   MainStack:
#     HeroHallView — big procedural portrait + name/level/XP, stats card,
#                    bottom row of 4 ActionTile (Stats / Equipment / Skills / Talents)
#     SubView      — swapped in at tile-tap. Equipment/Talents = embedded scenes;
#                    Stats / Skills = built inline (skills uses drag-and-drop).
#
# Roster rail stays visible inside sub-views so the player can switch hero
# without backing out. Switching hero in any view emits `hero_selected`,
# which the embedded screens already listen for.

const _HeroCardScript := preload("res://ui/HeroCard.gd")
const _ActionTileScript := preload("res://ui/ActionTile.gd")

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var meta_gold_label: Label = %MetaGoldLabel
@onready var roster_rail: ScrollContainer = %RosterRail
@onready var roster_list: VBoxContainer = %RosterList
@onready var hero_hall_view: Control = %HeroHallView
@onready var sub_view: Control = %SubView

# State machine: "" = Hero Hall, otherwise "stats"|"equipment"|"skills"|"talents".
var _current_sub: String = ""

# Cached widgets — cards by hero_id, action tiles by kind.
var _hero_cards: Dictionary = {}
var _action_tiles: Dictionary = {}

# Hero Hall view widgets — built once in _build_hero_hall, refreshed in _refresh_hero_hall.
var _hall_portrait: Control = null
var _hall_name_label: Label = null
var _hall_level_label: Label = null
var _hall_xp_bar: ProgressBar = null
var _hall_xp_label: Label = null
var _hall_stats_label: Label = null
var _hall_passives_label: Label = null

# Skills sub-view state — drag-and-drop participants.
var _skills_equipped_slots: Array = []
var _skills_available_grid: HFlowContainer = null
var _skills_locked_grid: HFlowContainer = null
var _skills_header_label: Label = null

const _PORTRAIT_DRAW_SCALE: float = 5.5
const _PORTRAIT_ANCHOR_FRACTION: float = 0.82
const _PORTRAIT_BG: Color = Color(0.07, 0.09, 0.12, 1.0)
const _PORTRAIT_BORDER: Color = Color(0.25, 0.30, 0.40, 1.0)
const _PORTRAIT_FLOOR: Color = Color(0.13, 0.16, 0.22, 1.0)


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build_roster_rail()
	_build_hero_hall()
	_refresh_meta_gold()
	_refresh_hero_hall()
	# Listeners.
	EventBus.hero_selected.connect(_on_hero_selected)
	EventBus.hero_skill_equipped.connect(func(_h, _s, _id) -> void:
		_refresh_action_tile_subtitles()
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
	EventBus.inventory_changed.connect(_refresh_action_tile_subtitles)


# --- Roster rail ----------------------------------------------------------

func _build_roster_rail() -> void:
	for child in roster_list.get_children():
		child.queue_free()
	_hero_cards.clear()
	if not has_node("/root/ContentRegistry"):
		return
	var heroes: Array = ContentRegistry.heroes
	for hero in heroes:
		if hero == null or not ("hero_id" in hero):
			continue
		var card: HeroCard = _HeroCardScript.new()
		roster_list.add_child(card)
		card.setup(hero)
		card.set_selected(String(hero.hero_id) == LoadoutState.selected_hero_id)
		card.pressed.connect(_on_card_pressed.bind(card))
		_hero_cards[String(hero.hero_id)] = card


func _on_card_pressed(card: HeroCard) -> void:
	var hid: String = card.get_hero_id()
	if hid == "" or hid == LoadoutState.selected_hero_id:
		return
	if not UnlockManager.is_hero_unlocked(hid):
		return
	LoadoutState.selected_hero_id = hid
	EventBus.hero_selected.emit(hid)


func _refresh_roster_progress() -> void:
	for hid in _hero_cards.keys():
		var card: HeroCard = _hero_cards[hid]
		if card != null and card.has_method("setup"):
			card.setup(ContentRegistry.find_hero(hid))
			card.set_selected(hid == LoadoutState.selected_hero_id)


func _on_hero_selected(hero_id: String) -> void:
	# Roster cards re-mark selected.
	for hid in _hero_cards.keys():
		var card: HeroCard = _hero_cards[hid]
		if card != null:
			card.set_selected(hid == hero_id)
	_refresh_hero_hall()
	_refresh_action_tile_subtitles()
	# If a sub-view is open, refresh it (Skills builds itself; Equipment/Talents
	# already listen to hero_selected via EventBus).
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

	# --- ActionRow (4 tiles, wrapping) ---
	# HFlowContainer instead of HBoxContainer so 4×200 + 3×12 = 836 px of
	# tiles wrap onto two rows on narrower aspect ratios instead of being
	# squeezed/overlapping. Min height fits one row of 120-tall tiles plus
	# v_separation; if a wrap fires, the container grows naturally.
	var action_row := HFlowContainer.new()
	action_row.custom_minimum_size = Vector2(0, 128)
	action_row.alignment = HFlowContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("h_separation", 12)
	action_row.add_theme_constant_override("v_separation", 12)
	hero_hall_view.add_child(action_row)

	for entry in [["stats", "Stats"], ["equipment", "Equipment"], ["skills", "Skills"], ["talents", "Talents"]]:
		var tile: ActionTile = _ActionTileScript.new()
		tile.setup(String(entry[0]), String(entry[1]))
		tile.pressed.connect(_on_action_tile_pressed.bind(String(entry[0])))
		action_row.add_child(tile)
		_action_tiles[String(entry[0])] = tile

	_refresh_action_tile_subtitles()


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


func _refresh_hero_hall() -> void:
	if _hall_name_label == null:
		return
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data == null:
		_hall_name_label.text = "No hero"
		_hall_level_label.text = ""
		_hall_xp_label.text = ""
		_hall_stats_label.text = ""
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
	# Stats lines.
	_hall_stats_label.text = "%s\nHP   %d\nDMG  %d\nRNG  %d\nSPD  %.2f\nARM  %d%%" % [
		dmg_type,
		int(hero_data.max_health),
		int(round(hero_data.attack_damage)),
		int(round(hero_data.attack_range)),
		float(hero_data.attack_speed),
		int(round(float(hero_data.armor) * 100.0)),
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


# --- Action tiles + sub-view routing --------------------------------------

func _on_action_tile_pressed(kind: String) -> void:
	_open_sub_view(kind)


func _refresh_action_tile_subtitles() -> void:
	# Stats — placeholder (no live count).
	_set_tile_subtitle("stats", "(coming soon)")
	# Equipment — count items in inventory pool.
	var equipped_count: int = 0
	if has_node("/root/InventoryManager"):
		equipped_count = InventoryManager.get_all_equipped(LoadoutState.selected_hero_id).size()
	_set_tile_subtitle("equipment", "%d equipped" % equipped_count)
	# Skills — count equipped of slot cap.
	var equipped: Array[String] = LoadoutState.get_equipped_skills(LoadoutState.selected_hero_id)
	var cnt: int = 0
	for s in equipped:
		if s != "":
			cnt += 1
	_set_tile_subtitle("skills", "%d / %d equipped" % [cnt, LoadoutState.EQUIPPED_SKILL_SLOTS])
	# Talents — show unspent stars (live count via getter).
	var stars: int = 0
	if has_node("/root/MetaProgression") and MetaProgression.has_method("get_available_stars"):
		stars = int(MetaProgression.get_available_stars())
	_set_tile_subtitle("talents", "%d ★ to spend" % stars)


func _set_tile_subtitle(kind: String, text: String) -> void:
	if not _action_tiles.has(kind):
		return
	var tile: ActionTile = _action_tiles[kind]
	if tile != null and tile.has_method("set_subtitle"):
		tile.set_subtitle(text)


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

	_current_sub = kind
	hero_hall_view.visible = false
	sub_view.visible = true
	# Equipment is inventory-heavy (paperdoll + 10×5 grid). Hide the roster
	# rail so the screen gets the full width — at 1920×1080 the inventory
	# would otherwise need a 192-px horizontal scroll. Stats/Skills/Talents
	# don't benefit from the extra width and keep the rail visible so the
	# player can switch hero without backing out.
	if roster_rail != null:
		roster_rail.visible = (kind != "equipment")
	# Top bar: swap Back chip to point back to Hero Hall + retitle.
	# Use "Hero Hall" (not just "Hall") so it reads as a destination, not
	# an ambiguous label.
	back_button.text = "← Hero Hall"
	title_label.text = _title_for_sub(kind)
	# Build the sub-view body.
	match kind:
		"stats":
			_build_stats_subview()
		"skills":
			_build_skills_subview()
		"equipment":
			_embed_screen("res://ui/EquipmentScreen.tscn")
		"talents":
			_embed_screen("res://ui/TalentScreen.tscn")
		_:
			pass


func _close_sub_view() -> void:
	for child in sub_view.get_children():
		child.queue_free()
	_skills_equipped_slots.clear()
	_skills_available_grid = null
	_skills_locked_grid = null
	_skills_header_label = null
	_current_sub = ""
	sub_view.visible = false
	hero_hall_view.visible = true
	# Restore roster rail (Equipment may have hidden it).
	if roster_rail != null:
		roster_rail.visible = true
	back_button.text = "← Back"
	title_label.text = "HERO HALL"


func _on_back() -> void:
	if _current_sub != "":
		_close_sub_view()
	else:
		SceneManager.goto("res://ui/WorldMap.tscn")


func _title_for_sub(kind: String) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	var name_str: String = String(hero_data.hero_name) if hero_data != null else ""
	match kind:
		"stats":
			return "STATS — %s" % name_str
		"equipment":
			return "EQUIPMENT — %s" % name_str
		"skills":
			return "SKILLS — %s" % name_str
		"talents":
			return "TALENTS — %s" % name_str
	return "HERO HALL"


func _embed_screen(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("[HeroesHub] failed to load %s" % scene_path)
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
		"Body/LeftPanel/LeftTitle",
		"Body/LeftPanel/StatsTitle",
		"Body/LeftPanel/DetailsTitle",
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


# --- Stats sub-view (stub) ------------------------------------------------

func _build_stats_subview() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	sub_view.add_child(vbox)

	var title := Label.new()
	title.text = "Stats"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Strength · Stamina · Dexterity\n(future system)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1.0))
	vbox.add_child(sub)

	var hint := Label.new()
	hint.text = "Coming soon"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 1.0))
	vbox.add_child(hint)


# --- Skills sub-view (drag-and-drop) --------------------------------------

const _SKILL_TILE_SIZE: Vector2 = Vector2(180, 100)
const _SKILL_SLOT_SIZE: Vector2 = Vector2(180, 100)


func _build_skills_subview() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 16)
	sub_view.add_child(vbox)

	_skills_header_label = Label.new()
	_skills_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skills_header_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_skills_header_label)

	_add_section_label(vbox, "EQUIPPED  (drag a skill here · tap a filled slot to clear)")
	var equipped_row := HBoxContainer.new()
	equipped_row.alignment = BoxContainer.ALIGNMENT_CENTER
	equipped_row.add_theme_constant_override("separation", 16)
	vbox.add_child(equipped_row)
	for slot_idx in LoadoutState.EQUIPPED_SKILL_SLOTS:
		var slot := _SkillSlot.new()
		slot.setup(slot_idx, self)
		equipped_row.add_child(slot)
		_skills_equipped_slots.append(slot)

	_add_section_label(vbox, "AVAILABLE  (drag onto an equipped slot)")
	_skills_available_grid = HFlowContainer.new()
	_skills_available_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_available_grid.add_theme_constant_override("h_separation", 12)
	_skills_available_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_skills_available_grid)

	_add_section_label(vbox, "LOCKED  (unlock by leveling)")
	_skills_locked_grid = HFlowContainer.new()
	_skills_locked_grid.alignment = HFlowContainer.ALIGNMENT_CENTER
	_skills_locked_grid.add_theme_constant_override("h_separation", 12)
	_skills_locked_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_skills_locked_grid)

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
		tile.setup(sid, _skill_name(hero_data, sid), false)
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
		tile.setup(String(skill.skill_id), "??? Lv %d" % lr, true)
		_skills_locked_grid.add_child(tile)


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
	const _ANCHOR_FRACTION: float = 0.85
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
	const _SIZE: Vector2 = Vector2(180, 100)
	const _BG_NORMAL: Color = Color(0.18, 0.24, 0.34, 1.0)
	const _BG_LOCKED: Color = Color(0.10, 0.13, 0.18, 1.0)
	const _BORDER: Color = Color(0.45, 0.50, 0.62, 1.0)
	const _BORDER_LOCKED: Color = Color(0.30, 0.34, 0.42, 1.0)
	var _skill_id: String = ""
	var _name: String = ""
	var _locked: bool = false
	func _init() -> void:
		custom_minimum_size = _SIZE
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	func setup(skill_id: String, display_name: String, locked: bool) -> void:
		_skill_id = skill_id
		_name = display_name
		_locked = locked
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if locked else Control.CURSOR_DRAG
		queue_redraw()
	func _get_drag_data(_at: Vector2) -> Variant:
		if _locked or _skill_id == "":
			return null
		var preview := _SkillTile.new()
		preview.setup(_skill_id, _name, false)
		preview.size = _SIZE
		preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
		set_drag_preview(preview)
		return {"skill_id": _skill_id, "source": "available", "from_slot": -1}
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg: Color = _BG_LOCKED if _locked else _BG_NORMAL
		var border: Color = _BORDER_LOCKED if _locked else _BORDER
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, 1.5)
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var col: Color = Color(0.55, 0.6, 0.7, 1.0) if _locked else Color.WHITE
		var label_size := font.get_string_size(_name, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16)
		var pos := Vector2((size.x - label_size.x) * 0.5, size.y * 0.5 + 6.0)
		draw_string(font, pos, _name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, col)


class _SkillSlot extends Control:
	# Drop target. Tap (no drag) on a filled slot clears it.
	const _SIZE: Vector2 = Vector2(180, 100)
	const _BG_EMPTY: Color = Color(0.10, 0.13, 0.18, 1.0)
	const _BG_FILLED: Color = Color(0.20, 0.30, 0.46, 1.0)
	const _BORDER_EMPTY: Color = Color(0.30, 0.34, 0.42, 1.0)
	const _BORDER_FILLED: Color = Color(1.0, 0.85, 0.4, 1.0)
	var _slot_idx: int = -1
	var _skill_id: String = ""
	var _name: String = ""
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
		if skill_id != "" and hero_data != null:
			for skill in hero_data.skills:
				if skill != null and skill.skill_id == skill_id:
					_name = String(skill.skill_name)
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
		if event is InputEventMouseButton or event is InputEventScreenTouch:
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
		var lbl_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16)
		var pos := Vector2((size.x - lbl_size.x) * 0.5, size.y * 0.5 + 6.0)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, col)
