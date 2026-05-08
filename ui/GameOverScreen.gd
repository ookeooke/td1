extends CanvasLayer

# Phase 12 + Phase 26: end-of-run overlay.
# Victory: shows stars + Continue button → WorldMap (records best stars).
# Defeat: shows wave reached + Restart button → reloads gameplay scene.
# Uses SceneManager for all transitions instead of reload_current_scene.

@onready var title_label: Label = %TitleLabel
@onready var summary_label: Label = %SummaryLabel
@onready var continue_button: Button = %ContinueButton
@onready var restart_button: Button = %RestartButton
# Phase 56b: debug-only Balance Verdict block. Hidden in release builds.
@onready var verdict_panel: PanelContainer = %VerdictPanel
@onready var metrics_grid: GridContainer = %MetricsGrid
@onready var flags_label: RichTextLabel = %FlagsLabel
@onready var replay_button: Button = %ReplayButton
@onready var sliders_button: Button = %SlidersButton

var _shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	replay_button.pressed.connect(_on_replay_pressed)
	sliders_button.pressed.connect(_on_sliders_pressed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)


func _on_game_over() -> void:
	if _shown:
		return
	if RunState.current_mode == "endless":
		var score: int = RunState.compute_endless_score()
		var is_best: bool = score > MetaProgression.endless_best_score
		if is_best:
			MetaProgression.endless_best_score = score
		# Phase 48 — also track per-level endless score so each map has its
		# own endless high score on the WorldMap card.
		MetaProgression.try_record_endless_score(RunState.current_level_id, score)
		MetaProgression.submit_endless_score("Player", score, RunState.wave_number)
		EventBus.endless_score_updated.emit(score)
		SaveManager.save_game()
		continue_button.text = "World Map"
		continue_button.visible = true
		restart_button.text = "Restart"
		restart_button.visible = true
		var best_text: String = " NEW BEST!" if is_best else " (Best: %d)" % MetaProgression.endless_best_score
		_show("Game Over", "Wave reached: %d\nScore: %d%s%s" % [RunState.wave_number, score, best_text, _build_damage_breakdown()])
		return
	# Campaign/Heroic/Iron defeat — give the player BOTH actions: retry the
	# level or bail out to the WorldMap. Previously the Continue button was
	# hidden on defeat, leaving restart as the only path and making the
	# screen feel like a dead end.
	continue_button.text = "World Map"
	continue_button.visible = true
	restart_button.text = "Restart"
	restart_button.visible = true
	var mode_label: String = RunState.current_mode.capitalize() if RunState.current_mode != "" else "Campaign"
	_show("Defeat", "You lost all your lives.\nMode: %s  •  Wave reached: %d%s" % [
		mode_label, RunState.wave_number, _build_damage_breakdown()
	])


func _on_all_waves_completed() -> void:
	# Diagnostic — narrows down whether the victory screen is failing to RUN
	# (handler not invoked / bailed at guard) vs failing to RENDER (handler
	# ran but the panel never visually appeared). Cheap, debug-only.
	print("[GameOverScreen] all_waves received  _shown=%s  lives=%d  mode=%s" % [
		_shown, RunState.lives, RunState.current_mode,
	])
	if _shown:
		print("[GameOverScreen] bail — _shown already true")
		return
	if RunState.lives <= 0:
		print("[GameOverScreen] bail — lives <= 0 (defeat path)")
		return
	var stars: int = RunState.calculate_stars()
	RunState.stars_earned = stars
	# Build the summary based on mode.
	var summary: String = ""
	match RunState.current_mode:
		"campaign":
			var star_text: String = "★".repeat(stars) + "☆".repeat(3 - stars)
			summary = "Campaign cleared!\n%s\nLives: %d  Gold: %d" % [star_text, RunState.lives, RunState.gold]
		"heroic":
			summary = "Heroic cleared!\n+1 bonus star\nLives: %d  Gold: %d" % [RunState.lives, RunState.gold]
		"iron":
			summary = "Iron cleared!\n+1 bonus star — flawless!\nLives: %d  Gold: %d" % [RunState.lives, RunState.gold]
		_:
			summary = "All waves cleared.\nLives: %d  Gold: %d" % [RunState.lives, RunState.gold]
	summary += _build_damage_breakdown()
	continue_button.text = "Continue"
	continue_button.visible = true
	restart_button.text = "Restart"
	restart_button.visible = false
	_show("Victory!", summary)
	EventBus.level_completed.emit(RunState.current_level_id, stars, RunState.current_mode)


# Phase 46: per-run damage attribution. Top-5 towers (by total damage dealt,
# surviving OR sold), plus hero and soldier totals. Hidden when no damage
# was recorded (e.g. an immediate defeat).
const _TOWER_LEADERBOARD_LIMIT: int = 5


func _build_damage_breakdown() -> String:
	var tower_entries: Array = RunState.round_damage_towers.values()
	var hero: float = RunState.round_damage_hero
	var sold: float = RunState.round_damage_soldiers
	if tower_entries.is_empty() and hero <= 0.0 and sold <= 0.0:
		return ""
	tower_entries.sort_custom(func(a, b): return float(a.get("total", 0.0)) > float(b.get("total", 0.0)))
	var lines: PackedStringArray = ["", "— Damage dealt —"]
	var shown: int = mini(_TOWER_LEADERBOARD_LIMIT, tower_entries.size())
	for i in range(shown):
		var e: Dictionary = tower_entries[i]
		var display: String = String(e.get("name", ""))
		if display.is_empty():
			display = "Tower"
		lines.append("%s: %s" % [display, _fmt(float(e.get("total", 0.0)))])
	if hero > 0.0:
		lines.append("Hero: %s" % _fmt(hero))
	if sold > 0.0:
		lines.append("Soldiers: %s" % _fmt(sold))
	return "\n" + "\n".join(lines)


func _fmt(n: float) -> String:
	var i: int = int(round(n))
	if i < 1000:
		return str(i)
	# Thousands separator for readability on long runs.
	var s: String = str(i)
	var out: String = ""
	var count: int = 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		count += 1
		if count % 3 == 0 and k > 0:
			out = "," + out
	return out


func _show(title: String, summary: String) -> void:
	_shown = true
	title_label.text = title
	summary_label.text = summary
	# Mode-coded title tint so the card reads at a glance: green on victory,
	# warm red on defeat/game-over, theme default otherwise.
	var t: String = title.to_lower()
	if t.begins_with("victory"):
		title_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	elif t.begins_with("defeat") or t.begins_with("game over"):
		title_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	else:
		title_label.remove_theme_color_override("font_color")
	visible = true
	get_tree().paused = true
	# Verdict panel populates AFTER RunStats has finalized the just-finished
	# run (RunStats appends on level_completed / game_over signals; signal
	# handler order isn't guaranteed). Deferred read of history[-1] avoids
	# the race entirely.
	if OS.is_debug_build():
		call_deferred("_populate_verdict")


func _populate_verdict() -> void:
	if not OS.is_debug_build():
		return
	print("[GameOverScreen/Verdict] populate begin")
	var history: Array = RunStats.get_history()
	if history.is_empty():
		print("[GameOverScreen/Verdict] bail — RunStats history empty")
		verdict_panel.visible = false
		return
	var record: Dictionary = history[history.size() - 1]
	if not (record is Dictionary):
		print("[GameOverScreen/Verdict] bail — last history record not a Dictionary")
		verdict_panel.visible = false
		return
	var level_id: String = String(record.get("level_id", ""))
	var mode: String = String(record.get("mode", ""))
	var run_id: String = String(record.get("run_id", ""))
	var level_data: Resource = _find_level_data(level_id)
	var wave_list: Resource = null
	if level_data != null and "wave_list_path" in level_data and String(level_data.wave_list_path) != "":
		wave_list = load(level_data.wave_list_path)
	var BV: GDScript = load("res://balance/BalanceVerdict.gd")
	if BV == null:
		print("[GameOverScreen/Verdict] bail — BalanceVerdict.gd failed to load")
		verdict_panel.visible = false
		return
	print("[GameOverScreen/Verdict] level=%s mode=%s lvl_data=%s wave_list=%s" % [
		level_id, mode,
		"ok" if level_data != null else "null",
		"ok" if wave_list != null else "null",
	])
	var prior: Array = BV.recent_comparable(history, level_id, mode, run_id)
	var verdict: Dictionary = BV.compute(record, level_data, wave_list, prior)
	print("[GameOverScreen/Verdict] compute returned metrics=%d flags=%d" % [
		(verdict.get("metrics", []) as Array).size(),
		(verdict.get("flags", []) as Array).size(),
	])
	_render_metrics_grid(verdict.get("metrics", []))
	_render_flags(verdict.get("flags", []), int(verdict.get("history_n", 0)))
	verdict_panel.visible = true
	print("[GameOverScreen/Verdict] populate complete; panel visible")


func _render_metrics_grid(metrics: Array) -> void:
	for c in metrics_grid.get_children():
		c.queue_free()
	for m in metrics:
		var label_lbl := Label.new()
		label_lbl.text = String(m.get("label", ""))
		label_lbl.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
		var value_lbl := Label.new()
		value_lbl.text = String(m.get("value_str", ""))
		var delta_lbl := Label.new()
		delta_lbl.text = String(m.get("delta_str", ""))
		delta_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		metrics_grid.add_child(label_lbl)
		metrics_grid.add_child(value_lbl)
		metrics_grid.add_child(delta_lbl)


func _render_flags(flags: Array, history_n: int) -> void:
	if flags.is_empty():
		var note: String = ""
		if history_n < 2:
			note = "[i][color=#888](Δ vs avg appears after 2+ prior runs of this level + mode)[/color][/i]"
		flags_label.text = "[color=#9bd]No verdict flags raised.[/color]\n" + note
		return
	var lines: PackedStringArray = []
	for f in flags:
		var sev: String = String(f.get("severity", "info"))
		var hex: String = "#f88" if sev == "warn" else "#fc8"
		lines.append("[color=%s]• %s[/color]" % [hex, String(f.get("label", ""))])
	if history_n < 2:
		lines.append("[i][color=#888](Δ vs avg appears after 2+ prior runs of this level + mode)[/color][/i]")
	flags_label.text = "\n".join(lines)


func _find_level_data(level_id: String) -> Resource:
	if ContentRegistry == null or level_id == "":
		return null
	var levels: Array = ContentRegistry.get("levels")
	if not (levels is Array):
		return null
	for ld in levels:
		if ld == null:
			continue
		if "level_id" in ld and String(ld.level_id) == level_id:
			return ld
	return null


func _on_replay_pressed() -> void:
	# Same path as RestartButton — keeps overrides active for back-to-back A/B
	# testing of slider tweaks.
	_on_restart_pressed()


func _on_sliders_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	SceneManager.goto("res://balance/debug/BalanceSliders.tscn")


func _on_continue_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	if RunState.current_mode != "endless":
		MetaProgression.record_stars(RunState.current_mode, RunState.current_level_id, RunState.stars_earned)
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	RunState.reset_for_level()
	EventBus.gold_changed.emit(RunState.gold)
	EventBus.lives_changed.emit(RunState.lives)
	SceneManager.goto("res://main/Main.tscn")
