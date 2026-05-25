@tool
extends BaseLevel

# Level6 — Crossroads (two threat lines entering from opposite corners and
# converging at a central base). All shared logic lives in BaseLevel.gd; this
# file only declares the level_id and wave_list_path.


func _level_id() -> String:
	return "level_6"


func _wave_list_path() -> String:
	return "res://levels/level6_waves.tres"
