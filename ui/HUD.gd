extends CanvasLayer

# In-level HUD. Gold / lives / wave / threat are HudChip widgets that pulse
# on value changes (mirrors the existing purchase-deny feedback pattern).
# Wave starts also fade a centered "Wave N" banner across the screen.

@onready var gold_chip: PanelContainer = %GoldChip
@onready var lives_chip: PanelContainer = %LivesChip
@onready var wave_chip: PanelContainer = %WaveChip
@onready var threat_chip: PanelContainer = %ThreatChip
@onready var wave_banner: Label = %WaveBanner

@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton

# Rolling 5-second window of incoming enemy HP. Each entry: [spawn_time_ms,
# max_health]. Old entries pruned in _process. Sum displayed on the threat
# chip with a tint that escalates by band.
const SPAWN_RATE_WINDOW_SEC: float = 5.0
var _spawn_rate_events: Array = []

# Fast-forward: cycles through 1x → 2x → 3x → 1x. Kingdom Rush uses 1x/2x;
# 3x is a power-user option for long endless runs. Engine.time_scale affects
# everything (physics, timers, tweens) which is exactly what TD fast-forward
# needs — towers shoot faster, enemies walk faster, waves progress faster.
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 3.0]
var _speed_idx: int = 0

# Cached last-known values to detect deltas for pulses. RunState is the
# source of truth; we just remember what we already showed.
var _last_gold: int = -1
var _last_lives: int = -1

var _banner_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(func(): EventBus.pause_requested.emit())
	speed_button.pressed.connect(_on_speed_pressed)
	_refresh_speed_label()
	_refresh_pause_label(false)
	_on_gold_changed(RunState.gold)
	_on_lives_changed(RunState.lives)
	_refresh_wave()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.lives_changed.connect(_on_lives_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.purchase_denied.connect(_on_purchase_denied)
	# Pause button glyph flips between ⏸ ("| |") while running and ▶ when
	# paused, so the same button always reads as "what pressing me will do".
	EventBus.pause_state_changed.connect(_refresh_pause_label)
	# Rolling 5s incoming-HP window updated on each spawn; pruned every frame
	# in _process. Cleared on wave_started so each wave's window is fresh.
	EventBus.enemy_spawned.connect(_on_enemy_spawned_for_rate)
	# Banner starts fully transparent.
	wave_banner.modulate = Color(1, 1, 1, 0)


func _on_gold_changed(amount: int) -> void:
	gold_chip.set_value("%d" % amount)
	if _last_gold < 0:
		_last_gold = amount
		return
	var delta: int = amount - _last_gold
	_last_gold = amount
	if delta > 0:
		gold_chip.pulse_pop()
		gold_chip.pulse_modulate(Color(1.4, 1.2, 0.6, 1.0), 0.06, 0.34)
	elif delta < 0:
		gold_chip.pulse_modulate(Color(0.78, 0.78, 0.78, 1.0), 0.05, 0.18)


func _on_lives_changed(amount: int) -> void:
	lives_chip.set_value("%d" % amount)
	if _last_lives < 0:
		_last_lives = amount
		return
	var delta: int = amount - _last_lives
	_last_lives = amount
	if delta < 0:
		lives_chip.pulse_pop(1.22, 0.08, 0.22)
		lives_chip.pulse_modulate(Color(1.0, 0.32, 0.32, 1.0), 0.06, 0.34)


# Deny feedback — flash + pulse on the gold chip so the player's eye is
# yanked from the rejected slot to the *reason*. Mirrors the original
# purchase_denied behavior on the old GoldLabel.
func _on_purchase_denied(_reason: String) -> void:
	gold_chip.pulse_modulate(Color(1.0, 0.32, 0.32, 1.0), 0.06, 0.34)
	gold_chip.pulse_pop()


func _on_wave_started(wave_number: int, _path_ids: Array) -> void:
	var total: int = WaveManager.wave_count()
	if total > 0:
		wave_chip.set_value("%d/%d" % [wave_number, total])
	else:
		wave_chip.set_value("%d" % wave_number)  # endless — no total
	wave_chip.pulse_pop(1.2, 0.08, 0.22)
	_show_wave_banner(wave_number)


func _on_all_waves_completed() -> void:
	wave_chip.set_value("WIN")
	wave_chip.pulse_pop(1.3, 0.1, 0.25)


func _on_speed_pressed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEED_OPTIONS.size()
	Engine.time_scale = SPEED_OPTIONS[_speed_idx]
	_refresh_speed_label()


func _refresh_speed_label() -> void:
	var spd: float = SPEED_OPTIONS[_speed_idx]
	speed_button.text = "%dx" % int(spd)


func _refresh_pause_label(paused: bool) -> void:
	pause_button.text = "▶" if paused else "| |"


func _refresh_wave() -> void:
	var total: int = WaveManager.wave_count()
	if total > 0 and RunState.wave_number > 0:
		wave_chip.set_value("%d/%d" % [RunState.wave_number, total])
	else:
		wave_chip.set_value("--")


# --- Wave banner ---

func _show_wave_banner(wave_number: int) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	wave_banner.text = "Wave %d" % wave_number
	wave_banner.modulate = Color(1, 1, 1, 0)
	_banner_tween = create_tween()
	_banner_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_banner_tween.tween_property(wave_banner, "modulate", Color(1, 1, 1, 1), 0.3)
	_banner_tween.tween_interval(0.5)
	_banner_tween.tween_property(wave_banner, "modulate", Color(1, 1, 1, 0), 0.6)


func _on_enemy_spawned_for_rate(enemy: Node, _path_id: String) -> void:
	# Push (now_ms, max_health) into the rolling window. Old entries are
	# pruned in _process so the displayed sum reflects the last 5s of spawns.
	# Use _effective_max_health() so endless _hp_scale and slider overrides
	# are reflected in the threat chip.
	if enemy == null or enemy.data == null:
		return
	var hp: int = enemy._effective_max_health() if enemy.has_method("_effective_max_health") else int(enemy.data.max_health)
	if hp <= 0:
		return
	_spawn_rate_events.append([Time.get_ticks_msec(), hp])


func _refresh_threat() -> void:
	# Drop entries older than SPAWN_RATE_WINDOW_SEC. Sum remaining HP and
	# update the chip. Called every frame from _process. Color escalates by
	# band so the player reads "how heavy is the next 5s" at a glance.
	var cutoff: int = Time.get_ticks_msec() - int(SPAWN_RATE_WINDOW_SEC * 1000.0)
	while _spawn_rate_events.size() > 0 and int(_spawn_rate_events[0][0]) < cutoff:
		_spawn_rate_events.pop_front()
	var total: int = 0
	for entry in _spawn_rate_events:
		total += int(entry[1])
	threat_chip.set_value("%d" % total)
	var color: Color = Color(0.93, 0.91, 0.87, 1)  # white (default)
	if total >= 1000:
		color = Color(1.0, 0.32, 0.28, 1)   # red
	elif total >= 500:
		color = Color(1.0, 0.55, 0.2, 1)    # orange
	elif total >= 200:
		color = Color(1.0, 0.85, 0.35, 1)   # yellow
	threat_chip.set_value_color(color)


func _process(_delta: float) -> void:
	_refresh_threat()
