extends Control
class_name EmptySkillSlot

# Phase 48 — placeholder rendered for an unequipped slot in the in-level
# skill cluster. Dimmed circle with a "+" glyph; tapping it tells the
# player where to set up their loadout. Visual sibling to CooldownButton
# so the cluster reads as N×80px tiles regardless of equipped state.

const SIZE: Vector2 = Vector2(80.0, 80.0)
const ARC_STEPS: int = 32


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		accept_event()
		Toast.show_message("Set skills in Heroes → Skills")


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.45
	# Dim disk with a thin border — reads as "slot exists but empty" vs a
	# CooldownButton's filled tile.
	draw_circle(center, radius, Color(0.10, 0.12, 0.16, 0.65))
	draw_arc(center, radius, 0.0, TAU, ARC_STEPS,
		Color(0.40, 0.44, 0.52, 0.85), 2.0, true)
	# "+" glyph — two crossed lines.
	var arm: float = radius * 0.45
	var thickness: float = 4.0
	var col: Color = Color(0.75, 0.78, 0.85, 0.85)
	draw_line(center + Vector2(-arm, 0), center + Vector2(arm, 0), col, thickness)
	draw_line(center + Vector2(0, -arm), center + Vector2(0, arm), col, thickness)
