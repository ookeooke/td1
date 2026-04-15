extends Node

# Enemy
signal enemy_spawned(enemy, path_id)
signal enemy_died(enemy, gold_value)
signal enemy_reached_end(enemy, lives_lost)

# Tower
signal tower_built(tower, spot_id)
signal tower_sold(tower, refund)
signal tower_upgraded(tower, new_level)
signal tower_branch_chosen(tower, branch)
signal tower_spot_tapped(spot_id)
signal tower_range_preview_requested(tower)
signal tower_build_requested(spot_id, tower_id)
signal tower_menu_dismissed()

# Soldiers
signal soldier_spawned(soldier, tower)
signal soldier_died(soldier)
signal soldier_blocking(soldier, enemy)

# Wave
signal wave_started(wave_number, path_ids)
signal wave_completed(wave_number)
signal early_wave_triggered(bonus_gold)
signal all_waves_completed()
signal spawn_direction_changed(path_id, screen_edge_position)

# Economy
signal gold_changed(new_amount)
signal lives_changed(new_amount)
signal stars_changed(total_stars)

# Hero
signal hero_spawned(hero)
signal hero_died()
signal hero_respawned()
signal hero_xp_gained(amount)
signal hero_leveled_up(new_level)
signal hero_skill_used(skill_name)
signal skill_cooldown_started(skill_name, duration)
signal skill_ready(skill_name)
signal hero_selected(hero_id)

# Spells
signal spell_cast(spell_name, position)
signal spell_cooldown_started(spell_name, duration)
signal spell_ready(spell_name)

# Game modes
signal endless_wave_started(wave_number)
signal endless_score_updated(score)
signal challenge_mode_started(mode)

# Progression
signal level_completed(level_id, stars_earned, mode)
signal hero_unlocked(hero_id)
signal tower_unlocked(tower_id)
signal permanent_upgrade_purchased(upgrade_id)
signal skill_point_spent(skill_id)
signal leaderboard_score_submitted(score)

# Game flow
signal game_over()
signal game_won()


func _ready() -> void:
	print("[EventBus] loaded")
