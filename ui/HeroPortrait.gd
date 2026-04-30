extends Control
class_name HeroPortrait

# Phase 49 — character preview drawn into the equipment screen via the
# existing UnitVisualDrawer (same procedural body the hero uses in-game,
# so no new art is needed). Sits between the two equipped-slot columns.
#
# Caller flow:
#   portrait.setup(hero_data)   # any HeroData with `visual: UnitVisualData`
#
# The visual is centered horizontally; vertical anchor sits at ~70% down
# so the legs land at the bottom of the frame and the head reads
# prominently in the upper portion (matches Diablo Immortal's framing).

const _DrawScale: float = 4.5
const _BackgroundColor: Color = Color(0.07, 0.09, 0.12, 1.0)
const _BorderColor: Color = Color(0.45, 0.48, 0.55, 1.0)
const _BorderThickness: float = 2.0
# Floor disc — subtle elliptical highlight under the hero's feet so the body
# reads as standing on something rather than floating in a void. Cheap and
# reads at any panel size.
const _FloorColor: Color = Color(0.13, 0.16, 0.22, 1.0)
# Vertical anchor — hero's feet land roughly at this fraction of panel height.
# 0.85 keeps a small floor strip below the legs and pushes the head up so the
# warrior fills more of the frame.
const _AnchorFraction: float = 0.85

var _visual: Resource = null  # UnitVisualData


func _ready() -> void:
	# A flat panel that doesn't intercept clicks. The screen still routes
	# taps through the normal slot/inventory icons; the portrait is decor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(hero_data: Resource) -> void:
	# Pull the visual off whatever HeroData was passed (defensive — older
	# heroes might not have `visual` set yet).
	_visual = null
	if hero_data != null and "visual" in hero_data:
		_visual = hero_data.visual
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, _BackgroundColor, true)
	draw_rect(rect, _BorderColor, false, _BorderThickness)
	if _visual == null:
		return
	# Anchor: horizontally centered, vertically near the bottom so the hero's
	# legs land just above a subtle floor disc. The 4.5× scale plus this
	# anchor lets the warrior fill ~70% of the panel height.
	var center: Vector2 = Vector2(size.x * 0.5, size.y * _AnchorFraction)
	# Floor disc — a flattened ellipse drawn below the feet. Hand-drawn via
	# draw_polyline since draw_arc fills are limited; a 24-segment ring works.
	var floor_y: float = center.y + _DrawScale * 16.0
	var floor_rx: float = size.x * 0.32
	var floor_ry: float = 12.0
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 25:
		var ang: float = TAU * float(i) / 24.0
		pts.append(Vector2(center.x + cos(ang) * floor_rx, floor_y + sin(ang) * floor_ry))
	draw_colored_polygon(pts, _FloorColor)
	UnitVisualDrawer.draw_unit(self, _visual, center, Vector2(_DrawScale, _DrawScale))
