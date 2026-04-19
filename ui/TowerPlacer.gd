extends Node

# Phase 8 + 38 refactor: resolves tower_id → scene/data/cost via
# ContentRegistry + a scene map. Adding a new tower = one .tres in
# ContentRegistry + one scene_map entry here (needed because attack
# towers and barracks use different scene structures).

# Scene map: tower_id → PackedScene. The only hardcoded part — needed
# because BaseTower vs TowerBarracks have different scene structures.
# ContentRegistry provides the data; this provides the scene.
const _SCENE_MAP: Dictionary = {
	"tower_archer": preload("res://towers/TowerArcher.tscn"),
	"tower_barracks": preload("res://towers/TowerBarracks.tscn"),
	"tower_mage": preload("res://towers/TowerMage.tscn"),
	"tower_artillery": preload("res://towers/TowerArtillery.tscn"),
}

@export var towers_parent_path: NodePath
@export var grid_manager_path: NodePath

var _towers_parent: Node
var _grid: Node
var _registry: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_towers_parent = get_node_or_null(towers_parent_path)
	if _towers_parent == null:
		_towers_parent = self
	_grid = get_node_or_null(grid_manager_path)
	if _grid == null:
		_grid = get_tree().root.find_child("GridManager", true, false)
	# Build the registry from ContentRegistry's tower data + the scene map.
	for tower_data in ContentRegistry.towers:
		if tower_data == null:
			continue
		var tid: String = tower_data.tower_id
		if tid == "" or not _SCENE_MAP.has(tid):
			push_warning("[TowerPlacer] no scene mapped for tower_id '%s'" % tid)
			continue
		_registry[tid] = {
			"scene": _SCENE_MAP[tid],
			"data": tower_data,
			"cost": int(tower_data.cost),
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
	# CORE RULE 14 — every tower implements get_sell_value().
	var refund: int = int(tower.get_sell_value())
	_grid.clear_tower_at(spot_id)
	GameState.add_gold(refund)
	EventBus.tower_sold.emit(tower, refund)
	tower.queue_free()
	print("[TowerPlacer] sold tower on %s for +%dg (gold now: %d)" % [spot_id, refund, GameState.gold])
