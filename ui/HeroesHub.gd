extends Control

# Phase B — Heroes hub with five tabs:
#   - Loadout   : hero picker (built inline below)
#   - Equipment : embeds EquipmentScreen.tscn (TopBar/Background hidden)
#   - Stats     : "coming soon" stub
#   - Skills    : "coming soon" stub
#   - Talents   : embeds TalentScreen.tscn (TopBar/Background hidden)
#
# Equipment + Talents are embedded rather than re-implemented — this avoids
# duplicating ~500 lines of inventory/talent logic and keeps the standalone
# screens working for any direct-navigation paths that still exist. The
# embed strategy: hide the screen's top bar + colored background and offset
# its body up so it aligns with the tab content area (TabContainer renders
# the tab strip at its top, and embedded children fill the area below it).
#
# Stats + Skills tabs are stubs — Phase plan reserves them for the future
# per-hero attribute and skill-tree systems.

@onready var back_button: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var loadout_tab: Control = %Loadout
@onready var equipment_tab: Control = %Equipment
@onready var stats_tab: Control = %Stats
@onready var skills_tab: Control = %Skills
@onready var talents_tab: Control = %Talents

# Loadout-tab UI built in script.
var _hero_label: Label
var _switch_button: Button


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build_loadout_tab()
	_embed_screen(equipment_tab, "res://ui/EquipmentScreen.tscn")
	_build_coming_soon_tab(stats_tab, "Stats", "Strength · Stamina · Dexterity\n(future system)")
	_build_coming_soon_tab(skills_tab, "Skills", "Per-hero skill upgrades\n(future system)")
	_embed_screen(talents_tab, "res://ui/TalentScreen.tscn")


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


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
	# Mirror LoadoutScreen._refresh_hero_info — pick a valid unlocked hero,
	# fall back through the roster if the saved selection is locked.
	var selected: Resource = null
	for h in heroes:
		if h.hero_id == GameState.selected_hero_id and UnlockManager.is_hero_unlocked(h.hero_id):
			selected = h
			break
	if selected == null:
		for h in heroes:
			if UnlockManager.is_hero_unlocked(h.hero_id):
				selected = h
				break
	if selected == null:
		selected = heroes[0]
	GameState.selected_hero_id = selected.hero_id

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
	# Disable switch when only one unlocked hero exists.
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
		if heroes[i].hero_id == GameState.selected_hero_id:
			current_idx = i
			break
	# Cycle to the next UNLOCKED hero (skip locked ones, like LoadoutScreen).
	for offset in range(1, heroes.size()):
		var try_idx: int = (current_idx + offset) % heroes.size()
		var candidate: Resource = heroes[try_idx]
		if UnlockManager.is_hero_unlocked(candidate.hero_id):
			GameState.selected_hero_id = candidate.hero_id
			# Notify embedded Equipment + Talents tabs so they refresh to the
			# new hero's data. Uses the existing (previously unused) EventBus
			# signal — listeners in EquipmentScreen + TalentScreen pick this up.
			EventBus.hero_selected.emit(candidate.hero_id)
			_refresh_loadout()
			return


# --- Embed pattern for existing standalone screens --------------------------

func _embed_screen(tab: Control, scene_path: String) -> void:
	# Instance the screen scene as a child of the tab. Hide the screen's own
	# TopBar (back/title) and Background — the hub provides those — and reset
	# the body offset so content fills the tab area cleanly.
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

	# Equipment screen: HeroLabel lives inside the (now hidden) TopBar — lift
	# it out so the player can still see which hero's gear they're viewing.
	# Same pattern Phase C used for UpgradeTree's StarsLabel.
	var hero_label: Control = screen.get_node_or_null("TopBar/HeroLabel")
	if hero_label != null and top_bar != null:
		top_bar.remove_child(hero_label)
		screen.add_child(hero_label)
		hero_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		hero_label.offset_left = 16
		hero_label.offset_top = 8
		hero_label.offset_right = -16
		hero_label.offset_bottom = 36
		hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Equipment screen: Body at offset_top=96 — pull up so content starts
	# below the relocated HeroLabel (or right below the tab strip if none).
	# Phase 49 — bumped from 48→56 because the new 144px slot row sits closer
	# to the tab strip. With the redundant LeftTitle / StatsTitle / DetailsTitle
	# also hidden below, the content reads cleanly below "Knight — Lv N".
	var body: Control = screen.get_node_or_null("Body")
	if body != null:
		body.offset_top = 56 if hero_label != null else 8

	# Phase 49 — hide section headers that duplicate context already provided
	# by HeroesHub's tab strip ("Equipment" tab) and the relocated HeroLabel.
	# Standalone EquipmentScreen still shows them. Each path is defensive —
	# only hides when the node is actually present.
	for header_path in ["Body/LeftPanel/LeftTitle", "Body/LeftPanel/StatsTitle", "Body/LeftPanel/DetailsTitle"]:
		var header: Control = screen.get_node_or_null(header_path)
		if header != null:
			header.visible = false

	# Talent screen: StarsLabel at offset_top=88 + ScrollContainer at 128 —
	# pull both up so the empty header space disappears.
	var stars: Control = screen.get_node_or_null("StarsLabel")
	if stars != null:
		stars.offset_top = 8
		stars.offset_bottom = 36
	var scroll: Control = screen.get_node_or_null("ScrollContainer")
	if scroll != null:
		scroll.offset_top = 48


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
