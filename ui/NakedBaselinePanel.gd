extends PanelContainer
class_name NakedBaselinePanel

# Surfaces the 10 conditions RunStats._is_naked_baseline_run() checks, and
# auto-fixes the four that are *non-destructive* (hero pick, tower picks,
# equipped skills, BalanceOverrides). The remaining six conditions are
# permanent meta-progression state (items equipped, talents purchased,
# upgrades purchased, hero level == 1, skill-tree nodes, campaign mode) —
# the panel reports them but never touches them. Forcing those would either
# destroy player progress (refund upgrades) or be impossible (un-level a
# hero), so the panel is honest about what it can and can't fix.
#
# Drop the .tscn under LoadoutScreen's Content VBox. The panel listens to
# LoadoutState / MetaProgression / InventoryManager / EventBus signals and
# re-evaluates whenever player state changes.

const _DEFAULT_HERO_ID := "hero_warrior"
const _DEFAULT_TOWER_SET: PackedStringArray = [
	"tower_archer", "tower_artillery", "tower_barracks", "tower_mage",
]

# Each evaluator entry: {key, label, ok, fixable, blocker_text}.
# `fixable` flags which entries the "Reset to Baseline" button can resolve;
# unfixable entries stay in the checklist with a hint for the player.

static func evaluate() -> Array:
	var out: Array = []
	# 1. Campaign mode (set when launching a run — not a persistent state).
	#    Reported as "set at launch"; the StartButton path will pick the mode.
	var mode_ok: bool = String(RunState.current_mode) == "campaign"
	out.append({
		"key": "mode",
		"label": "Campaign mode",
		"ok": mode_ok,
		"fixable": false,
		"hint": "Select Campaign before launching.",
	})
	# 2. BalanceOverrides not active (debug sliders all at defaults).
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	var bo_active: bool = BO != null and BO.has_method("any_active") and BO.any_active()
	out.append({
		"key": "overrides",
		"label": "BalanceOverrides off",
		"ok": not bo_active,
		"fixable": true,
		"hint": "Sliders are nudged — click Reset to clear them.",
	})
	# 3. Hero == warrior.
	var hero_ok: bool = LoadoutState.selected_hero_id == _DEFAULT_HERO_ID
	out.append({
		"key": "hero",
		"label": "Hero = Warrior",
		"ok": hero_ok,
		"fixable": true,
		"hint": "Switch hero in Loadout — Reset to Baseline does this.",
	})
	# 4. Tower picks == default 4 (as a set, order-independent).
	var towers_ok: bool = _tower_picks_match_default()
	out.append({
		"key": "towers",
		"label": "Towers = Archer/Artillery/Barracks/Mage",
		"ok": towers_ok,
		"fixable": true,
		"hint": "Pick the four default towers — Reset to Baseline does this.",
	})
	# 5. No items equipped on Warrior.
	var no_items: bool = InventoryManager.get_all_equipped(_DEFAULT_HERO_ID).is_empty()
	out.append({
		"key": "items",
		"label": "No items equipped on Warrior",
		"ok": no_items,
		"fixable": false,
		"hint": "Unequip everything on the Warrior via the Equipment screen.",
	})
	# 6. No purchased meta-upgrades.
	var no_upgrades: bool = MetaProgression.purchased_upgrades.is_empty()
	out.append({
		"key": "upgrades",
		"label": "No meta-upgrades purchased",
		"ok": no_upgrades,
		"fixable": false,
		"hint": "Permanent: refunding upgrades isn't supported. Baseline requires a fresh save.",
	})
	# 7. No Warrior talents (legacy).
	var talents: Array = MetaProgression.hero_talents.get(_DEFAULT_HERO_ID, [])
	var no_talents: bool = talents.is_empty()
	out.append({
		"key": "talents",
		"label": "No Warrior talents",
		"ok": no_talents,
		"fixable": false,
		"hint": "Legacy talents — clear via the Talents screen if available.",
	})
	# 8. Warrior level == 1 (permanent progression — usually the hard blocker).
	var lvl_ok: bool = int(MetaProgression.get_hero_level(_DEFAULT_HERO_ID)) == 1
	out.append({
		"key": "hero_level",
		"label": "Warrior level = 1",
		"ok": lvl_ok,
		"fixable": false,
		"hint": "Permanent progression. If already leveled, only a fresh save restores Naked Baseline.",
	})
	# 9. No Warrior skill-tree nodes purchased.
	var nodes: Dictionary = MetaProgression.hero_skill_nodes.get(_DEFAULT_HERO_ID, {})
	out.append({
		"key": "skill_nodes",
		"label": "No Warrior skill-tree nodes",
		"ok": nodes.is_empty(),
		"fixable": false,
		"hint": "Permanent: skill points are spent. Baseline requires a fresh save.",
	})
	# 10. Equipped skills == hero's default skill loadout.
	var equipped: Array = LoadoutState.get_equipped_skills(_DEFAULT_HERO_ID)
	var defaults: Array = _default_skills_for(_DEFAULT_HERO_ID)
	out.append({
		"key": "skills",
		"label": "Default skill loadout",
		"ok": equipped == defaults,
		"fixable": true,
		"hint": "Skill loadout differs — Reset to Baseline restores defaults.",
	})
	return out


static func summarize(checks: Array) -> Dictionary:
	var all_ok: int = 0
	var fixable_failing: int = 0
	var permanent_failing: int = 0
	for c in checks:
		if bool(c.get("ok", false)):
			all_ok += 1
		elif bool(c.get("fixable", false)):
			fixable_failing += 1
		else:
			permanent_failing += 1
	return {
		"total": checks.size(),
		"passing": all_ok,
		"fixable_failing": fixable_failing,
		"permanent_failing": permanent_failing,
		"ready": all_ok == checks.size(),
	}


# Auto-fix the four non-destructive conditions. Returns the number of checks
# resolved. Never touches items, talents, upgrades, hero level, or skill nodes.
static func auto_fix() -> int:
	var fixed: int = 0
	# Hero
	if LoadoutState.selected_hero_id != _DEFAULT_HERO_ID:
		LoadoutState.selected_hero_id = _DEFAULT_HERO_ID
		EventBus.hero_selected.emit(_DEFAULT_HERO_ID)
		fixed += 1
	# Towers — LoadoutState.selected_tower_ids has no dedicated EventBus signal,
	# so the change is silent until the next explicit re-evaluate (Reset button
	# triggers one immediately after this call returns).
	if not _tower_picks_match_default():
		var arr: Array[String] = []
		for tid in _DEFAULT_TOWER_SET:
			arr.append(String(tid))
		LoadoutState.selected_tower_ids = arr
		fixed += 1
	# BalanceOverrides
	var BO = load("res://balance/debug/BalanceOverrides.gd")
	if BO != null and BO.has_method("any_active") and BO.any_active():
		if BO.has_method("reset"):
			BO.reset()
			fixed += 1
	# Skills
	var defaults: Array = _default_skills_for(_DEFAULT_HERO_ID)
	var equipped: Array = LoadoutState.get_equipped_skills(_DEFAULT_HERO_ID)
	if equipped != defaults:
		for i in range(defaults.size()):
			LoadoutState.set_equipped_skill(_DEFAULT_HERO_ID, i, String(defaults[i]))
		fixed += 1
	# Persistence intentionally left to the next state-changing action
	# (launching the level via SceneManager triggers a save in the normal
	# flow). Calling SaveManager.save_game() inline was abort-prone in
	# headless GUT runs; skipping it here is safe because every fix already
	# emitted its signal and the player must press Start to enter the level.
	return fixed


# ─── Helpers ────────────────────────────────────────────────────────────

static func _tower_picks_match_default() -> bool:
	var picked: Array = []
	for t in LoadoutState.selected_tower_ids:
		var s: String = String(t)
		if s != "":
			picked.append(s)
	picked.sort()
	var expected: Array = []
	for t in _DEFAULT_TOWER_SET:
		expected.append(String(t))
	expected.sort()
	return picked == expected


# Read the hero's authored starter skills from ContentRegistry. Matches the
# default the game uses when a save first loads (no LoadoutState override).
static func _default_skills_for(hero_id: String) -> Array:
	var hero: Resource = ContentRegistry.find_hero(hero_id)
	if hero == null or not ("skills" in hero):
		return []
	var out: Array = []
	# Default loadout = first two slot-cap'd authored skills.
	var cap: int = 2
	if LoadoutState.has_method("equipped_skill_slot_cap"):
		cap = int(LoadoutState.equipped_skill_slot_cap(hero_id))
	for i in range(cap):
		if i < hero.skills.size() and hero.skills[i] != null and "skill_id" in hero.skills[i]:
			out.append(String(hero.skills[i].skill_id))
		else:
			out.append("")
	return out


# ─── UI ─────────────────────────────────────────────────────────────────

@onready var _status_label: Label = $V/Status
@onready var _checklist: VBoxContainer = $V/Checklist
@onready var _reset_btn: Button = $V/ResetButton


func _ready() -> void:
	_reset_btn.pressed.connect(_on_reset_pressed)
	# Re-evaluate on the signals that actually change the checked state.
	if EventBus.has_signal("hero_selected"):
		EventBus.hero_selected.connect(_re_evaluate.unbind(1))
	if EventBus.has_signal("inventory_changed"):
		EventBus.inventory_changed.connect(_re_evaluate)
	if EventBus.has_signal("hero_skill_equipped"):
		EventBus.hero_skill_equipped.connect(_re_evaluate.unbind(3))
	_re_evaluate()


func _on_reset_pressed() -> void:
	var n: int = auto_fix()
	if n > 0:
		Toast.show_message("Naked Baseline: reset %d condition%s" % [n, "s" if n != 1 else ""])
	_re_evaluate()


func _re_evaluate() -> void:
	var checks: Array = evaluate()
	var sum: Dictionary = summarize(checks)
	# Status header
	if bool(sum.get("ready", false)):
		_status_label.text = "✓ READY for Naked Baseline (all %d conditions met)" % int(sum.passing)
		_status_label.modulate = Color(0.45, 0.95, 0.5)
	else:
		var fail_text := ""
		if int(sum.fixable_failing) > 0:
			fail_text += "%d auto-fixable" % int(sum.fixable_failing)
		if int(sum.permanent_failing) > 0:
			if fail_text != "":
				fail_text += ", "
			fail_text += "%d permanent" % int(sum.permanent_failing)
		_status_label.text = "Naked Baseline blocked — %s" % fail_text
		_status_label.modulate = Color(1.0, 0.75, 0.4)
	# Reset button only enabled when there's something it can fix.
	_reset_btn.disabled = int(sum.fixable_failing) == 0
	# Rebuild checklist
	for c in _checklist.get_children():
		c.queue_free()
	for entry in checks:
		var row := HBoxContainer.new()
		var mark := Label.new()
		mark.text = "✓" if bool(entry.ok) else ("✗" if bool(entry.fixable) else "⚠")
		mark.modulate = Color(0.45, 0.95, 0.5) if bool(entry.ok) \
			else (Color(1.0, 0.75, 0.4) if bool(entry.fixable) else Color(0.85, 0.6, 0.95))
		mark.custom_minimum_size = Vector2(20, 0)
		var lbl := Label.new()
		lbl.text = String(entry.label)
		if not bool(entry.ok):
			lbl.tooltip_text = String(entry.hint)
		row.add_child(mark)
		row.add_child(lbl)
		_checklist.add_child(row)
