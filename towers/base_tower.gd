extends Node2D
class_name BaseTower

# DEBUG: every 3–6 shots, attach a random SlowEffect/StunEffect to the arrow
# so Phase 13's status system can be exercised through real gameplay instead
# of Main.gd's one-shot demo. Flip DEBUG_STATUS_ARROWS = true to re-enable.
const DEBUG_STATUS_ARROWS: bool = false
const _SlowEffectScript := preload("res://systems/SlowEffect.gd")
const _StunEffectScript := preload("res://systems/StunEffect.gd")

enum TargetingMode { FIRST, STRONG, WEAK }

@export var data: TowerData

var level: int = 1
const MAX_LEVEL: int = 3
# Phase 25 branch choice — -1 means not branched (either at L2 and below,
# or at L3 on the linear `level_upgrades[1]` path). 0+ is the chosen
# index into `data.level_3_branches`. Decision is permanent once set.
var branch_idx: int = -1


# Phase 19 review fix: attack loop moved off a Timer node and onto a float
# cooldown ticked in _physics_process. This makes the first shot fire the
# instant an enemy enters range (cooldown starts at 0) instead of waiting
# up to 1/attack_speed for a Timer to cycle.
var _attack_cooldown: float = 0.0
var _current_target: Node = null
var total_damage_dealt: float = 0.0
var targeting_mode: int = TargetingMode.FIRST

# Stable run-scoped key for the end-of-run damage leaderboard. Assigned
# lazily by GameState.record_round_damage on the tower's first hit.
# Using get_instance_id() as the key would be unsafe because Godot reuses
# freed IDs — a new tower could inherit a sold tower's tally.
@warning_ignore("unused_private_class_variable")
var _damage_key: int = -1

var _shots_since_buff: int = 0
var _next_buff_threshold: int = 0

# Construction + upgrade + aim animation state. _construct_t starts at
# TowerAnim.CONSTRUCTION_DURATION on build and ticks down; _upgrade_t is
# set to TowerAnim.UPGRADE_DURATION on every upgrade / branch choice.
# _aim_angle lerps toward the current target so the barrel tracks smoothly.
const _TowerAnimScript := preload("res://systems/TowerAnim.gd")
const AIM_LERP_SPEED: float = 12.0
var _construct_t: float = 0.0
var _upgrade_t: float = 0.0
var _aim_angle: float = -PI / 2.0

@onready var range_area: Area2D = $RangeArea
@onready var range_shape: CollisionShape2D = $RangeArea/CollisionShape2D


func _ready() -> void:
	if data == null:
		push_warning("[%s] no TowerData assigned" % name)
		return
	_refresh_range_shape()
	_next_buff_threshold = randi_range(3, 6)
	# Kick off the build-in animation. Firing is blocked by the early-return
	# in _physics_process while _construct_t > 0, so we leave _attack_cooldown
	# at 0 — the tower fires the frame after construction completes.
	_construct_t = _TowerAnimScript.CONSTRUCTION_DURATION
	modulate.a = 0.0


func _refresh_range_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = get_effective_range()
	range_shape.shape = circle


# Per-level effective stats — read through the current level's
# TowerUpgradeData if set; otherwise fall back to TowerData. At L3, if the
# tower chose a branch, the branch Resource wins over the linear L3 slot.
func _level_override() -> Resource:
	if data == null or level <= 1:
		return null
	if level >= 3 and branch_idx >= 0 and branch_idx < data.level_3_branches.size():
		return data.level_3_branches[branch_idx]
	if data.level_upgrades.is_empty():
		return null
	var idx: int = mini(level - 2, data.level_upgrades.size() - 1)
	return data.level_upgrades[idx]


func has_branch_options() -> bool:
	# True when stepping INTO L3 would require picking a branch (i.e. we're
	# at L2 and the data file defines at least one branch option).
	return data != null \
			and level == 2 \
			and not data.level_3_branches.is_empty() \
			and branch_idx < 0


func get_branch_options() -> Array[Resource]:
	if data == null:
		return []
	return data.level_3_branches


func get_branch_cost(idx: int) -> int:
	if data == null or idx < 0 or idx >= data.level_3_branches.size():
		return 0
	var branch: Resource = data.level_3_branches[idx]
	return int(branch.cost)


func upgrade_to_branch(idx: int) -> bool:
	if data == null or level != 2 or idx < 0 or idx >= data.level_3_branches.size():
		return false
	branch_idx = idx
	level = 3
	_refresh_range_shape()
	_attack_cooldown = 0.0
	_upgrade_t = _TowerAnimScript.UPGRADE_DURATION
	queue_redraw()
	EventBus.tower_upgraded.emit(self, level)
	EventBus.tower_branch_chosen.emit(self, idx)
	return true


func get_effective_damage() -> float:
	var base: float = _level_override().damage if _level_override() != null else data.damage
	base *= GameState.get_upgrade_multiplier(GameState.MOD_ARCHER_DAMAGE)
	return base


func get_effective_range() -> float:
	var base: float = _level_override().attack_range if _level_override() != null else data.attack_range
	base *= GameState.get_upgrade_multiplier(GameState.MOD_TOWER_RANGE)
	return base


# Unified range accessor used by UI (RangePreview, TowerStatsCard,
# TowerRadialMenu). Attack towers return attack_range; barracks override
# to return rally range. Keeps the UI duck-typed against a single method.
func get_preview_range() -> float:
	return get_effective_range()


# Returns the range this tower would have after the next paid upgrade, for
# the green "ghost ring" hover preview. 0.0 when there is no meaningful
# preview: maxed, or at L2 with branches (the branch cards preview their
# own ranges individually).
func get_upgrade_range() -> float:
	if data == null or level >= MAX_LEVEL or has_branch_options():
		return 0.0
	var next_idx: int = level - 1  # level 1 → data.level_upgrades[0] = L2
	if next_idx < 0 or next_idx >= data.level_upgrades.size():
		return 0.0
	var next: Resource = data.level_upgrades[next_idx]
	if next == null or next.attack_range <= 0.0:
		return 0.0
	return next.attack_range * GameState.get_upgrade_multiplier(GameState.MOD_TOWER_RANGE)


func get_effective_attack_speed() -> float:
	var ov: Resource = _level_override()
	return ov.attack_speed if ov != null else data.attack_speed


# Tower Indicator Interface: each tower formats its own stats row so the
# stats card stays tower-agnostic. Combat towers show Dmg / Rng / Spd.
func get_stats_line() -> String:
	return "Dmg %d   Rng %d   Spd %.1f" % [
		int(get_effective_damage()),
		int(get_preview_range()),
		get_effective_attack_speed(),
	]


# Structured stats used by the upgrade-preview diff so the card can color each
# column green/red by improvement. Rows: {label, value, fmt, higher_is_better}.
# Slow/stun/AoE rows are only emitted when the value is meaningful (> 0),
# since barely-used columns add noise for towers that never touch them.
func get_preview_stats() -> Array:
	# Read upgrade override first, fall back to base TowerData fields so an
	# Ice-Tower-style L1 that slows shows its slow row in the stats card too.
	var ov: Resource = _level_override()
	var aoe: float = data.aoe_radius if data != null else 0.0
	var slow_f: float = 0.0
	var slow_d: float = 0.0
	var stun: float = 0.0
	if ov != null:
		slow_f = ov.on_hit_slow_factor
		slow_d = ov.on_hit_slow_duration
		stun = ov.on_hit_stun_duration
	if slow_f <= 0.0 and data != null:
		slow_f = data.on_hit_slow_factor
		slow_d = data.on_hit_slow_duration
	# Same per-field fallback as _build_on_hit_effect so the card shows the
	# duration that will actually apply when the upgrade inherits it.
	if slow_f > 0.0 and slow_d <= 0.0 and data != null:
		slow_d = data.on_hit_slow_duration
	if stun <= 0.0 and data != null:
		stun = data.on_hit_stun_duration
	var rows: Array = [
		{"label": "Dmg", "value": get_effective_damage(), "fmt": "%d"},
		{"label": "Rng", "value": get_preview_range(), "fmt": "%d"},
		{"label": "Spd", "value": get_effective_attack_speed(), "fmt": "%.1f"},
	]
	if aoe > 0.0:
		rows.append({"label": "AoE", "value": aoe, "fmt": "%d"})
	if slow_f > 0.0:
		rows.append({"label": "Slow", "value": slow_f * 100.0, "fmt": "%d%%"})
		rows.append({"label": "SlowT", "value": slow_d, "fmt": "%.1fs"})
	if stun > 0.0:
		rows.append({"label": "Stun", "value": stun, "fmt": "%.1fs"})
	return rows


func get_sell_value() -> int:
	var ov: Resource = _level_override()
	if ov != null and ov.sell_value > 0:
		return ov.sell_value
	return data.sell_value


func record_damage(amount: float) -> void:
	total_damage_dealt += amount


func cycle_targeting_mode() -> void:
	targeting_mode = (targeting_mode + 1) % 3


func get_targeting_mode_name() -> String:
	match targeting_mode:
		TargetingMode.FIRST: return "First"
		TargetingMode.STRONG: return "Strong"
		TargetingMode.WEAK: return "Weak"
	return "First"


func get_upgrade_cost_to(next_level: int) -> int:
	# Cost to advance FROM current `level` TO `next_level`. next_level must
	# be current + 1 in Phase 24; branching in Phase 25 may extend this.
	if data == null or next_level <= 1 or next_level > MAX_LEVEL:
		return 0
	if next_level - 2 < data.level_upgrades.size():
		var ov: Resource = data.level_upgrades[next_level - 2]
		if ov.cost > 0:
			return ov.cost
	# Legacy fallback for .tres authored before TowerUpgradeData.
	if next_level == 2:
		return data.upgrade_cost_lvl2
	if next_level == 3:
		return data.upgrade_cost_lvl3
	return 0


func can_upgrade() -> bool:
	if level >= MAX_LEVEL:
		return false
	# If the next level requires a branch choice, linear upgrade is off —
	# the UI must show the branch picker instead. Caller checks
	# `has_branch_options()` for that case.
	if has_branch_options():
		return false
	return get_upgrade_cost_to(level + 1) > 0


func upgrade() -> bool:
	if not can_upgrade():
		return false
	level += 1
	_refresh_range_shape()
	# Reset attack cooldown so the faster-speed upgrade feels immediate
	# instead of waiting out the previous (slower) tick.
	_attack_cooldown = 0.0
	_upgrade_t = _TowerAnimScript.UPGRADE_DURATION
	queue_redraw()
	EventBus.tower_upgraded.emit(self, level)
	return true


var _recoil_t: float = 0.0

func _physics_process(delta: float) -> void:
	# Construction tick drives alpha fade + scale grow via TowerAnim. While
	# in construction we early-return so _pick_target doesn't fire and the
	# barrel stays at its idle angle.
	if _construct_t > 0.0:
		_construct_t = maxf(0.0, _construct_t - delta)
		modulate.a = _TowerAnimScript.construct_alpha(_construct_t)
		queue_redraw()
		if _construct_t > 0.0:
			return
		modulate.a = 1.0
	if _upgrade_t > 0.0:
		_upgrade_t = maxf(0.0, _upgrade_t - delta)
		queue_redraw()
	if _recoil_t > 0.0:
		_recoil_t -= delta
		queue_redraw()
	if data == null:
		return
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	# Pick + aim every frame so the barrel tracks between shots, not only
	# on the firing frame. _pick_target is cheap (Area2D overlap iteration).
	var target: Node = _pick_target()
	_tick_aim(delta, target)
	if _attack_cooldown > 0.0:
		return
	if target == null:
		_current_target = null
		return
	_current_target = target
	_fire_projectile(target)
	_attack_cooldown = 1.0 / maxf(0.01, get_effective_attack_speed())


func _tick_aim(delta: float, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dir: Vector2 = target.global_position - global_position
	if dir.length_squared() < 1.0:
		return
	var target_angle: float = dir.angle()
	var next: float = lerp_angle(_aim_angle, target_angle, clampf(AIM_LERP_SPEED * delta, 0.0, 1.0))
	if not is_equal_approx(next, _aim_angle):
		_aim_angle = next
		queue_redraw()


func _pick_target() -> Node:
	# Targeting mode selects which enemy to prioritize:
	#   FIRST  — furthest along path (default, classic TD behavior)
	#   STRONG — highest current HP (focus fire on tanky enemies)
	#   WEAK   — lowest current HP (finish off wounded enemies)
	# Sticky preference for the current target on ties prevents jitter.
	var best: Node = null
	var best_score: float = -INF if targeting_mode != TargetingMode.WEAK else INF
	for area in range_area.get_overlapping_areas():
		if not (area is BaseEnemy):
			continue
		var enemy: BaseEnemy = area
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if enemy.data != null and enemy.data.is_flying and not data.targets_flying:
			continue
		var score: float = _targeting_score(enemy)
		var dominated: bool = false
		if targeting_mode == TargetingMode.WEAK:
			dominated = score < best_score
		else:
			dominated = score > best_score
		if best == null or dominated:
			best = enemy
			best_score = score
			continue
		if is_equal_approx(score, best_score):
			if enemy == _current_target:
				best = enemy
				continue
			if best != _current_target and enemy.current_health < best.current_health:
				best = enemy
	return best


func _targeting_score(enemy: BaseEnemy) -> float:
	match targeting_mode:
		TargetingMode.FIRST:
			if enemy.get_parent() is PathFollow2D:
				return enemy.get_parent().progress_ratio
			return 0.0
		TargetingMode.STRONG, TargetingMode.WEAK:
			return float(enemy.current_health)
	return 0.0


func _fire_projectile(target: Node) -> void:
	if data.projectile_scene == null:
		return
	var proj: Node2D = data.projectile_scene.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position

	# Phase 25: branches can attach an on-hit status effect (Ranger's slow).
	# Construct a fresh instance per shot so per-target duration state isn't
	# shared between arrows.
	var effect = _build_on_hit_effect()
	if effect == null:
		effect = _maybe_roll_debug_effect()
	var aoe: float = data.aoe_radius if data != null else 0.0
	if proj.has_method("setup"):
		proj.setup(target, get_effective_damage(), data.damage_type, self, effect, aoe)
	_recoil_t = 0.08
	queue_redraw()


func _build_on_hit_effect():
	# Upgrade override wins when present (branch tint, L2/L3 carry-overs).
	# Otherwise fall back to the base-level fields on TowerData so L1 towers
	# authored as "it slows" (e.g. Ice Tower) can apply effects pre-upgrade.
	var ov: Resource = _level_override()
	var slow_f: float = 0.0
	var slow_d: float = 0.0
	var stun_d: float = 0.0
	if ov != null:
		slow_f = ov.on_hit_slow_factor
		slow_d = ov.on_hit_slow_duration
		stun_d = ov.on_hit_stun_duration
	if slow_f <= 0.0 and data != null:
		slow_f = data.on_hit_slow_factor
		slow_d = data.on_hit_slow_duration
	# Per-field fallback: an upgrade that boosts factor but leaves duration
	# at 0 should inherit the base duration — not silently fail because the
	# "both > 0" gate rejects it. Same direction the other way round.
	if slow_f > 0.0 and slow_d <= 0.0 and data != null:
		slow_d = data.on_hit_slow_duration
	if stun_d <= 0.0 and data != null:
		stun_d = data.on_hit_stun_duration
	if slow_f > 0.0 and slow_d > 0.0:
		return _SlowEffectScript.new(slow_f, slow_d)
	if stun_d > 0.0:
		return _StunEffectScript.new(stun_d)
	return null


func _maybe_roll_debug_effect():
	if not DEBUG_STATUS_ARROWS:
		return null
	_shots_since_buff += 1
	if _shots_since_buff < _next_buff_threshold:
		return null
	_shots_since_buff = 0
	_next_buff_threshold = randi_range(3, 6)
	if randi() % 2 == 0:
		print("[Tower/debug] slow arrow")
		return _SlowEffectScript.new(0.5, 2.0)
	print("[Tower/debug] stun arrow")
	return _StunEffectScript.new(0.8)


func _draw() -> void:
	# Construction ring sits UNDER the body so the tower rises out of a dust
	# puff. Drawn at identity transform (ground-level VFX).
	_TowerAnimScript.draw_construct_ring(self, _construct_t)

	# Combined uniform scale — construction grow × upgrade pulse × recoil.
	var s_construct: float = _TowerAnimScript.construct_scale(_construct_t)
	var s_upgrade: float = _TowerAnimScript.upgrade_scale(_upgrade_t)
	var s_recoil: float = 1.0 - (0.12 * clampf(_recoil_t / 0.08, 0.0, 1.0))
	var s: float = s_construct * s_upgrade * s_recoil

	# Body — scale-only transform.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var base_body: Color = data.body_color if data != null else Color(0.35, 0.45, 0.75)
	var ov: Resource = _level_override()
	if ov != null:
		base_body = base_body * ov.tint
	draw_circle(Vector2.ZERO, 55.0, base_body)
	draw_arc(Vector2.ZERO, 55.0, 0, TAU, 28, Color(0.08, 0.1, 0.25), 6.25)

	# Barrel — drawn in a rotated + scaled coordinate frame so it sticks out
	# toward the target. barrel_length == 0 disables (e.g. support towers).
	if data != null and data.barrel_length > 0.0:
		draw_set_transform(Vector2.ZERO, _aim_angle, Vector2(s, s))
		var half_w: float = data.barrel_width * 0.5
		var inset: float = data.barrel_inset
		var barrel_rect: Rect2 = Rect2(inset, -half_w, data.barrel_length, data.barrel_width)
		var barrel_col: Color = Color(base_body.r * 0.6, base_body.g * 0.6, base_body.b * 0.6, 1.0)
		draw_rect(barrel_rect, barrel_col)
		draw_rect(barrel_rect, Color(0.08, 0.1, 0.25), false, 4.0)
		# Muzzle cap — small dark disc at the tip so the barrel reads as a
		# proper opening rather than a floating bar.
		var tip_local: Vector2 = Vector2(inset + data.barrel_length, 0.0)
		draw_circle(tip_local, half_w * 0.7, Color(0.08, 0.1, 0.25))

	# Level pips — back in scale-only space so they ride the body, not the barrel.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	for i in level:
		draw_circle(Vector2(-15.0 + i * 15.0, -70.0), 5.5, Color(1.0, 0.85, 0.2))

	# Reset to identity for post-body VFX.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_TowerAnimScript.draw_upgrade_ring(self, _upgrade_t)
