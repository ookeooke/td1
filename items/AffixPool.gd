extends Resource
class_name AffixPool

# Named bucket of AffixData. ItemBase.allowed_affix_pools references pools by
# pool_id; LootRoller resolves the list via ContentRegistry.find_affix_pool.
# Weights come from the contained AffixData.weight.

@export var pool_id: String = ""                     # stable; matches filename
@export var affixes: Array[Resource] = []            # Array of AffixData


# Weighted pick. Optionally pass a RandomNumberGenerator for determinism.
# slot_filter: if >= 0, skip affixes whose allowed_slots is non-empty and
# does not contain slot_filter.
func pick_weighted(rng: RandomNumberGenerator = null, slot_filter: int = -1) -> Resource:
	var eligible: Array[Resource] = []
	var total: float = 0.0
	for a in affixes:
		if a == null:
			continue
		if slot_filter >= 0 and not a.allowed_slots.is_empty() and not a.allowed_slots.has(slot_filter):
			continue
		if a.weight <= 0.0:
			continue
		eligible.append(a)
		total += a.weight
	if eligible.is_empty() or total <= 0.0:
		return null
	var r: float = rng.randf() * total if rng != null else randf() * total
	var acc: float = 0.0
	for a in eligible:
		acc += a.weight
		if r <= acc:
			return a
	return eligible[-1]
