extends Resource
class_name TowerData

@export var tower_name: String = "Tower"
@export var tower_id: String = ""
@export var requires_unlock: bool = false
# Player Power Tier — see balance/BALANCE.md. Loadout-pick PPT (the slot is
# L1 conceptually); upgrade tiers are NOT factored in here. 1 = baseline
# starter tower, 5 = legendary unlock. LoadoutState.get_effective_ppt()
# averages this across selected_tower_ids.
@export_range(1, 10) var power_tier: int = 1
# Phase 47d-1: scene + icon now live on TowerData so a new tower is a
# single-file add (drop a .tres, register one preload in ContentRegistry).
# `pictogram` is a string key dispatched by TowerIconButton._draw_pictogram;
# multiple towers can share a glyph ("bow" for any archer variant, etc.).
@export var tower_scene: PackedScene
@export var pictogram: String = "generic"

@export var damage: float = 5.0
@export var damage_type: int = 0  # DamageCalculator.DamageType
@export var attack_range: float = 375.0
@export var attack_speed: float = 1.0
@export var cost: int = 50
@export var sell_value: int = 30
@export var targets_flying: bool = false
# AoE splash radius. 0 = single target (arrow). > 0 = projectile splashes
# on hit, damaging all enemies within this radius of the impact point.
@export var aoe_radius: float = 0.0
# Splash damage as a fraction of the primary-target damage. Primary target
# always takes 100 %; secondary targets in the AoE take this share. Default
# 0.5 matches the original hardcoded behavior. Range [0, 1] — values > 1
# would let splash hit harder than the primary, intentionally allowed for
# future weird towers (e.g. resonance bombs) but author at your peril.
@export_range(0.0, 1.0, 0.05) var splash_damage_pct: float = 0.5
# Phase 47d-6: base-level on-hit status effects (applied at L1 before any
# upgrade). Upgrade overrides on TowerUpgradeData still win when set.
# Matches TowerUpgradeData field shape for symmetry.
@export_range(0.0, 1.0) var on_hit_slow_factor: float = 0.0
@export var on_hit_slow_duration: float = 0.0
@export var on_hit_stun_duration: float = 0.0
# Placeholder body color for _draw(). Lets each tower type have a distinct
# visual without per-tower _draw() subclasses.
@export var body_color: Color = Color(0.35, 0.45, 0.75)

# Turret barrel, drawn as a rotated rectangle extending from the body toward
# the current target. Length 0 disables the barrel entirely (use for towers
# that don't aim — none right now, but keeps the door open). Defaults produce
# a visible stub on top of the existing 55px-radius body.
@export_group("Barrel")
@export_range(0.0, 120.0, 1.0) var barrel_length: float = 42.0
@export_range(0.0, 40.0, 1.0) var barrel_width: float = 14.0
# Inset from body center at which the barrel base starts. Keeps the inner
# end hidden under the body outline instead of floating detached.
@export_range(0.0, 60.0, 1.0) var barrel_inset: float = 18.0

# Phase 24: per-level upgrade stats. Index 0 = L2 data, index 1 = L3 data
# (ignored when `level_3_branches` is non-empty — branches take over).
@export var level_upgrades: Array[Resource] = []
# Phase 25: branch choices at level 3. If non-empty, L2 → L3 presents
# these as alternatives and `level_upgrades[1]` is bypassed. Conventional
# layout: index 0 = branch A (e.g. Ranger), index 1 = branch B (Musketeer).
# Nothing forces two branches — 1 here works fine (linear), 3+ would show
# more buttons.
@export var level_3_branches: Array[Resource] = []
# Legacy cost fields — kept for tower data files authored before Phase 24.
# New content should put `cost` on TowerUpgradeData instead. If a .tres has
# both, TowerUpgradeData wins via `_effective_upgrade_cost(level)`.
@export var upgrade_cost_lvl2: int = 0
@export var upgrade_cost_lvl3: int = 0
# Phase 25 branch scene overrides — deferred.
@export var upgrade_a_scene: PackedScene
@export var upgrade_b_scene: PackedScene
@export var upgrade_a_data: Resource
@export var upgrade_b_data: Resource

# Asset reference — per tower; not a "stat" so keeping alongside config.
@export var projectile_scene: PackedScene

# Barracks fields (unused on attack towers). Phase 16.
@export var soldier_scene: PackedScene
@export var soldier_data: Resource
@export var soldier_blocking_offset: Vector2 = Vector2(0, 112.5)
@export var soldier_spread: Vector2 = Vector2(40, 25)
@export var soldier_rally_range: float = 350.0

@export_multiline var encyclopedia_entry: String = ""


# Tower Indicator Interface (CORE RULE 14) — Resource-level accessors used by
# the build ring to preview a tower BEFORE it has been instantiated.

func is_barracks() -> bool:
	return soldier_data != null and soldier_scene != null


# Ring radius shown on the build-ring armed slot. Combat towers use
# attack_range; barracks fall back to rally range (their attack_range is 0).
# Applies the L1 range_mult debug override so the build-ring's range circle
# matches what the live tower will use after spawn (and what get_stats_line
# is already showing). Identity in production via is_active() short-circuit.
func get_preview_range() -> float:
	var rng_mult: float = 1.0
	if tower_id != "":
		var BO = load("res://balance/debug/BalanceOverrides.gd")
		rng_mult = BO.get_tower_mult(tower_id, "l1", "range_mult")
	if attack_range > 0.0:
		return attack_range * rng_mult
	return soldier_rally_range * rng_mult


# Stats-card row for a buildable (not-yet-built) tower. Format mirrors the
# live-tower get_stats_line() so the player sees the same numbers pre-build
# and post-build.
func get_stats_line() -> String:
	# Debug per-tower-tier overrides at L1 — keeps build-ring preview
	# aligned with what the placed tower will actually fire at. Identity
	# (1.0) in production. Lazy-loaded so this Resource isn't pinned to
	# the override module at .tres parse time.
	var dmg_mult: float = 1.0
	var rng_mult: float = 1.0
	var spd_mult: float = 1.0
	if tower_id != "":
		var BO = load("res://balance/debug/BalanceOverrides.gd")
		dmg_mult = BO.get_tower_mult(tower_id, "l1", "damage_mult")
		rng_mult = BO.get_tower_mult(tower_id, "l1", "range_mult")
		spd_mult = BO.get_tower_mult(tower_id, "l1", "speed_mult")
	if is_barracks():
		var sd: Resource = soldier_data
		return "Rally %d   Squad %d   HP %d" % [
			int(soldier_rally_range * rng_mult),
			int(sd.max_count),
			int(sd.max_health),
		]
	return "Dmg %d   Rng %d   Spd %.1f" % [
		int(damage * dmg_mult),
		int(attack_range * rng_mult),
		attack_speed * spd_mult,
	]


# L1 build cost with the BalanceOverrides cost_mult applied. UI display +
# affordability checks must route through this so the icon, stats card, and
# affordability gate read the same number TowerPlacer will actually charge.
# In production BalanceOverrides.is_active() returns false → mult is 1.0 →
# identity. Lazy load() (not preload) per CORE RULE 16.
func get_effective_cost() -> int:
	if tower_id == "":
		return cost
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	var mult: float = BO.get_tower_mult(tower_id, "l1", "cost_mult")
	return int(round(float(cost) * mult))
