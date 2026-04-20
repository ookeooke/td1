extends Resource
class_name LootTableData

# Authored .tres — drop probability + weighted list of base_ids. Attached
# to EnemyData as an optional field; falls back to a default table held by
# LootDropper if absent. LootDropper rolls drop_chance once per kill, then
# picks a base by weight and hands to LootRoller.
#
# `entries` is a Dictionary keyed by base_id so authoring in .tres text is
# trivial: `entries = { "base_iron_sword": 1.0, "base_chain_mail": 1.0 }`.

@export_range(0.0, 1.0) var drop_chance: float = 0.2
@export var entries: Dictionary = {}    # base_id -> weight (float)


func pick_base_id(wave: int = 999) -> String:
	# Honors each base's min_wave gate (Phase E2): entries whose referenced
	# base requires a later wave are excluded from the pick. Prevents early
	# waves from dropping Legendaries.
	if entries.is_empty():
		return ""
	var eligible_ids: Array[String] = []
	var eligible_weights: Array[float] = []
	var total: float = 0.0
	for base_id in entries.keys():
		var w: float = float(entries[base_id])
		if w <= 0.0:
			continue
		var base: Resource = ContentRegistry.find_item_base(String(base_id))
		if base != null and "min_wave" in base and base.min_wave > wave:
			continue
		eligible_ids.append(String(base_id))
		eligible_weights.append(w)
		total += w
	if eligible_ids.is_empty() or total <= 0.0:
		return ""
	var r: float = randf() * total
	var acc: float = 0.0
	for i in eligible_ids.size():
		acc += eligible_weights[i]
		if r <= acc:
			return eligible_ids[i]
	return eligible_ids[-1]
