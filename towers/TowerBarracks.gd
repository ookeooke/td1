extends Node2D
class_name TowerBarracks

# Phase 16: spawns soldiers up to data.soldier_data.max_count and keeps
# them respawned. Kingdom-Rush-style draggable flag controls where the
# squad rallies — touch the flag, drag, release; the three soldiers
# fan around the new rally point (using data.soldier_spread for the
# triangle shape). Soldiers are parented to the barracks so selling
# cleans them up automatically.

@export var data: TowerData

var level: int = 1
const MAX_LEVEL: int = 2

var _active_soldiers: Array[Node] = []
var _slot_positions: Array[Vector2] = []
var _flag_offset: Vector2 = Vector2.ZERO
var _dragging_flag: bool = false

# Build-in + upgrade animation state. Mirrors BaseTower so both tower types
# share the same feel on placement / upgrade. Decremented in _process (no
# _physics_process on barracks — _process is fine for visual-only ticks).
const _TowerAnimScript := preload("res://systems/TowerAnim.gd")
var _construct_t: float = 0.0
var _upgrade_t: float = 0.0
# Tap-to-place mode entered from the TowerSpotMenu's "Move Rally" button.
# While true the range circle is shown and the next InputEventScreenTouch
# either places the rally point (if inside the circle) or cancels.
var _placement_mode: bool = false

@onready var flag_area: Area2D = $FlagArea
@onready var flag_shape: CollisionShape2D = $FlagArea/CollisionShape2D


func _ready() -> void:
	if data == null or data.soldier_scene == null or _effective_soldier_data() == null:
		push_warning("[TowerBarracks] missing data / soldier_scene / soldier_data")
		return
	_flag_offset = data.soldier_blocking_offset
	var circle := CircleShape2D.new()
	circle.radius = 55.0
	flag_shape.shape = circle
	flag_area.position = _flag_offset
	flag_area.input_event.connect(_on_flag_input)
	_slot_positions = _build_slot_positions(_flag_offset)
	EventBus.soldier_died.connect(_on_soldier_died)
	EventBus.barracks_rally_move_requested.connect(_on_rally_move_requested)
	for i in _effective_soldier_data().max_count:
		_spawn_soldier(i)
	_construct_t = _TowerAnimScript.CONSTRUCTION_DURATION
	modulate.a = 0.0


func _process(delta: float) -> void:
	# Tick build + upgrade timers; drive alpha fade-in during construction.
	if _construct_t > 0.0:
		_construct_t = maxf(0.0, _construct_t - delta)
		modulate.a = _TowerAnimScript.construct_alpha(_construct_t)
		queue_redraw()
		if _construct_t <= 0.0:
			modulate.a = 1.0
	if _upgrade_t > 0.0:
		_upgrade_t = maxf(0.0, _upgrade_t - delta)
		queue_redraw()


# ── Upgrade plumbing (mirrors BaseTower) ────────────────────────────────

func _level_override() -> Resource:
	if data == null or level <= 1 or data.level_upgrades.is_empty():
		return null
	var idx: int = mini(level - 2, data.level_upgrades.size() - 1)
	return data.level_upgrades[idx]


func _effective_soldier_data() -> Resource:
	var ov: Resource = _level_override()
	if ov != null and ov.soldier_data_override != null:
		return ov.soldier_data_override
	return data.soldier_data if data != null else null


func _effective_rally_range() -> float:
	var ov: Resource = _level_override()
	if ov != null and ov.soldier_rally_range > 0.0:
		return ov.soldier_rally_range
	return data.soldier_rally_range if data != null else 0.0


func get_sell_value() -> int:
	var ov: Resource = _level_override()
	if ov != null and ov.sell_value > 0:
		return ov.sell_value
	return data.sell_value if data != null else 0


func get_upgrade_cost_to(next_level: int) -> int:
	if data == null or next_level <= 1 or next_level > MAX_LEVEL:
		return 0
	var idx: int = next_level - 2
	if idx >= 0 and idx < data.level_upgrades.size():
		var ov: Resource = data.level_upgrades[idx]
		if ov != null and ov.cost > 0:
			return ov.cost
	# Legacy fallback, matching BaseTower behaviour.
	if next_level == 2:
		return data.upgrade_cost_lvl2
	return 0


func can_upgrade() -> bool:
	if level >= MAX_LEVEL:
		return false
	return get_upgrade_cost_to(level + 1) > 0


func upgrade() -> bool:
	if not can_upgrade():
		return false
	level += 1
	# Replace the squad on upgrade: new level, new SoldierData, fresh spawn.
	# Simpler than mutating each BaseSoldier's data reference mid-combat and
	# keeps enemy block release paths (tree_exiting on soldier) working.
	for soldier in _active_soldiers:
		if soldier != null and is_instance_valid(soldier):
			soldier.queue_free()
	_active_soldiers.clear()
	# Re-clamp the flag to the new rally radius (it may have grown or shrunk).
	_flag_offset = _constrain_flag_pos(_flag_offset)
	flag_area.position = _flag_offset
	_slot_positions = _build_slot_positions(_flag_offset)
	var sd: Resource = _effective_soldier_data()
	if sd != null:
		for i in sd.max_count:
			_spawn_soldier(i)
	_upgrade_t = _TowerAnimScript.UPGRADE_DURATION
	queue_redraw()
	EventBus.tower_upgraded.emit(self, level)
	return true


# Unified range accessor used by UI. See BaseTower.get_preview_range.
func get_preview_range() -> float:
	return _effective_rally_range()


func get_upgrade_range() -> float:
	if not can_upgrade():
		return 0.0
	var idx: int = level - 1
	if idx < 0 or idx >= data.level_upgrades.size():
		return 0.0
	var next: Resource = data.level_upgrades[idx]
	if next == null or next.soldier_rally_range <= 0.0:
		return 0.0
	return next.soldier_rally_range


# Tower Indicator Interface: barracks show rally range / squad size / soldier
# health instead of the combat-tower Dmg/Rng/Spd row.
func get_stats_line() -> String:
	var sd: Resource = _effective_soldier_data()
	var squad: int = 0
	var hp: int = 0
	if sd != null:
		squad = int(sd.max_count)
		hp = int(sd.max_health)
	return "Rally %d   Squad %d   HP %d" % [
		int(_effective_rally_range()),
		squad,
		hp,
	]


func get_preview_stats() -> Array:
	var sd: Resource = _effective_soldier_data()
	var squad: float = float(sd.max_count) if sd != null else 0.0
	var hp: float = float(sd.max_health) if sd != null else 0.0
	var dmg: float = float(sd.damage) if sd != null and "damage" in sd else 0.0
	var rows: Array = [
		{"label": "Rally", "value": _effective_rally_range(), "fmt": "%d"},
		{"label": "Squad", "value": squad, "fmt": "%d"},
		{"label": "HP", "value": hp, "fmt": "%d"},
	]
	if dmg > 0.0:
		rows.append({"label": "Dmg", "value": dmg, "fmt": "%d"})
	return rows


# Barracks have no attack — return 0 so any UI that asks for these fields
# renders as N/A instead of crashing. Stats card does NOT call these; it
# uses get_stats_line() which formats rally/squad/HP directly.
func get_effective_damage() -> float:
	return 0.0


func get_effective_attack_speed() -> float:
	return 0.0


func begin_rally_placement() -> void:
	if _placement_mode:
		return
	_placement_mode = true
	# Suppress flag drag during tap-to-place so a tap that happens to land on
	# the flag area isn't interpreted as the start of a drag.
	flag_area.input_pickable = false
	queue_redraw()


func _end_rally_placement() -> void:
	if not _placement_mode:
		return
	_placement_mode = false
	flag_area.input_pickable = true
	queue_redraw()


func _on_rally_move_requested(barracks: Node) -> void:
	if barracks == self:
		begin_rally_placement()


func _build_slot_positions(local_offset: Vector2) -> Array[Vector2]:
	# Per CORE RULE 13: every rally slot must land on the navmesh. The flag
	# itself is already snapped in _constrain_flag_pos, but the three derived
	# triangle corners can still fall off-mesh near edges — so snap each one.
	var base: Vector2 = global_position + local_offset
	var sx: float = data.soldier_spread.x
	var sy: float = data.soldier_spread.y
	var positions: Array[Vector2] = []
	positions.append(_snap_world_to_navmesh(base + Vector2(-sx, -sy)))
	positions.append(_snap_world_to_navmesh(base + Vector2(0, sy)))
	positions.append(_snap_world_to_navmesh(base + Vector2(sx, -sy)))
	return positions


# Shared navmesh-snap helper used by flag placement AND rally slot derivation.
# Returns the input unchanged when no valid navigation map is available
# (e.g. early _ready before World2D is wired).
func _snap_world_to_navmesh(world_pos: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return world_pos
	var map_rid: RID = world.navigation_map
	if not map_rid.is_valid():
		return world_pos
	return NavigationServer2D.map_get_closest_point(map_rid, world_pos)


func _spawn_soldier(slot_index: int) -> void:
	if slot_index >= _slot_positions.size():
		return
	var soldier: CharacterBody2D = data.soldier_scene.instantiate()
	# Override scene-default data with the current level's effective data so
	# upgraded barracks spawn the stronger SoldierData. Set BEFORE add_child
	# so BaseSoldier._ready sees the right stats. Duplicate the resource so
	# we can stamp a per-squad accent band without mutating the shared .tres.
	var sd: Resource = _effective_soldier_data()
	if sd != null:
		var personal: Resource = sd.duplicate(true)
		if personal.visual != null:
			personal.visual.accent_band_color = _squad_color()
		soldier.data = personal
	add_child(soldier)
	soldier.global_position = global_position
	if soldier.has_method("setup"):
		soldier.setup(_slot_positions[slot_index], _flag_world_pos())
	soldier.set_meta("slot_index", slot_index)
	_active_soldiers.append(soldier)
	EventBus.soldier_spawned.emit(soldier, self)


# World-space position of the rally flag. Barracks passes this to each
# soldier so the squad shares one engagement zone center (not per-slot).
func _flag_world_pos() -> Vector2:
	return global_position + _flag_offset


# Deterministic per-barracks accent color derived from the spot's world
# position. Stable across save/load because spot positions are fixed by the
# level. Drawn as a thin ring inside each soldier's body outline so players
# can tell which barracks owns which soldier in a crowded lane.
func _squad_color() -> Color:
	# `seed` is the name of Godot's built-in RNG-seeding function — renamed
	# to `h` here to avoid SHADOWED_GLOBAL_IDENTIFIER at parse time.
	var h: int = int(roundf(global_position.x)) * 73856093 ^ int(roundf(global_position.y)) * 19349663
	var hue: float = float(h & 0xFFFF) / 65535.0
	return Color.from_hsv(hue, 0.65, 0.95)


func _on_soldier_died(soldier: Node) -> void:
	var idx: int = _active_soldiers.find(soldier)
	if idx < 0:
		return
	_active_soldiers.remove_at(idx)
	var slot: int = int(soldier.get_meta("slot_index", 0))
	var respawn_time: float = 4.0
	var sd: Resource = _effective_soldier_data()
	if sd != null and "respawn_time" in sd:
		respawn_time = sd.respawn_time
	_respawn_after(respawn_time, slot)


func _respawn_after(seconds: float, slot: int) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree():
		return
	_spawn_soldier(slot)


func _input(event: InputEvent) -> void:
	# Runs before _unhandled_input, so the placement tap is consumed before
	# SpotInputManager can reopen TowerSpotMenu on the barracks' own spot.
	if not _placement_mode:
		return
	if event is InputEventScreenTouch and event.pressed:
		var local_pos: Vector2 = _screen_to_local(event.position)
		var max_r: float = _effective_rally_range()
		if max_r <= 0.0 or local_pos.length() <= max_r:
			_flag_offset = _constrain_flag_pos(local_pos)
			flag_area.position = _flag_offset
			_recall_soldiers()
		_end_rally_placement()
		get_viewport().set_input_as_handled()


func _on_flag_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dragging_flag = true
		queue_redraw()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _dragging_flag:
		return
	if event is InputEventScreenDrag:
		_flag_offset = _constrain_flag_pos(_screen_to_local(event.position))
		flag_area.position = _flag_offset
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		_dragging_flag = false
		_recall_soldiers()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _clamp_to_rally_range(local_pos: Vector2) -> Vector2:
	var max_r: float = _effective_rally_range()
	if max_r <= 0.0:
		return local_pos
	if local_pos.length() > max_r:
		return local_pos.normalized() * max_r
	return local_pos


# Enforces CORE RULE 13: the rally flag must land on the navmesh so soldiers
# always arrive on walkable terrain. Drag off-navmesh snaps to the nearest
# valid point. Rally-radius clamp runs on both sides of the snap so a snap
# that escapes the radius pulls back in.
func _constrain_flag_pos(local_pos: Vector2) -> Vector2:
	var in_range: Vector2 = _clamp_to_rally_range(local_pos)
	var snapped_world: Vector2 = _snap_world_to_navmesh(to_global(in_range))
	return _clamp_to_rally_range(to_local(snapped_world))


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _recall_soldiers() -> void:
	_slot_positions = _build_slot_positions(_flag_offset)
	var flag_pos: Vector2 = _flag_world_pos()
	for soldier in _active_soldiers:
		if soldier == null or not is_instance_valid(soldier):
			continue
		var slot_i: int = int(soldier.get_meta("slot_index", 0))
		if slot_i < _slot_positions.size() and soldier.has_method("set_blocking_position"):
			soldier.set_blocking_position(_slot_positions[slot_i], flag_pos)


func _draw() -> void:
	# Engagement zone — always-visible subtle ring around the flag showing
	# the area where soldiers will intercept enemies. Enemies outside this
	# ring are "not this barracks's problem" and are ignored. Radius =
	# soldier leash_range from the active squad's data.
	var sd: Resource = _effective_soldier_data()
	if sd != null and "leash_range" in sd and sd.leash_range > 0.0:
		draw_circle(_flag_offset, sd.leash_range, Color(0.9, 0.35, 0.35, 0.04))
		draw_arc(_flag_offset, sd.leash_range, 0, TAU, 48, Color(0.9, 0.35, 0.35, 0.35), 2.0)
	# Rally range preview — shown while dragging the flag OR while the
	# player is in tap-to-place mode (entered via TowerSpotMenu's "Move
	# Rally" button). Drawn before the tower body so the body sits on
	# top of the fill.
	var rally_r: float = _effective_rally_range()
	if (_dragging_flag or _placement_mode) and rally_r > 0.0:
		draw_circle(Vector2.ZERO, rally_r, Color(1.0, 0.9, 0.3, 0.08))
		draw_arc(Vector2.ZERO, rally_r, 0, TAU, 48, Color(1.0, 0.9, 0.3, 0.75), 5.0)
	# Construction dust ring under the body (identity transform — ground VFX).
	_TowerAnimScript.draw_construct_ring(self, _construct_t, 40.0)
	# Build + upgrade scale stack. Applied to the body only — flag sits at its
	# own world offset so scaling it would drift it outward from the barracks.
	var s_construct: float = _TowerAnimScript.construct_scale(_construct_t)
	var s_upgrade: float = _TowerAnimScript.upgrade_scale(_upgrade_t)
	var s: float = s_construct * s_upgrade
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# Tower body — tint per upgrade level for visual read.
	var body_color: Color = Color(0.55, 0.35, 0.2)
	var ov: Resource = _level_override()
	if ov != null:
		body_color = body_color * ov.tint
	draw_rect(Rect2(-50, -50, 100, 100), body_color)
	draw_rect(Rect2(-50, -50, 100, 100), Color(0.2, 0.1, 0.05), false, 6.25)
	# Level pips at the top so upgrade state is visible at a glance.
	for i in level:
		draw_circle(Vector2(-15.0 + i * 15.0, -60.0), 5.0, Color(1.0, 0.85, 0.2))
	draw_line(Vector2(-50, -20), Vector2(50, -20), Color(0.2, 0.1, 0.05), 3.75)
	# Back to identity so the flag + upgrade ring aren't dragged by the scale.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Rally flag at _flag_offset (pole + cloth)
	var pole_top: Vector2 = _flag_offset + Vector2(0, -55)
	draw_line(_flag_offset, pole_top, Color(0.25, 0.18, 0.08), 5.0)
	draw_colored_polygon(
		PackedVector2Array([
			pole_top,
			pole_top + Vector2(35, 10),
			pole_top + Vector2(0, 25),
		]),
		Color(0.85, 0.2, 0.2)
	)
	# Upgrade burst ring at the base.
	_TowerAnimScript.draw_upgrade_ring(self, _upgrade_t, 70.0)
