extends Resource
class_name WaveList

# Ordered list of waves for a level. One .tres per level, referenced from
# LevelNodeData.wave_list_path so the world map stays a small index.

@export var waves: Array[WaveData] = []
