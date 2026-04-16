extends Resource
class_name TowerData

@export var tower_name: String = "Tower"
@export var tower_id: String = ""
@export var requires_unlock: bool = false

@export var damage: float = 5.0
@export var damage_type: int = 0  # DamageCalculator.DamageType
@export var attack_range: float = 375.0
@export var attack_speed: float = 1.0
@export var cost: int = 50
@export var sell_value: int = 30
@export var targets_flying: bool = false
# AoE splash radius. 0 = single target (arrow). > 0 = projectile splashes
# on hit, damaging all enemies within this radius of the impact point.
@export var aoe_radius: float = 0.0
# Placeholder body color for _draw(). Lets each tower type have a distinct
# visual without per-tower _draw() subclasses.
@export var body_color: Color = Color(0.35, 0.45, 0.75)

# Phase 24: per-level upgrade stats. Index 0 = L2 data, index 1 = L3 data
# (ignored when `level_3_branches` is non-empty — branches take over).
@export var level_upgrades: Array[Resource] = []
# Phase 25: branch choices at level 3. If non-empty, L2 → L3 presents
# these as alternatives and `level_upgrades[1]` is bypassed. Conventional
# layout: index 0 = branch A (e.g. Ranger), index 1 = branch B (Musketeer).
# Nothing forces two branches — 1 here works fine (linear), 3+ would show
# more buttons.
@export var level_3_branches: Array[Resource] = []
# Legacy cost fields — kept for tower data files authored before Phase 24.
# New content should put `cost` on TowerUpgradeData instead. If a .tres has
# both, TowerUpgradeData wins via `_effective_upgrade_cost(level)`.
@export var upgrade_cost_lvl2: int = 0
@export var upgrade_cost_lvl3: int = 0
# Phase 25 branch scene overrides — deferred.
@export var upgrade_a_scene: PackedScene
@export var upgrade_b_scene: PackedScene
@export var upgrade_a_data: Resource
@export var upgrade_b_data: Resource

# Asset reference — per tower; not a "stat" so keeping alongside config.
@export var projectile_scene: PackedScene

# Barracks fields (unused on attack towers). Phase 16.
@export var soldier_scene: PackedScene
@export var soldier_data: Resource
@export var soldier_blocking_offset: Vector2 = Vector2(0, 112.5)
@export var soldier_spread: Vector2 = Vector2(40, 25)
@export var soldier_rally_range: float = 350.0

@export_multiline var encyclopedia_entry: String = ""
