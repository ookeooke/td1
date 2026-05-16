extends AbilityData
class_name WeaponProfileAbility

# Pure-B attack spine: a WEAPON-slot item carries this on implicit_abilities
# to OWN the hero's attack — melee vs ranged, projectile, reach, damage type.
# When equipped it overrides the hero's HeroData attack fields; when no
# profile is active every read falls back to HeroData (the "unarmed"
# baseline). With zero WeaponProfileAbility authored anywhere, behavior is
# byte-identical (BaseHero._profile_* helpers all fall back to data.*).
#
# Lifecycle mirrors StatModifierAbility: ON_EQUIP registers, ON_UNEQUIP
# clears. Owner-agnostic per CORE RULE 11 — guarded by has_method so a
# non-hero owner is simply ignored.
#
# Sentinels (so "unset" never collides with a real value):
#   projectile_scene == null → MELEE weapon
#   weapon_attack_range  <= 0 → keep hero attack_range
#   weapon_damage_type   <  0 → inherit hero damage_type
#   weapon_base_damage   <= 0 → keep hero base damage
#   weapon_attack_speed  <= 0 → keep hero attack_speed
#   close_attack_*  0/0/-1   → keep hero close-attack profile
#
# Damage is BASE-REPLACE, not additive: BaseHero applies the StatModifier
# affix stack via a ratio so item +damage% is never double-counted (see
# BaseHero._profile_damage).

@export var projectile_scene: PackedScene = null
@export var weapon_attack_range: float = 0.0
@export var weapon_damage_type: int = -1
@export var weapon_base_damage: float = 0.0
@export var weapon_attack_speed: float = 0.0
@export var close_attack_damage: float = 0.0
@export var close_attack_speed: float = 0.0
@export var close_attack_damage_type: int = -1


func apply(owner: Node, ctx: Dictionary) -> void:
	if owner == null:
		return
	if not (owner.has_method("set_weapon_profile") and owner.has_method("clear_weapon_profile")):
		return
	# Attachment paths: AbilityHost.equip_ability (items) → ctx.phase=ON_EQUIP;
	# AbilityHost.add_ability (ON_SPAWN passive) → ctx empty. Only ON_UNEQUIP
	# clears; anything else registers (set_weapon_profile is idempotent / last-
	# wins so re-registering on respawn is safe).
	var phase: int = int(ctx.get("phase", -1))
	if phase == Trigger.ON_UNEQUIP:
		owner.clear_weapon_profile(self)
	else:
		owner.set_weapon_profile(self)


# AbilityHost.tick() calls this when duration > 0 and the ability ages out
# (e.g. a temporary weapon-swap buff). Without it the profile would leak
# after the ability is removed from the host.
func _on_expired(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if owner.has_method("clear_weapon_profile"):
		owner.clear_weapon_profile(self)
