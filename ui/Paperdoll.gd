extends Control
class_name Paperdoll

# Phase 50 — Equipment-screen backdrop. Replaces the prior HeroPortrait.
# Draws the hero's UnitVisualData faded behind a paperdoll layout, and
# exposes `anchor_for_slot(slot_idx)` so EquipmentScreen can position its
# slot ItemIcons at the right place for THIS hero.
#
# Default humanoid anchors are constants below; HeroData.slot_anchors lets
# any hero (e.g. Dragon) override per-slot positions. Anchors are
# normalized 0..1 of this control's size — 0,0 is top-left.

# Default anchor positions for the 6 humanoid slots (0..1 normalized).
# slot indices match ItemBase.slot: 0=Weapon, 1=Armor, 2=Helm, 3=Gloves, 4=Boots, 5=Trinket.
const DEFAULT_HUMANOID_ANCHORS: Dictionary = {
	0: Vector2(0.18, 0.62),   # Weapon — held in left hand
	1: Vector2(0.50, 0.46),   # Armor — chest
	2: Vector2(0.50, 0.10),   # Helm — above head
	3: Vector2(0.82, 0.62),   # Gloves — opposite hand
	4: Vector2(0.50, 0.88),   # Boots — feet
	5: Vector2(0.82, 0.18),   # Trinket — neck/shoulder
}

const _BG_COLOR: Color = Color(0.07, 0.09, 0.12, 1.0)
const _BORDER_COLOR: Color = Color(0.25, 0.30, 0.40, 1.0)
const _FLOOR_COLOR: Color = Color(0.13, 0.16, 0.22, 1.0)
# Optional decorative connector lines from anchor to the silhouette body —
# subtle, just enough to read "this slot is part of the figure".
const _CONNECTOR_COLOR: Color = Color(0.22, 0.27, 0.36, 0.55)
const _DEFAULT_PAPERDOLL_ALPHA: float = 0.35
const _DRAW_SCALE: float = 4.5
# Hero feet sit at this fraction of the panel height — the anchor frame
# matches HeroPortrait's framing so existing visuals look right.
const _ANCHOR_FRACTION: float = 0.85

var _hero_data: Resource = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func setup(hero_data: Resource) -> void:
	_hero_data = hero_data
	queue_redraw()


# Returns the absolute pixel position (within this Control's local space)
# for the given slot index, using the hero's authored anchor or the
# default humanoid anchor as a fallback. Callers center their slot widget
# on this point.
#
# Layout-time guard: at the moment EquipmentScreen._ready calls _build_slots,
# `size` is still (0, 0) because the parent HBoxContainer hasn't run its
# layout pass yet. Falling back to custom_minimum_size keeps slot positions
# stable on first build; later layout passes don't move the icons because
# their position is set absolute and doesn't track resize.
func anchor_for_slot(slot_idx: int) -> Vector2:
	var norm: Vector2 = _normalized_anchor_for_slot(slot_idx)
	var w: float = maxf(size.x, custom_minimum_size.x)
	var h: float = maxf(size.y, custom_minimum_size.y)
	return Vector2(norm.x * w, norm.y * h)


func _normalized_anchor_for_slot(slot_idx: int) -> Vector2:
	if _hero_data != null and "slot_anchors" in _hero_data:
		var overrides: Dictionary = _hero_data.slot_anchors
		if overrides.has(slot_idx):
			var v = overrides[slot_idx]
			if v is Vector2:
				return v
	if DEFAULT_HUMANOID_ANCHORS.has(slot_idx):
		return DEFAULT_HUMANOID_ANCHORS[slot_idx]
	# Fallback for unknown slot_id — top-center.
	return Vector2(0.5, 0.1)


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
	var center: Vector2 = Vector2(size.x * 0.5, size.y * _ANCHOR_FRACTION)
	# Floor disc — pre-figure so the figure draws on top.
	var floor_y: float = center.y + _DRAW_SCALE * 16.0
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
	UnitVisualDrawer.draw_unit(self, _hero_data.visual, center, Vector2(_DRAW_SCALE, _DRAW_SCALE), -1.0, 0.0, ctx)
