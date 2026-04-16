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

const BOSS_HP_BAR_SIZE: Vector2 = Vector2(50.0, 6.0)
const BOSS_HP_BAR_Y: float = -36.0
const BOSS_BODY_RADIUS: float = 22.0


func _ready() -> void:
	super._ready()
	if data != null and "boss_phases" in data:
		boss_phases = data.boss_phases
	# Sort phases by threshold descending so we check highest first.
	boss_phases.sort_custom(func(a, b): return a.hp_threshold > b.hp_threshold)
	_check_phase_transition()


func take_damage(amount: float, type: int, source: Node = null) -> void:
	super.take_damage(amount, type, source)
	if state != State.DYING:
		_check_phase_transition()


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
		queue_redraw()
		return
	var phase: Resource = boss_phases[idx]
	_phase_damage_mult = phase.damage_mult
	_phase_speed_mult = phase.speed_mult
	_phase_tint = phase.tint
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
	if _blocker == null or not is_instance_valid(_blocker) or data == null:
		release_combat()
		return
	_combat_cooldown -= delta
	if _combat_cooldown > 0.0:
		return
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	if _blocker.has_method("take_damage"):
		_blocker.take_damage(
			data.attack_damage * _phase_damage_mult,
			DamageCalculator.DamageType.PHYSICAL, self
		)


func _draw() -> void:
	# Larger body with phase tint.
	var body_color: Color = Color(0.6, 0.15, 0.15) * _phase_tint
	draw_circle(Vector2.ZERO, BOSS_BODY_RADIUS, body_color)
	draw_arc(Vector2.ZERO, BOSS_BODY_RADIUS, 0, TAU, 32, Color(0.2, 0.05, 0.05), 3.0)
	# Crown/horns indicator.
	draw_line(Vector2(-10, -BOSS_BODY_RADIUS), Vector2(-6, -BOSS_BODY_RADIUS - 10), Color(0.9, 0.8, 0.2), 2.5)
	draw_line(Vector2(10, -BOSS_BODY_RADIUS), Vector2(6, -BOSS_BODY_RADIUS - 10), Color(0.9, 0.8, 0.2), 2.5)
	# Status rings.
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, 32.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
	_draw_boss_health_bar()


# Boss health bar is ALWAYS visible (even at full HP) and larger than
# regular enemy bars.
func _draw_boss_health_bar() -> void:
	if data == null or data.max_health <= 0:
		return
	var pct: float = clampf(float(current_health) / float(data.max_health), 0.0, 1.0)
	var origin: Vector2 = Vector2(-BOSS_HP_BAR_SIZE.x * 0.5, BOSS_HP_BAR_Y)
	draw_rect(Rect2(origin, BOSS_HP_BAR_SIZE), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		var fill_color: Color = Color(0.9, 0.2, 0.2) if pct < 0.25 else Color(0.3, 0.9, 0.3)
		draw_rect(Rect2(origin, Vector2(BOSS_HP_BAR_SIZE.x * pct, BOSS_HP_BAR_SIZE.y)), fill_color)
	draw_rect(Rect2(origin, BOSS_HP_BAR_SIZE), Color(0, 0, 0), false, 1.0)
	# Phase markers on the health bar.
	for phase in boss_phases:
		var marker_x: float = origin.x + BOSS_HP_BAR_SIZE.x * phase.hp_threshold
		draw_line(
			Vector2(marker_x, BOSS_HP_BAR_Y - 1),
			Vector2(marker_x, BOSS_HP_BAR_Y + BOSS_HP_BAR_SIZE.y + 1),
			Color(1, 1, 1, 0.6), 1.0
		)
