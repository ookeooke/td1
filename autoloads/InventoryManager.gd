extends Node

# Phase 48 — Persistent loot ledger. Pure bookkeeping; stats flow through the
# hero's modifier stack via AbilityHost.equip_ability (see BaseHero._ready
# item-pass in A12). No stat mutation lives here.
#
# Data model:
#   hero_inventories[hero_id] -> Array[ItemInstance]   (owned, unequipped too)
#   hero_equipment[hero_id]   -> Dict[slot_str -> uid]  ("0".."5" keys; 6 slots)
#   round_pickups             -> Array[ItemInstance]    (this-run-only; merged
#                                 into selected hero's inventory on
#                                 level_completed)
#   starter_gear_granted      -> Array[String]          (hero_ids that already
#                                 received their starter pack — never re-grant)
#
# UIDs come from SaveManager.issue_uid(). Six slots per hero always present
# (3 active, 3 reserved) so future Phase F activation needs no migration.

const _ItemInstanceScript := preload("res://items/ItemInstance.gd")
const SLOT_COUNT: int = 6

var hero_inventories: Dictionary = {}      # hero_id -> Array[ItemInstance]
var hero_equipment: Dictionary = {}        # hero_id -> Dict[slot_str -> uid]
var round_pickups: Array = []              # Array[ItemInstance]
var starter_gear_granted: Array = []       # Array[String]


func _ready() -> void:
	# InventoryManager loads BEFORE SaveManager (SaveManager.load_game calls
	# into us during its _ready, so we must exist). ContentRegistry loads
	# AFTER us in the autoload list — we only call into it lazily from
	# ensure_starter_gear / runtime methods, never during _ready, so order
	# is safe despite the late dependency.
	EventBus.level_completed.connect(_on_level_completed)
	print("[InventoryManager] loaded")


# -- Persistence round-trip (called by SaveManager) -------------------------

func to_save_dict() -> Dictionary:
	var inv_out: Dictionary = {}
	for hero_id in hero_inventories.keys():
		var arr: Array = []
		for inst in hero_inventories[hero_id]:
			if inst != null:
				arr.append(inst.to_dict())
		inv_out[hero_id] = arr
	return {
		"hero_inventories": inv_out,
		"hero_equipment": hero_equipment.duplicate(true),
		"starter_gear_granted": starter_gear_granted.duplicate(),
	}


func from_save_dict(d: Dictionary) -> void:
	hero_inventories.clear()
	var inv_in: Dictionary = d.get("hero_inventories", {})
	for hero_id in inv_in.keys():
		var list: Array = []
		for entry in inv_in[hero_id]:
			if entry is Dictionary:
				list.append(_ItemInstanceScript.from_dict(entry))
		hero_inventories[hero_id] = list
	hero_equipment = (d.get("hero_equipment", {}) as Dictionary).duplicate(true)
	starter_gear_granted = (d.get("starter_gear_granted", []) as Array).duplicate()


# -- Round lifecycle --------------------------------------------------------

func add_to_round(instance) -> void:
	if instance == null:
		return
	round_pickups.append(instance)
	# Phase E4 — first-time encounter unlocks the encyclopedia entry.
	# GameState.try_unlock_encyclopedia is idempotent (skips if already in).
	if instance.base_id != "":
		GameState.try_unlock_encyclopedia(instance.base_id)
	EventBus.item_picked_up.emit(instance)
	EventBus.inventory_changed.emit()


func commit_round() -> void:
	if round_pickups.is_empty():
		return
	var hero_id: String = GameState.selected_hero_id
	if hero_id == "":
		round_pickups.clear()
		return
	if not hero_inventories.has(hero_id):
		hero_inventories[hero_id] = []
	var inv: Array = hero_inventories[hero_id]
	for inst in round_pickups:
		inv.append(inst)
	round_pickups.clear()
	EventBus.inventory_changed.emit()
	SaveManager.save_game()


func _on_level_completed(_level_id, _stars, _mode) -> void:
	# Sweep any still-on-ground drops before committing so end-of-wave drops
	# aren't lost when the scene tears down. ItemPickupManager's collect_all
	# calls _collect on each, which add_to_round's the instance back into us.
	ItemPickupManager.collect_all_pending()
	commit_round()


# -- Inventory queries ------------------------------------------------------

func get_inventory(hero_id: String) -> Array:
	return hero_inventories.get(hero_id, [])


# Phase polish — returns only items NOT currently equipped in any slot.
# Used by EquipmentScreen so equipped items render only in their slot on
# the left, not also in the inventory grid on the right (matches
# Diablo / WoW / PoE convention).
func get_unequipped(hero_id: String) -> Array:
	var equipped_uids: Dictionary = {}
	for i in SLOT_COUNT:
		var uid: String = get_equipped_uid(hero_id, i)
		if uid != "":
			equipped_uids[uid] = true
	var out: Array = []
	for inst in get_inventory(hero_id):
		if inst == null:
			continue
		if equipped_uids.has(inst.uid):
			continue
		out.append(inst)
	return out


func find_by_uid(hero_id: String, uid: String):
	for inst in get_inventory(hero_id):
		if inst != null and inst.uid == uid:
			return inst
	return null


func _ensure_equip_dict(hero_id: String) -> Dictionary:
	if not hero_equipment.has(hero_id):
		var d: Dictionary = {}
		for i in SLOT_COUNT:
			d[str(i)] = ""
		hero_equipment[hero_id] = d
	return hero_equipment[hero_id]


func get_equipped_uid(hero_id: String, slot: int) -> String:
	if slot < 0 or slot >= SLOT_COUNT:
		return ""
	var d: Dictionary = _ensure_equip_dict(hero_id)
	return String(d.get(str(slot), ""))


func get_equipped_instance(hero_id: String, slot: int):
	var uid: String = get_equipped_uid(hero_id, slot)
	if uid == "":
		return null
	return find_by_uid(hero_id, uid)


func get_all_equipped(hero_id: String) -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		var inst = get_equipped_instance(hero_id, i)
		if inst != null:
			out.append(inst)
	return out


# -- Equip / unequip --------------------------------------------------------
# No runtime stat application here — that's the hero's AbilityHost job on
# spawn. This module only tracks which uid occupies which slot. Equip is
# authored for between-level UI (never called mid-run in Phase 48).

func equip(hero_id: String, uid: String) -> bool:
	var inst = find_by_uid(hero_id, uid)
	if inst == null:
		return false
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		push_warning("[InventoryManager] equip: unknown base_id %s" % inst.base_id)
		return false
	var slot: int = int(base.slot)
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var d: Dictionary = _ensure_equip_dict(hero_id)
	var previous_uid: String = String(d.get(str(slot), ""))
	if previous_uid == uid:
		return false
	d[str(slot)] = uid
	if previous_uid != "":
		EventBus.item_unequipped.emit(hero_id, slot, find_by_uid(hero_id, previous_uid))
	EventBus.item_equipped.emit(hero_id, slot, inst)
	EventBus.inventory_changed.emit()
	return true


func unequip(hero_id: String, slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var d: Dictionary = _ensure_equip_dict(hero_id)
	var uid: String = String(d.get(str(slot), ""))
	if uid == "":
		return false
	d[str(slot)] = ""
	EventBus.item_unequipped.emit(hero_id, slot, find_by_uid(hero_id, uid))
	EventBus.inventory_changed.emit()
	return true


# -- Starter gear -----------------------------------------------------------

func ensure_starter_gear(hero_id: String) -> void:
	if hero_id == "" or starter_gear_granted.has(hero_id):
		return
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null or not ("starter_items" in hero_data):
		starter_gear_granted.append(hero_id)
		return
	if not hero_inventories.has(hero_id):
		hero_inventories[hero_id] = []
	var inv: Array = hero_inventories[hero_id]
	for base in hero_data.starter_items:
		if base == null:
			continue
		var inst = _ItemInstanceScript.new()
		inst.uid = SaveManager.issue_uid()
		inst.base_id = base.base_id
		inst.rolled_affixes = []
		inst.found_at_wave = 0
		inv.append(inst)
		# Auto-equip into the base's slot (if empty).
		var slot_str: String = str(int(base.slot))
		var d: Dictionary = _ensure_equip_dict(hero_id)
		if String(d.get(slot_str, "")) == "":
			d[slot_str] = inst.uid
	starter_gear_granted.append(hero_id)
	EventBus.inventory_changed.emit()
	SaveManager.save_game()
