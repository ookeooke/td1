extends Resource
class_name LevelNodeData

# One entry on the WorldMap. Data-driven: add more levels by creating more
# LevelNodeData .tres files and appending to the level_list.tres array.
# Stars + unlock state are read from GameState at runtime, not baked here.

@export var level_id: String = ""
@export var display_name: String = "Level"
@export var scene_path: String = "res://main/Main.tscn"
@export var unlock_order: int = 1
