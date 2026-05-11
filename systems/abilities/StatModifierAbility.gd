extends AbilityData
class_name StatModifierAbility

# Additive + multiplicative stat contributions from equipped items, buffs,
# and talents. Field naming matches BaseHero.recompute_stats()'s convention:
# for each stat key K, `<K>_flat` is added before `<K>_pct` is applied as
# (1 + pct) product. The ability doesn't mutate stats — it joins the owner's
# modifier stack and recompute reads its fields during rebuild.
#
# See CORE RULE 11 (one AbilityData primitive) and plan Design Principle 3
# (Base + ModifierStack, never mutate-and-revert).

@export var max_health_flat: float = 0.0
@export var max_health_pct: float = 0.0
@export var damage_flat: float = 0.0
@export var damage_pct: float = 0.0
@export var armor_flat: float = 0.0
@export var armor_pct: float = 0.0
@export var magic_resist_flat: float = 0.0
@export var magic_resist_pct: float = 0.0
@export var attack_speed_pct: float = 0.0
@export var attack_range_pct: float = 0.0
@export var move_speed_pct: float = 0.0
@export var xp_gain_mult_pct: float = 0.0
@export var skill_power_flat: float = 0.0
@export var skill_power_pct: float = 0.0
@export var health_regen_flat: float = 0.0
# Cooldown reduction stacks additively (5 × 4% = 20%). Stored as a fraction
# in [0..1]; the reader caps at 0.5 so a fully-geared loadout can't free-cast.
@export var cooldown_reduction_flat: float = 0.0


func apply(owner: Node, ctx: Dictionary) -> void:
	if owner == null:
		return
	if not (owner.has_method("register_modifier_source") and owner.has_method("recompute_stats")):
		return
	# Two attachment paths register this ability:
	#   - AbilityHost.equip_ability  (items)    → ctx = {"phase": ON_EQUIP}
	#   - AbilityHost.add_ability    (passives) → ctx = {} when trigger=ON_SPAWN
	# Only ON_UNEQUIP removes. Anything else registers — register_modifier_source
	# short-circuits duplicates so re-registering on respawn is safe.
	var phase: int = int(ctx.get("phase", -1))
	if phase == Trigger.ON_UNEQUIP:
		owner.unregister_modifier_source(self)
		owner.recompute_stats()
		if owner.has_method("_refresh_health_after_modifier_change"):
			owner._refresh_health_after_modifier_change()
	else:
		owner.register_modifier_source(self)
		owner.recompute_stats()
		if owner.has_method("_refresh_health_after_modifier_change"):
			owner._refresh_health_after_modifier_change()


# AbilityHost.tick() calls this when `duration > 0` and the ability ages out.
# Without it, a time-limited stat buff (e.g. Hunter's Stance pushed via
# BuffSkillData) would leak its registration in owner._modifier_sources —
# the ability gets removed from the host's _abilities array, but the modifier
# source persists. Unregister + recompute brings stats back to baseline.
func _on_expired(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if not (owner.has_method("unregister_modifier_source") and owner.has_method("recompute_stats")):
		return
	owner.unregister_modifier_source(self)
	owner.recompute_stats()
	if owner.has_method("_refresh_health_after_modifier_change"):
		owner._refresh_health_after_modifier_change()
