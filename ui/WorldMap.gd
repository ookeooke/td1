extends Control

# World Map — Kingdom Rush-style level selector. Renders a procedural
# parchment map (WorldMapView) with one banner-on-post marker per level.
# Tapping an unlocked marker routes to LoadoutScreen, which hosts the
# level info + mode picker. Locked markers toast a hint and stay put.
# Data-driven via res://ui/world_map/level_list.tres — add levels there.

# Populated in _ready() from ContentRegistry. Pushed into WorldMapView
# in _build_level_entries.
var _levels: Array[Resource] = []

@onready var back_button: Button = %BackButton
@onready var world_map_view: WorldMapView = %WorldMapView
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var heroes_button: Button = %HeroesButton
@onready var towers_button: Button = %TowersButton
@onready var codex_button: Button = %CodexButton
@onready var shop_button: Button = %ShopButton
@onready var stars_button: Button = %StarsButton
@onready var meta_gold_button: Button = %MetaGoldButton
@onready var settings_button: Button = %SettingsButton
@onready var test_range_button: Button = %TestRangeButton
@onready var balance_report_button: Button = %BalanceReportButton
@onready var balance_sliders_button: Button = %BalanceSlidersButton
@onready var level_audit_button: Button = %LevelAuditButton
@onready var supply_demand_button: Button = %SupplyDemandButton
@onready var coverage_button: Button = %CoverageButton
@onready var unlock_all_button: Button = %UnlockAllButton


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
		balance_sliders_button.pressed.connect(_on_balance_sliders)
		level_audit_button.pressed.connect(_on_level_audit)
		supply_demand_button.pressed.connect(_on_supply_demand)
		coverage_button.pressed.connect(_on_coverage)
		unlock_all_button.pressed.connect(_on_unlock_all)
	else:
		test_range_button.visible = false
		balance_report_button.visible = false
		balance_sliders_button.visible = false
		level_audit_button.visible = false
		supply_demand_button.visible = false
		coverage_button.visible = false
		unlock_all_button.visible = false
	_refresh_stars_label()
	_refresh_meta_gold_label()
	_refresh_heroes_button_dot()
	_load_levels()
	_build_level_entries()


# Single source of truth: ContentRegistry.levels (loaded at boot from
# level_list.tres). Adding a level is one .tres edit, no consumer changes.
func _load_levels() -> void:
	_levels = ContentRegistry.levels


func _refresh_stars_label() -> void:
	# KR-style top-bar resource counter — shows available (unspent) stars.
	stars_button.text = "★ %d" % MetaProgression.get_available_stars()


func _refresh_meta_gold_label() -> void:
	# Persistent inventory-sell currency (distinct from per-run gold).
	meta_gold_button.text = "💰 %d" % MetaProgression.meta_gold


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
		if LoadoutState.has_unequipped_skills(h.hero_id):
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


func _on_balance_sliders() -> void:
	# Debug-only — runtime overrides for HP / armor / speed / damage / gold
	# / PPT. Persisted to user://debug_balance.json. See balance/BALANCE.md.
	SceneManager.goto("res://balance/debug/BalanceSliders.tscn")


func _on_level_audit() -> void:
	# Debug-only — cross-level hardness + PPT-drift table. Reads authored
	# level_list.tres + per-level wave_list .tres files.
	SceneManager.goto("res://balance/audit/LevelAudit.tscn")


func _on_supply_demand() -> void:
	# Debug-only — Supply vs Demand model. See balance/BALANCE.md.
	SceneManager.goto("res://balance/audit/SupplyDemandReport.tscn")


func _on_coverage() -> void:
	# Debug-only — Coverage Report (map-aware balance). Greedy-spend
	# simulator + path heatmap + gold-usefulness curve. See the audit
	# screen and balance/audit/CoverageAnalyzer.gd.
	SceneManager.goto("res://balance/audit/CoverageReport.tscn")


func _on_unlock_all() -> void:
	# Debug-only — flips levels_unlocked[id] = true for every level in
	# ContentRegistry. Persists via SaveManager. Campaign-mode only;
	# Heroic/Iron still gate on stars / heroic_complete. Refreshes cards.
	for lvl in ContentRegistry.levels:
		if lvl == null or not ("level_id" in lvl) or lvl.level_id == "":
			continue
		MetaProgression.levels_unlocked[lvl.level_id] = true
	SaveManager.save_game()
	_refresh_level_states()
	# Re-run the auto-scroll so the view jumps to the now-highest unlocked
	# level (otherwise the camera stays parked over L1 and the player can't
	# tell that L4 became reachable).
	_on_markers_built()
	print("[WorldMap] unlock-all (debug) — %d levels unlocked" % ContentRegistry.levels.size())


func _build_level_entries() -> void:
	# Renders levels onto the WorldMap. Markers are children of WorldMapView,
	# rebuilt from ContentRegistry. Tapping an unlocked marker routes to
	# LoadoutScreen; locked taps toast a hint.
	if world_map_view == null:
		return
	if not world_map_view.marker_pressed.is_connected(_on_marker_pressed):
		world_map_view.marker_pressed.connect(_on_marker_pressed)
	if not world_map_view.markers_built.is_connected(_on_markers_built):
		world_map_view.markers_built.connect(_on_markers_built)
	if not world_map_view.celebration_finished.is_connected(_on_celebration_finished):
		world_map_view.celebration_finished.connect(_on_celebration_finished)
	world_map_view.set_levels(_levels)
	# Replay handoff: SaveManager._try_unlock_next_level set this when the
	# previous run cleared a level. Kick the road-reveal + marker-pop in the
	# same frame as set_levels — play_celebration overrides marker.visible on
	# the just-unlocked marker before any frame renders, so no flash.
	var pending: String = MetaProgression.pending_unlock_celebration_id
	if pending != "":
		world_map_view.play_celebration(pending)


# Cleared after the animation actually completes so a force-quit mid-celebration
# replays the show on next entry. SaveManager.save_game persists immediately.
func _on_celebration_finished() -> void:
	MetaProgression.pending_unlock_celebration_id = ""
	SaveManager.save_game()


# Auto-scrolls the ScrollContainer to the highest-unlock_order level the
# player has unlocked, so opening the WorldMap on a phone shows the player's
# "next" content without manual panning. Deferred one frame because
# ScrollContainer needs to finish layout before ensure_control_visible
# computes against the right content size.
func _on_markers_built() -> void:
	var lid: String = MetaProgression.get_highest_unlocked_level_id()
	if lid == "":
		return
	var marker: Control = world_map_view.get_marker_for_level(lid)
	if marker == null:
		return
	await get_tree().process_frame
	if scroll_container != null and is_instance_valid(marker):
		scroll_container.ensure_control_visible(marker)


# Refresh marker visuals (locked/star state) without rebuilding the marker
# tree. Called by debug Unlock All; safe to call any time.
func _refresh_level_states() -> void:
	if world_map_view != null:
		world_map_view.refresh_states()


func _on_marker_pressed(level_id: String) -> void:
	# Locked levels stay on the WorldMap with a hint toast — same UX as the
	# pre-rework card list. Unlocked taps route directly to LoadoutScreen,
	# which now hosts the level info + mode picker that used to live in the
	# Phase 1 detail modal.
	var is_unlocked: bool = MetaProgression.levels_unlocked.get(level_id, false)
	if not is_unlocked:
		Toast.show_message("Clear prior levels to unlock")
		return
	RunState.current_level_id = level_id
	# Default to Campaign so a stale mode from a prior level can't silently
	# downgrade or pre-select a locked option. Player picks Heroic/Iron/Endless
	# on the LoadoutScreen pill row.
	RunState.current_mode = "campaign"
	SceneManager.goto("res://ui/LoadoutScreen.tscn")

