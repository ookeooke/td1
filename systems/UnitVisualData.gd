extends Resource
class_name UnitVisualData

# Data resource describing how a unit is drawn. Replaces hardcoded colors
# and shapes in _draw() methods. Towers already have body_color on TowerData;
# this covers enemies, heroes, and soldiers.

enum Shape { CIRCLE, SQUARE }
enum Accent { NONE, WEAPON_LINE, CROSSHAIR, WINGS, CROWN }

@export var shape: Shape = Shape.CIRCLE
@export var body_color: Color = Color(0.75, 0.2, 0.2)
@export var outline_color: Color = Color(0.15, 0.05, 0.05)
@export var accent_color: Color = Color.WHITE
@export var accent_type: Accent = Accent.NONE
@export var radius: float = 14.0
@export var body_size: Vector2 = Vector2(20, 20)
@export var outline_width: float = 2.0
