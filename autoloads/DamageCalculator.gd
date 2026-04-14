extends Node

# Rule: ALL damage math lives here. Never calculate damage inline.
# Targets are expected to expose `.data` with `armor` and `magic_resist`
# (both clamped 0..1). Missing data -> unmitigated.

enum DamageType { PHYSICAL, MAGIC, TRUE }


func _ready() -> void:
	print("[DamageCalculator] loaded")


func calculate_damage(amount: float, type: int, target) -> float:
	if amount <= 0.0:
		return 0.0

	var armor := 0.0
	var magic_resist := 0.0
	if target and "data" in target and target.data != null:
		armor = clampf(target.data.armor, 0.0, 1.0)
		magic_resist = clampf(target.data.magic_resist, 0.0, 1.0)

	match type:
		DamageType.PHYSICAL:
			return amount * (1.0 - armor)
		DamageType.MAGIC:
			return amount * (1.0 - magic_resist)
		DamageType.TRUE:
			return amount
	return amount
