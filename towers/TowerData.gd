extends Resource
class_name TowerData

@export var tower_name: String = "Tower"
@export var tower_id: String = ""
@export var requires_unlock: bool = false

@export var damage: float = 5.0
@export var damage_type: int = 0  # DamageCalculator.DamageType
@export var attack_range: float = 150.0
@export var attack_speed: float = 1.0
@export var cost: int = 50
@export var sell_value: int = 30
@export var targets_flying: bool = false

@export var upgrade_cost_lvl2: int = 75
@export var upgrade_cost_lvl3: int = 120
@export var upgrade_a_scene: PackedScene
@export var upgrade_b_scene: PackedScene
@export var upgrade_a_data: Resource
@export var upgrade_b_data: Resource

# Asset reference — per tower; not a "stat" so keeping alongside config.
@export var projectile_scene: PackedScene

@export_multiline var encyclopedia_entry: String = ""
