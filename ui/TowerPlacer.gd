extends Node

# Phase 8: listens for tower_build_requested, resolves tower_id → scene/data/cost,
# spends gold through GameState, instances the tower at the spot position,
# parents it under @towers_parent, and registers it with GridManager.
# New tower types register here in later phases (mage, artillery, barracks).

const ARCHER_SCENE: PackedScene = preload("res://towers/TowerArcher.tscn")
const ARCHER_DATA: Resource = preload("res://towers/data/tower_archer.tres")

@export var towers_parent_path: NodePath
@export var grid_manager_path: NodePath

var _towers_parent: Node
var _grid: Node
var _registry: Dictionary = {}


func _ready() -> void:
	_towers_parent = get_node_or_null(towers_parent_path)
	if _towers_parent == null:
		_towers_parent = self
	_grid = get_node_or_null(grid_manager_path)
	if _grid == null:
		_grid = get_tree().root.find_child("GridManager", true, false)
	_registry["archer"] = {
		"scene": ARCHER_SCENE,
		"data": ARCHER_DATA,
		"cost": ARCHER_DATA.cost,
	}
	EventBus.tower_build_requested.connect(_on_build_requested)
	EventBus.tower_sell_requested.connect(_on_sell_requested)


func _on_build_requested(spot_id: String, tower_id: String) -> void:
	if not _registry.has(tower_id):
		push_warning("[TowerPlacer] unknown tower_id '%s'" % tower_id)
		return
	if _grid == null:
		push_error("[TowerPlacer] no GridManager")
		return
	if _grid.is_occupied(spot_id):
		return
	var entry: Dictionary = _registry[tower_id]
	var cost: int = entry.cost
	if not GameState.spend_gold(cost):
		print("[TowerPlacer] build refused — need %dg, have %d" % [cost, GameState.gold])
		return
	var tower: Node2D = (entry.scene as PackedScene).instantiate()
	tower.position = _grid.get_spot_position(spot_id)
	_towers_parent.add_child(tower)
	_grid.set_tower_at(spot_id, tower)
	EventBus.tower_built.emit(tower, spot_id)
	print("[TowerPlacer] built %s on %s for %dg (gold left: %d)" % [tower_id, spot_id, cost, GameState.gold])


func _on_sell_requested(spot_id: String) -> void:
	if _grid == null:
		return
	var tower: Node = _grid.get_tower_at(spot_id)
	if tower == null:
		return
	var refund: int = 0
	if "data" in tower and tower.data != null and "sell_value" in tower.data:
		refund = int(tower.data.sell_value)
	_grid.clear_tower_at(spot_id)
	GameState.add_gold(refund)
	EventBus.tower_sold.emit(tower, refund)
	tower.queue_free()
	print("[TowerPlacer] sold tower on %s for +%dg (gold now: %d)" % [spot_id, refund, GameState.gold])
