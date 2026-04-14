extends Node2D

@onready var map: Node2D = $Map


func _ready() -> void:
	print("[Main] EventBus signals: ", EventBus.get_signal_list().size())
	var grid: Node = map.get_node("GridManager")
	print("[Main] Map loaded — free spots: ", grid.get_free_spot_ids())
