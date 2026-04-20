extends Resource
class_name UnitVisualData

# Data resource describing how a unit is drawn. Replaces hardcoded colors
# and shapes in _draw() methods. Towers already have body_color on TowerData;
# this covers enemies, heroes, and soldiers.

enum Shape { CIRCLE, SQUARE }
enum Accent { NONE, WEAPON_LINE, CROSSHAIR, WINGS, CROWN }
# Drives draw_swing_arc_trail's silhouette. Default SWORD keeps the existing
# 60° arc, so every existing .tres renders unchanged until explicitly updated.
enum WeaponType { SWORD, SPEAR, STAFF, CLAWS }

@export var shape: Shape = Shape.CIRCLE
@export var body_color: Color = Color(0.75, 0.2, 0.2)
@export var outline_color: Color = Color(0.15, 0.05, 0.05)
@export var accent_color: Color = Color.WHITE
@export var accent_type: Accent = Accent.NONE
@export var radius: float = 35.0
@export var body_size: Vector2 = Vector2(50, 50)
@export var outline_width: float = 5.0
@export var weapon_type: WeaponType = WeaponType.SWORD
# Per-squad or per-faction accent ring drawn just inside the body outline.
# Zero alpha = disabled (default) so existing visuals are untouched. Used by
# TowerBarracks to tint each squad's soldiers by barracks spot_id.
@export var accent_band_color: Color = Color(0, 0, 0, 0)

# Procedural walk animation — applied by base_enemy in _draw() while WALKING.
# Amplitude 0 disables bob; squash 0 disables squash/stretch. Defaults are
# subtle so every existing enemy reads as "alive" without per-tres editing.
@export_group("Walk Animation")
# Vertical lift at peak, in pixels. Body hops by |sin| — two plants per cycle.
@export_range(0.0, 12.0, 0.1) var walk_bob_amplitude: float = 2.5
# Cycle rate in radians/sec. ~7.0 ≈ ~2.2 plants/sec (one plant per half cycle).
@export_range(0.0, 20.0, 0.1) var walk_bob_speed: float = 7.0
# Squash magnitude at each foot-plant (body scales X+ Y-). 0 = off.
@export_range(0.0, 0.25, 0.01) var walk_squash: float = 0.04
