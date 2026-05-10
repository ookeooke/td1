extends Resource
class_name LevelNodeData

# One entry on the WorldMap. Data-driven: add more levels by creating more
# LevelNodeData .tres files and appending to the level_list.tres array.
# Stars + unlock state are read from MetaProgression at runtime, not baked here.

@export var level_id: String = ""
@export var display_name: String = "Level"
@export var scene_path: String = "res://main/Main.tscn"
@export var unlock_order: int = 1

# WorldMap layout: marker positions are authored as Marker2D children of
# LevelMarkers in WorldMapView.tscn — the Marker2D node name must match
# this `level_id`. Mirrors the TowerSpots → Spot1 pattern from Level1.tscn.

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
# 600s = 10-minute rule for new levels (BALANCE.md, L4+). L1-L3 override
# this in level_list.tres with their original 4-5 min values and are
# grandfathered. Only applies to fresh LevelNodeData sub-resources.
@export var target_duration_sec: float = 600.0
@export var gold_budget_total: int = 700
# Authored starting gold for this level. Sentinel -1 = fall through to the
# RunState baseline chain (STARTING_GOLD + meta_bonus + starting_gold_add).
# When ≥ 0, REPLACES that chain at runtime so the player always starts the
# level with exactly this value regardless of meta upgrades.
# Persisted by BalanceSliders' Bake button from the per-level starting_gold
# slider — see RunState.reset_for_level().
@export var starting_gold: int = -1
# One entry per wave; each array sums to 1.0 (validated at editor open).
# Empty array = uniform distribution.
@export var wave_gold_shares: Array[float] = []
@export var wave_time_shares: Array[float] = []
@export var wave_pressure_targets: Array[float] = []
# Send-Wave button visible only in the last N seconds of the current wave's
# spawn — pressing it starts the next wave immediately, parallel to the
# still-running current spawners. Bonus = overlap_seconds × gold_per_sec.
# Caps the maximum overlap (and therefore the maximum bonus).
@export var early_call_window_sec: float = 10.0
# Default gold-per-second of overlap. Per-wave WaveData.early_call_gold_per_sec
# can override (-1 sentinel = inherit this value).
@export var early_call_gold_per_sec: float = 1.0

# Player Power Tier band — see balance/BALANCE.md "Player Power Tier (PPT)".
# `min_ppt` is the Naked Baseline floor (one-star achievable at this PPT or
# above). `target_ppt` is the designed-for sweet spot — the audit screen
# compares actual hardness against `target_ppt × PPT_TO_HARDNESS_FACTOR` and
# flags drift. New campaign levels should ramp target_ppt by ~+1 per slot.
@export_range(1, 10) var min_ppt: int = 1
@export_range(1, 10) var target_ppt: int = 2
