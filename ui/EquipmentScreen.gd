extends Control

# Phase 50 — Equipment screen with paperdoll backdrop + per-hero variable
# slots. The 6 ItemBase.slot indices are unchanged (0=Weapon, 1=Armor,
# 2=Helm, 3=Gloves, 4=Boots, 5=Trinket); a hero exposes only the subset
# listed in HeroData.equipment_slots. Default empty array = all 6.
#
# Slots position via Paperdoll.anchor_for_slot — humanoid heroes use the
# default anchors; non-humanoid (Dragon) overrides via HeroData.slot_anchors.
# Slot labels can be renamed per hero via HeroData.slot_label_overrides
# (e.g. Dragon shows "Breath Sigil" instead of "Weapon").
#
# Reached either standalone (legacy WorldMap path) or embedded in HeroesHub.

const _ItemIconScript := preload("res://ui/ItemIcon.gd")
const SLOT_COUNT: int = 6
const DEFAULT_SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Helm", "Gloves", "Boots", "Trinket"]
const ALL_SLOT_INDICES: Array[int] = [0, 1, 2, 3, 4, 5]

# Phase 49 — fixed spatial grid. CELL_PX matches ItemIcon.SIZE_PX so 1×1
# tiles look identical to the prior reflow layout; multi-cell items extend
# to (w*CELL_PX, h*CELL_PX). No gaps between cells (Diablo-style packed grid).
# Bumped 92→120 in the mobile-fit pass so tiles clear Material Design's
# 7 mm touch-target floor on a typical 6.1″ phone.
const CELL_PX: float = 120.0
# Phase 50 — paperdoll slots use a uniform 1×1 footprint regardless of item
# size, so they arrange around the silhouette evenly. Item icons in the
# inventory grid still render at their real footprint (1×2 swords etc.).
const PAPERDOLL_SLOT_W: int = 1
const PAPERDOLL_SLOT_H: int = 1

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var hero_label: Label = %HeroLabel
@onready var equipment_grid: Control = %EquipmentGrid
@onready var stats_panel: VBoxContainer = %StatsPanel
@onready var details_label: Label = %DetailsLabel
@onready var right_title: Label = %RightTitle
@onready var inventory_grid: Control = %InventoryGrid
@onready var hint_label: Label = %HintLabel
@onready var sell_mode_button: Button = %SellModeButton
@onready var lock_button: Button = %LockButton
@onready var sell_all_button: Button = %SellAllButton
@onready var meta_gold_label: Label = %MetaGoldLabel

# Holds the hero_id at the last _refresh call, used by hover to compute diffs.
var _cached_hero_id: String = ""

# Slot index (0-5) → ItemIcon instance
var _slot_icons: Dictionary = {}

# Sell-mode state — when on, tapping an inventory item starts a two-tap
# confirm to sell it instead of equipping. _pending_sell_uid holds the
# armed item; second tap on the same uid commits.
var _sell_mode: bool = false
var _pending_sell_uid: String = ""
# IP-4 — two-tap confirm for the batch "Sell all Common" button so an
# accidental tap can't liquidate every Common in one move.
var _sell_all_armed: bool = false

# Phase 49 — Stats panel state. _stat_rows maps stat key → StatRow Control,
# populated once in _build_stats_panel and addressed by key on every refresh
# / flash. _last_stats_dict caches the previously-rendered values so we can
# detect which stats changed when an item is equipped/unequipped. The
# _first_refresh flag suppresses flash + toast on initial load (no prior
# state to compare against). _last_equipped_name caches the name of the
# item that triggered the most recent refresh, consumed when building the
# toast summary line.
const _StatRowScript := preload("res://ui/StatRow.gd")
const _GAIN_FLASH_COLOR: Color = Color(0.55, 1.0, 0.55, 1.0)
const _LOSS_FLASH_COLOR: Color = Color(1.0, 0.55, 0.55, 1.0)
const _SECTION_HEADER_COLOR: Color = Color(0.6, 0.66, 0.78, 1.0)
const _STATS_LAYOUT: Array = [
	# section_name, [ (stat_key, display_name), ... ]
	# stat_key matches the keys returned by _compute_stats_dict — same string
	# is also passed to StatIcon.draw to pick the glyph.
	["OFFENSE", [["damage", "Damage"], ["attack_speed", "Atk Speed"]]],
	["DEFENSE", [["max_health", "Max HP"], ["armor", "Armor"]]],
	["UTILITY", [["move_speed", "Move Speed"], ["xp_gain_mult", "XP Gain"]]],
]
var _stat_rows: Dictionary = {}
var _last_stats_dict: Dictionary = {}
var _first_refresh: bool = true
var _last_equipped_name: String = ""
var _last_change_was_unequip: bool = false


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	# Ensure starter gear is granted + equipped for the currently selected
	# hero even if the player hasn't entered a level yet. Idempotent via
	# starter_gear_granted bookkeeping. MUST happen BEFORE we build slots
	# and connect inventory signals — ensure_starter_gear emits
	# inventory_changed, which would otherwise hit _refresh with an empty
	# _slot_icons dict.
	var hero_id: String = LoadoutState.selected_hero_id
	if hero_id != "":
		InventoryManager.ensure_starter_gear(hero_id)
	_build_slots()
	_build_stats_panel()
	EventBus.item_equipped.connect(_on_item_equipped)
	EventBus.item_unequipped.connect(_on_item_unequipped)
	EventBus.inventory_changed.connect(_on_inventory_changed_simple)
	# Refresh when the active hero changes (e.g. HeroesHub roster swap).
	# Rebuild slots first — the new hero may expose a different slot set
	# (Dragon = 3 slots vs humanoid 6) — then refresh stats + paperdoll.
	# Reset _first_refresh BEFORE ensure_starter_gear: that call can emit
	# inventory_changed → _on_inventory_changed_simple → _refresh, which
	# would otherwise compare the new hero's stats against the previous
	# hero's _last_stats_dict and fire a phantom "you equipped X" toast.
	EventBus.hero_selected.connect(func(new_id):
		_first_refresh = true
		_last_stats_dict.clear()
		if new_id != "":
			InventoryManager.ensure_starter_gear(new_id)
		_build_slots()
		_refresh()
	)
	# Sell-mode controls + meta-gold counter live-update.
	sell_mode_button.pressed.connect(_on_sell_mode_toggled)
	lock_button.pressed.connect(_on_lock_pressed)
	sell_all_button.pressed.connect(_on_sell_all_pressed)
	EventBus.meta_gold_changed.connect(_on_meta_gold_changed)
	_refresh_meta_gold_label()
	_refresh_sell_mode_visuals()
	_refresh()


func _on_inventory_changed(_hero_id, _slot, _instance) -> void:
	_refresh()


# Phase 49 — separate handlers for equip vs unequip so we can capture the
# affected item's name for the on-equip toast summary. Both still trigger
# a full _refresh which is where the flash + toast logic actually fires.
func _on_item_equipped(_hero_id, _slot, instance) -> void:
	_last_equipped_name = _resolve_item_name(instance)
	_last_change_was_unequip = false
	_refresh()


func _on_item_unequipped(_hero_id, _slot, instance) -> void:
	_last_equipped_name = _resolve_item_name(instance)
	_last_change_was_unequip = true
	_refresh()


func _resolve_item_name(instance) -> String:
	if instance == null:
		return ""
	var base: Resource = ContentRegistry.find_item_base(instance.base_id)
	if base != null and "base_name" in base:
		return String(base.base_name)
	return String(instance.base_id)


func _on_inventory_changed_simple() -> void:
	_refresh()
	# IP-3 / IP-4 — keep lock-button label and sell-all count in sync with
	# the latest inventory state (e.g., after a lock toggle or batch sell).
	if _sell_mode:
		_refresh_lock_button()
		_refresh_sell_all_button()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _build_slots() -> void:
	# Phase 50 — paperdoll layout. Slot icons are positioned via the
	# Paperdoll-attached EquipmentGrid's anchor_for_slot(slot_idx). Each
	# slot is a uniform 1×1 footprint regardless of item size so the
	# layout reads cleanly around the silhouette. Items in inventory keep
	# their real footprint.
	# Wipe any existing icons (called on hero swap to rebuild for the new hero).
	for child in equipment_grid.get_children():
		# Skip non-ItemIcon children (none expected, defensive).
		child.queue_free()
	_slot_icons.clear()
	for slot_idx in _active_slot_indices_for(LoadoutState.selected_hero_id):
		_build_one_slot(int(slot_idx))


func _build_one_slot(slot_idx: int) -> void:
	var icon: Control = _ItemIconScript.new()
	icon.set_slot_footprint(PAPERDOLL_SLOT_W, PAPERDOLL_SLOT_H)
	# Position via the Paperdoll's anchor_for_slot. Anchor is the slot's
	# centerpoint, so subtract half the icon's footprint to top-left it.
	var anchor: Vector2 = equipment_grid.anchor_for_slot(slot_idx) if equipment_grid.has_method("anchor_for_slot") else Vector2.ZERO
	var half := Vector2(CELL_PX * 0.5 * PAPERDOLL_SLOT_W, CELL_PX * 0.5 * PAPERDOLL_SLOT_H)
	icon.position = anchor - half
	icon.pressed.connect(_on_slot_pressed.bind(slot_idx))
	icon.hovered.connect(_on_item_hovered)
	icon.unhovered.connect(_on_item_unhovered)
	# IP-2 — long-press an equipped slot to see its details (mobile-only
	# path; on PC, hover already works).
	icon.long_pressed.connect(_on_item_hovered)
	_slot_icons[slot_idx] = icon
	equipment_grid.add_child(icon)


# Returns the slot indices THIS hero exposes. Reads HeroData.equipment_slots;
# empty array (or no hero data) falls back to the default 6-slot humanoid set.
func _active_slot_indices_for(hero_id: String) -> Array:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null or not ("equipment_slots" in hero_data):
		return ALL_SLOT_INDICES.duplicate()
	var arr: Array = hero_data.equipment_slots
	if arr.is_empty():
		return ALL_SLOT_INDICES.duplicate()
	var out: Array = []
	for v in arr:
		var i: int = int(v)
		if i >= 0 and i < SLOT_COUNT:
			out.append(i)
	return out


# Display label for a slot. Honors HeroData.slot_label_overrides for
# per-hero rename (e.g. Dragon's "Weapon" → "Breath Sigil"); falls back
# to DEFAULT_SLOT_NAMES.
func _resolve_slot_label(slot_idx: int) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(LoadoutState.selected_hero_id)
	if hero_data != null and "slot_label_overrides" in hero_data:
		var ov: Dictionary = hero_data.slot_label_overrides
		if ov.has(slot_idx):
			return String(ov[slot_idx])
	if slot_idx >= 0 and slot_idx < DEFAULT_SLOT_NAMES.size():
		return DEFAULT_SLOT_NAMES[slot_idx]
	return "Slot %d" % slot_idx


func _refresh() -> void:
	var hero_id: String = LoadoutState.selected_hero_id
	_cached_hero_id = hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var level: int = MetaProgression.get_hero_level(hero_id)
	hero_label.text = "%s — Lv %d" % [hero_data.hero_name, level] if hero_data != null else hero_id
	# Stats panel — mirrors BaseHero.recompute_stats formulas so the numbers
	# shown here match what the hero will have on next spawn. The grouped /
	# iconified rows + on-equip flash live in _refresh_stats_panel.
	_refresh_stats_panel(hero_data, InventoryManager.get_all_equipped(hero_id))
	# Clear details on any refresh; hover repopulates.
	# 2026-04-29 audit fix — preserve details during sell mode. _refresh()
	# fires on every sell-arm tap (to re-modulate icons), and wiping the
	# details panel each tap kills any context the player just long-pressed
	# to read. In sell mode, the hover/long-press path owns the label.
	if not _sell_mode:
		details_label.text = "Hover an item to see its details."
	# Phase 50 — paperdoll backdrop reflects the currently selected hero.
	# EquipmentGrid has Paperdoll.gd as its script; setup() refreshes both
	# the silhouette draw and the slot anchor map.
	if equipment_grid != null and equipment_grid.has_method("setup"):
		equipment_grid.setup(hero_data)
	# Left: slot state. _slot_icons only contains slots this hero exposes
	# (rebuilt by _build_slots whenever the hero changes).
	for slot_idx in _slot_icons.keys():
		var icon: Control = _slot_icons[slot_idx]
		var inst = InventoryManager.get_equipped_instance(hero_id, slot_idx)
		if inst == null:
			icon.setup_empty()
		else:
			icon.setup_instance(inst)
	# Right: inventory grid — only UNEQUIPPED items (equipped render on the
	# left only, matches ARPG convention). Header shows TOTAL pool size vs
	# cap (equipped count toward the cap), so the player sees at-a-glance
	# how much room is left before drops start auto-selling.
	for child in inventory_grid.get_children():
		child.queue_free()
	# Phase 49 — fixed spatial grid. Position each item icon at its grid
	# coordinates (top-left corner = (col * CELL_PX, row * CELL_PX)), sized
	# by its base footprint. Empty cells render a placeholder so the grid
	# reads as a real container even when sparse.
	var inv: Array = InventoryManager.get_unequipped()
	var rows: int = InventoryManager.GRID_ROWS
	var cols: int = InventoryManager.GRID_COLS
	# Build a "covered" mask in this scope to decide which cells need a
	# placeholder. Mirrors InventoryManager._build_occupancy but limited to
	# unequipped items (equipped ones are guaranteed to be at -1/-1).
	var cover: Array = []
	for _r in rows:
		var row: Array = []
		row.resize(cols)
		for c in cols:
			row[c] = false
		cover.append(row)
	for inst in inv:
		if inst == null or inst.grid_row < 0 or inst.grid_col < 0:
			continue
		var b: Resource = ContentRegistry.find_item_base(inst.base_id)
		if b == null:
			continue
		var iw: int = maxi(1, int(b.grid_width))
		var ih: int = maxi(1, int(b.grid_height))
		for dr in ih:
			for dc in iw:
				var rr: int = inst.grid_row + dr
				var cc: int = inst.grid_col + dc
				if rr >= 0 and rr < rows and cc >= 0 and cc < cols:
					cover[rr][cc] = true
	var filled_cells: int = 0
	for r in rows:
		for c in cols:
			if cover[r][c]:
				filled_cells += 1
	var total_cells: int = rows * cols
	right_title.text = "Inventory (%d / %d)" % [filled_cells, total_cells]
	right_title.modulate = Color.WHITE
	# Empty placeholders first — drawn under any item icons. mouse_filter set
	# to IGNORE so they don't catch clicks (which would no-op anyway) and so
	# moving the cursor across an empty cell between two real items doesn't
	# fire spurious enter/exit events on the empty.
	for r in rows:
		for c in cols:
			if cover[r][c]:
				continue
			var empty_icon: Control = _ItemIconScript.new()
			empty_icon.setup_empty()
			empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_icon.position = Vector2(c * CELL_PX, r * CELL_PX)
			empty_icon.size = Vector2(CELL_PX, CELL_PX)
			inventory_grid.add_child(empty_icon)
	# Item tiles — placed at their stored grid coordinates, sized by footprint.
	for inst in inv:
		if inst == null or inst.grid_row < 0 or inst.grid_col < 0:
			continue
		var base: Resource = ContentRegistry.find_item_base(inst.base_id)
		var w: int = 1
		var h: int = 1
		if base != null:
			w = maxi(1, int(base.grid_width))
			h = maxi(1, int(base.grid_height))
		var icon: Control = _ItemIconScript.new()
		icon.setup_instance(inst)
		icon.position = Vector2(inst.grid_col * CELL_PX, inst.grid_row * CELL_PX)
		icon.size = Vector2(w * CELL_PX, h * CELL_PX)
		icon.pressed.connect(_on_inventory_item_pressed)
		icon.hovered.connect(_on_item_hovered)
		icon.unhovered.connect(_on_item_unhovered)
		# IP-2 — long-press shows details on touch (mobile-equivalent of hover).
		# Reuses the existing hover handler so the details panel logic isn't
		# duplicated. Tapped items still equip / sell-arm — long-press is the
		# read-without-acting path.
		icon.long_pressed.connect(_on_item_hovered)
		# Sell-mode visual cue: faint red tint on every inventory item, with a
		# brighter glow on the armed (pending-confirm) item.
		if _sell_mode:
			if _pending_sell_uid == inst.uid:
				icon.modulate = Color(1.4, 0.7, 0.7, 1.0)
			else:
				icon.modulate = Color(1.0, 0.85, 0.85, 1.0)
		inventory_grid.add_child(icon)


# --- Interaction (D3) -------------------------------------------------------
# Direct-tap model: tap an inventory item → equip into its slot (swaps out
# anything currently there; the swapped-out item stays in inventory). Tap
# an equipped slot → unequip (slot goes empty, item still owned). Tapping a
# locked slot toasts "Slot locked".

func _on_inventory_item_pressed(inst) -> void:
	if inst == null:
		return
	# In sell mode, tap-to-arm-or-confirm the sell instead of equipping.
	if _sell_mode:
		_handle_sell_tap(inst)
		return
	var hero_id: String = LoadoutState.selected_hero_id
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		return
	var slot: int = int(base.slot)
	# Phase 50 — slots not authored on this hero refuse the item with a
	# clear toast (e.g. Dragon won't accept a humanoid Helm).
	if not (slot in _active_slot_indices_for(hero_id)):
		Toast.show_message("%s has no %s slot" % [_hero_name(hero_id), _resolve_slot_label(slot)])
		return
	InventoryManager.equip(hero_id, inst.uid)


func _hero_name(hero_id: String) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	return String(hero_data.hero_name) if hero_data != null and "hero_name" in hero_data else hero_id


# --- Sell mode ---------------------------------------------------------------
# Toggle button on the inventory header flips the panel into a "tap items to
# sell" state. Two-tap confirm: first tap arms a uid (toast + the icon stays
# brighter); second tap on the SAME uid commits the sale via
# InventoryManager.sell, which pays out meta-gold and removes the item.
# Tapping a different inventory item re-arms with that uid.
# Equipped slots aren't sellable (unequip first) — the slot tap handler keeps
# its existing unequip behavior even in sell mode so the player can free a
# slot without leaving the mode.

func _on_sell_mode_toggled() -> void:
	_sell_mode = not _sell_mode
	_pending_sell_uid = ""
	_refresh_sell_mode_visuals()
	_refresh()  # rebuilds inventory grid so each icon re-modulates


func _refresh_sell_mode_visuals() -> void:
	if _sell_mode:
		sell_mode_button.text = "Done"
		sell_mode_button.modulate = Color(1.0, 0.6, 0.6, 1.0)
		lock_button.visible = true
		sell_all_button.visible = true
		_refresh_lock_button()
		_refresh_sell_all_button()
		hint_label.text = "Sell mode: tap to mark for sale (tap again to confirm). Long-press for details. Use 🔒 to pin an armed item against sale."
	else:
		sell_mode_button.text = "Sell Mode"
		sell_mode_button.modulate = Color.WHITE
		lock_button.visible = false
		sell_all_button.visible = false
		_sell_all_armed = false
		hint_label.text = "Tap inventory item to equip. Tap equipped slot to unequip (item stays in inventory). Long-press for details."


# IP-3 — Lock button reflects the armed item's current lock state. Without
# an armed item, it's a no-op (toast hint). With one, it toggles the pin
# and updates the button label so the player sees what the next tap does.
func _refresh_lock_button() -> void:
	if _pending_sell_uid == "":
		lock_button.text = "🔒 Lock"
		lock_button.disabled = true
		return
	lock_button.disabled = false
	var inst = InventoryManager.find_by_uid(_pending_sell_uid)
	if inst != null and "locked" in inst and inst.locked:
		lock_button.text = "🔓 Unlock"
	else:
		lock_button.text = "🔒 Lock"


func _on_lock_pressed() -> void:
	if _pending_sell_uid == "":
		Toast.show_message("Tap an item first to choose what to lock")
		return
	var now_locked: bool = InventoryManager.toggle_lock(_pending_sell_uid)
	# Toggling consumes the arm — locking an item should NOT also stay-armed
	# for sale (that'd be confusing UX). The inventory_changed signal fires
	# from toggle_lock, so the icon redraw picks up the lock glyph for free.
	_pending_sell_uid = ""
	_refresh_lock_button()
	Toast.show_message("Locked from sale" if now_locked else "Unlocked")


# IP-4 — Two-tap-confirm batch sell of every unlocked Common in inventory.
# First tap arms with a 3-second auto-disarm; second tap commits. Skips
# locked items entirely (the whole point of the lock). Pricing per item
# uses the same SellPriceTable as single-item sells.
func _refresh_sell_all_button() -> void:
	var count: int = _count_sell_all_eligible()
	if _sell_all_armed:
		sell_all_button.text = "Confirm: sell %d" % count
		sell_all_button.modulate = Color(1.0, 0.7, 0.4, 1.0)
	else:
		sell_all_button.text = "Sell all Common (%d)" % count
		sell_all_button.modulate = Color.WHITE
	sell_all_button.disabled = count == 0


func _count_sell_all_eligible() -> int:
	# Counts unlocked, unequipped Commons. Mirrors the criteria used by
	# _on_sell_all_pressed so the displayed count matches what gets sold.
	var n: int = 0
	for inst in InventoryManager.get_unequipped():
		if inst == null or inst.locked:
			continue
		var base: Resource = ContentRegistry.find_item_base(inst.base_id)
		if base == null:
			continue
		if int(base.rarity) == 0:
			n += 1
	return n


func _on_sell_all_pressed() -> void:
	if not _sell_all_armed:
		var count: int = _count_sell_all_eligible()
		if count == 0:
			Toast.show_message("No unlocked Common items to sell")
			return
		_sell_all_armed = true
		_refresh_sell_all_button()
		# Auto-disarm after 3 seconds matches the single-item sell flow.
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(self) and _sell_all_armed:
				_sell_all_armed = false
				_refresh_sell_all_button()
		)
		return
	# Confirmed — sweep the inventory once, collect uids first to avoid
	# mutating the array we're iterating.
	_sell_all_armed = false
	var uids_to_sell: Array[String] = []
	for inst in InventoryManager.get_unequipped():
		if inst == null or inst.locked:
			continue
		var base: Resource = ContentRegistry.find_item_base(inst.base_id)
		if base == null:
			continue
		if int(base.rarity) == 0:
			uids_to_sell.append(inst.uid)
	var sold: int = 0
	var total_gold: int = 0
	for uid in uids_to_sell:
		var awarded: int = InventoryManager.sell(uid)
		if awarded > 0:
			sold += 1
			total_gold += awarded
	if sold > 0:
		Toast.show_message("Sold %d items for %dg" % [sold, total_gold])
	_refresh_sell_all_button()


func _handle_sell_tap(inst) -> void:
	# IP-3 — locked items refuse sale even at the UI layer, with a clear
	# toast instead of just silent failure deeper in InventoryManager.sell.
	if "locked" in inst and inst.locked:
		_pending_sell_uid = inst.uid  # arm so player can tap Lock to UNLOCK
		_refresh_lock_button()
		_refresh()
		Toast.show_message("Locked — tap 🔓 Unlock to allow sale")
		return
	var price: int = InventoryManager.get_sell_price(inst.uid)
	if price <= 0:
		Toast.show_message("This item can't be sold")
		return
	if _pending_sell_uid != inst.uid:
		# First tap on this item — arm the sale.
		_pending_sell_uid = inst.uid
		var base: Resource = ContentRegistry.find_item_base(inst.base_id)
		var name_str: String = base.base_name if base != null else "item"
		Toast.show_message("Sell %s for %dg? Tap again to confirm" % [name_str, price])
		_refresh_lock_button()  # button label may need to flip Lock ↔ Unlock
		_refresh()  # so the armed icon renders the visual cue
		# Auto-disarm after 3 seconds if the player walks away.
		var armed_uid: String = inst.uid
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(self) and _pending_sell_uid == armed_uid:
				_pending_sell_uid = ""
				_refresh_lock_button()
				_refresh()
		)
		return
	# Second tap on the same uid — commit.
	var awarded: int = InventoryManager.sell(inst.uid)
	_pending_sell_uid = ""
	_refresh_lock_button()
	if awarded > 0:
		Toast.show_message("Sold for %dg" % awarded)
	# inventory_changed fires via _refresh path; meta_gold_changed updates label.


func _on_meta_gold_changed(new_amount: int) -> void:
	_refresh_meta_gold_label_amount(new_amount)


func _refresh_meta_gold_label() -> void:
	_refresh_meta_gold_label_amount(MetaProgression.meta_gold)


func _refresh_meta_gold_label_amount(amount: int) -> void:
	# Only set if the label is ready — _ready may run before the @onready vars
	# are assigned in some embed orderings.
	if meta_gold_label != null:
		meta_gold_label.text = "💰 %d" % amount


func _on_slot_pressed(_signal_arg, slot_idx: int) -> void:
	# Phase 50 — slots that exist for this hero are always interactive; an
	# empty tap toasts "Slot is empty", a filled tap unequips. There's no
	# longer a locked-slot state — slots not authored on the hero simply
	# don't render.
	var hero_id: String = LoadoutState.selected_hero_id
	var current_uid: String = InventoryManager.get_equipped_uid(hero_id, slot_idx)
	if current_uid == "":
		Toast.show_message("%s slot is empty" % _resolve_slot_label(slot_idx))
		return
	InventoryManager.unequip(hero_id, slot_idx)


# --- Stats panel (D4) -------------------------------------------------------
# Mirrors BaseHero.recompute_stats so what's displayed here is what the hero
# will actually have on spawn. Duplicated formulas are acceptable — the two
# consumers (runtime hero, offline preview) have different lifecycles and
# coupling them would tangle presentation logic with simulation logic.

const _LEVEL_HEALTH_GROWTH: float = 0.15   # must match BaseHero
const _LEVEL_DAMAGE_GROWTH: float = 0.10   # must match BaseHero


# Phase 49 — Stats panel builder. Runs once at _ready, populates StatsPanel
# with three section headers and 6 StatRow children (2 per section). After
# this, _refresh_stats_panel just updates values + flashes the rows that
# changed; never rebuilds.
func _build_stats_panel() -> void:
	if stats_panel == null:
		return
	# Idempotent — clear in case _ready ran twice for any reason.
	for child in stats_panel.get_children():
		child.queue_free()
	_stat_rows.clear()
	for section_entry in _STATS_LAYOUT:
		var section_name: String = section_entry[0]
		var rows: Array = section_entry[1]
		# Compact header — small uppercase tag, minimal vertical footprint.
		var header: Label = Label.new()
		header.text = section_name
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", _SECTION_HEADER_COLOR)
		header.custom_minimum_size = Vector2(0, 14)
		stats_panel.add_child(header)
		# Two stat rows per section. Skip a bottom-divider — the next header's
		# uppercase color already differentiates sections without extra height.
		for row_entry in rows:
			var key: String = row_entry[0]
			var display: String = row_entry[1]
			var row: Control = _StatRowScript.new()
			stats_panel.add_child(row)
			# setup() needs both labels constructed; safe after add_child since
			# _ready ran. Initial value is empty — gets filled by the first
			# _refresh_stats_panel call right after.
			row.setup(key, display, "—")
			_stat_rows[key] = row


# Phase 49 — value-update + flash + toast pass. Walks every stat row,
# refreshes its value text, and on subsequent refreshes flashes the rows
# that changed. Suppresses flash + toast on the first call (no prior
# state) so the player isn't pelted with feedback on initial screen load.
func _refresh_stats_panel(hero_data: Resource, equipped: Array) -> void:
	if hero_data == null or _stat_rows.is_empty():
		return
	var current: Dictionary = _compute_stats_dict(hero_data, equipped)
	var deltas: Array = []   # Array of {key, display_name, dir, formatted_delta}
	for section_entry in _STATS_LAYOUT:
		for row_entry in section_entry[1]:
			var key: String = row_entry[0]
			var display: String = row_entry[1]
			if not _stat_rows.has(key):
				continue
			var row: Control = _stat_rows[key]
			var new_val: float = float(current.get(key, 0.0))
			var formatted: String = _format_stat_value(key, new_val)
			row.update_value(formatted)
			# Flash + delta capture, only on non-first refresh.
			if not _first_refresh and _last_stats_dict.has(key):
				var old_val: float = float(_last_stats_dict[key])
				var diff: float = new_val - old_val
				if absf(diff) > 0.0005:
					if diff > 0.0:
						row.flash(_GAIN_FLASH_COLOR)
					else:
						row.flash(_LOSS_FLASH_COLOR)
					deltas.append({
						"display": display,
						"diff": diff,
						"key": key,
					})
	_last_stats_dict = current
	# Toast summary — fires only when at least one stat changed AND there's
	# an originating item name (i.e., this refresh came from an equip/unequip,
	# not a hero-switch or initial load).
	if not _first_refresh and not deltas.is_empty() and _last_equipped_name != "":
		var verb: String = "Unequipped" if _last_change_was_unequip else "Equipped"
		var parts: Array[String] = []
		# Cap at 3 deltas to keep the toast short on big legendary swaps.
		for i in mini(deltas.size(), 3):
			var d: Dictionary = deltas[i]
			var arrow: String = "▲" if d.diff > 0.0 else "▼"
			parts.append("%s %s %s" % [arrow, d.display, _format_stat_delta(String(d.key), float(d.diff))])
		Toast.show_message("%s %s — %s" % [verb, _last_equipped_name, ", ".join(parts)])
	# Consume the trigger info regardless — a hero-switch refresh that follows
	# an equip shouldn't replay the same toast.
	_last_equipped_name = ""
	_last_change_was_unequip = false
	_first_refresh = false


# Phase 49 — single-stat formatter used by both the row update and the
# delta line in toasts. Mirrors the format strings the prior flat-label
# stats panel used so the numbers read identically.
func _format_stat_value(key: String, value: float) -> String:
	match key:
		"damage":
			return "%d" % int(round(value))
		"max_health":
			return "%d" % int(ceil(value))
		"armor":
			return "%d%%" % int(round(value * 100.0))
		"attack_speed":
			return "%.2f/s" % value
		"move_speed":
			return "%d" % int(round(value))
		"xp_gain_mult":
			return "+%d%%" % int(round((value - 1.0) * 100.0))
		_:
			return "%.2f" % value


# Phase 49 — delta-string formatter for toast lines. Signed integer for
# integer stats, signed percentage for armor/xp, signed 2-decimal for
# attack speed. Sign always shown so "+3" vs "-2" reads at a glance.
func _format_stat_delta(key: String, diff: float) -> String:
	match key:
		"damage", "max_health", "move_speed":
			return "%+d" % int(round(diff))
		"armor":
			return "%+d%%" % int(round(diff * 100.0))
		"attack_speed":
			return "%+.2f/s" % diff
		"xp_gain_mult":
			return "%+d%%" % int(round(diff * 100.0))
		_:
			return "%+.2f" % diff


# --- Hover details ---------------------------------------------------------

func _on_item_hovered(inst) -> void:
	if inst == null:
		return
	details_label.text = _format_item_details(inst)


func _on_item_unhovered() -> void:
	# Phase 49 — sticky details panel. Don't reset on unhover; the last-shown
	# item's stats stay visible until the player hovers another item or the
	# screen refreshes. Avoids flicker when the mouse passes over empty cells
	# between two adjacent real items, and matches ARPG convention.
	pass


const _RARITY_NAMES: Array[String] = ["Common", "Magic", "Rare", "Epic", "Legendary"]


func _format_item_details(inst) -> String:
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		return str(inst.base_id)
	var lines: Array[String] = []
	# Header: Name — Rarity Slot
	lines.append("%s" % base.base_name)
	lines.append("%s %s" % [
		_RARITY_NAMES[clampi(int(base.rarity), 0, _RARITY_NAMES.size() - 1)],
		_resolve_slot_label(clampi(int(base.slot), 0, SLOT_COUNT - 1)),
	])
	lines.append("")
	# Implicit abilities (always-on, inherent to the base)
	if base.implicit_abilities.size() > 0:
		lines.append("Implicit:")
		for ab in base.implicit_abilities:
			if ab == null:
				continue
			var impl_line: String = _format_ability_line(ab)
			if impl_line != "":
				lines.append("  " + impl_line)
	# Rolled affixes (unique per instance)
	if inst.rolled_affixes.size() > 0:
		lines.append("Affixes:")
		for roll in inst.rolled_affixes:
			var affix_id: String = String(roll.get("affix_id", ""))
			var value: float = float(roll.get("value", 0.0))
			var affix: Resource = ContentRegistry.find_affix(affix_id)
			if affix != null:
				lines.append("  " + affix.format_display(value))
	# Stat diff preview — "equipping this would change stats X → Y"
	var equipped: Array = InventoryManager.get_all_equipped(_cached_hero_id)
	# Build a swap-hypothetical list: drop whatever's in inst's slot, add inst.
	var hypothetical: Array = []
	var slot: int = int(base.slot)
	for e in equipped:
		if e == null:
			continue
		var e_base: Resource = ContentRegistry.find_item_base(e.base_id)
		if e_base != null and int(e_base.slot) == slot:
			continue   # drop whatever's in the target slot
		hypothetical.append(e)
	# Only preview the swap if inst isn't already equipped in that slot.
	var already_equipped: bool = false
	for e in equipped:
		if e != null and e.uid == inst.uid:
			already_equipped = true
			break
	if not already_equipped:
		hypothetical.append(inst)
		var diff: String = _format_stat_diff(equipped, hypothetical)
		if diff != "":
			lines.append("")
			lines.append("If equipped:")
			lines.append(diff)
	else:
		lines.append("")
		lines.append("(equipped)")
	return "\n".join(lines)


func _format_ability_line(ability: Resource) -> String:
	# Best-effort summary for an AbilityData resource. Inspects the common
	# StatModifierAbility fields + known ability types. Not exhaustive —
	# just enough to read "+3 Damage" / "+15 Max HP" / "+5% Atk Speed".
	var parts: PackedStringArray = []
	_append_if_nonzero(parts, ability, "damage_flat", "+%d Damage")
	_append_if_nonzero_pct(parts, ability, "damage_pct", "+%d%% Damage")
	_append_if_nonzero(parts, ability, "max_health_flat", "+%d Max HP")
	_append_if_nonzero_pct(parts, ability, "max_health_pct", "+%d%% Max HP")
	_append_if_nonzero(parts, ability, "armor_flat", "+%d%% Armor", 100.0)  # armor stored as 0-1 decimal
	_append_if_nonzero_pct(parts, ability, "attack_speed_pct", "+%d%% Atk Speed")
	_append_if_nonzero_pct(parts, ability, "move_speed_pct", "+%d%% Move Speed")
	_append_if_nonzero_pct(parts, ability, "xp_gain_mult_pct", "+%d%% XP Gain")
	_append_if_nonzero(parts, ability, "heal_amount", "+%d HP regen")
	_append_if_nonzero(parts, ability, "bonus_damage", "+%d bonus on hit")
	if parts.is_empty():
		return ""
	return ", ".join(parts)


func _append_if_nonzero(parts: PackedStringArray, ability: Resource, field: String, template: String, factor: float = 1.0) -> void:
	if not (field in ability):
		return
	var v: float = float(ability.get(field))
	if abs(v) < 0.001:
		return
	parts.append(template % int(round(v * factor)))


func _append_if_nonzero_pct(parts: PackedStringArray, ability: Resource, field: String, template: String) -> void:
	if not (field in ability):
		return
	var v: float = float(ability.get(field))
	if abs(v) < 0.001:
		return
	parts.append(template % int(round(v * 100.0)))


func _format_stat_diff(current_eq: Array, new_eq: Array) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(_cached_hero_id)
	if hero_data == null:
		return ""
	var cur: Dictionary = _compute_stats_dict(hero_data, current_eq)
	var after: Dictionary = _compute_stats_dict(hero_data, new_eq)
	var lines: Array[String] = []
	_append_diff_line(lines, "Dmg", int(round(cur.damage)), int(round(after.damage)))
	_append_diff_line(lines, "HP", int(ceil(cur.max_health)), int(ceil(after.max_health)))
	_append_diff_line(lines, "Arm%", int(round(cur.armor * 100.0)), int(round(after.armor * 100.0)))
	return "  " + "   ".join(lines) if not lines.is_empty() else "  (no stat change)"


func _append_diff_line(lines: Array[String], label: String, old_val: int, new_val: int) -> void:
	if old_val == new_val:
		return
	var arrow: String = "↑" if new_val > old_val else "↓"
	lines.append("%s %d%s%d" % [label, old_val, arrow, new_val])


# Shared stat-computation core; _refresh_stats_panel + _format_stat_diff are
# the formatters over this dict.
func _compute_stats_dict(hero_data: Resource, equipped: Array) -> Dictionary:
	var level: int = MetaProgression.get_hero_level(hero_data.hero_id)
	var hp_mult: float = 1.0 + float(level - 1) * _LEVEL_HEALTH_GROWTH
	var dmg_mult: float = 1.0 + float(level - 1) * _LEVEL_DAMAGE_GROWTH
	var base_stats: Dictionary = {
		"max_health": float(hero_data.max_health) * hp_mult,
		"damage": hero_data.attack_damage * dmg_mult * MetaProgression.get_upgrade_multiplier(MetaProgression.MOD_HERO_DAMAGE),
		"armor": hero_data.armor,
		"attack_speed": hero_data.attack_speed,
		"move_speed": hero_data.move_speed,
		"xp_gain_mult": 1.0,
	}
	var mods: Array = []
	for inst in equipped:
		if inst == null:
			continue
		for ab in inst.build_runtime_abilities(ContentRegistry):
			if ab != null:
				mods.append(ab)
	var current: Dictionary = {}
	for key in base_stats.keys():
		var flat_field: String = "%s_flat" % key
		var pct_field: String = "%s_pct" % key
		var v: float = float(base_stats[key])
		var pct_product: float = 1.0
		for m in mods:
			if m == null:
				continue
			if flat_field in m:
				v += float(m.get(flat_field))
			if pct_field in m:
				pct_product *= 1.0 + float(m.get(pct_field))
		current[key] = v * pct_product
	return current
