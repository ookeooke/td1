extends BaseEnemy
class_name BaseBoss

# Phase 38: multi-phase boss. Justified subclass per Rule 11 — bosses
# have a fundamentally different control loop (phase transitions on HP
# thresholds, stat scaling per phase, ability swaps, always-visible
# health bar, larger visual).
#
# Phases are BossPhaseData resources listed in `boss_phases` on the
# EnemyData. Sorted by hp_threshold descending — first phase whose
# threshold the boss's HP% drops below becomes active.

const _AbilityDataScript2 := preload("res://systems/AbilityData.gd")

var boss_phases: Array[Resource] = []
var _current_phase_idx: int = -1
var _phase_damage_mult: float = 1.0
var _phase_speed_mult: float = 1.0
var _phase_tint: Color = Color.WHITE
# Abilities pushed by the current phase — tracked so they can be popped
# on phase transition.
var _phase_abilities: Array[Resource] = []

const BOSS_HP_BAR_SIZE: Vector2 = Vector2(125.0, 15.0)
const BOSS_HP_BAR_Y: float = -90.0
const BOSS_BODY_RADIUS: float = 22.0


func _ready() -> void:
	super._ready()
	if data != null and "boss_phases" in data:
		boss_phases = data.boss_phases
	# Sort phases by threshold descending so we check highest first.
	boss_phases.sort_custom(func(a, b): return a.hp_threshold > b.hp_threshold)
	_check_phase_transition()


func take_damage(amount: float, type: int, source: Node = null) -> float:
	var final: float = super.take_damage(amount, type, source)
	if state != State.DYING:
		_check_phase_transition()
	return final


func _check_phase_transition() -> void:
	if data == null or boss_phases.is_empty():
		return
	var hp_frac: float = float(current_health) / float(data.max_health)
	var new_idx: int = -1
	for i in boss_phases.size():
		if hp_frac <= boss_phases[i].hp_threshold:
			new_idx = i
	if new_idx == _current_phase_idx:
		return
	_transition_to_phase(new_idx)


func _transition_to_phase(idx: int) -> void:
	# Remove abilities from the old phase.
	if _ability_host != null:
		for a in _phase_abilities:
			_ability_host.remove_ability(a)
	_phase_abilities.clear()
	_current_phase_idx = idx
	if idx < 0 or idx >= boss_phases.size():
		_phase_damage_mult = 1.0
		_phase_speed_mult = 1.0
		_phase_tint = Color.WHITE
		modulate = Color.WHITE
		queue_redraw()
		return
	var phase: Resource = boss_phases[idx]
	_phase_damage_mult = phase.damage_mult
	_phase_speed_mult = phase.speed_mult
	_phase_tint = phase.tint
	# Apply phase tint via modulate so the shared drawer (multi-part body)
	# inherits it without needing a tint-aware signature. Health bar /
	# status rings absorb the same tint, which is acceptable.
	modulate = _phase_tint
	# Push new phase abilities.
	if _ability_host != null:
		for a in phase.abilities:
			_ability_host.add_ability(a)
			_phase_abilities.append(a)
	queue_redraw()
	print("[Boss] %s entered phase '%s' (idx %d)" % [
		data.enemy_name if data != null else "?",
		phase.phase_name, idx,
	])


func _effective_speed() -> float:
	return super._effective_speed() * _phase_speed_mult


func _combat_tick(delta: float) -> void:
	_prune_blockers()
	if _blockers.is_empty() or data == null:
		release_combat()
		return
	_combat_cooldown -= delta
	if _combat_cooldown > 0.0:
		return
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	var focus: Node = _blockers[0]
	if focus != null and is_instance_valid(focus) and focus.has_method("take_damage"):
		focus.take_damage(
			data.attack_damage * _phase_damage_mult,
			DamageCalculator.DamageType.PHYSICAL, self
		)


func _draw() -> void:
	# Delegate the full body pipeline (shadow, slow-ghost, walk-bob, breath,
	# flinch, hit flash, stun stars, status rings, attack telegraph) to
	# BaseEnemy._draw. Boss-specific HP bar comes from the overridden
	# _draw_health_bar() below. Phase tint propagates via self.modulate
	# (set in _check_phase_transition).
	super._draw()


# Override BaseEnemy._draw_health_bar so the always-visible, larger boss
# bar replaces the regular hidden-at-full-HP bar without duplicating draws.
func _draw_health_bar() -> void:
	_draw_boss_health_bar()


# Boss health bar is ALWAYS visible (even at full HP) and larger than
# regular enemy bars.
func _draw_boss_health_bar() -> void:
	if data == null or data.max_health <= 0:
		return
	var zs: float = _get_zoom_scale()
	var bar_size: Vector2 = BOSS_HP_BAR_SIZE * zs
	# Boss has a head above the torso when race != NONE — push the bar above
	# both. minf picks the more-negative (higher on screen) value.
	var bar_y_local: float = BOSS_HP_BAR_Y
	if data.visual != null and data.visual.race != UnitVisualData.Race.NONE:
		var head_top: float = data.visual.head_y_offset * data.visual.radius - data.visual.head_radius_ratio * data.visual.radius
		bar_y_local = minf(BOSS_HP_BAR_Y, head_top - 14.0)
	var bar_y: float = bar_y_local * zs
	var pct: float = clampf(float(current_health) / float(data.max_health), 0.0, 1.0)
	var origin: Vector2 = Vector2(-bar_size.x * 0.5, bar_y)
	draw_rect(Rect2(origin, bar_size), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		var fill_color: Color = Color(0.9, 0.2, 0.2) if pct < 0.25 else Color(0.3, 0.9, 0.3)
		draw_rect(Rect2(origin, Vector2(bar_size.x * pct, bar_size.y)), fill_color)
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0), false, 1.0)
	# Phase markers on the health bar.
	for phase in boss_phases:
		var marker_x: float = origin.x + bar_size.x * phase.hp_threshold
		draw_line(
			Vector2(marker_x, bar_y - 1),
			Vector2(marker_x, bar_y + bar_size.y + 1),
			Color(1, 1, 1, 0.6), 1.0
		)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
