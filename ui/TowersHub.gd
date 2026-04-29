class_name TowersHub
extends Control

# Phase C — Towers hub with two tabs:
#   - Loadout : embeds LoadoutPickerScreen.tscn (ring + pool + reset)
#   - Upgrades: embeds UpgradeTree.tscn (star-spend tree)
#
# Same embed strategy as HeroesHub (Phase B): hide each screen's TopBar +
# Background and pull body offsets up so the content fits cleanly under the
# tab strip. The standalone scenes remain untouched and continue to work
# for direct-navigation paths.

# Tab indices — exported for outside callers (e.g. WorldMap stars-counter
# shortcut which sets pending_tab = TAB_UPGRADES before navigating here).
const TAB_LOADOUT: int = 0
const TAB_UPGRADES: int = 1

# One-shot hint for which tab to focus on the next instantiation. Cleared
# inside _ready after applying so it doesn't bleed into subsequent visits.
static var pending_tab: int = -1

@onready var back_button: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var loadout_tab: Control = %Loadout
@onready var upgrades_tab: Control = %Upgrades


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_embed_screen(loadout_tab, "res://ui/LoadoutPickerScreen.tscn")
	_embed_screen(upgrades_tab, "res://ui/UpgradeTree.tscn")
	if pending_tab >= 0:
		tab_container.current_tab = pending_tab
		pending_tab = -1


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _embed_screen(tab: Control, scene_path: String) -> void:
	# Instance the screen scene as a child of the tab. Hide chrome the hub
	# already provides (TopBar, Background) and pull body content up so it
	# sits below the tab strip without dead space.
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("[TowersHub] failed to load %s" % scene_path)
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

	# LoadoutPickerScreen: HintLabel at offset_top=90, RingAnchor anchored at
	# 35% vertical, PoolTitle at offset_top=620, PoolScroll at offset_top=670.
	# Pull HintLabel up; the rest is anchor-relative or absolute-bottom and
	# scales fine inside the tab content area.
	var hint: Control = screen.get_node_or_null("HintLabel")
	if hint != null:
		hint.offset_top = 8
		hint.offset_bottom = 44

	# UpgradeTree: StarsLabel inside TopBar (which we hid). The tree relies on
	# the StarsLabel being visible — re-host it as a sibling above the scroll
	# container so the player still sees their star budget.
	var stars: Control = screen.get_node_or_null("TopBar/StarsLabel")
	if stars != null and top_bar != null:
		top_bar.remove_child(stars)
		screen.add_child(stars)
		stars.set_anchors_preset(Control.PRESET_TOP_WIDE)
		stars.offset_left = 16
		stars.offset_top = 8
		stars.offset_right = -16
		stars.offset_bottom = 36

	# UpgradeTree ScrollContainer at offset_top=112 — pull up so the list
	# starts right under the relocated StarsLabel.
	var scroll: Control = screen.get_node_or_null("ScrollContainer")
	if scroll != null:
		scroll.offset_top = 48
