extends Node

# Phase 41: VFX autoload. Connects to EventBus signals and spawns
# FloatingText + DeathVFX at the relevant world positions.
#
# 2026-05-07: damage numbers now route through here via EventBus.hit_landed
# (CORE RULE 2). Per-(target, source) merge bucket sums hits within
# MERGE_WINDOW_SEC so multi-tower fire on one enemy doesn't flood the screen.
# DAMAGE_BIG (>=25% target HP) and hero-attributed hits bypass merging.

const _FloatingTextScript := preload("res://vfx/FloatingText.gd")
const _DeathVFXScript := preload("res://vfx/DeathVFX.gd")
const _HitSparkVFXScript := preload("res://vfx/HitSparkVFX.gd")
const _EnemyDeathDriftScript := preload("res://vfx/EnemyDeathDrift.gd")
const _SkillCastFlareScript := preload("res://vfx/SkillCastFlare.gd")

# Skill-name → flare color. Unlisted names fall back to yellow (buff).
const _SKILL_FLARE_COLORS: Dictionary = {
	"Whirlwind": Color(1.0, 0.5, 0.25),       # warrior AoE strike
	"Shield Wall": Color(0.9, 0.85, 0.3),     # warrior buff
	"Rally": Color(1.0, 0.85, 0.3),           # buff-like
	"Fireball": Color(1.0, 0.45, 0.1),        # fire
	"Frost Nova": Color(0.4, 0.85, 1.0),      # ice
	"Arcane Blast": Color(0.6, 0.4, 1.0),     # arcane
	"Heal": Color(0.4, 0.95, 0.5),            # heal
}

const MERGE_WINDOW_SEC: float = 0.25
const BIG_HIT_RATIO: float = 0.25

# Cached hero reference for XP text positioning.
var _hero: Node2D = null
var clean_view: bool = false

# Per-(target, source) damage accumulator. Key = "tid_sid". Each value:
# { acc: float, last_ms: int, last_pos: Vector2, target_id: int }.
var _merge_buckets: Dictionary = {}
var _merge_drain: Timer = null


func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.hero_xp_gained.connect(_on_hero_xp_gained)
	EventBus.hero_spawned.connect(func(h): _hero = h)
	EventBus.hero_died.connect(func(): _hero = null)
	EventBus.game_over.connect(_on_game_over)
	EventBus.game_won.connect(_on_game_won)
	EventBus.clean_view_toggled.connect(func(v): clean_view = v)
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.hero_skill_used.connect(_on_hero_skill_used)
	# Drain the last hit in any series so it isn't held forever waiting for
	# a follow-up that never arrives.
	_merge_drain = Timer.new()
	_merge_drain.wait_time = 0.05
	_merge_drain.autostart = true
	_merge_drain.process_mode = Node.PROCESS_MODE_PAUSABLE
	_merge_drain.timeout.connect(_drain_merge_buckets)
	add_child(_merge_drain)


func _on_enemy_died(enemy: Node, gold_value: int) -> void:
	if not is_instance_valid(enemy):
		return
	var pos: Vector2 = enemy.global_position
	var parent: Node = _get_world_parent()
	if parent == null:
		return
	# Death VFX — read color from visual data if available.
	var color: Color = Color(0.75, 0.2, 0.2)
	var radius: float = 14.0
	if enemy.data != null and enemy.data.visual != null:
		color = enemy.data.visual.body_color
		radius = enemy.data.visual.radius
	if not clean_view:
		_DeathVFXScript.spawn(parent, color, radius, pos)
		# Death drift — snapshot of the body ragdolling away from its killer.
		var hit_dir: Vector2 = Vector2.RIGHT
		var src: Node = enemy._last_damage_source if "_last_damage_source" in enemy else null
		if src != null and is_instance_valid(src) and src is Node2D:
			var away: Vector2 = enemy.global_position - (src as Node2D).global_position
			if away.length_squared() > 0.0001:
				hit_dir = away.normalized()
		if enemy.data != null and enemy.data.visual != null:
			_EnemyDeathDriftScript.spawn(parent, enemy.data.visual, pos, hit_dir)
	# Gold text — always shown (informational, not clutter).
	if gold_value > 0:
		_FloatingTextScript.spawn_kind(parent, _FloatingTextScript.Kind.GOLD, pos, float(gold_value))


func _on_hit_landed(target: Node, source: Node, amount: float, dmg_type: int) -> void:
	if not is_instance_valid(target):
		return
	var parent: Node = _get_world_parent()
	if parent == null:
		return
	var pos: Vector2 = (target as Node2D).global_position if target is Node2D else Vector2.ZERO

	# ----- Hit sparks (existing behavior, gated by clean_view) -----
	if not clean_view:
		var dir: Vector2 = Vector2.RIGHT
		if source != null and is_instance_valid(source) and source is Node2D:
			var away: Vector2 = pos - (source as Node2D).global_position
			if away.length_squared() > 0.0001:
				dir = away.normalized()
		_HitSparkVFXScript.spawn_for_damage_type(parent, pos, dir, dmg_type)

	# ----- Damage text -----
	if clean_view or amount <= 0.0:
		return
	if target is BaseEnemy:
		_handle_enemy_damage(parent, target, source, amount)
	elif target is BaseHero:
		_spawn_styled(parent, _FloatingTextScript.Kind.DAMAGE_HERO_TAKEN, pos + Vector2(0, -60), amount)
	elif target is BaseSoldier:
		_spawn_styled(parent, _FloatingTextScript.Kind.DAMAGE_SOLDIER_TAKEN, pos + Vector2(0, -40), amount)


func _handle_enemy_damage(parent: Node, enemy: Node, source: Node, amount: float) -> void:
	var max_hp: float = 1.0
	if enemy.has_method("_effective_max_health"):
		max_hp = float(enemy._effective_max_health())
	elif enemy.data != null:
		max_hp = float(enemy.data.max_health)
	var ratio: float = (amount / max_hp) if max_hp > 0.0 else 0.0
	# Big hits and hero-attributed hits bypass merging — they should pop
	# immediately and individually for legibility (skill bursts, crits).
	var is_big: bool = ratio >= BIG_HIT_RATIO
	var is_hero: bool = source != null and source is BaseHero
	if is_big or is_hero:
		var kind: int = _FloatingTextScript.Kind.DAMAGE_BIG if is_big else _FloatingTextScript.Kind.DAMAGE_ENEMY
		_spawn_styled(parent, kind, enemy.global_position + Vector2(0, -50), amount)
		return
	# Tower hits: accumulate per-(enemy, source) and spawn one number per
	# MERGE_WINDOW_SEC.
	var key: String = "%d_%d" % [enemy.get_instance_id(), source.get_instance_id() if source != null else 0]
	var now_ms: int = Time.get_ticks_msec()
	var bucket: Dictionary = _merge_buckets.get(key, {})
	if bucket.is_empty():
		# First hit in a new series — spawn immediately, reset bucket.
		_spawn_styled(parent, _FloatingTextScript.Kind.DAMAGE_ENEMY, enemy.global_position + Vector2(0, -50), amount)
		_merge_buckets[key] = {
			"acc": 0.0,
			"last_ms": now_ms,
			"last_pos": enemy.global_position,
			"target_id": enemy.get_instance_id(),
		}
		return
	var elapsed_ms: int = now_ms - int(bucket["last_ms"])
	if elapsed_ms < int(MERGE_WINDOW_SEC * 1000.0):
		# Inside window — accumulate, defer spawn.
		bucket["acc"] = float(bucket["acc"]) + amount
		bucket["last_pos"] = enemy.global_position
		_merge_buckets[key] = bucket
		return
	# Window elapsed — flush the accumulated total + the new hit, reset.
	var total: float = float(bucket["acc"]) + amount
	_spawn_styled(parent, _FloatingTextScript.Kind.DAMAGE_ENEMY, enemy.global_position + Vector2(0, -50), total)
	_merge_buckets[key] = {
		"acc": 0.0,
		"last_ms": now_ms,
		"last_pos": enemy.global_position,
		"target_id": enemy.get_instance_id(),
	}


func _drain_merge_buckets() -> void:
	# Flush buckets whose last activity is older than MERGE_WINDOW_SEC AND
	# whose accumulator still has un-spawned damage. Drops buckets for
	# freed enemies.
	if _merge_buckets.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	var window_ms: int = int(MERGE_WINDOW_SEC * 1000.0)
	var dead_keys: Array = []
	for key in _merge_buckets.keys():
		var bucket: Dictionary = _merge_buckets[key]
		var target: Object = instance_from_id(int(bucket["target_id"]))
		if target == null or not is_instance_valid(target):
			dead_keys.append(key)
			continue
		if now_ms - int(bucket["last_ms"]) >= window_ms:
			var acc: float = float(bucket["acc"])
			if acc > 0.0:
				var parent: Node = _get_world_parent()
				if parent != null:
					var pos: Vector2 = bucket["last_pos"] if "last_pos" in bucket else (target as Node2D).global_position
					_spawn_styled(parent, _FloatingTextScript.Kind.DAMAGE_ENEMY, pos + Vector2(0, -50), acc)
			dead_keys.append(key)
	for k in dead_keys:
		_merge_buckets.erase(k)


func _spawn_styled(parent: Node, kind: int, pos: Vector2, amount: float) -> void:
	if clean_view:
		return
	_FloatingTextScript.spawn_kind(parent, kind, pos, amount)


func _on_enemy_damaged(enemy: Node, _amount: float, _dmg_type: int) -> void:
	if clean_view:
		return
	if not is_instance_valid(enemy) or enemy.data == null:
		return
	if not enemy.data.is_boss:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null and cam.has_method("add_shake"):
		cam.add_shake(2.0, 0.12)


func _on_hero_skill_used(skill_name: String) -> void:
	if clean_view:
		return
	if _hero == null or not is_instance_valid(_hero):
		return
	var parent: Node = _get_world_parent()
	if parent == null:
		return
	var color: Color = _SKILL_FLARE_COLORS.get(skill_name, Color(1.0, 0.9, 0.3))
	_SkillCastFlareScript.spawn(parent, _hero.global_position, color)


func _on_hero_xp_gained(amount: int) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	var parent: Node = _get_world_parent()
	if parent == null:
		return
	_FloatingTextScript.spawn_kind(parent, _FloatingTextScript.Kind.XP, _hero.global_position + Vector2(0, -50), float(amount))


func _on_game_over() -> void:
	_screen_flash(Color(0.8, 0.15, 0.1, 0.3))


func _on_game_won() -> void:
	_screen_flash(Color(1.0, 0.9, 0.3, 0.25))


func _screen_flash(color: Color) -> void:
	# Brief colored flash via a temporary ColorRect on a high CanvasLayer.
	# PROCESS_MODE_ALWAYS + TWEEN_PAUSE_PROCESS so the fade completes even
	# after game_over pauses the tree — otherwise the flash freezes at full
	# alpha and covers the GameOverScreen. MOUSE_FILTER_IGNORE so the rect
	# never swallows clicks to the menu underneath.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(rect, "color:a", 0.0, 0.35)
	tween.tween_callback(layer.queue_free)


func _get_world_parent() -> Node:
	# VFX nodes are added to the current scene root so they stay in world
	# space and don't get freed when a specific unit despawns.
	return get_tree().current_scene
