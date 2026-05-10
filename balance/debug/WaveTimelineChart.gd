extends Control
class_name WaveTimelineChart

# Per-wave visual planner card. Renders one wave as a stacked timeline:
#   header text  →  fix-suggestion line  →  spawn window
#   demand bars (per 5s bucket)  →  L1 supply line overlay
#   in-spawn early-call band (right end, when next wave can be summoned)
#   path lanes at the bottom (one row per path in the level)  →  composition footer
#
# Pure read; no .tres mutation. Created at runtime by BalanceSliders for the
# level whose wave timelines are expanded. Debug-only — BalanceSliders gates
# the entire panel on OS.is_debug_build() upstream.
#
# Reuses BalanceCalculator helpers for EHP / damage / timeline math; reuses
# ContentRegistry.towers for the L1 dmg-per-gold supply line. The only new
# math is bucket aggregation (loop spawns, sum into time buckets).

# ─── Layout constants ──────────────────────────────────────────────────────
const CARD_HEIGHT: float = 150.0
const CARD_MIN_WIDTH: float = 560.0
const PAD_X: float = 8.0
const HEADER_Y: float = 4.0
const HEADER_H: float = 14.0
# Fix-suggestion lane between the header and the chart. Grows the card by
# 14 px universally — when no fix is suggested this lane is blank, accepted
# in exchange for visual consistency across waves with and without a fix.
const FIX_LINE_Y: float = 18.0
const FIX_LINE_H: float = 14.0
const FIX_LINE_FONT: int = 11
const CHART_TOP: float = 36.0
const CHART_BOTTOM: float = 130.0
const LANE_TOP: float = 132.0
const LANE_HEIGHT: float = 9.0             # per-path lane
const FOOTER_Y_FROM_BOTTOM: float = 4.0
const FOOTER_FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 12
const BUCKET_SEC: float = 5.0
# Time-axis row sits between the lane area and the composition footer. Baseline
# = (lane bottom) + LANE_AXIS_GAP. Labels mark each 5s bucket boundary; on long
# spawn windows we step every-other label to avoid overlap.
const LANE_AXIS_GAP: float = 12.0
const AXIS_LABEL_FONT_SIZE: int = 9
const WAVE_START_LINE_W: float = 1.0

# ─── Colors ────────────────────────────────────────────────────────────────
const COL_EARLYCALL_FULL: Color = Color(0.35, 0.85, 0.45, 0.55)  # in-cap zone
const COL_EARLYCALL_FADE: Color = Color(0.35, 0.85, 0.45, 0.0)   # fades to transparent over the cap
# Stacked-by-class bars: each bucket's EHP is segmented by enemy class so the
# composition of a spike is visible (60 % armored vs 60 % flying tells you a
# different design story). Class colors mirror the path-lane glyphs below
# (ENEMY_COLORS) so the eye links bar segment → lane dot. Magma intensity
# coloring (v1) was redundant with bar height; dropped.
const COL_BAR_OUTLINE: Color = Color(0, 0, 0, 0.35)   # 1px segment border for separation
# Supply line is a quiet *reference*, not an alarm. The bars do the alarming
# (high stop = spike). Mirrors Grafana / Datadog threshold-line convention.
const COL_SUPPLY_LINE: Color = Color(0.85, 0.88, 0.92, 0.55)
# Per-segment fills for the stacked supply bands. Tower=green is the loudest
# because it's usually the largest contributor; hero/skills/control are picked
# to NOT collide with the enemy class palette below (yellow=scout, cyan=flying,
# pink=boss already taken). Alpha is set per-band at draw time (floor faint,
# actual stronger) so bars behind the bands stay legible.
const COL_SUPPLY_TOWER:   Color = Color(0.45, 0.95, 0.55, 1.0)
const COL_SUPPLY_HERO:    Color = Color(0.95, 0.65, 0.35, 1.0)
const COL_SUPPLY_SKILLS:  Color = Color(0.55, 0.65, 0.95, 1.0)
const COL_SUPPLY_CONTROL: Color = Color(0.85, 0.55, 0.95, 1.0)
const COL_SUPPLY_TOP_FLOOR:  Color = Color(0.55, 0.85, 0.55, 0.60)
const COL_SUPPLY_TOP_ACTUAL: Color = Color(0.45, 0.95, 0.55, 0.95)
const COL_HEADER_OK: Color = Color(0.85, 0.95, 1.0)
const COL_HEADER_WARN: Color = Color(0.95, 0.80, 0.45)
const COL_FOOTER: Color = Color(0.65, 0.70, 0.78)
const COL_WAVE_START: Color = Color(0.95, 0.95, 1.0, 0.85)
# Hairline 5s tick on the timeline axis — replaces the alternating bucket
# backgrounds (chartjunk). Sits at low alpha so bars stay the dominant marks.
const COL_BUCKET_TICK: Color = Color(0.55, 0.60, 0.68, 0.20)
# Per-wave cumulative gold curve — same green as the level-overview chart so
# the eye links them as "the same number, zoomed in / out".
const COL_GOLD_CURVE: Color = Color(0.45, 0.95, 0.55, 0.95)
const COL_GOLD_CURVE_DOT: Color = Color(0.65, 1.00, 0.70, 1.0)

# Enemy class → lane glyph color. Matched against enemy_scene.resource_path
# (cheap, no instancing). Falls back to grey for unknown scenes.
const ENEMY_COLORS: Dictionary = {
	"basic":   Color(0.65, 0.65, 0.70),
	"scout":   Color(0.95, 0.90, 0.40),
	"armored": Color(0.65, 0.45, 0.25),
	"flying":  Color(0.45, 0.85, 0.95),
	"healer":  Color(0.45, 0.90, 0.55),
	"brute":   Color(0.55, 0.30, 0.30),
	"boss":    Color(0.95, 0.35, 0.55),
}

# Enemies that get a 1px orange ring drawn around their lane glyph — calls
# attention to load-bearing units in mixed-type waves.
const HEAVY_KEYS: Array[String] = ["boss", "brute", "armored"]

# Progression order (lightest / earliest → heaviest / boss). Used as the
# bottom-up stacking order for the per-bucket EHP bars: trash (basic) sits
# at the foundation, boss sits on top — visual hierarchy reads "weak below,
# strong above". Mirrors the slider list order in BalanceSliders so the eye
# learns one consistent layout.
const ENEMY_PROGRESSION: Array[String] = [
	"basic", "scout", "flying", "healer", "armored", "brute", "boss",
]

# ─── State ────────────────────────────────────────────────────────────────
var _wave: WaveData = null
var _level_data: Resource = null
var _wave_index: int = 0
# Two segmented supply dictionaries — keys: tower / hero / skills / control /
# total — already scaled to per-bucket damage by the caller. _supply_floor is
# the Naked Baseline reference (CORE RULE 18 floor); _supply_actual reflects
# the live LoadoutState. Both populated by BalanceSliders via player_supply_vector.
var _supply_floor: Dictionary = {}
var _supply_actual: Dictionary = {}
var _gold_at_start: int = 0
var _paths_in_level: Array = []   # ordered list of path_ids in the level
# Coverage-weighted pressure (canonical Tuning Console). -1.0 sentinel on
# _pressure_actual = "no data, fall back to legacy supply/demand ratio in
# the header." 0.0 on _pressure_target = unauthored target; verdict drops
# the drift and shows "(no target)" instead.
var _pressure_actual: float = -1.0
var _pressure_target: float = 0.0
var _pressure_reason: String = ""
# Concrete fix suggestion line shown below the header when verdict is bad.
# "" suppresses the lane visually (still 14 px tall — see FIX_LINE_Y).
var _pressure_fix: String = ""

# Cache per-scene EHP + gold_worth + class-key so we don't re-instantiate
# every redraw. Scoped to this chart instance — fine, six unique scenes max
# in practice.
var _enemy_hp_cache: Dictionary = {}      # scene_path → authored max_health (pre-override)
var _enemy_armor_cache: Dictionary = {}   # scene_path → authored armor (pre-override)
var _enemy_gold_cache: Dictionary = {}    # scene_path → authored gold_worth (int, pre-override)
var _enemy_id_cache: Dictionary = {}      # scene_path → enemy_id ("enemy_basic"/...)
var _enemy_class_cache: Dictionary = {}   # scene_path → "basic"/"scout"/...

# Derived per-redraw (kept on the instance so _draw is pure):
var _spawn_window_sec: float = 0.0
var _bucket_count: int = 0
var _bucket_ehp: Array = []               # Array[float], length = _bucket_count — total per bucket
# Stacked-by-class breakdown of each bucket. Element i is a Dictionary
# class_key → ehp_in_bucket_from_that_class. Sum of values == _bucket_ehp[i].
# Drives the stacked bar segments in _draw_demand_bars.
var _bucket_ehp_by_class: Array = []      # Array[Dictionary], length = _bucket_count
var _bucket_max_ehp: float = 0.0
var _required_damage: float = 0.0
# Cached peak supply totals (per-bucket, evaluated at the wave's END gold = the
# highest point of the income-adjusted curve). Used by _draw_demand_bars to set
# max_axis high enough that the sloped-band's peak doesn't pin to the chart
# top. Static "at start" totals are computed on the fly for the header display.
var _supply_floor_peak: float = 0.0
var _supply_actual_peak: float = 0.0
var _spawn_events: Array = []             # Array[{t: float, scene_path: String, path_id: String}]
# Per-wave cumulative gold timeline. Each entry {t, cumul} is a gold-rise
# event (one per enemy spawn = one bounty drop, plus wave.bounty at the end
# of the spawn window). Polyline drawn over the chart on a SHARED level-wide
# y-axis [0 … _level_final_gold], so stacked per-wave cards make the gold
# line look continuous: W2's line starts at the same height W1's ended.
var _gold_events: Array = []              # Array[{t: float, cumul: int}]
var _gold_at_wave_end: int = 0
# Final cumulative gold for the whole level. Anchors the gold y-axis so all
# per-wave charts share a scale. 0 = render the line at "no info" (skip).
var _level_final_gold: int = 0
var _composition_summary: String = ""
var _ratio_natural: float = 0.0

# Early-call band state — overlap-only redesign. The band lives INSIDE the
# spawn region's rightmost portion: start = spawn_end - early_call_window;
# end = spawn_end. Drag the band's LEFT edge to adjust the window.
# `_next_wave_gold_per_sec` drives the inline label and is mutable via
# scroll-wheel / context menu. Set via set_data; zero for the last wave.
var _next_wave_ec_window: float = 0.0
var _next_wave_gold_per_sec: float = 1.0
var _next_wave_authored_ec_window: float = 0.0
var _next_wave_authored_gold_per_sec: float = 1.0
var _has_next_wave: bool = false

# Cached during _draw so _gui_input can convert click coords back to the
# spawn-window or post-wave-gap x-axis without recomputing the split.
var _draw_spawn_x0: float = 0.0
var _draw_spawn_w: float = 0.0

# Drag state for the post-wave gap region.
enum GapDragMode { NONE, RIGHT_EDGE, EC_BOUNDARY }
var _gap_drag_mode: int = GapDragMode.NONE
var _gap_hover_zone: int = GapDragMode.NONE

# Emitted when the user clicks anywhere inside the chart's spawn-window
# region. BalanceSliders subscribes to this and shows the per-class
# +/- popup over that bucket.
signal bucket_clicked(wave_index: int, bucket_idx: int, t_start: float, t_end: float, screen_pos: Vector2)

# Emitted when the user drags / wheels / right-clicks the post-wave gap
# region. wave_index identifies THIS wave; the change targets THIS wave's
# successor (wave_index + 1). BalanceSliders writes the corresponding
# BalanceOverrides keys.
signal next_ec_window_changed(this_wave_index: int, new_seconds: float)
signal next_ec_gold_per_sec_changed(this_wave_index: int, new_rate: float)
# reset_window / reset_rate flags. Mirrors the band's two adjustable values.
signal next_reset_requested(this_wave_index: int, reset_window: bool, reset_rate: bool)


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# Drop the cached EnemyData snapshots so the next set_data re-instantiates
# each scene and reads fresh fields. Called by BalanceSliders after enemy
# bake — without this, EHP / gold / enemy_id reflect the PRE-bake authored
# values until the panel is closed and reopened.
func clear_enemy_caches() -> void:
	_enemy_hp_cache.clear()
	_enemy_armor_cache.clear()
	_enemy_gold_cache.clear()
	_enemy_id_cache.clear()
	_enemy_class_cache.clear()


# Public entry. Called by BalanceSliders after instantiation; can be called
# again to refresh after a slider change. `level_final_gold` is the level's
# total cumulative gold ceiling (starting + Σ bounties + drops), shared
# across all per-wave cards so the gold polyline looks continuous when the
# cards are stacked.
func set_data(wave: WaveData, level_data: Resource, wave_index: int,
		supply_floor: Dictionary, supply_actual: Dictionary,
		gold_at_start: int, paths_in_level: Array,
		level_final_gold: int = 0,
		next_wave_ec_window: float = 0.0,
		next_wave_authored_ec_window: float = 0.0,
		next_wave_gold_per_sec: float = 1.0,
		next_wave_authored_gold_per_sec: float = 1.0,
		has_next_wave: bool = false,
		pressure_actual: float = -1.0,
		pressure_target: float = 0.0,
		pressure_reason: String = "",
		pressure_fix: String = "") -> void:
	_wave = wave
	_level_data = level_data
	_wave_index = wave_index
	_supply_floor = supply_floor
	_supply_actual = supply_actual
	# Peaks are populated by _recompute once _gold_at_wave_end is known —
	# they're sampled at wave-end gold and drive max_axis + the header line.
	_supply_floor_peak = 0.0
	_supply_actual_peak = 0.0
	_gold_at_start = gold_at_start
	_paths_in_level = paths_in_level
	_level_final_gold = level_final_gold
	_next_wave_ec_window = max(0.0, next_wave_ec_window)
	_next_wave_authored_ec_window = max(0.0, next_wave_authored_ec_window)
	_next_wave_gold_per_sec = max(0.0, next_wave_gold_per_sec)
	_next_wave_authored_gold_per_sec = max(0.0, next_wave_authored_gold_per_sec)
	_has_next_wave = has_next_wave
	_pressure_actual = pressure_actual
	_pressure_target = pressure_target
	_pressure_reason = pressure_reason
	_pressure_fix = pressure_fix
	_recompute()
	_resize_for_paths()
	queue_redraw()


# Adjust card height so each path gets a lane (multi-path levels are taller).
# Vertical budget below the last lane: LANE_AXIS_GAP gap + 12px axis labels +
# 16px footer slot (footer text + 4px bottom margin) = 32px.
func _resize_for_paths() -> void:
	var lanes: int = max(1, _paths_in_level.size())
	var h: float = LANE_TOP + LANE_HEIGHT * lanes + 32.0
	custom_minimum_size = Vector2(CARD_MIN_WIDTH, h)


func _recompute() -> void:
	_bucket_ehp.clear()
	_bucket_ehp_by_class.clear()
	_bucket_max_ehp = 0.0
	_spawn_events.clear()
	_gold_events.clear()
	_gold_at_wave_end = _gold_at_start
	_required_damage = 0.0
	_spawn_window_sec = 0.0
	_composition_summary = ""
	_ratio_natural = 0.0
	if _wave == null:
		return
	# Pre-pass: compute the override-aware spawn window length by walking each
	# emitter and finding the latest spawn time with current interval/delay
	# overrides applied. bc.wave_spawn_timeline reads authored values only —
	# can't be reused once timing sliders are in play.
	var BO_timing: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var lvl_id_for_timing: String = ""
	if _level_data != null and "level_id" in _level_data:
		lvl_id_for_timing = String(_level_data.level_id)
	var max_spawn_t: float = 0.0
	for pre_si in range(_wave.spawns.size()):
		var pre_spawn: Resource = _wave.spawns[pre_si]
		if pre_spawn == null or pre_spawn.count <= 0:
			continue
		var pre_count_mult: float = 1.0
		var pre_delay: float = float(pre_spawn.start_delay)
		var pre_interval: float = float(pre_spawn.interval)
		if BO_timing != null and lvl_id_for_timing != "":
			pre_count_mult = BO_timing.get_wave_count_mult(lvl_id_for_timing, _wave_index, pre_si)
			var d_ov: float = BO_timing.get_wave_delay(lvl_id_for_timing, _wave_index, pre_si)
			if d_ov >= 0.0:
				pre_delay = d_ov
			var i_ov: float = BO_timing.get_wave_interval(lvl_id_for_timing, _wave_index, pre_si)
			if i_ov >= 0.0:
				pre_interval = i_ov
		var eff_count: int = max(0, int(round(float(pre_spawn.count) * pre_count_mult)))
		if eff_count <= 0:
			continue
		var last_t: float = pre_delay + float(eff_count - 1) * pre_interval
		if last_t > max_spawn_t:
			max_spawn_t = last_t
	_spawn_window_sec = max(max_spawn_t + 1.0, BUCKET_SEC)
	_bucket_count = int(ceil(_spawn_window_sec / BUCKET_SEC))
	_bucket_ehp.resize(_bucket_count)
	_bucket_ehp_by_class.resize(_bucket_count)
	for i in range(_bucket_count):
		_bucket_ehp[i] = 0.0
		_bucket_ehp_by_class[i] = {}
	# Walk every spawn-emitter and place enemies into buckets + lane events +
	# per-spawn gold drops. Each spawn-event also produces a gold-rise event
	# (kill-instantly assumption — bounty earned at spawn time). Sorted by time
	# at the end so the gold polyline is monotonic in t.
	# Per-emitter count override is applied here so bars / lane dots / gold
	# events all reflect the BalanceSliders Edit-emitters knob live.
	var BO_count: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var level_id_for_count: String = ""
	if _level_data != null and "level_id" in _level_data:
		level_id_for_count = String(_level_data.level_id)
	var class_counts: Dictionary = {}
	var raw_gold_events: Array = []
	var spawn_idx: int = -1
	for spawn in _wave.spawns:
		spawn_idx += 1
		if spawn == null or spawn.count <= 0 or spawn.enemy_scene == null:
			continue
		# Per-emitter overrides: count, interval, start_delay (all sentinel-safe).
		var count_mult: float = 1.0
		var effective_delay: float = float(spawn.start_delay)
		var effective_interval: float = float(spawn.interval)
		if BO_count != null and level_id_for_count != "":
			count_mult = BO_count.get_wave_count_mult(
				level_id_for_count, _wave_index, spawn_idx
			)
			var d_ov: float = BO_count.get_wave_delay(
				level_id_for_count, _wave_index, spawn_idx
			)
			if d_ov >= 0.0:
				effective_delay = d_ov
			var i_ov: float = BO_count.get_wave_interval(
				level_id_for_count, _wave_index, spawn_idx
			)
			if i_ov >= 0.0:
				effective_interval = i_ov
		var effective_count: int = max(0, int(round(float(spawn.count) * count_mult)))
		if effective_count <= 0:
			continue
		var ehp: float = _enemy_ehp_for(spawn.enemy_scene)
		var class_key: String = _enemy_class_for(spawn.enemy_scene)
		var gold: int = _enemy_gold_for(spawn.enemy_scene)
		class_counts[class_key] = int(class_counts.get(class_key, 0)) + effective_count
		for i in range(effective_count):
			var t: float = effective_delay + float(i) * effective_interval
			var b: int = clampi(int(t / BUCKET_SEC), 0, _bucket_count - 1)
			_bucket_ehp[b] += ehp
			var per_class: Dictionary = _bucket_ehp_by_class[b]
			per_class[class_key] = float(per_class.get(class_key, 0.0)) + ehp
			_spawn_events.append({"t": t, "class_key": class_key, "path_id": String(spawn.path_id)})
			if gold > 0:
				raw_gold_events.append({"t": t, "gold": gold})
	for v in _bucket_ehp:
		if float(v) > _bucket_max_ehp:
			_bucket_max_ehp = float(v)
	# Cumulative gold timeline. Sort kill events by time, accumulate, then add
	# wave.bounty as a final step at the end of the spawn window.
	raw_gold_events.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var running: int = _gold_at_start
	for ev in raw_gold_events:
		running += int(ev.gold)
		_gold_events.append({"t": float(ev.t), "cumul": running})
	var bounty: int = int(_wave.bounty) if "bounty" in _wave else 0
	if bounty > 0:
		running += bounty
		_gold_events.append({"t": _spawn_window_sec, "cumul": running})
	_gold_at_wave_end = running
	# Required damage. Sum bucket EHPs (override-aware) instead of
	# bc.wave_required_damage which reads authored counts only — the count
	# slider would otherwise show the wrong ratio.
	_required_damage = 0.0
	for v in _bucket_ehp:
		_required_damage += float(v)
	# Income-adjusted supply peaks: evaluate at gold_at_wave_end (the highest
	# point on the gold curve, hence the supply curve's ceiling). Drives the
	# chart's max_axis so the band's peak doesn't pin to the chart top.
	_supply_floor_peak = _supply_total_at_gold(_supply_floor, float(_gold_at_wave_end))
	_supply_actual_peak = _supply_total_at_gold(_supply_actual, float(_gold_at_wave_end))
	# Legacy ratio for the header fallback. Income-adjusted: take the AVERAGE
	# of supply-at-start and supply-at-end (linear ramp approximation), scale
	# up to the wave window, and compare to required damage. Better than the
	# old "all gold up-front" total it replaces.
	if _required_damage > 0.0 and _spawn_window_sec > 0.0:
		var actual_at_start: float = _supply_total_at_gold(_supply_actual, float(_gold_at_start))
		var avg_per_bucket: float = (actual_at_start + _supply_actual_peak) * 0.5
		var actual_total: float = avg_per_bucket * (_spawn_window_sec / BUCKET_SEC)
		_ratio_natural = actual_total / _required_damage
	# Composition summary footer line.
	var parts: PackedStringArray = []
	for k in class_counts.keys():
		parts.append("%s×%d" % [String(k), int(class_counts[k])])
	var paths_used: Dictionary = {}
	for ev in _spawn_events:
		paths_used[String(ev.path_id)] = true
	parts.append("%d path%s" % [paths_used.size(), "" if paths_used.size() == 1 else "s"])
	_composition_summary = " · ".join(parts)


# Sample cumulative gold at time t (seconds since wave start). Step function:
# walks _gold_events (each = {t, cumul} bounty drop or wave-bounty event) and
# returns the cumul value of the latest event with t_event <= t. Returns
# _gold_at_start when t precedes the first event. Used by the sloped supply
# band to know how much gold the player has accumulated at any moment.
func _gold_at_time(t: float) -> float:
	var g: float = float(_gold_at_start)
	for ev in _gold_events:
		if float(ev.t) > t:
			break
		g = float(ev.cumul)
	return g


# Resolve a supply Dictionary's total at a given gold level. Tower and control
# scale linearly with gold (more gold → more towers → more DPS); hero and
# skills are gold-independent constants. Per 5s bucket.
func _supply_total_at_gold(d: Dictionary, gold: float) -> float:
	return float(d.get("tower_per_gold",   0.0)) * gold \
		+ float(d.get("control_per_gold", 0.0)) * gold \
		+ float(d.get("hero_const",       0.0)) \
		+ float(d.get("skills_const",     0.0))


# Per-enemy physical EHP, cached by scene_path. Instantiates once per unique
# scene to read the .data resource, then frees the node. Also populates the
# gold_worth cache from the same instantiation — saves a second instantiate
# in _enemy_gold_for.
func _enemy_ehp_for(scene: PackedScene) -> float:
	if scene == null:
		return 0.0
	var path: String = scene.resource_path
	# Cache AUTHORED hp + armor separately (pre-override), so override stack
	# can be applied freshly on every call. Without this, sliders would
	# require cache invalidation on every drag — slower AND more error-
	# prone than just doing the multiply on read.
	if not _enemy_hp_cache.has(path):
		var inst: Node = scene.instantiate()
		var hp_raw: float = 0.0
		var armor_raw: float = 0.0
		var gold_worth: int = 0
		var enemy_id: String = ""
		if "data" in inst and inst.data != null:
			var d = inst.data
			hp_raw = float(d.max_health) if "max_health" in d else 0.0
			armor_raw = float(d.armor) if "armor" in d else 0.0
			gold_worth = int(d.gold_worth) if "gold_worth" in d else 0
			enemy_id = String(d.enemy_id) if "enemy_id" in d else ""
		inst.queue_free()
		_enemy_hp_cache[path] = hp_raw
		_enemy_armor_cache[path] = armor_raw
		_enemy_gold_cache[path] = gold_worth
		_enemy_id_cache[path] = enemy_id
	# Override stack — applied on every call so slider tweaks are live.
	#   HP:    authored × global hp_mult × per-level hp_mult × per-enemy hp_mult
	#   Armor: authored + global armor_add + per-enemy armor_add (clamp 0..0.95)
	# Mirrors BaseEnemy._ready (HP) + BaseEnemy.get_effective_armor (armor).
	var BO: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var enemy_id_now: String = String(_enemy_id_cache.get(path, ""))
	var hp: float = float(_enemy_hp_cache.get(path, 0.0))
	var armor: float = float(_enemy_armor_cache.get(path, 0.0))
	if BO != null:
		hp *= BO.get_hp_mult()
		if _level_data != null and "level_id" in _level_data and String(_level_data.level_id) != "":
			hp *= BO.get_level_float(String(_level_data.level_id), "hp_mult", 1.0)
		if enemy_id_now != "":
			hp *= BO.get_enemy_mult(enemy_id_now, "hp_mult")
		armor += BO.get_armor_add()
		if enemy_id_now != "":
			armor += BO.get_enemy_mult(enemy_id_now, "armor_add")
	armor = clampf(armor, 0.0, 0.95)
	return hp / max(0.05, 1.0 - armor)


# Override-aware gold drop on kill. Authored gold_worth × per-enemy gold_mult
# from BalanceOverrides — keeps the chart's cumul-gold curve in sync with the
# slider tweaks (without this, the curve plotted authored values even when
# the in-game runtime correctly applied the override).
func _enemy_gold_for(scene: PackedScene) -> int:
	if scene == null:
		return 0
	var path: String = scene.resource_path
	if not _enemy_gold_cache.has(path):
		_enemy_ehp_for(scene)  # populates ehp + gold + id together
	var raw: int = int(_enemy_gold_cache.get(path, 0))
	if raw <= 0:
		return 0
	var enemy_id: String = String(_enemy_id_cache.get(path, ""))
	var BO: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var mult: float = BO.get_enemy_mult(enemy_id, "gold_mult") if BO != null else 1.0
	return int(round(float(raw) * mult))


# Map enemy_scene's resource_path to a class-key for lane color + heavy ring.
# Matches against the basename so future renames stay forgiving.
func _enemy_class_for(scene: PackedScene) -> String:
	if scene == null:
		return "basic"
	var path: String = scene.resource_path
	if _enemy_class_cache.has(path):
		return String(_enemy_class_cache[path])
	var lower: String = path.to_lower()
	var key: String = "basic"
	if lower.contains("boss"):
		key = "boss"
	elif lower.contains("scout"):
		key = "scout"
	elif lower.contains("armor"):
		key = "armored"
	elif lower.contains("flying"):
		key = "flying"
	elif lower.contains("brute"):
		key = "brute"
	elif lower.contains("healer"):
		key = "healer"
	_enemy_class_cache[path] = key
	return key


# ─── Drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	if _wave == null:
		return
	var w: float = size.x
	var early_window: float = 10.0
	if _level_data != null and "early_call_window_sec" in _level_data:
		early_window = float(_level_data.early_call_window_sec)
	# Resolve effective window via the same chain WaveManager uses, so chart
	# visuals match what the player will actually get during play.
	if _level_data != null and "level_id" in _level_data and String(_level_data.level_id) != "":
		var lvl_id: String = String(_level_data.level_id)
		var BO_lvl: GDScript = load("res://balance/debug/BalanceOverrides.gd")
		if BO_lvl != null:
			# Default = level authored. Overridden in priority order below.
			# 1 (lowest): per-level debug override.
			var ec_ov: int = BO_lvl.get_level_int(lvl_id, "early_call_window", -1)
			if ec_ov >= 0:
				early_window = float(ec_ov)
			# 2: per-wave authored on WaveData.
			if "early_call_window_sec" in _wave and _wave.early_call_window_sec >= 0.0:
				early_window = float(_wave.early_call_window_sec)
			# 3 (highest): per-wave debug override.
			var w_ec_ov: float = BO_lvl.get_wave_early_call_window(lvl_id, _wave_index)
			if w_ec_ov >= 0.0:
				early_window = w_ec_ov
	# Overlap-only redesign: no preceding-gap and no post-spawn-gap regions.
	# The chart's x-axis is purely the spawn window. The early-call BAND lives
	# inside the spawn region's right end (start = spawn_end - ec_window).
	if _spawn_window_sec <= 0.0:
		return
	var usable: float = w - PAD_X * 2.0
	var spawn_x0: float = PAD_X
	var spawn_w: float = usable
	_draw_spawn_x0 = spawn_x0
	_draw_spawn_w = spawn_w

	_draw_header(w, early_window)
	_draw_fix_line(w)
	_draw_bucket_backgrounds(spawn_x0, spawn_w)
	_draw_demand_bars(spawn_x0, spawn_w)
	_draw_supply_bands(spawn_x0, spawn_w)
	_draw_gold_curve(spawn_x0, spawn_w)
	_draw_wave_start_line(spawn_x0)
	_draw_path_lanes(spawn_x0, spawn_w)
	_draw_time_axis(spawn_x0, spawn_w)
	if _has_next_wave and _next_wave_ec_window > 0.0:
		_draw_inspawn_band(spawn_x0, spawn_w)
	_draw_footer(w)


# Inverse-pressure fix suggestion drawn below the header in a reserved
# 14 px lane. Empty string → blank lane (kept reserved so cards stay aligned).
# Color matches the verdict band so the eye links the suggestion to the
# header's drift number above.
func _draw_fix_line(w: float) -> void:
	if _pressure_fix == "":
		return
	var font: Font = ThemeDB.fallback_font
	var col: Color = COL_HEADER_OK
	if _pressure_actual >= 0.0 and _pressure_target > 0.0:
		col = WaveDamageSimulator.drift_verdict(_pressure_actual, _pressure_target)["color"]
	# Slightly dimmer than the header — this is a how-to-fix annotation, not
	# a verdict.
	col = col.lerp(Color(0.85, 0.85, 0.85), 0.35)
	draw_string(font, Vector2(PAD_X + 8.0, FIX_LINE_Y + FIX_LINE_H - 2),
		_pressure_fix, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0,
		FIX_LINE_FONT, col)


func _draw_header(w: float, early_window: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var col: Color = COL_HEADER_OK
	# Pressure block — canonical Tuning Console verdict when the parent
	# screen supplied coverage-weighted numbers via set_data; otherwise
	# fall back to the legacy supply/demand ratio so isolated callers
	# (or any unconverted code) still see something.
	var pressure_block: String
	if _pressure_actual >= 0.0:
		var verdict: Dictionary = WaveDamageSimulator.drift_verdict(_pressure_actual, _pressure_target)
		col = verdict["color"]
		if bool(verdict["has_target"]):
			var drift: float = (_pressure_actual - _pressure_target) / _pressure_target
			pressure_block = "pressure %.2f / target %.2f · %+d%% %s" % [
				_pressure_actual, _pressure_target,
				int(round(drift * 100.0)), String(verdict["label"]),
			]
		else:
			pressure_block = "pressure %.2f · (no target)" % _pressure_actual
		if _pressure_reason != "":
			pressure_block += " · " + _pressure_reason
	else:
		var ratio_str: String = "—" if _ratio_natural <= 0.0 else "%.2f" % _ratio_natural
		var flag: String = ""
		if _ratio_natural > 0.0 and _ratio_natural < 1.0:
			flag = "  ⚠ supply<demand"
			col = COL_HEADER_WARN
		pressure_block = "ratio %s%s" % [ratio_str, flag]
	# Income-adjusted supply totals scaled back to the wave window for parity
	# with req_dmg. Sloped band → two numbers: at-start (low) and at-end (peak).
	# avg = (start + peak) / 2 ≈ total damage budget under the linear-ramp
	# assumption. Per-bucket → window: × (spawn_window / BUCKET_SEC).
	var window_ratio: float = _spawn_window_sec / BUCKET_SEC if _spawn_window_sec > 0.0 else 1.0
	var supply_block: String = ""
	if _supply_actual_peak > 0.0 or _supply_floor_peak > 0.0:
		var actual_at_start: float = _supply_total_at_gold(_supply_actual, float(_gold_at_start)) * window_ratio
		var actual_at_end: float = _supply_actual_peak * window_ratio
		var floor_at_start: float = _supply_total_at_gold(_supply_floor, float(_gold_at_start)) * window_ratio
		var floor_at_end: float = _supply_floor_peak * window_ratio
		# Breakdown reported at WAVE END (the peak — the most informative point).
		var t: float = float(_supply_actual.get("tower_per_gold",   0.0)) * float(_gold_at_wave_end) * window_ratio
		var h: float = float(_supply_actual.get("hero_const",       0.0)) * window_ratio
		var s: float = float(_supply_actual.get("skills_const",     0.0)) * window_ratio
		var k: float = float(_supply_actual.get("control_per_gold", 0.0)) * float(_gold_at_wave_end) * window_ratio
		supply_block = " · supply %.0f→%.0f [end: T %.0f H %.0f S %.0f C %.0f] vs floor %.0f→%.0f" % [
			actual_at_start, actual_at_end, t, h, s, k, floor_at_start, floor_at_end,
		]
	var head: String = "W%d — %.0fs spawn window · req %.0f dmg%s · %s" % [
		_wave_index + 1, _spawn_window_sec, _required_damage, supply_block, pressure_block,
	]
	if early_window > 0.0:
		head += "   (%.0fs early-call · max bonus %.0fg)" % [early_window, early_window]
	draw_string(font, Vector2(PAD_X, HEADER_Y + HEADER_H - 2),
		head, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, HEADER_FONT_SIZE, col)


func _draw_bucket_backgrounds(spawn_x0: float, spawn_w: float) -> void:
	# Hairline 5s ticks at each bucket boundary. Replaces the alternating-stripe
	# backgrounds (chartjunk per Tufte / Few — they double the non-data ink and
	# make bar heights harder to compare across the boundary). The ticks alone
	# preserve the time-grid affordance with ~5% the visual noise.
	if _bucket_count <= 0:
		return
	var bw: float = spawn_w / float(_bucket_count)
	var top: float = CHART_TOP
	var bot: float = CHART_BOTTOM
	for i in range(_bucket_count + 1):
		var x: float = spawn_x0 + bw * float(i)
		draw_line(Vector2(x, top), Vector2(x, bot), COL_BUCKET_TICK, 1.0, false)


func _draw_demand_bars(spawn_x0: float, spawn_w: float) -> void:
	if _bucket_count <= 0 or _bucket_max_ehp <= 0.0:
		return
	# Y-axis = damage per 5s bucket. Bars and BOTH supply bands (floor and
	# actual) live in this unit. Use the sloped bands' PEAK (= supply at
	# wave-end gold) so the band's high point doesn't pin to the chart top.
	# Headroom = ×1.15 so nothing pins to the edge.
	var max_axis: float = max(_bucket_max_ehp,
		max(_supply_floor_peak, _supply_actual_peak)) * 1.15
	if max_axis <= 0.0:
		return
	var chart_h: float = CHART_BOTTOM - CHART_TOP
	var bw: float = spawn_w / float(_bucket_count)
	# Progression-ordered stacking: basic at the foundation, boss on top.
	# Same order on every wave so the eye learns the layout. Matches the
	# Enemy slider list in BalanceSliders.
	var class_order: Array = ENEMY_PROGRESSION
	for i in range(_bucket_count):
		var ehp_total: float = float(_bucket_ehp[i])
		if ehp_total <= 0.0:
			continue
		var bx: float = spawn_x0 + bw * float(i) + 1.0
		var bw_inner: float = bw - 2.0
		# Stack bottom-up. Each class's segment height is proportional to its
		# share of this bucket's total EHP.
		var per_class: Dictionary = _bucket_ehp_by_class[i]
		var cursor_y: float = CHART_BOTTOM
		for class_key in class_order:
			var class_ehp: float = float(per_class.get(class_key, 0.0))
			if class_ehp <= 0.0:
				continue
			var seg_h: float = (class_ehp / max_axis) * (chart_h - 2.0)
			if seg_h < 0.5:  # don't render slivers; they read as fuzz
				continue
			var seg_y: float = cursor_y - seg_h
			var seg_col: Color = ENEMY_COLORS.get(class_key, Color(0.55, 0.55, 0.55))
			draw_rect(Rect2(bx, seg_y, bw_inner, seg_h), seg_col, true)
			# Hairline outline between segments — separates same-shade colors
			# (e.g. healer + flying both green-cyan) at small bar heights.
			if seg_y > CHART_TOP + 1.0:
				draw_line(
					Vector2(bx, seg_y), Vector2(bx + bw_inner, seg_y),
					COL_BAR_OUTLINE, 1.0, false,
				)
			cursor_y = seg_y


func _draw_supply_bands(spawn_x0: float, spawn_w: float) -> void:
	# INCOME-ADJUSTED THEORETICAL SUPPLY. Two stacked sloped bands: a faint
	# Naked Baseline floor and a stronger live-loadout actual. Each band's
	# height at any time t = (gold_at_t × tower_per_gold) + (gold_at_t ×
	# control_per_gold) + hero_const + skills_const. Tower and control segments
	# rise with the gold curve (more bounties → more towers → more DPS); hero
	# and skills sit underneath as constant slabs (loadout-fixed).
	#
	# Caveat: the gold curve models bounties as arriving at SPAWN time, not
	# actual death time, so the slope is slightly optimistic at each wave's
	# leading edge. Acceptable for a designer tool.
	var max_axis: float = max(_bucket_max_ehp,
		max(_supply_floor_peak, _supply_actual_peak)) * 1.15
	if max_axis <= 0.0 or _bucket_count <= 0 or _spawn_window_sec <= 0.0:
		return
	# Floor band first so the actual band overlays it where they share y-range.
	_draw_one_supply_band(spawn_x0, spawn_w, _supply_floor, max_axis,
		0.10, COL_SUPPLY_TOP_FLOOR)
	_draw_one_supply_band(spawn_x0, spawn_w, _supply_actual, max_axis,
		0.22, COL_SUPPLY_TOP_ACTUAL)


# Draw ONE income-adjusted supply band. For each 5s bucket [t_i, t_{i+1}]:
# sample the gold curve at the bucket's MIDPOINT, compute supply at that gold,
# and paint stacked tower/hero/skills/control segments up to that height.
# Then draw a dashed polyline through the bucket BOUNDARIES showing the total
# ceiling. Mid-vs-boundary mirrors the user's spec: filled = midpoint sample
# (representative supply during that bucket); top line = boundary samples
# (smooth ramp). A faint flat reference at supply-at-start helps debug whether
# the slope is doing what we expect.
func _draw_one_supply_band(spawn_x0: float, spawn_w: float, supply: Dictionary,
		max_axis: float, alpha: float, top_color: Color) -> void:
	var peak: float = _supply_total_at_gold(supply, float(_gold_at_wave_end))
	if peak <= 0.0:
		return
	var chart_h: float = CHART_BOTTOM - CHART_TOP
	var bw: float = spawn_w / float(_bucket_count)
	# Filled segments per bucket, sampled at midpoint.
	for i in range(_bucket_count):
		var t_mid: float = (float(i) + 0.5) * BUCKET_SEC
		var gold_mid: float = _gold_at_time(t_mid)
		# Stack bottom-up: tower (gold-scaled) → hero (const) → skills (const)
		# → control (gold-scaled). Same order as the header breakdown.
		var tower_v: float = float(supply.get("tower_per_gold",   0.0)) * gold_mid
		var hero_v: float  = float(supply.get("hero_const",       0.0))
		var skill_v: float = float(supply.get("skills_const",     0.0))
		var ctrl_v: float  = float(supply.get("control_per_gold", 0.0)) * gold_mid
		var segs: Array = [
			[tower_v, COL_SUPPLY_TOWER],
			[hero_v,  COL_SUPPLY_HERO],
			[skill_v, COL_SUPPLY_SKILLS],
			[ctrl_v,  COL_SUPPLY_CONTROL],
		]
		var bx: float = spawn_x0 + bw * float(i)
		var cursor_y: float = CHART_BOTTOM
		for seg in segs:
			var v: float = float(seg[0])
			if v <= 0.0:
				continue
			var seg_h: float = (v / max_axis) * (chart_h - 2.0)
			if seg_h < 0.5:
				continue
			var seg_y: float = cursor_y - seg_h
			var col: Color = seg[1]
			col.a = alpha
			draw_rect(Rect2(bx, seg_y, bw, seg_h), col, true)
			cursor_y = seg_y
	# Top dashed polyline through bucket boundaries — supply ceiling smooth ramp.
	var poly: PackedVector2Array = []
	for i in range(_bucket_count + 1):
		var t_b: float = float(i) * BUCKET_SEC
		var total_at_b: float = _supply_total_at_gold(supply, _gold_at_time(t_b))
		var x: float = spawn_x0 + bw * float(i)
		var y: float = CHART_BOTTOM - (total_at_b / max_axis) * (chart_h - 2.0)
		poly.append(Vector2(x, y))
	if poly.size() >= 2:
		# Per-segment dashing so the polyline reads as a threshold, not a curve
		# (matches the prior dashed flat line's visual language).
		for i in range(poly.size() - 1):
			draw_dashed_line(poly[i], poly[i + 1], top_color, 1.0, 4.0, true)
	# Faint flat reference at supply-at-start — debug aid that lets the
	# designer see the slope's *delta* relative to the legacy "all-gold-up-front"
	# baseline. Half the alpha of the band's own top line.
	var total_at_start: float = _supply_total_at_gold(supply, float(_gold_at_start))
	if total_at_start > 0.0:
		var ref_y: float = CHART_BOTTOM - (total_at_start / max_axis) * (chart_h - 2.0)
		var ref_col: Color = top_color
		ref_col.a *= 0.40
		draw_dashed_line(
			Vector2(spawn_x0, ref_y), Vector2(spawn_x0 + spawn_w, ref_y),
			ref_col, 1.0, 8.0, true,
		)


func _draw_wave_start_line(spawn_x0: float) -> void:
	draw_line(
		Vector2(spawn_x0, CHART_TOP - 2.0),
		Vector2(spawn_x0, CHART_BOTTOM + 2.0),
		COL_WAVE_START, WAVE_START_LINE_W, true,
	)


# Cumulative gold growth across the whole level, sliced into this wave's
# time window. Y-axis is shared across all per-wave cards: bottom = 0,
# top = _level_final_gold. Result: when cards are stacked vertically, the
# gold line position at the right edge of card N matches the position at
# the left edge of card N+1 — visually continuous, matching the actual
# monotonic gold accumulation. Trade-off: early-wave slopes are small in
# absolute terms (because the deltas ARE small); endpoint dot anchors the
# eye when the slope barely visually moves.
#
# Anchors the curve at gold_at_wave_start at the spawn window's left edge so
# the player's wallet entering the wave is plotted before any enemies spawn.
func _draw_gold_curve(spawn_x0: float, spawn_w: float) -> void:
	if _level_final_gold <= 0:
		return
	if _spawn_window_sec <= 0.0:
		return
	# Polyline lives just inside the chart band so it doesn't bleed into the
	# bucket ticks above CHART_TOP or the path-lane area below CHART_BOTTOM.
	var top_y: float = CHART_TOP + 1.0
	var bot_y: float = CHART_BOTTOM - 1.0
	var y_for_g: Callable = func(g: float) -> float:
		var f: float = clampf(g / float(_level_final_gold), 0.0, 1.0)
		return bot_y - f * (bot_y - top_y)
	# Carry-over flat segment in the pre-wave region: line at the wave-start
	# gold height, drawn from the left card edge to the wave-start vertical.
	var start_y: float = y_for_g.call(float(_gold_at_start))
	if spawn_x0 > PAD_X + 0.5:
		draw_line(Vector2(PAD_X, start_y), Vector2(spawn_x0, start_y),
			COL_GOLD_CURVE, 1.5, true)
	# Rising polyline through the spawn window.
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(spawn_x0, start_y))
	for ev in _gold_events:
		var t: float = float(ev.t)
		var g: float = float(ev.cumul)
		var x: float = spawn_x0 + clampf(t / _spawn_window_sec, 0.0, 1.0) * spawn_w
		pts.append(Vector2(x, y_for_g.call(g)))
	if _gold_events.is_empty() or float(_gold_events.back().t) < _spawn_window_sec - 0.01:
		pts.append(Vector2(spawn_x0 + spawn_w, y_for_g.call(float(_gold_at_wave_end))))
	draw_polyline(pts, COL_GOLD_CURVE, 1.5, true)
	# Endpoint dots — start and end anchor points so the absolute height is
	# readable even when the slope is small (early waves).
	draw_circle(Vector2(spawn_x0, start_y), 2.0, COL_GOLD_CURVE_DOT)
	if pts.size() > 1:
		draw_circle(pts[pts.size() - 1], 2.0, COL_GOLD_CURVE_DOT)


func _draw_path_lanes(spawn_x0: float, spawn_w: float) -> void:
	# One horizontal strip per path_id in the level. Glyph at each spawn time.
	var lanes: int = max(1, _paths_in_level.size())
	for li in range(lanes):
		var lane_y: float = LANE_TOP + LANE_HEIGHT * float(li) + LANE_HEIGHT * 0.5
		# Faint baseline so empty lanes still read as "this path exists".
		draw_line(
			Vector2(spawn_x0, lane_y), Vector2(spawn_x0 + spawn_w, lane_y),
			Color(0.25, 0.27, 0.30, 1.0), 1.0, true,
		)
	for ev in _spawn_events:
		var path_id: String = String(ev.path_id)
		var li2: int = _paths_in_level.find(path_id)
		if li2 < 0:
			li2 = 0  # fall back to first lane if path isn't registered
		var lane_y2: float = LANE_TOP + LANE_HEIGHT * float(li2) + LANE_HEIGHT * 0.5
		var t: float = float(ev.t)
		var cx: float = spawn_x0 + (t / _spawn_window_sec) * spawn_w
		var key: String = String(ev.class_key)
		var col: Color = ENEMY_COLORS.get(key, Color(0.55, 0.55, 0.55))
		draw_circle(Vector2(cx, lane_y2), 2.5, col)
		if HEAVY_KEYS.has(key):
			draw_arc(Vector2(cx, lane_y2), 4.0, 0.0, TAU, 12, Color(1.0, 0.6, 0.2, 0.9), 1.0, true)


# Time-axis label row beneath the path lanes. One label per 5s bucket
# boundary ("0s · 5s · 10s · …"). When the spawn window has more than 9
# buckets (>45s) we step every-other label so adjacent labels don't overlap.
func _draw_time_axis(spawn_x0: float, spawn_w: float) -> void:
	if _bucket_count <= 0 or _spawn_window_sec <= 0.0:
		return
	var lanes: int = max(1, _paths_in_level.size())
	var lane_bottom: float = LANE_TOP + LANE_HEIGHT * float(lanes)
	var baseline_y: float = lane_bottom + LANE_AXIS_GAP
	var font: Font = ThemeDB.fallback_font
	var step: int = 1 if _bucket_count <= 9 else 2
	var bw: float = spawn_w / float(_bucket_count)
	for i in range(_bucket_count + 1):
		if i % step != 0 and i != _bucket_count:
			continue
		var t_sec: int = int(round(float(i) * BUCKET_SEC))
		var label: String = "%ds" % t_sec
		var x: float = spawn_x0 + bw * float(i)
		# Center each label horizontally on its bucket boundary by shifting left
		# by half its rendered width.
		var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, AXIS_LABEL_FONT_SIZE).x
		draw_string(font, Vector2(x - label_w * 0.5, baseline_y),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_LABEL_FONT_SIZE, COL_FOOTER)


# In-spawn early-call band. Lives INSIDE the spawn region's right end:
# starts at `spawn_end - ec_window`, ends at `spawn_end`. Solid green at the
# LEFT edge (max overlap = max bonus when player presses right after band
# opens) → transparent at the RIGHT edge (no overlap, no bonus). Drag the
# LEFT edge to grow / shrink the early-call window.
const COL_BAND_HOVER_HANDLE: Color = Color(1.0, 0.95, 0.5, 0.9)
const COL_BAND_HANDLE_IDLE: Color = Color(0.55, 0.60, 0.68, 0.55)


func _draw_inspawn_band(spawn_x0: float, spawn_w: float) -> void:
	if not _has_next_wave or _next_wave_ec_window <= 0.0 or spawn_w <= 0.0:
		return
	if _spawn_window_sec <= 0.0:
		return
	var top: float = CHART_TOP
	var bot: float = CHART_BOTTOM
	# Window can't exceed the spawn window — clamp the visual.
	var window: float = min(_next_wave_ec_window, _spawn_window_sec)
	var band_w: float = (window / _spawn_window_sec) * spawn_w
	var band_x0: float = spawn_x0 + spawn_w - band_w
	# Green fade: solid at LEFT edge (max bonus / max overlap) → transparent
	# at RIGHT edge (no bonus / no overlap). 8-slice gradient.
	var steps: int = 8
	for i in range(steps):
		var f: float = float(i) / float(steps - 1)  # 0 = full, 1 = fade
		var seg_x: float = band_x0 + band_w * (float(i) / float(steps))
		var seg_w: float = band_w / float(steps) + 0.5
		var c: Color = COL_EARLYCALL_FULL.lerp(COL_EARLYCALL_FADE, f)
		draw_rect(Rect2(seg_x, top, seg_w, bot - top), c, true)
	# Left-edge drag handle marker (right edge is fixed at spawn end).
	var left_active: bool = _gap_hover_zone == GapDragMode.EC_BOUNDARY or _gap_drag_mode == GapDragMode.EC_BOUNDARY
	var left_color: Color = COL_BAND_HOVER_HANDLE if left_active else COL_BAND_HANDLE_IDLE
	var left_lw: float = 3.0 if left_active else 1.0
	draw_line(Vector2(band_x0, top), Vector2(band_x0, bot), left_color, left_lw, false)
	# Inline label beneath the band.
	var font: Font = ThemeDB.fallback_font
	var label: String = "early-call: %.0fs · %.1fg/s  (next wave)" % [
		_next_wave_ec_window, _next_wave_gold_per_sec
	]
	var lbl_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 10).x
	# Right-align the label with the spawn end so it stays anchored to the
	# band's visual context as the band grows / shrinks.
	var lbl_x: float = spawn_x0 + spawn_w - lbl_w
	draw_string(font, Vector2(lbl_x, bot + 12), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, COL_FOOTER)


# Returns the band zone under a screen position. Only LEFT edge is draggable;
# right edge is fixed at the spawn end.
func _gap_zone_at(pos: Vector2) -> int:
	if not _has_next_wave or _next_wave_ec_window <= 0.0:
		return GapDragMode.NONE
	if pos.y < CHART_TOP - 4 or pos.y > CHART_BOTTOM + 4:
		return GapDragMode.NONE
	if _spawn_window_sec <= 0.0 or _draw_spawn_w <= 0.0:
		return GapDragMode.NONE
	var window: float = min(_next_wave_ec_window, _spawn_window_sec)
	var band_w: float = (window / _spawn_window_sec) * _draw_spawn_w
	var band_x0: float = _draw_spawn_x0 + _draw_spawn_w - band_w
	if abs(pos.x - band_x0) <= 8.0:
		return GapDragMode.EC_BOUNDARY  # left edge of band = window length
	return GapDragMode.NONE


# True if a position is inside the band's body — used to gate scroll wheel
# and right-click handlers.
func _is_inside_band(pos: Vector2) -> bool:
	if not _has_next_wave or _next_wave_ec_window <= 0.0:
		return false
	if pos.y < CHART_TOP or pos.y > CHART_BOTTOM:
		return false
	if _spawn_window_sec <= 0.0:
		return false
	var window: float = min(_next_wave_ec_window, _spawn_window_sec)
	var band_w: float = (window / _spawn_window_sec) * _draw_spawn_w
	var band_x0: float = _draw_spawn_x0 + _draw_spawn_w - band_w
	return pos.x >= band_x0 and pos.x <= _draw_spawn_x0 + _draw_spawn_w


# Map an x-pixel inside the spawn window region to a bucket index. Returns
# -1 if x is outside the window (in pre-wave / margin / past end).
func _bucket_at_x(x: float) -> int:
	if _draw_spawn_w <= 0.0 or _bucket_count <= 0:
		return -1
	if x < _draw_spawn_x0 or x > _draw_spawn_x0 + _draw_spawn_w:
		return -1
	var bw: float = _draw_spawn_w / float(_bucket_count)
	var idx: int = int(floor((x - _draw_spawn_x0) / bw))
	return clampi(idx, 0, _bucket_count - 1)


func _gui_input(event: InputEvent) -> void:
	# Mouse motion: handle drag continuation OR hover update for cursor +
	# handle highlight on the post-wave gap region.
	if event is InputEventMouseMotion:
		if _gap_drag_mode != GapDragMode.NONE:
			_continue_gap_drag(event.position.x, event.ctrl_pressed)
			accept_event()
			return
		var z: int = _gap_zone_at(event.position)
		if z != _gap_hover_zone:
			_gap_hover_zone = z
			match z:
				GapDragMode.RIGHT_EDGE, GapDragMode.EC_BOUNDARY:
					mouse_default_cursor_shape = Control.CURSOR_HSIZE
				_:
					mouse_default_cursor_shape = Control.CURSOR_ARROW
			queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	# Mouse wheel — when cursor is on the early-call band: plain = ±1s on
	# window, shift = ±0.1 on gold_per_sec.
	if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if _is_inside_band(event.position):
			var dir: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if event.shift_pressed:
				next_ec_gold_per_sec_changed.emit(_wave_index,
					max(0.0, _next_wave_gold_per_sec + 0.1 * float(dir)))
			else:
				next_ec_window_changed.emit(_wave_index,
					max(0.0, _next_wave_ec_window + float(dir)))
			accept_event()
			return
	# Right-click on band → context menu.
	if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _gap_zone_at(event.position) != GapDragMode.NONE \
				or _is_inside_band(event.position):
			_show_gap_context_menu()
			accept_event()
			return
	# Left-click on gap edge → start drag. Otherwise fall through to bucket
	# click (existing behavior).
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var gz: int = _gap_zone_at(event.position)
			if gz != GapDragMode.NONE:
				_gap_drag_mode = gz
				accept_event()
				return
		else:
			if _gap_drag_mode != GapDragMode.NONE:
				_gap_drag_mode = GapDragMode.NONE
				queue_redraw()
				accept_event()
				return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var b: int = _bucket_at_x(event.position.x)
	if b < 0:
		return
	# Hit-test must also be inside the chart band (vertically) — clicks above
	# the bars or on the lane row / footer should NOT spawn the popup.
	if event.position.y < CHART_TOP or event.position.y > CHART_BOTTOM:
		return
	var t_start: float = float(b) * BUCKET_SEC
	var t_end: float = float(b + 1) * BUCKET_SEC
	var screen_pos: Vector2 = get_global_mouse_position()
	bucket_clicked.emit(_wave_index, b, t_start, t_end, screen_pos)
	accept_event()


func _continue_gap_drag(x: float, ctrl_held: bool) -> void:
	# Only the band's LEFT edge is draggable (= ec_window length). Right
	# edge is fixed at the spawn end. Cursor x → time-from-spawn-start →
	# ec_window = spawn_window - that_time.
	if _spawn_window_sec <= 0.0 or _draw_spawn_w <= 0.0:
		return
	if _gap_drag_mode != GapDragMode.EC_BOUNDARY:
		return
	var snap: float = 0.1 if ctrl_held else 1.0
	# Cursor's time on the spawn axis [0, spawn_window].
	var t_at_cursor: float = clampf((x - _draw_spawn_x0) / _draw_spawn_w * _spawn_window_sec,
		0.0, _spawn_window_sec)
	var new_window: float = clampf(_spawn_window_sec - t_at_cursor, 0.0, _spawn_window_sec)
	new_window = round(new_window / snap) * snap
	next_ec_window_changed.emit(_wave_index, new_window)


func _show_gap_context_menu() -> void:
	var menu := PopupMenu.new()
	var has_ec_override: bool = abs(_next_wave_ec_window - _next_wave_authored_ec_window) > 0.001
	var has_rate_override: bool = abs(_next_wave_gold_per_sec - _next_wave_authored_gold_per_sec) > 0.001
	menu.add_item("Reset early-call window", 0)
	menu.set_item_disabled(0, not has_ec_override)
	menu.add_item("Reset gold per second", 1)
	menu.set_item_disabled(1, not has_rate_override)
	menu.add_separator()
	menu.add_item("Reset both", 2)
	menu.set_item_disabled(3, not (has_ec_override or has_rate_override))
	var wave_idx: int = _wave_index
	menu.id_pressed.connect(func(id: int):
		match id:
			0: next_reset_requested.emit(wave_idx, true, false)
			1: next_reset_requested.emit(wave_idx, false, true)
			2: next_reset_requested.emit(wave_idx, true, true)
		menu.queue_free())
	menu.close_requested.connect(func(): menu.queue_free())
	add_child(menu)
	var screen_pos: Vector2 = get_global_mouse_position()
	var win: Window = get_window()
	var origin: Vector2i = Vector2i(screen_pos)
	if win != null:
		origin += win.position
	menu.popup(Rect2i(origin, Vector2i(0, 0)))


func _draw_footer(w: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var y: float = size.y - FOOTER_Y_FROM_BOTTOM
	draw_string(font, Vector2(PAD_X, y),
		_composition_summary, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, FOOTER_FONT_SIZE, COL_FOOTER)
