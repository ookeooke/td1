extends Control
class_name HeroHudPortrait

# Phase 48 — in-level hero portrait widget for the HUD.
#
# Bottom-right corner of the screen, anchors the new skill cluster (3 skill
# slots arc up-and-left from this disk). Replaces the top-left "Lv X XP Y/Z"
# text in HUD.gd.
#
# Distinct from the EquipmentScreen's `HeroPortrait` class (which draws a
# full procedural body via UnitVisualDrawer for the inventory screen). This
# is the compact HUD dial with HP/XP rings, a level badge, and a tap-to-
# focus interaction.
#
# Visual structure (all procedural _draw()):
#   - Outer ring   : XP progress (yellow), sweeps clockwise from 12 o'clock.
#   - Inner ring   : HP progress  (red→green gradient by health fraction).
#   - Center disk  : class color + glyph (warrior sword / mage star / etc).
#   - Level badge  : small disk in lower-right with the level number.
#   - Respawn time : during DEAD state, replaces level badge with countdown.
#
# Tap → camera focus + select the hero (mirrors KR's tap-portrait behavior).

const SIZE: Vector2 = Vector2(120, 120)
const XP_RING_THICKNESS: float = 8.0
const HP_RING_THICKNESS: float = 6.0
const RING_GAP: float = 2.0
const BADGE_RADIUS: float = 18.0
const BADGE_OFFSET: Vector2 = Vector2(48.0, 48.0)  # from portrait center
const ARC_STEPS: int = 64

var _hero: Node = null
# Polled each frame from _hero.current_health (no HP-change signal today).
var _last_hp: int = -1
var _last_xp: int = -1
var _last_level: int = -1
# Respawn countdown (seconds remaining). Drives the level-badge text overlay.
var _respawn_remaining: float = 0.0


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	# PROCESS_MODE_ALWAYS — the portrait stays interactive while the game is
	# tactical-paused (matches the radial menu / SkillBar / HUD convention).
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_died.connect(_on_hero_died)
	EventBus.hero_respawned.connect(_on_hero_respawned)
	EventBus.hero_xp_gained.connect(_on_xp_changed)
	EventBus.hero_leveled_up.connect(_on_level_changed)
	# Seed from a hero that may already exist (e.g. SkillBar rebuilt mid-run).
	for h in get_tree().get_nodes_in_group("heroes"):
		_hero = h
		break
	queue_redraw()


func _process(delta: float) -> void:
	# Respawn tick — gated to unpaused tree so it matches the SceneTreeTimer
	# the hero uses.
	if _respawn_remaining > 0.0 and not get_tree().paused:
		_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
		queue_redraw()
	if _hero == null or not is_instance_valid(_hero):
		return
	# Cheap state diff — only redraw when something visible changed. HP has no
	# signal today (set directly in BaseHero.take_damage), so polling here is
	# the simplest correct approach.
	var hp: int = _hero.current_health if "current_health" in _hero else 0
	var xp: int = _hero.current_xp if "current_xp" in _hero else 0
	var lv: int = _hero.level if "level" in _hero else 1
	if hp != _last_hp or xp != _last_xp or lv != _last_level:
		_last_hp = hp
		_last_xp = xp
		_last_level = lv
		queue_redraw()


func _on_hero_spawned(hero: Node) -> void:
	_hero = hero
	_respawn_remaining = 0.0
	queue_redraw()


func _on_hero_died() -> void:
	_respawn_remaining = _hero.data.respawn_time if _hero != null and is_instance_valid(_hero) and _hero.data != null else 30.0
	queue_redraw()


func _on_hero_respawned() -> void:
	_respawn_remaining = 0.0
	queue_redraw()


func _on_xp_changed(_amount: int) -> void:
	queue_redraw()


func _on_level_changed(_new_level: int) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Tap → focus camera + select the hero. Matches KR's tap-portrait UX.
	if event is InputEventScreenTouch and event.pressed:
		accept_event()
		if _hero != null and is_instance_valid(_hero):
			EventBus.camera_focus_requested.emit(_hero.global_position, 0.35)
			if _hero.has_method("set_selected"):
				_hero.set_selected(true)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var outer_radius: float = minf(size.x, size.y) * 0.5
	var xp_inner: float = outer_radius - XP_RING_THICKNESS
	var hp_outer: float = xp_inner - RING_GAP
	var hp_inner: float = hp_outer - HP_RING_THICKNESS
	var disk_radius: float = hp_inner - RING_GAP
	# Background plate so the rings read on busy backgrounds.
	draw_circle(center, outer_radius, Color(0.06, 0.07, 0.10, 0.85))

	# Outer ring — XP track + filled arc, sweeping clockwise from 12 o'clock.
	var xp_radius: float = (outer_radius + xp_inner) * 0.5
	draw_arc(center, xp_radius, 0.0, TAU, ARC_STEPS,
		Color(0.20, 0.18, 0.10, 0.85), XP_RING_THICKNESS, true)
	var xp_frac: float = _xp_fraction()
	if xp_frac > 0.0:
		draw_arc(center, xp_radius, -PI * 0.5,
			-PI * 0.5 + TAU * xp_frac, ARC_STEPS,
			ThemeColors.ACCENT_GOLD, XP_RING_THICKNESS, true)

	# Inner ring — HP track + filled arc (red→green by fraction).
	var hp_radius: float = (hp_outer + hp_inner) * 0.5
	draw_arc(center, hp_radius, 0.0, TAU, ARC_STEPS,
		Color(0.10, 0.08, 0.06, 0.85), HP_RING_THICKNESS, true)
	var hp_frac: float = _hp_fraction()
	if hp_frac > 0.0:
		var hp_color: Color = ThemeColors.ACCENT_RED.lerp(
			ThemeColors.ACCENT_GREEN, clampf(hp_frac, 0.0, 1.0))
		draw_arc(center, hp_radius, -PI * 0.5,
			-PI * 0.5 + TAU * hp_frac, ARC_STEPS,
			hp_color, HP_RING_THICKNESS, true)

	# Center disk — class color + glyph.
	var disk_color: Color = _class_color()
	draw_circle(center, disk_radius, disk_color)
	draw_arc(center, disk_radius, 0.0, TAU, ARC_STEPS,
		Color(0.0, 0.0, 0.0, 0.85), 2.0, true)
	_draw_class_glyph(center, disk_radius * 0.55)

	# Level badge — small filled disk in lower-right of portrait.
	var badge_pos: Vector2 = center + BADGE_OFFSET
	draw_circle(badge_pos, BADGE_RADIUS, Color(0.10, 0.12, 0.16, 1.0))
	draw_arc(badge_pos, BADGE_RADIUS, 0.0, TAU, ARC_STEPS,
		ThemeColors.ACCENT_GOLD, 2.0, true)
	var font: Font = ThemeDB.fallback_font
	var badge_text: String
	if _respawn_remaining > 0.0:
		badge_text = "%.0f" % ceil(_respawn_remaining)
	else:
		badge_text = str(_last_level if _last_level > 0 else 1)
	var bs: int = 18
	var ts: Vector2 = font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_CENTER, -1, bs)
	draw_string(font, badge_pos - Vector2(ts.x * 0.5, -bs * 0.35),
		badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, ThemeColors.TEXT_PRIMARY)


func _xp_fraction() -> float:
	if _hero == null or not is_instance_valid(_hero) or _hero.data == null:
		return 0.0
	if _last_level >= int(_hero.data.max_level):
		return 1.0
	var need: int = _hero._xp_needed_for_next_level() if _hero.has_method("_xp_needed_for_next_level") else 0
	if need <= 0:
		return 0.0
	return clampf(float(_last_xp) / float(need), 0.0, 1.0)


func _hp_fraction() -> float:
	if _hero == null or not is_instance_valid(_hero):
		return 0.0
	var max_hp: int = 1
	if _hero.has_method("_effective_max_health"):
		max_hp = maxi(1, _hero._effective_max_health())
	elif _hero.data != null:
		max_hp = maxi(1, _hero.data.max_health)
	return clampf(float(_last_hp) / float(max_hp), 0.0, 1.0)


func _class_color() -> Color:
	# Lookup by hero_id — same convention TowerIconButton uses for tower glyphs.
	# Add a case here when a new hero ships; falls back to a neutral steel.
	var hid: String = ""
	if _hero != null and is_instance_valid(_hero) and _hero.data != null:
		hid = _hero.data.hero_id
	match hid:
		"hero_warrior": return Color(0.45, 0.30, 0.20)  # bronze
		"hero_mage":    return Color(0.30, 0.25, 0.55)  # arcane purple
		"hero_ranger":  return Color(0.25, 0.45, 0.30)  # forest green
		"hero_paladin": return Color(0.55, 0.50, 0.25)  # gilt gold
	return Color(0.35, 0.38, 0.45)


func _draw_class_glyph(c: Vector2, r: float) -> void:
	var hid: String = ""
	if _hero != null and is_instance_valid(_hero) and _hero.data != null:
		hid = _hero.data.hero_id
	var fg: Color = ThemeColors.TEXT_PRIMARY
	match hid:
		"hero_warrior":
			# Sword — vertical line + crossguard + pommel.
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.7), fg, 3.0)
			draw_line(c + Vector2(-r * 0.45, 0.0), c + Vector2(r * 0.45, 0.0), fg, 3.0)
			draw_circle(c + Vector2(0, r * 0.8), 4.0, fg)
		"hero_mage":
			# Five-point star.
			var pts: PackedVector2Array = PackedVector2Array()
			for i in 5:
				var a_outer: float = -PI * 0.5 + TAU * float(i) / 5.0
				var a_inner: float = a_outer + PI / 5.0
				pts.append(c + Vector2(cos(a_outer), sin(a_outer)) * r)
				pts.append(c + Vector2(cos(a_inner), sin(a_inner)) * r * 0.45)
			draw_colored_polygon(pts, fg)
		"hero_ranger":
			# Bow — vertical arc + bowstring.
			draw_arc(c, r, -PI * 0.4, PI * 0.4, 24, fg, 3.0, true)
			draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.85), fg, 1.5)
		"hero_paladin":
			# Shield — rounded triangle silhouette.
			var shield: PackedVector2Array = PackedVector2Array([
				c + Vector2(-r * 0.7, -r * 0.5),
				c + Vector2(r * 0.7, -r * 0.5),
				c + Vector2(r * 0.7, r * 0.1),
				c + Vector2(0, r),
				c + Vector2(-r * 0.7, r * 0.1),
			])
			draw_colored_polygon(shield, fg)
		_:
			# Generic placeholder — solid disk.
			draw_circle(c, r * 0.5, fg)
