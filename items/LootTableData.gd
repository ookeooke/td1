extends Resource
class_name LootTableData

# Authored .tres — drop probability + weighted list of base_ids. Attached
# to EnemyData as an optional field; falls back to a default table held by
# LootDropper if absent. LootDropper rolls drop_chance once per kill, then
# picks a base by weight and hands to LootRoller.
#
# Two authoring modes:
#   1. Explicit (default) — `entries` Dict maps base_id -> weight. Use for
#      curated tables (boss tables, event drops). Adding a new base requires
#      a manual entry.
#   2. Derived (Phase 49) — set `derive_from_bases = true`. The table pulls
#      every authored base from ContentRegistry and weights it by
#      `base.drop_weight × rarity_weights[base.rarity]`. Adding a new .tres
#      to items/bases/ shows up in the loot pool with zero edits. `entries`
#      may still be set as a per-base override (e.g. exclude an item by
#      mapping its base_id to 0.0).

@export_range(0.0, 1.0) var drop_chance: float = 0.2
@export var entries: Dictionary = {}    # base_id -> weight (float)
# Phase 49 — when true, ignore `entries` as the source list and instead
# enumerate ContentRegistry.item_bases. `entries` is consulted as an
# override map: any base_id present overrides its derived weight (use 0.0
# to exclude). Default table flips this on; per-boss/per-event tables
# leave it false to stay curated.
@export var derive_from_bases: bool = false
# Per-rarity multipliers (COMMON, MAGIC, RARE, EPIC, LEGENDARY). Final
# weight = base.drop_weight × rarity_weights[base.rarity]. Tunable per
# table — a "Magic Find" event table could double the high-tier values.
@export var rarity_weights: Array[float] = [1.0, 0.8, 0.5, 0.2, 0.08]


func pick_base_id(wave: int = 999) -> String:
	if derive_from_bases:
		return _pick_derived(wave)
	return _pick_explicit(wave)


# Honors each base's min_wave gate (Phase E2): entries whose referenced
# base requires a later wave are excluded from the pick. Prevents early
# waves from dropping Legendaries.
func _pick_explicit(wave: int) -> String:
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
	return _pick_weighted(eligible_ids, eligible_weights, total)


# Phase 49 — enumerate every authored base and weight by drop_weight ×
# rarity multiplier. `entries` overrides individual bases (set to 0.0 to
# exclude). Same min_wave gating as _pick_explicit.
func _pick_derived(wave: int) -> String:
	var ids: Array[String] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for base in ContentRegistry.item_bases:
		if base == null or not ("base_id" in base):
			continue
		var bid: String = base.base_id
		if "min_wave" in base and int(base.min_wave) > wave:
			continue
		var w: float
		if entries.has(bid):
			w = float(entries[bid])
		else:
			var dw: float = float(base.drop_weight) if "drop_weight" in base else 1.0
			var rarity_idx: int = int(base.rarity) if "rarity" in base else 0
			rarity_idx = clampi(rarity_idx, 0, rarity_weights.size() - 1)
			var rmul: float = rarity_weights[rarity_idx] if rarity_idx >= 0 and rarity_idx < rarity_weights.size() else 1.0
			w = dw * rmul
		if w <= 0.0:
			continue
		ids.append(bid)
		weights.append(w)
		total += w
	return _pick_weighted(ids, weights, total)


func _pick_weighted(ids: Array[String], weights: Array[float], total: float) -> String:
	if ids.is_empty() or total <= 0.0:
		return ""
	var r: float = randf() * total
	var acc: float = 0.0
	for i in ids.size():
		acc += weights[i]
		if r <= acc:
			return ids[i]
	return ids[-1]
