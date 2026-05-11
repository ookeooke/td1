extends SkillData
class_name MarkedShotSkillData

# Phase 3L — Ranger SINGLE-target skill. Tap an enemy within skill_range to
# paint it; while painted, every damage source (hero, towers, soldiers) deals
# more damage to that one enemy. The mark expires after `mark_duration` or
# when the enemy dies — whichever first.
#
# Reuses the existing SINGLE-target SkillBar flow: _on_skill_button_pressed
# arms targeting, _input picks an enemy at the tap, cast_skill(idx, enemy)
# invokes apply(hero, enemy, ctx).

const _MarkedEffectScript: Script = preload("res://systems/MarkedEffect.gd")

@export var damage_taken_mult: float = 1.4
@export var mark_duration: float = 6.0


func apply(hero: Node, target, ctx: Dictionary = {}) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if target == null or not is_instance_valid(target):
		return
	# Phase 3L — rank/mod ctx scaling. Marked Shot reads:
	#   damage_mult   → mark's damage_taken_mult amplitude
	#   duration_mult → how long the mark lingers
	var eff_mult: float = damage_taken_mult * float(ctx.get("damage_mult", 1.0))
	var eff_dur: float = mark_duration * float(ctx.get("duration_mult", 1.0))
	# Apply mark via the standard status-effect pipeline. The target must be
	# a BaseEnemy (or anything implementing apply_status_effect) — bosses /
	# heroes / soldiers are silently ignored if they don't have the method.
	if not target.has_method("apply_status_effect"):
		return
	target.apply_status_effect(_MarkedEffectScript.new(eff_mult, eff_dur))
	print("[Skill/Marked] %s marked %s for %.1fs (×%.2f damage)" % [
		hero.data.hero_name if hero.data != null else "?",
		target.name,
		eff_dur,
		eff_mult,
	])
