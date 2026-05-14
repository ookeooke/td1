extends Node2D

# Persistent passive aura for the Necromancer hero. Four small green-purple
# wisps orbit the origin at different angular speeds; alpha breathes on a
# sin wave so the aura looks alive even when the hero is idle. Permanent
# until the hero dies — VFXSpawner attaches this as a child of the hero
# on hero_spawned and frees it on hero_died (or the hero's queue_free
# cascades down naturally).

const ORBIT_R: float = 28.0
const WISP_COUNT: int = 4
# Per-wisp angular speeds (rad/sec) — chosen as small relatively-prime-ish
# values so the orbits never visually sync up. Can't be `const` because
# PackedFloat32Array literals aren't compile-time constant expressions.
static var _SPEEDS: PackedFloat32Array = PackedFloat32Array([0.55, -0.70, 0.85, -0.45])
static var _PHASE_OFFSETS: PackedFloat32Array = PackedFloat32Array([0.0, 1.57, 3.14, 4.71])
# Soft halo / bright core colors. Green-purple alternates wisp-by-wisp so
# the aura reads as both unholy and arcane.
const _HALO_GREEN: Color = Color(0.45, 0.95, 0.55, 0.35)
const _CORE_GREEN: Color = Color(0.70, 1.00, 0.75, 0.95)
const _HALO_PURPLE: Color = Color(0.55, 0.25, 0.85, 0.35)
const _CORE_PURPLE: Color = Color(0.85, 0.55, 1.00, 0.95)

var _t: float = 0.0


func _ready() -> void:
	z_index = 3
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for i in WISP_COUNT:
		var angle: float = _PHASE_OFFSETS[i] + _t * _SPEEDS[i]
		# Slight radial pulse so the orbit looks orbital, not metronomic.
		var r: float = ORBIT_R + sin(_t * 1.3 + _PHASE_OFFSETS[i]) * 3.0
		var pos: Vector2 = Vector2(cos(angle), sin(angle) * 0.55) * r
		# Vertical squash (* 0.55) sells perspective — the orbit reads as a
		# ring tilted toward camera instead of a flat circle around the body.
		var breath: float = 0.55 + 0.45 * sin(_t * 2.0 + _PHASE_OFFSETS[i])
		var is_green: bool = (i % 2) == 0
		var halo: Color = _HALO_GREEN if is_green else _HALO_PURPLE
		var core: Color = _CORE_GREEN if is_green else _CORE_PURPLE
		halo.a *= breath
		core.a *= breath
		draw_circle(pos, 5.5, halo)
		draw_circle(pos, 2.4, core)
