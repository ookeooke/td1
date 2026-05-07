extends Control
class_name Paperdoll

# Phase 50 — Equipment-screen backdrop. Replaces the prior HeroPortrait.
# Draws the hero's UnitVisualData faded behind a paperdoll layout, and
# exposes `anchor_for_slot(slot_idx)` so EquipmentScreen can position its
# slot ItemIcons at the right place for THIS hero.
#
# Phase 55f — Slot positions are authored as Marker2D children named
# `Slot0`..`Slot5` (indices match `ItemBase.Slot`). Drag them in the
# Godot 2D viewport to reposition; runtime reads `marker.position` in
# this Control's local space. Mirrors the `TowerSpots → Spot1` and
# `LevelMarkers → level_1` pattern (CLAUDE.md "scene-tree nodes for
# authored geometry" rule).
#
# Resolution order for a given slot:
#   1. `HeroData.slot_anchors` per-hero override (normalized 0..1, used
#      by Dragon for its custom 3-slot layout).
#   2. `Slot<N>` Marker2D child of this Control (absolute pixels).
#   3. `DEFAULT_HUMANOID_ANCHORS` const fallback (normalized 0..1) — kept
#      so any future scene that forgets to add markers still works.

# Fallback humanoid anchors (0..1 normalized of this Control's size).
# Used only when no Marker2D child exists for the slot AND no HeroData
# override is set. Slot indices match ItemBase.slot.
const DEFAULT_HUMANOID_ANCHORS: Dictionary = {
	0: Vector2(0.18, 0.62),   # Weapon — held in left hand
	1: Vector2(0.50, 0.46),   # Armor — chest
	2: Vector2(0.50, 0.10),   # Helm — above head
	3: Vector2(0.82, 0.62),   # Gloves — opposite hand
	4: Vector2(0.50, 0.88),   # Boots — feet
	5: Vector2(0.82, 0.18),   # Trinket — neck/shoulder
}

# Marker2D child naming convention. `Slot0` .. `Slot5` matches ItemBase.Slot
# enum values; readable in the scene tree and matches the scene-graph-as-
# data pattern used elsewhere in the project.
const _SLOT_MARKER_PREFIX: String = "Slot"

const _BG_COLOR: Color = Color(0.07, 0.09, 0.12, 1.0)
const _BORDER_COLOR: Color = Color(0.25, 0.30, 0.40, 1.0)
const _FLOOR_COLOR: Color = Color(0.13, 0.16, 0.22, 1.0)
# Optional decorative connector lines from anchor to the silhouette body —
# subtle, just enough to read "this slot is part of the figure".
const _CONNECTOR_COLOR: Color = Color(0.22, 0.27, 0.36, 0.55)
const _DEFAULT_PAPERDOLL_ALPHA: float = 0.35
# Phase 55d — silhouette right-sized for the larger 600×720 grid + 120×144
# slot icons. Was 4.5 (Phase 50, sized for 540×600 grid + square 120×120
# cells) which produced a figure that filled most of the grid and visually
# fought the slots. 3.5 leaves a clean ring of slots around a smaller,
# centered figure. Phase 55f exposed for inspector-side tweaking — change
# in the EquipmentGrid node's Inspector pane, not in code.
@export var draw_scale: float = 3.5
# Hero figure pivot. Phase 55d lowered from 0.85 ("near the bottom",
# matching HeroPortrait's feet-on-ground framing) to 0.70 so the smaller
# silhouette sits roughly in the middle of the taller grid. Phase 55f
# exposed so it can be tuned visually with live preview in the editor.
@export_range(0.0, 1.0, 0.01) var anchor_fraction: float = 0.70

var _hero_data: Resource = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Clip the procedural hero silhouette to the paperdoll bounds so its body
	# / legs don't bleed down into the stats panel below.
	clip_contents = true
	queue_redraw()


func setup(hero_data: Resource) -> void:
	_hero_data = hero_data
	queue_redraw()


# Returns the absolute pixel position (within this Control's local space)
# for the given slot index. Resolution order:
#   1. HeroData.slot_anchors override (normalized 0..1)
#   2. Marker2D child named "Slot<N>" (absolute pixels)
#   3. DEFAULT_HUMANOID_ANCHORS fallback (normalized 0..1)
# Callers center their slot widget on the returned point.
#
# Layout-time guard: at the moment EquipmentScreen._ready calls _build_slots,
# `size` is still (0, 0) because the parent HBoxContainer hasn't run its
# layout pass yet. Normalized paths fall back to custom_minimum_size; the
# Marker2D path is unaffected (positions are absolute pixels in local space).
func anchor_for_slot(slot_idx: int) -> Vector2:
	# 1. Per-hero HeroData override wins.
	if _hero_data != null and "slot_anchors" in _hero_data:
		var overrides: Dictionary = _hero_data.slot_anchors
		if overrides.has(slot_idx):
			var v = overrides[slot_idx]
			if v is Vector2:
				return _norm_to_pixel(v)
	# 2. Marker2D child — visual editor-authored position.
	var marker_name: String = "%s%d" % [_SLOT_MARKER_PREFIX, slot_idx]
	var marker: Marker2D = get_node_or_null(marker_name) as Marker2D
	if marker != null:
		return marker.position
	# 3. Default fallback (normalized).
	if DEFAULT_HUMANOID_ANCHORS.has(slot_idx):
		return _norm_to_pixel(DEFAULT_HUMANOID_ANCHORS[slot_idx])
	# Last-resort fallback — top-center.
	return _norm_to_pixel(Vector2(0.5, 0.1))


func _norm_to_pixel(norm: Vector2) -> Vector2:
	var w: float = maxf(size.x, custom_minimum_size.x)
	var h: float = maxf(size.y, custom_minimum_size.y)
	return Vector2(norm.x * w, norm.y * h)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, _BG_COLOR, true)
	draw_rect(rect, _BORDER_COLOR, false, 2.0)
	if _hero_data == null or not ("visual" in _hero_data) or _hero_data.visual == null:
		return
	# Faded silhouette — same anchor framing as HeroPortrait so existing
	# visuals look identical, just dim. Floor disc included so the figure
	# reads as standing rather than floating.
	var alpha: float = _DEFAULT_PAPERDOLL_ALPHA
	if "paperdoll_alpha" in _hero_data:
		alpha = clampf(float(_hero_data.paperdoll_alpha), 0.0, 1.0)
	var center: Vector2 = Vector2(size.x * 0.5, size.y * anchor_fraction)
	# Floor disc — pre-figure so the figure draws on top.
	var floor_y: float = center.y + draw_scale * 16.0
	var floor_rx: float = size.x * 0.32
	var floor_ry: float = 12.0
	var floor_pts: PackedVector2Array = PackedVector2Array()
	for i in 25:
		var ang: float = TAU * float(i) / 24.0
		floor_pts.append(Vector2(center.x + cos(ang) * floor_rx, floor_y + sin(ang) * floor_ry))
	draw_colored_polygon(floor_pts, _FLOOR_COLOR)
	# Faded silhouette — UnitVisualDrawer's `skin_tint` multiplies into every
	# body part color, so passing white-with-alpha fades the whole figure.
	var ctx := {"skin_tint": Color(1.0, 1.0, 1.0, alpha)}
	UnitVisualDrawer.draw_unit(self, _hero_data.visual, center, Vector2(draw_scale, draw_scale), -1.0, 0.0, ctx)
