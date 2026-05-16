extends Resource
class_name HeroLevelCurveData

# Per-hero level pacing. Authored on HeroData.level_curve. ALL defaults
# reproduce the pre-Phase-2 hardcoded behavior EXACTLY, so a hero with no
# curve (level_curve == null → BaseHero/MetaProgression fall back to these
# same numbers) is byte-identical to before.
#
# - health_pct_per_level / damage_pct_per_level: linear growth multiplier
#   applied in BaseHero.compute_base_stats (was const LEVEL_*_GROWTH).
# - skill_points_by_level: level:int → points granted AT that level. Empty
#   ⇒ +1 per level-up from level 2 (the historical rule). A level absent
#   from a non-empty dict still grants the historical +1 (only override the
#   levels you want to differ).
# - active_slot_unlock_levels: hero levels at which an active-skill slot
#   opens. Default [1, 8] == LoadoutState.ACTIVE_SLOT_UNLOCK_LEVELS.
# - affinity_rank_by_level: level:int → affinity rank (Phase 1
#   HeroItemAffinityData.min_affinity_rank gate). Empty ⇒ rank 1 always
#   (every rank-1 affinity always-on, higher ranks dormant — Phase 1 default).
#
# CORE RULE 20: rank/points derived from level via this resource, never a
# per-hero variable; no save reshape (all runtime-derived).

@export var health_pct_per_level: float = 0.15
@export var damage_pct_per_level: float = 0.10
@export var attack_speed_pct_per_level: float = 0.0
@export var armor_flat_every_n_levels: float = 0.0
@export var skill_points_by_level: Dictionary = {}
@export var active_slot_unlock_levels: Array[int] = [1, 8]
@export var affinity_rank_by_level: Dictionary = {}


# Points granted when the hero reaches `lvl` (>=2). Empty dict ⇒ historical
# +1. Non-empty ⇒ authored override for listed levels, +1 for the rest.
func points_for_level(lvl: int) -> int:
	if lvl <= 1:
		return 0
	if skill_points_by_level.has(lvl):
		return int(skill_points_by_level[lvl])
	return 1


# Affinity rank at a given hero level. Empty dict ⇒ rank 1 (Phase 1 default).
# Otherwise the highest authored threshold <= lvl.
func affinity_rank_for_level(lvl: int) -> int:
	if affinity_rank_by_level.is_empty():
		return 1
	var rank: int = 1
	for threshold in affinity_rank_by_level.keys():
		if lvl >= int(threshold):
			rank = maxi(rank, int(affinity_rank_by_level[threshold]))
	return rank
