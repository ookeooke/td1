@tool
extends BaseLevel

# Level4 — Frost Vale (two-path converge). All shared logic lives in
# BaseLevel.gd; this file only declares the level_id and wave_list_path.


func _level_id() -> String:
	return "level_4"


func _wave_list_path() -> String:
	return "res://levels/level4_waves.tres"
