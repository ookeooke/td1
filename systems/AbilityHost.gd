extends RefCounted
class_name AbilityHost

# Per-unit ability dispatcher. Each unit (enemy / hero / tower / soldier)
# instantiates one AbilityHost in _ready, populates it from data.abilities
# (plus item-granted abilities later), and calls:
#   - tick(delta)               every _physics_process
#   - trigger(event, ctx={})    at specific lifecycle events
#
# Abilities typed as Resource (not AbilityData) to side-step Godot's
# class_name indexing lag on new scripts — runtime duck-typing is
# identical and the field names (`trigger`, `interval`, `apply`) are
# fixed by the AbilityData base contract.

const _AbilityDataScript = preload("res://systems/AbilityData.gd")

var owner: Node
var _abilities: Array[Resource] = []
# Parallel to _abilities — seconds since this ability last fired (ON_INTERVAL only).
var _interval_accum: Array[float] = []
# Parallel to _abilities — seconds elapsed since the ability was added.
# Used for duration > 0 auto-removal.
var _age: Array[float] = []


func _init(unit_owner: Node) -> void:
	owner = unit_owner


func add_ability(ability: Resource) -> void:
	if ability == null:
		return
	_abilities.append(ability)
	_interval_accum.append(0.0)
	_age.append(0.0)
	if ability.trigger == _AbilityDataScript.Trigger.ON_SPAWN:
		_safe_apply(ability, {})


func remove_ability(ability: Resource) -> void:
	var idx: int = _abilities.find(ability)
	if idx < 0:
		return
	_abilities.remove_at(idx)
	_interval_accum.remove_at(idx)
	_age.remove_at(idx)


func tick(delta: float) -> void:
	# Iterate backwards so duration-triggered removals don't skip entries.
	for i in range(_abilities.size() - 1, -1, -1):
		var a: Resource = _abilities[i]
		_age[i] += delta
		if a.trigger == _AbilityDataScript.Trigger.ON_INTERVAL:
			_interval_accum[i] += delta
			if _interval_accum[i] >= a.interval:
				_interval_accum[i] = 0.0
				_safe_apply(a, {})
		if a.duration > 0.0 and _age[i] >= a.duration:
			# Give the ability a chance to run finalization (e.g., kill the
			# owner for a LifetimeAbility / decoy / summon timer) before we
			# detach it. Callback is optional — only called if the subclass
			# defined it.
			if a.has_method("_on_expired"):
				a._on_expired(owner)
			_abilities.remove_at(i)
			_interval_accum.remove_at(i)
			_age.remove_at(i)


func trigger_event(event: int, ctx: Dictionary = {}) -> void:
	for a in _abilities:
		if a.trigger == event:
			_safe_apply(a, ctx)


func _safe_apply(ability: Resource, ctx: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	ability.apply(owner, ctx)
