extends Node2D

# Style-driven floating combat text.
# Old API kept verbatim:    spawn(parent, text, color, pos, font_size)
# New typed presets:        spawn_kind(parent, kind, pos, amount, text_override, color_override)
#
# Animation pipeline (styled path): scale 0.75 -> 1.25 -> 1.0 (pop / settle),
# parallel position drift, alpha fade across the last 30% of lifetime,
# 8-direction outline pass for readability over busy backgrounds.

const _Scene: PackedScene = preload("res://vfx/FloatingText.tscn")

enum Kind {
	DAMAGE_ENEMY,
	DAMAGE_BIG,
	DAMAGE_HERO_TAKEN,
	DAMAGE_SOLDIER_TAKEN,
	HEAL,
	GOLD,
	XP,
	PICKUP,
	WARNING,
}

# Style table. Values consumed by _start_styled() and _draw().
const _STYLES: Dictionary = {
	Kind.DAMAGE_ENEMY: {
		"font_size": 30,
		"color": Color(1.0, 0.32, 0.18),
		"outline_color": Color(0.05, 0.0, 0.0, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.55,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 80.0,
		"drift_spread": 18.0,
		"pop_scale": 1.25,
		"z_index": 100,
		"wobble": 6.0,
	},
	Kind.DAMAGE_BIG: {
		"font_size": 52,
		"color": Color(1.0, 0.85, 0.2),
		"outline_color": Color(0.25, 0.05, 0.0, 1.0),
		"outline_thickness": 3.0,
		"lifetime": 0.85,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 120.0,
		"drift_spread": 24.0,
		"pop_scale": 1.45,
		"z_index": 110,
		"wobble": 10.0,
	},
	Kind.DAMAGE_HERO_TAKEN: {
		"font_size": 38,
		"color": Color(1.0, 0.18, 0.18),
		"outline_color": Color(0.1, 0.0, 0.0, 1.0),
		"outline_thickness": 3.0,
		"lifetime": 0.7,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 110.0,
		"drift_spread": 22.0,
		"pop_scale": 1.35,
		"z_index": 105,
		"wobble": 8.0,
	},
	Kind.DAMAGE_SOLDIER_TAKEN: {
		"font_size": 26,
		"color": Color(1.0, 0.85, 0.2),
		"outline_color": Color(0.1, 0.05, 0.0, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.5,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 70.0,
		"drift_spread": 16.0,
		"pop_scale": 1.2,
		"z_index": 100,
		"wobble": 5.0,
	},
	Kind.HEAL: {
		"font_size": 32,
		"color": Color(0.4, 0.95, 0.5),
		"outline_color": Color(0.0, 0.15, 0.05, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.7,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 90.0,
		"drift_spread": 18.0,
		"pop_scale": 1.25,
		"z_index": 100,
		"wobble": 6.0,
	},
	Kind.GOLD: {
		"font_size": 36,
		"color": Color(1.0, 0.82, 0.25),
		"outline_color": Color(0.2, 0.1, 0.0, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.85,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 100.0,
		"drift_spread": 20.0,
		"pop_scale": 1.3,
		"z_index": 110,
		"wobble": 4.0,
	},
	Kind.XP: {
		"font_size": 32,
		"color": Color(0.45, 0.8, 1.0),
		"outline_color": Color(0.05, 0.05, 0.2, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.85,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 100.0,
		"drift_spread": 0.0,
		"pop_scale": 1.25,
		"z_index": 110,
		"wobble": 0.0,
	},
	Kind.PICKUP: {
		"font_size": 28,
		"color": Color(1.0, 1.0, 1.0),
		"outline_color": Color(0.05, 0.05, 0.05, 1.0),
		"outline_thickness": 2.0,
		"lifetime": 0.9,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 90.0,
		"drift_spread": 0.0,
		"pop_scale": 1.2,
		"z_index": 105,
		"wobble": 0.0,
	},
	Kind.WARNING: {
		"font_size": 36,
		"color": Color(1.0, 0.6, 0.1),
		"outline_color": Color(0.2, 0.05, 0.0, 1.0),
		"outline_thickness": 3.0,
		"lifetime": 0.8,
		"drift_dir": Vector2(0, -1),
		"drift_dist": 60.0,
		"drift_spread": 0.0,
		"pop_scale": 1.4,
		"z_index": 110,
		"wobble": 0.0,
	},
}

var _text: String = ""
var _color: Color = Color.WHITE
var _outline_color: Color = Color(0, 0, 0, 0.6)
var _outline_thickness: float = 0.0
var _font_size: int = 40
var _alpha: float = 1.0
var _scale_factor: float = 1.0
var _wobble_amp: float = 0.0
var _wobble_phase: float = 0.0
var _wobble_t: float = 0.0


# ---------- Public API ----------

# Legacy API. Kept verbatim for back-compat; renders with a single drop shadow
# and the original 0.6s rise/fade. New call sites should use spawn_kind().
static func spawn(parent: Node, text: String, color: Color, pos: Vector2, font_size: int = 40) -> void:
	var inst: Node2D = _Scene.instantiate()
	inst.global_position = pos
	inst._text = text
	inst._color = color
	inst._font_size = font_size
	inst._outline_thickness = 0.0
	parent.add_child(inst)
	inst._start_legacy()


# Typed style preset. `amount` auto-formats text per kind when `text_override`
# is empty. `color_override.a > 0` replaces the style color (used for item
# rarity tinting on PICKUP).
static func spawn_kind(parent: Node, kind: int, pos: Vector2, amount: float = 0.0,
		text_override: String = "", color_override: Color = Color(0, 0, 0, 0)) -> void:
	var style: Dictionary = _STYLES.get(kind, _STYLES[Kind.DAMAGE_ENEMY])
	var t: String = text_override if text_override != "" else _format_text(kind, amount)
	var inst: Node2D = _Scene.instantiate()
	inst.global_position = pos
	inst._text = t
	inst._color = color_override if color_override.a > 0.0 else (style["color"] as Color)
	inst._outline_color = style["outline_color"]
	inst._outline_thickness = float(style["outline_thickness"])
	inst._font_size = int(style["font_size"])
	inst.z_index = int(style["z_index"])
	parent.add_child(inst)
	inst._start_styled(style)


static func _format_text(kind: int, amount: float) -> String:
	match kind:
		Kind.GOLD:
			return "+%dg" % int(round(amount))
		Kind.XP:
			return "+%d XP" % int(round(amount))
		Kind.HEAL:
			return "+%d" % int(round(amount))
		Kind.WARNING:
			return ""
		_:
			return str(int(ceil(amount)))


# ---------- Internal ----------

func _start_legacy() -> void:
	var zs: float = _get_zoom_scale()
	var drift: float = 100.0 * zs
	_scale_factor = 1.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - drift, 0.6)
	tween.tween_property(self, "_alpha", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)


func _start_styled(style: Dictionary) -> void:
	var zs: float = _get_zoom_scale()
	var lifetime: float = float(style["lifetime"])
	var drift_dir: Vector2 = (style["drift_dir"] as Vector2).normalized()
	var drift_dist: float = float(style["drift_dist"]) * zs
	var spread: float = float(style["drift_spread"]) * zs
	var pop: float = float(style["pop_scale"])

	# Random horizontal nudge so consecutive numbers don't perfectly stack.
	if spread > 0.0:
		position.x += randf_range(-spread, spread)

	_wobble_amp = float(style["wobble"]) * zs
	_wobble_phase = randf() * TAU
	_scale_factor = 0.75
	_alpha = 1.0

	var target_pos: Vector2 = position + drift_dir * drift_dist

	# Pop -> settle.
	var s_tween: Tween = create_tween()
	s_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	s_tween.tween_property(self, "_scale_factor", pop, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	s_tween.tween_property(self, "_scale_factor", 1.0, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

	# Drift over full lifetime.
	var p_tween: Tween = create_tween()
	p_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	p_tween.tween_property(self, "position", target_pos, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Fade — last 30% of lifetime.
	var fade_delay: float = lifetime * 0.7
	var fade_dur: float = maxf(0.05, lifetime - fade_delay)
	var f_tween: Tween = create_tween()
	f_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	f_tween.tween_interval(fade_delay)
	f_tween.tween_property(self, "_alpha", 0.0, fade_dur)
	f_tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_wobble_t += delta
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var zs: float = _get_zoom_scale()
	var scaled_size: int = int(_font_size * zs * _scale_factor)
	if scaled_size < 4:
		scaled_size = 4
	var text_size: Vector2 = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, scaled_size)
	var wobble_off: float = 0.0
	if _wobble_amp > 0.0:
		wobble_off = sin(_wobble_t * 6.0 + _wobble_phase) * _wobble_amp
	var text_pos: Vector2 = Vector2(-text_size.x * 0.5 + wobble_off, scaled_size * 0.35)
	var c: Color = _color
	c.a = _alpha
	if _outline_thickness > 0.0:
		var ot: float = _outline_thickness * zs
		var oc: Color = _outline_color
		oc.a = _outline_color.a * _alpha
		# 8-direction outline (cardinal + diagonal) for legibility on busy maps.
		var dirs: Array = [
			Vector2(ot, 0), Vector2(-ot, 0), Vector2(0, ot), Vector2(0, -ot),
			Vector2(ot, ot), Vector2(-ot, -ot), Vector2(ot, -ot), Vector2(-ot, ot),
		]
		for d in dirs:
			draw_string(font, text_pos + d, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_size, oc)
	else:
		# Legacy drop shadow.
		draw_string(font, text_pos + Vector2(2, 2) * zs, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_size, Color(0, 0, 0, _alpha * 0.6))
	draw_string(font, text_pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_size, c)


func _get_zoom_scale() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return 1.0 / cam.zoom.x
