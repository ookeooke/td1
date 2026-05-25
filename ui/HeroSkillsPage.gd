extends Control

# Unified hero Skills page — replaces the prior "Skills" (active drag-grid) +
# "Talents" (skill tree) split inside HeroesHub. Embedded the same way both
# predecessors were: instanced into HeroesHub.sub_view by _open_sub_view.
#
# Three bands top-to-bottom, plus a side inspector that updates on tap:
#   1. HEADER          — Lv / Points ★
#   2. ACTIVE LOADOUT  — N slots (1-3 by hero level, from LoadoutState)
#   3. PASSIVE LOADOUT — N chips (1-3 by hero level)
#   4. SKILL TREE      — tab-filtered list (All / Skills / Passives / Mods),
#                        rows lifted verbatim from HeroSkillTreeScreen
#   ➡ INSPECTOR        — right side panel, content depends on what was tapped
#
# Per Preventive Bug Rule 3: re-reads LoadoutState.selected_hero_id and
# refreshes on EventBus.hero_selected so swapping heroes in the sidebar
# refreshes everything underneath.

const _PANEL_BG: Color = Color(0.13, 0.17, 0.23, 1.0)
const _PANEL_BG_DIM: Color = Color(0.10, 0.13, 0.18, 1.0)
const _PANEL_BORDER: Color = Color(0.25, 0.30, 0.40, 1.0)
const _GOLD: Color = Color(1.0, 0.85, 0.4, 1.0)
const _MUTED: Color = Color(0.55, 0.62, 0.74, 1.0)
const _TEXT: Color = Color(0.92, 0.95, 1.0, 1.0)
const _OK_BORDER: Color = Color(0.45, 0.85, 0.55, 1.0)
const _DENY_BORDER: Color = Color(0.65, 0.30, 0.40, 1.0)
const _ACTIVE_ACCENT: Color = Color(0.45, 0.65, 1.00, 1.0)
const _PASSIVE_ACCENT: Color = Color(0.85, 0.55, 1.00, 1.0)

# Preloaded — autoloads compile before class_name registry, mirroring the
# pattern in HeroSkillTreeScreen / LoadoutState.
const _HeroSkillNodeDataScript = preload("res://heroes/HeroSkillNodeData.gd")
const _SkillGlyphScript = preload("res://ui/SkillGlyph.gd")
const _SkillMapScript = preload("res://ui/HeroSkillMap.gd")


# Small procedural icon Control. Sized via custom_minimum_size; reads its
# pictogram key + tint colors from setup(). Empty pictogram = nothing drawn
# (caller still gets a sized spacer). Matches the rendering CooldownButton
# uses in-level so the equip UI and the in-level SkillBar look like a set.
class _SkillGlyphIcon extends Control:
	var _key: String = ""
	var _white: Color = Color(1, 1, 1, 1)
	var _dark: Color = Color(0.07, 0.09, 0.12, 1)
	const _GLYPH_SCRIPT = preload("res://ui/SkillGlyph.gd")

	func setup(key: String, px: float, white: Color, dark: Color) -> void:
		_key = key
		_white = white
		_dark = dark
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		if _key == "":
			return
		var g: float = min(size.x, size.y) * 0.45
		_GLYPH_SCRIPT.draw(self, _key, size * 0.5, g, _white, _dark)

# Tab filter: -1 = ALL, or HeroSkillNodeData.Kind value (0=Skills, 1=Passives, 2=Mods).
const _TAB_ALL: int = -1

# Inspector mode keys.
const _INSP_NONE: int = 0
const _INSP_ACTIVE_SLOT: int = 1  # tapped an active-loadout slot
const _INSP_PASSIVE_SLOT: int = 2  # tapped a passive-loadout chip
const _INSP_TREE_NODE: int = 3  # tapped a tree row

var _hero_id: String = ""
# Tracks the hero_id used by the previous refresh so we can drop inspector
# state wholesale on hero swap. The active-slot / passive-slot inspector
# modes cache a slot_index that's meaningless on the new hero (e.g. L8
# warrior has 3 active slots; switching to a L1 hero leaves the inspector
# pointing at slot 2 which doesn't exist).
var _last_refreshed_hero_id: String = ""

# Header
var _points_label: Label = null

# Bands
var _active_row: HBoxContainer = null
var _passive_row: HBoxContainer = null

# Tabs
var _tab_buttons: Dictionary = {}  # kind_int → Button
var _active_tab: int = _TAB_ALL

# Tree list
var _nodes_vbox: VBoxContainer = null

# Inspector (right side panel)
var _inspector_panel: PanelContainer = null
var _inspector_vbox: VBoxContainer = null
var _insp_mode: int = _INSP_NONE
var _insp_content_id: String = ""
var _insp_slot_index: int = -1

# Unified-chooser Phase 3 — skill-map view. Additive: the legacy tab+list
# stays built and reachable via the view toggle until the map is verified.
var _list_col: VBoxContainer = null
var _map_scroll: ScrollContainer = null
var _skill_map: Control = null
var _view_toggle: Button = null
var _view_mode: String = "map"   # "map" | "list"
var _map_hero_id: String = ""
# Floating detail card (map mode). The legacy/list mode keeps the docked
# right panel; in map mode the same rendered content shows in a card placed
# next to the tapped node/slot, so the info reads as part of the map (the
# right-corner panel felt disconnected from a spatial constellation).
var _docked_vbox: VBoxContainer = null
var _float_overlay: Control = null
var _float_panel: PanelContainer = null
var _float_vbox: VBoxContainer = null
const _FLOAT_W: float = 360.0
const _FLOAT_H: float = 560.0
const _NODE_GAP: float = 52.0
var _float_scroll: ScrollContainer = null
var _float_a: Vector2 = Vector2.ZERO       # anchor (overlay-local) of open card
var _float_below: bool = false             # place card below anchor vs beside
var _float_refit_tries: int = 0            # bounded retries for deferred refit
var _float_close: Button = null            # ✕ on the floating card
# Two-step confirm for the point-spending BUY action (unified-chooser
# Phase 5). Mirrors EquipmentScreen's sell-arm: first tap arms, second tap
# on the same node commits, 3s auto-disarm. Equip/unequip stay single-tap
# (reversible — single-tap carve-out per the interaction rule).
var _buy_armed_id: String = ""


func _ready() -> void:
	_hero_id = LoadoutState.selected_hero_id
	_last_refreshed_hero_id = _hero_id
	_build_layout()
	_refresh_all()
	EventBus.hero_node_purchased.connect(_on_state_changed)
	EventBus.hero_skill_points_changed.connect(_on_state_changed)
	EventBus.hero_passive_equipped.connect(_on_state_changed)
	EventBus.hero_skill_equipped.connect(_on_state_changed)
	EventBus.hero_skill_mod_chosen.connect(_on_state_changed)
	EventBus.hero_leveled_up.connect(_on_state_changed)
	EventBus.hero_selected.connect(_on_state_changed)


func _exit_tree() -> void:
	if EventBus.hero_node_purchased.is_connected(_on_state_changed):
		EventBus.hero_node_purchased.disconnect(_on_state_changed)
	if EventBus.hero_skill_points_changed.is_connected(_on_state_changed):
		EventBus.hero_skill_points_changed.disconnect(_on_state_changed)
	if EventBus.hero_passive_equipped.is_connected(_on_state_changed):
		EventBus.hero_passive_equipped.disconnect(_on_state_changed)
	if EventBus.hero_skill_equipped.is_connected(_on_state_changed):
		EventBus.hero_skill_equipped.disconnect(_on_state_changed)
	if EventBus.hero_skill_mod_chosen.is_connected(_on_state_changed):
		EventBus.hero_skill_mod_chosen.disconnect(_on_state_changed)
	if EventBus.hero_leveled_up.is_connected(_on_state_changed):
		EventBus.hero_leveled_up.disconnect(_on_state_changed)
	if EventBus.hero_selected.is_connected(_on_state_changed):
		EventBus.hero_selected.disconnect(_on_state_changed)


func _on_state_changed(_a = null, _b = null, _c = null) -> void:
	_refresh_all()


# ── Layout build (run once in _ready) ──────────────────────────────────

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	add_child(outer)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)

	# Header row — Lv / Points on the left, "Reset to default" button right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 20)
	_points_label.add_theme_color_override("font_color", _GOLD)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_points_label)

	# Reset-to-default — re-applies HeroData.starter_skill_ids (or the
	# implicit first-N fallback) to the active loadout. Doesn't touch passives
	# (those are owned-content gated; resetting could un-equip a paid-for
	# passive the player intends to keep).
	var reset_btn := Button.new()
	reset_btn.text = "Reset to default"
	reset_btn.tooltip_text = "Restore the active loadout to the hero's authored starter skills."
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	# Map/List view toggle — keeps the legacy list reachable while the
	# constellation is the default (unified-chooser Phase 3).
	_view_toggle = Button.new()
	_view_toggle.focus_mode = Control.FOCUS_NONE
	_view_toggle.custom_minimum_size = Vector2(124, 40)
	_view_toggle.pressed.connect(_on_view_toggle)
	header.add_child(_view_toggle)

	# Active loadout band.
	_add_section_label(root, "ACTIVE LOADOUT", _ACTIVE_ACCENT)
	_active_row = HBoxContainer.new()
	_active_row.add_theme_constant_override("separation", 12)
	root.add_child(_active_row)

	# Passive loadout band.
	_add_section_label(root, "PASSIVE LOADOUT", _PASSIVE_ACCENT)
	_passive_row = HBoxContainer.new()
	_passive_row.add_theme_constant_override("separation", 12)
	root.add_child(_passive_row)

	# Body row: tree list LEFT, inspector RIGHT.
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# LEFT: tab bar + scrolling node list.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_list_col = left

	var tab_header := HBoxContainer.new()
	tab_header.add_theme_constant_override("separation", 12)
	left.add_child(tab_header)

	var tree_label := Label.new()
	tree_label.text = "SKILL TREE"
	tree_label.add_theme_font_size_override("font_size", 14)
	tree_label.add_theme_color_override("font_color", _MUTED)
	tree_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_header.add_child(tree_label)

	for entry in [
		[_TAB_ALL,                                "All"],
		[_HeroSkillNodeDataScript.Kind.ACTIVE_RANK, "Skills"],
		[_HeroSkillNodeDataScript.Kind.PASSIVE_RANK,"Passives"],
		[_HeroSkillNodeDataScript.Kind.MOD,         "Mods"],
	]:
		var kind_val: int = int(entry[0])
		var label: String = String(entry[1])
		var btn := Button.new()
		btn.text = label
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(82, 32)
		btn.pressed.connect(func(): _on_tab_pressed(kind_val))
		tab_header.add_child(btn)
		_tab_buttons[kind_val] = btn

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_nodes_vbox = VBoxContainer.new()
	_nodes_vbox.add_theme_constant_override("separation", 6)
	_nodes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_nodes_vbox)

	# RIGHT: inspector panel — fixed 460 wide.
	_inspector_panel = PanelContainer.new()
	_inspector_panel.custom_minimum_size = Vector2(460, 0)
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var insp_sb := _make_stylebox(_PANEL_BG, _PANEL_BORDER)
	insp_sb.content_margin_left = 16
	insp_sb.content_margin_right = 16
	insp_sb.content_margin_top = 14
	insp_sb.content_margin_bottom = 14
	_inspector_panel.add_theme_stylebox_override("panel", insp_sb)
	body.add_child(_inspector_panel)

	_inspector_vbox = VBoxContainer.new()
	_inspector_vbox.add_theme_constant_override("separation", 8)
	_inspector_panel.add_child(_inspector_vbox)
	_docked_vbox = _inspector_vbox

	# Skill-map view — sibling of the legacy list, before the inspector.
	# Inspect-only: node taps route into the EXISTING _inspect_tree_node
	# pipeline, so the inspector + all action buttons are reused unchanged.
	_map_scroll = ScrollContainer.new()
	_map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skill_map = _SkillMapScript.new()
	_skill_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_scroll.add_child(_skill_map)
	body.add_child(_map_scroll)
	body.move_child(_map_scroll, _list_col.get_index() + 1)
	_skill_map.node_selected.connect(_inspect_tree_node)

	# Floating detail card overlay (map mode). Full-page, input-transparent
	# except the card itself; sits above `body` so the card draws over the
	# map. Same content as the docked panel — only the host vbox differs.
	_float_overlay = Control.new()
	_float_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_overlay.visible = false
	add_child(_float_overlay)
	_float_panel = PanelContainer.new()
	_float_panel.custom_minimum_size = Vector2(_FLOAT_W, 0)
	_float_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var fsb := _make_stylebox(_PANEL_BG, _PANEL_BORDER)
	fsb.content_margin_left = 16
	fsb.content_margin_right = 16
	fsb.content_margin_top = 14
	fsb.content_margin_bottom = 14
	_float_panel.add_theme_stylebox_override("panel", fsb)
	_float_panel.visible = false
	_float_overlay.add_child(_float_panel)
	# Inner scroll so a tall node (status + cost + requires + equip + buy)
	# never exceeds the card; fixed width so autowrap labels wrap correctly
	# (a free-floating PanelContainer otherwise computes height vs ~0 width).
	_float_scroll = ScrollContainer.new()
	_float_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_float_panel.add_child(_float_scroll)
	_float_vbox = VBoxContainer.new()
	_float_vbox.add_theme_constant_override("separation", 8)
	_float_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_float_vbox.custom_minimum_size = Vector2(_FLOAT_W - 36.0, 0)
	_float_scroll.add_child(_float_vbox)
	# Explicit close affordance — sits above the card at its top-right.
	# (A full-screen outside-tap catcher would block dragging the map to
	# pan, so we use ✕ + tap-empty-map instead.)
	_float_close = Button.new()
	_float_close.text = "✕"
	_float_close.focus_mode = Control.FOCUS_NONE
	_float_close.custom_minimum_size = Vector2(40, 40)
	_float_close.size = Vector2(40, 40)
	_float_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_float_close.visible = false
	_float_close.pressed.connect(_dismiss_float_card)
	_float_overlay.add_child(_float_close)
	# Re-place the card when the map scrolls (node moves on screen).
	var hsb: HScrollBar = _map_scroll.get_h_scroll_bar()
	var vsb: VScrollBar = _map_scroll.get_v_scroll_bar()
	if hsb != null:
		hsb.value_changed.connect(func(_v: float) -> void: _position_float_card())
	if vsb != null:
		vsb.value_changed.connect(func(_v: float) -> void: _position_float_card())

	_apply_view_mode()


func _add_section_label(parent: Container, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)


# ── Refresh ────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	var new_hero_id: String = LoadoutState.selected_hero_id
	if new_hero_id != _last_refreshed_hero_id:
		# Hero swapped — drop inspector wholesale. Slot index, content_id,
		# and mode all become meaningless on the new hero. The stale-node
		# guard below covers hero-internal changes (content reload etc.).
		_clear_inspector()
		_last_refreshed_hero_id = new_hero_id
	_hero_id = new_hero_id
	if _insp_mode == _INSP_TREE_NODE:
		var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
		if tree == null or tree.find_node(_insp_content_id) == null:
			_clear_inspector()
	_refresh_header()
	_refresh_active_row()
	_refresh_passive_row()
	_refresh_tabs()
	_refresh_nodes()
	_refresh_inspector()
	_refresh_skill_map()


func _refresh_header() -> void:
	if _points_label == null:
		return
	var lvl: int = MetaProgression.get_hero_level(_hero_id)
	var pts: int = MetaProgression.get_skill_points(_hero_id)
	_points_label.text = "Lv %d    Points: %d ★" % [lvl, pts]


# ── Active band ────────────────────────────────────────────────────────

func _refresh_active_row() -> void:
	if _active_row == null:
		return
	for c in _active_row.get_children():
		c.queue_free()
	var hero_data: Resource = ContentRegistry.find_hero(_hero_id)
	if hero_data == null:
		return
	var cap: int = LoadoutState.get_active_slot_cap(_hero_id)
	var equipped: Array[String] = LoadoutState.get_equipped_skills(_hero_id)
	for i in cap:
		var sid: String = equipped[i] if i < equipped.size() else ""
		_active_row.add_child(_make_active_slot_card(i, sid, hero_data))


func _make_active_slot_card(slot_idx: int, skill_id: String, hero_data: Resource) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(200, 84)
	card.focus_mode = Control.FOCUS_NONE
	var bg: Color = _PANEL_BG if skill_id != "" else _PANEL_BG_DIM
	var border: Color = _ACTIVE_ACCENT if skill_id != "" else _PANEL_BORDER
	var sb := _make_stylebox(bg, border)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", _make_stylebox(bg.lightened(0.05), _GOLD))
	card.add_theme_stylebox_override("pressed", sb)

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_top = 8
	h.offset_right = -8
	h.offset_bottom = -8
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Icon (left). Uses the skill's authored pictogram via SkillGlyph; empty
	# slots show a dimmed dotted ring placeholder via the same control so the
	# card layout stays stable.
	var icon := _SkillGlyphIcon.new()
	var icon_white: Color = _TEXT if skill_id != "" else _MUTED
	icon.setup(_skill_pictogram(hero_data, skill_id), 56.0, icon_white, _PANEL_BG_DIM)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var name_lbl := Label.new()
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 14)
	if skill_id == "":
		name_lbl.text = "(empty)"
		name_lbl.add_theme_color_override("font_color", _MUTED)
	else:
		name_lbl.text = _skill_name(hero_data, skill_id)
		name_lbl.add_theme_color_override("font_color", _TEXT)
	v.add_child(name_lbl)

	# Mod chip — name of the currently-chosen mod, or "—".
	if skill_id != "":
		var mod_id: String = LoadoutState.get_chosen_mod(_hero_id, skill_id)
		var mod_lbl := Label.new()
		mod_lbl.add_theme_font_size_override("font_size", 11)
		mod_lbl.add_theme_color_override("font_color", _GOLD if mod_id != "" else _MUTED)
		mod_lbl.text = _mod_short_name(mod_id) if mod_id != "" else "—"
		v.add_child(mod_lbl)

	card.pressed.connect(func(): _inspect_active_slot(slot_idx, skill_id))
	return card


# ── Passive band ───────────────────────────────────────────────────────

func _refresh_passive_row() -> void:
	if _passive_row == null:
		return
	for c in _passive_row.get_children():
		c.queue_free()
	var cap: int = LoadoutState.get_passive_slot_cap(_hero_id)
	var equipped: Array[String] = LoadoutState.get_equipped_passives(_hero_id)
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	for i in cap:
		var pid: String = equipped[i] if i < equipped.size() else ""
		_passive_row.add_child(_make_passive_chip(i, pid, tree))


func _make_passive_chip(slot_idx: int, passive_id: String, tree: Resource) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(140, 84)
	card.focus_mode = Control.FOCUS_NONE
	var bg: Color = _PANEL_BG if passive_id != "" else _PANEL_BG_DIM
	var border: Color = _PASSIVE_ACCENT if passive_id != "" else _PANEL_BORDER
	var sb := _make_stylebox(bg, border)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", _make_stylebox(bg.lightened(0.05), _GOLD))
	card.add_theme_stylebox_override("pressed", sb)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 13)
	if passive_id == "":
		name_lbl.text = "(empty)"
		name_lbl.add_theme_color_override("font_color", _MUTED)
	else:
		name_lbl.text = (tree.get_passive_name(passive_id) if tree != null else passive_id)
		name_lbl.add_theme_color_override("font_color", _TEXT)
	v.add_child(name_lbl)

	if passive_id != "":
		var rank_lbl := Label.new()
		rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_lbl.add_theme_font_size_override("font_size", 12)
		rank_lbl.add_theme_color_override("font_color", _GOLD)
		var purchased: int = MetaProgression.get_purchased_passive_rank(_hero_id, passive_id)
		var dots: String = ""
		for i in 3:
			dots += "★" if i < purchased else "☆"
		rank_lbl.text = dots
		v.add_child(rank_lbl)

	card.pressed.connect(func(): _inspect_passive_slot(slot_idx, passive_id))
	return card


# ── Tabs + tree list ───────────────────────────────────────────────────

func _on_tab_pressed(kind: int) -> void:
	if _active_tab == kind:
		return
	_active_tab = kind
	_refresh_tabs()
	_refresh_nodes()


func _refresh_tabs() -> void:
	for k in _tab_buttons.keys():
		var btn: Button = _tab_buttons[k]
		var is_active: bool = (int(k) == _active_tab)
		btn.modulate = Color.WHITE if is_active else Color(0.6, 0.65, 0.75, 1.0)
		var sb := _make_stylebox(_PANEL_BG if is_active else _PANEL_BG_DIM,
			_GOLD if is_active else _PANEL_BORDER)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)


func _refresh_nodes() -> void:
	if _nodes_vbox == null:
		return
	for c in _nodes_vbox.get_children():
		c.queue_free()
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree == null:
		var msg := Label.new()
		msg.text = "No skill tree authored for this hero."
		msg.add_theme_color_override("font_color", _MUTED)
		_nodes_vbox.add_child(msg)
		return
	for node in tree.nodes:
		if node == null:
			continue
		if not _tab_matches(int(node.kind)):
			continue
		_nodes_vbox.add_child(_make_node_row(node))
	if _nodes_vbox.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "(no nodes in this category)"
		empty.add_theme_color_override("font_color", _MUTED)
		_nodes_vbox.add_child(empty)


func _tab_matches(node_kind: int) -> bool:
	if _active_tab == _TAB_ALL:
		return true
	# Mods tab folds in both MOD and CAPSTONE / SLOT_UNLOCK = no — keep Mods
	# strictly to MOD kind so the categorization stays predictable.
	return node_kind == _active_tab


# Lifted from HeroSkillTreeScreen._make_node_row with one change: tapping
# the row anywhere outside the BUY button selects the node for the right-
# side inspector instead of opening a popup. BUY stays as inline action.
func _make_node_row(node: Resource) -> Control:
	var row := PanelContainer.new()
	var node_id: String = String(node.node_id)
	var is_selected: bool = (_insp_mode == _INSP_TREE_NODE and _insp_content_id == node_id)
	var sb := _make_stylebox(_PANEL_BG, _GOLD if is_selected else _PANEL_BORDER)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	# Left icon — ACTIVE_RANK + MOD nodes carry a target_id (skill_id); look
	# up the skill's pictogram. Other kinds (passive/slot/capstone) keep the
	# unicode kind glyph in the title text below.
	var kind: int = int(node.kind)
	var pictogram: String = ""
	if kind == _HeroSkillNodeDataScript.Kind.ACTIVE_RANK \
			or kind == _HeroSkillNodeDataScript.Kind.MOD:
		var hero_data: Resource = ContentRegistry.find_hero(_hero_id)
		pictogram = _skill_pictogram(hero_data, String(node.target_id))
	if pictogram != "":
		var icon := _SkillGlyphIcon.new()
		icon.setup(pictogram, 36.0, _TEXT, _PANEL_BG)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(icon)

	# Left: kind glyph + title + description.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	h.add_child(left)

	var title := Label.new()
	var rank_str: String = ""
	if int(node.rank) > 0 and kind != _HeroSkillNodeDataScript.Kind.MOD \
			and kind != _HeroSkillNodeDataScript.Kind.CAPSTONE \
			and kind != _HeroSkillNodeDataScript.Kind.SLOT_UNLOCK:
		rank_str = " — Rank %d" % int(node.rank)
	# When an icon is drawn, drop the unicode kind glyph (avoid double-icon).
	var glyph_prefix: String = "" if pictogram != "" else _kind_glyph(kind)
	title.text = "%s%s%s" % [glyph_prefix, String(node.node_name), rank_str]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _TEXT)
	left.add_child(title)

	var desc := Label.new()
	desc.text = String(node.description)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", _MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(desc)

	# Right: BUY / PURCHASED / mod toggle.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(160, 0)
	h.add_child(right)

	var purchased_rank: int = MetaProgression.get_purchased_rank(_hero_id, node_id)
	var is_mod: bool = int(node.kind) == _HeroSkillNodeDataScript.Kind.MOD
	if purchased_rank >= int(node.rank):
		if is_mod:
			right.add_child(_make_mod_status_widget(node))
		else:
			var status := Label.new()
			status.text = "PURCHASED"
			status.add_theme_color_override("font_color", _OK_BORDER)
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(status)
	else:
		var check: Dictionary = MetaProgression.can_purchase_node(_hero_id, node_id)
		var buy := Button.new()
		buy.text = "BUY · %d ★" % int(node.point_cost)
		buy.disabled = not check.ok
		buy.add_theme_color_override("font_color", _TEXT if check.ok else _MUTED)
		buy.pressed.connect(func(): _on_buy_pressed(node_id))
		right.add_child(buy)
		if not check.ok:
			var reason := Label.new()
			reason.text = String(check.reason)
			reason.add_theme_font_size_override("font_size", 11)
			reason.add_theme_color_override("font_color", _DENY_BORDER)
			reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(reason)

	# Whole-row tap → inspect. The overlay is added first (so it draws under
	# the row content). Godot dispatches input from last child to first, so
	# the inner BUY button (MOUSE_FILTER_STOP) captures its own taps; clicks
	# on label area fall through to the overlay below.
	var overlay := Button.new()
	overlay.flat = true
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.pressed.connect(func(): _inspect_tree_node(node_id))
	row.add_child(overlay)
	row.move_child(overlay, 0)
	return row


# Lifted verbatim from HeroSkillTreeScreen._make_mod_status_widget.
func _make_mod_status_widget(node: Resource) -> Control:
	var skill_id: String = String(node.target_id)
	var mod: Resource = node.ability
	if mod == null or not ("mod_id" in mod):
		var fallback := Label.new()
		fallback.text = "PURCHASED"
		fallback.add_theme_color_override("font_color", _OK_BORDER)
		return fallback
	var mod_id: String = String(mod.mod_id)
	var chosen: String = LoadoutState.get_chosen_mod(_hero_id, skill_id)
	if chosen == mod_id:
		var active := Label.new()
		active.text = "★ ACTIVE"
		active.add_theme_color_override("font_color", _GOLD)
		active.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		return active
	var pick := Button.new()
	pick.text = "Pick"
	pick.pressed.connect(_on_pick_mod.bind(skill_id, mod_id))
	return pick


# ── Inspector ──────────────────────────────────────────────────────────

func _inspect_active_slot(slot_idx: int, skill_id: String) -> void:
	_insp_mode = _INSP_ACTIVE_SLOT
	_insp_content_id = skill_id
	_insp_slot_index = slot_idx
	EventBus.skill_node_inspected.emit(int(_HeroSkillNodeDataScript.Kind.ACTIVE_RANK), skill_id, slot_idx)
	_refresh_nodes()  # update selection outline
	_refresh_inspector()


func _inspect_passive_slot(slot_idx: int, passive_id: String) -> void:
	_insp_mode = _INSP_PASSIVE_SLOT
	_insp_content_id = passive_id
	_insp_slot_index = slot_idx
	EventBus.skill_node_inspected.emit(int(_HeroSkillNodeDataScript.Kind.PASSIVE_RANK), passive_id, slot_idx)
	_refresh_nodes()
	_refresh_inspector()


func _inspect_tree_node(node_id: String) -> void:
	_insp_mode = _INSP_TREE_NODE
	_insp_content_id = node_id
	_insp_slot_index = -1
	_buy_armed_id = ""  # selecting a different node clears any armed buy
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree != null:
		var node: Resource = tree.find_node(node_id)
		if node != null:
			EventBus.skill_node_inspected.emit(int(node.kind), node_id, -1)
	_refresh_nodes()
	_refresh_inspector()


func _clear_inspector() -> void:
	_insp_mode = _INSP_NONE
	_insp_content_id = ""
	_insp_slot_index = -1
	_buy_armed_id = ""


# ── Skill-map view (unified-chooser Phase 3) ───────────────────────────
# Toggles between the constellation (default) and the legacy tab+list.
# Both are always built; only visibility changes, so the legacy path stays
# fully functional and verifiable until the map is signed off.

func _on_view_toggle() -> void:
	_view_mode = "list" if _view_mode == "map" else "map"
	_apply_view_mode()


func _apply_view_mode() -> void:
	var is_map: bool = _view_mode == "map"
	if _list_col != null:
		_list_col.visible = not is_map
	if _map_scroll != null:
		_map_scroll.visible = is_map
	if _view_toggle != null:
		_view_toggle.text = "≣ List view" if is_map else "▦ Map view"
	# Retarget where the (unchanged) render code draws: docked right panel
	# for list mode, floating card for map mode.
	if is_map:
		_inspector_vbox = _float_vbox
		if _inspector_panel != null:
			_inspector_panel.visible = false
		if _float_overlay != null:
			_float_overlay.visible = true
	else:
		_inspector_vbox = _docked_vbox
		if _inspector_panel != null:
			_inspector_panel.visible = true
		if _float_overlay != null:
			_float_overlay.visible = false
	_refresh_inspector()
	if is_map and _skill_map != null:
		if _map_hero_id != _hero_id:
			_map_hero_id = _hero_id
			_skill_map.setup(_hero_id)
		if _insp_mode == _INSP_TREE_NODE:
			_skill_map.set_selected_node(_insp_content_id)
		else:
			_skill_map.clear_selection()


func _refresh_skill_map() -> void:
	if _skill_map == null:
		return
	if _map_hero_id != _hero_id:
		# Hero swapped — rebuild nodes/positions for the new tree.
		_map_hero_id = _hero_id
		_skill_map.setup(_hero_id)
	else:
		# States (purchased / available / locked) are computed live in the
		# map's _draw from MetaProgression, so a redraw is enough after a
		# buy / level-up / equip.
		_skill_map.queue_redraw()
	if _insp_mode == _INSP_TREE_NODE:
		_skill_map.set_selected_node(_insp_content_id)
	else:
		_skill_map.clear_selection()


func _refresh_inspector() -> void:
	if _inspector_vbox == null:
		return
	for c in _inspector_vbox.get_children():
		c.queue_free()
	match _insp_mode:
		_INSP_NONE:
			_render_inspector_placeholder()
		_INSP_ACTIVE_SLOT:
			_render_inspector_active_slot()
		_INSP_PASSIVE_SLOT:
			_render_inspector_passive_slot()
		_INSP_TREE_NODE:
			_render_inspector_tree_node()
	_position_float_card()


# Place the floating detail card next to the tapped node (or loadout slot)
# in map mode; hide it when nothing meaningful is selected. List/Equipment
# keep the docked panel, so this is a no-op there.
func _position_float_card() -> void:
	if _view_mode != "map" or _float_panel == null or _float_overlay == null:
		return
	var anchor_g := Vector2.ZERO
	var below: bool = false
	var have_anchor: bool = false
	if _insp_mode == _INSP_TREE_NODE and _insp_content_id != "" \
			and _skill_map != null and _skill_map.has_node_pos(_insp_content_id):
		anchor_g = _skill_map.get_global_transform() \
			* _skill_map.node_pos(_insp_content_id)
		have_anchor = true
	elif _insp_mode == _INSP_ACTIVE_SLOT and _active_row != null:
		var c := _slot_widget(_active_row, _insp_slot_index)
		if c != null:
			anchor_g = c.get_global_rect().get_center() \
				+ Vector2(0, c.get_global_rect().size.y * 0.5)
			below = true
			have_anchor = true
	elif _insp_mode == _INSP_PASSIVE_SLOT and _passive_row != null:
		var c2 := _slot_widget(_passive_row, _insp_slot_index)
		if c2 != null:
			anchor_g = c2.get_global_rect().get_center() \
				+ Vector2(0, c2.get_global_rect().size.y * 0.5)
			below = true
			have_anchor = true
	if not have_anchor:
		_float_panel.visible = false
		if _float_close != null:
			_float_close.visible = false
		return
	_float_a = _float_overlay.get_global_transform().affine_inverse() * anchor_g
	_float_below = below
	_float_panel.visible = true
	# First pass uses the capped height (autowrap content can't be measured
	# until laid out); _refit shrinks to the real content height next frame.
	_place_float_card(minf(_FLOAT_H, maxf(160.0, _float_overlay.size.y - 16.0)))
	_float_refit_tries = 0
	call_deferred("_refit_float_card")


func _refit_float_card() -> void:
	if _float_panel == null or not _float_panel.visible:
		return
	if _float_vbox.size.y <= 1.0:
		# Layout not settled yet — keep the provisional capped card and
		# retry next frame rather than collapsing to the min height.
		_float_refit_tries += 1
		if _float_refit_tries <= 8:
			call_deferred("_refit_float_card")
		return
	var ov: float = _float_overlay.size.y - 16.0
	# _float_vbox.size.y is the real laid-out content height by now.
	var card_h: float = clampf(_float_vbox.size.y + 36.0, 110.0,
		minf(_FLOAT_H, maxf(160.0, ov)))
	_place_float_card(card_h)


func _place_float_card(card_h: float) -> void:
	_float_scroll.custom_minimum_size = Vector2(_FLOAT_W - 36.0, card_h)
	var ov: Vector2 = _float_overlay.size
	var sz: Vector2 = Vector2(_FLOAT_W, card_h + 24.0)
	var a: Vector2 = _float_a
	var pos: Vector2
	if _float_below:
		pos = Vector2(a.x - sz.x * 0.5, a.y + 10.0)
	else:
		pos = Vector2(a.x + _NODE_GAP, a.y - sz.y * 0.5)
		if pos.x + sz.x > ov.x - 8.0:
			pos.x = a.x - _NODE_GAP - sz.x  # flip to the node's left side
	pos.x = clampf(pos.x, 8.0, maxf(8.0, ov.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, ov.y - sz.y - 8.0))
	_float_panel.position = pos
	if _float_close != null:
		_float_close.position = pos + Vector2(_FLOAT_W - 46.0, 6.0)
		_float_close.visible = true


# Close the floating card: clear map selection + inspector, which makes
# _position_float_card hide the panel (and the ✕) on the next refresh.
func _dismiss_float_card() -> void:
	if _skill_map != null:
		_skill_map.set_selected_node("")
	_inspect_tree_node("")


func _slot_widget(row: HBoxContainer, idx: int) -> Control:
	if row == null or row.get_child_count() == 0:
		return null
	return row.get_child(clampi(idx, 0, row.get_child_count() - 1)) as Control


func _render_inspector_placeholder() -> void:
	var lbl := Label.new()
	lbl.text = "Tap a slot, chip, or tree row to inspect."
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", _MUTED)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_vbox.add_child(lbl)


func _render_inspector_active_slot() -> void:
	var hero_data: Resource = ContentRegistry.find_hero(_hero_id)
	if hero_data == null:
		return
	_inspector_vbox.add_child(_make_h2_label("ACTIVE SLOT %d" % (_insp_slot_index + 1), _ACTIVE_ACCENT))
	if _insp_content_id != "":
		var skill: Resource = _find_skill(hero_data, _insp_content_id)
		if skill != null:
			var name_str: String = String(skill.skill_name) if "skill_name" in skill else _insp_content_id
			var pictogram: String = _skill_pictogram(hero_data, _insp_content_id)
			_inspector_vbox.add_child(_make_icon_h1_row(pictogram, name_str))
			_inspector_vbox.add_child(_make_body_label(_describe_skill(skill)))
			var chosen_mod: String = LoadoutState.get_chosen_mod(_hero_id, _insp_content_id)
			if chosen_mod != "":
				_inspector_vbox.add_child(_make_kv_label("Mod", _mod_short_name(chosen_mod)))
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func(): _equip_active(_insp_slot_index, ""))
		_inspector_vbox.add_child(unequip_btn)
	else:
		_inspector_vbox.add_child(_make_body_label(
			"Empty slot. Tap a learned skill in the map — its panel has a slot picker + Equip."))


func _render_inspector_passive_slot() -> void:
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	_inspector_vbox.add_child(_make_h2_label("PASSIVE SLOT %d" % (_insp_slot_index + 1), _PASSIVE_ACCENT))
	if _insp_content_id != "" and tree != null:
		_inspector_vbox.add_child(_make_h1_label(tree.get_passive_name(_insp_content_id)))
		var purchased: int = MetaProgression.get_purchased_passive_rank(_hero_id, _insp_content_id)
		_inspector_vbox.add_child(_make_kv_label("Rank", "%d / 3" % purchased))
		_inspector_vbox.add_child(_make_body_label(_describe_passive(tree, _insp_content_id)))
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func(): _equip_passive(_insp_slot_index, ""))
		_inspector_vbox.add_child(unequip_btn)
	else:
		_inspector_vbox.add_child(_make_body_label(
			"Empty slot. Tap an owned passive in the map — its panel has a slot picker + Equip."))


func _render_inspector_tree_node() -> void:
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree == null:
		return
	var node: Resource = tree.find_node(_insp_content_id)
	if node == null:
		_clear_inspector()
		_render_inspector_placeholder()
		return
	var kind: int = int(node.kind)
	_inspector_vbox.add_child(_make_h2_label(_kind_label(kind), _kind_color(kind)))
	var hero_data: Resource = ContentRegistry.find_hero(_hero_id)
	var node_pict: String = ""
	if kind == _HeroSkillNodeDataScript.Kind.ACTIVE_RANK \
			or kind == _HeroSkillNodeDataScript.Kind.MOD:
		node_pict = _skill_pictogram(hero_data, String(node.target_id))
	_inspector_vbox.add_child(_make_icon_h1_row(node_pict, String(node.node_name)))
	_inspector_vbox.add_child(_make_body_label(String(node.description)))

	var purchased_rank: int = MetaProgression.get_purchased_rank(_hero_id, _insp_content_id)
	_inspector_vbox.add_child(_make_kv_label("Status",
		"Purchased" if purchased_rank >= int(node.rank) else "Available"))
	_inspector_vbox.add_child(_make_kv_label("Cost", "%d ★" % int(node.point_cost)))
	if int(node.level_required) > 1:
		_inspector_vbox.add_child(_make_kv_label("Level required", "%d" % int(node.level_required)))
	if not node.prerequisite_ids.is_empty():
		var names: PackedStringArray = []
		for pid in node.prerequisite_ids:
			var prereq: Resource = tree.find_node(String(pid))
			if prereq != null:
				names.append(String(prereq.node_name))
			else:
				names.append(String(pid))
		_inspector_vbox.add_child(_make_kv_label("Requires", ", ".join(names)))

	_add_equip_controls(node, kind)

	if purchased_rank < int(node.rank):
		var check: Dictionary = MetaProgression.can_purchase_node(_hero_id, _insp_content_id)
		var armed: bool = (_buy_armed_id == _insp_content_id and check.ok)
		var buy := Button.new()
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = not check.ok
		if armed:
			buy.text = "Confirm — spend %d ★" % int(node.point_cost)
			# Warm orange = armed/confirm, deliberately ≠ the gold selection
			# colour so the two states never read the same.
			buy.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
		else:
			buy.text = "BUY · %d ★" % int(node.point_cost)
		buy.pressed.connect(func(): _on_buy_pressed(_insp_content_id))
		_inspector_vbox.add_child(buy)
		if not check.ok:
			_inspector_vbox.add_child(_make_kv_label("Why not", String(check.reason)))


# ── Actions ───────────────────────────────────────────────────────────

func _on_buy_pressed(node_id: String) -> void:
	# Two-step confirm — BUY spends skill points, so it needs a deliberate
	# second tap (same node) to commit. First tap arms + relabels; a 3s
	# timer auto-disarms so a stray arm doesn't linger. Mirrors the
	# EquipmentScreen sell-arm pattern.
	if _buy_armed_id == node_id:
		_buy_armed_id = ""
		_on_buy(node_id)
		return
	_buy_armed_id = node_id
	_refresh_inspector()
	var node_ref: String = node_id
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(func() -> void:
		if _buy_armed_id == node_ref:
			_buy_armed_id = ""
			_refresh_inspector()
	)


func _on_buy(node_id: String) -> void:
	if not MetaProgression.purchase_node(_hero_id, node_id):
		return
	Toast.show_message("Purchased: %s" % node_id)
	# Auto-select MOD on purchase (mirrors HeroSkillTreeScreen._on_buy).
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree != null:
		var node: Resource = tree.find_node(node_id)
		if node != null and int(node.kind) == _HeroSkillNodeDataScript.Kind.MOD:
			var mod: Resource = node.ability
			if mod != null and "mod_id" in mod:
				LoadoutState.set_chosen_mod(_hero_id, String(node.target_id), String(mod.mod_id))
	_persist()


func _on_pick_mod(skill_id: String, mod_id: String) -> void:
	if LoadoutState.set_chosen_mod(_hero_id, skill_id, mod_id):
		_persist()


func _equip_active(slot_idx: int, skill_id: String) -> void:
	if slot_idx < 0:
		return
	if LoadoutState.set_equipped_skill(_hero_id, slot_idx, skill_id):
		# Update inspector content so the slot shows the new skill immediately.
		_insp_content_id = skill_id
		_persist()


func _equip_passive(slot_idx: int, passive_id: String) -> void:
	if slot_idx < 0:
		return
	if LoadoutState.set_equipped_passive(_hero_id, slot_idx, passive_id):
		_insp_content_id = passive_id
		_persist()


# Item-parity equip UI for the skill-map node panel. ACTIVE_RANK / PASSIVE_RANK
# nodes whose skill/passive is learned get a slot dropdown + Equip button right
# here — no scrolling skill list. Other kinds (MOD / SLOT_UNLOCK / CAPSTONE)
# aren't equippable so this is a no-op for them.
func _add_equip_controls(node: Resource, kind: int) -> void:
	var content_id: String = String(node.target_id)
	var is_passive: bool
	var equippable: bool
	var slot_cap: int
	var equipped: Array[String]
	if kind == _HeroSkillNodeDataScript.Kind.ACTIVE_RANK:
		is_passive = false
		equippable = content_id in LoadoutState.get_unlocked_skill_ids(_hero_id)
		slot_cap = LoadoutState.get_active_slot_cap(_hero_id)
		equipped = LoadoutState.get_equipped_skills(_hero_id)
	elif kind == _HeroSkillNodeDataScript.Kind.PASSIVE_RANK:
		is_passive = true
		equippable = MetaProgression.get_purchased_passive_rank(_hero_id, content_id) > 0
		slot_cap = LoadoutState.get_passive_slot_cap(_hero_id)
		equipped = LoadoutState.get_equipped_passives(_hero_id)
	else:
		return
	if not equippable:
		_inspector_vbox.add_child(_make_kv_label("Equip", "Learn this first"))
		return

	var cur_slot: int = equipped.find(content_id)
	_inspector_vbox.add_child(_make_kv_label("Equipped",
		("Slot %d" % (cur_slot + 1)) if cur_slot >= 0 else "Not equipped"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.custom_minimum_size = Vector2(140, 44)
	for s in slot_cap:
		var occ: String = equipped[s] if s < equipped.size() else ""
		var tag: String = ""
		if occ == content_id:
			tag = "  ✓"
		elif occ != "":
			tag = "  (in use)"
		picker.add_item("Slot %d%s" % [s + 1, tag], s)
	# Default: current slot → else first empty → else slot 1.
	var sel: int = cur_slot
	if sel < 0:
		sel = equipped.find("")
	if sel < 0 or sel >= slot_cap:
		sel = 0
	picker.select(sel)
	row.add_child(picker)

	var eq_btn := Button.new()
	eq_btn.focus_mode = Control.FOCUS_NONE
	eq_btn.custom_minimum_size = Vector2(0, 44)
	eq_btn.text = "Move here" if cur_slot >= 0 else "Equip"
	eq_btn.pressed.connect(func() -> void:
		_equip_from_node(is_passive, picker.get_selected_id(), content_id))
	row.add_child(eq_btn)
	_inspector_vbox.add_child(row)

	if cur_slot >= 0:
		var un := Button.new()
		un.focus_mode = Control.FOCUS_NONE
		un.custom_minimum_size = Vector2(0, 44)
		un.text = "Unequip"
		un.pressed.connect(func() -> void:
			_equip_from_node(is_passive, cur_slot, ""))
		_inspector_vbox.add_child(un)


# Equip/unequip from the node panel WITHOUT clobbering _insp_content_id
# (unlike _equip_active/_equip_passive, which the slot inspector still uses).
# Keeps the inspector pinned to the same node so it re-renders in place.
func _equip_from_node(is_passive: bool, slot_idx: int, content_id: String) -> void:
	if slot_idx < 0:
		return
	var ok: bool
	if is_passive:
		ok = LoadoutState.set_equipped_passive(_hero_id, slot_idx, content_id)
	else:
		ok = LoadoutState.set_equipped_skill(_hero_id, slot_idx, content_id)
	if ok:
		_persist()
		_refresh_all()


func _persist() -> void:
	if has_node("/root/SaveManager"):
		SaveManager.save_game()


func _on_reset_pressed() -> void:
	if LoadoutState.reset_active_loadout_to_default(_hero_id):
		Toast.show_message("Loadout reset to default")
		_persist()


# ── Helpers ───────────────────────────────────────────────────────────

func _make_stylebox(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _make_icon_h1_row(pictogram: String, title: String) -> Control:
	# Pictogram on the left (48px), H1 label to its right. When pictogram is
	# "" (no glyph authored), falls back to a plain H1 label so the layout
	# doesn't sprout an empty icon column.
	if pictogram == "":
		return _make_h1_label(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var icon := _SkillGlyphIcon.new()
	icon.setup(pictogram, 48.0, _TEXT, _PANEL_BG)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var lbl := _make_h1_label(title)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lbl)
	return h


func _make_h1_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", _TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


func _make_h2_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_body_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _MUTED)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


func _make_kv_label(key: String, value: String) -> Label:
	var lbl := Label.new()
	lbl.text = "%s: %s" % [key, value]
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _TEXT)
	return lbl


func _kind_glyph(kind: int) -> String:
	match kind:
		_HeroSkillNodeDataScript.Kind.ACTIVE_RANK:  return "⚡ "
		_HeroSkillNodeDataScript.Kind.PASSIVE_RANK: return "✦ "
		_HeroSkillNodeDataScript.Kind.MOD:          return "✚ "
		_HeroSkillNodeDataScript.Kind.SLOT_UNLOCK:  return "🔓 "
		_HeroSkillNodeDataScript.Kind.CAPSTONE:     return "★ "
		_:                                          return ""


func _kind_label(kind: int) -> String:
	match kind:
		_HeroSkillNodeDataScript.Kind.ACTIVE_RANK:  return "ACTIVE RANK"
		_HeroSkillNodeDataScript.Kind.PASSIVE_RANK: return "PASSIVE RANK"
		_HeroSkillNodeDataScript.Kind.MOD:          return "MOD"
		_HeroSkillNodeDataScript.Kind.SLOT_UNLOCK:  return "SLOT UNLOCK"
		_HeroSkillNodeDataScript.Kind.CAPSTONE:     return "CAPSTONE"
		_:                                          return "NODE"


func _kind_color(kind: int) -> Color:
	match kind:
		_HeroSkillNodeDataScript.Kind.ACTIVE_RANK:  return _ACTIVE_ACCENT
		_HeroSkillNodeDataScript.Kind.PASSIVE_RANK: return _PASSIVE_ACCENT
		_HeroSkillNodeDataScript.Kind.MOD:          return _GOLD
		_:                                          return _MUTED


func _skill_name(hero_data: Resource, skill_id: String) -> String:
	if hero_data == null or not ("skills" in hero_data):
		return skill_id
	for skill in hero_data.skills:
		if skill != null and String(skill.skill_id) == skill_id:
			if "skill_name" in skill and String(skill.skill_name) != "":
				return String(skill.skill_name)
			return skill_id
	return skill_id


func _skill_pictogram(hero_data: Resource, skill_id: String) -> String:
	if skill_id == "":
		return ""
	var skill: Resource = _find_skill(hero_data, skill_id)
	if skill != null and "pictogram" in skill:
		return String(skill.pictogram)
	return ""


func _find_skill(hero_data: Resource, skill_id: String) -> Resource:
	if hero_data == null or not ("skills" in hero_data):
		return null
	for skill in hero_data.skills:
		if skill != null and String(skill.skill_id) == skill_id:
			return skill
	return null


func _describe_skill(skill: Resource) -> String:
	if skill == null:
		return ""
	if "description" in skill and String(skill.description) != "":
		return String(skill.description)
	# Build a short stats line as fallback.
	var parts: PackedStringArray = []
	if "cooldown" in skill:
		parts.append("CD %.1fs" % float(skill.cooldown))
	if "damage" in skill and float(skill.damage) > 0.0:
		parts.append("Dmg %d" % int(skill.damage))
	if "aoe_radius" in skill and float(skill.aoe_radius) > 0.0:
		parts.append("AoE %d" % int(skill.aoe_radius))
	return ", ".join(parts)


func _describe_passive(tree: Resource, passive_id: String) -> String:
	if tree == null:
		return ""
	var parts: PackedStringArray = []
	for n in tree.nodes:
		if n == null:
			continue
		if int(n.kind) != _HeroSkillNodeDataScript.Kind.PASSIVE_RANK:
			continue
		if String(n.target_id) != passive_id:
			continue
		var purchased: int = MetaProgression.get_purchased_rank(_hero_id, String(n.node_id))
		var prefix: String = ("✓ " if purchased >= int(n.rank) else "• ")
		parts.append("%sR%d: %s" % [prefix, int(n.rank), String(n.description)])
	return "\n".join(parts)


func _mod_short_name(mod_id: String) -> String:
	if mod_id == "":
		return ""
	var mod: Resource = LoadoutState.find_skill_mod(_hero_id, mod_id)
	if mod != null and "mod_name" in mod and String(mod.mod_name) != "":
		return String(mod.mod_name)
	return mod_id
