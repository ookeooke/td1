extends RefCounted
class_name BalanceCalculator

# Hardness score for any wave or level. Pure-function utility — call from
# @tool-marked level scripts to validate authored levels against the target
# curve documented in the balance plan, or from runtime/telemetry to record
# expected-vs-actual difficulty.
#
# Score formula per enemy:
#   score = W_EHP * EHP + W_LIVES * lives_worth + W_SPEED * move_speed
#   EHP   = max_health / max(0.05, 1.0 - armor)
#
# Magic resist is intentionally not folded into EHP — most player damage is
# physical; folding both would double-count. Resist-heavy enemies still raise
# total score via their HP and speed.

const W_EHP: float = 2.0
const W_LIVES: float = 50.0
const W_SPEED: float = 0.02  # 2.0 / 100.0 — speed 140 contributes 2.8

# PackedScene → EnemyData lookup cache. Avoids re-instantiating the scene
# on every score call; a 5-wave level resolves the same handful of scenes
# repeatedly. Call clear_cache() when reloading content in editor.
static var _scene_data_cache: Dictionary = {}

static func clear_cache() -> void:
	_scene_data_cache.clear()

static func enemy_score(data: EnemyData) -> float:
	if data == null:
		return 0.0
	var ehp: float = float(data.max_health) / max(0.05, 1.0 - data.armor)
	return W_EHP * ehp + W_LIVES * float(data.lives_worth) + W_SPEED * data.move_speed

static func score_wave(wave: WaveData) -> float:
	if wave == null:
		return 0.0
	var total: float = 0.0
	for spawn in wave.spawns:
		if spawn == null or spawn.count <= 0:
			continue
		var ed := _data_from_scene(spawn.enemy_scene)
		if ed == null:
			continue
		total += enemy_score(ed) * float(spawn.count)
	return total

static func score_level(wave_list: WaveList, starting_gold: int = 100) -> float:
	if wave_list == null:
		return 0.0
	var total: float = 0.0
	for w in wave_list.waves:
		total += score_wave(w)
	return total - 0.5 * float(starting_gold)

# Verbose form — returns a dictionary with per-wave breakdown for editor
# logging. Used by Level scripts in @tool mode to print authoring readouts.
static func score_level_breakdown(wave_list: WaveList, starting_gold: int = 100) -> Dictionary:
	var per_wave: Array = []
	var total: float = 0.0
	if wave_list != null:
		for w in wave_list.waves:
			var s := score_wave(w)
			per_wave.append(s)
			total += s
	return {
		"per_wave": per_wave,
		"wave_total": total,
		"starting_gold": starting_gold,
		"net_score": total - 0.5 * float(starting_gold),
	}

static func _data_from_scene(scene: PackedScene) -> EnemyData:
	if scene == null:
		return null
	if _scene_data_cache.has(scene):
		return _scene_data_cache[scene]
	var inst: Node = scene.instantiate()
	var ed: EnemyData = null
	if "data" in inst:
		ed = inst.data
	inst.free()
	_scene_data_cache[scene] = ed
	return ed
