extends CanvasLayer

# Tactical-pause live run dashboard. Opens via EventBus.run_stats_panel_requested.
# Reads RunState + WaveManager + ContentRegistry for live values; refreshes
# damage attribution per-frame (no per-tick signal). Closes on Dim tap, X,
# or game resume.
#
# Damage breakdown mirrors GameOverScreen._build_damage_breakdown — same
# data source (RunState.round_damage_*), trimmed display: top-5 towers +
# Hero + Soldiers when nonzero.

const _TOWER_LEADERBOARD_LIMIT: int = 5

@onready var root: Control = %Root
@onready var dim: ColorRect = %Dim
@onready var close_button: Button = %CloseButton
@onready var context_label: Label = %ContextLabel
@onready var wave_label: Label = %WaveLabel
@onready var resources_label: RichTextLabel = %ResourcesLabel
@onready var damage_label: RichTextLabel = %DamageLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(_hide)
	dim.gui_input.connect(_on_dim_input)
	EventBus.run_stats_panel_requested.connect(_on_requested)
	EventBus.pause_state_changed.connect(_on_pause_state_changed)
	EventBus.gold_changed.connect(_on_resources_changed)
	EventBus.lives_changed.connect(_on_resources_changed)
	EventBus.wave_started.connect(_on_wave_started)


func _on_requested() -> void:
	root.visible = true
	_refresh_static()
	_refresh_resources()
	_refresh_damage()


func _on_pause_state_changed(paused: bool) -> void:
	if not paused:
		_hide()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_hide()


func _hide() -> void:
	root.visible = false


func _on_resources_changed(_v: int) -> void:
	if root.visible:
		_refresh_resources()


func _on_wave_started(_n: int, _paths: Array) -> void:
	if root.visible:
		_refresh_static()


# Damage attribution has no per-tick signal — poll while panel is open.
# Trivial cost: ~5 dict reads/frame, only when the player chose to look.
func _process(_delta: float) -> void:
	if not root.visible:
		return
	_refresh_damage()


func _refresh_static() -> void:
	var mode: String = String(RunState.current_mode).capitalize() if RunState.current_mode != "" else "Campaign"
	var level_name: String = _resolve_level_name(RunState.current_level_id)
	var elapsed: float = _resolve_elapsed()
	context_label.text = "%s · %s · %s elapsed" % [mode, level_name, _fmt_time(elapsed)]
	var total: int = WaveManager.wave_count()
	var cur: int = max(RunState.wave_number, 0)
	if total > 0:
		wave_label.text = "Wave %d / %d" % [cur, total]
	else:
		wave_label.text = "Wave %d" % cur


func _refresh_resources() -> void:
	resources_label.text = "[b]Gold[/b]  %d     [b]Lives[/b]  %d     [b]Score[/b]  %d" % [
		RunState.gold, RunState.lives, RunState.score,
	]


func _refresh_damage() -> void:
	var tower_entries: Array = RunState.round_damage_towers.values()
	var hero: float = RunState.round_damage_hero
	var sold: float = RunState.round_damage_soldiers
	if tower_entries.is_empty() and hero <= 0.0 and sold <= 0.0:
		damage_label.text = "[i]no damage dealt yet[/i]"
		return
	tower_entries.sort_custom(func(a, b): return float(a.get("total", 0.0)) > float(b.get("total", 0.0)))
	var lines: PackedStringArray = PackedStringArray()
	var shown: int = mini(_TOWER_LEADERBOARD_LIMIT, tower_entries.size())
	for i in range(shown):
		var e: Dictionary = tower_entries[i]
		var display: String = String(e.get("name", ""))
		if display.is_empty():
			display = "Tower"
		lines.append("  • %s — %s" % [display, _fmt_num(float(e.get("total", 0.0)))])
	if hero > 0.0:
		lines.append("  • Hero — %s" % _fmt_num(hero))
	if sold > 0.0:
		lines.append("  • Soldiers — %s" % _fmt_num(sold))
	damage_label.text = "\n".join(lines)


func _resolve_level_name(level_id: String) -> String:
	if level_id == "":
		return "—"
	var entry: Resource = ContentRegistry.find_level(level_id)
	if entry == null or not ("display_name" in entry):
		return level_id
	return String(entry.display_name)


# Pulls the level-elapsed clock from Main if it exposes a getter. Falls
# back to 0 — the panel still loads, just without a timer. Decoupled from
# Main so a future scene that lacks the helper doesn't crash this panel.
func _resolve_elapsed() -> float:
	var main: Node = get_tree().current_scene
	if main != null and main.has_method("get_level_elapsed"):
		return float(main.get_level_elapsed())
	return 0.0


func _fmt_time(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func _fmt_num(n: float) -> String:
	if n >= 1000.0:
		return "%.1fk" % (n / 1000.0)
	return "%d" % int(round(n))
