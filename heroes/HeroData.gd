extends Resource
class_name HeroData

# Phase 18: hero stats. XP / leveling fields are present so Phase 19 can
# read them without re-saving every .tres, but unused this phase.

@export var hero_name: String = "Hero"
@export var hero_id: String = ""
@export var requires_unlock: bool = false
# Player Power Tier — see balance/BALANCE.md "Player Power Tier (PPT)".
# 1 = baseline starter (warrior); 5 = legendary endgame hero. Summed by
# LoadoutState.get_effective_ppt() to compute what the player loadout is
# worth, which the balance audit compares against per-level target_ppt.
@export_range(1, 10) var power_tier: int = 1

@export var max_health: int = 100
@export var attack_damage: float = 10.0
@export var attack_range: float = 150.0
# Blocker-claim radius — enemies entering this halt and engage as melee.
# Decoupled from `attack_range` so ranged heroes (mage, sniper) attack from
# afar without freezing every enemy at the edge of their projectile reach,
# while melee heroes still pull enemies into face contact. 0 = derive
# `min(attack_range, BaseHero.DEFAULT_ENGAGE_RADIUS)` at spawn — set it
# explicitly only when the archetype diverges (tank with bigger presence,
# sniper that should never block, dragon with a large body).
@export var engage_radius: float = 0.0
@export var attack_speed: float = 1.0
@export var move_speed: float = 275.0
@export var armor: float = 0.2
@export var magic_resist: float = 0.0
@export var damage_type: int = 0  # DamageCalculator.DamageType.PHYSICAL
@export var targets_flying: bool = true

@export var xp_per_level: Array[int] = [50, 120, 220, 360, 540, 760, 1040, 1380, 1780, 2240]
@export var max_level: int = 10
@export var respawn_time: float = 30.0
# How many enemies this hero can lock into COMBAT simultaneously. Tanks
# (warrior) default to 2, fragile casters to 1 via their .tres override.
# Enemies allow any number of blockers — the cap lives here.
@export var max_block_targets: int = 2

# Active skills (player-cast via SkillBar buttons) — SkillData subclasses.
@export var skills: Array[Resource] = []
# Starter loadout — the skill_ids that fill the player's active slots on a
# new save (or when "Reset to default" is pressed in the Skills page).
# Order matters: starter_skill_ids[0] occupies slot 0, [1] slot 1, etc.
# Empty array = fall back to "first N unlocked in author order" (see
# LoadoutState._default_equipped_for). Skill ids referencing skills not
# authored on this hero are silently dropped at resolve time.
@export var starter_skill_ids: Array[String] = []
# Passive abilities (always-on traits, auras, on-hit effects) — AbilityData
# subclasses. Items equipped later will also push AbilityData via the same
# dispatcher, so passives + item-granted effects use one pipeline.
@export var abilities: Array[Resource] = []
# Per-hero talent tree (Phase 40). Purchased with stars, pushed onto the
# hero's AbilityHost at gameplay start.
@export var talents: Array[Resource] = []
@export var visual: Resource  # UnitVisualData — drives _draw() when set
# Phase 3R-followup-3 — optional projectile for basic attacks. When set,
# _attack_step spawns this PackedScene's root and calls setup(target, damage,
# damage_type, source) on it (mirroring BaseTower._fire_projectile). Use
# res://projectiles/Arrow.tscn for the ranger archetype. Null = instant hit
# (melee / instant magic strike). Mirrors TowerData.projectile_scene.
@export var projectile_scene: PackedScene
# Phase 48 — starter gear granted + auto-equipped the first time this hero
# is played. Each entry is an ItemBase; InventoryManager.ensure_starter_gear
# creates a zero-affix ItemInstance and slots it into the matching slot.
# Only applied once per hero_id (tracked via starter_gear_granted).
@export var starter_items: Array[Resource] = []

# Phase 50 — Per-hero equipment-slot configuration. Slot ints reference
# ItemBase.slot (0=Weapon, 1=Armor, 2=Helm, 3=Gloves, 4=Boots, 5=Trinket).
# - equipment_slots: which slot indices THIS hero exposes. Empty array =
#   default humanoid layout (all 6).
# - slot_label_overrides: per-slot rename (e.g. Dragon's "Weapon" → "Breath
#   Sigil"). Missing keys fall back to the default SLOT_NAMES.
# - slot_anchors: paperdoll-relative position for each slot (Vector2 in
#   0..1 space; (0.5, 0.1) = top-center). Missing keys fall back to the
#   default humanoid anchors.
# - paperdoll_alpha: backdrop silhouette translucency (0..1). Default 0.35.
@export var equipment_slots: Array[int] = []
@export var slot_label_overrides: Dictionary = {}
@export var slot_anchors: Dictionary = {}
@export_range(0.0, 1.0) var paperdoll_alpha: float = 0.35

@export_multiline var encyclopedia_entry: String = ""


# Build-preview stats row — pre-spawn (no current_health, no modifiers).
# Mirrors TowerData.get_stats_line() spacing (three spaces between fields)
# and BaseHero.get_stats_line() field order so the player reads the same
# card in HeroesHub Hall, Encyclopedia, and the loadout screen.
func get_stats_line() -> String:
	var line: String = "Dmg %d   Rng %d   Spd %.1f   HP %d   Arm %d%%" % [
		int(round(attack_damage)),
		int(round(attack_range)),
		attack_speed,
		max_health,
		int(round(armor * 100.0)),
	]
	if magic_resist > 0.0:
		line += "   MR %d%%" % int(round(magic_resist * 100.0))
	return line
