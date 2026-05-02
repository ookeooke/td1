extends Control

# World Map — level select screen. Shows one panel per level with name,
# stars earned, and locked/unlocked state. Tap unlocked → gameplay.
# Data-driven via `levels: Array[LevelNodeData]` set in the .tscn.
# Stars + unlock state read from GameState (populated by SaveManager later).

@export var levels: Array[Resource] = []

# Debug-only: maps level_id → its WaveList .tres path so the WorldMap card
# can compute and display the level's hardness score. Hardcoded for now —
# at ~5 levels we'd promote `waves_path: String` onto LevelNodeData and
# read it from there.
const _LEVEL_WAVES: Dictionary = {
	"level_1": "res://levels/level1_waves.tres",
}

@onready var back_button: Button = %BackButton
@onready var level_list_container: VBoxContainer = %LevelList
@onready var heroes_button: Button = %HeroesButton
@onready var towers_button: Button = %TowersButton
@onready var codex_button: Button = %CodexButton
@onready var shop_button: Button = %ShopButton
@onready var stars_button: Button = %StarsButton
@onready var meta_gold_button: Button = %MetaGoldButton
@onready var settings_button: Button = %SettingsButton
@onready var test_range_button: Button = %TestRangeButton
@onready var balance_report_button: Button = %BalanceReportButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	heroes_button.pressed.connect(_on_heroes)
	towers_button.pressed.connect(_on_towers)
	codex_button.pressed.connect(_on_codex)
	shop_button.pressed.connect(_on_shop)
	stars_button.pressed.connect(_on_stars)
	meta_gold_button.pressed.connect(_on_meta_gold)
	settings_button.pressed.connect(_on_settings)
	# Test Range — debug-only sandbox for measuring tower DPS in isolation.
	# Hidden in shipped builds via OS.is_debug_build(); the scene file itself
	# is also stripped via export_presets.cfg exclude_filter ("balance/*").
	if OS.is_debug_build():
		test_range_button.pressed.connect(_on_test_range)
		balance_report_button.pressed.connect(_on_balance_report)
	else:
		test_range_button.visible = false
		balance_report_button.visible = false
	_refresh_stars_label()
	_refresh_meta_gold_label()
	_refresh_heroes_button_dot()
	_build_level_entries()


func _refresh_stars_label() -> void:
	# KR-style top-bar resource counter — shows available (unspent) stars.
	stars_button.text = "★ %d" % GameState.get_available_stars()


func _refresh_meta_gold_label() -> void:
	# Persistent inventory-sell currency (distinct from per-run gold).
	meta_gold_button.text = "💰 %d" % GameState.meta_gold


# Phase 48 — red dot in the corner of the Heroes button when ANY unlocked
# hero has at least one unlocked-but-unequipped skill. Mirrors the unread-
# badge convention from mobile games and tells the player at a glance that
# there's a loadout decision waiting in Heroes → Skills. Recalculated on
# WorldMap entry; HeroesHub redraws cards on its own when it mutates state.
func _refresh_heroes_button_dot() -> void:
	if heroes_button == null:
		return
	var dot: Control = heroes_button.get_node_or_null("UnequippedDot")
	var any_pending: bool = false
	for h in ContentRegistry.heroes:
		if h == null:
			continue
		if not UnlockManager.is_hero_unlocked(h.hero_id):
			continue
		if GameState.has_unequipped_skills(h.hero_id):
			any_pending = true
			break
	if not any_pending:
		if dot != null:
			dot.visible = false
		return
	if dot == null:
		dot = ColorRect.new()
		dot.name = "UnequippedDot"
		dot.color = ThemeColors.ACCENT_RED
		dot.custom_minimum_size = Vector2(16, 16)
		dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -20
		dot.offset_top = 4
		dot.offset_right = -4
		dot.offset_bottom = 20
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heroes_button.add_child(dot)
	dot.visible = true


func _on_back() -> void:
	SceneManager.goto("res://ui/MainMenu.tscn")


func _on_heroes() -> void:
	SceneManager.goto("res://ui/HeroesHub.tscn")


func _on_towers() -> void:
	SceneManager.goto("res://ui/TowersHub.tscn")


func _on_codex() -> void:
	SceneManager.goto("res://ui/CodexHub.tscn")


func _on_shop() -> void:
	SceneManager.goto("res://ui/ShopScreen.tscn")


func _on_stars() -> void:
	# Stars-counter shortcut: jump straight into Towers hub > Upgrades tab.
	# Hub reads this hint on _ready and clears it.
	TowersHub.pending_tab = TowersHub.TAB_UPGRADES
	SceneManager.goto("res://ui/TowersHub.tscn")


func _on_meta_gold() -> void:
	# Meta-gold has no spending destination yet (Town Buy phase will add one).
	# For now, route to the Equipment tab where the player can sell items —
	# that's where the counter visibly grows, and it teaches the loop.
	SceneManager.goto("res://ui/HeroesHub.tscn")


func _on_settings() -> void:
	SceneManager.goto("res://ui/OptionsScreen.tscn")


func _on_test_range() -> void:
	# Debug-only sandbox. SceneManager.goto uses a string path so no static
	# dependency from this script to balance/ — the folder is stripped
	# at export time and this code path is gated by OS.is_debug_build() above.
	SceneManager.goto("res://balance/test_range/TestRange.tscn")


func _on_balance_report() -> void:
	# Debug-only — reads user://run_stats.json and shows aggregates.
	# Same gating + string-path pattern as the Test Range button.
	SceneManager.goto("res://balance/report/BalanceReport.tscn")


func _build_level_entries() -> void:
	for child in level_list_container.get_children():
		child.queue_free()
	for data in levels:
		if data == null:
			continue
		var panel: PanelContainer = _make_level_panel(data)
		level_list_container.add_child(panel)


func _make_level_panel(data: Resource) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 110)
	var hbox := HBoxContainer.new()
	hbox.set("theme_override_constants/separation", 16)
	panel.add_child(hbox)

	# Left side: level info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.set("theme_override_font_sizes/font_size", 24)
	info_vbox.add_child(name_label)

	# Composite stars: campaign (0–3) + heroic (+1) + iron (+1) = max 5.
	var total_stars: int = GameState.calculate_total_stars_for_level(data.level_id)
	var star_text: String = "★".repeat(total_stars) + "☆".repeat(5 - total_stars)
	var stars_label := Label.new()
	stars_label.text = star_text
	stars_label.set("theme_override_font_sizes/font_size", 20)
	info_vbox.add_child(stars_label)

	# Debug-only: per-level hardness score from BalanceCalculator. Players
	# don't see this in shipped builds — it would read as gibberish without
	# context. The whole balance/ folder is stripped at export anyway.
	if OS.is_debug_build():
		var hardness_label := Label.new()
		hardness_label.text = "Hardness: %s" % _format_hardness(data.level_id)
		hardness_label.set("theme_override_font_sizes/font_size", 12)
		hardness_label.modulate = Color(1.0, 0.8, 0.4)
		info_vbox.add_child(hardness_label)

	# Phase 48 — best time + endless high score. Only show if the player
	# has posted a run (otherwise the row would read "Best: —  Endless: —"
	# which adds clutter with zero information).
	var metrics_line: String = _format_level_metrics(data.level_id)
	if metrics_line != "":
		var metrics_label := Label.new()
		metrics_label.text = metrics_line
		metrics_label.set("theme_override_font_sizes/font_size", 14)
		metrics_label.modulate = Color(0.7, 0.78, 0.9)
		info_vbox.add_child(metrics_label)

	# Right side: mode pill row (Campaign / Heroic / Iron / Endless) or lock.
	# Phase F — Endless promoted to a sibling pill alongside the other three
	# modes, replacing the prior Play + Endless button pair. Mode picker
	# happens here on the level card; LoadoutScreen no longer needs to ask.
	var is_unlocked: bool = GameState.levels_unlocked.get(data.level_id, false)
	if is_unlocked:
		var pill_row := HBoxContainer.new()
		pill_row.set("theme_override_constants/separation", 8)
		hbox.add_child(pill_row)
		_add_mode_pill(pill_row, data, "campaign")
		_add_mode_pill(pill_row, data, "heroic")
		_add_mode_pill(pill_row, data, "iron")
		_add_mode_pill(pill_row, data, "endless")
	else:
		var lock_btn := Button.new()
		lock_btn.text = "Locked"
		lock_btn.custom_minimum_size = Vector2(100, 94)
		lock_btn.set("theme_override_font_sizes/font_size", 20)
		lock_btn.modulate = Color(0.7, 0.7, 0.7)
		lock_btn.pressed.connect(func(): Toast.show_message("Clear prior levels to unlock"))
		hbox.add_child(lock_btn)

	return panel


func _add_mode_pill(row: HBoxContainer, data: Resource, mode: String) -> void:
	# Mirrors LoadoutScreen._refresh_mode_buttons logic so the pills here
	# show the same gating + status text the LoadoutScreen would have. Tap
	# launches gameplay (via LoadoutScreen) directly.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 64)
	btn.set("theme_override_font_sizes/font_size", 14)
	var lid: String = data.level_id
	match mode:
		"campaign":
			var campaign_stars: int = GameState.level_stars.get(lid, 0)
			var stars_str: String = "★".repeat(campaign_stars) + "☆".repeat(3 - campaign_stars)
			btn.text = "Campaign\n%s" % stars_str
			btn.disabled = false
		"heroic":
			var heroic_done: bool = GameState.heroic_complete.get(lid, false)
			var heroic_unlocked: bool = GameState.is_heroic_unlocked(lid)
			if heroic_done:
				btn.text = "Heroic\nDone ✓"
				btn.disabled = false
			elif heroic_unlocked:
				btn.text = "Heroic\nReady"
				btn.disabled = false
			else:
				btn.text = "Heroic\nNeed 3★"
				btn.disabled = true
		"iron":
			var iron_done: bool = GameState.iron_complete.get(lid, false)
			var iron_unlocked: bool = GameState.is_iron_unlocked(lid)
			if iron_done:
				btn.text = "Iron\nDone ✓"
				btn.disabled = false
			elif iron_unlocked:
				btn.text = "Iron\nReady"
				btn.disabled = false
			else:
				btn.text = "Iron\nNeed Heroic"
				btn.disabled = true
		"endless":
			var best: int = GameState.get_endless_best_score(lid)
			# Score, not a wave count — "Best %d" matches LoadoutScreen and
			# LeaderboardScreen wording; "W%d" was misleading.
			if best > 0:
				btn.text = "Endless\nBest %d" % best
			else:
				btn.text = "Endless\n—"
			btn.disabled = false
	if not btn.disabled:
		btn.pressed.connect(_on_mode_pill_pressed.bind(data, mode))
	row.add_child(btn)


func _on_mode_pill_pressed(data: Resource, mode: String) -> void:
	GameState.current_level_id = data.level_id
	GameState.current_mode = mode
	# LoadoutScreen reads current_mode to pre-select the matching pill in its
	# own mode row (which becomes redundant after this phase but stays as a
	# pre-battle confirmation). Endless flow: LoadoutScreen hides the
	# Campaign/Heroic/Iron row when mode == "endless" — pre-existing logic.
	SceneManager.goto("res://ui/LoadoutScreen.tscn")


func _format_level_metrics(level_id: String) -> String:
	var parts: PackedStringArray = []
	var best: float = GameState.get_best_time(level_id)
	if best > 0.0:
		parts.append("Best: %s" % _format_seconds(best))
	var endless: int = GameState.get_endless_best_score(level_id)
	if endless > 0:
		parts.append("Endless: %d" % endless)
	return "   ".join(parts)


func _format_seconds(s: float) -> String:
	if s < 60.0:
		return "%.1fs" % s
	var minutes: int = int(s / 60.0)
	var rem: float = s - float(minutes * 60)
	return "%d:%05.2f" % [minutes, rem]


# Debug-only — looks up the level's WaveList and returns its hardness score
# as a plain integer string. Returns "—" if the level isn't in _LEVEL_WAVES,
# the file is missing, or BalanceCalculator was deleted with the balance/
# folder. Caller is already gated by OS.is_debug_build().
func _format_hardness(level_id: String) -> String:
	var path: String = _LEVEL_WAVES.get(level_id, "")
	if path == "":
		return "—"
	var wl: WaveList = load(path)
	if wl == null:
		return "—"
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return "—"
	return "%d" % int(bc.score_level(wl, GameState.STARTING_GOLD))


