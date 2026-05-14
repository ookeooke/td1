extends Node

# Phase 41: Audio infrastructure. Plays SFX via a pre-allocated pool and
# music via a dedicated player. Gracefully handles missing audio files —
# the game runs silent until .wav/.ogg files are dropped into res://audio/.

const SFX_POOL_SIZE: int = 8

const SFX_PATHS: Dictionary = {
	"enemy_die":      "res://audio/sfx/enemy_die.wav",
	"enemy_hit":      "res://audio/sfx/enemy_hit.wav",
	"tower_shoot":    "res://audio/sfx/tower_shoot.wav",
	"tower_build":    "res://audio/sfx/tower_build.wav",
	"tower_sell":     "res://audio/sfx/tower_sell.wav",
	"tower_upgrade":  "res://audio/sfx/tower_upgrade.wav",
	"gold_earned":    "res://audio/sfx/gold_earned.wav",
	"purchase_denied":"res://audio/sfx/purchase_denied.wav",
	"wave_start":     "res://audio/sfx/wave_start.wav",
	"wave_complete":  "res://audio/sfx/wave_complete.wav",
	"hero_skill":     "res://audio/sfx/hero_skill.wav",
	"hero_level_up":  "res://audio/sfx/hero_level_up.wav",
	"game_over":      "res://audio/sfx/game_over.wav",
	"victory":        "res://audio/sfx/victory.wav",
	"boss_phase":     "res://audio/sfx/boss_phase.wav",
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer = null
var _sfx_volume: float = 1.0
var _music_volume: float = 0.7
# Paths we already warned about — log once, not every frame.
var _warned_paths: Dictionary = {}


func _ready() -> void:
	# Pre-allocate SFX pool.
	for i in SFX_POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_sfx_pool.append(player)
	# Music player.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	# Wire EventBus signals.
	EventBus.enemy_died.connect(func(_e, _g): play_sfx("enemy_die"))
	EventBus.tower_built.connect(func(_t, _s): play_sfx("tower_build"))
	EventBus.tower_sold.connect(func(_t, _r): play_sfx("tower_sell"))
	EventBus.tower_upgraded.connect(func(_t, _l): play_sfx("tower_upgrade"))
	EventBus.wave_started.connect(func(_w, _p): play_sfx("wave_start"))
	EventBus.wave_completed.connect(func(_w): play_sfx("wave_complete"))
	EventBus.hero_skill_used.connect(func(_s): play_sfx("hero_skill"))
	EventBus.purchase_denied.connect(func(_r): play_sfx("purchase_denied"))
	EventBus.game_over.connect(func(): play_sfx("game_over"))
	EventBus.all_waves_completed.connect(func(): play_sfx("victory"))


func play_sfx(event_name: String) -> void:
	if not SFX_PATHS.has(event_name):
		return
	var path: String = SFX_PATHS[event_name]
	if not ResourceLoader.exists(path):
		if not _warned_paths.has(path):
			_warned_paths[path] = true
			print("[SoundManager] Missing audio: %s" % path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var player: AudioStreamPlayer = _get_idle_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = linear_to_db(_sfx_volume)
	player.play()


func play_music(path: String) -> void:
	if not ResourceLoader.exists(path):
		if not _warned_paths.has(path):
			_warned_paths[path] = true
			print("[SoundManager] Missing music: %s" % path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.volume_db = linear_to_db(_music_volume)
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func set_sfx_volume(linear: float) -> void:
	_sfx_volume = clampf(linear, 0.0, 1.0)


func set_music_volume(linear: float) -> void:
	_music_volume = clampf(linear, 0.0, 1.0)
	if _music_player.playing:
		_music_player.volume_db = linear_to_db(_music_volume)


func _get_idle_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return null
