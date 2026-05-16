extends Resource
class_name HeroItemAffinityData

# A hero-platform "weapon-family mastery": when ALL of `required_item_tags`
# are present among the hero's equipped items' `ItemBase.item_tags`, and the
# hero's current affinity rank meets `min_affinity_rank`, the hero gains
# `bonus_abilities` (any AbilityData subclass) — attached/detached through the
# AbilityHost equip lifecycle, mirroring StatModifierAbility.
#
# Authored on HeroData.item_affinities. Off-affinity items still function
# (stats/profile apply); they just never satisfy a required-tag set, so the
# bonus simply isn't granted. CORE RULE 11 (one AbilityData primitive),
# CORE RULE 20 (rank derived from level, never stored).
#
# `min_affinity_rank` is gated by the hero's level curve (Phase 2). Until the
# curve wires rank, every hero is rank 1, so rank-1 affinities are always-on
# and higher-rank ones are simply dormant — backward-compatible by default.

@export var affinity_id: String = ""               # stable, unique; matches filename basename
@export var display_name: String = ""              # player-facing (e.g. "Sword Mastery")
@export var required_item_tags: Array[String] = [] # ALL must be present among equipped item_tags
@export var bonus_abilities: Array[Resource] = []  # AbilityData[] granted while satisfied
@export var min_affinity_rank: int = 1             # hero affinity rank required (Phase 2 curve)
