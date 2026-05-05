extends Button
class_name HeroCard

# Phase 50 — Roster-rail card for the Hero Hall. One card per hero in
# ContentRegistry.heroes. Tap selects the hero (writes LoadoutState +
# emits hero_selected). Locked heroes render dimmed with a 🔒 overlay
# and are disabled.
#
# Visual layout (280×120):
#   ┌────────────────────────┐
#   │ [Sprite]  Hero Name    │
#   │  small    Lv 5   ⚔     │
#   │  60×80    ▓▓▓▓░░       │
#   └────────────────────────┘

const _CARD_SIZE: Vector2 = Vector2(280, 120)
const _SPRITE_SCALE: float = 1.6
const _SPRITE_OFFSET: Vector2 = Vector2(56, 78)
const _BG_NORMAL: Color = Color(0.13, 0.17, 0.23, 1.0)
const _BG_SELECTED: Color = Color(0.20, 0.27, 0.40, 1.0)
const _BORDER_NORMAL: Color = Color(0.28, 0.34, 0.46, 1.0)
const _BORDER_SELECTED: Color = Color(1.0, 0.85, 0.4, 1.0)
const _NAME_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const _META_COLOR: Color = Color(0.65, 0.72, 0.85, 1.0)
const _XP_BAR_BG: Color = Color(0.10, 0.13, 0.18, 1.0)
const _XP_BAR_FILL: Color = Color(0.55, 0.85, 1.0, 1.0)
const _LOCKED_DIM: Color = Color(0.45, 0.45, 0.5, 1.0)

var _hero_data: Resource = null
var _hero_id: String = ""
var _is_unlocked: bool = true
var _is_selected: bool = false
var _level: int = 1
var _xp_pct: float = 0.0


func _ready() -> void:
	custom_minimum_size = _CARD_SIZE
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()


func setup(hero_data: Resource) -> void:
	_hero_data = hero_data
	if hero_data != null and "hero_id" in hero_data:
		_hero_id = String(hero_data.hero_id)
		_is_unlocked = UnlockManager.is_hero_unlocked(_hero_id) if hero_data.requires_unlock else true
	disabled = not _is_unlocked
	_refresh_progress()
	queue_redraw()


func set_selected(is_selected: bool) -> void:
	if _is_selected == is_selected:
		return
	_is_selected = is_selected
	queue_redraw()


func get_hero_id() -> String:
	return _hero_id


func _refresh_progress() -> void:
	if _hero_data == null or _hero_id == "":
		_level = 1
		_xp_pct = 0.0
		return
	_level = MetaProgression.get_hero_level(_hero_id)
	var xp: int = MetaProgression.get_hero_xp(_hero_id)
	var need: int = 0
	var max_lvl: int = int(_hero_data.max_level) if "max_level" in _hero_data else 10
	var xp_per_level: Array = _hero_data.xp_per_level if "xp_per_level" in _hero_data else []
	if _level - 1 >= 0 and _level - 1 < xp_per_level.size():
		need = int(xp_per_level[_level - 1])
	if _level >= max_lvl or need <= 0:
		_xp_pct = 1.0
	else:
		_xp_pct = clampf(float(xp) / float(need), 0.0, 1.0)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg: Color = _BG_SELECTED if _is_selected else _BG_NORMAL
	var border: Color = _BORDER_SELECTED if _is_selected else _BORDER_NORMAL
	# Body + border.
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0 if _is_selected else 1.0)
	# Sprite (procedural hero visual) on the left side. Faded when locked.
	if _hero_data != null and "visual" in _hero_data and _hero_data.visual != null:
		# Tint via UnitVisualDrawer's skin_tint ctx so locked heroes render
		# dim. Faded silhouette, no overlay rect needed.
		var tint: Color = _LOCKED_DIM if not _is_unlocked else Color.WHITE
		var ctx := {"skin_tint": tint}
		UnitVisualDrawer.draw_unit(self, _hero_data.visual, _SPRITE_OFFSET, Vector2(_SPRITE_SCALE, _SPRITE_SCALE), -1.0, 0.0, ctx)
	# Lock icon overlay for locked heroes.
	if not _is_unlocked:
		_draw_lock_icon(Vector2(56, 60), 16.0)
	# Name + level + XP bar — right of the sprite area.
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var name_str: String = String(_hero_data.hero_name) if _hero_data != null and "hero_name" in _hero_data else "?"
	if not _is_unlocked:
		name_str = "Locked"
	var text_x: float = 124.0
	# Name
	draw_string(font, Vector2(text_x, 36.0), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, _NAME_COLOR)
	# Sub-line: "Lv N" and a damage-type icon glyph.
	if _is_unlocked:
		var sub: String = "Lv %d" % _level
		draw_string(font, Vector2(text_x, 64.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, _META_COLOR)
	# XP bar (only for unlocked heroes).
	if _is_unlocked:
		var bar_rect := Rect2(Vector2(text_x, 78.0), Vector2(140.0, 8.0))
		draw_rect(bar_rect, _XP_BAR_BG, true)
		var fill_rect := Rect2(bar_rect.position, Vector2(bar_rect.size.x * _xp_pct, bar_rect.size.y))
		if fill_rect.size.x > 0.5:
			draw_rect(fill_rect, _XP_BAR_FILL, true)


func _draw_lock_icon(pos: Vector2, r: float) -> void:
	# Padlock body + shackle. Uses _LOCKED_DIM as the stroke color so it
	# reads as part of the locked treatment, not the highlight color.
	var col: Color = Color(1.0, 0.85, 0.4, 1.0)
	draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.9)), col, true)
	draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.9)), col.darkened(0.5), false, 1.0)
	# Shackle (arc).
	draw_arc(pos + Vector2(0, -r * 0.1), r * 0.45, PI, 0.0, 16, col.darkened(0.2), 2.5, true)
	# Keyhole.
	draw_circle(pos + Vector2(0, r * 0.3), r * 0.12, col.darkened(0.5))
