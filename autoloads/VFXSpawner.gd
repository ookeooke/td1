extends Node

# Phase 41: VFX autoload. Connects to EventBus signals and spawns
# FloatingText + DeathVFX at the relevant world positions.

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

# Cached hero reference for XP text positioning.
var _hero: Node2D = null
var clean_view: bool = false


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
		_FloatingTextScript.spawn(parent, "+%dg" % gold_value, Color(0.83, 0.66, 0.20), pos)


func _on_hit_landed(target: Node, source: Node, _amount: float, dmg_type: int) -> void:
	if clean_view:
		return
	if not is_instance_valid(target):
		return
	var parent: Node = _get_world_parent()
	if parent == null:
		return
	var pos: Vector2 = (target as Node2D).global_position if target is Node2D else Vector2.ZERO
	# Direction: away from the source (the spark sprays out from impact toward
	# the back of the target). If source is unknown, default outward-right.
	var dir: Vector2 = Vector2.RIGHT
	if source != null and is_instance_valid(source) and source is Node2D:
		var away: Vector2 = pos - (source as Node2D).global_position
		if away.length_squared() > 0.0001:
			dir = away.normalized()
	_HitSparkVFXScript.spawn_for_damage_type(parent, pos, dir, dmg_type)


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
	_FloatingTextScript.spawn(parent, "+%d XP" % amount, Color(0.2, 0.7, 1.0), _hero.global_position + Vector2(0, -50))


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
