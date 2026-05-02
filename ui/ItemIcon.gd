extends Control
class_name ItemIcon

# Phase 48 D1 — reusable tile for EquipmentScreen slots + inventory grid.
# Procedural _draw() renders a rarity-tinted border + icon glyph. Mirrors
# TowerIconButton's render style (no sprites needed, works on any theme).
#
# Three modes:
#   - Empty slot (setup_empty): grey hatched square, no glyph, no rarity
#   - Filled (setup_instance): rarity-colored border, glyph in center,
#     optional "armed" outline for two-step-commit interaction
#   - Locked (setup_locked): padlock-style dim overlay, no click
#
# Emits `pressed(instance)` when clicked — null instance means empty slot
# was tapped (useful for "tap to unequip" UX).

signal pressed(instance)
signal hovered(instance)
signal unhovered
# IP-2 — fired when the user holds touch/click for >= LONG_PRESS_SECONDS.
# Mobile-friendly replacement for hover-only details (touch has no hover).
# When emitted, `pressed` is suppressed for that interaction so a long-press
# doesn't also accidentally equip / sell-arm the item.
signal long_pressed(instance)

const SIZE_PX: float = 120.0
const BORDER_THICKNESS_PX: float = 3.0
const ARMED_RING_THICKNESS_PX: float = 3.0
const GLYPH_RADIUS_PX: float = 36.0

# Rarity tints for the border — same palette as ItemPickup halo so drops
# the player sees on the ground match what they see in the UI.
const _RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.75),   # 0 COMMON
	Color(0.4, 0.7, 1.0),      # 1 MAGIC
	Color(1.0, 0.9, 0.3),      # 2 RARE
	Color(0.8, 0.4, 1.0),      # 3 EPIC
	Color(1.0, 0.55, 0.1),     # 4 LEGENDARY
]

# IP-1 — Per-rarity border thickness + background tint. Dramatic visual
# hierarchy at a glance (Common reads as plain, Legendary reads as obvious
# treasure). Index matches _RARITY_COLORS.
const _RARITY_BORDER_THICKNESS: Array[float] = [3.0, 4.0, 4.5, 5.0, 6.0]
# Background tints — base dark + a kiss of rarity color. Common keeps the
# original _FILLED_BG; higher rarities lerp toward their rarity color at
# small alpha so the icon glyph still reads.
const _RARITY_BG_TINT_AMOUNT: Array[float] = [0.0, 0.10, 0.16, 0.22, 0.30]

const _ARMED_COLOR: Color = Color(1.0, 0.95, 0.4)      # yellow (matches tower menu)
const _LOCKED_COLOR: Color = Color(0.25, 0.25, 0.25)
# Empty tiles need enough contrast to be visible against the screen
# background (which is ~0.1,0.14,0.18 in EquipmentScreen). Lifted bg + hot
# border so the cell reads clearly as "slot, no item".
const _EMPTY_BG: Color = Color(0.19, 0.22, 0.28)
const _EMPTY_BORDER: Color = Color(0.45, 0.48, 0.55)
const _EMPTY_PLUS_COLOR: Color = Color(0.38, 0.42, 0.5)
const _FILLED_BG: Color = Color(0.08, 0.08, 0.12)

# Phase 49 art pass — Diablo-Immortal-style layered tile rendering. Higher
# rarities accumulate decoration layers (glow, ornaments, sparkles) on top of
# the basic Common tile. Index matches _RARITY_COLORS:
#   0 Common    : tile + border + glyph                      (no flourish)
#   1 Magic     : + radial bg wash + soft inner glow + sheen
#   2 Rare      : + filigree corner ornaments + 2 sparkles
#   3 Epic      : + brighter glow + 4 sparkles
#   4 Legendary : + intense glow + 6 sparkles
const _SPARKLE_COUNTS: Array[int] = [0, 0, 2, 4, 6]
# Inner glow strength per rarity tier — alpha multiplier applied to the
# rarity color in concentric falloff rings.
const _GLOW_ALPHAS: Array[float] = [0.0, 0.18, 0.30, 0.42, 0.55]
# Glow ring thickness at the brightest layer (px at SIZE_PX scale).
const _GLOW_THICKNESS: Array[float] = [0.0, 4.0, 6.0, 8.0, 12.0]

var _instance = null
var _base: Resource = null
var _armed: bool = false
var _locked: bool = false
var _is_empty: bool = true
# Phase 49 — equipment slots claim a fixed footprint matching their item
# type (HELM 1×1, ARMOR 2×2, WEAPON 1×2, etc) so a sword appears at the
# same pixel size whether equipped or sitting in inventory. (0, 0) means
# "no slot override" — sizing falls back to the item's natural footprint
# (used by inventory icons).
var _slot_footprint: Vector2i = Vector2i.ZERO
# IP-3 — "do not sell" pin (separate from `_locked` which means slot-locked /
# disabled). When true, the icon draws a small padlock glyph in the
# upper-right corner; rendering is otherwise unchanged.
var _locked_for_sale: bool = false

# IP-2 — long-press tracking. Started on touch/mouse-down; if the press is
# released before LONG_PRESS_SECONDS, fires `pressed`. If the timer elapses
# while still pressed, fires `long_pressed` and marks `_long_press_consumed`
# so the eventual release is a no-op.
const LONG_PRESS_SECONDS: float = 0.45
var _press_timer: SceneTreeTimer = null
var _long_press_consumed: bool = false


func _ready() -> void:
	# Phase 49 — sizing now flows from setup_instance (base footprint) so that
	# multi-cell items (1×2, 2×2, ...) render at the right pixel size. Default
	# is 1×1 — that path serves equipment slot icons + empty placeholders, which
	# never mutate _base.
	_apply_footprint_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Phase 49 — pixel size = SIZE_PX * footprint. Sizing priority:
#   1. _slot_footprint when non-zero (equipment slot icons use a fixed
#      footprint matching their item type — items render at the same
#      size in inventory and in slots)
#   2. _base.grid_width × grid_height when an item is set
#   3. 1×1 fallback for empty / locked tiles
# Called from _ready, set_slot_footprint, and setup_instance — order-
# independent so callers can setup either before OR after add_child.
func _apply_footprint_size() -> void:
	var w: int = 1
	var h: int = 1
	if _slot_footprint != Vector2i.ZERO:
		w = maxi(1, _slot_footprint.x)
		h = maxi(1, _slot_footprint.y)
	elif _base != null:
		w = maxi(1, int(_base.grid_width))
		h = maxi(1, int(_base.grid_height))
	var px: Vector2 = Vector2(SIZE_PX * float(w), SIZE_PX * float(h))
	custom_minimum_size = px
	size = px


# Phase 49 — pin this icon to a fixed footprint regardless of which item
# (if any) is later equipped here. Used by equipment slot icons so the
# slot's shape matches its item type (HELM 1×1, ARMOR 2×2, WEAPON 1×2)
# and items render at the same pixel size as in inventory. Pass (0, 0) to
# revert to base-footprint sizing (the default for inventory icons).
func set_slot_footprint(w: int, h: int) -> void:
	_slot_footprint = Vector2i(maxi(0, w), maxi(0, h))
	_apply_footprint_size()


func _on_mouse_entered() -> void:
	if not _is_empty and not _locked:
		hovered.emit(_instance)


func _on_mouse_exited() -> void:
	unhovered.emit()


func setup_instance(inst) -> void:
	_instance = inst
	_base = null
	_is_empty = false
	_locked = false
	_locked_for_sale = inst != null and "locked" in inst and inst.locked
	if inst != null:
		_base = ContentRegistry.find_item_base(inst.base_id)
	_apply_footprint_size()
	queue_redraw()


func setup_empty() -> void:
	_instance = null
	_base = null
	_is_empty = true
	_locked = false
	queue_redraw()


func setup_locked() -> void:
	_instance = null
	_base = null
	_is_empty = true
	_locked = true
	queue_redraw()


func set_armed(on: bool) -> void:
	if _armed == on:
		return
	_armed = on
	queue_redraw()


func get_instance():
	return _instance


func _on_gui_input(event: InputEvent) -> void:
	if _locked:
		return
	# Press-down: start long-press timer. Release before timeout = pressed
	# emit; release after = long_pressed already fired, swallow this release.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press()
		else:
			_end_press()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_press()
		else:
			_end_press()


func _begin_press() -> void:
	_long_press_consumed = false
	# Cancel any stale timer (defensive — shouldn't normally happen).
	_press_timer = get_tree().create_timer(LONG_PRESS_SECONDS)
	var captured_timer: SceneTreeTimer = _press_timer
	captured_timer.timeout.connect(func():
		# Only fire if this captured timer is still the active one (the user
		# might have released and started a new press in the meantime).
		if is_instance_valid(self) and _press_timer == captured_timer and not _long_press_consumed:
			_long_press_consumed = true
			long_pressed.emit(_instance)
	)


func _end_press() -> void:
	# Clear the timer reference so any pending callback no-ops.
	_press_timer = null
	if _long_press_consumed:
		# Long-press already handled this interaction — don't double-fire pressed.
		_long_press_consumed = false
		return
	pressed.emit(_instance)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	# Use the shorter dimension as the scale factor so 1×2 swords (narrow +
	# tall) don't have effects sized by the long axis and clipped horizontally.
	var scale_factor: float = minf(rect.size.x, rect.size.y) / SIZE_PX
	# --- Empty / locked tiles ----------------------------------------------
	if _is_empty:
		_draw_empty_well(rect, scale_factor)
		if _locked:
			_draw_locked_overlay(rect, scale_factor)
		return
	# --- Filled tiles ------------------------------------------------------
	if _base == null:
		# Defensive — unknown base. Render a plain dark tile so the cell still
		# claims its space; mostly happens during a brief window if a content
		# .tres reference is missing.
		draw_rect(rect, _FILLED_BG, true)
		draw_rect(rect, _EMPTY_BORDER, false, BORDER_THICKNESS_PX)
		return
	var rarity: int = clampi(int(_base.rarity), 0, _RARITY_COLORS.size() - 1)
	var rarity_color: Color = _RARITY_COLORS[rarity]
	# Layer 1 — radial-ish background (4 concentric rects, brighter toward
	# the center). Common stays nearly flat; legendary glows from the middle.
	_draw_filled_background(rect, rarity, rarity_color)
	# Layer 2 — sheen sweep (Magic+). Faint white triangle in the upper-left
	# so the tile reads as polished glass rather than a flat sticker.
	if rarity >= 1:
		_draw_sheen(rect)
	# Layer 3 — inner glow ring (Magic+). Soft falloff of rarity color, drawn
	# inside the border so it "leaks" inward toward the glyph.
	if rarity >= 1:
		_draw_inner_glow(rect, rarity_color, rarity, scale_factor)
	# Layer 4 — beveled border. Outer line in rarity color; 1px highlight on
	# top/left edges and 1px shadow on bottom/right for inset metal feel.
	_draw_beveled_border(rect, rarity_color, _RARITY_BORDER_THICKNESS[rarity])
	# Layer 5 — filigree corner ornaments (Rare+). Small triangular flags at
	# each corner, rarity-colored, lightened toward white for richness.
	if rarity >= 2:
		_draw_corner_ornaments(rect, rarity_color, scale_factor)
	# Layer 6 — sparkles (Rare+). Seeded by item uid so they stay put across
	# redraws (no jitter), 4-point stars in a brightened rarity color.
	if rarity >= 2:
		_draw_sparkles(rect, rarity_color, rarity, scale_factor)
	# Layer 7 — glyph with drop shadow. Shadow first (offset down), then the
	# real glyph + rarity pips. Glyph radius scales with tile size.
	# Phase 49 — sword glyphs are taller than wide (~2.4:1 in r-units after
	# the 1.25× vertical stretch); use a separate calc that lets `r` grow
	# with tile height. Square glyphs (armor, trinkets, generic) keep the
	# old min(w,h)-based scale.
	var center: Vector2 = rect.position + rect.size * 0.5
	var glyph_id: String = String(_base.icon_glyph)
	var glyph_r: float
	if glyph_id.begins_with("sword"):
		# Half-extents in r-units after the stretch: sword is about ±0.55
		# wide (crossguard) and ±1.20 tall (blade tip to pommel bottom).
		var half_w: float = 0.55
		var half_h: float = 1.20
		var max_r_w: float = rect.size.x * 0.5 / half_w
		var max_r_h: float = rect.size.y * 0.5 / half_h
		# 0.92 leaves a small breathing margin at the tile edge.
		glyph_r = minf(max_r_w, max_r_h) * 0.92
	else:
		glyph_r = GLYPH_RADIUS_PX * scale_factor
	_draw_glyph_shadow(_base.icon_glyph, center, glyph_r, _base.icon_color)
	ItemGlyph.draw(self, _base.icon_glyph, center, glyph_r, _base.icon_color)
	ItemGlyph.draw_rarity_pips(self, rarity, center, glyph_r)
	# Layer 8 — armed outline (sell-mode confirm), drawn over everything.
	if _armed:
		var armed_rect: Rect2 = rect.grow(-1.0)
		draw_rect(armed_rect, _ARMED_COLOR, false, ARMED_RING_THICKNESS_PX)
	# Layer 9 — lock-for-sale padlock overlay (existing IP-3).
	if _locked_for_sale:
		var pad_size: Vector2 = Vector2(18.0, 18.0)
		var pad_pos: Vector2 = rect.position + Vector2(rect.size.x - pad_size.x - 4.0, 4.0)
		var pad_rect: Rect2 = Rect2(pad_pos, pad_size)
		draw_rect(pad_rect, Color(0.95, 0.85, 0.3, 0.95), true)
		draw_rect(pad_rect, Color(0.2, 0.16, 0.05, 1.0), false, 2.0)
		# Shackle — a small arc above the body, drawn as two short verticals
		# so we don't pull in draw_arc (cheap, readable).
		var shackle_y0: float = pad_pos.y - 5.0
		var shackle_y1: float = pad_pos.y + 1.0
		draw_line(Vector2(pad_pos.x + 4.0, shackle_y0), Vector2(pad_pos.x + 4.0, shackle_y1), Color(0.2, 0.16, 0.05, 1.0), 2.0)
		draw_line(Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y0), Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y1), Color(0.2, 0.16, 0.05, 1.0), 2.0)
		draw_line(Vector2(pad_pos.x + 4.0, shackle_y0), Vector2(pad_pos.x + pad_size.x - 4.0, shackle_y0), Color(0.2, 0.16, 0.05, 1.0), 2.0)


# --- Tile-art helpers (Phase 49) ---------------------------------------------
# All helpers operate in local Control coordinates (rect.position is usually
# Vector2.ZERO). scale_factor is min(width,height) / SIZE_PX so effects shrink
# proportionally on narrow 1×2 / 1×1 tiles and grow on 2×2 / slot tiles.


# Empty inventory placeholder + empty equipment slot. Reads as a recessed
# "well" — outer ring slightly lit, inner area slightly darker, soft "+"
# mark in the middle. Lower-contrast than a filled tile so the eye skips
# over empty cells when scanning the grid for items.
func _draw_empty_well(rect: Rect2, scale_factor: float) -> void:
	# Outer ring (lighter) draws first, then a darker inner inset overlays it.
	draw_rect(rect, _EMPTY_BG, true)
	var inner_inset: float = 6.0 * scale_factor
	var inner_rect: Rect2 = rect.grow(-inner_inset)
	draw_rect(inner_rect, _EMPTY_BG.darkened(0.15), true)
	# Thin border so the cell edge is still readable.
	draw_rect(rect, _EMPTY_BORDER, false, 1.5)
	# Subtle "+" mark in the center.
	var center: Vector2 = rect.position + rect.size * 0.5
	var arm: float = rect.size.x * 0.16
	draw_line(center + Vector2(-arm, 0), center + Vector2(arm, 0), _EMPTY_PLUS_COLOR, 2.0)
	draw_line(center + Vector2(0, -arm), center + Vector2(0, arm), _EMPTY_PLUS_COLOR, 2.0)


# Crosshatch + small padlock badge over an already-drawn empty well, used for
# equipment slots that aren't unlockable yet (HELM, GLOVES, BOOTS pre-Phase-F).
func _draw_locked_overlay(rect: Rect2, scale_factor: float) -> void:
	var cross: Color = Color(0.4, 0.4, 0.4, 0.4)
	draw_line(rect.position, rect.position + rect.size, cross, 2.0)
	draw_line(Vector2(rect.position.x + rect.size.x, rect.position.y),
			  Vector2(rect.position.x, rect.position.y + rect.size.y),
			  cross, 2.0)
	# Tiny padlock badge centered. Body + top shackle drawn from primitives.
	var center: Vector2 = rect.position + rect.size * 0.5
	var body_size: Vector2 = Vector2(18.0, 16.0) * scale_factor
	var body_rect: Rect2 = Rect2(center - body_size * 0.5, body_size)
	draw_rect(body_rect, Color(0.55, 0.55, 0.6, 0.9), true)
	draw_rect(body_rect, Color(0.2, 0.2, 0.25, 1.0), false, 1.5)
	var shackle_w: float = body_size.x * 0.55
	var shackle_top: Vector2 = Vector2(center.x, body_rect.position.y - 4.0 * scale_factor)
	draw_line(Vector2(center.x - shackle_w * 0.5, body_rect.position.y),
			  Vector2(center.x - shackle_w * 0.5, shackle_top.y),
			  Color(0.2, 0.2, 0.25, 1.0), 1.5)
	draw_line(Vector2(center.x + shackle_w * 0.5, body_rect.position.y),
			  Vector2(center.x + shackle_w * 0.5, shackle_top.y),
			  Color(0.2, 0.2, 0.25, 1.0), 1.5)
	draw_line(Vector2(center.x - shackle_w * 0.5, shackle_top.y),
			  Vector2(center.x + shackle_w * 0.5, shackle_top.y),
			  Color(0.2, 0.2, 0.25, 1.0), 1.5)


# Radial-ish background using 3 concentric inset rects with progressively
# brighter rarity-tinted color. Cheaper than a real radial gradient and
# produces the same "glowing from the middle" feel.
func _draw_filled_background(rect: Rect2, rarity: int, rarity_color: Color) -> void:
	var bg_base: Color = _FILLED_BG
	var center_color: Color = bg_base.lerp(rarity_color, _RARITY_BG_TINT_AMOUNT[rarity])
	# Outer dark.
	draw_rect(rect, bg_base, true)
	# 3 brightening insets. Each step shrinks more and is closer to center_color.
	var steps: int = 3
	for i in steps:
		var t: float = float(i + 1) / float(steps + 1)
		var inset_amt: float = rect.size.x * t * 0.12
		var step_rect: Rect2 = rect.grow(-inset_amt)
		var step_color: Color = bg_base.lerp(center_color, t)
		# Alpha fade from edge → center so layers blend rather than hard-step.
		step_color.a = 0.45 + t * 0.4
		draw_rect(step_rect, step_color, true)


# Faint diagonal highlight at the upper-left — reads as a soft "polish" sheen
# on metal/glass. White at low alpha so it doesn't fight the rarity color.
func _draw_sheen(rect: Rect2) -> void:
	var sheen_color: Color = Color(1.0, 1.0, 1.0, 0.07)
	var pts: PackedVector2Array = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x * 0.5, 0.0),
		rect.position + Vector2(0.0, rect.size.y * 0.5),
	])
	draw_colored_polygon(pts, sheen_color)


# Concentric inset rectangles with falling alpha — approximates a Gaussian-ish
# inner glow that brightens the area just inside the border. Brighter for
# higher rarities (controlled by _GLOW_ALPHAS / _GLOW_THICKNESS tables).
func _draw_inner_glow(rect: Rect2, color: Color, rarity: int, scale_factor: float) -> void:
	var max_thickness: float = _GLOW_THICKNESS[rarity] * scale_factor
	var max_alpha: float = _GLOW_ALPHAS[rarity]
	var steps: int = 4
	for i in steps:
		var t: float = float(i) / float(steps - 1)  # 0..1
		var inset_amt: float = 1.5 * float(i) * scale_factor
		var glow_rect: Rect2 = rect.grow(-inset_amt)
		var glow_color: Color = color
		glow_color.a = max_alpha * (1.0 - t)
		var thickness: float = maxf(1.0, max_thickness * (1.0 - t) * 0.5)
		draw_rect(glow_rect, glow_color, false, thickness)


# Outer rarity border + 1px highlight on top/left + 1px shadow on bottom/right.
# The bevel turns the flat tile into something that reads as inset metal.
func _draw_beveled_border(rect: Rect2, color: Color, thickness: float) -> void:
	draw_rect(rect, color, false, thickness)
	# Highlight (top + left).
	var hl: Color = color.lightened(0.35)
	hl.a = 0.7
	draw_line(rect.position,
			  Vector2(rect.position.x + rect.size.x, rect.position.y),
			  hl, 1.0)
	draw_line(rect.position,
			  Vector2(rect.position.x, rect.position.y + rect.size.y),
			  hl, 1.0)
	# Shadow (bottom + right).
	var sh: Color = color.darkened(0.45)
	sh.a = 0.7
	draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
			  rect.position + rect.size, sh, 1.0)
	draw_line(Vector2(rect.position.x + rect.size.x, rect.position.y),
			  rect.position + rect.size, sh, 1.0)


# Filigree corner ornaments — small rarity-colored triangles at each corner.
# Brightens toward white so they read as gold leaf rather than a darker line.
func _draw_corner_ornaments(rect: Rect2, color: Color, scale_factor: float) -> void:
	var orn_size: float = 9.0 * scale_factor
	var orn_inset: float = 3.0 * scale_factor
	var orn_color: Color = color.lightened(0.25)
	orn_color.a = 0.85
	# Top-left.
	var p_tl: Vector2 = rect.position + Vector2(orn_inset, orn_inset)
	draw_colored_polygon(PackedVector2Array([
		p_tl, p_tl + Vector2(orn_size, 0.0), p_tl + Vector2(0.0, orn_size),
	]), orn_color)
	# Top-right.
	var p_tr: Vector2 = Vector2(rect.position.x + rect.size.x - orn_inset, rect.position.y + orn_inset)
	draw_colored_polygon(PackedVector2Array([
		p_tr, p_tr - Vector2(orn_size, 0.0), p_tr + Vector2(0.0, orn_size),
	]), orn_color)
	# Bottom-left.
	var p_bl: Vector2 = Vector2(rect.position.x + orn_inset, rect.position.y + rect.size.y - orn_inset)
	draw_colored_polygon(PackedVector2Array([
		p_bl, p_bl + Vector2(orn_size, 0.0), p_bl - Vector2(0.0, orn_size),
	]), orn_color)
	# Bottom-right.
	var p_br: Vector2 = rect.position + rect.size - Vector2(orn_inset, orn_inset)
	draw_colored_polygon(PackedVector2Array([
		p_br, p_br - Vector2(orn_size, 0.0), p_br - Vector2(0.0, orn_size),
	]), orn_color)


# Sparkles — small 4-point stars at uid-seeded positions. Stable across
# redraws so the player doesn't see them jitter on every hover/refresh.
# Count scales with rarity (Rare 2 → Legendary 6).
func _draw_sparkles(rect: Rect2, color: Color, rarity: int, scale_factor: float) -> void:
	var count: int = _SPARKLE_COUNTS[rarity]
	if count <= 0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if _instance != null and "uid" in _instance:
		rng.seed = hash(_instance.uid)
	else:
		rng.seed = 12345  # stable fallback for previews / placeholder paths
	var sparkle_size: float = 3.0 * scale_factor
	var sparkle_color: Color = color.lightened(0.5)
	sparkle_color.a = 0.9
	var inset: float = rect.size.x * 0.18
	for _i in count:
		var x: float = rng.randf_range(rect.position.x + inset, rect.position.x + rect.size.x - inset)
		var y: float = rng.randf_range(rect.position.y + inset, rect.position.y + rect.size.y - inset)
		_draw_one_sparkle(Vector2(x, y), sparkle_size, sparkle_color)


# 4-point star: cross + tiny center dot. Cheap and reads at small sizes.
func _draw_one_sparkle(pos: Vector2, sz: float, color: Color) -> void:
	draw_line(pos + Vector2(-sz, 0.0), pos + Vector2(sz, 0.0), color, 1.5)
	draw_line(pos + Vector2(0.0, -sz), pos + Vector2(0.0, sz), color, 1.5)
	draw_circle(pos, sz * 0.35, color)


# Glyph drop shadow — draw the same glyph offset down + dark + low alpha,
# THEN the real glyph paints on top. Adds depth so the icon sits on the tile
# rather than floating in 2D.
func _draw_glyph_shadow(glyph_name: String, center: Vector2, glyph_r: float, _icon_color: Color) -> void:
	var shadow_offset: Vector2 = Vector2(0.0, 2.5)
	var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.4)
	ItemGlyph.draw(self, glyph_name, center + shadow_offset, glyph_r, shadow_color)
