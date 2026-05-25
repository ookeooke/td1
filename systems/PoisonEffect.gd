extends "res://systems/StatusEffect.gd"
class_name PoisonEffect

# Damage-over-time, identical mechanic to BurnEffect but distinct status slot
# (id="poison") so a single carrier can stack burn + poison simultaneously
# from different sources. Damage type defaults to TRUE — poison should bypass
# armor AND magic resist (it's biological, not elemental). Carrier ticking
# requirement is the same as BurnEffect: BaseEnemy / BaseSoldier / BaseHero
# call `effect.tick(self, delta)` each frame from their `_tick_effects`.

var dps: float = 0.0
var tick_interval: float = 0.5
var damage_type: int = 2  # DamageCalculator.DamageType.TRUE — poison bypasses everything
var _tick_accumulator: float = 0.0
var source: Node = null


func _init(p_dps: float = 1.5, p_duration: float = 4.0, p_source: Node = null,
		p_damage_type: int = 2, p_tick_interval: float = 0.5) -> void:
	id = "poison"
	dps = maxf(0.0, p_dps)
	duration = maxf(0.0, p_duration)
	source = p_source
	damage_type = p_damage_type
	tick_interval = maxf(0.05, p_tick_interval)


# Reapplication preserves _tick_accumulator — see BurnEffect.refresh for
# the rationale. Same contract: max(dps), max(duration), latest source.
func refresh(new_effect) -> void:
	if new_effect == null:
		return
	if "dps" in new_effect and new_effect.dps > dps:
		dps = new_effect.dps
	if new_effect.duration > duration:
		duration = new_effect.duration
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
