extends Node2D

func _ready() -> void:
	print("[Main] Phase 1 skeleton running")
	print("[Main] EventBus signals available: ", EventBus.get_signal_list().size())
