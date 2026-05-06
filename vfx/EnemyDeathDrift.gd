class_name EnemyDeathDrift
extends Node2D

# Snapshot of a dying enemy that stays near the death point, tips over, squishes
# flat, and fades. Kill feedback should read as a collapsed body, not an instant
# despawn or a still-moving enemy.

const _UnitVisualDrawer := preload("res://systems/UnitVisualDrawer.gd")

const LIFETIME: float = 0.50

var _visual: Resource = null  # UnitVisualData
var _t: float = LIFETIME
var _fall_dir: float = 1.0


# Signature kept compatible with the previous drift-based version. hit_dir now
# chooses which side the body tips toward, but the corpse stays anchored at the
# kill point.
static func spawn(parent: Node, visual: Resource, pos: Vector2, hit_dir: Vector2) -> void:
	if parent == null or visual == null:
		return
	var inst := EnemyDeathDrift.new()
	inst.global_position = pos
	inst._visual = visual
	inst._fall_dir = -1.0 if hit_dir.x < 0.0 else 1.0
	parent.add_child(inst)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	modulate.a = clampf(_t / LIFETIME, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _visual == null:
		return
	var progress: float = clampf(1.0 - _t / LIFETIME, 0.0, 1.0)

	# Branch: textured enemies (single image) tip-over without Y-squish. The
	# procedural path's 78% Y-squash collapses a multi-part body believably
	# (head/legs/arms flatten into a heap) but on a single texture it just
	# smears the whole sprite. Tip-over reads as "fell over dead" instead.
	var has_texture: bool = "texture" in _visual and _visual.texture != null
	if has_texture:
		var ts: Vector2 = _visual.texture_size if "texture_size" in _visual else Vector2(64.0, 64.0)
		# Smooth ease-out for the rotation so it slows as it lands.
		var rot_eased: float = 1.0 - pow(1.0 - progress, 3.0)
		# Brief impact pop (sin curve: 0 → 1 → 0) makes the kill snap.
		var pop_t: float = sin(progress * PI) * 0.12
		var s_tex: float = 1.0 + pop_t
		var rot_tex: float = _fall_dir * deg_to_rad(85.0) * rot_eased
		var drift_x: float = _fall_dir * progress * ts.x * 0.20
		var drift_y: float = progress * ts.y * 0.10
		draw_set_transform(Vector2(drift_x, drift_y), rot_tex, Vector2(s_tex, s_tex))
		_UnitVisualDrawer.draw_unit(self, _visual)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# Procedural — tip + squish + flatten + dust (original behavior).
	# Body falls toward the killing blow direction, then flattens
	# (Y → 0.22) and widens slightly (X → 1.35). Pivot compensation
	# keeps feet near the original kill point.
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)
	var sx: float = 1.0 + eased * 0.35
	var sy: float = 1.0 - eased * 0.78
	var torso_r: float = _visual.radius if "radius" in _visual else 32.0
	var feet_y: float = torso_r * 0.85
	# Offset compensation: with scale sy applied to local Y, a point at
	# local (0, feet_y) ends up at offset.y + feet_y * sy. Setting
	# offset.y = feet_y * (1 - sy) keeps the feet pinned at the original
	# world Y regardless of squish.
	var off_y: float = feet_y * (1.0 - sy) + eased * torso_r * 0.18
	var off_x: float = _fall_dir * eased * torso_r * 0.18
	var rot: float = _fall_dir * deg_to_rad(38.0) * minf(1.0, progress * 1.8)
	draw_set_transform(Vector2(off_x, off_y), rot, Vector2(sx, sy))
	_UnitVisualDrawer.draw_unit(self, _visual)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var dust_alpha: float = clampf((1.0 - progress) * 0.28, 0.0, 0.28)
	if dust_alpha > 0.0:
		draw_circle(Vector2(0.0, feet_y * 0.85), torso_r * (0.35 + progress * 0.75), Color(0.35, 0.27, 0.18, dust_alpha))