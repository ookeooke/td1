extends Resource
class_name EnemyData

# Stable ID for save/leaderboard/loot references. Never rename in released builds.
@export var enemy_id: String = ""
@export var enemy_name: String = "Enemy"
@export var max_health: int = 10
@export var move_speed: float = 150.0
@export_range(0.0, 1.0) var armor: float = 0.0
@export_range(0.0, 1.0) var magic_resist: float = 0.0
@export var lives_worth: int = 1
@export var gold_worth: int = 5
# XP awarded to the hero when the hero delivers the killing blow. Towers
# don't grant XP — only direct hero kills (last-hit semantics).
@export var xp_worth: int = 5

# Melee counter-attack stats — used by BaseEnemy while engaged in COMBAT
# state (vs. a blocking soldier). Flying units skip engagement entirely.
@export var attack_damage: float = 3.0
@export var attack_speed: float = 1.0
# Phase 45d: AoE counter-attack radius. 0 = single-target (hit _blockers[0]
# only — default, matches all existing archetypes). >0 = hit every blocker
# within this pixel radius of the focus blocker. Designed as the balance
# counter to stacked-rally boss gangs (KR's Yeti / Magma Elemental pattern).
@export var attack_splash_radius: float = 0.0

@export var is_flying: bool = false
# Phase 45f: dedicated bypass archetype (Rushing-Monkey equivalent). When
# true, BaseEnemy.engage_combat rejects every blocker, so the enemy walks
# through soldier lines uninterrupted. Author as opt-in data — default keeps
# the entire roster's behavior unchanged. Intended counter: AoE towers.
@export var bypass_engagement: bool = false
@export var can_stealth: bool = false
@export_range(0.0, 1.0) var stealth_threshold: float = 0.5

# Phase 20.5 architecture: per-enemy mechanics (regen, heal-aura,
# explode-on-death, summon-on-death, stealth-under-HP, enrage, etc.)
# are now modeled as AbilityData resources in this array, not as flat
# bool+param pairs on this data class. Keeps EnemyData lean and lets
# designers mix-and-match behaviours on a single enemy in the Inspector.
@export var abilities: Array[Resource] = []
# Phase 38: boss phase transitions. Empty for non-bosses.
@export var boss_phases: Array[Resource] = []
@export var is_boss: bool = false

@export var visual: Resource  # UnitVisualData — drives _draw() when set
@export_multiline var encyclopedia_entry: String = ""
