extends CanvasLayer

@onready var gold_label: Label = %GoldLabel
@onready var lives_label: Label = %LivesLabel
@onready var wave_label: Label = %WaveLabel
@onready var hero_label: Label = %HeroLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton

var _hero: Node = null

# Fast-forward: cycles through 1x → 2x → 3x → 1x. Kingdom Rush uses 1x/2x;
# 3x is a power-user option for long endless runs. Engine.time_scale affects
# everything (physics, timers, tweens) which is exactly what TD fast-forward
# needs — towers shoot faster, enemies walk faster, waves progress faster.
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 3.0]
var _speed_idx: int = 0


func _ready() -> void:
	pause_button.pressed.connect(func(): EventBus.pause_requested.emit())
	speed_button.pressed.connect(_on_speed_pressed)
	_refresh_speed_label()
	_on_gold_changed(GameState.gold)
	_on_lives_changed(GameState.lives)
	_refresh_wave()
	_refresh_hero()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.lives_changed.connect(_on_lives_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_xp_gained.connect(_on_hero_xp_gained)
	EventBus.hero_leveled_up.connect(_on_hero_leveled_up)
	EventBus.hero_died.connect(_on_hero_died)


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
	if total > 0 and GameState.wave_number > 0:
		wave_label.text = "Wave: %d/%d" % [GameState.wave_number, total]
	else:
		wave_label.text = "Wave: --"


func _on_hero_spawned(hero: Node) -> void:
	_hero = hero
	_refresh_hero()


func _on_hero_xp_gained(_amount: int) -> void:
	_refresh_hero()


func _on_hero_leveled_up(_new_level: int) -> void:
	_refresh_hero()


func _on_hero_died() -> void:
	_refresh_hero()


func _refresh_hero() -> void:
	if _hero == null or not is_instance_valid(_hero):
		hero_label.text = "Hero: --"
		return
	var lvl: int = _hero.level if "level" in _hero else 1
	var xp: int = _hero.current_xp if "current_xp" in _hero else 0
	var need: int = _hero._xp_needed_for_next_level() if _hero.has_method("_xp_needed_for_next_level") else 0
	if need <= 0:
		hero_label.text = "Lv %d (MAX)" % lvl
	else:
		hero_label.text = "Lv %d  XP %d/%d" % [lvl, xp, need]
