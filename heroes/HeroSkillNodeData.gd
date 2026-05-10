extends Resource
class_name HeroSkillNodeData

# Phase 1 — one node in a hero's skill tree.
# Every progression purchase the player can make on a hero is a node. Authored
# as a sub_resource inside the hero's HeroSkillTreeData.tres.
#
# Replaces the legacy TalentData system (Phase 40) — talents migrate into
# PASSIVE_RANK nodes during the save-version bump.

enum Kind {
	ACTIVE_RANK,    # rank 1/2/3 of an active skill (scaling lives on SkillData.rank_scaling)
	PASSIVE_RANK,   # rank 1/2/3 of a passive skill (each rank's ability stacks via AbilityHost)
	MOD,            # sidegrade modifier attached to an active skill
	SLOT_UNLOCK,    # opens an equip slot (passive_slot_2, active_slot_3, passive_slot_3)
	CAPSTONE,       # L10 endgame node
}

@export var node_id: String = ""                  # stable, unique within tree, never rename
@export var node_name: String = ""
@export_multiline var description: String = ""
@export var kind: int = Kind.PASSIVE_RANK
# Which inner content id this node operates on:
# - PASSIVE_RANK → passive_id (matches a stable string the hero authors)
# - ACTIVE_RANK / MOD → skill_id (matches SkillData.skill_id)
# - SLOT_UNLOCK → slot key, e.g. "passive_slot_2" / "active_slot_3"
# - CAPSTONE → empty
@export var target_id: String = ""
# Which rank (1, 2, 3) this node grants. For MOD / SLOT_UNLOCK / CAPSTONE
# this is always 1.
@export var rank: int = 1
@export var point_cost: int = 1
@export var level_required: int = 1
# Node ids that must already be purchased (rank > 0) before this one becomes
# available. Empty array = no prerequisites.
@export var prerequisite_ids: Array[String] = []
# AbilityData applied when this node is active:
# - PASSIVE_RANK: pushed onto AbilityHost when the passive is equipped AND
#   the parent node's rank is purchased. Ranks stack — buying R1 + R2 pushes
#   both abilities, so R2 can be a flat extension (+heal_amount) without
#   needing to re-author R1's effect.
# - MOD: pushed onto the active skill at compose time (Phase 2).
# - CAPSTONE: always-on once purchased.
# - ACTIVE_RANK / SLOT_UNLOCK: null. Rank scaling lives on SkillData; slot
#   unlocks are gating-only.
@export var ability: Resource = null
