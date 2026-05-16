extends RefCounted
class_name HeroAffinityPreview

# Phase 3 — pure UI teaching helper. Tells the player, in plain language,
# whether an item activates a hero's weapon-family mastery and what the hero
# is "best with". Reuses the SAME matchers the live hero / dressing room use
# (BaseHero._collect_equipped_item_tags + _affinities_to_grant) so the UI can
# never disagree with actual gameplay. No scene deps — static, unit-testable.
#
# Design rule (plan Phase 3): off-family gear must read as ALLOWED, not
# broken. Inactive = "stats still apply", never an error.


# Effective affinity rank for a hero right now (level → curve). Mirrors
# BaseHero._affinity_rank so preview == runtime.
static func _rank_for(hero_id: String) -> int:
	var hd: Resource = ContentRegistry.find_hero(hero_id)
	if hd == null or not hd.has_method("get_level_curve"):
		return 1
	return hd.get_level_curve().affinity_rank_for_level(MetaProgression.get_hero_level(hero_id))


# Short player-facing summary of an affinity's bonus (best-effort, one line).
# Recognizes the common StatModifierAbility fields; unknown abilities fall
# back to the affinity's own display name only.
static func _bonus_summary(aff: Resource) -> String:
	if aff == null or not ("bonus_abilities" in aff):
		return ""
	for ab in aff.bonus_abilities:
		if ab == null:
			continue
		if "damage_pct" in ab and float(ab.damage_pct) > 0.0:
			return "+%d%% damage" % int(round(float(ab.damage_pct) * 100.0))
		if "damage_flat" in ab and float(ab.damage_flat) > 0.0:
			return "+%d damage" % int(round(float(ab.damage_flat)))
		if "armor_pct" in ab and float(ab.armor_pct) > 0.0:
			return "+%d%% armor" % int(round(float(ab.armor_pct) * 100.0))
		if "attack_speed_pct" in ab and float(ab.attack_speed_pct) > 0.0:
			return "+%d%% attack speed" % int(round(float(ab.attack_speed_pct) * 100.0))
	return ""


# Per-item teaching block shown in the gear detail panel. `equipped` is the
# hero's current equipped ItemInstance array (the candidate may or may not
# already be among them — we test "tags present WITH this item").
# Returns { active: bool, title: String, lines: Array[String] }.
static func preview_for_item(hero_id: String, item_base: Resource, equipped: Array) -> Dictionary:
	var inactive := {
		"active": false,
		"title": "No mastery",
		"lines": ["Usable by any hero. Stats still apply."],
	}
	if hero_id == "" or item_base == null or not ("item_tags" in item_base):
		return inactive
	var hd: Resource = ContentRegistry.find_hero(hero_id)
	if hd == null or not ("item_affinities" in hd):
		return inactive
	var affs: Array = hd.item_affinities
	if affs.is_empty():
		return inactive
	var hero_name: String = hd.hero_name if "hero_name" in hd else hero_id
	# Tag set WITH the candidate item folded in (so the player sees what
	# equipping it would unlock, not just the current state).
	var tag_set: Dictionary = BaseHero._collect_equipped_item_tags(equipped)
	for t in item_base.item_tags:
		tag_set[t] = true
	var rank: int = _rank_for(hero_id)
	# Does the candidate's family participate in any of the hero's affinities?
	var item_tag_lookup: Dictionary = {}
	for t in item_base.item_tags:
		item_tag_lookup[t] = true
	var family_relevant := false
	for aff in affs:
		if aff == null or not ("required_item_tags" in aff):
			continue
		for rt in aff.required_item_tags:
			if item_tag_lookup.has(rt):
				family_relevant = true
				break
		if family_relevant:
			break
	if not family_relevant:
		return {
			"active": false,
			"title": "No %s mastery" % hero_name,
			"lines": ["Off-family gear — stats still apply."],
		}
	# Family matches a hero affinity. Is it actually satisfied (all required
	# tags present + rank met)? Same predicate as runtime.
	var granted: Array = BaseHero._affinities_to_grant(affs, tag_set, rank)
	for aff in affs:
		if aff == null or not ("bonus_abilities" in aff):
			continue
		var is_active := false
		for ga in aff.bonus_abilities:
			if ga != null and granted.has(ga):
				is_active = true
				break
		var disp: String = aff.display_name if "display_name" in aff and aff.display_name != "" else "Mastery"
		# Only report the affinity whose family this item belongs to.
		var belongs := false
		for rt in aff.required_item_tags:
			if item_tag_lookup.has(rt):
				belongs = true
				break
		if not belongs:
			continue
		if is_active:
			var summ: String = _bonus_summary(aff)
			var lines: Array = [disp]
			if summ != "":
				lines.append(summ)
			return {"active": true, "title": "Affinity Active", "lines": lines}
		else:
			# Right family, not yet satisfied (needs more required tags or a
			# higher rank). Encourage, don't scold.
			return {
				"active": false,
				"title": "Best With %s" % hero_name,
				"lines": ["%s — equip the full set / level up to unlock." % disp],
			}
	return inactive


# Compact one-liner for the Hero Overview POWER block. Lists the families the
# hero masters and which masteries are currently active with equipped gear.
# Empty string when the hero has no authored affinities (older heroes).
static func overview_line(hero_id: String) -> String:
	var hd: Resource = ContentRegistry.find_hero(hero_id)
	if hd == null or not ("item_affinities" in hd):
		return ""
	var affs: Array = hd.item_affinities
	if affs.is_empty():
		return ""
	var families: Array = []
	for aff in affs:
		if aff == null or not ("required_item_tags" in aff):
			continue
		for rt in aff.required_item_tags:
			if not families.has(rt):
				families.append(rt)
	var equipped: Array = InventoryManager.get_all_equipped(hero_id)
	var tag_set: Dictionary = BaseHero._collect_equipped_item_tags(equipped)
	var rank: int = _rank_for(hero_id)
	var granted: Array = BaseHero._affinities_to_grant(affs, tag_set, rank)
	var active_names: Array = []
	for aff in affs:
		if aff == null or not ("bonus_abilities" in aff):
			continue
		for ga in aff.bonus_abilities:
			if ga != null and granted.has(ga):
				var disp: String = aff.display_name if "display_name" in aff and aff.display_name != "" else "Mastery"
				if not active_names.has(disp):
					active_names.append(disp)
				break
	var out: String = "Best With: %s" % ", ".join(families)
	if not active_names.is_empty():
		out += "\nActive: %s" % ", ".join(active_names)
	return out
