extends Resource
class_name TalentData

# One talent node in a hero's skill tree. Purchased with total stars
# (same pool as permanent upgrades). When purchased, the linked
# `ability` Resource is pushed onto the hero's AbilityHost at gameplay
# start — the talent becomes a permanent passive for that hero.

@export var talent_id: String = ""
@export var talent_name: String = ""
@export_multiline var description: String = ""
@export var star_cost: int = 1
@export var prerequisite_id: String = ""  # empty = no prereq
# The AbilityData to push onto the hero. Duplicated at runtime so
# per-hero instances don't share mutable state.
@export var ability: Resource = null
