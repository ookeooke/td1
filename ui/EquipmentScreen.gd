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

@onready var back_button: Button = %BackButton
@onready var title_label: Label = %TitleLabel
@onready var hero_label: Label = %HeroLabel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var right_title: Label = %RightTitle
@onready var inventory_grid: HFlowContainer = %InventoryGrid
@onready var hint_label: Label = %HintLabel

# Slot index (0-5) → ItemIcon instance
var _slot_icons: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build_slots()
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
		_slot_icons[slot_idx] = icon
		container.add_child(label)
		container.add_child(icon)
		slot_grid.add_child(container)


func _refresh() -> void:
	var hero_id: String = GameState.selected_hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	hero_label.text = hero_data.hero_name if hero_data != null else hero_id
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
		inventory_grid.add_child(icon)
	if inv.is_empty():
		var empty: Label = Label.new()
		empty.text = "No items yet. Kill enemies in levels to collect loot."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
		inventory_grid.add_child(empty)
