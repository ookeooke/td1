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
const _PICKUP_SCENE_PATH := "res://items/ItemPickup.tscn"

var _default_table: Resource = null
var _pickup_scene: PackedScene = null


func _ready() -> void:
	_default_table = load(_DEFAULT_TABLE_PATH)
	if _default_table == null:
		push_warning("[LootDropper] default table not found at %s" % _DEFAULT_TABLE_PATH)
	_pickup_scene = load(_PICKUP_SCENE_PATH)
	if _pickup_scene == null:
		push_warning("[LootDropper] pickup scene not found at %s" % _PICKUP_SCENE_PATH)
	EventBus.enemy_died.connect(_on_enemy_died)
	print("[LootDropper] loaded")


func _on_enemy_died(enemy: Node, _gold: int) -> void:
	if not is_instance_valid(enemy):
		return
	# Phase E3: per-enemy loot_table override. Bosses / elites can author
	# their own .tres (guaranteed drop, weighted to higher rarities).
	# Regular mobs leave data.loot_table = null → fall back to the default.
	var table: Resource = _default_table
	if enemy != null and "data" in enemy and enemy.data != null \
			and "loot_table" in enemy.data and enemy.data.loot_table != null:
		table = enemy.data.loot_table
	if table == null:
		return
	if randf() > table.drop_chance:
		return
	var wave: int = GameState.wave_number
	var base_id: String = table.pick_base_id(wave)
	if base_id == "":
		return
	var base: Resource = ContentRegistry.find_item_base(base_id)
	if base == null:
		push_warning("[LootDropper] unknown base_id '%s' in loot table" % base_id)
		return
	var inst = LootRoller.roll_item_instance(base, wave)
	if inst == null:
		return
	var world_pos: Vector2 = enemy.global_position
	_spawn_pickup(inst, world_pos)
	EventBus.item_dropped.emit(inst, world_pos)


func _spawn_pickup(inst, world_pos: Vector2) -> void:
	if _pickup_scene == null:
		return
	var pickup: Node2D = _pickup_scene.instantiate()
	pickup.setup(inst)
	pickup.global_position = world_pos
	# Parent to the current scene (Main) so world-space positions align with
	# enemies/towers/hero. Main is a Node2D, matching the coordinate system.
	var host: Node = get_tree().current_scene
	if host == null:
		push_warning("[LootDropper] no current_scene to parent pickup to")
		pickup.queue_free()
		return
	host.add_child(pickup)
