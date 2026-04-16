extends Area2D
class_name BaseEnemy

enum State { WALKING, STUNNED, COMBAT, STEALTHED, DYING }

const HP_BAR_SIZE: Vector2 = Vector2(28.0, 4.0)
const HP_BAR_Y_OFFSET: float = -26.0

@export var data: EnemyData

var state: int = State.WALKING
var current_health: int = 0

var _path_follow: PathFollow2D
var _path_id: String = ""

# Active status effects keyed by id ("slow", "stun"). Reapplying the same id
# replaces the prior effect (refreshes duration / takes stronger value).
var _effects: Dictionary = {}

# Combat engagement — set by soldiers calling engage_combat(self).
var _blocker: Node = null
var _combat_cooldown: float = 0.0

# Last source that dealt damage — used by _die() to award XP to the hero
# when the hero landed the killing blow (last-hit semantics). Towers get
# gold, not XP.
var _last_damage_source: Node = null

# Phase 20.5: per-unit ability dispatcher. Populated from data.abilities
# in _ready(); ticked each physics frame; triggered on death so
# abilities like ExplodeOnDeath or SummonOnDeath can hook in.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
var _ability_host: RefCounted = null


func _ready() -> void:
	if data:
		current_health = data.max_health
	# Phase 20: group membership so skill targeting can enumerate live
	# enemies without walking the whole tree. get_tree().get_nodes_in_group
	# is only called on tap (targeting), not per-frame — perf rule intact.
	add_to_group("enemies")
	# Phase 20.5: host any abilities attached via EnemyData.abilities.
	# Added after add_to_group so ON_SPAWN abilities that look up
	# group members already see this enemy registered.
	_ability_host = _AbilityHostScript.new(self)
	if data != null:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	queue_redraw()


func setup(path_follow: PathFollow2D, path_id: String) -> void:
	_path_follow = path_follow
	_path_id = path_id


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func _physics_process(delta: float) -> void:
	if _path_follow == null or data == null:
		return
	_tick_effects(delta)
	if _ability_host != null:
		_ability_host.tick(delta)
	match state:
		State.WALKING:
			_path_follow.progress += _effective_speed() * delta
			if _path_follow.progress_ratio >= 1.0:
				_reach_end()
		State.COMBAT:
			_combat_tick(delta)
		State.STUNNED, State.STEALTHED, State.DYING:
			pass


func engage_combat(soldier: Node) -> void:
	if state == State.DYING or soldier == null:
		return
	_blocker = soldier
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed) if data != null else 1.0
	change_state(State.COMBAT)


func release_combat(soldier: Node = null) -> void:
	# If a specific soldier is provided, only release if it matches the
	# current blocker (prevents stale release calls).
	if soldier != null and _blocker != soldier:
		return
	_blocker = null
	_combat_cooldown = 0.0
	if state == State.COMBAT:
		change_state(State.WALKING)


func _combat_tick(delta: float) -> void:
	if _blocker == null or not is_instance_valid(_blocker) or data == null:
		release_combat()
		return
	_combat_cooldown -= delta
	if _combat_cooldown > 0.0:
		return
	_combat_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	if _blocker.has_method("take_damage"):
		_blocker.take_damage(data.attack_damage, DamageCalculator.DamageType.PHYSICAL, self)


func apply_status_effect(effect) -> void:
	# effect: StatusEffect subclass (SlowEffect / StunEffect / etc.)
	# Untyped param so this compiles before Godot indexes systems/*.gd class_names.
	if effect == null or state == State.DYING:
		return
	_effects[effect.id] = effect
	effect.apply(self)
	if effect.id == "stun" and state != State.STUNNED:
		change_state(State.STUNNED)
	queue_redraw()


func _tick_effects(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired: Array[String] = []
	for id in _effects.keys():
		var e = _effects[id]
		e.duration -= delta
		if e.duration <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		var e = _effects[id]
		e.remove(self)
		_effects.erase(id)
		if id == "stun" and state == State.STUNNED:
			change_state(State.WALKING)
	queue_redraw()


func _effective_speed() -> float:
	var s: float = data.move_speed
	if _effects.has("slow"):
		s *= (1.0 - _effects["slow"].slow_factor)
	return s


func take_damage(amount: float, type: int, source: Node = null) -> void:
	if state == State.DYING or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	if source != null:
		_last_damage_source = source
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()


func heal(amount: float) -> void:
	if state == State.DYING or data == null:
		return
	if current_health >= data.max_health:
		return
	var before: int = current_health
	current_health = mini(data.max_health, current_health + int(ceil(amount)))
	if current_health != before:
		queue_redraw()
		print("[Enemy/heal] %s %d → %d" % [data.enemy_name, before, current_health])


func _die() -> void:
	change_state(State.DYING)
	# Last-hit XP: only the hero earns XP, towers don't.
	if _last_damage_source != null and is_instance_valid(_last_damage_source) \
			and _last_damage_source is BaseHero and data.xp_worth > 0:
		_last_damage_source.gain_xp(data.xp_worth)
	# Fire ON_DEATH abilities (explode, summon, buff allies, etc.) BEFORE
	# despawn so they can read our position / iterate the enemies group
	# while we're still valid.
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.enemy_died.emit(self, data.gold_worth)
	_despawn()


func _reach_end() -> void:
	change_state(State.DYING)
	EventBus.enemy_reached_end.emit(self, data.lives_worth)
	_despawn()


func _despawn() -> void:
	if is_instance_valid(_path_follow):
		_path_follow.queue_free()
	queue_free()


func _draw() -> void:
	if data != null and data.visual != null:
		UnitVisualDrawer.draw_unit(self, data.visual)
	else:
		draw_circle(Vector2.ZERO, 14.0, Color(0.75, 0.2, 0.2))
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 24, Color(0.15, 0.05, 0.05), 2.0)
	# Status-effect overlay rings. Stun drawn outermost so it's visible even
	# if a slow is also active.
	var ring_r: float = (data.visual.radius if data != null and data.visual != null else 14.0) + 5.0
	if _effects.has("slow"):
		draw_arc(Vector2.ZERO, ring_r, 0, TAU, 28, Color(0.2, 0.7, 1.0), 3.0)
	if _effects.has("stun"):
		draw_arc(Vector2.ZERO, ring_r + 4.0, 0, TAU, 28, Color(1.0, 0.95, 0.2), 3.0)
	_draw_health_bar()


# Drawn by every enemy subclass at the end of its _draw() override.
# Visible whenever current_health < max_health (plus during the pre-despawn
# redraw, where current_health has just hit 0). Hidden at full HP so an
# untouched enemy is uncluttered.
func _draw_health_bar() -> void:
	if data == null or data.max_health <= 0:
		return
	if current_health >= data.max_health:
		return
	var pct: float = clampf(float(current_health) / float(data.max_health), 0.0, 1.0)
	var origin: Vector2 = Vector2(-HP_BAR_SIZE.x * 0.5, HP_BAR_Y_OFFSET)
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * pct, HP_BAR_SIZE.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0), false, 1.0)
