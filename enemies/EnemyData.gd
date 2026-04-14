extends Resource
class_name EnemyData

@export var enemy_name: String = "Enemy"
@export var max_health: int = 10
@export var move_speed: float = 60.0
@export_range(0.0, 1.0) var armor: float = 0.0
@export_range(0.0, 1.0) var magic_resist: float = 0.0
@export var lives_worth: int = 1
@export var gold_worth: int = 5

@export var is_flying: bool = false
@export var can_stealth: bool = false
@export_range(0.0, 1.0) var stealth_threshold: float = 0.5

@export var regenerates: bool = false
@export var regen_rate: float = 0.0

@export var heals_allies: bool = false
@export var heal_range: float = 0.0
@export var heal_amount: float = 0.0
@export var heal_interval: float = 3.0

@export var explodes_on_death: bool = false
@export var explosion_damage: float = 0.0
@export var explosion_range: float = 0.0

@export var spawns_on_death: bool = false
@export var spawn_scene: PackedScene
@export var spawn_count: int = 0

@export_multiline var encyclopedia_entry: String = ""
