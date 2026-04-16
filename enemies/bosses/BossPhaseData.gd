extends Resource
class_name BossPhaseData

# One phase of a boss encounter. Activates when the boss's HP drops below
# `hp_threshold` (fraction 0.0–1.0 of max HP). Stat multipliers stack on
# top of the base EnemyData values. Abilities are pushed/popped by
# BaseBoss on phase transition.

# Phase activates when (current_health / max_health) drops below this.
@export_range(0.0, 1.0) var hp_threshold: float = 1.0
@export var phase_name: String = ""
@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
# Abilities that become active during this phase (and deactivate when
# the next phase triggers). Composed from the same AbilityData pool.
@export var abilities: Array[Resource] = []
# Visual tint for the boss body during this phase.
@export var tint: Color = Color.WHITE
