@tool
extends BaseLevel

# Level2 — Stone Bridge (single-path serpentine).
# All shared logic lives in BaseLevel.gd; this file only declares which
# level_id and wave_list_path this scene represents.


func _level_id() -> String:
	return "level_2"


func _wave_list_path() -> String:
	return "res://levels/level2_waves.tres"
