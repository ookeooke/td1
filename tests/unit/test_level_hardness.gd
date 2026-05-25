extends GutTest

func test_all_level_hardness_and_drifts() -> void:
	var level_list_res = load("res://ui/world_map/level_list.tres")
	assert_not_null(level_list_res, "level_list.tres must exist")
	
	var levels = level_list_res.levels
	assert_gt(levels.size(), 0, "There must be levels authored")
	
	# Print header for the tabular report
	print("\n=== LEVEL HARDNESS AND DRIFT REPORT ===")
	print("%-18s | %-12s | %-12s | %-12s | %-10s | %-8s" % ["Level Name", "ID", "Target PPT", "Hardness", "Drift %", "Status"])
	print("------------------------------------------------------------------------------------")
	
	for lvl in levels:
		if lvl == null:
			continue
		var wave_list = load(lvl.wave_list_path)
		if wave_list == null:
			fail_test("Could not load wave list for: " + lvl.level_id)
			continue
			
		var target_ppt: int = lvl.target_ppt if "target_ppt" in lvl else 2
		var starting_gold: int = lvl.starting_gold if "starting_gold" in lvl else 100
		
		# Compute actual score and drift
		var actual_score: float = BalanceCalculator.score_level(wave_list, starting_gold)
		var drift: float = BalanceCalculator.score_for_ppt(wave_list, target_ppt, starting_gold)
		
		var status := "GREEN"
		if absf(drift) > 25.0:
			status = "RED (Out)"
		elif absf(drift) > 15.0:
			status = "YELLOW"
			
		print("%-18s | %-12s | %-12d | %-12.1f | %-+9.1f%% | %-8s" % [
			lvl.display_name, lvl.level_id, target_ppt, actual_score, drift, status
		])
		
		# Assert Level 5 and 6 are within ±90% drift for now (untuned campaign level stub)
		if lvl.level_id == "level_5" or lvl.level_id == "level_6":
			assert_lt(absf(drift), 90.0, "Level %s drift (%+.1f%%) must be within ±90%%" % [lvl.level_id, drift])
