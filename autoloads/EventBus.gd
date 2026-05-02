extends Node

# Enemy
signal enemy_spawned(enemy, path_id)
signal enemy_died(enemy, gold_value)
signal enemy_reached_end(enemy, lives_lost)
signal enemy_damaged(enemy, amount, dmg_type)

# Combat (any unit taking damage; drives hit sparks, boss-shake, etc.)
signal hit_landed(target, source, amount, dmg_type)
signal soldier_fell(soldier, facing_dir)

# Tower
signal tower_built(tower, spot_id)
signal tower_sold(tower, refund)
signal tower_upgraded(tower, new_level)
signal tower_upgrade_requested(spot_id)
signal tower_branch_upgrade_requested(spot_id, branch_idx)
signal tower_branch_chosen(tower, branch)
signal tower_spot_tapped(spot_id)
signal tower_range_preview_requested(tower)
signal tower_build_requested(spot_id, tower_id)
signal tower_sell_requested(spot_id)
signal tower_menu_dismissed()

# Soldiers
signal soldier_spawned(soldier, tower)
signal soldier_died(soldier)
signal soldier_blocking(soldier, enemy)
signal barracks_rally_move_requested(barracks)

# Wave
signal wave_started(wave_number, path_ids)
# wave_spawning_complete: last enemy of wave N has been *spawned* (not killed).
# Triggers next wave's countdown — see CORE RULE 19 (early-call overlap).
signal wave_spawning_complete(wave_number)
# wave_completed: every enemy of wave N is dead/leaked. Bounty pays here.
signal wave_completed(wave_number)
signal early_wave_triggered(bonus_gold)
signal wave_countdown_started(duration)
signal all_waves_completed()
signal clean_view_toggled(enabled)
signal spawn_direction_changed(path_id, screen_edge_position)

# Economy
signal gold_changed(new_amount)
signal lives_changed(new_amount)
signal stars_changed(total_stars)
# Persistent meta-currency. Run-gold (gold_changed) is volatile per level;
# meta-gold survives across levels. Earned today by selling items in the
# Equipment tab; future Town phases will let the player spend it.
signal meta_gold_changed(new_amount)
signal item_sold(instance, gold_reward)

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
# Fired by BaseHero._level_up_apply() when a skill's level_required is
# reached. WorldMap badge + Toast listen. Equipping is still manual — the
# player picks from Heroes → Skills.
signal hero_skill_unlocked(hero_id, skill_id)
# Fired by LoadoutState.set_equipped_skill() when the loadout changes.
# SkillBar listens to rebuild the in-level slot cluster.
signal hero_skill_equipped(hero_id, slot, skill_id)

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

# Camera
signal map_tap_confirmed(screen_pos, claim)
signal camera_focus_requested(world_pos, duration)

# Items / Loot (Phase 48)
signal item_dropped(instance, world_pos)
signal item_picked_up(instance)
signal item_equipped(hero_id, slot, instance)
signal item_unequipped(hero_id, slot, instance)
signal inventory_changed()

# Game flow
signal game_over()
signal game_won()
signal pause_requested()
signal encyclopedia_entry_unlocked(content_id)
signal iap_purchase_completed(product_id, unlock_id)


func _ready() -> void:
	print("[EventBus] loaded")
