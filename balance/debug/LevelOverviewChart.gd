extends Control
class_name LevelOverviewChart

# Whole-level arc card: per-wave EHP bars + cumulative gold curve, side by side
# along the wave-index axis. Sits above the per-wave detail cards in the
# BalanceSliders wave-timelines block. Answers the design intent the per-wave
# cards can't: "where are the spike waves vs the rest waves, and is the gold
# curve climbing fast enough during rests to fund the next spike?"
#
# Reuses BalanceCalculator helpers; no new math. Pure read; no .tres mutation.
# Debug-only — the surrounding BalanceSliders panel is gated upstream.

# ─── Layout constants ─────────────────────────────────────────────────────
# Card layout grew by 24 px when the pressure strip was added between
# header and EHP bars (Tuning Console). Constants below enclose the strip
# in y-band [STRIP_TOP..STRIP_BOTTOM]; PLOT_TOP shifts down accordingly so
# the EHP bars and gold line keep their absolute footprint.
const CARD_HEIGHT: float = 224.0
const CARD_MIN_WIDTH: float = 560.0
const PAD_X: float = 8.0
const HEADER_Y: float = 4.0
const HEADER_H: float = 14.0
const STRIP_TOP: float = 22.0
const STRIP_BOTTOM: float = 46.0
const PLOT_TOP: float = 50.0
const PLOT_BOTTOM: float = 184.0
const X_LABEL_Y: float = 190.0
const X_LABEL_FONT: int = 11
const FOOTER_Y_FROM_BOTTOM: float = 4.0
const FOOTER_FONT: int = 11
const HEADER_FONT: int = 13
const AXIS_LABEL_FONT: int = 10
const STRIP_FONT: int = 10

# ─── Colors (mirror WaveTimelineChart palette so the language is shared) ──
# Stacked-by-class bars: each wave-bar is segmented by enemy class so the
# composition is visible at a glance ("W7 is mostly armored, W8 is flyers").
# Class colors duplicated from WaveTimelineChart.ENEMY_COLORS so this card
# stays self-contained — six unique scenes max in practice.
const ENEMY_COLORS: Dictionary = {
	"basic":   Color(0.65, 0.65, 0.70),
	"scout":   Color(0.95, 0.90, 0.40),
	"armored": Color(0.65, 0.45, 0.25),
	"flying":  Color(0.45, 0.85, 0.95),
	"healer":  Color(0.45, 0.90, 0.55),
	"brute":   Color(0.55, 0.30, 0.30),
	"boss":    Color(0.95, 0.35, 0.55),
}
const COL_BAR_OUTLINE: Color = Color(0, 0, 0, 0.35)
const COL_AVG_LINE: Color = Color(0.85, 0.88, 0.92, 0.50)

# Progression order (lightest / earliest → heaviest / boss). Bar stacking
# uses this so trash (basic) sits at the foundation, boss sits on top.
# Mirrors the slider list order in BalanceSliders.
const ENEMY_PROGRESSION: Array[String] = [
	"basic", "scout", "flying", "healer", "armored", "brute", "boss",
]
const COL_GOLD_LINE: Color = Color(0.45, 0.95, 0.55, 1.0)
const COL_GOLD_DOT: Color = Color(0.65, 1.00, 0.70, 1.0)
const COL_HEADER_OK: Color = Color(0.85, 0.95, 1.0)
const COL_HEADER_WARN: Color = Color(0.95, 0.80, 0.45)
# Coverage-driven saturation marker — drawn as a dashed horizontal line at
# the gold value where extra gold stops buying realistic damage on this map.
# See WaveDamageSimulator.saturation_gold and balance/audit/CoverageReport.
const COL_SATURATION: Color = Color(0.95, 0.55, 0.85, 0.85)
const COL_AXIS_LABEL: Color = Color(0.65, 0.70, 0.78)
const COL_FOOTER: Color = Color(0.65, 0.70, 0.78)
const COL_BOSS_MARK: Color = Color(0.95, 0.35, 0.55, 0.95)

# Off-target band on cumulative gold vs gold_budget_total (% drift). Header
# turns warm-yellow when |delta| exceeds this — fastest signal that the level
# is over- or under-funded relative to design intent.
const GOLD_DRIFT_WARN_PCT: float = 15.0


# ─── State ────────────────────────────────────────────────────────────────
var _wave_list: WaveList = null
var _level_data: Resource = null
var _starting_gold: int = 0
# Coverage-driven saturation gold for this level. 0 = unknown / don't draw.
# Populated by BalanceSliders before set_data via the optional fourth arg.
var _saturation_gold: int = 0
# Per-wave coverage-weighted pressure rows (canonical for Tuning Console).
# Each row: {actual, target, drift, supply, demand, gold_at_start, reason}.
# Empty = strip not drawn (legacy callers / errors); see plan.
var _pressure_rows: Array = []

# Cache per-scene EHP + gold + id + class-key, populated lazily by walking
# each wave's spawns. Mirrors WaveTimelineChart's caches to avoid
# re-instantiating the same enemy scene across waves.
var _enemy_hp_cache: Dictionary = {}      # scene_path → authored max_health (pre-override)
var _enemy_armor_cache: Dictionary = {}   # scene_path → authored armor (pre-override)
var _enemy_gold_cache: Dictionary = {}    # scene_path → authored gold_worth
var _enemy_id_cache: Dictionary = {}      # scene_path → enemy_id
var _enemy_class_cache: Dictionary = {}   # scene_path → "basic"/"scout"/...

# Derived per-redraw:
var _per_wave_ehp: Array = []         # Array[float], length = wave count — total per wave
# Stacked-by-class breakdown of each wave. Element i is a Dictionary
# class_key → ehp_in_wave_from_that_class. Sum of values == _per_wave_ehp[i].
var _per_wave_ehp_by_class: Array = []   # Array[Dictionary]
var _per_wave_gold: Array = []        # Array[int]
var _cumul_gold: Array = []           # Array[int], length = wave_count + 1 (incl. start)
var _per_wave_required_dmg: Array = []
var _avg_ehp: float = 0.0
var _max_ehp: float = 0.0
var _final_gold: int = 0
var _total_required_dmg: float = 0.0
var _hardness: float = 0.0
var _boss_waves: Array = []           # Array[int] — wave indices that contain a boss


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Drop the cached EnemyData snapshots — see WaveTimelineChart.clear_enemy_caches.
func clear_enemy_caches() -> void:
	_enemy_hp_cache.clear()
	_enemy_armor_cache.clear()
	_enemy_gold_cache.clear()
	_enemy_id_cache.clear()
	_enemy_class_cache.clear()


func set_data(wave_list: WaveList, level_data: Resource, starting_gold: int,
		saturation_gold: int = 0, pressure_rows: Array = []) -> void:
	_wave_list = wave_list
	_level_data = level_data
	_starting_gold = starting_gold
	_saturation_gold = saturation_gold
	_pressure_rows = pressure_rows
	_recompute()
	queue_redraw()


func _recompute() -> void:
	_per_wave_ehp.clear()
	_per_wave_ehp_by_class.clear()
	_per_wave_gold.clear()
	_cumul_gold.clear()
	_per_wave_required_dmg.clear()
	_boss_waves.clear()
	_avg_ehp = 0.0
	_max_ehp = 0.0
	_final_gold = _starting_gold
	_total_required_dmg = 0.0
	_hardness = 0.0
	if _wave_list == null or _wave_list.waves.is_empty():
		return
	var bc: GDScript = load("res://balance/BalanceCalculator.gd")
	if bc == null:
		return
	_hardness = bc.score_level(_wave_list, _starting_gold)
	# Per-wave EHP + per-class breakdown + override-aware gold, all in one
	# spawn walk. Each emitter's contribution is multiplied by its
	# wave_overrides count_mult so per-emitter slider edits land on bars,
	# cumul-gold curve, AND the per-wave required-damage total in lockstep
	# with what the runtime will spawn.
	var BO_count: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var level_id_for_count: String = ""
	if _level_data != null and "level_id" in _level_data:
		level_id_for_count = String(_level_data.level_id)
	var sum_ehp: float = 0.0
	for i in range(_wave_list.waves.size()):
		var wave: WaveData = _wave_list.waves[i]
		if wave == null:
			_per_wave_ehp.append(0.0)
			_per_wave_ehp_by_class.append({})
			_per_wave_required_dmg.append(0.0)
			_per_wave_gold.append(0)
			continue
		# Override-aware walk — totals derived from the same overridden counts
		# so the bar height matches the per-class stack. Authored helpers
		# (bc.wave_ehp_physical / wave_required_damage) read the .tres, not
		# overrides, so we don't use them here.
		var by_class: Dictionary = {}
		var wave_ehp_total: float = 0.0
		var wave_req_dmg: float = 0.0
		var wave_gold: int = int(wave.bounty) if "bounty" in wave else 0
		var spawn_idx: int = -1
		for spawn in wave.spawns:
			spawn_idx += 1
			if spawn == null or spawn.count <= 0 or spawn.enemy_scene == null:
				continue
			var count_mult: float = 1.0
			if BO_count != null and level_id_for_count != "":
				count_mult = BO_count.get_wave_count_mult(
					level_id_for_count, i, spawn_idx
				)
			var effective_count: int = max(0, int(round(float(spawn.count) * count_mult)))
			if effective_count <= 0:
				continue
			var per_enemy_ehp: float = _enemy_ehp_for(spawn.enemy_scene)
			var class_key: String = _enemy_class_for(spawn.enemy_scene)
			var contribution: float = per_enemy_ehp * float(effective_count)
			by_class[class_key] = float(by_class.get(class_key, 0.0)) + contribution
			wave_ehp_total += contribution
			wave_req_dmg += contribution
			wave_gold += _enemy_gold_for(spawn.enemy_scene) * effective_count
		_per_wave_ehp.append(wave_ehp_total)
		_per_wave_required_dmg.append(wave_req_dmg)
		_total_required_dmg += wave_req_dmg
		sum_ehp += wave_ehp_total
		if wave_ehp_total > _max_ehp:
			_max_ehp = wave_ehp_total
		_per_wave_ehp_by_class.append(by_class)
		_per_wave_gold.append(wave_gold)
		# Boss detection: scene path contains "boss" (mirrors the heuristic in
		# WaveTimelineChart._enemy_class_for, no instancing needed).
		for spawn in wave.spawns:
			if spawn != null and spawn.enemy_scene != null:
				if spawn.enemy_scene.resource_path.to_lower().contains("boss"):
					_boss_waves.append(i)
					break
	if not _per_wave_ehp.is_empty():
		_avg_ehp = sum_ehp / float(_per_wave_ehp.size())
	# Cumulative gold: index 0 = starting, index i+1 = starting + Σ wave_gold[0..i].
	# Built AFTER the spawn walk so it reflects the override-adjusted per-wave
	# totals computed above (was previously built from authored score_level
	# _breakdown.per_wave_gold, ignoring gold_mult sliders).
	_cumul_gold.append(_starting_gold)
	var running: int = _starting_gold
	for g in _per_wave_gold:
		running += int(g)
		_cumul_gold.append(running)
	_final_gold = running


# ─── Drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	if _wave_list == null or _wave_list.waves.is_empty():
		return
	var w: float = size.x
	var n: int = _wave_list.waves.size()
	var usable: float = w - PAD_X * 2.0
	var slot_w: float = usable / float(n)
	_draw_header(w)
	_draw_pressure_strip(usable, slot_w, n)
	_draw_avg_line(usable)
	_draw_bars(usable, slot_w)
	_draw_gold_line(usable, slot_w)
	_draw_saturation_marker(usable)
	_draw_x_labels(usable, slot_w, n)
	_draw_axis_labels(w)
	_draw_footer(w)


func _draw_header(w: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var lvl_name: String = "Level"
	if _level_data != null and "display_name" in _level_data:
		lvl_name = String(_level_data.display_name)
	var head: String = "%s — %d waves · req %s dmg total · gold %s → %s · hardness %.0f" % [
		lvl_name, _wave_list.waves.size(),
		_fmt_n(_total_required_dmg), _fmt_n(_starting_gold), _fmt_n(_final_gold),
		_hardness,
	]
	var col: Color = COL_HEADER_OK
	# Off-target band on cumul gold vs authored gold_budget_total → warn header.
	if _level_data != null and "gold_budget_total" in _level_data and int(_level_data.gold_budget_total) > 0:
		var target: float = float(_level_data.gold_budget_total) + float(_starting_gold)
		var drift_pct: float = (float(_final_gold) - target) / target * 100.0
		if absf(drift_pct) > GOLD_DRIFT_WARN_PCT:
			col = COL_HEADER_WARN
			head += "  ⚠ %+.0f%% vs target" % drift_pct
	# Saturation overshoot — wallet ends above the coverage plateau, meaning
	# late-level gold isn't buying damage. Tag in warm-yellow regardless of
	# the gold-budget drift band so it's always visible when relevant.
	if _saturation_gold > 0 and _final_gold > _saturation_gold:
		head += "  · over-sat +%sg" % _fmt_n(float(_final_gold - _saturation_gold))
		col = COL_HEADER_WARN
	# Tuning Console summary: count of waves whose drift is "dangerous" or
	# "likely unfair" against the authored target (drift > +10%). Surfaces
	# the level-wide signal without requiring scan of the strip.
	var over: int = 0
	for row in _pressure_rows:
		if float(row.get("target", 0.0)) <= 0.0:
			continue
		if float(row.get("drift", 0.0)) > 0.10:
			over += 1
	if over > 0:
		head += "  · %d wave%s over target" % [over, "" if over == 1 else "s"]
		col = COL_HEADER_WARN
	draw_string(font, Vector2(PAD_X, HEADER_Y + HEADER_H - 2),
		head, HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, HEADER_FONT, col)


func _draw_avg_line(usable: float) -> void:
	if _max_ehp <= 0.0 or _avg_ehp <= 0.0:
		return
	var plot_h: float = PLOT_BOTTOM - PLOT_TOP
	var y: float = PLOT_BOTTOM - (_avg_ehp / (_max_ehp * 1.15)) * (plot_h - 2.0)
	draw_dashed_line(
		Vector2(PAD_X, y), Vector2(PAD_X + usable, y),
		COL_AVG_LINE, 1.0, 4.0, true,
	)


func _draw_bars(_usable: float, slot_w: float) -> void:
	if _max_ehp <= 0.0:
		return
	var plot_h: float = PLOT_BOTTOM - PLOT_TOP
	var max_axis: float = _max_ehp * 1.15
	# Progression-ordered stacking: basic at the foundation, boss on top.
	# Matches the per-wave detail charts and the BalanceSliders enemy list.
	var class_order: Array = ENEMY_PROGRESSION
	for i in range(_per_wave_ehp.size()):
		var ehp_total: float = float(_per_wave_ehp[i])
		if ehp_total <= 0.0:
			continue
		# Bar sits centered in its wave-slot, with breathing room on either side.
		var bx: float = PAD_X + slot_w * float(i) + slot_w * 0.18
		var bw: float = slot_w * 0.64
		var per_class: Dictionary = _per_wave_ehp_by_class[i] if i < _per_wave_ehp_by_class.size() else {}
		# Stack bottom-up, segment height proportional to that class's share.
		var cursor_y: float = PLOT_BOTTOM
		for class_key in class_order:
			var class_ehp: float = float(per_class.get(class_key, 0.0))
			if class_ehp <= 0.0:
				continue
			var seg_h: float = (class_ehp / max_axis) * (plot_h - 2.0)
			if seg_h < 0.5:
				continue
			var seg_y: float = cursor_y - seg_h
			var seg_col: Color = ENEMY_COLORS.get(class_key, Color(0.55, 0.55, 0.55))
			draw_rect(Rect2(bx, seg_y, bw, seg_h), seg_col, true)
			if seg_y > PLOT_TOP + 1.0:
				draw_line(
					Vector2(bx, seg_y), Vector2(bx + bw, seg_y),
					COL_BAR_OUTLINE, 1.0, false,
				)
			cursor_y = seg_y
		# Boss marker — six-pointed star above the bar's top.
		if _boss_waves.has(i):
			var bar_top_y: float = PLOT_BOTTOM - (ehp_total / max_axis) * (plot_h - 2.0)
			_draw_boss_marker(Vector2(bx + bw * 0.5, max(PLOT_TOP, bar_top_y - 8.0)))


# Per-enemy physical EHP, cached by scene_path. Instantiates once per unique
# scene to read the .data resource, then frees the node. Mirrors the helper
# in WaveTimelineChart so this card stays self-contained.
func _enemy_ehp_for(scene: PackedScene) -> float:
	if scene == null:
		return 0.0
	var path: String = scene.resource_path
	# Cache AUTHORED hp + armor; apply override stack on every read so slider
	# changes are live without cache invalidation. Mirrors
	# WaveTimelineChart._enemy_ehp_for.
	if not _enemy_hp_cache.has(path):
		var inst: Node = scene.instantiate()
		var hp_raw: float = 0.0
		var armor_raw: float = 0.0
		var gw: int = 0
		var eid: String = ""
		if "data" in inst and inst.data != null:
			var d = inst.data
			hp_raw = float(d.max_health) if "max_health" in d else 0.0
			armor_raw = float(d.armor) if "armor" in d else 0.0
			gw = int(d.gold_worth) if "gold_worth" in d else 0
			eid = String(d.enemy_id) if "enemy_id" in d else ""
		inst.queue_free()
		_enemy_hp_cache[path] = hp_raw
		_enemy_armor_cache[path] = armor_raw
		_enemy_gold_cache[path] = gw
		_enemy_id_cache[path] = eid
	# HP stack: authored × global × per-level × per-enemy.
	# Armor stack: authored + global + per-enemy (clamp 0..0.95).
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


# Override-aware gold drop per kill. Authored gold_worth × gold_mult.
func _enemy_gold_for(scene: PackedScene) -> int:
	if scene == null:
		return 0
	var path: String = scene.resource_path
	if not _enemy_gold_cache.has(path):
		_enemy_ehp_for(scene)  # populates ehp + gold + id together
	var raw: int = int(_enemy_gold_cache.get(path, 0))
	if raw <= 0:
		return 0
	var eid: String = String(_enemy_id_cache.get(path, ""))
	var BO: GDScript = load("res://balance/debug/BalanceOverrides.gd")
	var mult: float = BO.get_enemy_mult(eid, "gold_mult") if BO != null else 1.0
	return int(round(float(raw) * mult))


# Maps an enemy scene's resource_path to the class-key used by ENEMY_COLORS.
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


func _draw_boss_marker(center: Vector2) -> void:
	# Compact 6-point star: two interleaved triangles, ~5 px radius. draw_polyline
	# avoids font-glyph rendering issues across platforms.
	var r: float = 4.0
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(7):  # close back to start
		var ang: float = TAU * float(i) / 6.0 - PI / 2.0
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	draw_polyline(pts, COL_BOSS_MARK, 1.5, true)


func _draw_pressure_strip(_usable: float, slot_w: float, n: int) -> void:
	# Per-wave coverage-weighted pressure displayed as a row of cells. Top
	# line is the actual pressure (white); bottom line is signed drift vs
	# authored target colored by verdict band. Cell background tints by
	# verdict at low alpha so the row reads at a glance. When the row is
	# empty (legacy caller / no data) the strip is suppressed.
	if _pressure_rows.is_empty() or n <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var top_y: float = STRIP_TOP
	var cell_h: float = STRIP_BOTTOM - STRIP_TOP
	for i in range(min(n, _pressure_rows.size())):
		var row: Dictionary = _pressure_rows[i]
		var actual: float = float(row.get("actual", 0.0))
		var target: float = float(row.get("target", 0.0))
		var verdict: Dictionary = WaveDamageSimulator.drift_verdict(actual, target)
		var v_color: Color = verdict["color"]
		var has_target: bool = bool(verdict["has_target"])
		# Cell background — verdict color at low alpha, slightly larger when
		# the wave is over target so the warning reads even on small displays.
		var cell_x: float = PAD_X + slot_w * float(i) + 2.0
		var cell_w: float = slot_w - 4.0
		var bg: Color = v_color
		bg.a = 0.18 if has_target else 0.10
		draw_rect(Rect2(cell_x, top_y, cell_w, cell_h), bg, true)
		# Top line: actual pressure.
		var actual_str: String = "%.2f" % actual
		var asz: Vector2 = font.get_string_size(actual_str, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT)
		draw_string(font,
			Vector2(cell_x + (cell_w - asz.x) * 0.5, top_y + STRIP_FONT + 1.0),
			actual_str, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT,
			Color(0.95, 0.95, 0.95))
		# Bottom line: drift% (or "(no target)") in verdict color.
		var bot_str: String
		if has_target:
			var drift: float = float(row.get("drift", 0.0))
			bot_str = "%+d%%" % int(round(drift * 100.0))
		else:
			bot_str = "—"
		var bsz: Vector2 = font.get_string_size(bot_str, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT)
		draw_string(font,
			Vector2(cell_x + (cell_w - bsz.x) * 0.5, top_y + cell_h - 2.0),
			bot_str, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT, v_color)


func _draw_saturation_marker(usable: float) -> void:
	# Coverage-driven plateau. Drawn over the gold polyline as a dashed
	# horizontal line at y(saturation_gold). Where the green wallet curve
	# crosses this line is the wave at which extra gold stops converting
	# to damage on this map. Suppressed when saturation is 0 (unknown),
	# negative, or near/above the chart's top edge.
	if _saturation_gold <= 0 or _final_gold <= 0:
		return
	var max_axis: float = float(_final_gold) * 1.05
	if float(_saturation_gold) >= max_axis * 0.99:
		return
	var plot_h: float = PLOT_BOTTOM - PLOT_TOP
	var y: float = PLOT_BOTTOM - (float(_saturation_gold) / max_axis) * (plot_h - 2.0)
	draw_dashed_line(
		Vector2(PAD_X, y), Vector2(PAD_X + usable, y),
		COL_SATURATION, 1.5, 6.0, true,
	)
	# Right-edge pill label "sat: 1,500g". Placed just above the line so it
	# doesn't collide with the bottom-edge "Xg" label that already sits at
	# the right edge.
	var font: Font = ThemeDB.fallback_font
	var label: String = "sat: %sg" % _fmt_n(float(_saturation_gold))
	var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT)
	var lx: float = PAD_X + usable - sz.x - 4.0
	var ly: float = y - 4.0
	if ly < PLOT_TOP + sz.y:
		ly = y + sz.y + 2.0
	draw_string(font, Vector2(lx, ly),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT, COL_SATURATION)


func _draw_gold_line(_usable: float, slot_w: float) -> void:
	if _cumul_gold.size() < 2 or _final_gold <= 0:
		return
	var plot_h: float = PLOT_BOTTOM - PLOT_TOP
	var max_axis: float = float(_final_gold) * 1.05
	# X positions: _cumul_gold[0] anchored at left edge of plot;
	# _cumul_gold[i+1] anchored at the RIGHT edge of wave-slot i (i.e. wave-end).
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(_cumul_gold.size()):
		var g: float = float(_cumul_gold[i])
		var y: float = PLOT_BOTTOM - (g / max_axis) * (plot_h - 2.0)
		var x: float
		if i == 0:
			x = PAD_X
		else:
			x = PAD_X + slot_w * float(i)  # right edge of wave (i-1)
		pts.append(Vector2(x, y))
	draw_polyline(pts, COL_GOLD_LINE, 2.0, true)
	# Dot at each wave-end vertex (skip the starting-gold anchor on the left).
	for i in range(1, pts.size()):
		draw_circle(pts[i], 2.5, COL_GOLD_DOT)


func _draw_x_labels(_usable: float, slot_w: float, n: int) -> void:
	var font: Font = ThemeDB.fallback_font
	for i in range(n):
		var label: String = str(i + 1)
		var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, X_LABEL_FONT).x
		var x: float = PAD_X + slot_w * (float(i) + 0.5) - text_w * 0.5
		draw_string(font, Vector2(x, X_LABEL_Y),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, X_LABEL_FONT, COL_AXIS_LABEL)


func _draw_axis_labels(w: float) -> void:
	# Right-edge labels: top = max EHP value, bottom = final cumul gold.
	var font: Font = ThemeDB.fallback_font
	var max_str: String = "%s EHP" % _fmt_n(_max_ehp)
	var ms: Vector2 = font.get_string_size(max_str, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT)
	draw_string(font, Vector2(w - PAD_X - ms.x, PLOT_TOP + 8.0),
		max_str, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT, COL_AXIS_LABEL)
	var gold_str: String = "%sg" % _fmt_n(_final_gold)
	var gs: Vector2 = font.get_string_size(gold_str, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT)
	draw_string(font, Vector2(w - PAD_X - gs.x, PLOT_BOTTOM - 2.0),
		gold_str, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_FONT, COL_GOLD_DOT)


func _draw_footer(w: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var bits: PackedStringArray = []
	if not _boss_waves.is_empty():
		var marks: PackedStringArray = []
		for bi in _boss_waves:
			marks.append("W%d" % (int(bi) + 1))
		bits.append("bosses: " + ", ".join(marks))
	if _level_data != null and "gold_budget_total" in _level_data:
		bits.append("cumul gold @ end: %sg (target %sg)" % [
			_fmt_n(_final_gold), _fmt_n(int(_level_data.gold_budget_total) + _starting_gold),
		])
	if bits.is_empty():
		return
	var y: float = size.y - FOOTER_Y_FROM_BOTTOM
	draw_string(font, Vector2(PAD_X, y),
		"   ".join(bits), HORIZONTAL_ALIGNMENT_LEFT, w - PAD_X * 2.0, FOOTER_FONT, COL_FOOTER)


static func _fmt_n(n) -> String:
	var i: int = int(round(float(n)))
	if i < 1000:
		return str(i)
	var s: String = str(i)
	var out: String = ""
	var c: int = 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		c += 1
		if c % 3 == 0 and k > 0:
			out = "," + out
	return out
