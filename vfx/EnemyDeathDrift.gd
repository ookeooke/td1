class_name EnemyDeathDrift
extends Node2D

# Snapshot of a dying enemy that stays at the death point and squishes flat
# while fading. Player feedback: a kill produces a clear "drop and fade"
# silhouette instead of an instant despawn. No drift, no rotation — the body
# stays exactly where it died (kills shouldn't look like the enemy is still
# moving along the path).

const _UnitVisualDrawer := preload("res://systems/UnitVisualDrawer.gd")

const LIFETIME: float = 0.35

var _visual: Resource = null  # UnitVisualData
var _t: float = LIFETIME


# Signature kept compatible with the previous drift-based version so
# VFXSpawner doesn't need a matching change. hit_dir is ignored — kills no
# longer push the body along the hit direction.
static func spawn(parent: Node, visual: Resource, pos: Vector2, _hit_dir: Vector2) -> void:
	if parent == null or visual == null:
		return
	var inst := EnemyDeathDrift.new()
	inst.global_position = pos
	inst._visual = visual
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
	# Squish in-place. Body flattens (Y → 0.3) and widens slightly (X → 1.25)
	# so the silhouette reads as "collapsed on the ground". Pivot at the feet
	# so the bottom edge stays anchored at the spawn point — the body sinks
	# down rather than shrinking around its center.
	var progress: float = clampf(1.0 - _t / LIFETIME, 0.0, 1.0)
	var sx: float = 1.0 + progress * 0.25
	var sy: float = 1.0 - progress * 0.7
	var torso_r: float = _visual.radius if "radius" in _visual else 32.0
	var feet_y: float = torso_r * 0.85
	# Offset compensation: with scale sy applied to local Y, a point at
	# local (0, feet_y) ends up at offset.y + feet_y * sy. Setting
	# offset.y = feet_y * (1 - sy) keeps the feet pinned at the original
	# world Y regardless of squish.
	var off_y: float = feet_y * (1.0 - sy)
	_UnitVisualDrawer.draw_unit(self, _visual, Vector2(0.0, off_y), Vector2(sx, sy))