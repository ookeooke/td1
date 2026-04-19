extends Control

# Phase 45b: floating stats card shown above the occupied-spot radial menu.
# Pure display — no input. Tracks a tower and refreshes its labels on demand.
#
# Positioning is driven by TowerRadialMenu: it sets `position` to the ring's
# anchor point and this script offsets itself upward by the card height
# once the panel has resolved its minimum size.

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %TitleLabel
@onready var stats_label: Label = %StatsLabel
@onready var meta_label: Label = %MetaLabel

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
	stats_label.text = data.get_stats_line()
	stats_label.visible = stats_label.text != ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Cost: %dg" % int(data.cost))
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
	var current_line: String = current.get_stats_line() if current != null else ""
	var upgrade_line: String = upgrade.get_stats_line(current.data) if current != null else ""
	stats_label.text = _diff_line(current_line, upgrade_line)
	stats_label.visible = stats_label.text != ""
	meta_label.text = "Cost: %dg" % int(upgrade.cost)
	meta_label.visible = true
	await _reposition(min_clearance)


# Sell confirmation mode: no stats, just a refund callout.
func show_for_sell_confirm(refund: int, anchor_pos: Vector2, min_clearance: float) -> void:
	_tower = null
	_anchor_pos = anchor_pos
	visible = true
	title_label.text = "Sell tower?"
	stats_label.text = "Tap again to confirm"
	stats_label.visible = true
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
	var line: String = _tower.get_stats_line()
	stats_label.text = line
	stats_label.visible = line != ""

	var parts: PackedStringArray = PackedStringArray()
	if _tower.has_method("get_targeting_mode_name"):
		parts.append("Target: %s" % _tower.get_targeting_mode_name())
	if "total_damage_dealt" in _tower:
		parts.append("Damage: %s" % _format_number(_tower.total_damage_dealt))
	meta_label.text = "   \u2022   ".join(parts)
	meta_label.visible = not parts.is_empty()


func _format_number(value: float) -> String:
	var n: int = int(value)
	if n >= 1000:
		@warning_ignore("integer_division")
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)
