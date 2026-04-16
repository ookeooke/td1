extends Resource
class_name SpellData

# Phase 22: global spell resource. Same Resource+subclass pattern as
# SkillData — each concrete spell subclasses this and overrides apply().
# Spells target a world position (AoE) or fire globally; no caster Node
# is required, which is why they live in a separate panel from hero skills.
#
# Per CLAUDE.md: spells are upgradeable via the permanent upgrade tree
# (Phase 28). Upgrades will push `AbilityData` effects onto the spell's
# cast context — same primitive the rest of the game uses.

enum TargetType { AREA, GLOBAL }

# Stable ID for save/unlock/upgrade-tree references. Never rename post-release.
@export var spell_id: String = ""
@export var spell_name: String = "Spell"
# 0 = unlimited cast distance (GLOBAL-style reach, still AoE at target point).
@export var cast_range: float = 0.0
# Radius of effect around the tapped point.
@export var radius: float = 80.0
@export var damage: float = 0.0
@export var damage_type: int = 1  # DamageCalculator.DamageType.MAGIC by default
@export var cooldown: float = 30.0
@export var target_type: int = TargetType.AREA
@export var icon: Texture2D
@export var vfx_scene: PackedScene
@export_multiline var description: String = ""


# Subclasses override. `world_pos` is the tapped location in world-space.
# `caster` is whoever triggered the cast (usually the SpellPanel, passed
# through for future upgrades that care about who cast it — e.g. "spell
# damage +20% if cast by tapping on an enemy under attack by a tower").
func apply(_world_pos: Vector2, _caster: Node) -> void:
	pass
