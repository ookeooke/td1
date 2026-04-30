extends RefCounted
class_name ItemInstance

# Runtime object representing one specific dropped/owned item. Unlike
# ItemBase (shared authored template), each ItemInstance has a stable UID
# and its own rolled affix values. Not a Resource — persisted as plain
# Dictionary in the save file, see to_dict/from_dict.
#
# UIDs come from SaveManager.issue_uid() (monotonic counter). Never generate
# UIDs inline — the counter lives in the save and must survive restarts so
# equipment-slot references (hero_equipment keys) stay valid.

var uid: String = ""
var base_id: String = ""
var rolled_affixes: Array = []   # Array of { "affix_id": String, "value": float }
var found_at_wave: int = 0
# IP-3 — player-set "do not sell" pin. Sell endpoint refuses locked items.
# Defaults to false; round-trips through to_dict/from_dict; older saves
# missing the field default to false (additive — no migration needed).
var locked: bool = false
# Phase 49 — grid placement on the shared inventory grid. -1/-1 means
# unplaced; InventoryManager._reflow_unplaced() assigns coordinates on the
# next opportunity (load, equip-back, manual reflow). Equipped items also
# carry -1/-1 since they don't occupy any grid cell while equipped.
var grid_row: int = -1
var grid_col: int = -1


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"base_id": base_id,
		"affixes": rolled_affixes.duplicate(true),
		"found_at_wave": found_at_wave,
		"locked": locked,
		"grid_row": grid_row,
		"grid_col": grid_col,
	}


static func from_dict(d: Dictionary) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.uid = String(d.get("uid", ""))
	inst.base_id = String(d.get("base_id", ""))
	inst.rolled_affixes = (d.get("affixes", []) as Array).duplicate(true)
	inst.found_at_wave = int(d.get("found_at_wave", 0))
	inst.locked = bool(d.get("locked", false))
	inst.grid_row = int(d.get("grid_row", -1))
	inst.grid_col = int(d.get("grid_col", -1))
	return inst


# Resolve this instance into the live AbilityData list that should be
# attached to the wearer. Combines the base's implicit abilities (shared
# across all instances of this base, so duplicate them so per-hero state
# doesn't leak) with each rolled affix's injected ability.
# `registry` is ContentRegistry (passed in to avoid a hard global dep).
func build_runtime_abilities(registry) -> Array:
	var out: Array = []
	if registry == null:
		push_warning("[ItemInstance] build_runtime_abilities: no registry")
		return out
	var base: Resource = registry.find_item_base(base_id)
	if base == null:
		push_warning("[ItemInstance] unknown base_id: %s" % base_id)
		return out
	# Implicits — always-on, duplicate so the shared template is never mutated.
	for impl in base.implicit_abilities:
		if impl != null:
			out.append(impl.duplicate(true))
	# Rolled affixes — resolve affix, inject value, append.
	for roll in rolled_affixes:
		var affix_id: String = String(roll.get("affix_id", ""))
		var value: float = float(roll.get("value", 0.0))
		var affix: Resource = registry.find_affix(affix_id)
		if affix == null:
			push_warning("[ItemInstance] unknown affix_id: %s" % affix_id)
			continue
		var built: Resource = affix.make_rolled_ability(value)
		if built != null:
			out.append(built)
	return out


# Display helper — "Iron Sword" + each rolled affix line. Used by UI tiles.
func format_full_description(registry) -> String:
	if registry == null:
		return "(no registry)"
	var base: Resource = registry.find_item_base(base_id)
	var lines: PackedStringArray = []
	if base != null:
		lines.append(base.base_name)
	for roll in rolled_affixes:
		var affix_id: String = String(roll.get("affix_id", ""))
		var value: float = float(roll.get("value", 0.0))
		var affix: Resource = registry.find_affix(affix_id)
		if affix != null:
			lines.append(affix.format_display(value))
	return "\n".join(lines)
