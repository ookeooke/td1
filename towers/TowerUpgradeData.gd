extends Resource
class_name TowerUpgradeData

# Phase 24: per-level upgrade data for attack towers. Sits in
# TowerData.level_upgrades[], index 0 = L2, index 1 = L3. Phase 25 will
# use this same Resource type for branch choices (Ranger vs. Musketeer)
# by putting two TowerUpgradeData instances at the L3 slot.
#
# Each entry fully overrides the level's damage/range/speed rather than
# stacking multipliers — easier to balance-tune in the Inspector, and
# Phase 25 branches want totally different stat profiles anyway.

@export var upgrade_name: String = ""
@export var damage: float = 0.0
@export var attack_range: float = 0.0
@export var attack_speed: float = 0.0
@export var cost: int = 0  # gold to reach this level from the previous level
@export var sell_value: int = 0  # refund after buying this upgrade
# On-hit ability list for projectiles at this level — reserved for future
# general-purpose on-hit composition (pierce, chain, etc.). Phase 41 polish
# generalizes on-hit to this list. For Phase 25 branching, the common
# cases (slow, stun) have dedicated fields below so we don't need to
# instantiate RefCounted StatusEffects through the ability pipeline yet.
@export var on_hit_abilities: Array[Resource] = []
# Phase 25 branch-specific on-hit status effects per projectile. Leave at
# 0 for branches that just boost raw stats (Musketeer).
@export_range(0.0, 1.0) var on_hit_slow_factor: float = 0.0
@export var on_hit_slow_duration: float = 0.0
@export var on_hit_stun_duration: float = 0.0
# Placeholder tint for the tower body — gives a visual read on upgrade
# level until Phase 41 polish introduces real per-level sprites.
@export var tint: Color = Color.WHITE

# Barracks-only overrides. Null / 0 means "inherit from base TowerData".
@export var soldier_data_override: Resource = null
@export var soldier_rally_range: float = 0.0


# Post-upgrade stats row used by the radial menu's upgrade-preview card.
# Reads own fields; falls back to the base TowerData when a field is 0 /
# null (matching _level_override() inheritance in BaseTower/TowerBarracks).
func get_stats_line(base: TowerData) -> String:
	if base != null and base.is_barracks():
		var sd: Resource = soldier_data_override if soldier_data_override != null else base.soldier_data
		var rally: float = soldier_rally_range if soldier_rally_range > 0.0 else base.soldier_rally_range
		return "Rally %d   Squad %d   HP %d" % [
			int(rally),
			int(sd.max_count),
			int(sd.max_health),
		]
	var dmg: float = damage if damage > 0.0 else (base.damage if base != null else 0.0)
	var rng: float = attack_range if attack_range > 0.0 else (base.attack_range if base != null else 0.0)
	var spd: float = attack_speed if attack_speed > 0.0 else (base.attack_speed if base != null else 0.0)
	return "Dmg %d   Rng %d   Spd %.1f" % [int(dmg), int(rng), spd]


# Structured post-upgrade stats for the diff-card. Mirrors the shape of
# BaseTower.get_preview_stats / TowerBarracks.get_preview_stats so the card
# can zip rows by label and render color-coded gains/losses.
func get_preview_stats(base: TowerData) -> Array:
	if base != null and base.is_barracks():
		var sd: Resource = soldier_data_override if soldier_data_override != null else base.soldier_data
		var rally: float = soldier_rally_range if soldier_rally_range > 0.0 else base.soldier_rally_range
		var squad: float = float(sd.max_count) if sd != null else 0.0
		var hp: float = float(sd.max_health) if sd != null else 0.0
		var dmg_s: float = float(sd.damage) if sd != null and "damage" in sd else 0.0
		var rows_b: Array = [
			{"label": "Rally", "value": rally, "fmt": "%d"},
			{"label": "Squad", "value": squad, "fmt": "%d"},
			{"label": "HP", "value": hp, "fmt": "%d"},
		]
		if dmg_s > 0.0:
			rows_b.append({"label": "Dmg", "value": dmg_s, "fmt": "%d"})
		return rows_b
	var dmg: float = damage if damage > 0.0 else (base.damage if base != null else 0.0)
	var rng: float = attack_range if attack_range > 0.0 else (base.attack_range if base != null else 0.0)
	var spd: float = attack_speed if attack_speed > 0.0 else (base.attack_speed if base != null else 0.0)
	var aoe: float = base.aoe_radius if base != null else 0.0
	var rows: Array = [
		{"label": "Dmg", "value": dmg, "fmt": "%d"},
		{"label": "Rng", "value": rng, "fmt": "%d"},
		{"label": "Spd", "value": spd, "fmt": "%.1f"},
	]
	if aoe > 0.0:
		rows.append({"label": "AoE", "value": aoe, "fmt": "%d"})
	# Phase 47d-6: post-upgrade slow/stun inherits from base TowerData when
	# the upgrade doesn't override, matching _build_on_hit_effect's fallback.
	# Keeps the diff card honest for towers whose slow is a base trait
	# (Ice Tower) rather than an upgrade trait (Ranger branch).
	var eff_slow_f: float = on_hit_slow_factor if on_hit_slow_factor > 0.0 else (base.on_hit_slow_factor if base != null else 0.0)
	var eff_slow_d: float = on_hit_slow_duration if on_hit_slow_duration > 0.0 else (base.on_hit_slow_duration if base != null else 0.0)
	var eff_stun: float = on_hit_stun_duration if on_hit_stun_duration > 0.0 else (base.on_hit_stun_duration if base != null else 0.0)
	if eff_slow_f > 0.0:
		rows.append({"label": "Slow", "value": eff_slow_f * 100.0, "fmt": "%d%%"})
		rows.append({"label": "SlowT", "value": eff_slow_d, "fmt": "%.1fs"})
	if eff_stun > 0.0:
		rows.append({"label": "Stun", "value": eff_stun, "fmt": "%.1fs"})
	return rows
