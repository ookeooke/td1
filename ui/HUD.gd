extends CanvasLayer

@onready var gold_label: Label = %GoldLabel
@onready var lives_label: Label = %LivesLabel
@onready var wave_label: Label = %WaveLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton
@onready var countdown_label: Label = %CountdownLabel
@onready var send_wave_button: Button = %SendWaveButton
@onready var spawn_rate_label: Label = %SpawnRateLabel

# Rolling 5-second window of incoming enemy HP. Each entry: [spawn_time_ms,
# max_health]. Old entries pruned in _process. Sum displayed as "Incoming:
# X HP/5s" in the top-right — design diagnostic + player threat preview.
const SPAWN_RATE_WINDOW_SEC: float = 5.0
var _spawn_rate_events: Array = []

# 2026-04-29 — Send Wave button blinks while a wave countdown is active so
# the player notices the "click me to start" affordance. Tween pulses the
# button's modulate alpha; killed when the wave launches or is sent early.
var _send_wave_blink: Tween = null

# Fast-forward: cycles through 1x → 2x → 3x → 1x. Kingdom Rush uses 1x/2x;
# 3x is a power-user option for long endless runs. Engine.time_scale affects
# everything (physics, timers, tweens) which is exactly what TD fast-forward
# needs — towers shoot faster, enemies walk faster, waves progress faster.
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 3.0]
var _speed_idx: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(func(): EventBus.pause_requested.emit())
	speed_button.pressed.connect(_on_speed_pressed)
	_refresh_speed_label()
	_on_gold_changed(RunState.gold)
	_on_lives_changed(RunState.lives)
	_refresh_wave()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.lives_changed.connect(_on_lives_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	# Early wave call.
	send_wave_button.pressed.connect(_on_send_wave_pressed)
	countdown_label.visible = false
	send_wave_button.visible = false
	EventBus.wave_countdown_started.connect(_on_countdown_started)
	EventBus.wave_started.connect(_on_wave_launched)
	EventBus.early_wave_triggered.connect(_on_early_wave)
	# Rolling 5s incoming-HP indicator. Updated on each spawn; pruned every
	# frame in _process. Cleared on wave_started so each wave's window is fresh.
	EventBus.enemy_spawned.connect(_on_enemy_spawned_for_rate)


func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount


func _on_lives_changed(amount: int) -> void:
	lives_label.text = "Lives: %d" % amount


func _on_wave_started(wave_number: int, _path_ids: Array) -> void:
	var total: int = WaveManager.wave_count()
	if total > 0:
		wave_label.text = "Wave: %d/%d" % [wave_number, total]
	else:
		wave_label.text = "Wave: %d" % wave_number  # endless — no total


func _on_all_waves_completed() -> void:
	wave_label.text = "Victory!"


func _on_speed_pressed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEED_OPTIONS.size()
	Engine.time_scale = SPEED_OPTIONS[_speed_idx]
	_refresh_speed_label()


func _refresh_speed_label() -> void:
	var spd: float = SPEED_OPTIONS[_speed_idx]
	speed_button.text = "%dx" % int(spd)


func _refresh_wave() -> void:
	var total: int = WaveManager.wave_count()
	if total > 0 and RunState.wave_number > 0:
		wave_label.text = "Wave: %d/%d" % [RunState.wave_number, total]
	else:
		wave_label.text = "Wave: --"


# --- Early wave call ---

func _on_countdown_started(duration: float) -> void:
	# duration <= 0 = button-only mode (typically W1). No timer ticks; the
	# wave waits for the player to press the Send-Wave button.
	if duration <= 0.0:
		countdown_label.text = "Ready when you are"
	else:
		countdown_label.text = "Next wave: %.1fs" % duration
	countdown_label.visible = true
	# KR-canonical: button visible the entire countdown. Bonus magnitude is
	# capped by early_call_window_sec (in WaveManager.call_early_wave) so
	# unlimited gold isn't possible. See CORE RULE 19.
	send_wave_button.visible = true
	_start_send_wave_blink()


func _start_send_wave_blink() -> void:
	# Stop any prior tween before starting a fresh one — otherwise back-to-back
	# countdowns layer tweens onto the same property and modulate fights itself.
	_stop_send_wave_blink()
	send_wave_button.modulate = Color(1.0, 1.0, 0.6, 1.0)  # warm yellow at full brightness
	_send_wave_blink = create_tween()
	_send_wave_blink.set_loops()                      # infinite until killed
	_send_wave_blink.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # keep blinking through tactical pause
	_send_wave_blink.tween_property(send_wave_button, "modulate",
		Color(1.0, 1.0, 0.6, 0.45), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_send_wave_blink.tween_property(send_wave_button, "modulate",
		Color(1.0, 1.0, 0.6, 1.0), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_send_wave_blink() -> void:
	if _send_wave_blink != null and _send_wave_blink.is_valid():
		_send_wave_blink.kill()
	_send_wave_blink = null
	# Restore default modulate so a hidden button isn't half-faded next time.
	send_wave_button.modulate = Color.WHITE


func _on_enemy_spawned_for_rate(enemy: Node, _path_id: String) -> void:
	# Push (now_ms, max_health) into the rolling window. Old entries are
	# pruned in _process so the displayed sum reflects the last 5s of spawns.
	if enemy == null or enemy.data == null:
		return
	var hp: int = int(enemy.data.max_health)
	if hp <= 0:
		return
	_spawn_rate_events.append([Time.get_ticks_msec(), hp])


func _refresh_spawn_rate() -> void:
	# Drop entries older than SPAWN_RATE_WINDOW_SEC. Sum remaining HP and
	# update the label. Called every frame from _process.
	var cutoff: int = Time.get_ticks_msec() - int(SPAWN_RATE_WINDOW_SEC * 1000.0)
	while _spawn_rate_events.size() > 0 and int(_spawn_rate_events[0][0]) < cutoff:
		_spawn_rate_events.pop_front()
	var total: int = 0
	for entry in _spawn_rate_events:
		total += int(entry[1])
	spawn_rate_label.text = "Incoming: %d HP/5s" % total


func _process(_delta: float) -> void:
	_refresh_spawn_rate()
	# Tick the countdown label from WaveManager state.
	if countdown_label.visible and WaveManager._in_countdown:
		# Button-only mode (W1) keeps the "Ready when you are" label set by
		# _on_countdown_started. Other waves tick down the seconds remaining.
		if WaveManager._countdown_total > 0.0:
			countdown_label.text = "Next wave: %.1fs" % maxf(0.0, WaveManager._countdown_remaining)
		# Window-gate the Send-Wave button: only visible in the last
		# early_call_window_sec of countdown (or always, in button-only mode).
		# Lazy-start blink the moment the button first appears in this countdown.
		var should_show: bool = WaveManager.early_call_available()
		if should_show != send_wave_button.visible:
			send_wave_button.visible = should_show
			if should_show:
				_start_send_wave_blink()
			else:
				_stop_send_wave_blink()


func _on_wave_launched(_wave_number: int, _path_ids: Array) -> void:
	_hide_countdown()


func _on_send_wave_pressed() -> void:
	WaveManager.call_early_wave()
	_hide_countdown()


func _on_early_wave(_bonus_gold: int) -> void:
	_hide_countdown()


func _hide_countdown() -> void:
	countdown_label.visible = false
	send_wave_button.visible = false
	_stop_send_wave_blink()


