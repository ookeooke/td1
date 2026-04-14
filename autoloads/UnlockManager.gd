extends Node

# Phase 1 stub — IAP + unlock checks implemented in Phase 36/37.
# Rule: reads from SaveManager only; all unlock gates call is_unlocked(id).

func _ready() -> void:
	print("[UnlockManager] loaded")
