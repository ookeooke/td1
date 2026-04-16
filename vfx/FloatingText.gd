extends Node2D

# Tween-based floating text that drifts upward and fades out.
# Usage: FloatingText.spawn(parent, "+5g", Color.GOLD, pos)

const _Scene: PackedScene = preload("res://vfx/FloatingText.tscn")

var _text: String = ""
var _color: Color = Color.WHITE
var _font_size: int = 16
var _alpha: float = 1.0


static func spawn(parent: Node, text: String, color: Color, pos: Vector2, font_size: int = 16) -> void:
	var inst: Node2D = _Scene.instantiate()
	inst.global_position = pos
	inst._text = text
	inst._color = color
	inst._font_size = font_size
	parent.add_child(inst)
	inst._start()


func _start() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 40.0, 0.6)
	tween.tween_property(self, "_alpha", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, _font_size)
	var text_pos: Vector2 = Vector2(-text_size.x * 0.5, _font_size * 0.35)
	var c: Color = _color
	c.a = _alpha
	# Drop shadow for readability.
	draw_string(font, text_pos + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0, 0, 0, _alpha * 0.6))
	draw_string(font, text_pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, c)
