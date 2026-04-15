extends Node

const STARTING_GOLD: int = 100
const STARTING_LIVES: int = 20

var gold: int = 0
var lives: int = 0
var score: int = 0
var wave_number: int = 0
var current_mode: String = "campaign"  # "campaign" / "heroic" / "iron" / "endless"


func _ready() -> void:
	reset()
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_reached_end.connect(_on_enemy_reached_end)
	print("[GameState] loaded — gold=%d lives=%d" % [gold, lives])


func reset() -> void:
	gold = STARTING_GOLD
	lives = STARTING_LIVES
	score = 0
	wave_number = 0


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


func lose_lives(amount: int) -> void:
	if amount <= 0:
		return
	lives = maxi(0, lives - amount)
	EventBus.lives_changed.emit(lives)
	if lives <= 0:
		EventBus.game_over.emit()


func _on_enemy_died(_enemy: Node, gold_value: int) -> void:
	add_gold(gold_value)


func _on_enemy_reached_end(_enemy: Node, lives_lost: int) -> void:
	lose_lives(lives_lost)
