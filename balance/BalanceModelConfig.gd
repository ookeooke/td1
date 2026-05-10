extends Resource
class_name BalanceModelConfig

# Tunable weights for the Supply vs Demand balance model. Lifted out of
# BalanceCalculator constants so designers can adjust without code edits.
# All defaults are 1.0 (or the historical hardcoded value) — never invent
# weights from intuition. Move them only when run-stats data justifies it.
#
# See balance/BALANCE.md "Supply vs Demand" for the model + bands.


# ── Hardness weights (mirror BalanceCalculator constants) ────────────────
@export_group("Hardness")
@export var w_ehp: float = 2.0
@export var w_lives: float = 50.0
@export var w_speed: float = 0.02
@export var ppt_to_hardness_factor: float = 7500.0


# ── Enemy archetype demand multipliers ───────────────────────────────────
# Default 1.0 = parity with the legacy single-axis hardness formula. Move
# only once the predicted-vs-observed report shows a class of levels
# drifting in the same direction (e.g. flying-heavy levels under-rated).
@export_group("Enemy Archetype Demand Weights")
@export_range(0.0, 5.0, 0.05) var flying_demand_weight: float = 1.0
@export_range(0.0, 5.0, 0.05) var armored_demand_weight: float = 1.0
@export_range(0.0, 5.0, 0.05) var magic_resist_demand_weight: float = 1.0
# Boss is 1.5 by default — mass-of-EHP that arrives in a single life makes
# kill_window pressure spike compared to the same EHP spread across grunts.
@export_range(0.0, 5.0, 0.05) var boss_demand_weight: float = 1.5
# +25% effective EHP per boss phase — phases gate stat bumps that the
# player has to chew through before progressing.
@export_range(0.0, 1.0, 0.05) var boss_phase_per_phase_bonus: float = 0.25
# Bypass enemies ignore soldier/hero blocking — costs supply via lost
# block_capacity, accounted for here as a flat archetype premium.
@export_range(0.0, 5.0, 0.05) var bypass_demand_weight: float = 1.2
# Threshold for "armored" / "magic-resistant" classification. Authored
# armor values cluster around 0.0 / 0.2 / 0.45 — 0.3 splits cleanly.
@export_range(0.0, 0.95, 0.05) var armor_classify_threshold: float = 0.3
@export_range(0.0, 0.95, 0.05) var magic_resist_classify_threshold: float = 0.3


# ── Enemy ability scoring ─────────────────────────────────────────────────
# Abilities (regen, heal-aura) were previously authored but never scored
# (audit gap). Every healing tick during the wave's kill_window is converted
# to "EHP add" — the player effectively has to do that much more damage to
# remove the wave.
@export_group("Enemy Ability Demand")
@export_range(0.0, 5.0, 0.05) var regen_score_weight: float = 1.0
# Heal-aura affects every nearby ally — approximate the multiplier as
# average affected count; tune from data.
@export_range(0.0, 5.0, 0.05) var heal_aura_score_weight: float = 1.0
@export_range(1, 20, 1) var heal_aura_avg_targets: int = 3
# Enemy attack DPS against blockers is a drain on supply (soldiers/hero
# absorb damage instead of doing damage). Currently only runtime; folded
# into a small block_cost term here.
@export_range(0.0, 5.0, 0.05) var enemy_attack_dps_to_block_cost: float = 1.0


# ── Per-tier tower weights ───────────────────────────────────────────────
# Independent per-tier scalars — the dominant path emerges from data.
# Default 1.0 across the board. Push down if a tier never gets reached in
# practice (e.g. branch picks rarely chosen → set to 0.5).
@export_group("Per-Tier Tower Weights")
@export_range(0.0, 2.0, 0.05) var tier_l1_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var tier_l2_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var tier_l3_linear_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var tier_branch_weight: float = 1.0
# DPS-per-gold reference rate (Archer L1 = 4.8 DPS / 50 g = 0.096). Used
# as the floor when computing supply.
@export_range(0.01, 1.0, 0.001) var dps_per_gold: float = 0.096
# Theoretical DPS rarely lands at 100% in practice — towers spend cycles
# out of range, on dead targets, between projectiles. Community range
# 50-80%. Default 0.65; calibrate per-level from RunStats.damage_by_tower.
@export_range(0.1, 1.0, 0.01) var effective_to_theoretical_dps_ratio: float = 0.65


# ── Player supply segment weights ─────────────────────────────────────────
# Each "segment" is a damage-budget contributor (towers, hero, skills,
# control, blocking). Independent scalars so designers can dial how much
# each segment "counts" without changing the underlying math.
@export_group("Player Supply Segment Weights")
@export_range(0.0, 2.0, 0.05) var segment_tower_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_hero_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_skills_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_control_weight: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_blocking_weight: float = 1.0
# Estimated fraction of level duration the hero spends in combat.
# 0.55 ≈ KR-typical (hero seeks, fights, walks, occasionally dies).
@export_range(0.0, 1.0, 0.05) var hero_active_time_pct: float = 0.55
# Fraction of cooldown windows that are actually cast. <1.0 because the
# player won't always have a useful target ready when CD expires.
@export_range(0.0, 1.0, 0.05) var skill_uptime_pct: float = 0.7


# ── Control conversion (CC as DPS multiplier, NOT flat damage) ───────────
# Industry warning (SMITE diminishing returns, etc.): converting CC to
# flat damage stacks to infinity. Instead, model CC as multiplying the DPS
# applied to the affected enemy DURING the CC window, capped by stack_cap.
@export_group("Control Conversion")
# An enemy under slow takes effectively this many times the DPS it would
# absorb un-slowed (towers get more shots per pass).
@export_range(1.0, 3.0, 0.05) var slow_dps_multiplier: float = 1.5
@export_range(1.0, 5.0, 0.05) var stun_dps_multiplier: float = 2.0
# Max fraction of kill_window that can be under CC — saturation guard.
@export_range(0.0, 1.0, 0.05) var control_stack_cap: float = 0.6


# ── Safety bands (color thresholds) ───────────────────────────────────────
# safety_ratio = total_supply / total_demand. Bands match the user's spec:
#   < red_max     impossible/tight
#   red..orange   very hard
#   orange..green good challenge
#   green..blue   comfortable
#   > blue_max    too easy / boring
@export_group("Safety Bands")
@export_range(0.0, 5.0, 0.05) var safety_ratio_red_max: float = 1.0
@export_range(0.0, 5.0, 0.05) var safety_ratio_orange_max: float = 1.15
@export_range(0.0, 5.0, 0.05) var safety_ratio_green_max: float = 1.4
@export_range(0.0, 5.0, 0.05) var safety_ratio_blue_max: float = 2.0


# ── Density weight ───────────────────────────────────────────────────────
# Same total EHP feels harder when packed into a tighter spawn window
# (no time to retarget, AoE less efficient). Multiplier on density when
# computing the swarm sub-ratio.
@export_group("Density")
@export_range(0.0, 5.0, 0.05) var density_pressure_weight: float = 1.0

# ── Barracks balance ─────────────────────────────────────────────────────
# Reference incoming DPS used by the barracks block-uptime formula:
#   uptime = HP / (HP + respawn × ref_dps)
# 5.0 dmg/s ≈ a single basic enemy in melee (community baseline). Tune
# upward for armored-heavy levels where soldiers face more incoming damage.
@export_group("Barracks")
@export_range(0.0, 50.0, 0.5) var ref_enemy_dps_vs_soldier: float = 5.0


# Convenience: returns the default config when no .tres is provided. Used
# as a safe fallback so callers never crash on null.
static func defaults() -> BalanceModelConfig:
	return BalanceModelConfig.new()
