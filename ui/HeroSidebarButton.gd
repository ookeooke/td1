extends Button
class_name HeroSidebarButton

# Phase 51 — Compact 120×112 hero button for the HeroesHub left sidebar.
# Replaces the 280×120 HeroCard so the sidebar can stay 140 px wide on
# every page (Equipment + Skills + Talents need every horizontal pixel).
#
# Visual:
#   ┌────────────┐
#   │  portrait  │  procedural sprite (UnitVisualDrawer)
#   │            │
#   │   Name     │  font 14
#   │   Lv 7     │  font 12, lock icon if locked
#   └────────────┘
#
# Public surface mirrors HeroCard.gd 1:1 so the hub's selection +
# refresh code is unchanged: setup / set_selected / get_hero_id.

const _BTN_SIZE: Vector2 = Vector2(120, 112)
# Phase 52 — sprite scale dropped 1.4 → 1.0 so the procedural hero (~40 px
# tall) fits comfortably in the upper 64-px band of the 112-px card. clip
# at the button border catches any future hero with a tall plume / weapon.
# Phase 52b — scale dropped 1.0 → 0.75 and offset chest lifted 46 → 38.
# At 1.0 the helmet pushed the top edge and the sword/legs leaked into the
# name/Lv label band; the warrior's full silhouette (helmet + body + sword
# tip) is ~70 px tall at scale 1.0, not 40 px as the original comment
# assumed. 0.75 keeps it inside the upper 64-px band with clear headroom.
const _SPRITE_SCALE: float = 0.75
const _SPRITE_OFFSET: Vector2 = Vector2(60, 38)
const _BG_NORMAL: Color = Color(0.13, 0.17, 0.23, 1.0)
const _BG_SELECTED: Color = Color(0.20, 0.27, 0.40, 1.0)
const _BORDER_NORMAL: Color = Color(0.28, 0.34, 0.46, 1.0)
const _BORDER_SELECTED: Color = Color(1.0, 0.85, 0.4, 1.0)
const _NAME_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const _META_COLOR: Color = Color(0.65, 0.72, 0.85, 1.0)
const _LOCKED_DIM: Color = Color(0.45, 0.45, 0.5, 1.0)

var _hero_data: Resource = null
var _hero_id: String = ""
var _is_unlocked: bool = true
var _is_selected: bool = false
var _level: int = 1


func _ready() -> void:
	custom_minimum_size = _BTN_SIZE
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	queue_redraw()


func setup(hero_data: Resource) -> void:
	_hero_data = hero_data
	if hero_data != null and "hero_id" in hero_data:
		_hero_id = String(hero_data.hero_id)
		_is_unlocked = UnlockManager.is_hero_unlocked(_hero_id) if hero_data.requires_unlock else true
	disabled = not _is_unlocked
	_level = MetaProgression.get_hero_level(_hero_id) if _hero_id != "" else 1
	queue_redraw()


func set_selected(is_selected: bool) -> void:
	if _is_selected == is_selected:
		return
	_is_selected = is_selected
	queue_redraw()


func get_hero_id() -> String:
	return _hero_id


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg: Color = _BG_SELECTED if _is_selected else _BG_NORMAL
	var border: Color = _BORDER_SELECTED if _is_selected else _BORDER_NORMAL
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0 if _is_selected else 1.0)
	# Procedural portrait — top half. Locked = dim tint.
	if _hero_data != null and "visual" in _hero_data and _hero_data.visual != null:
		var tint: Color = _LOCKED_DIM if not _is_unlocked else Color.WHITE
		var ctx := {"skin_tint": tint}
		UnitVisualDrawer.draw_unit(self, _hero_data.visual, _SPRITE_OFFSET, Vector2(_SPRITE_SCALE, _SPRITE_SCALE), -1.0, 0.0, ctx)
	if not _is_unlocked:
		_draw_lock_icon(Vector2(60, 44), 12.0)
	# Name + Lv on bottom band.
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var name_str: String = String(_hero_data.hero_name) if _hero_data != null and "hero_name" in _hero_data else "?"
	if not _is_unlocked:
		name_str = "Locked"
	var name_size := font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 14)
	var name_pos := Vector2((size.x - name_size.x) * 0.5, 86.0)
	draw_string(font, name_pos, name_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, _NAME_COLOR)
	if _is_unlocked:
		var sub: String = "Lv %d" % _level
		var sub_size := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12)
		var sub_pos := Vector2((size.x - sub_size.x) * 0.5, 104.0)
		draw_string(font, sub_pos, sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, _META_COLOR)


func _draw_lock_icon(pos: Vector2, r: float) -> void:
	var col: Color = Color(1.0, 0.85, 0.4, 1.0)
	draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.9)), col, true)
	draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.9)), col.darkened(0.5), false, 1.0)
	draw_arc(pos + Vector2(0, -r * 0.1), r * 0.45, PI, 0.0, 16, col.darkened(0.2), 2.0, true)
	draw_circle(pos + Vector2(0, r * 0.3), r * 0.12, col.darkened(0.5))
