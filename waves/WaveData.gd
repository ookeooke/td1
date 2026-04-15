extends Resource
class_name WaveData

# One wave = any number of WaveSpawn emitters running in parallel.
# `countdown` is the grace period (SpawnMarker show time) before the wave fires.
# `bounty` is bonus gold awarded when the wave is cleared.

@export var spawns: Array[WaveSpawn] = []
@export var countdown: float = 3.0
@export var bounty: int = 0
