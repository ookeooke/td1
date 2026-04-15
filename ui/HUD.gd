extends CanvasLayer

@onready var gold_label: Label = %GoldLabel
@onready var lives_label: Label = %LivesLabel
@onready var wave_label: Label = %WaveLabel


func _ready() -> void:
	_on_gold_changed(GameState.gold)
	_on_lives_changed(GameState.lives)
	_refresh_wave()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.lives_changed.connect(_on_lives_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)


func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount


func _on_lives_changed(amount: int) -> void:
	lives_label.text = "Lives: %d" % amount


func _on_wave_started(wave_number: int, _path_ids: Array) -> void:
	var total: int = WaveManager.wave_count()
	wave_label.text = "Wave: %d/%d" % [wave_number, total]


func _on_all_waves_completed() -> void:
	wave_label.text = "Victory!"


func _refresh_wave() -> void:
	var total: int = WaveManager.wave_count()
	if total > 0 and GameState.wave_number > 0:
		wave_label.text = "Wave: %d/%d" % [GameState.wave_number, total]
	else:
		wave_label.text = "Wave: --"
