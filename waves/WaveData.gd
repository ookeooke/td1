extends Resource
class_name WaveData

# One wave = any number of WaveSpawn emitters running in parallel.
# `countdown` is the grace period (SpawnMarker show time) before the wave fires.
# `bounty` is bonus gold awarded when the wave is cleared.
#
# 2026-04-29 — Default bumped 3.0 → 20.0s. Player should have time to plan
# tower placement between waves; KR-style "Send Wave" button can skip the
# wait for a gold bonus. WaveManager additionally overrides the FIRST wave
# to a longer grace (FIRST_WAVE_COUNTDOWN) so opening setup feels generous.

@export var spawns: Array[WaveSpawn] = []
@export var countdown: float = 20.0
@export var bounty: int = 0
