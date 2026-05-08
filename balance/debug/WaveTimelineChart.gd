extends Control
class_name WaveTimelineChart

# Per-wave visual planner card. Renders one wave as a stacked timeline:
#   header text  →  pre-wave (countdown + early-call zone)  →  spawn window
#   demand bars (per 5s bucket)  →  L1 supply line overlay
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
const CHART_TOP: float = 22.0
const CHART_BOTTOM: float = 116.0          # taller bar + supply line area, +50% over v1
const LANE_TOP: float = 118.0
const LANE_HEIGHT: float = 9.0             # per-path lane
const FOOTER_Y_FROM_BOTTOM: float = 4.0
const FOOTER_FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 12
const BUCKET_SEC: float = 5.0
const WAVE_START_LINE_W: float = 1.0

# ─── Colors ────────────────────────────────────────────────────────────────
const COL_PREWAVE_BASE: Color = Color(0.16, 0.18, 0.22, 1.0)
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
var _l1_dmg_per_gold: float = 0.0
var _gold_at_start: int = 0
var _paths_in_level: Array = []   # ordered list of path_ids in the level

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
var _supply_damage: float = 0.0           # total damage capacity over whole wave
var _supply_per_bucket: float = 0.0       # supply normalized to per-bucket — drives chart Y axis
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


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
		l1_dmg_per_gold: float, gold_at_start: int, paths_in_level: Array,
		level_final_gold: int = 0) -> void:
	_wave = wave
	_level_data = level_data
	_wave_index = wave_index
	_l1_dmg_per_gold = l1_dmg_per_gold
	_gold_at_start = gold_at_start
	_paths_in_level = paths_in_level
	_level_final_gold = level_final_gold
	_recompute()
	_resize_for_paths()
	queue_redraw()


# Adjust card height so each path gets a lane (multi-path levels are taller).
func _resize_for_paths() -> void:
	var lanes: int = max(1, _paths_in_level.size())
	var h: float = LANE_TOP + LANE_HEIGHT * lanes + 18.0  # +footer + padding
	custom_minimum_size = Vector2(CARD_MIN_WIDTH, h)


func _recompute() -> void:
	_bucket_ehp.clear()
	_bucket_ehp_by_class.clear()
	_bucket_max_ehp = 0.0
	_spawn_events.clear()
	_gold_events.clear()
	_gold_at_wave_end = _gold_at_start
	_required_damage = 0.0
	_supply_damage = 0.0
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
	# Required damage and supply. Sum bucket EHPs (override-aware) instead of
	# bc.wave_required_damage which reads authored counts only — the count
	# slider would otherwise show the wrong ratio.
	_required_damage = 0.0
	for v in _bucket_ehp:
		_required_damage += float(v)
	_supply_damage = _l1_dmg_per_gold * float(_gold_at_start)
	# Per-5s-equivalent supply so bars and line share a Y axis. Bars are
	# per-bucket EHP; line is "DPS budget × bucket length". Total-supply ratio
	# is still shown in the header (apples-to-apples on the headline number).
	if _spawn_window_sec > 0.0:
		_supply_per_bucket = _supply_damage * (BUCKET_SEC / _spawn_window_sec)
	else:
		_supply_per_bucket = 0.0
	if _required_damage > 0.0:
		_ratio_natural = _supply_damage / _required_damage
	# Composition summary footer line.
	var parts: PackedStringArray = []
	for k in class_counts.keys():
		parts.append("%s×%d" % [String(k), int(class_counts[k])])
	var paths_used: Dictionary = {}
	for ev in _spawn_events:
		paths_used[String(ev.path_id)] = true
	parts.append("%d path%s" % [paths_used.size(), "" if paths_used.size() == 1 else "s"])
	_composition_summary = " · ".join(parts)


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
	var countdown: float = float(_wave.countdown) if "countdown" in _wave else 0.0
	var early_window: float = 10.0
	if _level_data != null and "early_call_window_sec" in _level_data:
		early_window = float(_level_data.early_call_window_sec)
	# Resolve effective window via the same 4-step chain WaveManager uses,
	# so chart visuals match what the player will actually get during play.
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
			# Per-wave countdown override — pre-wave region width tracks the
			# overridden countdown, so the green early-call zone scales with it.
			var cd_ov: int = BO_lvl.get_wave_countdown(lvl_id, _wave_index)
			if cd_ov >= 0:
				countdown = float(cd_ov)
	# Map total visible time = countdown + spawn_window into [PAD_X, w - PAD_X].
	var total_t: float = countdown + _spawn_window_sec
	if total_t <= 0.0:
		return
	var usable: float = w - PAD_X * 2.0
	var prewave_w: float = (countdown / total_t) * usable
	var spawn_x0: float = PAD_X + prewave_w
	var spawn_w: float = usable - prewave_w

	_draw_header(w, countdown, early_window)
	_draw_prewave(prewave_w, countdown, early_window)
	_draw_bucket_backgrounds(spawn_x0, spawn_w)
	_draw_demand_bars(spawn_x0, spawn_w)
	_draw_supply_line(spawn_x0, spawn_w)
	_draw_gold_curve(spawn_x0, spawn_w)
	_draw_wave_start_line(spawn_x0)
	_draw_path_lanes(spawn_x0, spawn_w)
	_draw_footer(w)


func _draw_header(w: float, countdown: float, early_window: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var ratio_str: String = "—" if _ratio_natural <= 0.0 else "%.2f" % _ratio_natural
	var flag: String = ""
	var col: Color = COL_HEADER_OK
	if _ratio_natural > 0.0 and _ratio_natural < 1.0:
		flag = "  ⚠ supply<demand"
		col = COL_HEADER_WARN
	var head: String = "W%d — %.0fs countdown · %.0fs spawn window · req %.0f dmg · ratio %s%s" % [
		_wave_index + 1, countdown, _spawn_window_sec, _required_damage, ratio_str, flag,
	]
	if countdown > 0.0:
		head += "   (%.0fs early-call · max bonus %.0fg)" % [early_window, early_window]
	draw_string(font, Vector2(PAD_X, HEADER_Y + HEADER_H - 2),
		head, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, HEADER_FONT_SIZE, col)


func _draw_prewave(prewave_w: float, countdown: float, early_window: float) -> void:
	if prewave_w <= 0.0:
		return
	# Base dark grey across the full pre-wave region.
	draw_rect(Rect2(PAD_X, CHART_TOP, prewave_w, CHART_BOTTOM - CHART_TOP), COL_PREWAVE_BASE, true)
	# Early-call green tint inside the last `early_window` seconds (where bonus
	# = sec_remaining, capped at early_window). Solid alpha at the cap edge,
	# fading to transparent at t=0 — visualizes the diminishing bonus.
	if countdown <= 0.0 or early_window <= 0.0:
		return
	var cap_visible: float = min(early_window, countdown)
	if cap_visible <= 0.0:
		return
	var ec_w: float = (cap_visible / countdown) * prewave_w
	var ec_x0: float = PAD_X + (prewave_w - ec_w)
	# Two-step gradient via stacked alphas — Godot's draw_rect doesn't gradient.
	var steps: int = 8
	for i in range(steps):
		var f: float = float(i) / float(steps - 1)  # 0 = cap edge, 1 = wave start
		var seg_x: float = ec_x0 + ec_w * (float(i) / float(steps))
		var seg_w: float = ec_w / float(steps) + 0.5
		var c: Color = COL_EARLYCALL_FULL.lerp(COL_EARLYCALL_FADE, f)
		draw_rect(Rect2(seg_x, CHART_TOP, seg_w, CHART_BOTTOM - CHART_TOP), c, true)


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
	# Y-axis = damage per 5s bucket. Both bars and supply line live in this
	# unit. Headroom = ×1.15 so neither extreme pins flush to the chart edge.
	var max_axis: float = max(_bucket_max_ehp, _supply_per_bucket) * 1.15
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


func _draw_supply_line(spawn_x0: float, spawn_w: float) -> void:
	# Quiet, dashed reference line — Grafana / Datadog convention. Bar color
	# (magma high-stop) carries the alarm signal; the line itself is a static
	# threshold the eye scans against. Single neutral color regardless of
	# breach state — the breach is read off the bar tops, not the line.
	if _supply_per_bucket <= 0.0:
		return
	var max_axis: float = max(_bucket_max_ehp, _supply_per_bucket) * 1.15
	if max_axis <= 0.0:
		return
	var chart_h: float = CHART_BOTTOM - CHART_TOP
	var supply_y: float = CHART_BOTTOM - (_supply_per_bucket / max_axis) * (chart_h - 2.0)
	draw_dashed_line(
		Vector2(spawn_x0, supply_y), Vector2(spawn_x0 + spawn_w, supply_y),
		COL_SUPPLY_LINE, 1.0, 4.0, true,
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
# Includes a flat carry-over segment across the pre-wave region (countdown)
# at gold_at_wave_start, so the player's wallet entering the wave is plotted
# even before any enemies spawn.
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


func _draw_footer(w: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var y: float = size.y - FOOTER_Y_FROM_BOTTOM
	draw_string(font, Vector2(PAD_X, y),
		_composition_summary, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, FOOTER_FONT_SIZE, COL_FOOTER)
