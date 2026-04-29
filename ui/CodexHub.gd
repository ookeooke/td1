extends Control

# Phase D — Codex hub with two tabs:
#   - Bestiary : embeds EncyclopediaScreen.tscn (its own inner tab row stays —
#                Enemies / Towers / Heroes / Items)
#   - Records  : embeds LeaderboardScreen.tscn (endless mode top scores)
#
# Same embed pattern as Phases B + C: hide each screen's TopBar + Background,
# pull body offsets up. Achievements tab arrives in a future phase when that
# system lands.

@onready var back_button: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var bestiary_tab: Control = %Bestiary
@onready var records_tab: Control = %Records


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_embed_screen(bestiary_tab, "res://ui/EncyclopediaScreen.tscn")
	_embed_screen(records_tab, "res://ui/LeaderboardScreen.tscn")


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _embed_screen(tab: Control, scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("[CodexHub] failed to load %s" % scene_path)
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

	# EncyclopediaScreen: TabRow (inner Enemies/Towers/Heroes/Items) at
	# offset_top=88, ScrollContainer at offset_top=160. Pull both up so the
	# inner tab row sits right under the outer Codex tab strip.
	var inner_tabs: Control = screen.get_node_or_null("TabRow")
	if inner_tabs != null:
		inner_tabs.offset_top = 8
		inner_tabs.offset_bottom = 68

	# LeaderboardScreen: ScrollContainer at offset_top=112 — pull up.
	# (Encyclopedia ScrollContainer also pulled to the same offset since it
	# sits below the inner tab row at ~68.)
	var scroll: Control = screen.get_node_or_null("ScrollContainer")
	if scroll != null:
		# Encyclopedia needs more headroom for the inner tab row; Leaderboard
		# has no inner tab row.
		if inner_tabs != null:
			scroll.offset_top = 80
		else:
			scroll.offset_top = 8
