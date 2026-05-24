extends GutTest

# Coverage for the small read-only helpers in RunStatsDigest. The full digest
# is exercised indirectly via BalanceReport; this file pins the new
# defeat_wave_counts contract which the Phase 3 Wave Diagnostics Panel
# depends on (correct "died here" math — defeats only, not victories).


func _run(level_id: String, outcome: String, final_wave: int, reason: String = "") -> Dictionary:
	return {
		"level_id": level_id,
		"outcome": outcome,
		"final_wave_reached": final_wave,
		"defeat_reason": reason,
	}


func test_defeat_wave_counts_excludes_victories() -> void:
	# Three W10 victories + two W4 defeats (lives_zero) on level_5 → {4:2}
	# (victories on W10 must NOT show up as "died at W10").
	var runs := [
		_run("level_5", "victory", 10),
		_run("level_5", "victory", 10),
		_run("level_5", "victory", 10),
		_run("level_5", "defeat", 4, "lives_zero"),
		_run("level_5", "defeat", 4, "lives_zero"),
	]
	var d: Dictionary = RunStatsDigest.defeat_wave_counts(runs, "level_5")
	assert_eq(int(d.get(4, 0)), 2, "two lives_zero defeats counted at W4")
	assert_eq(int(d.get(10, 0)), 0, "victories at W10 NOT counted as deaths")
	assert_eq(d.size(), 1, "only the W4 entry exists")


func test_defeat_wave_counts_filters_by_level() -> void:
	var runs := [
		_run("level_5", "defeat", 3, "lives_zero"),
		_run("level_6", "defeat", 3, "lives_zero"),
	]
	var d5: Dictionary = RunStatsDigest.defeat_wave_counts(runs, "level_5")
	var d6: Dictionary = RunStatsDigest.defeat_wave_counts(runs, "level_6")
	assert_eq(int(d5.get(3, 0)), 1, "level_5 sees its defeat")
	assert_eq(int(d6.get(3, 0)), 1, "level_6 sees its defeat independently")
	assert_eq(d5.size(), 1, "level_5 doesn't pick up level_6's runs")


func test_defeat_wave_counts_ignores_other_defeat_reasons() -> void:
	# Only defeat_reason == "lives_zero" counts as a real "died here" — other
	# defeat reasons (timeout, crash, abandon) shouldn't inflate the wave death
	# histogram.
	var runs := [
		_run("level_5", "defeat", 5, "lives_zero"),
		_run("level_5", "defeat", 5, "timeout"),
		_run("level_5", "defeat", 5, "abandon"),
	]
	var d: Dictionary = RunStatsDigest.defeat_wave_counts(runs, "level_5")
	assert_eq(int(d.get(5, 0)), 1, "only the lives_zero defeat counts")


func test_defeat_wave_counts_empty_returns_empty() -> void:
	var d: Dictionary = RunStatsDigest.defeat_wave_counts([], "level_5")
	assert_eq(d.size(), 0, "empty input → empty dict, no crash")


# Regression: a pre-existing line `String(r.get("final_wave_reached", 0))`
# in level_digest errored at runtime ("Nonexistent 'String' constructor")
# whenever `final_wave_reached` was an int — which is the real shape every
# saved run carries. The bug stayed dormant until the Phase 3 Wave
# Diagnostics Panel started calling level_digest() at panel-open time on
# real history. Fix was `String(...)` → `str(...)`. This test pins that the
# function returns cleanly on a realistic run shape.
func test_level_digest_handles_int_final_wave_reached() -> void:
	var runs := [
		{
			"level_id": "level_5",
			"outcome": "victory",
			"final_wave_reached": 10,     # int, as actually saved
			"defeat_reason": "",
			"naked_baseline": false,
			"overrides_active": true,
			"duration_s": 600.0,
			"final_gold": 250,
		},
		{
			"level_id": "level_5",
			"outcome": "defeat",
			"final_wave_reached": 4,
			"defeat_reason": "lives_zero",
			"naked_baseline": false,
			"overrides_active": true,
			"duration_s": 180.0,
			"final_gold": 120,
		},
	]
	var d: Dictionary = RunStatsDigest.level_digest(runs, "level_5")
	assert_eq(int(d.get("n_runs", 0)), 2,
		"level_digest aggregates both runs without erroring on int final_wave_reached")
	var dist: Dictionary = d.get("final_wave_dist", {})
	# Keys are stringified ints ("10" and "4").
	assert_eq(int(dist.get("10", 0)), 1, "victory's W10 counted")
	assert_eq(int(dist.get("4", 0)), 1, "defeat's W4 counted")
