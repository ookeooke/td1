extends Node

# Phase 8: listens for tower_build_requested, resolves tower_id → scene/data/cost,
# spends gold through GameState, instances the tower at the spot position,
# parents it under @towers_parent, and registers it with GridManager.
# New tower types register here in later phases (mage, artillery, barracks).

const ARCHER_SCENE: PackedScene = preload("res://towers/TowerArcher.tscn")
const ARCHER_DATA: Resource = preload("res://towers/data/tower_archer.tres")
const BARRACKS_SCENE: PackedScene = preload("res://towers/TowerBarracks.tscn")
const BARRACKS_DATA: Resource = preload("res://towers/data/tower_barracks.tres")

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
	_registry["barracks"] = {
		"scene": BARRACKS_SCENE,
		"data": BARRACKS_DATA,
		"cost": BARRACKS_DATA.cost,
	}
	EventBus.tower_build_requested.connect(_on_build_requested)
	EventBus.tower_sell_requested.connect(_on_sell_requested)
	EventBus.tower_upgrade_requested.connect(_on_upgrade_requested)
	EventBus.tower_branch_upgrade_requested.connect(_on_branch_upgrade_requested)


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


func _on_upgrade_requested(spot_id: String) -> void:
	if _grid == null:
		return
	var tower: Node = _grid.get_tower_at(spot_id)
	if tower == null or not tower.has_method("can_upgrade"):
		return
	if not tower.can_upgrade():
		return
	var cost: int = tower.get_upgrade_cost_to(tower.level + 1)
	if cost <= 0:
		return
	if not GameState.spend_gold(cost):
		print("[TowerPlacer] upgrade refused — need %dg, have %d" % [cost, GameState.gold])
		return
	if not tower.upgrade():
		# Refund if the tower unexpectedly refused after we already spent.
		GameState.add_gold(cost)
		return
	print("[TowerPlacer] upgraded tower on %s to lvl %d for %dg (gold left: %d)" % [
		spot_id, tower.level, cost, GameState.gold,
	])


func _on_branch_upgrade_requested(spot_id: String, branch_idx: int) -> void:
	if _grid == null:
		return
	var tower: Node = _grid.get_tower_at(spot_id)
	if tower == null or not tower.has_method("has_branch_options"):
		return
	if not tower.has_branch_options():
		return
	var cost: int = tower.get_branch_cost(branch_idx)
	if cost <= 0:
		return
	if not GameState.spend_gold(cost):
		print("[TowerPlacer] branch upgrade refused — need %dg, have %d" % [cost, GameState.gold])
		return
	if not tower.upgrade_to_branch(branch_idx):
		GameState.add_gold(cost)
		return
	print("[TowerPlacer] branched tower on %s → branch %d for %dg (gold left: %d)" % [
		spot_id, branch_idx, cost, GameState.gold,
	])


func _on_sell_requested(spot_id: String) -> void:
	if _grid == null:
		return
	var tower: Node = _grid.get_tower_at(spot_id)
	if tower == null:
		return
	var refund: int = 0
	if tower.has_method("get_sell_value"):
		refund = int(tower.get_sell_value())
	elif "data" in tower and tower.data != null and "sell_value" in tower.data:
		refund = int(tower.data.sell_value)
	_grid.clear_tower_at(spot_id)
	GameState.add_gold(refund)
	EventBus.tower_sold.emit(tower, refund)
	tower.queue_free()
	print("[TowerPlacer] sold tower on %s for +%dg (gold now: %d)" % [spot_id, refund, GameState.gold])
