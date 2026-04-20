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
	var bob: float = sin(_age * TAU / BOB_PERIOD_S) * BOB_HEIGHT_PX * zs
	var center: Vector2 = Vector2(0, -20 + bob)
	var radius: float = ICON_RADIUS_PX * zs
	# Rarity halo — slightly larger than the icon
	draw_arc(center, radius + HALO_THICKNESS_PX * zs, 0.0, TAU, 32, _rarity_color, HALO_THICKNESS_PX * zs, true)
	# Dark backing disc so glyph is always readable over any map terrain
	draw_circle(center, radius, Color(0.08, 0.08, 0.1, 0.85))
	# Procedural glyph + rarity pips (same helper as ItemIcon)
	ItemGlyph.draw(self, _icon_glyph, center, radius, _icon_color)
	ItemGlyph.draw_rarity_pips(self, _rarity_idx, center, radius)


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
		_FloatingTextScript.spawn(host, "+" + label, _rarity_color, global_position, 28)
	SoundManager.play_sfx("item_pickup")
