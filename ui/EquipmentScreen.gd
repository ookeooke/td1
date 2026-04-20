extends Control

# Phase 48 D2 — Equipment screen. Shows the selected hero's 6 slots
# (3 active: Weapon/Armor/Trinket; 3 locked: Helm/Gloves/Boots) on the
# left, and the full owned-item inventory on the right.
#
# D2 = read-only: clicking items does nothing. D3 adds the equip/unequip
# two-step-commit interaction.
#
# Reached from WorldMap via an "Equipment" button (wired in D4).

const _ItemIconScript := preload("res://ui/ItemIcon.gd")
const SLOT_COUNT: int = 6
const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Helm", "Gloves", "Boots", "Trinket"]
# Grid order — W/A/T on top row, locked H/G/B on bottom.
const SLOT_ORDER: Array[int] = [0, 1, 5, 2, 3, 4]
# Slots the player can equip into today. Others render locked until Phase F
# activates them.
const ACTIVE_SLOTS: Array[int] = [0, 1, 5]

# Inventory is always padded to at least this many cells so the grid feels
# like a proper inventory with headroom (empty tiles = free space).
# Auto-grows in steps of one row beyond MIN so 40+ items still look clean.
const MIN_INVENTORY_CELLS: int = 40
const INVENTORY_ROW_STEP: int = 8

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var hero_label: Label = %HeroLabel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var stats_label: Label = %StatsLabel
@onready var right_title: Label = %RightTitle
@onready var inventory_grid: HFlowContainer = %InventoryGrid
@onready var hint_label: Label = %HintLabel

# Slot index (0-5) → ItemIcon instance
var _slot_icons: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	EventBus.item_equipped.connect(_on_inventory_changed)
	EventBus.item_unequipped.connect(_on_inventory_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed_simple)
	_build_slots()
	_refresh()


func _on_inventory_changed(_hero_id, _slot, _instance) -> void:
	_refresh()


func _on_inventory_changed_simple() -> void:
	_refresh()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _build_slots() -> void:
	for slot_idx in SLOT_ORDER:
		var container: VBoxContainer = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var label: Label = Label.new()
		label.text = SLOT_NAMES[slot_idx]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		var icon: Control = _ItemIconScript.new()
		icon.pressed.connect(_on_slot_pressed.bind(slot_idx))
		_slot_icons[slot_idx] = icon
		container.add_child(label)
		container.add_child(icon)
		slot_grid.add_child(container)


func _refresh() -> void:
	var hero_id: String = GameState.selected_hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var level: int = GameState.get_hero_level(hero_id)
	hero_label.text = "%s — Lv %d" % [hero_data.hero_name, level] if hero_data != null else hero_id
	# Stats panel — mirrors BaseHero.recompute_stats formulas so the numbers
	# shown here match what the hero will have on next spawn.
	stats_label.text = _compute_stats_text(hero_data, InventoryManager.get_all_equipped(hero_id))
	# Left: slot state
	for slot_idx in SLOT_ORDER:
		var icon: Control = _slot_icons[slot_idx]
		if not ACTIVE_SLOTS.has(slot_idx):
			icon.setup_locked()
			continue
		var inst = InventoryManager.get_equipped_instance(hero_id, slot_idx)
		if inst == null:
			icon.setup_empty()
		else:
			icon.setup_instance(inst)
	# Right: inventory grid — show every owned instance, including starter gear.
	for child in inventory_grid.get_children():
		child.queue_free()
	var inv: Array = InventoryManager.get_inventory(hero_id)
	right_title.text = "Inventory (%d)" % inv.size()
	for inst in inv:
		if inst == null:
			continue
		var icon: Control = _ItemIconScript.new()
		icon.setup_instance(inst)
		icon.pressed.connect(_on_inventory_item_pressed)
		inventory_grid.add_child(icon)
	# Phase polish — always pad beyond current inventory so the grid shows
	# headroom. At minimum MIN_INVENTORY_CELLS; if the player has more than
	# that, grow in row steps AND always leave at least one empty row so it
	# never looks "exactly full".
	var target_cells: int = MIN_INVENTORY_CELLS
	if inv.size() >= target_cells:
		target_cells = inv.size() + INVENTORY_ROW_STEP
	for _i in (target_cells - inv.size()):
		var empty_icon: Control = _ItemIconScript.new()
		empty_icon.setup_empty()
		inventory_grid.add_child(empty_icon)


# --- Interaction (D3) -------------------------------------------------------
# Direct-tap model: tap an inventory item → equip into its slot (swaps out
# anything currently there; the swapped-out item stays in inventory). Tap
# an equipped slot → unequip (slot goes empty, item still owned). Tapping a
# locked slot toasts "Slot locked".

func _on_inventory_item_pressed(inst) -> void:
	if inst == null:
		return
	var hero_id: String = GameState.selected_hero_id
	var base: Resource = ContentRegistry.find_item_base(inst.base_id)
	if base == null:
		return
	var slot: int = int(base.slot)
	if not ACTIVE_SLOTS.has(slot):
		Toast.show_message("%s slot is locked" % SLOT_NAMES[slot])
		return
	InventoryManager.equip(hero_id, inst.uid)


func _on_slot_pressed(_signal_arg, slot_idx: int) -> void:
	if not ACTIVE_SLOTS.has(slot_idx):
		Toast.show_message("%s slot is locked" % SLOT_NAMES[slot_idx])
		return
	var hero_id: String = GameState.selected_hero_id
	var current_uid: String = InventoryManager.get_equipped_uid(hero_id, slot_idx)
	if current_uid == "":
		Toast.show_message("Slot is empty")
		return
	InventoryManager.unequip(hero_id, slot_idx)


# --- Stats panel (D4) -------------------------------------------------------
# Mirrors BaseHero.recompute_stats so what's displayed here is what the hero
# will actually have on spawn. Duplicated formulas are acceptable — the two
# consumers (runtime hero, offline preview) have different lifecycles and
# coupling them would tangle presentation logic with simulation logic.

const _LEVEL_HEALTH_GROWTH: float = 0.15   # must match BaseHero
const _LEVEL_DAMAGE_GROWTH: float = 0.10   # must match BaseHero


func _compute_stats_text(hero_data: Resource, equipped: Array) -> String:
	if hero_data == null:
		return ""
	var level: int = GameState.get_hero_level(hero_data.hero_id)
	var hp_mult: float = 1.0 + float(level - 1) * _LEVEL_HEALTH_GROWTH
	var dmg_mult: float = 1.0 + float(level - 1) * _LEVEL_DAMAGE_GROWTH
	var base_stats: Dictionary = {
		"max_health": float(hero_data.max_health) * hp_mult,
		"damage": hero_data.attack_damage * dmg_mult * GameState.get_upgrade_multiplier(GameState.MOD_HERO_DAMAGE),
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
	# Format — aligned columns, fixed-width labels.
	var lines: Array[String] = []
	lines.append("Damage      %d" % int(round(current.damage)))
	lines.append("Max HP      %d" % int(ceil(current.max_health)))
	lines.append("Armor       %d%%" % int(round(current.armor * 100.0)))
	lines.append("Atk Speed   %.2f/s" % current.attack_speed)
	lines.append("Move Speed  %d" % int(round(current.move_speed)))
	lines.append("XP Gain     +%d%%" % int(round((current.xp_gain_mult - 1.0) * 100.0)))
	return "\n".join(lines)
