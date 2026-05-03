extends Resource
class_name LevelList

# Container for the campaign's per-level metadata. Single .tres file
# (level_list.tres) holds an Array of LevelNodeData with one entry per
# campaign level. Loaded by ContentRegistry at boot; consumers iterate
# `ContentRegistry.levels` or call `ContentRegistry.find_level(id)`.
#
# Type is Array[Resource] (not Array[LevelNodeData]) to match the rest of
# ContentRegistry's catalog convention — Godot 4 typed arrays are invariant,
# so consumers can't downcast Array[LevelNodeData] → Array[Resource]. Element
# type is enforced at runtime by ContentRegistry._validate_ids.

@export var levels: Array[Resource] = []
