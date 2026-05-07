extends PanelContainer
class_name HudChip

# Compact HUD widget: themed panel with a procedurally-drawn glyph icon on
# the left and a value Label on the right. Used for gold / lives / wave /
# threat. pulse_pop() and pulse_modulate() animate scale + tint so value
# changes yank the player's eye to the chip — same shape as the existing
# purchase-deny feedback in HUD.gd.

# Layout: PanelContainer (theme draws panel) → MarginContainer (margin_left
# reserves the icon slot) → Label. Glyph is drawn in _draw() over the panel
# but under the Label, in the reserved 32px slot at the chip's left edge.

const _GLYPH_SLOT_W: float = 32.0
const _PANEL_PAD: float = 10.0  # matches game_theme PanelContainer content_margin_left

@export var glyph: String = "":
	set(v):
		glyph = v
		queue_redraw()

@export var value_text: String = "":
	set(v):
		value_text = v
		if is_inside_tree():
			var lbl: Label = get_node_or_null("Margin/ChipValue") as Label
			if lbl != null:
				lbl.text = v

var _scale_tween: Tween = null
var _color_tween: Tween = null


func _ready() -> void:
	var lbl: Label = get_node_or_null("Margin/ChipValue") as Label
	if lbl != null:
		lbl.text = value_text
	resized.connect(_update_pivot)
	_update_pivot()
	queue_redraw()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


# ---------- Public ----------

func set_value(text: String) -> void:
	value_text = text


func set_value_color(c: Color) -> void:
	var lbl: Label = get_node_or_null("Margin/ChipValue") as Label
	if lbl != null:
		lbl.add_theme_color_override("font_color", c)


func pulse_pop(scale_to: float = 1.18, in_dur: float = 0.08, out_dur: float = 0.18) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_update_pivot()
	scale = Vector2.ONE
	_scale_tween = create_tween()
	_scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scale_tween.tween_property(self, "scale", Vector2(scale_to, scale_to), in_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE, out_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func pulse_modulate(flash: Color, in_dur: float = 0.06, out_dur: float = 0.34) -> void:
	if _color_tween != null and _color_tween.is_valid():
		_color_tween.kill()
	modulate = Color.WHITE
	_color_tween = create_tween()
	_color_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_color_tween.tween_property(self, "modulate", flash, in_dur)
	_color_tween.tween_property(self, "modulate", Color.WHITE, out_dur)


# ---------- Glyph ----------

func _draw() -> void:
	# Panel stylebox is drawn by the parent class first; the glyph sits on top.
	var c: Vector2 = Vector2(_PANEL_PAD + _GLYPH_SLOT_W * 0.5, size.y * 0.5)
	var r: float = minf(_GLYPH_SLOT_W, size.y) * 0.4
	match glyph:
		"coin": _draw_coin(c, r)
		"heart": _draw_heart(c, r)
		"wave": _draw_wave(c, r)
		"threat": _draw_threat(c, r)
		_: pass


func _draw_coin(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(1.0, 0.82, 0.25))
	draw_arc(c, r, 0, TAU, 32, Color(0.4, 0.25, 0.05), 1.5, true)
	draw_arc(c, r * 0.6, 0, TAU, 24, Color(1.0, 0.92, 0.5), 1.5, true)


func _draw_heart(c: Vector2, r: float) -> void:
	var col: Color = Color(0.95, 0.25, 0.3)
	var lobe: float = r * 0.55
	var lc: Vector2 = c + Vector2(-lobe * 0.7, -r * 0.15)
	var rc: Vector2 = c + Vector2(lobe * 0.7, -r * 0.15)
	draw_circle(lc, lobe, col)
	draw_circle(rc, lobe, col)
	var pts: PackedVector2Array = PackedVector2Array([
		c + Vector2(-r * 1.05, 0),
		c + Vector2(r * 1.05, 0),
		c + Vector2(0, r * 0.95),
	])
	draw_colored_polygon(pts, col)


func _draw_wave(c: Vector2, r: float) -> void:
	var col: Color = Color(0.6, 0.85, 1.0)
	var w: float = r * 1.1
	for i in range(3):
		var off_y: float = -r * 0.55 + r * 0.5 * float(i)
		var pts: PackedVector2Array = PackedVector2Array([
			c + Vector2(-w, off_y - 3.0),
			c + Vector2(0, off_y + r * 0.25),
			c + Vector2(w, off_y - 3.0),
			c + Vector2(w, off_y),
			c + Vector2(0, off_y + r * 0.25 + 3.0),
			c + Vector2(-w, off_y),
		])
		draw_colored_polygon(pts, col)


func _draw_threat(c: Vector2, r: float) -> void:
	var col: Color = Color(0.95, 0.95, 0.95)
	draw_circle(c + Vector2(0, -r * 0.15), r * 0.85, col)
	var jaw_pts: PackedVector2Array = PackedVector2Array([
		c + Vector2(-r * 0.5, r * 0.4),
		c + Vector2(r * 0.5, r * 0.4),
		c + Vector2(r * 0.32, r * 0.85),
		c + Vector2(-r * 0.32, r * 0.85),
	])
	draw_colored_polygon(jaw_pts, col)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.15), r * 0.2, Color(0.05, 0.05, 0.05))
	draw_circle(c + Vector2(r * 0.3, -r * 0.15), r * 0.2, Color(0.05, 0.05, 0.05))
