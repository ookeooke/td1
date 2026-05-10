extends Resource
class_name HeroSkillTreeData

# Phase 1 — the full skill tree for one hero.
# Lives at `res://heroes/data/skill_trees/<hero_id>.tres`; filename basename
# matches `hero_id` so ContentRegistry._validate_ids() catches drift.

@export var hero_id: String = ""
@export var nodes: Array[Resource] = []  # Array[HeroSkillNodeData]


func find_node(node_id: String) -> Resource:
	for n in nodes:
		if n != null and "node_id" in n and n.node_id == node_id:
			return n
	return null


# All nodes that operate on the same passive_id / skill_id (ranks 1..N).
func nodes_for_target(target_id_arg: String) -> Array:
	var out: Array = []
	for n in nodes:
		if n != null and "target_id" in n and n.target_id == target_id_arg:
			out.append(n)
	return out


# Deduplicated passive_ids referenced by PASSIVE_RANK nodes — the hero's
# "passive pool" (which passives this hero can ever own and equip).
func get_passive_ids() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for n in nodes:
		if n == null or not ("kind" in n):
			continue
		if int(n.kind) != HeroSkillNodeData.Kind.PASSIVE_RANK:
			continue
		var pid: String = String(n.target_id)
		if pid == "" or seen.has(pid):
			continue
		seen[pid] = true
		out.append(pid)
	return out


# Convenience: friendly name for a passive (first PASSIVE_RANK node with the
# matching target_id has it). Falls back to the raw passive_id.
func get_passive_name(passive_id: String) -> String:
	for n in nodes:
		if n == null or not ("kind" in n):
			continue
		if int(n.kind) != HeroSkillNodeData.Kind.PASSIVE_RANK:
			continue
		if n.target_id == passive_id and n.rank == 1:
			return String(n.node_name)
	return passive_id
