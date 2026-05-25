extends GutTest

# Whole-codebase bug/edge audit — 2026-05-18. 10 cases that each assert the
# CORRECT contract, so they currently FAIL (red) and pinpoint a confirmed,
# player-reachable defect. NO production code is touched by this pass; see
# docs/BUG_EDGE_AUDIT_2026-05-18.md for the full triage (incl. the false
# positives that were rejected and the deferred latent list).
#
# Headless-limit convention (mirrors test_combat_blocking.gd header): where a
# defect lives in scene/transition code GUT can't safely drive, the test is a
# CHARACTERIZATION assertion on the observable contract, marked inline.
#
# When a bug is fixed, the matching test flips green and becomes its
# regression lock — do NOT delete it.

const _EquipmentScreenScript := preload("res://ui/EquipmentScreen.gd")
const _HeroSkillsPageScript := preload("res://ui/HeroSkillsPage.gd")

var _spawned: Array[Node] = []
var _restore: Array[Callable] = []


func after_each() -> void:
	for c in _restore:
		c.call()
	_restore.clear()
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


# ── #1 EquipmentScreen has no _exit_tree (Preventive Bug Rule 3) ─────────
# It connects EventBus.hero_selected / item_equipped / inventory_changed /
# meta_gold_changed in _ready() but never disconnects. HeroSkillsPage (the
# documented reference pattern) DOES. Embedded in HeroesHub which queue_frees
# it → stale handlers fire on a freed node after leaving the hub.
func test_equipmentscreen_defines_exit_tree() -> void:
	var es: Node = _EquipmentScreenScript.new()
	_spawned.append(es)
	var ref: Node = _HeroSkillsPageScript.new()
	_spawned.append(ref)
	assert_true(ref.has_method("_exit_tree"),
		"reference: HeroSkillsPage defines _exit_tree (the correct pattern)")
	assert_true(es.has_method("_exit_tree"),
		"BUG: EquipmentScreen must define _exit_tree to disconnect its EventBus " +
		"signals (Preventive Bug Rule 3) — it currently does not")


# ── #2 EquipmentScreen binds hero_selected as an anonymous lambda ────────
# Even if _exit_tree existed, an inline lambda has no stable Callable to
# disconnect. The handler must be a named method so cleanup is possible.
func test_equipmentscreen_hero_selected_handler_is_named_method() -> void:
	var es: Node = _EquipmentScreenScript.new()
	_spawned.append(es)
	# A correctly-written embedded screen exposes a named refresh/state
	# handler it can both connect AND disconnect (see HeroSkillsPage
	# _on_state_changed). EquipmentScreen wires a closure instead.
	var has_named: bool = es.has_method("_on_hero_selected") \
		or es.has_method("_on_state_changed") \
		or es.has_method("_on_hero_changed")
	assert_true(has_named,
		"BUG: EquipmentScreen connects EventBus.hero_selected via an anonymous " +
		"lambda — un-disconnectable. It needs a named handler method.")


# ── #3 / #4 MetaProgression.add_hero_xp emits before committing entry ────
# hero_xp_gained (line ~638) and hero_leveled_up (~648) fire while
# entry["xp"]/["level"] aren't written until ~664-665. A listener that
# re-queries get_hero_level/get_hero_xp during the signal sees stale values.
func _xp_to_cross_one_level(hid: String) -> int:
	var hd: Resource = ContentRegistry.find_hero(hid)
	var lvl: int = MetaProgression.get_hero_level(hid)
	var idx: int = lvl - 1
	if hd == null or idx < 0 or idx >= hd.xp_per_level.size():
		return 0
	return int(hd.xp_per_level[idx]) + 1


func _snapshot_hero_progress(hid: String) -> void:
	var before: Dictionary = (MetaProgression.hero_progress.get(hid, {}) as Dictionary).duplicate(true)
	_restore.append(func():
		if before.is_empty():
			MetaProgression.hero_progress.erase(hid)
		else:
			MetaProgression.hero_progress[hid] = before
		if MetaProgression.has_method("_persist"):
			MetaProgression._persist())


func test_add_hero_xp_level_committed_before_signal() -> void:
	if ContentRegistry.heroes.is_empty():
		pass_test("no heroes registered (skip)")
		return
	var hid: String = String(ContentRegistry.heroes[0].hero_id)
	_snapshot_hero_progress(hid)
	MetaProgression.hero_progress[hid] = {"level": 1, "xp": 0, "last_synced_level": 1}
	var need: int = _xp_to_cross_one_level(hid)
	if need <= 0:
		pass_test("hero already max level (skip)")
		return
	var seen_level: Array = [-1]
	var emitted: Array = [-2]
	var cb := func(new_lvl: int):
		emitted[0] = new_lvl
		seen_level[0] = MetaProgression.get_hero_level(hid)
	EventBus.hero_leveled_up.connect(cb)
	_restore.append(func():
		if EventBus.hero_leveled_up.is_connected(cb):
			EventBus.hero_leveled_up.disconnect(cb))
	MetaProgression.add_hero_xp(hid, need)
	assert_eq(seen_level[0], emitted[0],
		"BUG: get_hero_level() during hero_leveled_up returns the OLD level " +
		"(emitted %s, dict still %s) — entry committed after the emit" % [emitted[0], seen_level[0]])


func test_add_hero_xp_xp_committed_before_signal() -> void:
	if ContentRegistry.heroes.is_empty():
		pass_test("no heroes registered (skip)")
		return
	var hid: String = String(ContentRegistry.heroes[0].hero_id)
	_snapshot_hero_progress(hid)
	MetaProgression.hero_progress[hid] = {"level": 1, "xp": 0, "last_synced_level": 1}
	var xp_before: int = MetaProgression.get_hero_xp(hid)
	var seen_xp: Array = [-1]
	var cb := func(_amt: int):
		seen_xp[0] = MetaProgression.get_hero_xp(hid)
	EventBus.hero_xp_gained.connect(cb)
	_restore.append(func():
		if EventBus.hero_xp_gained.is_connected(cb):
			EventBus.hero_xp_gained.disconnect(cb))
	MetaProgression.add_hero_xp(hid, 5)  # small, no level-up
	assert_ne(seen_xp[0], xp_before,
		"BUG: get_hero_xp() during hero_xp_gained still returns the pre-gain " +
		"value (%d) — entry['xp'] committed after the emit" % xp_before)


# ── #5 TowerRadialMenu backdrop reacts to InputEventMouseButton ──────────
# CLAUDE.md: with emulate_touch_from_mouse a PC click fires BOTH a mouse and
# a touch event; handlers must process ScreenTouch ONLY. The backdrop also
# branches on InputEventMouseButton → one click dismisses twice on PC.
func test_radialmenu_backdrop_ignores_mouse_button() -> void:
	assert_eq(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse"), true,
		"precondition: emulate_touch_from_mouse on (PC click ⇒ duplicate touch event)")
	var scn: PackedScene = load("res://ui/TowerRadialMenu.tscn")
	assert_not_null(scn, "TowerRadialMenu.tscn loads")
	var menu: Node = scn.instantiate()
	_spawned.append(menu)
	add_child(menu)
	# Characterization: a correctly-written backdrop handler must not classify
	# an InputEventMouseButton as a tap (the touch twin already covers PC).
	assert_true(menu.has_method("_on_backdrop_input"), "backdrop handler present")
	var src := (menu.get_script() as GDScript).source_code
	assert_false(src.contains("InputEventMouseButton"),
		"BUG: TowerRadialMenu handles InputEventMouseButton — on PC the duplicate " +
		"mouse+touch pair double-fires the backdrop dismiss (CLAUDE.md input rule)")


# ── #6 SceneManager has no recovery when change_scene_to_file fails ──────
# goto() sets _transitioning + opaque black STOP rect, then schedules
# change_scene_to_file via tween. The return value is never checked and no
# abort path exists, so a failed/typo'd path soft-locks the game forever.
# Characterization (driving a real failed change_scene would wreck the GUT
# scene tree): assert a recovery/guard affordance exists.
func test_scenemanager_has_failed_transition_recovery() -> void:
	var sm: Node = get_node_or_null("/root/SceneManager")
	assert_not_null(sm, "SceneManager autoload present")
	if sm == null:
		return
	var src := (sm.get_script() as GDScript).source_code
	var guards_path: bool = src.contains("ResourceLoader.exists") \
		or src.contains("FileAccess.file_exists")
	var has_abort: bool = sm.has_method("abort_transition") or sm.has_method("reset")
	assert_true(guards_path or has_abort,
		"BUG: SceneManager.goto neither validates the scene path " +
		"(ResourceLoader.exists) nor exposes an abort/reset — a failed " +
		"change_scene_to_file leaves _transitioning=true + a black STOP rect " +
		"and every later goto() early-returns (permanent soft-lock)")


# ── #7 InventoryManager re-persists the legacy "" hero key ──────────────
# Pre-2026-04-29 saves contain hero_equipment:{"":{...}}. from_save_dict
# deep-dupes the dict verbatim and never strips the empty key, so every
# subsequent save carries the orphan forever.
func test_inventory_from_save_dict_drops_empty_hero_key() -> void:
	var im: Node = get_node_or_null("/root/InventoryManager")
	assert_not_null(im, "InventoryManager autoload present")
	if im == null:
		return
	var before: Dictionary = (im.hero_equipment as Dictionary).duplicate(true)
	var before_shared: Array = (im.shared_inventory as Array).duplicate()
	_restore.append(func():
		im.hero_equipment = before
		im.shared_inventory = before_shared)
	im.from_save_dict({
		"shared_inventory": [],
		"hero_equipment": {"": {"0": "", "1": ""}, "hero_warrior": {"0": ""}},
		"starter_gear_granted": [],
	})
	assert_false(im.hero_equipment.has(""),
		"BUG: from_save_dict re-imports the legacy empty-string hero key — " +
		"permanent save bloat for every migrating player")


# ── #8 LoadoutState.get_effective_ppt does not self-heal stale nodes ─────
# CORE RULE 20: reads that resolve a content_id MUST purge entries the
# catalog no longer authors AND persist the cleaned form (get_equipped_skills
# does). get_effective_ppt just `continue`s past a null find_node and leaves
# the stale node_id in MetaProgression.hero_skill_nodes forever.
func test_get_effective_ppt_self_heals_stale_node_ids() -> void:
	var ls: Node = get_node_or_null("/root/LoadoutState")
	var mp: Node = get_node_or_null("/root/MetaProgression")
	if ls == null or mp == null:
		pass_test("autoloads absent (skip)")
		return
	var hid: String = ls.selected_hero_id
	if hid == "" and not ContentRegistry.heroes.is_empty():
		hid = String(ContentRegistry.heroes[0].hero_id)
		ls.selected_hero_id = hid
	var before: Dictionary = (mp.hero_skill_nodes.get(hid, {}) as Dictionary).duplicate(true)
	_restore.append(func():
		if before.is_empty():
			mp.hero_skill_nodes.erase(hid)
		else:
			mp.hero_skill_nodes[hid] = before)
	mp.hero_skill_nodes[hid] = {"__definitely_not_a_real_node__": 1}
	ls.get_effective_ppt()
	assert_false(mp.hero_skill_nodes.get(hid, {}).has("__definitely_not_a_real_node__"),
		"BUG: get_effective_ppt skips a stale skill-tree node id but never " +
		"purges it (CORE RULE 20 self-healing-reads violation)")


# ── #9 EquipmentScreen connect/disconnect imbalance (quantified) ────────
# The concrete leak surface behind #1/#2: _ready() wires several EventBus
# signals but the script contains zero disconnects and no _exit_tree, so
# every one of them outlives the screen. Deterministic source assertion.
func test_equipmentscreen_connect_disconnect_balanced() -> void:
	var src: String = (_EquipmentScreenScript as GDScript).source_code
	var connects: int = _count(src, "EventBus.", ".connect(")
	var disconnects: int = src.count(".disconnect(")
	assert_gt(connects, 0, "precondition: EquipmentScreen connects EventBus signals")
	var msg: String = ("BUG: EquipmentScreen has %d EventBus connect()s and %d " +
		"disconnect()s with no _exit_tree — every connection leaks past the " +
		"screen's life (Preventive Bug Rule 3; HeroSkillsPage is the reference)") \
		% [connects, disconnects]
	assert_true(disconnects >= connects or src.contains("func _exit_tree"), msg)


# Count occurrences of `prefix...needle` on the same line (cheap, good enough
# for a connect-pattern tally on known-formatted source).
func _count(src: String, prefix: String, needle: String) -> int:
	var n := 0
	for line in src.split("\n"):
		if line.contains(prefix) and line.contains(needle):
			n += 1
	return n


# ── #10 BaseHero connects autoload signals in _ready, no _exit_tree ─────
# _ready() does `EventBus.map_tap_confirmed.connect(_on_map_tap)` with NO
# is_connected guard, while combat_lull_changed IS guarded — inconsistent —
# and BaseHero defines no _exit_tree. CLAUDE.md Preventive Bug Rule 4
# (load-bearing invariants must be executable) + Rule 3 spirit: a node that
# subscribes to an autoload across its lifetime needs symmetric teardown.
func test_base_hero_autoload_signal_lifecycle_symmetric() -> void:
	var src := (load("res://heroes/base_hero.gd") as GDScript).source_code
	var raw_connects := src.contains("EventBus.map_tap_confirmed.connect(")
	var guarded := src.contains("is_connected(_on_map_tap)") \
		or src.contains("map_tap_confirmed.is_connected(")
	var has_teardown := src.contains("func _exit_tree")
	assert_true(raw_connects, "precondition: BaseHero subscribes to map_tap_confirmed")
	assert_true(guarded or has_teardown,
		"BUG: BaseHero connects EventBus.map_tap_confirmed with no is_connected " +
		"guard and no _exit_tree, while combat_lull_changed IS guarded — " +
		"asymmetric autoload-signal lifecycle (Preventive Bug Rule 3/4)")
