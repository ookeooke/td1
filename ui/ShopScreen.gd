extends Control

# Phase 37 shop: shows purchasable content (locked heroes, towers, bundles).
# Each entry has a Buy button that routes through PurchaseManager (stub).
# Products are @export so they can be edited in the Inspector / .tscn.

@export var products: Array[Resource] = []

@onready var back_button: Button = %BackButton
@onready var product_list: VBoxContainer = %ProductList
@onready var restore_button: Button = %RestoreButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	restore_button.pressed.connect(_on_restore)
	EventBus.iap_purchase_completed.connect(_on_purchase_completed)
	_build_list()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_restore() -> void:
	PurchaseManager.restore_purchases()


func _on_purchase_completed(_product_id: String, _unlock_id: String) -> void:
	_build_list()  # refresh to show "Owned"


func _build_list() -> void:
	for child in product_list.get_children():
		child.queue_free()
	for product in products:
		if product == null:
			continue
		_add_product_entry(product)


func _add_product_entry(product: Resource) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var margin := MarginContainer.new()
	margin.set("theme_override_constants/margin_left", 12)
	margin.set("theme_override_constants/margin_top", 10)
	margin.set("theme_override_constants/margin_right", 12)
	margin.set("theme_override_constants/margin_bottom", 10)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.set("theme_override_constants/separation", 12)
	margin.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = product.display_name
	name_label.set("theme_override_font_sizes/font_size", 20)
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = product.description
	desc_label.set("theme_override_font_sizes/font_size", 14)
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(desc_label)

	var is_owned: bool = _is_product_unlocked(product)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 60)
	btn.set("theme_override_font_sizes/font_size", 18)
	if is_owned:
		btn.text = "Owned"
		btn.disabled = true
	else:
		btn.text = product.price_text
		btn.pressed.connect(_on_buy.bind(product))
	hbox.add_child(btn)

	product_list.add_child(panel)


func _on_buy(product: Resource) -> void:
	PurchaseManager.purchase(product.product_id, product.unlock_id)


# Dispatch to UnlockManager's type-specific checker based on the product's
# declared unlock_type. Prevents the hero/tower id-collision bug class.
func _is_product_unlocked(product: Resource) -> bool:
	match product.unlock_type:
		ProductData.UnlockType.HERO:
			return UnlockManager.is_hero_unlocked(product.unlock_id)
		ProductData.UnlockType.TOWER:
			return UnlockManager.is_tower_unlocked(product.unlock_id)
	return false
