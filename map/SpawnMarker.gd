@tool
extends Node2D

# Editor-only authoring annotation for path-spawn locations. WaveCallIndicator
# anchors its Send-Wave badge at the Path2D's first curve-point at runtime;
# this marker exists for the 2D-editor preview (yellow arrow + enemy-icon)
# and as a FALLBACK anchor if the path lookup ever fails (typo / partially-
# authored level). `_draw()` is gated to `Engine.is_editor_hint()` so the
# preview never renders at runtime — the badge owns the spawn-point UI.

@export var path_id: String = ""
@export_range(0.0, 360.0) var direction_degrees: float = 0.0
@export var enemy_icon_color: Color = Color(0.55, 0.55, 0.65, 0.85)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	# Editor-only: authors need the arrow visible while placing the marker in
	# the 2D editor. At runtime the WaveCallIndicator badge (CanvasLayer 7)
	# owns the spawn-point UI — drawing here would just stack a permanent
	# yellow arrow under the badge.
	if not Engine.is_editor_hint():
		return
	var rad := deg_to_rad(direction_degrees)
	var dir := Vector2(cos(rad), sin(rad))
	var perp := Vector2(-dir.y, dir.x)

	var tip := dir * 34.0
	var base_l := dir * 6.0 + perp * 18.0
	var base_r := dir * 6.0 - perp * 18.0
	draw_colored_polygon(
		PackedVector2Array([tip, base_l, base_r]),
		Color(0.95, 0.85, 0.2)
	)
	draw_line(base_l, base_r, Color(0.25, 0.18, 0.05), 2.0)
	draw_line(base_l, tip, Color(0.25, 0.18, 0.05), 2.0)
	draw_line(base_r, tip, Color(0.25, 0.18, 0.05), 2.0)

	var icon_pos := -dir * 22.0
	draw_circle(icon_pos, 12.0, enemy_icon_color)
	draw_arc(icon_pos, 12.0, 0, TAU, 20, Color(0.1, 0.05, 0.05), 2.0)
