extends Control

# Phase 33: endless leaderboard display. Reads from
# MetaProgression.endless_leaderboard (local top-20 for now). Future online
# integration: swap the data source to an HTTP fetch from LootLocker /
# GameJolt / custom REST API — UI stays unchanged.

@onready var back_button: Button = %BackButton
@onready var scores_list: VBoxContainer = %ScoresList


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build_list()


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _build_list() -> void:
	for child in scores_list.get_children():
		child.queue_free()

	if MetaProgression.endless_leaderboard.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No scores yet.\nPlay Endless mode to set a record!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.set("theme_override_font_sizes/font_size", 18)
		scores_list.add_child(empty_label)
		return

	# Header row
	var header := _make_row("#", "Name", "Score", "Wave", Color(0.9, 0.85, 0.5))
	scores_list.add_child(header)

	var rank: int = 0
	for entry in MetaProgression.endless_leaderboard:
		rank += 1
		var name_str: String = str(entry.get("name", "???"))
		var score_str: String = str(int(entry.get("score", 0)))
		var wave_str: String = str(int(entry.get("wave", 0)))
		var color: Color = Color(1.0, 0.95, 0.3) if rank <= 3 else Color.WHITE
		var row := _make_row(str(rank), name_str, score_str, wave_str, color)
		scores_list.add_child(row)


func _make_row(rank_text: String, name_text: String, score_text: String, wave_text: String, color: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.set("theme_override_constants/separation", 8)

	var rank_label := Label.new()
	rank_label.text = rank_text
	rank_label.custom_minimum_size = Vector2(40, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.set("theme_override_font_sizes/font_size", 18)
	rank_label.modulate = color
	hbox.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.set("theme_override_font_sizes/font_size", 18)
	name_label.modulate = color
	hbox.add_child(name_label)

	var score_label := Label.new()
	score_label.text = score_text
	score_label.custom_minimum_size = Vector2(80, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.set("theme_override_font_sizes/font_size", 18)
	score_label.modulate = color
	hbox.add_child(score_label)

	var wave_label := Label.new()
	wave_label.text = "W" + wave_text
	wave_label.custom_minimum_size = Vector2(50, 0)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.set("theme_override_font_sizes/font_size", 16)
	wave_label.modulate = color
	hbox.add_child(wave_label)

	return hbox
