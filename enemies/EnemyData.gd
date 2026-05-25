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

# Ranged attack — used by BaseEnemy in WALKING state when attack_range > 0.
# Enemy halts to fire at the nearest soldier/hero in range; resumes walking
# once no target is in range. Melee counter-attack (attack_damage /
# attack_speed) still applies if a blocker engages it — both can coexist on
# one enemy. Goblin Archer is the first archetype to use this; all existing
# enemies keep attack_range = 0 so the ranged branch is skipped.
@export var attack_range: float = 0.0
@export var ranged_damage: float = 0.0
@export var ranged_attack_speed: float = 0.0    # shots/sec; cooldown = 1/ranged_attack_speed
@export var ranged_projectile: PackedScene
# Inspector-friendly enum (values pinned to DamageCalculator.DamageType).
# PHYSICAL=0 (armor-mitigated), MAGIC=1 (magic_resist-mitigated), TRUE=2
# (bypasses all). Default PHYSICAL keeps existing archers' arrows unchanged.
@export_enum("PHYSICAL:0", "MAGIC:1", "TRUE:2") var ranged_damage_type: int = 0
# Ranged status payloads — exactly one applies per shot (Arrow.gd has a
# single _status_effect slot). Priority in _fire_ranged_projectile: burn
# > poison > slow. Identity 0/0 = no status, archers ship melee-only by
# default and existing variants stay unchanged. Each archer variant
# authors ONE of these triplets — pick the type that defines the archetype.
# Goblin Fire Archer uses burn, Goblin Ice Archer uses slow, Goblin Poison
# Archer uses poison. CORE RULE 22: each new pair is wired to BalanceSliders.
@export var ranged_burn_dps: float = 0.0
@export var ranged_burn_duration: float = 0.0
@export var ranged_poison_dps: float = 0.0
@export var ranged_poison_duration: float = 0.0
@export_range(0.0, 1.0) var ranged_slow_factor: float = 0.0
@export var ranged_slow_duration: float = 0.0

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
# Phase 48 E3 — optional per-enemy loot table override. Null = use the
# default table held by LootDropper. Bosses typically set this to their own
# guaranteed-drop table; regular mobs leave it null.
@export var loot_table: Resource
@export_multiline var encyclopedia_entry: String = ""
