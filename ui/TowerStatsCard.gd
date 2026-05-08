extends Control

# Phase 45b: floating stats card shown above the occupied-spot radial menu.
# Pure display — no input. Tracks a tower and refreshes its labels on demand.
#
# Positioning is driven by TowerRadialMenu: it sets `position` to the ring's
# anchor point and this script offsets itself upward by the card height
# once the panel has resolved its minimum size.

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %TitleLabel
@onready var stats_label: RichTextLabel = %StatsLabel
@onready var meta_label: Label = %MetaLabel

# AAA-style diff palette: color only the delta so unchanged rows recede and
# the eye lands on what actually moved. Current value + label + → arrow stay
# in neutral; only the new value carries gain/loss color.
const COLOR_GAIN: String    = "#8ae07a"  # muted lime — improvement
const COLOR_LOSS: String    = "#e87a6f"  # soft coral — regression
const COLOR_DIM: String     = "#7a8296"  # slate — unchanged rows fade back
const COLOR_NEUTRAL: String = "#d4dae6"  # label / current value / → arrow

var _tower: Node = null
var _anchor_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_for(tower: Node, anchor_pos: Vector2, min_clearance: float) -> void:
	# `min_clearance` is the required distance between the anchor point and
	# the BOTTOM of the card — ensures the card sits fully above the top
	# radial slot regardless of its resolved height.
	_tower = tower
	_anchor_pos = anchor_pos
	visible = true
	refresh()
	await _reposition(min_clearance)


# Build-ring preview mode: show a buildable tower's specs before it exists.
# Reads TowerData accessors — no instance involved.
func show_for_build_preview(data: Resource, anchor_pos: Vector2, min_clearance: float) -> void:
	_tower = null
	_anchor_pos = anchor_pos
	visible = true
	title_label.text = String(data.tower_name)
	_set_stats_plain(data.get_stats_line())
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Cost: %dg" % data.get_effective_cost())
	if data.encyclopedia_entry != "":
		parts.append(String(data.encyclopedia_entry))
	meta_label.text = "   \u2022   ".join(parts)
	meta_label.visible = not parts.is_empty()
	await _reposition(min_clearance)


# Action-ring upgrade/branch preview mode: shows arrow-diff between current
# tower stats and what they'd become after paying for the next level.
func show_for_upgrade_preview(current: Node, upgrade: Resource, anchor_pos: Vector2, min_clearance: float) -> void:
	_tower = null
	_anchor_pos = anchor_pos
	visible = true
	var upgrade_name: String = String(upgrade.upgrade_name) if upgrade.upgrade_name != "" else "Upgrade"
	title_label.text = "Upgrade \u2192 %s" % upgrade_name
	# Prefer structured per-stat data so we can color gains green / losses red.
	# Fall back to the legacy string zip if a tower doesn't implement the
	# structured accessor yet (defensive — all current tower classes do).
	var curr_stats: Array = current.get_preview_stats() if current != null and current.has_method("get_preview_stats") else []
	var up_stats: Array = []
	if current != null and upgrade.has_method("get_preview_stats"):
		# Pass the post-upgrade tier_key so the upgrade resource can apply
		# per-tier BalanceOverrides multipliers — keeping the diff card
		# in sync with what the live tower will actually read after the
		# upgrade. Falls back to "" for towers that don't expose the
		# helper (preview then shows raw .tres values, prior behavior).
		var tower_id: String = String(current.data.tower_id) if current.data != null else ""
		var tier_key: String = ""
		if current.has_method("tier_key_for_upgrade"):
			tier_key = current.tier_key_for_upgrade(upgrade)
		up_stats = upgrade.get_preview_stats(current.data, tower_id, tier_key)
	var bbcode: String = ""
	if not curr_stats.is_empty() and not up_stats.is_empty():
		bbcode = _diff_bbcode(curr_stats, up_stats)
	else:
		var current_line: String = current.get_stats_line() if current != null else ""
		var upgrade_line: String = upgrade.get_stats_line(current.data) if current != null else ""
		bbcode = _escape_bbcode(_diff_line(current_line, upgrade_line))
	_set_stats_bbcode(bbcode)
	meta_label.text = "Cost: %dg" % int(upgrade.cost)
	meta_label.visible = true
	await _reposition(min_clearance)


# Sell confirmation mode: no stats, just a refund callout.
func show_for_sell_confirm(refund: int, anchor_pos: Vector2, min_clearance: float) -> void:
	_tower = null
	_anchor_pos = anchor_pos
	visible = true
	title_label.text = "Sell tower?"
	_set_stats_plain("Tap again to confirm")
	meta_label.text = "Refund: +%dg" % refund
	meta_label.visible = true
	await _reposition(min_clearance)


func hide_card() -> void:
	visible = false
	_tower = null


func _reposition(min_clearance: float) -> void:
	await get_tree().process_frame
	var panel_size: Vector2 = panel.get_combined_minimum_size()
	panel.size = panel_size
	panel.position = -panel_size * 0.5
	position = _anchor_pos + Vector2(0, -min_clearance - panel_size.y * 0.5)


# Zips two stats-lines into a "label curr→next" row. Assumes both lines share
# the same shape (split on 3-space separator → pairs of "label value").
func _diff_line(current_line: String, upgrade_line: String) -> String:
	if current_line == "" or upgrade_line == "":
		return upgrade_line if current_line == "" else current_line
	var curr_parts: PackedStringArray = current_line.split("   ", false)
	var upg_parts: PackedStringArray = upgrade_line.split("   ", false)
	if curr_parts.size() != upg_parts.size():
		return upgrade_line
	var out: PackedStringArray = PackedStringArray()
	for i in curr_parts.size():
		var curr: String = curr_parts[i]
		var upg: String = upg_parts[i]
		var space_curr: int = curr.rfind(" ")
		var space_upg: int = upg.rfind(" ")
		if space_curr < 0 or space_upg < 0:
			out.append("%s \u2192 %s" % [curr, upg])
			continue
		var label: String = curr.substr(0, space_curr)
		var curr_val: String = curr.substr(space_curr + 1)
		var upg_val: String = upg.substr(space_upg + 1)
		out.append("%s %s\u2192%s" % [label, curr_val, upg_val])
	return "   ".join(out)


func refresh() -> void:
	if _tower == null or _tower.data == null:
		return
	var tname: String = _tower.data.tower_name
	var lvl: int = int(_tower.level) if "level" in _tower else 1
	title_label.text = "%s  \u2022  Lv %d" % [tname, lvl]

	# Tower Indicator Interface (CORE RULE 14): each tower formats its own
	# stats row. No per-class branching here — archers show Dmg/Rng/Spd,
	# barracks show Rally/Squad/HP, future tower types own their own line.
	_set_stats_plain(_tower.get_stats_line())

	var parts: PackedStringArray = PackedStringArray()
	if _tower.has_method("get_targeting_mode_name"):
		parts.append("Target: %s" % _tower.get_targeting_mode_name())
	if "total_damage_dealt" in _tower:
		parts.append("Damage: %s" % _format_number(_tower.total_damage_dealt))
	meta_label.text = "   \u2022   ".join(parts)
	meta_label.visible = not parts.is_empty()


# ── Stats label helpers (RichTextLabel + BBCode) ────────────────────────

func _set_stats_plain(text: String) -> void:
	_set_stats_bbcode(_escape_bbcode(text))


func _set_stats_bbcode(bbcode: String) -> void:
	if bbcode == "":
		stats_label.visible = false
		stats_label.text = ""
		return
	stats_label.visible = true
	stats_label.text = "[center]%s[/center]" % bbcode


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


# Produces BBCode-colored diff row from two structured stat arrays.
# Each array is [{label, value, fmt}, ...]. Stats present in only one side
# are shown as new additions (green) or removals (red). Unchanged stats
# render in the card's default text color; changed ones use green on gain,
# red on loss.
func _diff_bbcode(curr: Array, up: Array) -> String:
	var curr_by_label: Dictionary = {}
	var order: Array = []
	for row in curr:
		curr_by_label[row.label] = row
		order.append(row.label)
	var up_by_label: Dictionary = {}
	for row in up:
		up_by_label[row.label] = row
		if not order.has(row.label):
			order.append(row.label)

	var cols: PackedStringArray = PackedStringArray()
	for label in order:
		var c = curr_by_label.get(label, null)
		var u = up_by_label.get(label, null)
		var c_val: float = float(c.value) if c != null else 0.0
		var u_val: float = float(u.value) if u != null else 0.0
		var fmt: String = u.fmt if u != null else (c.fmt if c != null else "%d")
		var display_label: String = label
		if label == "SlowT":
			display_label = "Dur"
		if c == null and u != null:
			# New ability introduced by the upgrade — "+" prefix reads as "added".
			cols.append("[color=%s]+%s %s[/color]" % [COLOR_GAIN, display_label, fmt % u_val])
		elif u == null and c != null:
			# Ability removed by the upgrade — "−" prefix reads as "lost".
			cols.append("[color=%s]\u2212%s %s[/color]" % [COLOR_LOSS, display_label, fmt % c_val])
		elif is_equal_approx(c_val, u_val):
			# Unchanged rows fade into the background so changes pop.
			cols.append("[color=%s]%s %s[/color]" % [COLOR_DIM, display_label, fmt % c_val])
		else:
			# Color ONLY the new value + direction arrow. Current value stays
			# neutral so the diff reads as "X → [colored Y]" at a glance.
			var is_gain: bool = u_val > c_val
			var color: String = COLOR_GAIN if is_gain else COLOR_LOSS
			var dir_arrow: String = "\u2191" if is_gain else "\u2193"
			cols.append("%s %s\u2192[color=%s]%s %s[/color]" % [
				display_label, fmt % c_val, color, fmt % u_val, dir_arrow
			])
	return "   ".join(cols)


func _format_number(value: float) -> String:
	var n: int = int(value)
	if n >= 1000:
		@warning_ignore("integer_division")
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)
