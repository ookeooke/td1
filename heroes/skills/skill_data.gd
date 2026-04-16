extends Resource
class_name SkillData

# Phase 20: base skill resource. Per CLAUDE.md:
#   - Each skill is its own script (subclass SkillData and override apply())
#   - Cooldown + range are data, not scattered through hero code
#   - Damage goes through DamageCalculator when applied (see subclasses)
# The SkillData resource is shared — cooldown state lives on the hero in a
# parallel Array[float], not on the resource itself.

enum TargetType { SINGLE, AREA, SELF }

@export var skill_name: String = "Skill"
@export var skill_id: String = ""
# 0 = use hero.data.attack_range at cast time.
@export var skill_range: float = 0.0
@export var damage: float = 0.0
@export var damage_type: int = 0  # DamageCalculator.DamageType
@export var cooldown: float = 5.0
@export var target_type: int = TargetType.SINGLE
@export var icon: Texture2D
@export_multiline var description: String = ""


# Subclasses override this with the actual effect. hero is BaseHero,
# target is whatever the targeting mode produced (an enemy, a Vector2 for
# AREA skills, or null for SELF).
func apply(_hero: Node, _target) -> void:
	pass
