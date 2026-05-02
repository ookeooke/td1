extends CanvasLayer

# Phase 20 / 48 — in-level skill cluster.
#
# Bottom-right corner of the screen. The HeroHudPortrait lives at the
# corner; two skill slots arc up-and-left from it (DI-style thumb
# cluster). Each slot reads from `GameState.hero_equipped_skills[hero_id]`;
# unequipped slots render an EmptySkillSlot placeholder ("+" tile).
#
# Tap a slot → enter targeting mode (range circle drawn around the hero,
# radius = skill's effective range). Next screen tap inside the range that
# lands on an enemy → cast. Tap outside range or with no enemy nearby →
# cancel targeting, nothing happens.
#
# Cooldown display is a radial fill overlay drawn via the button's _draw
# override (CooldownButton.gd). Never text, per CLAUDE.md.

const CooldownButtonScene: PackedScene = preload("res://ui/CooldownButton.tscn")
const _SkillDataScript: Script = preload("res://heroes/skills/skill_data.gd")
const _EmptySlotScript: Script = preload("res://ui/EmptySkillSlot.gd")
const TARGET_TAP_TOLERANCE: float = 80.0

# Slot positions inside the Cluster Control. Each entry is the top-left
# corner of an 80×80 slot. Slot 0 sits closest to the portrait (right
# thumb's natural reach); slot 1 steps up and to the left along a 45° arc.
# Distance between slot centers ≈ 100px so the 80px tiles don't overlap.
# Cluster size in the .tscn is 200×400 — extra headroom kept so a future
# 3rd / 4th slot can slot in without retuning the layout.
const SLOT_POSITIONS: Array[Vector2] = [
	Vector2(80.0, 180.0),   # Slot 0 — closest to portrait
	Vector2(40.0, 100.0),   # Slot 1 — above-left of slot 0
]

@onready var cluster: Control = %Cluster

var _hero: Node = null
var _buttons: Array = []
var _targeting_idx: int = -1


func _ready() -> void:
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)
	# Loadout changes happen on the WorldMap (Heroes → Skills tab) — the
	# in-level bar is a passive read of GameState.hero_equipped_skills.
	# Listening here is defensive: if a future feature ever flips a slot
	# mid-run, the bar reflects it without a manual rebuild.
	EventBus.hero_skill_equipped.connect(_on_loadout_changed)


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


func _on_loadout_changed(hero_id: String, _slot: int, _skill_id: String) -> void:
	if _hero == null or _hero.data == null or _hero.data.hero_id != hero_id:
		return
	_cancel_targeting()
	_rebuild_buttons()


func _rebuild_buttons() -> void:
	# Free everything except the Portrait child, which is authored in the
	# .tscn and owns its own state (hero/HP/XP signals). Slots are recreated
	# fresh on every loadout change.
	for child in cluster.get_children():
		if child.name == "Portrait":
			continue
		child.queue_free()
	_buttons.clear()
	if _hero == null or _hero.data == null:
		return
	# Phase 48 — render the per-hero equipped loadout (length 3) instead of
	# every authored skill. The button's `idx` stays as the index into
	# data.skills so the hero's parallel _skill_cooldowns / get_skill_data
	# accessors keep working unchanged. Empty slots get an EmptySkillSlot
	# placeholder so the cluster always reads as 3 tiles.
	var equipped: Array[String] = GameState.get_equipped_skills(_hero.data.hero_id)
	for slot_idx in SLOT_POSITIONS.size():
		var skill_id: String = equipped[slot_idx] if slot_idx < equipped.size() else ""
		var slot: Control
		if skill_id == "":
			slot = _EmptySlotScript.new()
		else:
			var idx: int = _find_skill_idx_by_id(skill_id)
			if idx < 0:
				# Stale loadout entry (e.g. skill_id renamed) — show placeholder.
				slot = _EmptySlotScript.new()
			else:
				slot = CooldownButtonScene.instantiate()
				slot.setup(_hero, idx)
				slot.triggered.connect(_on_skill_button_pressed)
				_buttons.append(slot)
		slot.position = SLOT_POSITIONS[slot_idx]
		slot.size = Vector2(80.0, 80.0)
		cluster.add_child(slot)


func _find_skill_idx_by_id(skill_id: String) -> int:
	if _hero == null or _hero.data == null:
		return -1
	for i in _hero.data.skills.size():
		var s: Resource = _hero.data.skills[i]
		if s != null and s.skill_id == skill_id:
			return i
	return -1


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




func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x


func _find_enemy_near(world_pos: Vector2, max_hero_dist: float, hero_pos: Vector2) -> Node:
	# Pick the enemy closest to the tap that is ALSO within the skill's
	# range of the hero. TARGET_TAP_TOLERANCE gives finger-friendly slack.
	var best: Node = null
	var zoom_scale: float = _get_zoom_scale()
	var scaled_tolerance: float = TARGET_TAP_TOLERANCE * zoom_scale
	var best_d2: float = scaled_tolerance * scaled_tolerance
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
