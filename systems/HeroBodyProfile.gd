extends Resource
class_name HeroBodyProfile

# Hero-platform body/movement layer (Pure-B architecture, layer 4).
# Authored on HeroData.body_profile. Null ⇒ DEFAULT_HUMANOID (ground,
# blocks, NEAREST targeting) — byte-identical to pre-Phase-4 behavior.
#
# IMPORTANT: this resource is mostly DECLARATIVE. A flying hero that never
# blocks ground is achieved by the EXISTING mechanism — authoring
# HeroData.max_block_targets = 0 (and detection_radius_px = 0) plus
# UnitVisualData.flight_height_px > 0 for the float+shadow. No new branch is
# added to the load-bearing blocker state machine (COMBAT_BLOCKING_DOCTRINE
# 6 invariants stay untouched). ContentRegistry._assert_body_profiles()
# asserts the declarative flags here AGREE with that authored mechanism, so
# is_flying / blocks_ground can never silently drift from reality
# (Preventive Bug Rule 4 — executable, not a comment).
#
# The ONLY behavioral hook is targeting_priority: a pure comparator bias in
# the existing target pickers. NEAREST (default) reproduces today's
# fewest-blockers → progress → distance order exactly.

enum TargetingPriority {
	NEAREST,      # default — today's order, no bias (byte-identical)
	GROUND_FIRST, # de-prioritize flyers among otherwise-equal candidates
	AIR_FIRST,    # de-prioritize ground among otherwise-equal candidates
}

@export var is_flying: bool = false
@export var blocks_ground: bool = true
@export var targeting_priority: int = TargetingPriority.NEAREST
# Cosmetic float height for a flying body. Mirrors UnitVisualData.flight_
# height_px; kept here only for the consistency boot-check (the actual
# render reads UnitVisualData). 0 = grounded.
@export var flight_height_px: float = 0.0
