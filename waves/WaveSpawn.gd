extends Resource
class_name WaveSpawn

# One emitter within a wave: spawn N enemies on one path at a given interval.
# Edit these directly in the Inspector when you open a WaveData resource.

@export var path_id: String = "left"  # Must match a Path2D node name under Level.Paths.
@export var enemy_scene: PackedScene
@export var count: int = 1
@export var interval: float = 1.0       # Seconds between spawns within this emitter.
@export var start_delay: float = 0.0    # Delay after wave starts before this emitter begins.
