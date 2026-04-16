extends Node

# Phase 37 stub: client-side purchase flow. Every buy routes through here.
# Currently returns instant success (no real billing SDK). When store
# accounts are ready, swap the body of purchase() for RevenueCat /
# Google Play Billing calls. UnlockManager + SaveManager + UI stay unchanged.
#
# restore_purchases() is required by Apple App Store guidelines — must
# exist even if it's a no-op on Android.


func _ready() -> void:
	print("[PurchaseManager] loaded (stub — all purchases auto-succeed)")


func purchase(product_id: String, unlock_id: String) -> void:
	# TODO: replace with real SDK call.
	# Real flow: SDK.purchase(product_id) → await receipt → validate → unlock.
	print("[PurchaseManager] purchase '%s' → auto-success (stub)" % product_id)
	UnlockManager.unlock(unlock_id)
	EventBus.iap_purchase_completed.emit(product_id, unlock_id)


func restore_purchases() -> void:
	# TODO: replace with real SDK restore call.
	# Real flow: SDK.restore() → iterate receipts → unlock each.
	print("[PurchaseManager] restore_purchases (stub — nothing to restore)")
