extends SkillData
class_name SlashSkillData

# Single-target heavy strike. Delivers damage instantly to the supplied
# enemy. Damage routes through DamageCalculator via BaseEnemy.take_damage,
# so armor / magic_resist / true-damage rules apply. Source = hero, so
# the kill still counts as a hero kill for XP.


func apply(hero: Node, target) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not (target is BaseEnemy):
		return
	var enemy: BaseEnemy = target
	if enemy.state == BaseEnemy.State.DYING:
		return
	enemy.take_damage(damage, damage_type, hero)
