extends Resource
class_name LevelNodeData

# One entry on the WorldMap. Data-driven: add more levels by creating more
# LevelNodeData .tres files and appending to the level_list.tres array.
# Stars + unlock state are read from GameState at runtime, not baked here.

@export var level_id: String = ""
@export var display_name: String = "Level"
@export var scene_path: String = "res://main/Main.tscn"
@export var unlock_order: int = 1

# Authored economy + pressure curve — see balance/BALANCE.md
# "Authored economy + pressure curve".
#
# Three knobs the level designer authors directly:
#   1. gold_budget_total — max gold from kills + bounties (no early-calls)
#   2. target_duration_sec — passive run length floor
#   3. wave_pressure_targets — per-wave gear pressure (required÷affordable DPS)
#
# Per-wave shapes (gold + time) are arrays that sum to 1.0. The system
# derives wave-by-wave gold targets and time slices from them.
@export var wave_list_path: String = ""
@export var target_duration_sec: float = 360.0
@export var gold_budget_total: int = 700
# One entry per wave; each array sums to 1.0 (validated at editor open).
# Empty array = uniform distribution.
@export var wave_gold_shares: Array[float] = []
@export var wave_time_shares: Array[float] = []
@export var wave_pressure_targets: Array[float] = []
# Send-Wave button visible only in the last N seconds of countdown.
# Caps the early-call gold bonus per wave at this value.
@export var early_call_window_sec: float = 10.0
