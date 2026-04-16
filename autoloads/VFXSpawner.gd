extends Node

# Phase 41: VFX autoload. Connects to EventBus signals and spawns
# FloatingText + DeathVFX at the relevant world positions.

const _FloatingTextScript := preload("res://vfx/FloatingText.gd")
const _DeathVFXScript := preload("res://vfx/DeathVFX.gd")

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
	# Gold text — always shown (informational, not clutter).
	if gold_value > 0:
		_FloatingTextScript.spawn(parent, "+%dg" % gold_value, Color(0.83, 0.66, 0.20), pos)


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
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween: Tween = create_tween()
	tween.tween_property(rect, "color:a", 0.0, 0.35)
	tween.tween_callback(layer.queue_free)


func _get_world_parent() -> Node:
	# VFX nodes are added to the current scene root so they stay in world
	# space and don't get freed when a specific unit despawns.
	return get_tree().current_scene
