extends Node

# Phase 48 — Persistent loot ledger. Pure bookkeeping; stats flow through the
# hero's modifier stack via AbilityHost.equip_ability (see BaseHero._ready
# item-pass in A12). No stat mutation lives here.
#
# Data model (post-IA-2 refactor):
#   shared_inventory          -> Array[ItemInstance]    (ALL owned items,
#                                 hero-agnostic — single pool browsed by
#                                 every hero, AAA-style stash)
#   hero_equipment[hero_id]   -> Dict[slot_str -> uid]  ("0".."5" keys; 6
#                                 slots) — references shared_inventory uids
#   round_pickups             -> Array[ItemInstance]    (this-run-only; merged
#                                 into shared_inventory on level_completed)
#   starter_gear_granted      -> Array[String]          (hero_ids that already
#                                 received their starter pack — never re-grant)
#
# IA-2 history: prior `hero_inventories[hero_id]` silos were collapsed into
# the single shared pool. Equipment refs by uid are unchanged. SaveManager
# v2→v3 migration flattens old saves transparently.
#
# UIDs come from SaveManager.issue_uid(). Six slots per hero always present
# (3 active, 3 reserved) so future Phase F activation needs no migration.

const _ItemInstanceScript := preload("res://items/ItemInstance.gd")
const _SellPriceTable: Resource = preload("res://economy/sell_price_table.tres")
const SLOT_COUNT: int = 6
# IA-3 — soft inventory cap. Drops past this point are auto-sold at half
# price (per `_AUTO_SELL_RATIO`) instead of being lost — converts the cap
# into pressure to clean up rather than a hard punishment. Tunable.
const MAX_INVENTORY_SIZE: int = 60
const _AUTO_SELL_RATIO: float = 0.5

var shared_inventory: Array = []           # Array[ItemInstance] — global pool
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


# 2026-04-29 audit fix — full wipe of every InventoryManager-owned field.
# Called from SaveManager.delete_save() so "Reset Progress" actually clears
# items, equipment slots, and the starter-gear bookkeeping (which previously
# blocked re-grants because starter_gear_granted survived the reset).
func reset() -> void:
	shared_inventory.clear()
	hero_equipment.clear()
	round_pickups.clear()
	starter_gear_granted.clear()
	EventBus.inventory_changed.emit()


# -- Persistence round-trip (called by SaveManager) -------------------------

func to_save_dict() -> Dictionary:
	# IA-2 — shared_inventory is one flat array now; serialize as an Array of
	# instance dicts (vs the prior dict-of-arrays keyed by hero_id).
	var arr: Array = []
	for inst in shared_inventory:
		if inst != null:
			arr.append(inst.to_dict())
	return {
		"shared_inventory": arr,
		"hero_equipment": hero_equipment.duplicate(true),
		"starter_gear_granted": starter_gear_granted.duplicate(),
	}


func from_save_dict(d: Dictionary) -> void:
	# IA-2 — accepts either the new shared_inventory format OR a v2 save's
	# hero_inventories silos (SaveManager normally migrates v2 → v3 first,
	# but this fallback is defensive: a save loader that bypasses migration
	# still ends up with a flat shared pool).
	shared_inventory.clear()
	if d.has("shared_inventory") and d.shared_inventory is Array:
		for entry in d.shared_inventory:
			if entry is Dictionary:
				shared_inventory.append(_ItemInstanceScript.from_dict(entry))
	elif d.has("hero_inventories") and d.hero_inventories is Dictionary:
		# Defensive v2-shape fallback. Items merge in encounter order; uids are
		# globally unique (SaveManager.next_uid is monotonic) so no collision.
		for hero_id in d.hero_inventories.keys():
			for entry in d.hero_inventories[hero_id]:
				if entry is Dictionary:
					shared_inventory.append(_ItemInstanceScript.from_dict(entry))
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
	# IA-2 — drops are now hero-agnostic. They flow into the shared pool
	# regardless of which hero was on the level (the player can browse them
	# from any hero afterward, gated by hero_restriction at equip time).
	# IA-3 — each entry routes through `add_to_shared` which enforces the
	# capacity cap (auto-sells overflow at half price).
	if round_pickups.is_empty():
		return
	for inst in round_pickups:
		add_to_shared(inst)
	round_pickups.clear()
	EventBus.inventory_changed.emit()
	SaveManager.save_game()


# IA-3 — Single chokepoint for adding an instance to the shared pool.
# Returns true when the item entered inventory; false when the cap auto-sold
# it. Emits `item_sold` + meta-gold credit + a toast on the auto-sell path
# so the player has clear feedback that something happened to the drop.
# Starter gear bypasses this on purpose — call paths that grant starter
# items append directly to `shared_inventory` (idempotent + always allowed).
func add_to_shared(instance) -> bool:
	if instance == null:
		return false
	if shared_inventory.size() >= MAX_INVENTORY_SIZE:
		var auto_sell_price: int = 0
		var base: Resource = ContentRegistry.find_item_base(instance.base_id)
		if base != null:
			auto_sell_price = int(_SellPriceTable.price_for(int(base.rarity)) * _AUTO_SELL_RATIO)
		if auto_sell_price > 0:
			GameState.add_meta_gold(auto_sell_price)
			EventBus.item_sold.emit(instance, auto_sell_price)
			Toast.show_message("Inventory full — auto-sold for %dg" % auto_sell_price)
		else:
			Toast.show_message("Inventory full — drop discarded")
		return false
	shared_inventory.append(instance)
	return true


func _on_level_completed(_level_id, _stars, _mode) -> void:
	# Sweep any still-on-ground drops before committing so end-of-wave drops
	# aren't lost when the scene tears down. ItemPickupManager's collect_all
	# calls _collect on each, which add_to_round's the instance back into us.
	ItemPickupManager.collect_all_pending()
	commit_round()


# -- Inventory queries ------------------------------------------------------

func get_shared_inventory() -> Array:
	# IA-2 — direct accessor for the global pool. Most callers should use
	# get_unequipped() instead; this is for code that needs every owned item
	# (encyclopedia, save migration audit, etc.).
	return shared_inventory


# Returns only items NOT currently equipped in ANY hero's slots. Used by
# EquipmentScreen so an item the Warrior is wielding doesn't double-appear
# in the Mage's inventory grid (matches Diablo / WoW / PoE convention —
# equipped is in-use everywhere).
func get_unequipped() -> Array:
	# IA-2 — sweep every hero's equipment, not just the active one. An item
	# equipped on Hero A is not "available inventory" from Hero B's view.
	var equipped_uids: Dictionary = {}
	for hero_id in hero_equipment.keys():
		var d: Dictionary = hero_equipment[hero_id]
		for i in SLOT_COUNT:
			var uid: String = String(d.get(str(i), ""))
			if uid != "":
				equipped_uids[uid] = true
	var out: Array = []
	for inst in shared_inventory:
		if inst == null:
			continue
		if equipped_uids.has(inst.uid):
			continue
		out.append(inst)
	return out


func find_by_uid(uid: String):
	for inst in shared_inventory:
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
	return find_by_uid(uid)


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
	var inst = find_by_uid(uid)
	if inst == null:
		return false
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		push_warning("[InventoryManager] equip: unknown base_id %s" % inst.base_id)
		return false
	var slot: int = int(base.slot)
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	# IA-1 — enforce hero_restriction. Empty array = any hero (default);
	# non-empty = whitelist. Item declines to be equipped on a non-listed hero.
	if base.hero_restriction.size() > 0 and not base.hero_restriction.has(hero_id):
		var hero_data: Resource = ContentRegistry.find_hero(hero_id)
		var hero_name: String = hero_data.hero_name if hero_data != null and "hero_name" in hero_data else hero_id
		Toast.show_message("%s can't use this item" % hero_name)
		return false
	# IA-1 — enforce level_requirement. Skipped when set to 1 (the default
	# value for items with no level gate).
	if base.level_requirement > 1 and GameState.get_hero_level(hero_id) < base.level_requirement:
		Toast.show_message("Requires Lv %d" % base.level_requirement)
		return false
	var d: Dictionary = _ensure_equip_dict(hero_id)
	var previous_uid: String = String(d.get(str(slot), ""))
	if previous_uid == uid:
		return false
	d[str(slot)] = uid
	if previous_uid != "":
		EventBus.item_unequipped.emit(hero_id, slot, find_by_uid(previous_uid))
	EventBus.item_equipped.emit(hero_id, slot, inst)
	EventBus.inventory_changed.emit()
	return true


# IA-1 — Internal helper used by both the equip path and ensure_starter_gear.
# Returns true when the base passes hero + level gates for this hero. Pure
# read; no side effects, no toasts (those are the caller's responsibility).
func _can_hero_equip(hero_id: String, base: Resource) -> bool:
	if base == null:
		return false
	if base.hero_restriction.size() > 0 and not base.hero_restriction.has(hero_id):
		return false
	if base.level_requirement > 1 and GameState.get_hero_level(hero_id) < base.level_requirement:
		return false
	return true


func unequip(hero_id: String, slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var d: Dictionary = _ensure_equip_dict(hero_id)
	var uid: String = String(d.get(str(slot), ""))
	if uid == "":
		return false
	d[str(slot)] = ""
	EventBus.item_unequipped.emit(hero_id, slot, find_by_uid(uid))
	EventBus.inventory_changed.emit()
	return true


# -- Sell / destroy ---------------------------------------------------------
# `destroy` is the lower-level item-removal primitive. Sell is the
# player-facing version that also pays out meta-gold. Future Town phases
# (disenchant, craft-consume) can reuse `destroy` directly.

func _is_equipped(uid: String) -> bool:
	# IA-2 — checked across ALL heroes' equipment, not just one. An item
	# equipped on Hero A is "in use" from anyone's perspective.
	for hero_id in hero_equipment.keys():
		var d: Dictionary = hero_equipment[hero_id]
		for i in SLOT_COUNT:
			if String(d.get(str(i), "")) == uid:
				return true
	return false


func destroy(uid: String) -> bool:
	# Remove an item from the shared pool. Refuses to destroy items equipped
	# on ANY hero — caller must unequip first. Returns true when something
	# was actually removed (so callers know whether to commit side effects).
	var idx: int = -1
	for i in shared_inventory.size():
		if shared_inventory[i] != null and shared_inventory[i].uid == uid:
			idx = i
			break
	if idx < 0:
		return false
	if _is_equipped(uid):
		# Defensive — sell() blocks at the UI layer, but other future callers
		# (disenchant, craft) shouldn't accidentally nuke equipped gear either.
		push_warning("[InventoryManager] destroy refused: %s is equipped" % uid)
		return false
	shared_inventory.remove_at(idx)
	EventBus.inventory_changed.emit()
	return true


func sell(uid: String) -> int:
	# Sell an inventory item for meta-gold. Returns the gold awarded
	# (0 on failure — bad uid, equipped item, locked item, missing base data).
	var inst = find_by_uid(uid)
	if inst == null:
		return 0
	# IP-3 — refuse to sell pinned items. UI also blocks but defense-in-depth
	# matters here because sell pays out gold; double-protection costs nothing.
	if inst.locked:
		return 0
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		push_warning("[InventoryManager] sell: unknown base_id %s" % inst.base_id)
		return 0
	var reward: int = _SellPriceTable.price_for(int(base.rarity))
	# destroy() also handles the equipped-item refusal — bail before paying out
	# if the destroy fails so the player can't accidentally print free gold.
	if not destroy(uid):
		return 0
	GameState.add_meta_gold(reward)
	EventBus.item_sold.emit(inst, reward)
	SaveManager.save_game()
	return reward


# IP-3 — flip the lock state on an inventory item. Returns the new state
# (true = locked). Invalid uid returns false silently (caller can re-query).
# Persists immediately so a crash doesn't lose the player's pinning work.
func toggle_lock(uid: String) -> bool:
	var inst = find_by_uid(uid)
	if inst == null:
		return false
	inst.locked = not inst.locked
	EventBus.inventory_changed.emit()
	SaveManager.save_game()
	return inst.locked


# Compute the would-be sell price without committing — used by the
# Equipment-tab Sell button to label "Sell for Ng" before the player taps.
func get_sell_price(uid: String) -> int:
	var inst = find_by_uid(uid)
	if inst == null:
		return 0
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		return 0
	return _SellPriceTable.price_for(int(base.rarity))


# -- Starter gear -----------------------------------------------------------

func ensure_starter_gear(hero_id: String) -> void:
	if hero_id == "" or starter_gear_granted.has(hero_id):
		return
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null or not ("starter_items" in hero_data):
		starter_gear_granted.append(hero_id)
		return
	# IA-2 — starter items go straight into the shared pool. Auto-equip step
	# below uses _can_hero_equip to gate restricted-or-too-low-level items.
	for base in hero_data.starter_items:
		if base == null:
			continue
		var inst = _ItemInstanceScript.new()
		inst.uid = SaveManager.issue_uid()
		inst.base_id = base.base_id
		inst.rolled_affixes = []
		inst.found_at_wave = 0
		shared_inventory.append(inst)
		# Auto-equip into the base's slot (if empty AND the base passes the
		# same hero/level gates that interactive equip uses). Defense against
		# a misconfigured starter pack — a hero-restricted-to-Mage item in
		# Warrior's starter list would otherwise be silently force-equipped.
		if not _can_hero_equip(hero_id, base):
			continue
		var slot_str: String = str(int(base.slot))
		var d: Dictionary = _ensure_equip_dict(hero_id)
		if String(d.get(slot_str, "")) == "":
			d[slot_str] = inst.uid
	starter_gear_granted.append(hero_id)
	EventBus.inventory_changed.emit()
	SaveManager.save_game()
