extends Node

# Phase 48 C1 — listens to EventBus.enemy_died, rolls a drop via LootRoller,
# and (in C2+) spawns an ItemPickup at the enemy's death position. For now
# (C1) just logs the rolled instance — visual and pickup come in C2/C3.
#
# Design:
# - Uses a global default LootTableData loaded at _ready. Future: read
#   enemy.data.loot_table for per-enemy overrides (Phase E tuning).
# - Any killer triggers drops (tower, hero, soldier, spell) — enemy_died
#   fires regardless of source. Matches user's confirmed design decision.
# - drop_chance is rolled once per kill; if it passes, a specific base is
#   picked by weighted random from the table; LootRoller generates the
#   instance with UID and affixes.

const _DEFAULT_TABLE_PATH := "res://items/data/loot_table_default.tres"

var _default_table: Resource = null


func _ready() -> void:
	_default_table = load(_DEFAULT_TABLE_PATH)
	if _default_table == null:
		push_warning("[LootDropper] default table not found at %s" % _DEFAULT_TABLE_PATH)
	EventBus.enemy_died.connect(_on_enemy_died)
	print("[LootDropper] loaded")


func _on_enemy_died(enemy: Node, _gold: int) -> void:
	if not is_instance_valid(enemy):
		return
	var table: Resource = _default_table   # Phase E: read enemy.data.loot_table if set
	if table == null:
		return
	if randf() > table.drop_chance:
		return
	var base_id: String = table.pick_base_id()
	if base_id == "":
		return
	var base: Resource = ContentRegistry.find_item_base(base_id)
	if base == null:
		push_warning("[LootDropper] unknown base_id '%s' in loot table" % base_id)
		return
	var wave: int = GameState.wave_number
	var inst = LootRoller.roll_item_instance(base, wave)
	if inst == null:
		return
	var world_pos: Vector2 = enemy.global_position
	# C2+ will spawn an ItemPickup here. For now emit the signal + log.
	EventBus.item_dropped.emit(inst, world_pos)
	print("[LootDropper] dropped %s uid=%s @ %s" % [base_id, inst.uid, world_pos])
