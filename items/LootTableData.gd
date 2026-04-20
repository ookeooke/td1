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


func pick_base_id() -> String:
	if entries.is_empty():
		return ""
	var total: float = 0.0
	for w in entries.values():
		total += float(w)
	if total <= 0.0:
		return ""
	var r: float = randf() * total
	var acc: float = 0.0
	for base_id in entries.keys():
		acc += float(entries[base_id])
		if r <= acc:
			return String(base_id)
	return String(entries.keys()[-1])
