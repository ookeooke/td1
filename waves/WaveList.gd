extends Resource
class_name WaveList

# Ordered list of waves for a level. Phase 26 will fold this into LevelData
# alongside star thresholds; for now each level has its own WaveList .tres.

@export var waves: Array[WaveData] = []
