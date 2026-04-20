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
@onready var details_label: Label = %DetailsLabel
@onready var right_title: Label = %RightTitle
@onready var inventory_grid: HFlowContainer = %InventoryGrid
@onready var hint_label: Label = %HintLabel

# Holds the hero_id at the last _refresh call, used by hover to compute diffs.
var _cached_hero_id: String = ""

# Slot index (0-5) → ItemIcon instance
var _slot_icons: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	# Ensure starter gear is granted + equipped for the currently selected
	# hero even if the player hasn't entered a level yet. Idempotent via
	# starter_gear_granted bookkeeping. MUST happen BEFORE we build slots
	# and connect inventory signals — ensure_starter_gear emits
	# inventory_changed, which would otherwise hit _refresh with an empty
	# _slot_icons dict.
	var hero_id: String = GameState.selected_hero_id
	if hero_id != "":
		InventoryManager.ensure_starter_gear(hero_id)
	_build_slots()
	EventBus.item_equipped.connect(_on_inventory_changed)
	EventBus.item_unequipped.connect(_on_inventory_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed_simple)
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
		icon.hovered.connect(_on_item_hovered)
		icon.unhovered.connect(_on_item_unhovered)
		_slot_icons[slot_idx] = icon
		container.add_child(label)
		container.add_child(icon)
		slot_grid.add_child(container)


func _refresh() -> void:
	var hero_id: String = GameState.selected_hero_id
	_cached_hero_id = hero_id
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	var level: int = GameState.get_hero_level(hero_id)
	hero_label.text = "%s — Lv %d" % [hero_data.hero_name, level] if hero_data != null else hero_id
	# Stats panel — mirrors BaseHero.recompute_stats formulas so the numbers
	# shown here match what the hero will have on next spawn.
	stats_label.text = _compute_stats_text(hero_data, InventoryManager.get_all_equipped(hero_id))
	# Clear details on any refresh; hover repopulates.
	details_label.text = "Hover an item to see its details."
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
	# Right: inventory grid — only UNEQUIPPED items (equipped render on the
	# left only, matches ARPG convention). Count shown is unequipped count;
	# the player sees at a glance how much bag-space is used.
	for child in inventory_grid.get_children():
		child.queue_free()
	var inv: Array = InventoryManager.get_unequipped(hero_id)
	right_title.text = "Inventory (%d)" % inv.size()
	for inst in inv:
		if inst == null:
			continue
		var icon: Control = _ItemIconScript.new()
		icon.setup_instance(inst)
		icon.pressed.connect(_on_inventory_item_pressed)
		icon.hovered.connect(_on_item_hovered)
		icon.unhovered.connect(_on_item_unhovered)
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
	var current: Dictionary = _compute_stats_dict(hero_data, equipped)
	# Format — aligned columns, fixed-width labels.
	var lines: Array[String] = []
	lines.append("Damage      %d" % int(round(current.damage)))
	lines.append("Max HP      %d" % int(ceil(current.max_health)))
	lines.append("Armor       %d%%" % int(round(current.armor * 100.0)))
	lines.append("Atk Speed   %.2f/s" % current.attack_speed)
	lines.append("Move Speed  %d" % int(round(current.move_speed)))
	lines.append("XP Gain     +%d%%" % int(round((current.xp_gain_mult - 1.0) * 100.0)))
	return "\n".join(lines)


# --- Hover details ---------------------------------------------------------

func _on_item_hovered(inst) -> void:
	if inst == null:
		details_label.text = ""
		return
	details_label.text = _format_item_details(inst)


func _on_item_unhovered() -> void:
	details_label.text = "Hover an item to see its details."


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
		SLOT_NAMES[clampi(int(base.slot), 0, SLOT_NAMES.size() - 1)],
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


# Shared stat-computation core; _compute_stats_text is just a formatter over this.
func _compute_stats_dict(hero_data: Resource, equipped: Array) -> Dictionary:
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
	return current
