extends Control
class_name HeroSkillMap

# Unified-chooser Phase 2 — a Path-of-Exile-lite skill constellation.
#
# INSPECT-ONLY. This control draws the hero's skill tree as a node graph and
# emits `node_selected(node_id)` when a node is tapped. It NEVER purchases,
# equips, or mutates anything — every commit goes through the host page's
# detail-panel buttons (HeroSkillsPage, Phase 3). Keeping it side-effect-free
# is what makes it safe to drop in additively.
#
# Layout is computed at runtime from the authored data only (no .tres
# changes): X = level_required (1..10), Y = lane-by-kind with per-cell
# stacking, edges = prerequisite_ids. Phase-0 audit confirmed the data is
# rich enough for a readable, deterministic graph.
#
# Per-node hit targets are transparent Button children (≥80px, focus-less,
# tap-consuming). Button.pressed dedupes mouse vs. emulated-touch, so there
# is no PC double-fire — unlike a raw _input handler.

signal node_selected(node_id: String)

const _NodeData := preload("res://heroes/HeroSkillNodeData.gd")
const _Theme := preload("res://ui/theme/ThemeColors.gd")

# --- layout constants -----------------------------------------------------
const COL_W: float = 150.0          # horizontal px per hero level
const ROW_H: float = 104.0          # vertical px between stacked nodes
const LANE_GAP: float = 150.0       # vertical px between kind lanes
const MARGIN: Vector2 = Vector2(70, 60)
const NODE_R: float = 32.0          # node visual radius
const HIT: float = 80.0             # hit-target side (mobile touch floor)

# Lane order top→bottom. CAPSTONE shares the active lane but is pinned right.
const _LANE := {
	_NodeData.Kind.ACTIVE_RANK: 0,
	_NodeData.Kind.MOD: 1,
	_NodeData.Kind.SLOT_UNLOCK: 2,
	_NodeData.Kind.PASSIVE_RANK: 3,
	_NodeData.Kind.CAPSTONE: 0,
}

var _hero_id: String = ""
var _hero_data: Resource = null
var _tree: Resource = null
# node_id -> { node:Resource, pos:Vector2, kind:int }
var _vm: Dictionary = {}
var _selected_id: String = ""


func _ready() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # receive _gui_input taps


# Rebuild for a hero. Safe to call repeatedly (hero swap).
func setup(hero_id: String) -> void:
	_hero_id = hero_id
	_selected_id = ""
	_vm.clear()
	if not has_node("/root/ContentRegistry"):
		return
	_hero_data = ContentRegistry.find_hero(hero_id)
	_tree = ContentRegistry.find_skill_tree(hero_id)
	if _tree == null or not ("nodes" in _tree):
		custom_minimum_size = Vector2.ZERO
		queue_redraw()
		return
	_layout()
	queue_redraw()


# Hit-test taps directly against node positions. No per-node child Buttons —
# those proved fragile inside a ScrollContainer (zero-size parent / setup
# recall race left them unspawned, so clicks never landed). Touch-only:
# emulate_touch_from_mouse means a PC click also arrives as ScreenTouch, so
# handling ONLY ScreenTouch fires exactly once on both touch and mouse.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	if _vm.is_empty():
		return
	var p: Vector2 = event.position
	var best_id: String = ""
	var best_d: float = HIT * 0.5 + 4.0  # generous tap radius (≥80px target)
	for nid in _vm.keys():
		var d: float = p.distance_to(_vm[nid]["pos"])
		if d <= best_d:
			best_d = d
			best_id = String(nid)
	if best_id != "":
		accept_event()
		set_selected_node(best_id)
		node_selected.emit(best_id)
	elif _selected_id != "":
		# Tap on empty space dismisses the current selection (and the
		# floating card). Only consume the event when something was open.
		accept_event()
		set_selected_node("")
		node_selected.emit("")


# Map-local centre of a node, for hosts that position UI next to it.
func node_pos(node_id: String) -> Vector2:
	if _vm.has(node_id):
		return _vm[node_id]["pos"]
	return Vector2.ZERO


func has_node_pos(node_id: String) -> bool:
	return _vm.has(node_id)


func set_selected_node(node_id: String) -> void:
	if node_id == _selected_id:
		return
	_selected_id = node_id
	queue_redraw()


func clear_selection() -> void:
	_selected_id = ""
	queue_redraw()


# --- layout ---------------------------------------------------------------

func _layout() -> void:
	# Stack counter keyed by "lane:level" so multiple nodes at the same level
	# in the same lane fan downward instead of overlapping.
	var stack: Dictionary = {}
	var max_x: float = 0.0
	var max_y: float = 0.0
	for n in _tree.nodes:
		if n == null or not ("node_id" in n):
			continue
		var kind: int = int(n.kind)
		var lane: int = int(_LANE.get(kind, 3))
		var lvl: int = clampi(int(n.level_required), 1, 10)
		var pos: Vector2
		if kind == _NodeData.Kind.CAPSTONE:
			# Pinned far right, vertically centered between the lanes.
			pos = Vector2(MARGIN.x + 10.0 * COL_W, MARGIN.y + 1.5 * LANE_GAP)
		else:
			var key: String = "%d:%d" % [lane, lvl]
			var idx: int = int(stack.get(key, 0))
			stack[key] = idx + 1
			pos = Vector2(
				MARGIN.x + float(lvl - 1) * COL_W,
				MARGIN.y + float(lane) * LANE_GAP + float(idx) * ROW_H)
		_vm[String(n.node_id)] = {"node": n, "pos": pos, "kind": kind}
		max_x = maxf(max_x, pos.x)
		max_y = maxf(max_y, pos.y)
	# Reserve room for node radius + label below.
	custom_minimum_size = Vector2(max_x + MARGIN.x + NODE_R,
		max_y + MARGIN.y + NODE_R + 28.0)


# --- node state -----------------------------------------------------------

enum _State { LOCKED, AVAILABLE, PURCHASED }


func _state_of(n: Resource) -> int:
	if not has_node("/root/MetaProgression"):
		return _State.LOCKED
	if MetaProgression.get_purchased_rank(_hero_id, String(n.node_id)) > 0:
		return _State.PURCHASED
	var lvl: int = MetaProgression.get_hero_level(_hero_id)
	if lvl < int(n.level_required):
		return _State.LOCKED
	for pre in n.prerequisite_ids:
		if MetaProgression.get_purchased_rank(_hero_id, String(pre)) <= 0:
			return _State.LOCKED
	return _State.AVAILABLE


func _is_equipped(n: Resource) -> bool:
	# Equipped ring for ACTIVE_RANK whose skill is in the active loadout.
	if int(n.kind) != _NodeData.Kind.ACTIVE_RANK:
		return false
	if not has_node("/root/LoadoutState"):
		return false
	return String(n.target_id) in LoadoutState.get_equipped_skills(_hero_id)


# --- draw -----------------------------------------------------------------

func _kind_color(kind: int) -> Color:
	match kind:
		_NodeData.Kind.ACTIVE_RANK:  return _Theme.ACCENT_CYAN
		_NodeData.Kind.PASSIVE_RANK: return Color(0.66, 0.45, 0.95)
		_NodeData.Kind.MOD:          return _Theme.ACCENT_GOLD
		_NodeData.Kind.SLOT_UNLOCK:  return _Theme.ACCENT_GREEN
		_NodeData.Kind.CAPSTONE:     return _Theme.ACCENT_GOLD
		_:                           return _Theme.TEXT_SECONDARY


func _draw() -> void:
	if _vm.is_empty():
		var f0 := ThemeDB.fallback_font
		draw_string(f0, Vector2(MARGIN.x, MARGIN.y), "No skill tree.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _Theme.TEXT_SECONDARY)
		return
	# 1) Prerequisite edges (under nodes).
	for nid in _vm.keys():
		var n: Resource = _vm[nid]["node"]
		var to: Vector2 = _vm[nid]["pos"]
		for pre in n.prerequisite_ids:
			var pk: String = String(pre)
			if _vm.has(pk):
				var lit: bool = _state_of(n) != _State.LOCKED
				var col: Color = _Theme.ACCENT_GOLD if lit else _Theme.PANEL_BORDER
				col.a = 0.85 if lit else 0.45
				draw_line(_vm[pk]["pos"], to, col, 3.0)
	# 2) Nodes.
	var font := ThemeDB.fallback_font
	for nid in _vm.keys():
		var entry: Dictionary = _vm[nid]
		var n: Resource = entry["node"]
		var c: Vector2 = entry["pos"]
		var kind: int = entry["kind"]
		var st: int = _state_of(n)
		var base: Color = _kind_color(kind)
		var fill: Color = base
		match st:
			_State.LOCKED:    fill = Color(base.r, base.g, base.b, 0.22)
			_State.AVAILABLE: fill = Color(base.r, base.g, base.b, 0.72)
			_State.PURCHASED: fill = base
		_draw_node_shape(kind, c, fill, st)
		# Equipped ring (cyan), then selection ring (gold) on top.
		if _is_equipped(n):
			draw_arc(c, NODE_R + 6.0, 0, TAU, 32, _Theme.ACCENT_CYAN, 3.0)
		if String(nid) == _selected_id:
			draw_arc(c, NODE_R + 11.0, 0, TAU, 36, _Theme.ACCENT_GOLD, 4.0)
		# Label below.
		var label: String = String(n.node_name)
		var tcol: Color = _Theme.TEXT_PRIMARY if st != _State.LOCKED else _Theme.TEXT_SECONDARY
		draw_string(font, c + Vector2(-NODE_R - 26.0, NODE_R + 20.0),
			label, HORIZONTAL_ALIGNMENT_CENTER, (NODE_R + 26.0) * 2.0, 13, tcol)


func _draw_node_shape(kind: int, c: Vector2, fill: Color, st: int) -> void:
	var border := Color(0.05, 0.06, 0.09, 1.0) if st == _State.PURCHASED else _Theme.PANEL_BORDER
	match kind:
		_NodeData.Kind.PASSIVE_RANK:
			_draw_poly_shape(c, NODE_R, 6, fill, border)
		_NodeData.Kind.MOD:
			draw_circle(c, NODE_R * 0.62, fill)
			draw_arc(c, NODE_R * 0.62, 0, TAU, 24, border, 2.0)
		_NodeData.Kind.SLOT_UNLOCK:
			var r := Rect2(c - Vector2(NODE_R * 1.5, NODE_R * 0.7),
				Vector2(NODE_R * 3.0, NODE_R * 1.4))
			draw_rect(r, fill)
			draw_rect(r, border, false, 2.0)
		_NodeData.Kind.CAPSTONE:
			_draw_poly_shape(c, NODE_R * 1.35, 4, fill, _Theme.ACCENT_GOLD)
		_:  # ACTIVE_RANK
			draw_circle(c, NODE_R, fill)
			draw_arc(c, NODE_R, 0, TAU, 32, border, 2.5)


func _draw_poly_shape(c: Vector2, r: float, sides: int, fill: Color, border: Color) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		var a: float = -PI * 0.5 + TAU * float(i) / float(sides)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, border, 2.0)
