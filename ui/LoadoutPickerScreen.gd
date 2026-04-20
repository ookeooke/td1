extends Control

# Phase 47d-4: tower loadout picker — reached from the WorldMap "Loadout"
# button. Visual vocabulary mirrors the in-game build ring (same RING_RADIUS
# + ICON_SIZE as TowerRadialMenu) so the player sees the exact slot shape
# they'll use mid-level.
#
# Interaction (tap-arm-then-tap-place):
#   1. Tap a loadout slot → arms it (yellow glow).
#   2. Tap a pool tower → placed in the armed slot. If the tower was already
#      equipped in another slot, the two slots SWAP (no-duplicate rule
#      without making the player lose a pick). If no slot is armed and
#      there's a free unlocked slot, auto-place into the first one.
#   3. Tap an equipped pool tower → unequip (clear that slot).
#   4. Tap a locked slot → toast.
# Every change persists via SaveManager.save_game().

const TowerIconButton := preload("res://ui/TowerIconButton.gd")

# Parity with the in-game ring so the player recognises the shape.
const RING_RADIUS: float = 120.0
const ICON_SIZE: float = 90.0
const POOL_ICON_SIZE: float = 90.0

@onready var back_button: Button = %BackButton
@onready var reset_button: Button = %ResetButton
@onready var ring_anchor: Control = %RingAnchor
@onready var pool_container: HFlowContainer = %PoolContainer
@onready var title_label: Label = %TitleLabel

var _ring_slots: Array = []           # index → TowerIconButton (slot)
var _pool_icons: Array = []           # index → TowerIconButton (pool)
var _pool_tower_ids: Array = []       # parallel to _pool_icons
var _armed_slot_idx: int = -1         # -1 means no slot armed


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	reset_button.pressed.connect(_on_reset)
	title_label.text = "Choose Your Towers"
	_build_ring()
	_build_pool()
	_refresh_equipped_badges()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _on_reset() -> void:
	GameState.reset_loadout_to_default()
	SaveManager.save_game()
	_rebuild_ring()
	_refresh_equipped_badges()
	Toast.show_message("Loadout reset")


# ── Ring of loadout slots ───────────────────────────────────────────────

func _build_ring() -> void:
	_rebuild_ring()


func _rebuild_ring() -> void:
	for slot in _ring_slots:
		if slot != null and is_instance_valid(slot):
			slot.queue_free()
	_ring_slots.clear()
	_armed_slot_idx = -1
	var n: int = GameState.TOWER_SLOT_MAX
	var cap: int = mini(GameState.tower_slot_cap, n)
	for i in range(n):
		var angle: float = -PI * 0.5 + (TAU / float(n)) * float(i)
		var slot: Control = TowerIconButton.new()
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * RING_RADIUS
		slot.position = offset - Vector2(ICON_SIZE, ICON_SIZE) * 0.5
		slot.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5
		ring_anchor.add_child(slot)
		if i < cap:
			var tid: String = ""
			if i < GameState.selected_tower_ids.size():
				tid = GameState.selected_tower_ids[i]
			var data: Resource = ContentRegistry.find_tower(tid) if tid != "" else null
			if data != null:
				# setup_pool instead of setup: ring slots in the picker must
				# not gate on GameState.gold (which may be 0 on first boot or
				# leftover from a prior run). Affordability is a runtime
				# concept, not a loadout concept.
				slot.setup_pool(data)
				# Reuse the TowerIconButton's `pressed` signal for "arm this slot".
				# Binding the slot index lets one handler cover every slot.
				slot.pressed.connect(_on_loadout_slot_pressed.bind(i))
			else:
				# Empty-but-unlocked slot — tap to arm (so the player can fill
				# it with a pool pick). Uses the locked padlock visual; the
				# tap handler treats it as an arming op, not an error.
				slot.setup_locked()
				slot.locked_pressed.connect(_on_empty_slot_pressed.bind(i))
		else:
			# Progression-locked slot — feedback only.
			slot.setup_locked()
			slot.locked_pressed.connect(_on_progression_locked_pressed)
		_ring_slots.append(slot)


func _on_loadout_slot_pressed(_tower_id: String, slot_idx: int) -> void:
	_arm_slot(slot_idx)


func _on_empty_slot_pressed(slot_idx: int) -> void:
	# Arming an empty unlocked slot lets the next pool-tap fill it.
	_arm_slot(slot_idx)


func _on_progression_locked_pressed() -> void:
	Toast.show_message("Unlock through progression")


func _arm_slot(slot_idx: int) -> void:
	# Toggle: tapping the already-armed slot disarms it.
	if _armed_slot_idx == slot_idx:
		_set_armed(-1)
		return
	_set_armed(slot_idx)


func _set_armed(slot_idx: int) -> void:
	if _armed_slot_idx >= 0 and _armed_slot_idx < _ring_slots.size():
		var prev: Control = _ring_slots[_armed_slot_idx]
		if prev != null and is_instance_valid(prev) and prev.has_method("set_armed"):
			prev.set_armed(false)
	_armed_slot_idx = slot_idx
	if slot_idx >= 0 and slot_idx < _ring_slots.size():
		var cur: Control = _ring_slots[slot_idx]
		if cur != null and is_instance_valid(cur) and cur.has_method("set_armed"):
			cur.set_armed(true)


# ── Pool of unlocked towers ─────────────────────────────────────────────

func _build_pool() -> void:
	for child in pool_container.get_children():
		child.queue_free()
	_pool_icons.clear()
	_pool_tower_ids.clear()
	for data in ContentRegistry.towers:
		if data == null:
			continue
		if not UnlockManager.is_tower_unlocked(data.tower_id):
			continue
		var icon: Control = TowerIconButton.new()
		pool_container.add_child(icon)
		# `setup_pool` bypasses affordability so costly towers (Artillery at
		# 120g) can be equipped even with starting 100g — loadout selection
		# is independent of the current run's gold.
		icon.setup_pool(data)
		icon.pressed.connect(_on_pool_tower_pressed)
		_pool_icons.append(icon)
		_pool_tower_ids.append(data.tower_id)


func _on_pool_tower_pressed(tower_id: String) -> void:
	# If the tower is already in the loadout and no slot is armed, unequip it.
	var existing: int = GameState.selected_tower_ids.find(tower_id)
	if _armed_slot_idx < 0 and existing >= 0 and existing < GameState.tower_slot_cap:
		_clear_slot(existing)
		return
	# Place into the armed slot, or the first empty unlocked slot.
	var target: int = _armed_slot_idx
	if target < 0:
		target = _first_empty_unlocked_slot()
	if target < 0:
		Toast.show_message("All slots full — tap a slot to replace")
		return
	if GameState.set_loadout_slot(target, tower_id):
		SaveManager.save_game()
		_rebuild_ring()
		_refresh_equipped_badges()


func _clear_slot(slot_idx: int) -> void:
	if GameState.set_loadout_slot(slot_idx, ""):
		SaveManager.save_game()
		_rebuild_ring()
		_refresh_equipped_badges()


func _first_empty_unlocked_slot() -> int:
	var cap: int = mini(GameState.tower_slot_cap, GameState.TOWER_SLOT_MAX)
	for i in range(cap):
		if i >= GameState.selected_tower_ids.size() or GameState.selected_tower_ids[i] == "":
			return i
	return -1


func _refresh_equipped_badges() -> void:
	var cap: int = mini(GameState.tower_slot_cap, GameState.selected_tower_ids.size())
	var equipped: Dictionary = {}
	for i in range(cap):
		var tid: String = GameState.selected_tower_ids[i]
		if tid != "":
			equipped[tid] = true
	for i in range(_pool_icons.size()):
		var icon: Control = _pool_icons[i]
		if icon != null and is_instance_valid(icon) and icon.has_method("set_equipped"):
			icon.set_equipped(equipped.has(_pool_tower_ids[i]))
