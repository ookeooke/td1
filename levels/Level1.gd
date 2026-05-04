@tool
extends BaseLevel

# Level1 — first campaign map. All shared logic (drawing, decorations,
# hardness readout, spot registration, camera config) lives in BaseLevel.gd.
# This file only declares which level_id and wave_list_path this scene is for.


func _level_id() -> String:
	return "level_1"


func _wave_list_path() -> String:
	return "res://levels/level1_waves.tres"
