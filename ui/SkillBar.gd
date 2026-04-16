extends CanvasLayer

# Phase 20 skill bar. Bottom-right column of skill buttons, one per skill
# in hero.data.skills. Tap a button → enter targeting mode (range circle
# drawn around the hero, radius = skill's effective range). Next screen
# tap inside the range that lands on an enemy → cast. Tap outside range
# or with no enemy nearby → cancel targeting, nothing happens.
#
# Cooldown display is a radial fill overlay drawn via the button's _draw
# override (CooldownButton.gd). Never text, per CLAUDE.md.

const CooldownButtonScene: PackedScene = preload("res://ui/CooldownButton.tscn")
const _SkillDataScript: Script = preload("res://heroes/skills/skill_data.gd")
const TARGET_TAP_TOLERANCE: float = 32.0

@onready var button_column: VBoxContainer = %ButtonColumn

var _hero: Node = null
var _buttons: Array = []
var _targeting_idx: int = -1


func _ready() -> void:
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)


func _process(_delta: float) -> void:
	# Cooldown buttons redraw themselves from the hero's cooldown fractions.
	# The range-circle preview is drawn by the hero itself (it already
	# tracks its own position in _draw), so SkillBar doesn't need to drive
	# a separate overlay node here.
	for btn in _buttons:
		if btn.has_method("refresh"):
			btn.refresh()


func _on_hero_spawned(hero: Node) -> void:
	_hero = hero
	_rebuild_buttons()


func _on_hero_died() -> void:
	_cancel_targeting()


func _rebuild_buttons() -> void:
	for child in button_column.get_children():
		child.queue_free()
	_buttons.clear()
	if _hero == null or _hero.data == null:
		return
	for i in _hero.data.skills.size():
		var btn: Control = CooldownButtonScene.instantiate()
		btn.setup(_hero, i)
		btn.triggered.connect(_on_skill_button_pressed)
		button_column.add_child(btn)
		_buttons.append(btn)


func _on_skill_button_pressed(idx: int) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	if not _hero.can_cast_skill(idx):
		return
	var skill: Resource = _hero.get_skill_data(idx)
	if skill == null:
		return
	# SELF skills cast immediately — no targeting step.
	if skill.target_type == _SkillDataScript.TargetType.SELF:
		_hero.cast_skill(idx, null)
		return
	# SINGLE / AREA both need a targeting tap. Toggle off if the same
	# button is pressed again.
	if _targeting_idx == idx:
		_cancel_targeting()
		return
	_targeting_idx = idx
	_hero.set_skill_range_preview(_hero.get_skill_effective_range(idx))


func _cancel_targeting() -> void:
	_targeting_idx = -1
	if _hero != null and is_instance_valid(_hero):
		_hero.set_skill_range_preview(0.0)


# Sits in _input so the cast tap is consumed before SpotInputManager /
# HeroWarrior / HeroInputManager see it. Without this, tapping to cast
# at an enemy near a tower spot would also open the build menu.
func _input(event: InputEvent) -> void:
	if _targeting_idx < 0:
		return
	if get_viewport().is_input_handled():
		return
	if not (event is InputEventScreenTouch):
		return
	if not event.pressed:
		return
	var world_pos: Vector2 = _screen_to_world(event.position)
	var hero_pos: Vector2 = _hero.global_position
	var skill_range: float = _hero.get_skill_effective_range(_targeting_idx)
	# Require the tap itself to be inside the range circle — predictable,
	# matches the visual hint.
	if hero_pos.distance_to(world_pos) > skill_range:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
		return
	var skill: Resource = _hero.get_skill_data(_targeting_idx)
	if skill != null and skill.target_type == _SkillDataScript.TargetType.AREA:
		# AoE: the tap position itself IS the target. Always fires when the
		# tap is in range — hitting nothing is the player's problem.
		_hero.cast_skill(_targeting_idx, world_pos)
	else:
		# SINGLE: need an enemy near the tap and within range of the hero.
		var target: Node = _find_enemy_near(world_pos, skill_range, hero_pos)
		if target != null:
			_hero.cast_skill(_targeting_idx, target)
	# Either path ends targeting — a miss also closes the mode so the player
	# isn't stuck armed. Consume so stray handlers don't also react.
	_cancel_targeting()
	get_viewport().set_input_as_handled()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Same transform chain SpotInputManager / HeroInputManager use — maps
	# canvas-layer screen coords back into the world-space the hero lives in.
	var map: Node2D = get_tree().root.find_child("Level1", true, false) as Node2D
	if map == null:
		return screen_pos
	return map.get_global_transform_with_canvas().affine_inverse() * screen_pos


func _find_enemy_near(world_pos: Vector2, max_hero_dist: float, hero_pos: Vector2) -> Node:
	# Pick the enemy closest to the tap that is ALSO within the skill's
	# range of the hero. TARGET_TAP_TOLERANCE gives finger-friendly slack.
	var best: Node = null
	var best_d2: float = TARGET_TAP_TOLERANCE * TARGET_TAP_TOLERANCE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy):
			continue
		if enemy.state == BaseEnemy.State.DYING:
			continue
		if hero_pos.distance_to(enemy.global_position) > max_hero_dist:
			continue
		var d2: float = world_pos.distance_squared_to(enemy.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = enemy
	return best
