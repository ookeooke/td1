extends CanvasLayer

# Phase 22 spell panel. Bottom-left column of spell buttons, one per spell
# in `spells` (set in Main.tscn via Inspector; Phase 30 LoadoutScreen will
# populate this from player selection instead).
#
# Mirrors SkillBar architecture: CooldownButton per entry, modal AREA
# targeting via _input consumption, yellow range preview while armed.
# Unlike skills, spells have no caster unit, so the panel itself is the
# "caster" passed into apply().
#
# Provider contract for CooldownButton: `cooldown_fraction(idx)` +
# `display_name(idx)`.

const CooldownButtonScene: PackedScene = preload("res://ui/CooldownButton.tscn")
const _SpellDataScript: Script = preload("res://spells/SpellData.gd")
const TARGET_TAP_TOLERANCE: float = 80.0

@export var spells: Array[Resource] = []

@onready var button_column: VBoxContainer = %ButtonColumn

var _cooldowns: Array[float] = []
var _targeting_idx: int = -1
var _buttons: Array = []


func _ready() -> void:
	_cooldowns.resize(spells.size())
	_cooldowns.fill(0.0)
	_build_buttons()


func _physics_process(delta: float) -> void:
	# Tick cooldowns + emit spell_ready crossings for any future listeners.
	for i in _cooldowns.size():
		if _cooldowns[i] <= 0.0:
			continue
		var before: float = _cooldowns[i]
		_cooldowns[i] = maxf(0.0, _cooldowns[i] - delta)
		if before > 0.0 and _cooldowns[i] <= 0.0:
			var spell: Resource = spells[i]
			if spell != null:
				EventBus.spell_ready.emit(spell.spell_name)


func _process(_delta: float) -> void:
	for btn in _buttons:
		if btn.has_method("refresh"):
			btn.refresh()


func _build_buttons() -> void:
	for child in button_column.get_children():
		child.queue_free()
	_buttons.clear()
	for i in spells.size():
		var btn: Control = CooldownButtonScene.instantiate()
		btn.setup(self, i)
		btn.triggered.connect(_on_spell_button_pressed)
		button_column.add_child(btn)
		_buttons.append(btn)


# ── CooldownButton provider contract ──────────────────────────────────

func cooldown_fraction(idx: int) -> float:
	if idx < 0 or idx >= spells.size():
		return 0.0
	var spell: Resource = spells[idx]
	if spell == null or spell.cooldown <= 0.0:
		return 0.0
	return clampf(_cooldowns[idx] / spell.cooldown, 0.0, 1.0)


func display_name(idx: int) -> String:
	if idx < 0 or idx >= spells.size():
		return "?"
	var spell: Resource = spells[idx]
	if spell == null:
		return "?"
	return spell.spell_name


# ── Targeting + cast ──────────────────────────────────────────────────

func _on_spell_button_pressed(idx: int) -> void:
	if idx < 0 or idx >= spells.size():
		return
	if _cooldowns[idx] > 0.0:
		return
	if _targeting_idx == idx:
		_cancel_targeting()
		return
	_targeting_idx = idx


func _cancel_targeting() -> void:
	_targeting_idx = -1


func _input(event: InputEvent) -> void:
	# Consume the cast tap before SpotInputManager / hero / HeroInputManager
	# can react, same discipline as SkillBar.
	if _targeting_idx < 0:
		return
	if get_viewport().is_input_handled():
		return
	if not (event is InputEventScreenTouch):
		return
	if not event.pressed:
		return
	var world_pos: Vector2 = _screen_to_world(event.position)
	var spell: Resource = spells[_targeting_idx]
	# cast_range = 0 means unlimited — spells can hit anywhere on the map.
	# Otherwise we enforce the range. Current Fireball uses 0.
	spell.apply(world_pos, self)
	# Phase 28: permanent upgrade (Spell Mastery = type 5).
	_cooldowns[_targeting_idx] = spell.cooldown * GameState.get_upgrade_multiplier(GameState.MOD_SPELL_COOLDOWN)
	EventBus.spell_cast.emit(spell.spell_name, world_pos)
	EventBus.spell_cooldown_started.emit(spell.spell_name, spell.cooldown)
	_cancel_targeting()
	get_viewport().set_input_as_handled()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var map: Node2D = get_tree().root.find_child("Level1", true, false) as Node2D
	if map == null:
		return screen_pos
	return map.get_global_transform_with_canvas().affine_inverse() * screen_pos


