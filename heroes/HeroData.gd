extends Resource
class_name HeroData

# Phase 18: hero stats. XP / leveling fields are present so Phase 19 can
# read them without re-saving every .tres, but unused this phase.

@export var hero_name: String = "Hero"
@export var hero_id: String = ""
@export var requires_unlock: bool = false

@export var max_health: int = 100
@export var attack_damage: float = 10.0
@export var attack_range: float = 150.0
@export var attack_speed: float = 1.0
@export var move_speed: float = 275.0
@export var armor: float = 0.2
@export var magic_resist: float = 0.0
@export var damage_type: int = 0  # DamageCalculator.DamageType.PHYSICAL
@export var targets_flying: bool = true

@export var xp_per_level: Array[int] = [50, 120, 220, 360, 540, 760, 1040, 1380, 1780, 2240]
@export var max_level: int = 10
@export var respawn_time: float = 30.0

# Active skills (player-cast via SkillBar buttons) — SkillData subclasses.
@export var skills: Array[Resource] = []
# Passive abilities (always-on traits, auras, on-hit effects) — AbilityData
# subclasses. Items equipped later will also push AbilityData via the same
# dispatcher, so passives + item-granted effects use one pipeline.
@export var abilities: Array[Resource] = []
# Per-hero talent tree (Phase 40). Purchased with stars, pushed onto the
# hero's AbilityHost at gameplay start.
@export var talents: Array[Resource] = []
@export var visual: Resource  # UnitVisualData — drives _draw() when set
@export_multiline var encyclopedia_entry: String = ""
