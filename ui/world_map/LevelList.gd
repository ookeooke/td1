extends Resource
class_name LevelList

# Container for the campaign's per-level metadata. Single .tres file
# (level_list.tres) holds an Array[LevelNodeData] with one entry per
# campaign level. Loaded by Main.gd (early-call window lookup) and
# Level<N>.gd (drift/pressure readout). Kept as a typed Resource so
# `.levels` is accessible via direct property access (a script_class=
# "Resource" with no script attached drops unknown properties on load).

@export var levels: Array[LevelNodeData] = []
