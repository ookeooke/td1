extends Resource
class_name UnitVisualData

# Data resource describing how a unit is drawn. Replaces hardcoded colors
# and shapes in _draw() methods. Towers already have body_color on TowerData;
# this covers enemies, heroes, and soldiers.

enum Shape { CIRCLE, SQUARE }
enum Accent { NONE, WEAPON_LINE, CROSSHAIR, WINGS, CROWN, SKULL_CHEST, RIBCAGE }
# Drives draw_swing_arc_trail's silhouette. Default SWORD keeps the existing
# 60° arc, so every existing .tres renders unchanged until explicitly updated.
enum WeaponType { SWORD, SPEAR, STAFF, CLAWS, BOW }
# Race tag selects the multi-part body silhouette (head, legs, optional tusks).
# NONE = legacy single-shape draw, kept as fallback for any visual not migrated.
enum Race { NONE, HUMAN, ORC, GOBLIN, TROLL, UNDEAD }
# Headgear drawn over the head when race != NONE. CROWN_BIG reproduces the old
# Accent.CROWN silhouette as a hat so bosses keep their crown after migration.
enum Hat { NONE, HORNS, HELMET, HOOD, BANDANA, CROWN_BIG }
# Optional authored procedural profiles. DEFAULT preserves the shared unit
# renderer; hero-specific values let one unit opt into a richer silhouette
# without forcing the generic enemy/soldier drawer to absorb special cases.
enum RenderProfile { DEFAULT, NECROMANCER_PREMIUM, MAGE_PREMIUM, DRAGON_PREMIUM }

@export var shape: Shape = Shape.CIRCLE
@export var body_color: Color = Color(0.75, 0.2, 0.2)
@export var outline_color: Color = Color(0.15, 0.05, 0.05)
@export var accent_color: Color = Color.WHITE
@export var accent_type: Accent = Accent.NONE
@export var radius: float = 35.0
@export var body_size: Vector2 = Vector2(50, 50)
@export var outline_width: float = 5.0
@export var weapon_type: WeaponType = WeaponType.SWORD
@export var render_profile: RenderProfile = RenderProfile.DEFAULT
# Per-squad or per-faction accent ring drawn just inside the body outline.
# Zero alpha = disabled (default) so existing visuals are untouched. Used by
# TowerBarracks to tint each squad's soldiers by barracks spot_id.
@export var accent_band_color: Color = Color(0, 0, 0, 0)

# Flight lift — body sprite draws offset upward by this many pixels; the
# ground shadow stays glued to the unit's true ground position so size +
# placement read at a glance. Universal AAA convention (KR / Bloons / PvZ /
# Brawl Stars). Shadow auto-shrinks and dims with height in
# UnitVisualDrawer.draw_ground_shadow. 0 = ground unit. Author 35-50 for
# harpies / bats; 50-70 for big dragon bosses. Same field applies to future
# flying heroes — engagement gating (max_block_targets, guard zone,
# is_flying filters) is data-authored separately.
@export_group("Flight")
@export_range(0.0, 80.0, 1.0) var flight_height_px: float = 0.0

# Procedural walk animation — applied by base_enemy in _draw() while WALKING.
# Amplitude 0 disables bob; squash 0 disables squash/stretch. Defaults are
# subtle so every existing enemy reads as "alive" without per-tres editing.
@export_group("Walk Animation")
# Vertical lift at peak, in pixels. Body hops by |sin| — two plants per cycle.
@export_range(0.0, 12.0, 0.1) var walk_bob_amplitude: float = 4.0
# Cycle rate in radians/sec. ~7.0 ≈ ~2.2 plants/sec (one plant per half cycle).
@export_range(0.0, 20.0, 0.1) var walk_bob_speed: float = 7.0
# Squash magnitude at each foot-plant (body scales X+ Y-). 0 = off.
@export_range(0.0, 0.25, 0.01) var walk_squash: float = 0.06
# Body tilt amplitude in radians. Body rocks ±this much per cycle, peaking
# mid-step (between plants), zero at plant. Sells weight-shift on a single
# image. ~0.035 rad ≈ 2°. 0 = off.
@export_range(0.0, 0.10, 0.005) var walk_tilt_amplitude: float = 0.035

# Multi-part body composition (head + legs + optional tusks + hat). When
# race == NONE the drawer skips these and draws the legacy single shape, so
# every pre-existing .tres renders unchanged until it opts in.
@export_group("Body Parts")
@export var race: Race = Race.NONE
@export var head_color: Color = Color(0.42, 0.55, 0.25)
# Head radius as a fraction of torso radius. ~0.55 keeps the head visibly
# smaller than the torso while staying readable at low zoom.
@export_range(0.2, 1.2, 0.05) var head_radius_ratio: float = 0.55
# Vertical placement of head center, in units of torso radius (negative = up).
@export_range(-2.0, 0.0, 0.05) var head_y_offset: float = -0.95
@export var has_tusks: bool = false
@export var hat: Hat = Hat.NONE
# Optional second hat layered on the first — used by the boss to combine
# CROWN_BIG (top) with HORNS (head). Hat.NONE = single-hat behavior.
@export var hat_secondary: Hat = Hat.NONE
@export var hat_color: Color = Color(0.3, 0.3, 0.3)
@export var leg_color: Color = Color(0.25, 0.18, 0.12)
@export var arm_color: Color = Color(0.42, 0.55, 0.25)

# Optional procedural polish layers. Defaults are disabled so existing visual
# resources render exactly as before until a .tres opts in. These are cosmetic
# only: no gameplay stats, no collision changes, and no extra nodes.
@export_group("Polish")
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export_range(0.0, 1.0, 0.01) var highlight_strength: float = 0.0
@export var armor_plate_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var shoulder_pad_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var cape_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export_range(0.5, 2.0, 0.05) var weapon_trail_strength: float = 1.0
@export var weapon_glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.01) var weapon_glow_strength: float = 0.0
# When alpha > 0, overrides the default dark eye dots with glowing eyes of
# this color (plus a soft outer halo). Used by undead/demonic units so the
# silhouette reads as "not alive" at a glance. Default alpha 0 = legacy
# dark dots, so every existing visual renders unchanged.
@export var eye_glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)
# Optional orb / finial drawn at the staff tip when weapon_type == STAFF.
# Alpha 0 (default) → use the legacy hardcoded blue knob. When set, the
# finial replaces the default knob with a colored core + soft halo.
@export var staff_finial_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export_range(0.0, 14.0, 0.5) var staff_finial_size: float = 0.0

# When set, replaces the procedural torso/head/legs/arms/hat with this image.
# Shadow, hit-flash, status rings, HP bar, swing-arc trail still wrap the
# texture (they're drawn outside draw_unit()). Walk-bob and squash inherit
# automatically via the body transform. Leave null to keep the procedural
# silhouette.
@export_group("Texture Override")
@export var texture: Texture2D = null
# Render size in pixels — centered on the unit origin. If either component
# is 0, falls back to (radius * 2, radius * 2) so the texture matches the
# procedural body's footprint.
@export var texture_size: Vector2 = Vector2(80, 80)
