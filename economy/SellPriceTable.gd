extends Resource
class_name SellPriceTable

# Maps item rarity (0-4: Common/Magic/Rare/Epic/Legendary) to sell-gold reward.
# Authored as a `.tres` file so designers can tune values without code changes.
# Loaded by InventoryManager.sell().

@export var common: int = 10
@export var magic: int = 50
@export var rare: int = 200
@export var epic: int = 1000
@export var legendary: int = 5000


# Look up the sell price for a given rarity int. Out-of-range rarities clamp
# to Common — defensive against future rarity tier additions or bad data.
func price_for(rarity: int) -> int:
	match rarity:
		0: return common
		1: return magic
		2: return rare
		3: return epic
		4: return legendary
		_: return common
