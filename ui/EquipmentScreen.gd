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

# Phase 52 — uniform one-slot inventory. Display columns are derived
# from the panel width (5–12 cols clamped); every item renders as a
# single 120×120 cell regardless of `ItemBase.grid_width / grid_height`.
# Storage matches: `InventoryManager.add_to_shared` packs every item at
# 1×1, so cap == item count == 50. Vertical scroll handles overflow rows.
const DISPLAY_MIN_COLS: int = 5
const DISPLAY_MAX_COLS: int = 12

# Phase 55 — Diablo-Immortal-style gear cells. Slots are slightly taller
# than wide (5:6 ratio, 120×144) for both the paperdoll and the stash so
# a sword reads as a tall blade instead of a square sticker. Width stays
# at 120 (legacy CELL_PX value) so column counts and ScrollContainer
# layout don't shift; only the y stride changes. Both axes feed into
# ItemIcon via set_pixel_size — _draw scales effects from min(w,h).
const CELL_W: float = 120.0
const CELL_H: float = 144.0

# Phase 55 — stash tabs split items by category. Relics holds trinket-class
# slots (the small-icon side of the Diablo Immortal layout); Gear is "every
# other slot" — phrased as a negation so a future Slot enum value (RING /
# OFFHAND / etc.) automatically lands in Gear instead of being silently
# dropped from both tabs. Items with a corrupt slot index (-1, 99) also
# fall through to Gear so they remain visible.
#
# Storage is unchanged — InventoryManager is still one shared bag; the
# tab is purely a display filter. Keeping it shared means the bag capacity
# (50) applies across both tabs, matching how the player thinks of "my
# stuff" rather than "my gear bag, separately my relic bag".
enum Tab { GEAR, RELICS }
const _RELIC_SLOTS: Array[int] = [5]              # Trinket — extend here when adding new accessory slots

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var hero_label: Label = %HeroLabel
@onready var equipment_grid: Control = %EquipmentGrid
@onready var stats_panel: VBoxContainer = %StatsPanel
@onready var details_label: RichTextLabel = %DetailsLabel
@onready var right_title: Label = %RightTitle
@onready var inventory_grid: Control = %InventoryGrid
@onready var action_row: HBoxContainer = %ActionRow
@onready var equip_button: Button = %EquipButton
@onready var lock_button: Button = %LockButton
@onready var sell_button: Button = %SellButton
@onready var sell_all_button: Button = %SellAllButton
@onready var meta_gold_label: Label = %MetaGoldLabel
# Phase 54 — bottom-sheet details overlay (Diablo Immortal pattern).
@onready var details_overlay: Control = %DetailsOverlay
@onready var dim_backdrop: ColorRect = %DimBackdrop
@onready var details_header: Label = %DetailsHeader
@onready var close_button: Button = %CloseButton
# Phase 55 — Gear / Relics tab bar above the stash grid.
@onready var tab_gear_button: Button = %TabGearButton
@onready var tab_relics_button: Button = %TabRelicsButton

# Rarity → name color for the bottom-sheet header. Mirrors ItemIcon's
# _RARITY_COLORS so a Rare item's name reads gold both on the icon border
# and in the sheet header.
const _RARITY_HEADER_COLORS: Array[Color] = [
	Color(0.85, 0.85, 0.85),   # Common
	Color(0.45, 0.75, 1.0),    # Magic
	Color(1.0, 0.92, 0.4),     # Rare
	Color(0.85, 0.5, 1.0),     # Epic
	Color(1.0, 0.6, 0.15),     # Legendary
]

# Holds the hero_id at the last _refresh call, used by hover to compute diffs.
var _cached_hero_id: String = ""

# Phase 55 — currently active stash tab. Storage is unchanged (one shared
# bag); _current_tab only filters which items render in the inventory grid.
# Selecting an item from one tab and switching tabs auto-clears the
# selection so the action row doesn't dangle on a now-hidden uid.
var _current_tab: int = Tab.GEAR

# Slot index (0-5) → ItemIcon instance
var _slot_icons: Dictionary = {}

# Phase 52 — Tap-to-select state. Tap an inventory item to inspect; details
# panel + action row (Equip / Lock / Sell) act on _selected_uid. Sell button
# is two-tap confirm in-place: first tap arms (button label flips to
# "Sell? +Ng"), second tap commits. Selecting a different item or switching
# hero clears both. Replaces the prior _sell_mode / _pending_sell_uid pair.
var _selected_uid: String = ""
var _sell_armed_uid: String = ""
# uid → ItemIcon control, populated each refresh so selection updates can
# call icon.set_selected() without rebuilding the grid.
var _inventory_icons: Dictionary = {}
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
	# Phase 53 — POWER row leads with DPS (damage × atk_speed, derived) and
	# Health, the two headline numbers most useful for cross-item comparison.
	# Magic Resist surfaced in DEFENSE; rows render but auto-hide when value
	# rounds to 0 AND no equipped item modifies them (see _refresh_stats_panel).
	["POWER",   [["dps", "DPS"], ["max_health", "Health"]]],
	["OFFENSE", [["damage", "Damage"], ["attack_speed", "Atk Speed"]]],
	["DEFENSE", [["armor", "Armor"], ["magic_resist", "Magic Resist"]]],
	["UTILITY", [["move_speed", "Move Speed"], ["xp_gain_mult", "XP Gain"]]],
]
# Stats that should hide when value rounds to 0 AND no equipped item modifies
# them. Avoids showing "Mag Resist 0%" on heroes with no MR (Knight) while
# still keeping the row visible for the Mage (intrinsic 30%) or any hero with
# a Magic Resist affix equipped.
const _HIDE_WHEN_ZERO_KEYS: Array[String] = ["magic_resist"]
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
	# Patches D + F — also reset:
	#   - sticky details panel (otherwise shows hero-A's item while hero B
	#     is active, especially in sell mode where _refresh skips the reset)
	#   - sell-mode + pending sell uid (avoid persisting destructive mode
	#     across heroes silently)
	EventBus.hero_selected.connect(func(new_id):
		_first_refresh = true
		_last_stats_dict.clear()
		details_label.text = _DEFAULT_DETAILS_HINT
		# Phase 52 — clear any selection / sell-arm carrying over from the
		# previous hero (their item is invisible on the new paperdoll, so the
		# action row would dangle on a stale uid).
		_selected_uid = ""
		_sell_armed_uid = ""
		_sell_all_armed = false
		# Phase 54 — also hide the details overlay if it's open.
		if details_overlay != null:
			details_overlay.visible = false
		if new_id != "":
			InventoryManager.ensure_starter_gear(new_id)
		_build_slots()
		_refresh()
	)
	# Phase 52 — selected-item action row + batch sell + meta-gold live update.
	equip_button.pressed.connect(_on_equip_pressed)
	lock_button.pressed.connect(_on_lock_pressed)
	sell_button.pressed.connect(_on_sell_pressed)
	sell_all_button.pressed.connect(_on_sell_all_pressed)
	# Phase 55 — Gear / Relics tab bar. The first _refresh() at the bottom
	# of _ready will call _refresh_tab_buttons; no extra call needed here.
	tab_gear_button.pressed.connect(_on_tab_pressed.bind(Tab.GEAR))
	tab_relics_button.pressed.connect(_on_tab_pressed.bind(Tab.RELICS))
	# Phase 54 — bottom-sheet dismiss paths. DimBackdrop catches taps outside
	# the sheet; CloseButton is the explicit dismiss control.
	dim_backdrop.gui_input.connect(_on_dim_backdrop_input)
	close_button.pressed.connect(_dismiss_details)
	EventBus.meta_gold_changed.connect(_on_meta_gold_changed)
	# Phase 50 — re-flow inventory when the ScrollContainer resizes. Fires
	# once the initial layout pass settles (replacing the placeholder 5-col
	# layout from _ready when sizes were still 0), and again on any window
	# resize / parent layout change (e.g. RosterRail toggling visibility in
	# the embedded HeroesHub flow).
	var sc: Control = inventory_grid.get_parent() as Control
	if sc != null:
		sc.resized.connect(_refresh)
	_refresh_meta_gold_label()
	_refresh_action_row()
	_refresh_sell_all_button()
	_refresh()


# Default text shown by DetailsLabel when nothing is selected. Stored as
# a const so the multiple reset paths (refresh, hero swap, post-action)
# all use the same string.
const _DEFAULT_DETAILS_HINT: String = "Tap an item to inspect."


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
	# Phase 52 — selected uid may have just been sold/unequipped; if so,
	# clear it so the action row doesn't dangle on a missing instance.
	# Phase 54 — also hide the overlay in that case so the bottom-sheet
	# isn't left showing a ghost item.
	if _selected_uid != "" and InventoryManager.find_by_uid(_selected_uid) == null:
		_selected_uid = ""
		_sell_armed_uid = ""
		if details_overlay != null:
			details_overlay.visible = false
	_refresh()
	_refresh_action_row()
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
	icon.set_pixel_size(Vector2(CELL_W, CELL_H))
	# Position via the Paperdoll's anchor_for_slot. Anchor is the slot's
	# centerpoint, so subtract half the icon's footprint to top-left it.
	var anchor: Vector2 = equipment_grid.anchor_for_slot(slot_idx) if equipment_grid.has_method("anchor_for_slot") else Vector2.ZERO
	var half := Vector2(CELL_W * 0.5, CELL_H * 0.5)
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
	# Phase 52 — preserve details panel when an item is selected; otherwise
	# reset to the default hint. Selection survives refreshes (lock toggle,
	# inventory_changed, etc.); the action row reflects the same uid.
	if _selected_uid != "" and InventoryManager.find_by_uid(_selected_uid) != null:
		_render_details_for(_selected_uid)
	else:
		details_label.text = _DEFAULT_DETAILS_HINT
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
	# Right: inventory grid — only UNEQUIPPED items. Phase 50 responsive
	# Phase 52 — uniform one-slot inventory. Every inventory icon renders as
	# 1×1 regardless of `ItemBase.grid_width / grid_height` (those stay as
	# authored data — preserved for future flair). Layout is index-based
	# row/col; capacity reads as item count, not occupied cells. Save format
	# unchanged — `InventoryManager` storage internals still drive add/equip.
	for child in inventory_grid.get_children():
		child.queue_free()
	_inventory_icons.clear()
	# Phase 55 — filter the unequipped bag by the active tab. Storage is
	# unchanged (single shared bag); Gear holds the 5 main equipment slots,
	# Relics holds the trinket slot. Total bag-cap header reflects ALL
	# items so the player sees overall fullness regardless of which tab
	# they're viewing.
	var inv_all: Array = InventoryManager.get_unequipped()
	var inv: Array = _filter_inventory_by_tab(inv_all, _current_tab)
	var display_cols: int = _compute_display_cols()
	# Phase 55 — empty backdrop reflects ACTUAL remaining bag capacity rather
	# than always drawing 50 cells. Storage is shared across tabs, so showing
	# 49 empty cells in the Relics tab when only 1 trinket fits would lie
	# about how many more relics the player can carry. Visible cells per tab =
	# items in this tab + remaining shared bag space.
	var bag_cap: int = InventoryManager.GRID_ROWS * InventoryManager.GRID_COLS
	var bag_free: int = maxi(0, bag_cap - inv_all.size())
	var visible_cells: int = clampi(inv.size() + bag_free, 0, bag_cap)
	var display_rows: int = maxi(1, int(ceil(float(visible_cells) / float(display_cols))))
	inventory_grid.custom_minimum_size = Vector2(
		float(display_cols) * CELL_W,
		float(display_rows) * CELL_H,
	)
	# Header — items in this tab + total bag fullness across both tabs.
	var tab_name: String = "Gear" if _current_tab == Tab.GEAR else "Relics"
	right_title.text = "%s (%d) — Bag %d / %d" % [tab_name, inv.size(), inv_all.size(), bag_cap]
	right_title.modulate = Color.WHITE
	_refresh_tab_buttons()
	# Empty-cell backdrop. Cells past `visible_cells` aren't drawn so the grid
	# truthfully shows "items in this tab + free bag space." mouse_filter=IGNORE
	# so placeholders don't catch hover/click between real items.
	for r in display_rows:
		var stop_row: bool = false
		for c in display_cols:
			if r * display_cols + c >= visible_cells:
				stop_row = true
				break
			var empty_icon: Control = _ItemIconScript.new()
			empty_icon.set_pixel_size(Vector2(CELL_W, CELL_H))
			empty_icon.setup_empty()
			empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_icon.position = Vector2(c * CELL_W, r * CELL_H)
			inventory_grid.add_child(empty_icon)
		if stop_row:
			break
	# Item tiles in row-major index order.
	for i in inv.size():
		var inst = inv[i]
		if inst == null:
			continue
		var col: int = i % display_cols
		@warning_ignore("integer_division")
		var row: int = i / display_cols
		var icon: Control = _ItemIconScript.new()
		icon.set_pixel_size(Vector2(CELL_W, CELL_H))
		icon.setup_instance(inst)
		icon.position = Vector2(col * CELL_W, row * CELL_H)
		icon.pressed.connect(_on_inventory_item_pressed)
		icon.hovered.connect(_on_item_hovered)
		icon.unhovered.connect(_on_item_unhovered)
		# Long-press shows details on touch (read-without-acting path).
		icon.long_pressed.connect(_on_item_hovered)
		icon.set_selected(_selected_uid == inst.uid)
		icon.set_armed(_sell_armed_uid == inst.uid)
		inventory_grid.add_child(icon)
		_inventory_icons[inst.uid] = icon


# Phase 50 — Display column count derived from ScrollContainer width. At
# _ready time the parent layout hasn't settled yet, so falls back to the
# minimum (5 cols). Connecting to the ScrollContainer's resized signal in
# _ready triggers a re-refresh once the layout pass completes, replacing
# the placeholder layout with the correct one.
func _compute_display_cols() -> int:
	if inventory_grid == null:
		return DISPLAY_MIN_COLS
	var avail: float = 0.0
	var sc: Control = inventory_grid.get_parent() as Control
	if sc != null:
		avail = sc.size.x
	if avail <= 0.0:
		# Fallback: one CELL_W wider than min so minimum reads sensibly.
		avail = float(DISPLAY_MIN_COLS) * CELL_W
	var n: int = int(avail / CELL_W)
	return clampi(n, DISPLAY_MIN_COLS, DISPLAY_MAX_COLS)


# --- Phase 55: tab filter / state -------------------------------------------
# Phrased as "Relics is the explicit list, Gear is everything else." Stranded
# items (null base, corrupt slot index, future slot values not yet known to
# the tab system) fall through to Gear so they're never invisible-but-stored.
func _is_relic_slot(slot: int) -> bool:
	return slot in _RELIC_SLOTS


func _instance_belongs_to_tab(inst, tab: int) -> bool:
	if inst == null:
		return false
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	var slot: int = -1 if base == null else int(base.slot)
	var is_relic: bool = _is_relic_slot(slot)
	# RELICS tab claims relic slots; GEAR claims everything else (including
	# stranded items with slot=-1 or unknown enum values).
	return is_relic if tab == Tab.RELICS else not is_relic


func _filter_inventory_by_tab(inv: Array, tab: int) -> Array:
	var out: Array = []
	for inst in inv:
		if _instance_belongs_to_tab(inst, tab):
			out.append(inst)
	return out


func _on_tab_pressed(tab: int) -> void:
	if tab == _current_tab:
		return
	# Switching tabs hides the previously selected item if it's in the other
	# tab — clear selection so the action row doesn't dangle on a now-hidden
	# uid. Sell-arm and the bottom-sheet share the fate.
	_current_tab = tab
	if _selected_uid != "":
		var inst = InventoryManager.find_by_uid(_selected_uid)
		if inst != null and not _instance_belongs_to_tab(inst, tab):
			_dismiss_details()
	_refresh()
	# Reset the stash scroll to top so a tab with few items doesn't render
	# below the viewport (e.g. Gear scrolled down → Relics with 1 trinket
	# would otherwise leave the trinket above the viewport).
	var sc: ScrollContainer = inventory_grid.get_parent() as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 0


# Visual state for the two tab buttons. Active tab uses Godot's built-in
# disabled state so it reads as "pressed in" — clearly stronger than a
# brightness swap. Disabled also prevents redundant taps. Inactive tab
# stays interactive.
func _refresh_tab_buttons() -> void:
	if tab_gear_button == null or tab_relics_button == null:
		return
	tab_gear_button.disabled = _current_tab == Tab.GEAR
	tab_relics_button.disabled = _current_tab == Tab.RELICS


# --- Interaction ------------------------------------------------------------
# Tap-to-select model: tap an inventory item → select. Action row (Equip /
# Lock / Sell) operates on the selected uid. Tap an equipped slot →
# unequip (slot goes empty, item stays in inventory).

func _on_inventory_item_pressed(inst) -> void:
	if inst == null:
		return
	_select_item(inst.uid)


func _hero_name(hero_id: String) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	return String(hero_data.hero_name) if hero_data != null and "hero_name" in hero_data else hero_id


# --- Phase 52: tap-to-select + action row ------------------------------------
# Tap an inventory item → _select_item(uid). Selected uid drives the
# DetailsLabel content + the action row buttons (Equip / Lock / Sell).
# Sell is two-tap confirm in-place: first press arms, second press commits.
# Selecting a different item, switching hero, or any inventory mutation
# clears the sell-armed state (defensive: never sell an item the player
# wasn't actively confirming).

func _select_item(uid: String) -> void:
	if uid == _selected_uid:
		# Tap on already-selected item: no-op (we explicitly chose strict
		# tap-to-select; Equip button is the only commit path).
		return
	# Tapping a different item disarms any pending sell on the previous one.
	if _sell_armed_uid != "":
		_set_icon_armed(_sell_armed_uid, false)
		_sell_armed_uid = ""
	# Update selection state on the icon controls.
	if _selected_uid != "" and _inventory_icons.has(_selected_uid):
		var prev = _inventory_icons[_selected_uid]
		if prev != null and prev.has_method("set_selected"):
			prev.set_selected(false)
	_selected_uid = uid
	if uid != "" and _inventory_icons.has(uid):
		var cur = _inventory_icons[uid]
		if cur != null:
			if cur.has_method("set_selected"):
				cur.set_selected(true)
			if cur.has_method("set_armed"):
				cur.set_armed(false)
	_render_details_for(uid)
	_refresh_action_row()
	# Phase 54 — bring up the bottom-sheet whenever a real item is selected.
	if uid != "":
		_show_details_overlay(uid)


func _render_details_for(uid: String) -> void:
	if uid == "":
		details_label.text = _DEFAULT_DETAILS_HINT
		return
	var inst = InventoryManager.find_by_uid(uid)
	if inst == null:
		details_label.text = _DEFAULT_DETAILS_HINT
		return
	# _format_item_details already produces the comparison block (name +
	# rarity + slot + implicit + rolled affixes + stat diff vs equipped) —
	# repurpose wholesale as the selection-detail body.
	_on_item_hovered(inst)


# Phase 54 — bottom-sheet plumbing. Show updates the rarity-colored header
# label, makes the overlay visible (script-only — no animation in first pass).
# Dismiss clears _selected_uid + sell-arm and hides the overlay.
func _show_details_overlay(uid: String) -> void:
	if details_overlay == null:
		return
	var inst = InventoryManager.find_by_uid(uid)
	if inst == null:
		return
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	var name_str: String = String(base.base_name) if base != null else String(inst.base_id)
	var rarity_idx: int = clampi(int(base.rarity), 0, _RARITY_HEADER_COLORS.size() - 1) if base != null else 0
	details_header.text = name_str.to_upper()
	details_header.add_theme_color_override("font_color", _RARITY_HEADER_COLORS[rarity_idx])
	details_overlay.visible = true


func _dismiss_details() -> void:
	# Clear selection state on the icon currently selected (if any), reset
	# sell-arm, hide the overlay, refresh the action row to disabled state.
	if _selected_uid != "":
		if _inventory_icons.has(_selected_uid):
			var prev = _inventory_icons[_selected_uid]
			if prev != null and prev.has_method("set_selected"):
				prev.set_selected(false)
	if _sell_armed_uid != "":
		_set_icon_armed(_sell_armed_uid, false)
	_selected_uid = ""
	_sell_armed_uid = ""
	if details_overlay != null:
		details_overlay.visible = false
	details_label.text = _DEFAULT_DETAILS_HINT
	_refresh_action_row()


func _on_dim_backdrop_input(event: InputEvent) -> void:
	# Tap on the dim backdrop area (outside the sheet itself) → dismiss.
	# Touch and mouse both arrive here through gui_input.
	var is_press: bool = false
	if event is InputEventMouseButton:
		is_press = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		is_press = event.pressed
	if is_press:
		_dismiss_details()
		accept_event()


func _refresh_action_row() -> void:
	# Disabled state when nothing selected.
	if _selected_uid == "":
		equip_button.disabled = true
		equip_button.text = "Equip"
		lock_button.disabled = true
		lock_button.text = "🔒 Lock"
		sell_button.disabled = true
		sell_button.text = "Sell"
		sell_button.modulate = Color.WHITE
		return
	var inst = InventoryManager.find_by_uid(_selected_uid)
	if inst == null:
		# Stale uid; clear and re-enter disabled state.
		_selected_uid = ""
		_sell_armed_uid = ""
		_refresh_action_row()
		return
	var hero_id: String = LoadoutState.selected_hero_id
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	var slot: int = int(base.slot) if base != null else -1
	# Phase 55h — branch on whether the selected item is currently equipped on
	# the active hero. If so, the primary button reads "Unequip" and Sell is
	# disabled (player must unequip first to sell — clearer than auto-unequip-
	# then-sell). Tapping an equipped paperdoll slot now opens this sheet
	# instead of the prior destructive instant-unequip.
	var is_equipped_on_active: bool = (
		slot >= 0 and InventoryManager.get_equipped_uid(hero_id, slot) == _selected_uid
	)
	# Equip / Unequip button.
	if is_equipped_on_active:
		equip_button.disabled = false
		equip_button.text = "Unequip"
	else:
		# Slot-availability check — hero may not expose this slot at all.
		var slot_ok: bool = base != null and (slot in _active_slot_indices_for(hero_id))
		equip_button.disabled = not slot_ok
		if slot_ok and InventoryManager.get_equipped_uid(hero_id, slot) != "":
			equip_button.text = "Replace"
		else:
			equip_button.text = "Equip"
	# Lock button — flips label to reflect the next tap's effect. Lock works on
	# equipped items too (locks against accidental sale once unequipped).
	lock_button.disabled = false
	var is_locked: bool = "locked" in inst and inst.locked
	lock_button.text = "🔓 Unlock" if is_locked else "🔒 Lock"
	# Sell button — disabled while equipped (player must unequip first). For
	# unequipped items the existing two-tap-confirm + locked-refusal flow
	# applies. Armed state still shows the confirm prompt with refund value.
	if is_equipped_on_active:
		sell_button.disabled = true
		sell_button.text = "Sell"
		sell_button.modulate = Color.WHITE
	else:
		var price: int = InventoryManager.get_sell_price(_selected_uid)
		sell_button.disabled = price <= 0
		if _sell_armed_uid == _selected_uid:
			sell_button.text = "Sell? +%dg" % price
			sell_button.modulate = Color(1.0, 0.7, 0.4, 1.0)
		else:
			sell_button.text = "Sell"
			sell_button.modulate = Color.WHITE


func _on_equip_pressed() -> void:
	if _selected_uid == "":
		return
	var inst = InventoryManager.find_by_uid(_selected_uid)
	if inst == null:
		return
	var hero_id: String = LoadoutState.selected_hero_id
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		return
	var slot: int = int(base.slot)
	# Phase 55h — if the selected item is currently equipped on this hero,
	# the button is "Unequip" and we route to InventoryManager.unequip.
	# Capture uid first since _dismiss_details clears it.
	if InventoryManager.get_equipped_uid(hero_id, slot) == _selected_uid:
		_dismiss_details()
		InventoryManager.unequip(hero_id, slot)
		return
	if not (slot in _active_slot_indices_for(hero_id)):
		Toast.show_message("%s has no %s slot" % [_hero_name(hero_id), _resolve_slot_label(slot)])
		return
	# Phase 55 polish — dismiss the bottom-sheet BEFORE equipping. Otherwise
	# the inventory_changed signal that equip() emits triggers a refresh that
	# briefly re-renders the sheet showing the now-equipped item before the
	# dismiss runs.
	var uid_to_equip: String = _selected_uid
	_dismiss_details()
	InventoryManager.equip(hero_id, uid_to_equip)


func _on_lock_pressed() -> void:
	if _selected_uid == "":
		return
	var now_locked: bool = InventoryManager.toggle_lock(_selected_uid)
	# Toggling lock should not also disarm sell — keep the selection so the
	# player can still hit Sell after unlocking. _refresh_action_row picks
	# up the new lock label via inventory_changed.
	Toast.show_message("Locked from sale" if now_locked else "Unlocked")


func _on_sell_pressed() -> void:
	if _selected_uid == "":
		return
	var inst = InventoryManager.find_by_uid(_selected_uid)
	if inst == null:
		return
	if "locked" in inst and inst.locked:
		Toast.show_message("Locked — tap 🔓 Unlock to allow sale")
		return
	var price: int = InventoryManager.get_sell_price(_selected_uid)
	if price <= 0:
		Toast.show_message("This item can't be sold")
		return
	if _sell_armed_uid != _selected_uid:
		# First press — arm. Auto-disarm after 3 s if the player walks away.
		_sell_armed_uid = _selected_uid
		_set_icon_armed(_sell_armed_uid, true)
		_refresh_action_row()
		var armed_uid: String = _selected_uid
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(self) and _sell_armed_uid == armed_uid:
				_set_icon_armed(_sell_armed_uid, false)
				_sell_armed_uid = ""
				_refresh_action_row()
		)
		return
	# Second press — commit. inventory_changed clears _selected_uid via
	# _on_inventory_changed_simple (the sold instance is now find_by_uid==null).
	var awarded: int = InventoryManager.sell(_selected_uid)
	# Phase 54 — auto-dismiss the sheet after a successful sell.
	_dismiss_details()
	if awarded > 0:
		Toast.show_message("Sold for %dg" % awarded)


# Phase 52 — flip an inventory icon's _armed state without rebuilding the
# whole grid. Used by the Sell button two-tap confirm flow.
func _set_icon_armed(uid: String, on: bool) -> void:
	if uid == "" or not _inventory_icons.has(uid):
		return
	var icon = _inventory_icons[uid]
	if icon != null and icon.has_method("set_armed"):
		icon.set_armed(on)


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
	# Phase 55h — tap-to-inspect, not tap-to-unequip. Empty slots toast as
	# before; filled slots open the same bottom-sheet inventory items use,
	# with the action row's primary button now reading "Unequip" (handled in
	# _refresh_action_row + _on_equip_pressed). Replaces the prior destructive
	# instant-unequip-on-tap which was unsafe on mobile.
	var hero_id: String = LoadoutState.selected_hero_id
	var current_uid: String = InventoryManager.get_equipped_uid(hero_id, slot_idx)
	if current_uid == "":
		Toast.show_message("%s slot is empty" % _resolve_slot_label(slot_idx))
		return
	_select_item(current_uid)


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
			# Phase 53 — hide rows in _HIDE_WHEN_ZERO_KEYS when value rounds to 0.
			# Avoids "Mag Resist 0%" noise on heroes with no MR; the row reappears
			# the moment a hero or item brings the value above zero.
			if key in _HIDE_WHEN_ZERO_KEYS and absf(new_val) < 0.005:
				row.visible = false
				continue
			row.visible = true
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
		"dps":
			return "%.1f" % value
		"max_health":
			return "%d" % int(ceil(value))
		"armor":
			return "%d%%" % int(round(value * 100.0))
		"magic_resist":
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
		"dps":
			return "%+.1f" % diff
		"armor":
			return "%+d%%" % int(round(diff * 100.0))
		"magic_resist":
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
	# Phase 54 — name + rarity color now live in the bottom-sheet's
	# DetailsHeader Label (set by _show_details_overlay). The body still
	# emits the "Rare Trinket" subline so the player sees rarity + slot
	# type without forcing them to read the colored title twice.
	lines.append("[color=#9aa9c8]%s %s[/color]" % [
		_RARITY_NAMES[clampi(int(base.rarity), 0, _RARITY_NAMES.size() - 1)],
		_resolve_slot_label(clampi(int(base.slot), 0, SLOT_COUNT - 1)),
	])
	lines.append("")
	# Implicit abilities (always-on, inherent to the base). Gather body
	# lines first; only emit the header if at least one non-empty body line
	# exists — otherwise an item whose abilities all _format_ability_line to
	# empty would leave a dangling "Implicit:" header with nothing under it.
	var implicit_lines: Array[String] = []
	for ab in base.implicit_abilities:
		if ab == null:
			continue
		var impl_line: String = _format_ability_line(ab)
		if impl_line != "":
			implicit_lines.append("  " + impl_line)
	if implicit_lines.size() > 0:
		lines.append("Implicit:")
		lines.append_array(implicit_lines)
	# Rolled affixes (unique per instance) — same defensive header guard.
	var affix_lines: Array[String] = []
	for roll in inst.rolled_affixes:
		var affix_id: String = String(roll.get("affix_id", ""))
		var value: float = float(roll.get("value", 0.0))
		var affix: Resource = ContentRegistry.find_affix(affix_id)
		if affix != null:
			affix_lines.append("  " + affix.format_display(value))
	if affix_lines.size() > 0:
		lines.append("Affixes:")
		lines.append_array(affix_lines)
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
			lines.append("[color=#9aa9c8]EQUIP PREVIEW[/color]")
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


# Phase 54 — equip preview iterates the FULL _STATS_LAYOUT so DPS, Magic
# Resist, Move Speed, XP Gain etc. all surface in the comparison whenever
# an item changes them. Lines are BBCode-colored: green for gains, red for
# losses. Only changed stats emit; unchanged ones are skipped so the panel
# stays compact. The DetailsLabel is a RichTextLabel with bbcode_enabled.
const _DIFF_GAIN_COLOR: String = "#7fff7f"
const _DIFF_LOSS_COLOR: String = "#ff7f7f"


func _format_stat_diff(current_eq: Array, new_eq: Array) -> String:
	var hero_data: Resource = ContentRegistry.find_hero(_cached_hero_id)
	if hero_data == null:
		return ""
	var cur: Dictionary = _compute_stats_dict(hero_data, current_eq)
	var after: Dictionary = _compute_stats_dict(hero_data, new_eq)
	var lines: Array[String] = []
	for section_entry in _STATS_LAYOUT:
		for row_entry in section_entry[1]:
			var key: String = row_entry[0]
			var display: String = row_entry[1]
			var old_v: float = float(cur.get(key, 0.0))
			var new_v: float = float(after.get(key, 0.0))
			var diff: float = new_v - old_v
			if absf(diff) < 0.0005:
				continue
			var arrow: String = "▲" if diff > 0.0 else "▼"
			var color: String = _DIFF_GAIN_COLOR if diff > 0.0 else _DIFF_LOSS_COLOR
			lines.append("[color=%s]%s %s   %s → %s   (%s)[/color]" % [
				color,
				arrow,
				display,
				_format_stat_value(key, old_v),
				_format_stat_value(key, new_v),
				_format_stat_delta(key, diff),
			])
	if lines.is_empty():
		return "(no stat change)"
	return "\n".join(lines)


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
		"magic_resist": float(hero_data.magic_resist) if "magic_resist" in hero_data else 0.0,
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
	# Phase 53 — derived DPS for the POWER section. Computed AFTER mod resolution
	# so flat/pct on damage and attack_speed both feed in.
	current["dps"] = float(current.get("damage", 0.0)) * float(current.get("attack_speed", 0.0))
	return current
