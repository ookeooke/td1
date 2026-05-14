extends Node2D

# Phase 48 C2 — world-space ground drop spawned by LootDropper at an
# enemy's death position. Draws a rarity-tinted circle that bobs gently to
# catch the eye. After LIFETIME_S it auto-collects (DI-style generous; the
# player never loses drops). Tap-to-collect arrives in C3 via
# ItemPickupManager; C2 drops collect only on timeout.

const LIFETIME_S: float = 30.0
const TAP_RADIUS: float = 50.0
const BOB_HEIGHT_PX: float = 6.0
const BOB_PERIOD_S: float = 1.6
const ICON_RADIUS_PX: float = 18.0
const HALO_THICKNESS_PX: float = 3.0
# Diablo-style beacon. Vertical light beam + ground aura intensify with
# rarity so a legendary drop reads from across the map while a common drop
# is a quiet halo. Per-rarity intensity multiplier drives both beam and aura.
const BEAM_HEIGHT_PX: float = 200.0
const BEAM_WIDTH_BASE_PX: float = 6.0
const AURA_BASE_RADIUS_PX: float = 26.0
const _RARITY_INTENSITY: Array[float] = [
	0.00,  # COMMON    — no beam, very faint aura
	0.35,  # MAGIC     — thin beam, small aura
	0.60,  # RARE      — medium beam + ring
	0.85,  # EPIC      — strong beam + bright aura
	1.15,  # LEGENDARY — tallest beam, fast pulse, expanding shockwave
]

const _FloatingTextScript := preload("res://vfx/FloatingText.gd")

# Rarity tint halos — drawn as an outer ring to hint at value without
# needing UI text.
const _RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.75),   # 0 COMMON   — grey
	Color(0.4, 0.7, 1.0),      # 1 MAGIC    — blue
	Color(1.0, 0.9, 0.3),      # 2 RARE     — yellow
	Color(0.8, 0.4, 1.0),      # 3 EPIC     — purple
	Color(1.0, 0.55, 0.1),     # 4 LEGENDARY— orange
]

var instance = null   # ItemInstance — set by LootDropper via setup() before add_child
var _age: float = 0.0
var _icon_color: Color = Color.WHITE
var _rarity_color: Color = Color.WHITE
var _icon_glyph: String = "generic"
var _rarity_idx: int = 0


func setup(inst) -> void:
	instance = inst


func _ready() -> void:
	# Resolve display colors once (ContentRegistry is populated by now).
	if instance != null:
		var base: Resource = ContentRegistry.find_item_base(instance.base_id)
		if base != null:
			_icon_color = base.icon_color
			_icon_glyph = base.icon_glyph
			_rarity_idx = clampi(int(base.rarity), 0, _RARITY_COLORS.size() - 1)
			_rarity_color = _RARITY_COLORS[_rarity_idx]
	# Register with central tap router (C3).
	ItemPickupManager.register(self)


func _exit_tree() -> void:
	# Safe to call even if _collect already ran — ItemPickupManager.unregister
	# is idempotent (erase is a no-op on missing element).
	ItemPickupManager.unregister(self)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME_S:
		_collect()
		return
	queue_redraw()


func _draw() -> void:
	var zs: float = _get_zoom_scale()
	var intensity: float = _RARITY_INTENSITY[_rarity_idx]
	# 1. Ground aura — pulsing rings under the item (drawn first so beam +
	# item paint over it). Always on, scales with rarity.
	_draw_ground_aura(intensity, zs)
	# 2. Vertical beam of light — column of rarity color rising from the
	# ground. Higher rarities get a wider, taller, brighter beam. Common
	# items skip the beam entirely so the world isn't littered with light.
	if intensity > 0.0:
		_draw_beam_of_light(intensity, zs)
	# 3. Item icon — bobs gently on top of the beam.
	var bob: float = sin(_age * TAU / BOB_PERIOD_S) * BOB_HEIGHT_PX * zs
	var center: Vector2 = Vector2(0, -20 + bob)
	var radius: float = ICON_RADIUS_PX * zs
	# Rarity halo — slightly larger than the icon.
	# Snap stroke width to integer px and disable AA so the halo reads as
	# a crisp ring at any camera zoom now that the in-world style is chunky.
	var halo_w: float = maxf(1.0, roundf(HALO_THICKNESS_PX * zs))
	draw_arc(center, radius + HALO_THICKNESS_PX * zs, 0.0, TAU, 24, _rarity_color, halo_w, false)
	# Dark backing disc so glyph is always readable over any map terrain.
	draw_circle(center, radius, Color(0.08, 0.08, 0.1, 0.85))
	# Procedural glyph + rarity pips (same helper as ItemIcon).
	ItemGlyph.draw(self, _icon_glyph, center, radius, _icon_color)
	ItemGlyph.draw_rarity_pips(self, _rarity_idx, center, radius)


# Pulsing ground aura — soft inner disc + mid ring + an expanding outer ring
# that ripples outward and resets, so even at rest the drop reads as alive.
func _draw_ground_aura(intensity: float, zs: float) -> void:
	# Common drops still get a faint baseline glow so they don't blend into
	# the terrain. Higher tiers stack brightness on top.
	var base_intensity: float = 0.25 + intensity * 0.85
	var pulse_speed: float = 2.0 + intensity * 1.5
	var pulse: float = 0.55 + sin(_age * pulse_speed) * 0.45  # 0.10 .. 1.0
	var base_r: float = AURA_BASE_RADIUS_PX * zs * (0.85 + intensity * 0.35)
	# Inner soft disc.
	var inner_alpha: float = 0.22 * pulse * base_intensity
	draw_circle(Vector2.ZERO, base_r, Color(_rarity_color.r, _rarity_color.g, _rarity_color.b, inner_alpha))
	# Mid ring — fixed radius, alpha pulses in sync with disc.
	var mid_alpha: float = 0.45 * pulse * base_intensity
	draw_arc(Vector2.ZERO, base_r * 1.30, 0.0, TAU, 32, Color(_rarity_color.r, _rarity_color.g, _rarity_color.b, mid_alpha), 2.5 * zs)
	# Outer shockwave — expands outward over ~1.5 s then resets, so the
	# drop continually emits a soft ripple. Fades as it grows.
	var ripple_period: float = maxf(0.6, 1.6 - intensity * 0.5)
	var ripple_t: float = fmod(_age, ripple_period) / ripple_period  # 0 → 1
	var ripple_r: float = base_r * (1.0 + ripple_t * 1.6)
	var ripple_alpha: float = (1.0 - ripple_t) * 0.40 * (0.4 + intensity)
	draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 32, Color(_rarity_color.r, _rarity_color.g, _rarity_color.b, ripple_alpha), 2.0 * zs)


# Vertical beam — drawn as two stacked tapered quads (outer wider/fainter,
# inner narrower/brighter). Per-vertex alpha gradient fades the top to 0
# so the beam dissolves into the sky instead of cutting off hard.
func _draw_beam_of_light(intensity: float, zs: float) -> void:
	var pulse: float = 0.85 + sin(_age * (2.5 + intensity * 1.5)) * 0.15
	var h: float = BEAM_HEIGHT_PX * zs * (0.7 + intensity * 0.5)
	# Outer wide layer (drawn first, behind inner).
	var outer_w: float = (BEAM_WIDTH_BASE_PX + intensity * 14.0) * zs
	_draw_beam_layer(outer_w, h, _rarity_color, 0.30 * intensity * pulse)
	# Inner brighter core.
	var inner_w: float = (BEAM_WIDTH_BASE_PX + intensity * 6.0) * zs
	_draw_beam_layer(inner_w, h, _rarity_color, 0.55 * intensity * pulse)
	# Bright base flare at the foot of the beam — small filled disc that
	# pulses in size; sells the "beam emerging from the ground" silhouette.
	var flare_r: float = (4.0 + intensity * 6.0) * zs * pulse
	draw_circle(Vector2.ZERO, flare_r, Color(_rarity_color.r, _rarity_color.g, _rarity_color.b, 0.55 * intensity))
	draw_circle(Vector2.ZERO, flare_r * 0.45, Color(1.0, 1.0, 1.0, 0.65 * intensity))


# One trapezoid layer of the beam — bottom = full alpha, top = 0 alpha.
# Slight inward taper at the top so the beam looks like a column of light.
func _draw_beam_layer(width: float, height: float, base_color: Color, alpha: float) -> void:
	var hw_bot: float = width * 0.5
	var hw_top: float = width * 0.30
	var bot: Color = Color(base_color.r, base_color.g, base_color.b, alpha)
	var top: Color = Color(base_color.r, base_color.g, base_color.b, 0.0)
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(-hw_bot, 0.0),
		Vector2(hw_bot, 0.0),
		Vector2(hw_top, -height),
		Vector2(-hw_top, -height),
	])
	var cols: PackedColorArray = PackedColorArray([bot, bot, top, top])
	draw_polygon(pts, cols)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x


# World-space tap radius (used by ItemPickupManager in C3 for spatial query)
func get_tap_radius() -> float:
	return TAP_RADIUS


# Collect path — called by timeout (C2) or by ItemPickupManager tap (C3).
# Safe to call more than once; _collected guard prevents double-add.
var _collected: bool = false
func _collect() -> void:
	if _collected:
		return
	_collected = true
	if instance != null:
		InventoryManager.add_to_round(instance)
		_spawn_pickup_feedback()
	queue_free()


# Phase C4: floating text + SFX on collect. SoundManager logs harmlessly
# if the sfx file is missing (same pattern as tower_build, enemy_die, etc).
func _spawn_pickup_feedback() -> void:
	var base: Resource = ContentRegistry.find_item_base(instance.base_id)
	var label: String = base.base_name if base != null else instance.base_id
	var host: Node = get_tree().current_scene
	if host != null:
		_FloatingTextScript.spawn_kind(host, _FloatingTextScript.Kind.PICKUP, global_position, 0.0, "+" + label, _rarity_color)
	SoundManager.play_sfx("item_pickup")
