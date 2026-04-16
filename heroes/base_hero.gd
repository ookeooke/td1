extends CharacterBody2D
class_name BaseHero

# Phase 18: tap-to-move + auto-attack. One hero per level (Phase 30 wires
# selection in HeroRoom). NavigationAgent2D is intentionally skipped this
# phase — Level1 has no obstacles, so straight-line movement is sufficient.
# Switch to NavigationAgent2D once a level introduces blocked tiles.
#
# States:
#   IDLE     → standing, polls AttackRange Area2D for a target each frame
#   MOVING   → walking toward _move_target until inside MOVE_REACHED_TOLERANCE
#   COMBAT   → swinging at _target_enemy on attack_speed cooldown
#   DEAD     → death anim placeholder, ignored by _physics_process
#
# Player taps that don't hit a tower spot or consumed UI cancel any active
# combat and switch to MOVING — explicit move command beats auto-attack.

enum State { IDLE, MOVING, COMBAT, DEAD }

const HP_BAR_SIZE: Vector2 = Vector2(36.0, 5.0)
const HP_BAR_Y_OFFSET: float = -22.0
const MOVE_REACHED_TOLERANCE: float = 4.0
# Tap-to-select hit radius around the hero body (slightly larger than the
# 20×20 visual square so it's finger-friendly).
const SELECT_TAP_RADIUS: float = 22.0
const SELECTION_RING_RADIUS: float = 18.0
# Lunge animation — hero hops a few px toward its target on every attack
# tick and snaps back. Triangle-wave easing computed analytically; no Tween
# node allocated (cheaper, and a new attack just resets the clock).
const LUNGE_DURATION: float = 0.12
const LUNGE_DISTANCE: float = 7.0

@export var data: HeroData

var state: int = State.IDLE
var current_health: int = 0
# Option B selection: tap hero → armed (ring on). Issuing a move command
# (or dying) auto-clears it so a later stray tap doesn't re-move the hero.
var is_selected: bool = false

# Phase 19 — XP / leveling. current_xp resets to 0 after each level-up and
# ticks toward data.xp_per_level[level - 1] (the cost of the next level).
# Per level we add +15% max_health (and heal to full) and +10% damage.
var level: int = 1
var current_xp: int = 0
const LEVEL_HEALTH_GROWTH: float = 0.15
const LEVEL_DAMAGE_GROWTH: float = 0.10

var _move_target: Vector2 = Vector2.ZERO
var _has_move_target: bool = false
var _target_enemy: Node = null
var _attack_cooldown: float = 0.0

var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_t: float = 0.0

# Phase 20: parallel to data.skills — seconds of cooldown remaining per
# slot. Sized in _ready(). The skill resource is shared; only the cooldown
# state is per-hero, which is why it lives here and not on SkillData.
var _skill_cooldowns: Array[float] = []

# Phase 20 targeting overlay — non-zero radius when the SkillBar has an
# armed skill. Drawn as a yellow range circle under the hero so the
# player can see the cast reach. Reset to 0 on cancel / cast.
var _skill_range_preview: float = 0.0

# Phase 20.5: passive-ability dispatcher. Populated from data.abilities in
# _ready; ticked each _physics_process; triggered on hit-dealt/taken/kill/
# death so passives like "on-kill: +5% damage for 3 s" can hook in later.
const _AbilityHostScript := preload("res://systems/AbilityHost.gd")
const _AbilityDataScript := preload("res://systems/AbilityData.gd")
var _ability_host: RefCounted = null

@onready var attack_range_area: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D


func _ready() -> void:
	if data == null:
		push_warning("[BaseHero] missing HeroData")
		return
	current_health = _effective_max_health()
	var atk_circle := CircleShape2D.new()
	atk_circle.radius = data.attack_range
	attack_range_shape.shape = atk_circle
	_skill_cooldowns.resize(data.skills.size())
	_skill_cooldowns.fill(0.0)
	_ability_host = _AbilityHostScript.new(self)
	if "abilities" in data:
		for ability in data.abilities:
			_ability_host.add_ability(ability)
	# Deferred so sibling nodes (HUD, Main) have finished _ready() and
	# connected to hero_spawned before we fire it. Without this, Main.tscn
	# sibling-order has HUD readying AFTER the hero, so the initial Lv/XP
	# payload never reaches the HUD label.
	EventBus.hero_spawned.emit.call_deferred(self)


func _effective_max_health() -> int:
	if data == null:
		return 0
	return int(ceil(float(data.max_health) * (1.0 + (level - 1) * LEVEL_HEALTH_GROWTH)))


func _effective_damage() -> float:
	if data == null:
		return 0.0
	var base: float = data.attack_damage * (1.0 + (level - 1) * LEVEL_DAMAGE_GROWTH)
	# Phase 28: permanent upgrade (Hero Training = type 3).
	base *= GameState.get_upgrade_multiplier(3)
	return base


func _tick_skill_cooldowns(delta: float) -> void:
	for i in _skill_cooldowns.size():
		if _skill_cooldowns[i] <= 0.0:
			continue
		var before: float = _skill_cooldowns[i]
		_skill_cooldowns[i] = maxf(0.0, _skill_cooldowns[i] - delta)
		if before > 0.0 and _skill_cooldowns[i] <= 0.0:
			var skill: Resource = get_skill_data(i)
			if skill != null:
				EventBus.skill_ready.emit(skill.skill_name)


func get_skill_data(idx: int) -> Resource:
	if data == null or idx < 0 or idx >= data.skills.size():
		return null
	return data.skills[idx] as Resource


func get_skill_cooldown_fraction(idx: int) -> float:
	# 0.0 = ready, 1.0 = just cast. UI radial overlay maps this to arc coverage.
	var skill: Resource = get_skill_data(idx)
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	if idx >= _skill_cooldowns.size():
		return 0.0
	return clampf(_skill_cooldowns[idx] / skill.cooldown, 0.0, 1.0)


# CooldownButton provider contract — generic names so the same button
# class drives both hero skill buttons and (Phase 22) spell buttons.
func cooldown_fraction(idx: int) -> float:
	return get_skill_cooldown_fraction(idx)


func display_name(idx: int) -> String:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return "?"
	return skill.skill_name


func get_skill_effective_range(idx: int) -> float:
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return 0.0
	if skill.skill_range > 0.0:
		return skill.skill_range
	return data.attack_range


func set_skill_range_preview(radius: float) -> void:
	if is_equal_approx(_skill_range_preview, radius):
		return
	_skill_range_preview = radius
	queue_redraw()


func can_cast_skill(idx: int) -> bool:
	if state == State.DEAD or data == null:
		return false
	if idx < 0 or idx >= _skill_cooldowns.size():
		return false
	return _skill_cooldowns[idx] <= 0.0


func cast_skill(idx: int, target) -> bool:
	# target: Node (for SINGLE), Vector2 (for AREA), or null (for SELF).
	# Returns true if the skill actually fired (not on cooldown / valid target).
	if not can_cast_skill(idx):
		return false
	var skill: Resource = get_skill_data(idx)
	if skill == null:
		return false
	skill.apply(self, target)
	_skill_cooldowns[idx] = skill.cooldown
	EventBus.hero_skill_used.emit(skill.skill_name)
	EventBus.skill_cooldown_started.emit(skill.skill_name, skill.cooldown)
	# Face the target for the lunge visual on melee single-target casts.
	if target is Node2D:
		_start_lunge(target.global_position)
	return true


func _xp_needed_for_next_level() -> int:
	if data == null or level >= data.max_level:
		return 0
	var idx: int = level - 1
	if idx < 0 or idx >= data.xp_per_level.size():
		return 0
	return data.xp_per_level[idx]


func gain_xp(amount: int) -> void:
	if state == State.DEAD or data == null or amount <= 0:
		return
	if level >= data.max_level:
		return
	# Phase 28: permanent upgrade (Fast Learner = type 4).
	var scaled: int = int(ceil(float(amount) * GameState.get_upgrade_multiplier(4)))
	current_xp += scaled
	EventBus.hero_xp_gained.emit(amount)
	var needed: int = _xp_needed_for_next_level()
	while needed > 0 and current_xp >= needed and level < data.max_level:
		current_xp -= needed
		_level_up()
		needed = _xp_needed_for_next_level()
	if level >= data.max_level:
		current_xp = 0


func _level_up() -> void:
	level += 1
	# Heal to the new max. Kingdom Rush convention.
	current_health = _effective_max_health()
	queue_redraw()
	EventBus.hero_leveled_up.emit(level)
	print("[Hero] %s reached level %d" % [data.hero_name, level])


func change_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state


func move_to(world_pos: Vector2) -> void:
	if state == State.DEAD or data == null:
		return
	_move_target = world_pos
	_has_move_target = true
	# Explicit move overrides any active engagement.
	_target_enemy = null
	_attack_cooldown = 0.0
	# Auto-deselect on move command — Option B. Next stray tap won't re-move
	# the hero until the player taps the body to re-arm.
	if is_selected:
		set_selected(false)
	change_state(State.MOVING)


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Tap-on-hero distance check (no Area2D picking — flaky with runtime
	# shape sizing). Uses _unhandled_input rather than _input so that:
	#  - TowerSpotMenu's Backdrop (GUI phase) can consume taps first while
	#    it's open, keeping the menu modal,
	#  - SpotInputManager (earlier in tree order) can consume taps that
	#    land on a tower spot, so a hero standing on/near a spot doesn't
	#    steal the tap away from the build/sell menu.
	if state == State.DEAD:
		return
	if not (event is InputEventScreenTouch):
		return
	if not event.pressed:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	if local.length() > SELECT_TAP_RADIUS:
		return
	set_selected(not is_selected)
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if state == State.DEAD or data == null:
		return
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		queue_redraw()
	_tick_skill_cooldowns(delta)
	if _ability_host != null:
		_ability_host.tick(delta)
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			_seek_target()
		State.MOVING:
			_move_step()
		State.COMBAT:
			velocity = Vector2.ZERO
			_attack_step(delta)
	move_and_slide()


func _start_lunge(target_world_pos: Vector2) -> void:
	var dir: Vector2 = target_world_pos - global_position
	if dir.length_squared() < 0.01:
		return
	_lunge_dir = dir.normalized()
	# Cap duration so very fast attack_speed values don't truncate the lunge
	# mid-animation — we want each swing's lunge to fully complete before
	# the next one starts (would look like the hero stuttering forward).
	var cooldown: float = 1.0 / maxf(0.01, data.attack_speed) if data != null else LUNGE_DURATION
	_lunge_t = minf(LUNGE_DURATION, cooldown * 0.9)
	queue_redraw()


func _lunge_offset() -> Vector2:
	if _lunge_t <= 0.0:
		return Vector2.ZERO
	# Triangle wave 0 → 1 → 0 over LUNGE_DURATION (peak at the midpoint).
	var t: float = 1.0 - (_lunge_t / LUNGE_DURATION)
	var phase: float = 1.0 - absf(t * 2.0 - 1.0)
	return _lunge_dir * (LUNGE_DISTANCE * phase)


func _move_step() -> void:
	var to_target: Vector2 = _move_target - global_position
	if to_target.length() < MOVE_REACHED_TOLERANCE:
		velocity = Vector2.ZERO
		_has_move_target = false
		change_state(State.IDLE)
		return
	velocity = to_target.normalized() * data.move_speed


func _seek_target() -> void:
	var nearest: Node = null
	var nearest_d2: float = INF
	for area in attack_range_area.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if enemy.data == null:
			continue
		# targets_flying is true for the warrior, so we don't filter on is_flying.
		if enemy.data.is_flying and not data.targets_flying:
			continue
		var d2: float = global_position.distance_squared_to(enemy.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = enemy
	if nearest != null:
		_target_enemy = nearest
		_attack_cooldown = 0.0
		change_state(State.COMBAT)


func _attack_step(delta: float) -> void:
	if _target_enemy == null or not is_instance_valid(_target_enemy):
		_target_enemy = null
		change_state(State.IDLE)
		return
	var enemy: BaseEnemy = _target_enemy
	if enemy.state == BaseEnemy.State.DYING:
		_target_enemy = null
		change_state(State.IDLE)
		return
	# Drop the engagement if the enemy walked out of attack range.
	if not (enemy in attack_range_area.get_overlapping_areas()):
		_target_enemy = null
		change_state(State.IDLE)
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(0.01, data.attack_speed)
	_start_lunge(enemy.global_position)
	var dmg: float = _effective_damage()
	var dying: bool = enemy.state == BaseEnemy.State.DYING
	enemy.take_damage(dmg, data.damage_type, self)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_DEALT, {"target": enemy, "amount": dmg})
		# Kill is inferred by post-hit state transition. BaseEnemy enters
		# DYING inside take_damage when HP drops to 0.
		if not dying and enemy.state == BaseEnemy.State.DYING:
			_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_KILL, {"victim": enemy})


func take_damage(amount: float, type: int, source: Node = null) -> void:
	if state == State.DEAD or data == null:
		return
	var final: float = DamageCalculator.calculate_damage(amount, type, self)
	current_health -= int(ceil(final))
	queue_redraw()
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_HIT_TAKEN, {"source": source, "amount": final})
	if current_health <= 0:
		_die()


func _die() -> void:
	change_state(State.DEAD)
	velocity = Vector2.ZERO
	visible = false
	set_selected(false)
	if _ability_host != null:
		_ability_host.trigger_event(_AbilityDataScript.Trigger.ON_DEATH, {})
	EventBus.hero_died.emit()


func _draw() -> void:
	# Skill targeting range circle (Phase 20) — drawn first so the body
	# and selection ring sit on top of the faint fill.
	if _skill_range_preview > 0.0:
		draw_circle(Vector2.ZERO, _skill_range_preview, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, _skill_range_preview, 0.0, TAU, 48, Color(1.0, 0.9, 0.3, 0.85), 2.5)
	# Selection ring sits on the ground (no lunge) so it reads as a marker
	# under the unit, not as part of the body. Drawn first so the body
	# covers the inside of the ring.
	if is_selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(1.0, 0.95, 0.3, 0.85), 2.5)
	# Body + sword translated by the lunge offset.
	var off: Vector2 = _lunge_offset()
	if off != Vector2.ZERO:
		draw_set_transform(off, 0.0, Vector2.ONE)
	draw_rect(Rect2(-10, -10, 20, 20), Color(0.85, 0.7, 0.2))
	draw_rect(Rect2(-10, -10, 20, 20), Color(0.2, 0.15, 0.05), false, 2.0)
	draw_line(Vector2(0, -10), Vector2(0, -16), Color(0.9, 0.9, 0.95), 2.5)
	if off != Vector2.ZERO:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_health_bar()


func _draw_health_bar() -> void:
	if data == null:
		return
	var max_hp: int = _effective_max_health()
	if max_hp <= 0:
		return
	if current_health >= max_hp:
		return
	var pct: float = clampf(float(current_health) / float(max_hp), 0.0, 1.0)
	var origin: Vector2 = Vector2(-HP_BAR_SIZE.x * 0.5, HP_BAR_Y_OFFSET)
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0.12, 0.12, 0.12))
	if pct > 0.0:
		draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * pct, HP_BAR_SIZE.y)), Color(0.3, 0.9, 0.3))
	draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0), false, 1.0)
