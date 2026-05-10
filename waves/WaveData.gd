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
# DEPRECATED. The countdown rest-beat between waves was removed in the
# overlap-only redesign — waves are now back-to-back and early-call works
# as a suffix of the previous wave's spawn (overlap, not gap-skip). The
# field is kept on WaveData so existing .tres files load without errors,
# but WaveManager ignores it. New authoring should leave it at the default.
@export var countdown: float = 0.0
@export var bounty: int = 0
# Per-wave early-call window override. The LAST N seconds of the PREVIOUS
# wave's spawn during which the Send Wave button is active for THIS wave.
# Pressing during the window → THIS wave starts immediately, parallel to
# the previous wave's still-running spawners. Bonus = (overlap_seconds) × gold_per_sec.
# Sentinel -1 = inherit from LevelNodeData.early_call_window_sec (default 10).
@export var early_call_window_sec: float = -1.0
# Gold per second of overlap when this wave is early-called. Default 1.0g/s
# (sentinel -1 = inherit from LevelNodeData.early_call_gold_per_sec).
@export var early_call_gold_per_sec: float = -1.0
