extends CanvasLayer

# Phase 12 + Phase 26: end-of-run overlay.
# Victory: shows stars + Continue button → WorldMap (records best stars).
# Defeat: shows wave reached + Restart button → reloads gameplay scene.
# Uses SceneManager for all transitions instead of reload_current_scene.

@onready var title_label: Label = %TitleLabel
@onready var summary_label: Label = %SummaryLabel
@onready var continue_button: Button = %ContinueButton
@onready var restart_button: Button = %RestartButton

var _shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)


func _on_game_over() -> void:
	if _shown:
		return
	if GameState.current_mode == "endless":
		var score: int = GameState.compute_endless_score()
		var is_best: bool = score > GameState.endless_best_score
		if is_best:
			GameState.endless_best_score = score
		GameState.submit_endless_score("Player", score)
		EventBus.endless_score_updated.emit(score)
		SaveManager.save_game()
		continue_button.text = "World Map"
		continue_button.visible = true
		restart_button.text = "Restart"
		restart_button.visible = true
		var best_text: String = " NEW BEST!" if is_best else " (Best: %d)" % GameState.endless_best_score
		_show("Game Over", "Wave reached: %d\nScore: %d%s%s" % [GameState.wave_number, score, best_text, _build_damage_breakdown()])
		return
	# Campaign/Heroic/Iron defeat — give the player BOTH actions: retry the
	# level or bail out to the WorldMap. Previously the Continue button was
	# hidden on defeat, leaving restart as the only path and making the
	# screen feel like a dead end.
	continue_button.text = "World Map"
	continue_button.visible = true
	restart_button.text = "Restart"
	restart_button.visible = true
	var mode_label: String = GameState.current_mode.capitalize() if GameState.current_mode != "" else "Campaign"
	_show("Defeat", "You lost all your lives.\nMode: %s  \u2022  Wave reached: %d%s" % [
		mode_label, GameState.wave_number, _build_damage_breakdown()
	])


func _on_all_waves_completed() -> void:
	if _shown:
		return
	if GameState.lives <= 0:
		return
	var stars: int = GameState.calculate_stars()
	GameState.stars_earned = stars
	# Build the summary based on mode.
	var summary: String = ""
	match GameState.current_mode:
		"campaign":
			var star_text: String = "★".repeat(stars) + "☆".repeat(3 - stars)
			summary = "Campaign cleared!\n%s\nLives: %d  Gold: %d" % [star_text, GameState.lives, GameState.gold]
		"heroic":
			summary = "Heroic cleared!\n+1 bonus star\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
		"iron":
			summary = "Iron cleared!\n+1 bonus star — flawless!\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
		_:
			summary = "All waves cleared.\nLives: %d  Gold: %d" % [GameState.lives, GameState.gold]
	summary += _build_damage_breakdown()
	continue_button.text = "Continue"
	continue_button.visible = true
	restart_button.text = "Restart"
	restart_button.visible = false
	_show("Victory!", summary)
	EventBus.level_completed.emit(GameState.current_level_id, stars, GameState.current_mode)


# Phase 46: per-run damage attribution. Top-5 towers (by total damage dealt,
# surviving OR sold), plus hero and soldier totals. Hidden when no damage
# was recorded (e.g. an immediate defeat).
const _TOWER_LEADERBOARD_LIMIT: int = 5


func _build_damage_breakdown() -> String:
	var tower_entries: Array = GameState.round_damage_towers.values()
	var hero: float = GameState.round_damage_hero
	var sold: float = GameState.round_damage_soldiers
	var spells: float = GameState.round_damage_spells
	if tower_entries.is_empty() and hero <= 0.0 and sold <= 0.0 and spells <= 0.0:
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
	if spells > 0.0:
		lines.append("Spells: %s" % _fmt(spells))
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


func _on_continue_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	if GameState.current_mode != "endless":
		GameState.record_stars()
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	WaveManager.stop()
	GameState.reset_for_level()
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.lives_changed.emit(GameState.lives)
	SceneManager.goto("res://main/Main.tscn")
