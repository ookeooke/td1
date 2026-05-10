extends Resource
class_name SkillModData

# Phase 2C — sidegrade modifier attached to one active skill. Authored as
# a sub_resource on a HeroSkillNodeData of kind=MOD; the node's `target_id`
# carries the parent skill_id.
#
# At cast time, the chosen mod's `scaling` dict is merged into the rank-
# scaling ctx that BaseHero passes to SkillData.apply(). Skills only read
# what they understand: ShieldBashSkillData reads damage_mult and
# aoe_radius_mult; other subclasses ignore those keys today.
#
# Sidegrade discipline (CLAUDE.md plan): a mod must trade off, never strictly
# upgrade. Authoring rule: every mod's scaling Dictionary should contain at
# least one positive AND one negative key (e.g. cooldown_mult: 1.3 paired
# with damage_mult: 0.7). Pure-buff mods kill the "build choice" pressure.

@export var mod_id: String = ""                  # stable, unique within tree
@export var mod_name: String = ""
@export_multiline var description: String = ""
# Keys merged into the cast-time ctx. `*_mult` keys multiply with rank
# scaling; other keys take last-wins (mod overrides rank). Common keys:
#   damage_mult, cooldown_mult, aoe_radius_mult, count_mult, duration_mult.
@export var scaling: Dictionary = {}
