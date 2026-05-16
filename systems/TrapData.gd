extends Resource
class_name TrapData

# Phase 5 — authored stats for a placed trap/mine/totem. Referenced by
# PlaceTrapSkillData (content, deferred to sign-off). One TrapData backs
# many placed Trap instances.

enum TriggerKind { PROXIMITY, TIMED }  # PROXIMITY: detonates on enemy in radius

@export var trap_id: String = ""
@export var damage: float = 20.0
@export var damage_type: int = 0          # DamageCalculator.DamageType (PHYSICAL)
@export var radius: float = 80.0          # detonation / detection radius (px)
@export var arm_time: float = 0.6         # seconds before it can trigger
@export var lifetime: float = 12.0        # auto-despawn after N seconds
@export var trigger_kind: int = TriggerKind.PROXIMITY
@export var max_active: int = 3           # concurrent traps for one hero
