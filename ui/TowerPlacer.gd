extends Node

# Phase 8 + 38 + 47d-1: resolves tower_id → scene/data/cost entirely from
# ContentRegistry. Each TowerData now carries its own `tower_scene`
# PackedScene field, so adding a new tower is ONE file — drop a .tres,
# register it in ContentRegistry. No scene map to keep in sync.

@export var towers_parent_path: NodePath
@export var grid_manager_path: NodePath

var _towers_parent: Node
var _grid: Node
var _registry: Dictionary = {}

# Debug per-tower-tier overrides — identity (1.0) in production. Read at
# build time so live slider tweaks apply to the next placed tower without
# rebuilding the registry.
const _BalanceOverrides := preload("res://balance/debug/BalanceOverrides.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_towers_parent = get_node_or_null(towers_parent_path)
	if _towers_parent == null:
		_towers_parent = self
	_grid = get_node_or_null(grid_manager_path)
	if _grid == null:
		_grid = get_tree().root.find_child("GridManager", true, false)
	# Build the registry straight from ContentRegistry — scene now lives on
	# TowerData itself (Phase 47d-1).
	for tower_data in ContentRegistry.towers:
		if tower_data == null:
			continue
		var tid: String = tower_data.tower_id
		if tid == "":
			push_warning("[TowerPlacer] tower has empty tower_id")
			continue
		if tower_data.tower_scene == null:
			push_warning("[TowerPlacer] tower '%s' has no tower_scene set on its TowerData" % tid)
			continue
		_registry[tid] = {
			"scene": tower_data.tower_scene,
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
	# Compute cost live so debug per-tier override applies without rebuild.
	var cost: int = int(round(float(entry.cost) * _BalanceOverrides.get_tower_mult(tower_id, "l1", "cost_mult")))
	if not RunState.spend_gold(cost):
		print("[TowerPlacer] build refused — need %dg, have %d" % [cost, RunState.gold])
		return
	var tower: Node2D = (entry.scene as PackedScene).instantiate()
	# Phase 47d-6 fix: override the scene's baked `data` (if any) with the
	# TowerData we actually want. This turns the scene into a pure chassis
	# so ONE combat scene (TowerCombat.tscn) can back N data-driven towers,
	# AND breaks the circular tres↔tscn reference that was leaving
	# `tower.data = null` for towers whose scene round-trips to their own
	# TowerData. Must happen BEFORE add_child so base_tower._ready sees the
	# right data.
	if "data" in tower:
		tower.data = entry.data
	tower.position = _grid.get_spot_position(spot_id)
	_towers_parent.add_child(tower)
	_grid.set_tower_at(spot_id, tower)
	EventBus.tower_built.emit(tower, spot_id)
	print("[TowerPlacer] built %s on %s for %dg (gold left: %d)" % [tower_id, spot_id, cost, RunState.gold])


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
	if not RunState.spend_gold(cost):
		print("[TowerPlacer] upgrade refused — need %dg, have %d" % [cost, RunState.gold])
		return
	if not tower.upgrade():
		# Refund if the tower unexpectedly refused after we already spent.
		RunState.add_gold(cost)
		return
	print("[TowerPlacer] upgraded tower on %s to lvl %d for %dg (gold left: %d)" % [
		spot_id, tower.level, cost, RunState.gold,
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
	if not RunState.spend_gold(cost):
		print("[TowerPlacer] branch upgrade refused — need %dg, have %d" % [cost, RunState.gold])
		return
	if not tower.upgrade_to_branch(branch_idx):
		RunState.add_gold(cost)
		return
	print("[TowerPlacer] branched tower on %s → branch %d for %dg (gold left: %d)" % [
		spot_id, branch_idx, cost, RunState.gold,
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
	RunState.add_gold(refund)
	EventBus.tower_sold.emit(tower, refund)
	tower.queue_free()
	print("[TowerPlacer] sold tower on %s for +%dg (gold now: %d)" % [spot_id, refund, RunState.gold])
