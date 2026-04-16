extends Resource
class_name SoldierData

# Stable ID for save/unlock/loot references. Never rename in released builds.
@export var soldier_id: String = ""
@export var soldier_name: String = "Soldier"
@export var max_health: int = 20
@export var attack_damage: float = 4.0
@export var attack_speed: float = 1.0
@export var move_speed: float = 70.0
@export_range(0.0, 1.0) var armor: float = 0.1
@export_range(0.0, 1.0) var magic_resist: float = 0.0
@export var respawn_time: float = 4.0
@export var max_count: int = 3
@export var melee_range: float = 18.0
# Composed passives — heal aura (Paladin), damage block (Shield Bearer),
# enrage under HP (Berserker), etc. Same AbilityData primitive enemies use.
@export var abilities: Array[Resource] = []
@export var visual: Resource  # UnitVisualData — drives _draw() when set
@export_multiline var encyclopedia_entry: String = ""
