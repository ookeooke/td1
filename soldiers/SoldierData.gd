extends Resource
class_name SoldierData

# Stable ID for save/unlock/loot references. Never rename in released builds.
@export var soldier_id: String = ""
@export var soldier_name: String = "Soldier"
@export var max_health: int = 20
@export var attack_damage: float = 4.0
@export var attack_speed: float = 1.0
@export var move_speed: float = 175.0
@export_range(0.0, 1.0) var armor: float = 0.1
@export_range(0.0, 1.0) var magic_resist: float = 0.0
@export var respawn_time: float = 4.0
@export var max_count: int = 3
@export var melee_range: float = 45.0
# Kingdom-Rush charge sense: soldier at rally that spots an enemy within
# this radius charges out to intercept. Must be >= melee_range; the radius
# is auto-maxed against melee_range at _ready so a lazy .tres can leave it 0.
@export var aggro_range: float = 130.0
# Max distance the soldier may drift from its rally slot during a charge
# before it drops the target and returns home. Anchors the chase to the
# barracks zone so a fast enemy can't drag troops off the lane.
@export var leash_range: float = 200.0
# How many enemies this soldier can lock into COMBAT simultaneously. Basic
# grunts hold one; Paladin-class variants (capacity 2+) can tank a small
# pack solo. Enemies allow any number of blockers — the cap lives here.
@export var max_block_targets: int = 1
# Composed passives — heal aura (Paladin), damage block (Shield Bearer),
# enrage under HP (Berserker), etc. Same AbilityData primitive enemies use.
@export var abilities: Array[Resource] = []
@export var visual: Resource  # UnitVisualData — drives _draw() when set
@export_multiline var encyclopedia_entry: String = ""
