extends Resource
class_name AbilityData

# Base class for all composable abilities — enemy traits, hero passives,
# tower on-hit effects, item-granted effects, talent-tree nodes. One
# unifying primitive so the same machinery handles every "mechanic on top
# of base stats". Subclasses override `apply(owner, ctx)` with the actual
# effect; the `trigger` field tells AbilityHost *when* to call it.
#
# Keep AbilityData deliberately flat and well-named — Godot's Inspector
# only handles Array[Resource] nicely when the resource types are easy
# to scan.

enum Trigger {
	ON_SPAWN,      # Fired once when the ability is first attached.
	ON_INTERVAL,   # Fired every `interval` seconds by AbilityHost.tick().
	ON_HIT_DEALT,  # Fired when owner damages another unit. ctx has {target, amount}.
	ON_HIT_TAKEN,  # Fired when owner takes damage. ctx has {source, amount}.
	ON_KILL,       # Fired when owner kills another unit. ctx has {victim}.
	ON_DEATH,      # Fired when owner dies.
	WHILE_ALIVE,   # Passive — not dispatched per-event. Reserved for stat-stack use later.
	ON_EQUIP,      # Reserved for items (future).
	ON_UNEQUIP,    # Reserved for items (future).
}

@export var ability_id: String = ""
@export var trigger: int = Trigger.ON_SPAWN
# Only meaningful for ON_INTERVAL.
@export var interval: float = 1.0
# 0.0 = permanent (default). If > 0.0, AbilityHost auto-removes the ability
# that many seconds after it was added. Used for temporary buffs pushed by
# skills ("Rally: +X damage for 10 s") so the skill doesn't need its own
# bookkeeping to undo itself.
@export var duration: float = 0.0


# Subclasses override. `owner` is the unit (BaseEnemy, BaseHero, etc.).
# `ctx` is a Dictionary carrying event-specific payload. Keep implementations
# owner-agnostic — if you need `if owner is BaseHero`, the abstraction is
# wrong and you should split the ability.
func apply(_owner: Node, _ctx: Dictionary) -> void:
	pass
