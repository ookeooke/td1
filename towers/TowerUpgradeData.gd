extends Resource
class_name TowerUpgradeData

# Phase 24: per-level upgrade data for attack towers. Sits in
# TowerData.level_upgrades[], index 0 = L2, index 1 = L3. Phase 25 will
# use this same Resource type for branch choices (Ranger vs. Musketeer)
# by putting two TowerUpgradeData instances at the L3 slot.
#
# Each entry fully overrides the level's damage/range/speed rather than
# stacking multipliers — easier to balance-tune in the Inspector, and
# Phase 25 branches want totally different stat profiles anyway.

@export var upgrade_name: String = ""
@export var damage: float = 0.0
@export var attack_range: float = 0.0
@export var attack_speed: float = 0.0
@export var cost: int = 0  # gold to reach this level from the previous level
@export var sell_value: int = 0  # refund after buying this upgrade
# On-hit ability list for projectiles at this level — reserved for future
# general-purpose on-hit composition (pierce, chain, etc.). Phase 41 polish
# generalizes on-hit to this list. For Phase 25 branching, the common
# cases (slow, stun) have dedicated fields below so we don't need to
# instantiate RefCounted StatusEffects through the ability pipeline yet.
@export var on_hit_abilities: Array[Resource] = []
# Phase 25 branch-specific on-hit status effects per projectile. Leave at
# 0 for branches that just boost raw stats (Musketeer).
@export_range(0.0, 1.0) var on_hit_slow_factor: float = 0.0
@export var on_hit_slow_duration: float = 0.0
@export var on_hit_stun_duration: float = 0.0
# Placeholder tint for the tower body — gives a visual read on upgrade
# level until Phase 41 polish introduces real per-level sprites.
@export var tint: Color = Color.WHITE
