extends Node2D
class_name Trap

# Phase 5 — a placed trap/mine/totem. Script-driven (no .tscn) so it's
# fully unit-testable headless. Lifecycle:
#   arm_time elapses → armed → first engageable-ground enemy in radius →
#   detonate (AoE damage all ground enemies in radius via DamageCalculator)
#   → _die(). Auto-despawns at lifetime even if never triggered.
#
# Damage routes through DamageCalculator (CORE RULE 6). Targeting reuses the
# shared BaseEnemy.is_engageable_ground() gate — flyers are never hit and
# the check is NOT re-derived (Blocker invariant #1). Group scan is throttled
# to _SCAN_INTERVAL (never every physics frame — mobile perf rule), mirroring
# HealAuraAbility's ON_INTERVAL cadence.

const _SCAN_INTERVAL: float = 0.15

var data: TrapData = null
var _summoner: Node = null            # hero that placed it (XP routing parity)
var _age: float = 0.0
var _scan_accum: float = 0.0
var _armed: bool = false
var _spent: bool = false


func setup(trap_data: TrapData, summoner: Node = null) -> void:
	data = trap_data
	_summoner = summoner


func _physics_process(delta: float) -> void:
	if data == null or _spent:
		return
	tick(delta)


# Pure-ish stepper (also callable from tests without a SceneTree). Advances
# age, arms after arm_time, despawns at lifetime, throttle-scans the enemy
# group for a proximity trigger.
func tick(delta: float) -> void:
	if data == null or _spent:
		return
	_age += delta
	if not _armed and _age >= data.arm_time:
		_armed = true
	if _age >= data.lifetime:
		_die()
		return
	if not _armed or data.trigger_kind != TrapData.TriggerKind.PROXIMITY:
		return
	_scan_accum += delta
	if _scan_accum < _SCAN_INTERVAL:
		return
	_scan_accum = 0.0
	if not is_inside_tree():
		return
	var hits: Array = _engageable_in_radius(get_tree().get_nodes_in_group("enemies"))
	if not hits.is_empty():
		detonate(hits)


# Pure filter: enemies within radius that a melee threat could hit. Reuses
# the SHARED is_engageable_ground() gate (never re-derived — invariant #1);
# flyers excluded exactly like every melee path.
func _engageable_in_radius(enemies: Array) -> Array:
	var out: Array = []
	if data == null:
		return out
	var r2: float = data.radius * data.radius
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("is_engageable_ground") or not e.is_engageable_ground():
			continue
		if global_position.distance_squared_to(e.global_position) <= r2:
			out.append(e)
	return out


# Apply AoE damage to every passed enemy then expire (one-shot mine).
# Passes RAW damage to take_damage — BaseEnemy.take_damage runs
# DamageCalculator.calculate_damage internally (CORE RULE 6); pre-applying
# it here would double-resist. `enemies` is pre-filtered by
# _engageable_in_radius; tests pass an explicit array.
func detonate(enemies: Array) -> void:
	if _spent or data == null:
		return
	_spent = true
	for e in enemies:
		if e == null or not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		e.take_damage(data.damage, data.damage_type, _summoner)
	_die()


func _die() -> void:
	if not is_queued_for_deletion():
		queue_free()
