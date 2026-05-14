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
		buy.pressed.connect(func(): _on_buy(node_id))
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
		_inspector_vbox.add_child(_make_body_label("Empty slot. Tap a skill below to equip."))
	# Owned-but-unequipped actives list — tap to equip into this slot.
	_inspector_vbox.add_child(_make_h2_label("AVAILABLE", _MUTED))
	var unlocked: Array[String] = LoadoutState.get_unlocked_skill_ids(_hero_id)
	var equipped: Array[String] = LoadoutState.get_equipped_skills(_hero_id)
	var any_added: bool = false
	for sid in unlocked:
		if sid == _insp_content_id:
			continue
		var label: String = _skill_name(hero_data, sid)
		var btn := Button.new()
		btn.text = ("✓ " if sid in equipped else "+ ") + label
		btn.pressed.connect(func(): _equip_active(_insp_slot_index, sid))
		_inspector_vbox.add_child(btn)
		any_added = true
	if not any_added:
		_inspector_vbox.add_child(_make_body_label("(no other skills unlocked yet)"))


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
		_inspector_vbox.add_child(_make_body_label("Empty slot. Tap an owned passive below to equip."))
	# Owned passives — tap to equip into this slot.
	_inspector_vbox.add_child(_make_h2_label("OWNED", _MUTED))
	if tree == null:
		return
	var equipped: Array[String] = LoadoutState.get_equipped_passives(_hero_id)
	var any_added: bool = false
	for pid in tree.get_passive_ids():
		if pid == _insp_content_id:
			continue
		var rank: int = MetaProgression.get_purchased_passive_rank(_hero_id, pid)
		if rank <= 0:
			continue
		var label: String = tree.get_passive_name(pid)
		var btn := Button.new()
		btn.text = ("✓ " if pid in equipped else "+ ") + label
		btn.pressed.connect(func(): _equip_passive(_insp_slot_index, pid))
		_inspector_vbox.add_child(btn)
		any_added = true
	if not any_added:
		_inspector_vbox.add_child(_make_body_label("(buy a passive in the tree to enable equipping)"))


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

	if purchased_rank < int(node.rank):
		var check: Dictionary = MetaProgression.can_purchase_node(_hero_id, _insp_content_id)
		var buy := Button.new()
		buy.text = "BUY · %d ★" % int(node.point_cost)
		buy.disabled = not check.ok
		buy.pressed.connect(func(): _on_buy(_insp_content_id))
		_inspector_vbox.add_child(buy)
		if not check.ok:
			_inspector_vbox.add_child(_make_kv_label("Why not", String(check.reason)))


# ── Actions ───────────────────────────────────────────────────────────

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
