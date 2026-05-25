extends "res://systems/StatusEffect.gd"
class_name BurnEffect

# Damage-over-time. Applied to a unit that implements apply_status_effect()
# AND ticks its `_effects` dict (carriers must call BurnEffect.tick(self,
# delta) each frame — see BaseEnemy._tick_effects and the mirrored hooks
# on BaseSoldier / BaseHero). Damage type is MAGIC by default so fire
# bypasses armor (thematic + matches what Kingdom Rush does with elemental
# DoTs).
#
# Carrier responsibility:
#   - Add a "burn" branch to _tick_effects that calls effect.tick(self, delta)
#   - apply_status_effect(burn) when a fire projectile hits.
#
# The effect ticks an internal accumulator and applies damage_per_tick when
# the accumulator crosses tick_interval. Decrements `duration` itself only
# from the carrier's standard _tick_effects loop (carriers subtract delta
# from `duration` and call remove() when <= 0). This mirrors how SlowEffect
# and StunEffect rely on the carrier for duration accounting.

const _DamageCalculatorScript := preload("res://autoloads/DamageCalculator.gd")

var dps: float = 0.0
var tick_interval: float = 0.5
var damage_type: int = 1  # DamageCalculator.DamageType.MAGIC — fire bypasses armor
var _tick_accumulator: float = 0.0
# Source of the burn — typically the enemy archer that fired the arrow. Used
# for damage attribution so RunStats records "killed by goblin_fire_archer"
# rather than an anonymous "burn" source. May be null if the source has
# despawned by the time the tick fires (the archer died before its DoT
# expired) — carriers must handle null sources.
var source: Node = null


func _init(p_dps: float = 2.0, p_duration: float = 3.0, p_source: Node = null,
		p_damage_type: int = 1, p_tick_interval: float = 0.5) -> void:
	id = "burn"
	dps = maxf(0.0, p_dps)
	duration = maxf(0.0, p_duration)
	source = p_source
	damage_type = p_damage_type
	tick_interval = maxf(0.05, p_tick_interval)


# Called by the carrier's _tick_effects each frame. Accumulates time and
# deals damage when the accumulator crosses tick_interval. Damage per tick =
# dps * tick_interval so total damage over `duration` ≈ dps * duration
# regardless of the chosen interval.
# Reapplication: take the strongest DPS and the longest remaining duration,
# but PRESERVE the existing _tick_accumulator so a rapid stream of hits
# can't reset the clock to zero every time and suppress all damage. Before
# this contract, two fire archers shooting one target at <0.5s intervals
# applied zero burn damage — each new hit reset the accumulator before it
# crossed tick_interval. (Code review 2026-05-25.)
func refresh(new_effect) -> void:
	if new_effect == null:
		return
	if "dps" in new_effect and new_effect.dps > dps:
		dps = new_effect.dps
	if new_effect.duration > duration:
		duration = new_effect.duration
	# Source attribution: prefer the latest valid source so kill credit
	# follows the most recent applier when the original archer dies mid-DoT.
	if "source" in new_effect and new_effect.source != null and is_instance_valid(new_effect.source):
		source = new_effect.source


func tick(carrier: Node, delta: float) -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	if not carrier.has_method("take_damage"):
		return
	_tick_accumulator += delta
	if _tick_accumulator < tick_interval:
		return
	_tick_accumulator -= tick_interval
	var dmg: float = dps * tick_interval
	if dmg <= 0.0:
		return
	var attribution: Node = source if (source != null and is_instance_valid(source)) else null
	carrier.take_damage(dmg, damage_type, attribution)
