extends CanvasLayer

# Tactical-pause enemy inspector. Listens for EventBus.enemy_inspected,
# pins to top-right of the screen, refreshes HP + active effects every frame
# while visible (since neither has a per-instance change signal). Auto-
# closes on resume or when the inspected enemy despawns.

@onready var panel: PanelContainer = %Panel
@onready var name_label: Label = %NameLabel
@onready var hp_label: Label = %HPLabel
@onready var stats_label: RichTextLabel = %StatsLabel
@onready var effects_label: RichTextLabel = %EffectsLabel
@onready var description_label: RichTextLabel = %DescriptionLabel
@onready var close_button: Button = %CloseButton
@onready var more_button: Button = %MoreButton

var _enemy_ref: WeakRef = null
var _show_description: bool = false
var _has_description: bool = false


func _ready() -> void:
	close_button.pressed.connect(_hide)
	more_button.pressed.connect(_toggle_description)
	EventBus.enemy_inspected.connect(_on_enemy_inspected)
	EventBus.pause_state_changed.connect(_on_pause_state_changed)


func _on_pause_state_changed(paused: bool) -> void:
	if not paused:
		_hide()


func _on_enemy_inspected(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_enemy_ref = weakref(enemy)
	_populate_static(enemy)
	_refresh_dynamic(enemy)
	panel.visible = true


func _hide() -> void:
	panel.visible = false
	_enemy_ref = null


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	var e: Node = _resolve()
	if e == null:
		_hide()
		return
	_refresh_dynamic(e)


func _resolve() -> Node:
	if _enemy_ref == null:
		return null
	var e: Object = _enemy_ref.get_ref()
	if e == null or not is_instance_valid(e):
		return null
	# "state" == 3 (DYING) means the death animation is playing; don't
	# keep the card around through that.
	if "state" in e and e.state == 3:
		return null
	return e


func _populate_static(enemy: Node) -> void:
	var data = enemy.data if "data" in enemy else null
	name_label.text = String(data.enemy_name) if data != null else "Enemy"
	var lines: PackedStringArray = PackedStringArray()
	if data != null:
		var armor: float = enemy.get_effective_armor() if enemy.has_method("get_effective_armor") else float(data.armor)
		var magres: float = enemy.get_effective_magic_resist() if enemy.has_method("get_effective_magic_resist") else float(data.magic_resist)
		lines.append("[b]Armor[/b]  %d%%" % int(round(armor * 100.0)))
		lines.append("[b]Magic resist[/b]  %d%%" % int(round(magres * 100.0)))
		lines.append("[b]Speed[/b]  %.0f" % float(data.move_speed))
		if "is_flying" in data and data.is_flying:
			lines.append("[i]Flying[/i]")
	stats_label.text = "\n".join(lines)
	# Encyclopedia description — only show the More toggle if the enemy data
	# has authored a non-empty entry. Reset to collapsed on every new tap so
	# the player isn't stuck with stale Description state from a prior enemy.
	var desc: String = String(data.encyclopedia_entry) if data != null and "encyclopedia_entry" in data else ""
	_has_description = desc.strip_edges() != ""
	description_label.text = desc
	_show_description = false
	_apply_description_visibility()


func _toggle_description() -> void:
	_show_description = not _show_description
	_apply_description_visibility()


func _apply_description_visibility() -> void:
	more_button.visible = _has_description
	description_label.visible = _has_description and _show_description
	more_button.text = "Less ▴" if _show_description else "More ▾"


func _refresh_dynamic(enemy: Node) -> void:
	var max_hp: int = enemy._effective_max_health() if enemy.has_method("_effective_max_health") else int(enemy.data.max_health if "data" in enemy and enemy.data != null else 1)
	var cur_hp: int = enemy.current_health if "current_health" in enemy else 0
	hp_label.text = "HP  %d / %d" % [cur_hp, max_hp]
	_refresh_effects(enemy)


func _refresh_effects(enemy: Node) -> void:
	if not "_effects" in enemy:
		effects_label.visible = false
		return
	var effects: Dictionary = enemy._effects
	if effects.is_empty():
		effects_label.visible = false
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Effects[/b]")
	for id in effects.keys():
		var e = effects[id]
		# BaseEnemy._tick_effects ticks `duration` down in place — it IS the
		# remaining time. No separate "remaining_time" field exists.
		var remaining: float = float(e.duration) if e != null and "duration" in e else 0.0
		lines.append("  • %s  (%.1fs)" % [String(id), remaining])
	effects_label.text = "\n".join(lines)
	effects_label.visible = true
