extends CanvasLayer

# Tactical-pause hero inspector. Opens on EventBus.hero_inspected (emitted
# by HeroHudPortrait when tapped during pause). Stats are sourced through
# `HeroStats.effective_for(hero_id)` per Preventive Bug Rule 1 — never
# reading base HeroData fields for display, so item modifiers + per-level
# growth + meta multipliers all stack correctly.
#
# Lives on its own CanvasLayer above the EnemyInfoCard (layer 11 vs 10) so
# the two inspectors don't fight over z-order. Auto-closes on resume.

@onready var root: Control = %Root
@onready var dim: ColorRect = %Dim
@onready var name_label: Label = %NameLabel
@onready var level_hp_label: Label = %LevelHpLabel
@onready var close_button: Button = %CloseButton
@onready var more_button: Button = %MoreButton
@onready var stats_label: RichTextLabel = %StatsLabel
@onready var items_label: RichTextLabel = %ItemsLabel
@onready var skills_label: RichTextLabel = %SkillsLabel
@onready var talents_label: RichTextLabel = %TalentsLabel
@onready var description_sep: HSeparator = %Sep5
@onready var description_header: Label = %DescriptionHeader
@onready var description_label: RichTextLabel = %DescriptionLabel

var _hero_id: String = ""
var _hero_ref: WeakRef = null
var _show_description: bool = false
var _has_description: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(_hide)
	more_button.pressed.connect(_toggle_description)
	dim.gui_input.connect(_on_dim_input)
	EventBus.hero_inspected.connect(_on_hero_inspected)
	EventBus.pause_state_changed.connect(_on_pause_state_changed)


func _on_pause_state_changed(paused: bool) -> void:
	if not paused:
		_hide()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_hide()


func _on_hero_inspected(hero_id: String) -> void:
	if hero_id == "":
		return
	_hero_id = hero_id
	_hero_ref = null
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.data != null and h.data.hero_id == hero_id:
			_hero_ref = weakref(h)
			break
	_populate(hero_id)
	root.visible = true


func _hide() -> void:
	root.visible = false
	_hero_id = ""
	_hero_ref = null


# Live HP update — the rest is static (items/skills/talents don't change
# mid-level except via skill cast / item drop, both fine to refresh-on-open).
func _process(_delta: float) -> void:
	if not root.visible or _hero_ref == null:
		return
	var h: Object = _hero_ref.get_ref()
	if h == null or not is_instance_valid(h):
		return
	_refresh_hp_line(h)


func _populate(hero_id: String) -> void:
	var hero_data: Resource = ContentRegistry.find_hero(hero_id)
	if hero_data == null:
		name_label.text = "Unknown hero"
		level_hp_label.text = ""
		stats_label.text = ""
		items_label.text = ""
		skills_label.text = ""
		talents_label.text = ""
		return
	name_label.text = String(hero_data.hero_name)

	var hero_node: Object = _hero_ref.get_ref() if _hero_ref != null else null
	_refresh_hp_line(hero_node)

	# Stats — Preventive Bug Rule 1: route through HeroStats.effective_for.
	var stats: Dictionary = HeroStats.effective_for(hero_id)
	stats_label.text = _format_stats(stats, hero_data)

	# Equipment
	items_label.text = _format_equipped_items(hero_id)

	# Skills
	skills_label.text = _format_equipped_skills(hero_id, hero_data)

	# Talents
	talents_label.text = _format_talents(hero_id)

	# Encyclopedia / lore — collapse to default on every new hero opened.
	var desc: String = String(hero_data.encyclopedia_entry) if "encyclopedia_entry" in hero_data else ""
	_has_description = desc.strip_edges() != ""
	description_label.text = desc
	_show_description = false
	_apply_description_visibility()


func _toggle_description() -> void:
	_show_description = not _show_description
	_apply_description_visibility()


func _apply_description_visibility() -> void:
	more_button.visible = _has_description
	var on: bool = _has_description and _show_description
	description_sep.visible = on
	description_header.visible = on
	description_label.visible = on
	more_button.text = "Less ▴" if _show_description else "More ▾"


func _refresh_hp_line(hero_node: Object) -> void:
	var level: int = MetaProgression.get_hero_level(_hero_id)
	var cur: int = 0
	var max_hp: int = 0
	if hero_node != null and is_instance_valid(hero_node):
		cur = hero_node.current_health if "current_health" in hero_node else 0
		max_hp = hero_node.get_effective_max_health() if hero_node.has_method("get_effective_max_health") else 0
	if max_hp <= 0:
		var stats: Dictionary = HeroStats.effective_for(_hero_id)
		max_hp = int(stats.get("max_health", 0))
		cur = max_hp
	level_hp_label.text = "Lv %d · HP %d / %d" % [level, cur, max_hp]


func _format_stats(stats: Dictionary, hero_data: Resource) -> String:
	if stats.is_empty():
		return "[i]no stats[/i]"
	var dmg: float = float(stats.get("damage", 0.0))
	var spd: float = float(stats.get("attack_speed", 1.0))
	var rng: float = float(stats.get("attack_range", 0.0))
	var armor: float = float(stats.get("armor", 0.0))
	var magres: float = float(stats.get("magic_resist", 0.0))
	var sp: float = float(stats.get("skill_power", 1.0))
	var cdr: float = float(stats.get("cooldown_reduction", 0.0))
	var dps: float = float(stats.get("dps", dmg * spd))
	var engage_r: float = float(hero_data.engage_radius) if "engage_radius" in hero_data else 0.0
	var blocks: int = int(hero_data.max_block_targets) if "max_block_targets" in hero_data else 1
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Damage[/b]  %.0f   [b]Attack speed[/b]  %.2f/s   [b]DPS[/b]  %.0f" % [dmg, spd, dps])
	lines.append("[b]Attack range[/b]  %.0f   [b]Engage radius[/b]  %.0f" % [rng, engage_r])
	lines.append("[b]Armor[/b]  %d%%   [b]Magic resist[/b]  %d%%" % [int(round(armor * 100.0)), int(round(magres * 100.0))])
	lines.append("[b]Skill power[/b]  ×%.2f   [b]Cooldown reduction[/b]  %d%%   [b]Blocks[/b]  %d" % [sp, int(round(cdr * 100.0)), blocks])
	return "\n".join(lines)


func _format_equipped_items(hero_id: String) -> String:
	var items: Array = InventoryManager.get_all_equipped(hero_id)
	if items.is_empty():
		return "[i]nothing equipped[/i]"
	var lines: PackedStringArray = PackedStringArray()
	for inst in items:
		if inst == null:
			continue
		var base_id: String = String(inst.base_id) if "base_id" in inst else ""
		var base: Resource = ContentRegistry.find_item_base(base_id) if base_id != "" else null
		var item_name: String = String(base.base_name) if base != null else base_id if base_id != "" else "?"
		lines.append("  • %s" % item_name)
	if lines.is_empty():
		return "[i]nothing equipped[/i]"
	return "\n".join(lines)


func _format_equipped_skills(hero_id: String, hero_data: Resource) -> String:
	var equipped: Array[String] = LoadoutState.get_equipped_skills(hero_id)
	if equipped.is_empty():
		return "[i]no skills slotted[/i]"
	var lines: PackedStringArray = PackedStringArray()
	for sid in equipped:
		if sid == "":
			continue
		var sname: String = _resolve_skill_name(hero_data, sid)
		lines.append("  • %s" % sname)
	if lines.is_empty():
		return "[i]no skills slotted[/i]"
	return "\n".join(lines)


func _resolve_skill_name(hero_data: Resource, skill_id: String) -> String:
	if hero_data == null or not ("skills" in hero_data):
		return skill_id
	for s in hero_data.skills:
		if s != null and "skill_id" in s and s.skill_id == skill_id:
			return String(s.skill_name) if "skill_name" in s else skill_id
	return skill_id


func _format_talents(hero_id: String) -> String:
	# Talents (legacy/v1 talent system) live in MetaProgression.hero_talents
	# as Array[String] of talent_ids keyed by hero_id. The newer per-rank
	# skill tree lives in hero_skill_progression — show talent_ids only;
	# the panel is at-a-glance, not the full Heroes hub view.
	var talents: Array = MetaProgression.hero_talents.get(hero_id, [])
	if talents.is_empty():
		return "[i]none purchased[/i]"
	var lines: PackedStringArray = PackedStringArray()
	for t in talents:
		lines.append("  • %s" % String(t))
	return "\n".join(lines)
