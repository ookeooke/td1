extends Resource
class_name ProductData

# One purchasable item in the shop. Maps a store product_id to the
# content it unlocks. Price is display-only (real price comes from the
# store SDK at runtime). Phase 37 stub; Phase 41+ wires to RevenueCat.

@export var product_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var price_text: String = "$0.99"  # display-only placeholder
# The content ID that UnlockManager.unlock() receives on purchase.
@export var unlock_id: String = ""
