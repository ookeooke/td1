@tool
extends BaseLevel

# Level3 — Mountain Pass (single-path ring detour). All shared logic lives
# in BaseLevel.gd; this file only declares the level_id and wave_list_path.


func _level_id() -> String:
	return "level_3"


func _wave_list_path() -> String:
	return "res://levels/level3_waves.tres"
