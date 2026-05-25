extends RefCounted

# NOTE: no class_name — callers preload via const, same pattern as
# BalanceOverrides.gd. Keeps the editor's global registry uncluttered.
#
# Single source of truth for the enemy "class key" used by the debug/balance
# tooling (slider panel, wave timeline chart, level overview chart) to
# colorize, sort, and resolve enemy-class identity. Production combat code
# does NOT read this — it operates on EnemyData and content_id directly.
#
# Why centralize: this metadata used to live in 5+ duplicated functions and
# 3 duplicated color dicts across BalanceSliders.gd, WaveTimelineChart.gd
# and LevelOverviewChart.gd. Adding a new enemy required updating every
# site; missing one resulted in silent visual misclassification (the new
# enemy rendered as gray "basic" in charts even though the runtime spawned
# the right scene). Boot-time validation in ContentRegistry now catches
# any future drift before it ships.
#
# Adding a new enemy class:
#   1. Append the class_key to KEYS_IN_PROGRESSION_ORDER at the position
#      matching its difficulty band (lighter → heavier, boss last).
#   2. Add the chart color to COLORS.
#   3. Add the default scene path to SCENE_PATHS (used by the wave editor
#      "+ enemy" dropdown).
#   4. Add a substring match to _SUBSTRING_MATCHES — typically the new
#      class_key itself, e.g. ["necro", "necromancer"]. Match BEFORE
#      "basic" since "basic" is the fallback substring.
#   5. Boot the project; ContentRegistry._validate_class_keys will print
#      [ContentRegistry/DRIFT] warnings if any registered enemy fails to
#      resolve. Fix until silent.


const KEYS_IN_PROGRESSION_ORDER: Array[String] = [
	"basic", "scout", "archer", "flying", "healer", "cultist", "armored", "brute", "boss",
]


# Per-class chart palette. Used by:
#   - WaveTimelineChart.ENEMY_COLORS (bar stack segments + lane glyphs)
#   - LevelOverviewChart.ENEMY_COLORS (per-wave stacked bars)
#   - BalanceSliders._EMITTER_STRIP_COLORS (per-emitter strip ticks)
const COLORS: Dictionary = {
	"basic":   Color(0.65, 0.65, 0.70),
	"scout":   Color(0.95, 0.90, 0.40),
	"archer":  Color(0.55, 0.75, 0.35),
	"armored": Color(0.65, 0.45, 0.25),
	"flying":  Color(0.45, 0.85, 0.95),
	"healer":  Color(0.45, 0.90, 0.55),
	"cultist": Color(0.70, 0.45, 0.95),
	"brute":   Color(0.55, 0.30, 0.30),
	"boss":    Color(0.95, 0.35, 0.55),
}


# Default scene path per class — used by the wave editor's bucket-popup "+"
# button to instantiate a brand-new WaveSpawn when no existing emitter of
# that class is in the bucket. Bosses always start with Boss1; future boss
# variants would need a separate boss_<n> class_key.
const SCENE_PATHS: Dictionary = {
	"basic":   "res://enemies/EnemyBasic.tscn",
	"scout":   "res://enemies/EnemyScout.tscn",
	"archer":  "res://enemies/EnemyGoblinArcher.tscn",
	"armored": "res://enemies/EnemyArmored.tscn",
	"flying":  "res://enemies/EnemyFlying.tscn",
	"healer":  "res://enemies/EnemyHealer.tscn",
	"cultist": "res://enemies/EnemyDarkCultist.tscn",
	"brute":   "res://enemies/EnemyBrute.tscn",
	"boss":    "res://enemies/bosses/Boss1.tscn",
}


# Substring → class_key. Order matters — first match wins. Specific archetypes
# (boss, archer, scout, etc.) come BEFORE "basic" so a name like
# "enemy_basic_grunt" wouldn't accidentally match "basic" before a more
# specific keyword. Substring matching is intentionally loose — both
# enemy_id strings ("enemy_goblin_archer") and scene resource_paths
# ("res://enemies/EnemyGoblinArcher.tscn") resolve through the same table.
const _SUBSTRING_MATCHES: Array[Array] = [
	["boss",    "boss"],
	["archer",  "archer"],
	["cultist", "cultist"],
	["scout",   "scout"],
	["armor",   "armored"],
	["flying",  "flying"],
	["brute",   "brute"],
	["healer",  "healer"],
	["basic",   "basic"],
]


# Returns the class_key matched by substring, or "" if no substring hits.
# Callers that need a defensive default should use class_key_for_safe.
# The "" return is what ContentRegistry's boot validator checks for —
# returning "basic" as a silent fallback would defeat the validator.
static func class_key_for(path_or_id: String) -> String:
	var lower: String = path_or_id.to_lower()
	for pair in _SUBSTRING_MATCHES:
		if lower.contains(String(pair[0])):
			return String(pair[1])
	return ""


# Same as class_key_for but never returns "" — falls back to "basic" so
# chart/sort code can use the result without null-checks. Use the strict
# class_key_for in boot validators where unknown classes must be flagged.
static func class_key_for_safe(path_or_id: String) -> String:
	var k: String = class_key_for(path_or_id)
	return k if k != "" else "basic"


# Returns the chart color for a class_key, falling back to neutral gray.
# Gray is the same color basics use, so an unknown class is at least not
# visually disruptive — but ContentRegistry's validator should have
# already caught missing entries.
static func color_for(class_key: String) -> Color:
	return COLORS.get(class_key, Color(0.55, 0.55, 0.55))


# Returns the progression rank (lower = earlier in the campaign / lighter
# difficulty band). Unknown class_keys sort last. Used by:
#   - BalanceSliders enemy section sort
#   - chart bar segment stacking order
static func progression_rank(class_key: String) -> int:
	var idx: int = KEYS_IN_PROGRESSION_ORDER.find(class_key)
	return idx if idx >= 0 else KEYS_IN_PROGRESSION_ORDER.size()
