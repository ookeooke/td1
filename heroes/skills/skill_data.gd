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
# Player Power Tier — see balance/BALANCE.md. 1 = basic; 5 = ult. Per-skill
# contribution to LoadoutState.get_effective_ppt().
@export_range(1, 10) var power_tier: int = 1
# 0 = use hero.data.attack_range at cast time.
@export var skill_range: float = 0.0
@export var damage: float = 0.0
@export var damage_type: int = 0  # DamageCalculator.DamageType
@export var cooldown: float = 5.0
@export var target_type: int = TargetType.SINGLE
@export var icon: Texture2D
@export_multiline var description: String = ""
# Hero level at which this skill becomes equippable. Default 1 = always
# available. Skills with level_required > hero level appear in the WorldMap
# Skills tab as locked ("Unlocks at Lv X"); only unlocked skills can be
# slotted into the hero's 3 equipped-skill loadout.
@export var level_required: int = 1
# When true, AREA-targeting bypasses the hero range check — player can tap
# anywhere on the map. SkillBar skips the range circle preview and skips
# the in-range gate. Use for "summon"-style skills that drop allies on the
# road far from the hero. Default false = range-locked (existing behavior).
@export var unrestricted_targeting: bool = false

# Phase 2 — per-rank scaling deltas. Index 0 = R2 deltas, index 1 = R3
# deltas. Each entry is a Dictionary with optional keys:
#   cooldown_mult: float — multiplied into the rank's effective cooldown
# Future keys (damage_mult, etc.) require subclass cooperation in apply()
# and will land alongside Phase 2B/C. Empty array = skill doesn't rank up.
@export var rank_scaling: Array[Dictionary] = []


# Subclasses override this with the actual effect. hero is BaseHero,
# target is whatever the targeting mode produced (an enemy, a Vector2 for
# AREA skills, or null for SELF). `ctx` carries rank-scaling and (later)
# mod-context — subclasses that scale on damage / radius / count read keys
# like `ctx.get("damage_mult", 1.0)`. Defaults to {} so older call sites
# without rank context still work.
func apply(_hero: Node, _target, _ctx: Dictionary = {}) -> void:
	pass


# Effective cooldown for a given purchased rank (1..N). Applies cooldown_mult
# from each rank's scaling dict in order — R3 stacks atop R2. Defensive
# clamp so an authored pathological value can't yield zero.
func get_effective_cooldown(rank: int) -> float:
	var c: float = cooldown
	# rank N consumes scaling indices [0, N-2]: R2 → index 0, R3 → indices 0+1.
	for i in maxi(0, rank - 1):
		if i >= rank_scaling.size():
			break
		var entry: Dictionary = rank_scaling[i]
		c *= float(entry.get("cooldown_mult", 1.0))
	return maxf(0.01, c)


# Phase 2B — flatten the per-rank scaling dicts into one merged dict for the
# given purchased rank. `*_mult` keys multiply across ranks (R2 0.85 × R3
# 0.90 → 0.765); other keys take last-wins. Returned dict is safe to pass
# as `ctx` to apply().
func get_effective_scaling(rank: int) -> Dictionary:
	var out: Dictionary = {}
	for i in maxi(0, rank - 1):
		if i >= rank_scaling.size():
			break
		var entry: Dictionary = rank_scaling[i]
		for key in entry:
			if String(key).ends_with("_mult"):
				out[key] = float(out.get(key, 1.0)) * float(entry[key])
			else:
				out[key] = entry[key]
	return out
