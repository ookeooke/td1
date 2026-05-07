@tool
extends BaseLevel

# Level5 — Riverford (river-canyon two-bridge map). All shared logic lives in
# BaseLevel.gd; this file only declares the level_id and wave_list_path.


func _level_id() -> String:
	return "level_5"


func _wave_list_path() -> String:
	return "res://levels/level5_waves.tres"
