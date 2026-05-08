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
# Per-wave early-call window override. Caps `bonus = min(seconds_remaining, window)`.
# Sentinel -1 = inherit from LevelNodeData.early_call_window_sec (default 10).
# Use cases: shorter window on boss waves (less reward for skipping the
# breathing room), longer window on rest waves (encourage aggressive play).
# Authored per-wave; the BalanceSliders slider can also override at runtime.
@export var early_call_window_sec: float = -1.0
