extends Resource
class_name ItemBase

# Authored .tres template for an equippable item "species" (e.g. "Iron Sword").
# A single ItemBase backs many ItemInstance drops; instances diverge by their
# rolled affix values. Base fields are invariant per species. See the plan's
# "Item BASE vs Item INSTANCE" section for the factoring.

enum Slot { WEAPON, ARMOR, HELM, GLOVES, BOOTS, TRINKET }  # 6 reserved; launch uses 0/1/5
enum Rarity { COMMON, MAGIC, RARE, EPIC, LEGENDARY }

@export var base_id: String = ""                       # stable; must equal filename basename
@export var base_name: String = "Item"
@export var slot: int = Slot.WEAPON
@export var rarity: int = Rarity.COMMON
# Player Power Tier — see balance/BALANCE.md. Default 0 means "derive from
# rarity at read time" (COMMON=1, MAGIC=2, RARE=3, EPIC=4, LEGENDARY=5).
# Override (1–10) for items that punch above or below their rarity band.
@export_range(0, 10) var power_tier: int = 0


# Power tier resolution: explicit override wins, else derived from rarity.
# Called from LoadoutState.get_effective_ppt() — keep cheap.
func resolve_power_tier() -> int:
	if power_tier > 0:
		return power_tier
	# Rarity enum values 0..4 map to PPT 1..5.
	return clampi(int(rarity) + 1, 1, 5)
@export var icon_glyph: String = "generic"             # key into ItemIcon._draw_glyph
@export var icon_color: Color = Color.WHITE            # base tint; rarity halo drawn separately
@export var hero_restriction: Array[String] = []       # empty = any hero
@export var level_requirement: int = 1
@export var implicit_abilities: Array[Resource] = []   # always-on, never rerolled
@export var affix_slots: int = 0                       # number of rolled affixes per drop
@export var allowed_affix_pools: Array[String] = []    # pool_id references
@export var drop_weight: float = 1.0                   # 0 = excluded from random tables
@export var min_wave: int = 1
# Inventory footprint in grid cells. Defaults to 1×1 — existing .tres files
# need no edit. Mark larger items (e.g. great-sword 1×2) by overriding.
@export var grid_width: int = 1
@export var grid_height: int = 1
@export_multiline var description: String = ""
