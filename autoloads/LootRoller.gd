extends Node

# Phase 48 B2 — pure function layer that turns "an enemy died carrying
# some base" into "a specific ItemInstance with UID and rolled affixes".
# No game integration lives here; LootDropper (Phase C) will call this from
# the enemy_died signal handler.
#
# Design invariants:
# - Affixes are picked without replacement across all allowed pools, so an
#   instance never has two of the same affix_id.
# - Affix values are rolled uniformly in [value_min, value_max] per the
#   AffixData spec. Int affixes round to nearest integer.
# - UIDs come from SaveManager.issue_uid() — monotonic, collision-proof.
# - No seeded RNG. Loot is cosmetic-progression, not leaderboard-affecting
#   (see plan Design Principle 6).

const _ItemInstanceScript := preload("res://items/ItemInstance.gd")


# Produce a single rolled ItemInstance for the given base. Returns null only
# if the base is null or SaveManager isn't ready.
# wave: the wave number the drop happened on (stored on the instance for
# encyclopedia / lore display). Caller passes 0 for starter kit / test rolls.
func roll_item_instance(base, wave: int = 0) -> RefCounted:
	if base == null:
		push_warning("[LootRoller] roll_item_instance: null base")
		return null
	var inst = _ItemInstanceScript.new()
	inst.uid = SaveManager.issue_uid()
	inst.base_id = base.base_id
	inst.rolled_affixes = _roll_affixes_for(base)
	inst.found_at_wave = wave
	return inst


# Pool-resolution + weighted pick loop. Rolls base.affix_slots affixes
# without repeating an affix_id within this instance. Skips silently if a
# pool is missing or empty — fewer rolled affixes is preferable to crashing.
func _roll_affixes_for(base) -> Array:
	var out: Array = []
	if base.affix_slots <= 0 or base.allowed_affix_pools.is_empty():
		return out
	var used_ids: Dictionary = {}   # affix_id -> true (de-dup set)
	for _i in base.affix_slots:
		var picked = _pick_affix_across_pools(base.allowed_affix_pools, used_ids)
		if picked == null:
			break   # no more affixes available (all de-duped or pools empty)
		used_ids[picked.affix_id] = true
		var v: float = picked.roll_value()
		out.append({"affix_id": picked.affix_id, "value": v})
	return out


# Combine all pool affixes into one weighted list (excluding already-used
# ids), pick one by total-weight random draw. Returns null if no candidates.
func _pick_affix_across_pools(pool_ids: Array, used_ids: Dictionary):
	var candidates: Array = []
	var total_weight: float = 0.0
	for pool_id in pool_ids:
		var pool = ContentRegistry.find_affix_pool(pool_id)
		if pool == null:
			continue
		for a in pool.affixes:
			if a == null:
				continue
			if used_ids.has(a.affix_id):
				continue
			if a.weight <= 0.0:
				continue
			candidates.append(a)
			total_weight += a.weight
	if candidates.is_empty() or total_weight <= 0.0:
		return null
	var r: float = randf() * total_weight
	var acc: float = 0.0
	for a in candidates:
		acc += a.weight
		if r <= acc:
			return a
	return candidates[-1]


func _ready() -> void:
	print("[LootRoller] loaded")
	# Phase B3 smoketest — print one rolled example of each rollable base so
	# we can eyeball that the pipeline works end-to-end without waiting for
	# Phase C's LootDropper. Remove when drops arrive in gameplay. Deferred
	# one frame so all autoloads have finished _ready first.
	call_deferred("_debug_smoketest")


func _debug_smoketest() -> void:
	var sample_ids: Array = ["base_iron_sword", "base_chain_mail", "base_amulet_wisdom"]
	for id in sample_ids:
		var base = ContentRegistry.find_item_base(id)
		if base == null:
			continue
		var inst = roll_item_instance(base, 0)
		if inst == null:
			continue
		var affix_lines: PackedStringArray = []
		for roll in inst.rolled_affixes:
			var a = ContentRegistry.find_affix(String(roll.get("affix_id", "")))
			if a == null:
				affix_lines.append("?")
			else:
				affix_lines.append(a.format_display(float(roll.get("value", 0.0))))
		print("[LootRoller/DEBUG] %s uid=%s affixes=[%s]" % [id, inst.uid, ", ".join(affix_lines)])
