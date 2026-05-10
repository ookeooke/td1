extends Control

# Phase 34: Encyclopedia / Codex. Three tabs (Enemies, Towers, Heroes).
# Auto-generates stat tables from the actual Resource fields so they
# never drift from gameplay values. Flavor text from `encyclopedia_entry`.
# Locked entries show "???" until first encounter unlocks them.
#
# Data source: ContentRegistry autoload (B+D architecture).

enum Tab { ENEMIES, TOWERS, HEROES, ITEMS }

@onready var back_button: Button = %BackButton
@onready var enemies_tab: Button = %EnemiesTab
@onready var towers_tab: Button = %TowersTab
@onready var heroes_tab: Button = %HeroesTab
@onready var items_tab: Button = %ItemsTab
@onready var entry_list: VBoxContainer = %EntryList

var _current_tab: int = Tab.ENEMIES


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	enemies_tab.pressed.connect(_select_tab.bind(Tab.ENEMIES))
	towers_tab.pressed.connect(_select_tab.bind(Tab.TOWERS))
	heroes_tab.pressed.connect(_select_tab.bind(Tab.HEROES))
	items_tab.pressed.connect(_select_tab.bind(Tab.ITEMS))
	_select_tab(Tab.ENEMIES)


func _on_back() -> void:
	SceneManager.goto("res://ui/WorldMap.tscn")


func _select_tab(tab: int) -> void:
	_current_tab = tab
	enemies_tab.modulate = Color.WHITE if tab == Tab.ENEMIES else Color(0.5, 0.5, 0.5)
	towers_tab.modulate = Color.WHITE if tab == Tab.TOWERS else Color(0.5, 0.5, 0.5)
	heroes_tab.modulate = Color.WHITE if tab == Tab.HEROES else Color(0.5, 0.5, 0.5)
	items_tab.modulate = Color.WHITE if tab == Tab.ITEMS else Color(0.5, 0.5, 0.5)
	_rebuild_entries()


func _rebuild_entries() -> void:
	for child in entry_list.get_children():
		child.queue_free()
	match _current_tab:
		Tab.ENEMIES:
			for data in ContentRegistry.enemies:
				_add_entry(_enemy_id(data), _format_enemy(data), data)
		Tab.TOWERS:
			for data in ContentRegistry.towers:
				_add_entry(data.tower_id, _format_tower(data), data)
		Tab.HEROES:
			for data in ContentRegistry.heroes:
				_add_entry(data.hero_id, _format_hero(data), data)
		Tab.ITEMS:
			# Skip the starter bases (never drop). Only show rollable content.
			for data in ContentRegistry.item_bases:
				if data == null or not ("base_id" in data):
					continue
				if data.drop_weight <= 0.0:
					continue
				_add_entry(data.base_id, _format_item(data), data)


func _enemy_id(data: Resource) -> String:
	if "enemy_id" in data and data.enemy_id != "":
		return data.enemy_id
	return data.enemy_name.to_lower().replace(" ", "_")


func _is_unlocked(content_id: String) -> bool:
	return content_id in MetaProgression.encyclopedia_unlocked


func _add_entry(content_id: String, formatted: Dictionary, _data: Resource) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var margin := MarginContainer.new()
	margin.set("theme_override_constants/margin_left", 12)
	margin.set("theme_override_constants/margin_top", 8)
	margin.set("theme_override_constants/margin_right", 12)
	margin.set("theme_override_constants/margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set("theme_override_constants/separation", 4)
	margin.add_child(vbox)

	var unlocked: bool = _is_unlocked(content_id)

	var name_label := Label.new()
	name_label.text = formatted.name if unlocked else "???"
	name_label.set("theme_override_font_sizes/font_size", 20)
	name_label.modulate = Color.WHITE if unlocked else Color(0.4, 0.4, 0.4)
	vbox.add_child(name_label)

	if unlocked:
		var stats_label := Label.new()
		stats_label.text = formatted.stats
		stats_label.set("theme_override_font_sizes/font_size", 14)
		stats_label.modulate = Color(0.8, 0.9, 1.0)
		vbox.add_child(stats_label)

		if formatted.description != "":
			var desc_label := Label.new()
			desc_label.text = formatted.description
			desc_label.set("theme_override_font_sizes/font_size", 14)
			desc_label.modulate = Color(0.7, 0.7, 0.7)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(desc_label)
	else:
		var lock_label := Label.new()
		lock_label.text = "Encounter this unit to unlock its entry."
		lock_label.set("theme_override_font_sizes/font_size", 13)
		lock_label.modulate = Color(0.5, 0.5, 0.5)
		vbox.add_child(lock_label)

	entry_list.add_child(panel)


# ── Auto-stat formatters — one per category ──────────────────────────

func _format_enemy(data: Resource) -> Dictionary:
	var stats: String = "HP %d  SPD %.0f  Armor %.0f%%  M.Resist %.0f%%" % [
		data.max_health, data.move_speed,
		data.armor * 100, data.magic_resist * 100,
	]
	if data.is_flying:
		stats += "  [Flying]"
	if data.abilities.size() > 0:
		var ability_names: PackedStringArray = []
		for a in data.abilities:
			if a != null and "ability_id" in a:
				ability_names.append(a.ability_id)
		if ability_names.size() > 0:
			stats += "  Abilities: " + ", ".join(ability_names)
	return {
		"name": data.enemy_name,
		"stats": stats,
		"description": data.encyclopedia_entry if "encyclopedia_entry" in data else "",
	}


func _format_tower(data: Resource) -> Dictionary:
	var stats: String = "DMG %.0f  RNG %.0f  SPD %.1f  Cost %dg" % [
		data.damage, data.attack_range, data.attack_speed, data.get_effective_cost(),
	]
	if data.targets_flying:
		stats += "  [Hits Air]"
	# Show branch info if L3 branches exist.
	if "level_3_branches" in data and data.level_3_branches.size() > 0:
		var branch_names: PackedStringArray = []
		for b in data.level_3_branches:
			if b != null and "upgrade_name" in b:
				branch_names.append(b.upgrade_name)
		if branch_names.size() > 0:
			stats += "\nBranches: " + " / ".join(branch_names)
	return {
		"name": data.tower_name,
		"stats": stats,
		"description": data.encyclopedia_entry if "encyclopedia_entry" in data else "",
	}


func _format_item(data: Resource) -> Dictionary:
	const _SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Helm", "Gloves", "Boots", "Trinket"]
	const _RARITY_NAMES: Array[String] = ["Common", "Magic", "Rare", "Epic", "Legendary"]
	var slot_name: String = _SLOT_NAMES[clampi(int(data.slot), 0, _SLOT_NAMES.size() - 1)]
	var rarity_name: String = _RARITY_NAMES[clampi(int(data.rarity), 0, _RARITY_NAMES.size() - 1)]
	var stats: String = "%s — %s, %d rolled affix slots" % [rarity_name, slot_name, int(data.affix_slots)]
	if data.min_wave > 1:
		stats += "  [Wave %d+]" % int(data.min_wave)
	if data.allowed_affix_pools.size() > 0:
		stats += "\nAffix pools: " + ", ".join(data.allowed_affix_pools)
	return {
		"name": data.base_name,
		"stats": stats,
		"description": data.description if "description" in data else "",
	}


func _format_hero(data: Resource) -> Dictionary:
	var stats: String = data.get_stats_line()
	if data.skills.size() > 0:
		var skill_names: PackedStringArray = []
		for s in data.skills:
			if s != null and "skill_name" in s:
				skill_names.append(s.skill_name)
		if skill_names.size() > 0:
			stats += "\nSkills: " + ", ".join(skill_names)
	return {
		"name": data.hero_name,
		"stats": stats,
		"description": data.encyclopedia_entry if "encyclopedia_entry" in data else "",
	}
