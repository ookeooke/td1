extends Control

# Phase 1 — embedded inside HeroesHub. Shows the selected hero's skill tree:
# unspent points, passive nodes with BUY buttons, equipped passive slots, and
# an "owned" row of passives the player can tap to equip.
#
# MVP (Phase 1B): passive nodes only. ACTIVE_RANK / MOD / SLOT_UNLOCK /
# CAPSTONE rendering lands in Phase 2 / Phase 3. The screen registers with
# EventBus signals so a purchase or equip refresh comes through without a
# re-open.

const _PANEL_BG: Color = Color(0.13, 0.17, 0.23, 1.0)
const _PANEL_BORDER: Color = Color(0.25, 0.30, 0.40, 1.0)
const _GOLD: Color = Color(1.0, 0.85, 0.4, 1.0)
const _MUTED: Color = Color(0.55, 0.62, 0.74, 1.0)
const _TEXT: Color = Color(0.92, 0.95, 1.0, 1.0)
const _OK_BG: Color = Color(0.18, 0.28, 0.20, 1.0)
const _OK_BORDER: Color = Color(0.45, 0.85, 0.55, 1.0)
const _DENY_BG: Color = Color(0.20, 0.16, 0.18, 1.0)
const _DENY_BORDER: Color = Color(0.65, 0.30, 0.40, 1.0)

# Preloaded so the Kind enum is accessible regardless of class_name registry
# load order (mirrors the autoload-side pattern in MetaProgression / LoadoutState).
const _HeroSkillNodeDataScript = preload("res://heroes/HeroSkillNodeData.gd")

var _hero_id: String = ""
var _points_label: Label = null
var _equipped_row: HBoxContainer = null
var _available_row: HBoxContainer = null
var _nodes_vbox: VBoxContainer = null


func _ready() -> void:
	_hero_id = LoadoutState.selected_hero_id
	_build_layout()
	_refresh_all()
	EventBus.hero_node_purchased.connect(_on_state_changed)
	EventBus.hero_skill_points_changed.connect(_on_state_changed)
	EventBus.hero_passive_equipped.connect(_on_state_changed)
	EventBus.hero_skill_mod_chosen.connect(_on_state_changed)
	EventBus.hero_leveled_up.connect(_on_state_changed)


func _exit_tree() -> void:
	if EventBus.hero_node_purchased.is_connected(_on_state_changed):
		EventBus.hero_node_purchased.disconnect(_on_state_changed)
	if EventBus.hero_skill_points_changed.is_connected(_on_state_changed):
		EventBus.hero_skill_points_changed.disconnect(_on_state_changed)
	if EventBus.hero_passive_equipped.is_connected(_on_state_changed):
		EventBus.hero_passive_equipped.disconnect(_on_state_changed)
	if EventBus.hero_skill_mod_chosen.is_connected(_on_state_changed):
		EventBus.hero_skill_mod_chosen.disconnect(_on_state_changed)
	if EventBus.hero_leveled_up.is_connected(_on_state_changed):
		EventBus.hero_leveled_up.disconnect(_on_state_changed)


# All EventBus payloads are arg-variable; collapse them into one refresh.
func _on_state_changed(_a = null, _b = null, _c = null) -> void:
	_refresh_all()


func _build_layout() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	root.add_child(v)

	# ── Header: points available ─────────────────────────────────────────
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 22)
	_points_label.add_theme_color_override("font_color", _GOLD)
	v.add_child(_points_label)

	# ── Equipped passive slots row ───────────────────────────────────────
	var equipped_label := Label.new()
	equipped_label.text = "EQUIPPED PASSIVES"
	equipped_label.add_theme_font_size_override("font_size", 14)
	equipped_label.add_theme_color_override("font_color", _MUTED)
	v.add_child(equipped_label)

	_equipped_row = HBoxContainer.new()
	_equipped_row.add_theme_constant_override("separation", 12)
	v.add_child(_equipped_row)

	# ── Owned passives (tap to equip to next slot) ───────────────────────
	var owned_label := Label.new()
	owned_label.text = "OWNED PASSIVES — tap to equip"
	owned_label.add_theme_font_size_override("font_size", 14)
	owned_label.add_theme_color_override("font_color", _MUTED)
	v.add_child(owned_label)

	_available_row = HBoxContainer.new()
	_available_row.add_theme_constant_override("separation", 12)
	v.add_child(_available_row)

	# ── Node list (one row per passive node) ─────────────────────────────
	var nodes_label := Label.new()
	nodes_label.text = "SKILL TREE"
	nodes_label.add_theme_font_size_override("font_size", 14)
	nodes_label.add_theme_color_override("font_color", _MUTED)
	v.add_child(nodes_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_nodes_vbox = VBoxContainer.new()
	_nodes_vbox.add_theme_constant_override("separation", 8)
	_nodes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_nodes_vbox)


func _refresh_all() -> void:
	_hero_id = LoadoutState.selected_hero_id  # re-pull in case hub switched heroes
	_refresh_points()
	_refresh_equipped()
	_refresh_available()
	_refresh_nodes()


func _refresh_points() -> void:
	if _points_label == null:
		return
	var lvl: int = MetaProgression.get_hero_level(_hero_id)
	var pts: int = MetaProgression.get_skill_points(_hero_id)
	_points_label.text = "Lv %d    Points: %d ★" % [lvl, pts]


func _refresh_equipped() -> void:
	if _equipped_row == null:
		return
	for child in _equipped_row.get_children():
		child.queue_free()
	var cap: int = LoadoutState.get_passive_slot_cap(_hero_id)
	var equipped: Array[String] = LoadoutState.get_equipped_passives(_hero_id)
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	for i in cap:
		var pid: String = equipped[i] if i < equipped.size() else ""
		var slot := _make_passive_card(pid, true, i, tree)
		_equipped_row.add_child(slot)


func _refresh_available() -> void:
	if _available_row == null:
		return
	for child in _available_row.get_children():
		child.queue_free()
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree == null:
		return
	var equipped: Array[String] = LoadoutState.get_equipped_passives(_hero_id)
	for pid in tree.get_passive_ids():
		var rank_purchased: int = MetaProgression.get_purchased_passive_rank(_hero_id, pid)
		if rank_purchased <= 0:
			continue
		if pid in equipped:
			continue
		_available_row.add_child(_make_passive_card(pid, false, -1, tree))
	if _available_row.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "(buy a passive below to enable equipping)"
		empty.add_theme_color_override("font_color", _MUTED)
		_available_row.add_child(empty)


func _refresh_nodes() -> void:
	if _nodes_vbox == null:
		return
	for child in _nodes_vbox.get_children():
		child.queue_free()
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
		_nodes_vbox.add_child(_make_node_row(node))


# ── Card builders ───────────────────────────────────────────────────────

func _make_passive_card(passive_id: String, is_slot: bool, slot_idx: int, tree: Resource) -> Control:
	# A 120x88 card. If `is_slot=true` and `passive_id=""`, renders as an
	# empty slot. Tap behavior depends on the role:
	#   - equipped-slot card with a passive_id → unequip
	#   - empty equipped-slot → no-op
	#   - available-row card → equip into first empty slot
	var card := Button.new()
	card.custom_minimum_size = Vector2(120, 88)
	card.focus_mode = Control.FOCUS_NONE
	var bg_color: Color = _PANEL_BG if passive_id != "" else Color(0.10, 0.13, 0.18, 1.0)
	var sb := _make_stylebox(bg_color, _PANEL_BORDER)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", _make_stylebox(bg_color.lightened(0.05), _GOLD))
	card.add_theme_stylebox_override("pressed", sb)
	card.add_theme_stylebox_override("disabled", sb)

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

	# Wire interaction.
	if is_slot:
		if passive_id != "":
			card.pressed.connect(func(): _unequip(slot_idx))
	else:
		card.pressed.connect(func(): _equip_to_next_slot(passive_id))

	return card


func _make_node_row(node: Resource) -> Control:
	# One row per node: name, description, rank, status (BUY/PURCHASED/locked).
	# PanelContainer's stylebox carries the padding; inner VBoxContainers add
	# only separation (margin_* constants don't apply to BoxContainer).
	var row := PanelContainer.new()
	var row_sb := _make_stylebox(_PANEL_BG, _PANEL_BORDER)
	row_sb.content_margin_left = 12
	row_sb.content_margin_right = 12
	row_sb.content_margin_top = 8
	row_sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", row_sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	# Left column — name + description.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	h.add_child(left)

	var title := Label.new()
	var rank_str: String = ""
	if int(node.rank) > 0:
		rank_str = " — Rank %d" % int(node.rank)
	title.text = "%s%s" % [String(node.node_name), rank_str]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _TEXT)
	left.add_child(title)

	var desc := Label.new()
	desc.text = String(node.description)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", _MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(desc)

	# Right column — buy button or status.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(160, 0)
	h.add_child(right)

	var node_id: String = String(node.node_id)
	var purchased_rank: int = MetaProgression.get_purchased_rank(_hero_id, node_id)
	var is_mod: bool = int(node.kind) == _HeroSkillNodeDataScript.Kind.MOD
	if purchased_rank >= int(node.rank):
		# Owned. MOD nodes get a toggle here so the player can switch among
		# multiple owned mods for the same skill — non-MOD nodes just show
		# a static PURCHASED badge.
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

	return row


# MOD-node post-purchase widget: ACTIVE label if currently chosen for that
# skill, otherwise a [Pick] button that selects this mod (deselecting any
# previously-active mod for the same skill — set_chosen_mod is single-slot).
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
	pick.pressed.connect(func(): LoadoutState.set_chosen_mod(_hero_id, skill_id, mod_id))
	return pick


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


# ── Actions ─────────────────────────────────────────────────────────────

func _on_buy(node_id: String) -> void:
	if not MetaProgression.purchase_node(_hero_id, node_id):
		return
	Toast.show_message("Purchased: %s" % node_id)
	# Auto-select MOD on purchase so the player gets immediate effect; they
	# can still toggle to a different owned mod via [Pick]. No auto-select for
	# PASSIVE_RANK / ACTIVE_RANK / SLOT_UNLOCK / CAPSTONE.
	var tree: Resource = ContentRegistry.find_skill_tree(_hero_id)
	if tree == null:
		return
	var node: Resource = tree.find_node(node_id)
	if node == null:
		return
	if int(node.kind) != _HeroSkillNodeDataScript.Kind.MOD:
		return
	var mod: Resource = node.ability
	if mod == null or not ("mod_id" in mod):
		return
	LoadoutState.set_chosen_mod(_hero_id, String(node.target_id), String(mod.mod_id))


func _equip_to_next_slot(passive_id: String) -> void:
	var cap: int = LoadoutState.get_passive_slot_cap(_hero_id)
	var equipped: Array[String] = LoadoutState.get_equipped_passives(_hero_id)
	for i in cap:
		if equipped[i] == "":
			LoadoutState.set_equipped_passive(_hero_id, i, passive_id)
			return
	# No empty slot — replace the last slot. UX rationale: the player
	# explicitly tapped an owned passive while equipped is full, so they
	# want to swap something. Last-slot replacement is the cheapest signal-
	# preserving choice; a fuller "drag to a specific slot" pattern lands
	# when drag support arrives.
	LoadoutState.set_equipped_passive(_hero_id, cap - 1, passive_id)


func _unequip(slot_idx: int) -> void:
	LoadoutState.set_equipped_passive(_hero_id, slot_idx, "")
