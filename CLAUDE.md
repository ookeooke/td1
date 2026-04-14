# CLAUDE.md — Fantasy Tower Defense (Kingdom Rush Style)
> Godot 4.6.2 | GDScript | Android + iOS + PC | Touch + Mouse  in claude code terminal

---

## 🔒 CORE RULES — READ BEFORE EVERY RESPONSE

1. **Never modify working scripts.** Append or add new scripts only.
2. **All cross-system communication via EventBus signals only.** No direct node references between unrelated systems.
3. **One script = one responsibility.** Never combine movement, combat, and UI logic in one file.
4. **All stats live in .tres Resource files.** Never hardcode stats inside scripts.
5. **State changes only through a change_state() function.** Never set state variables directly.
6. **All damage through DamageCalculator.calculate_damage().** Never calculate damage inline.
7. **All IAP-locked content checked through UnlockManager before loading.** Never hardcode unlock states.
8. **All save/load through SaveManager only.** No other script touches the save file.
9. **Before changing anything working, explain why the change is needed.** Then wait for approval.
10. **Never skip or combine build phases.** Each phase must be committed to Git before starting the next.

---

## 🎮 Game Reference & Design Decisions

| Property | Decision |
|---|---|
| Style | Kingdom Rush series (Ironhide Game Studio) |
| Theme | Fantasy medieval — knights, mages, orcs, trolls |
| Genre | Tower defense + hero unit + active skills + global spells |
| Platform | Android, iOS (primary) + PC (secondary) |
| Input | Touch + Mouse via "Emulate Touch From Mouse" |
| Aspect ratios | 16:9, 18:9, 19:9, 4:3 — all must work |
| Enemy paths | Multiple paths per level — enemies split across routes |
| Wave transition | Direction markers on screen edges showing spawn points |
| Tower placement | Fixed pre-defined spots only |
| Tower placement input | Select tower type → tap spot |
| Tower upgrades | Branching at level 3 (choice A or B, permanent) |
| Heroes on map | One at a time |
| Hero selection | Chosen in HeroRoom before level starts |
| Soldiers | Yes — barracks spawn soldiers that block enemies |
| Global spells | Yes — two spells deployable anywhere on map |
| Game modes | Campaign + Endless mode |
| Challenge modes | Heroic and Iron per level (like Kingdom Rush) |
| Leaderboard | Online leaderboard |
| Progression | Stars, permanent upgrades, hero unlocks, tower unlocks, skill tree |
| Monetization | Heroes and towers as IAP |
| Save system | Full persistence — stars, progress, unlocks between sessions |
| Encyclopedia | Yes — towers, enemies, heroes |
| Enemy health bars | Visible only when enemy takes damage |
| Tower range preview | Circle shown when tower is tapped |

---

## 📁 Folder Structure

```
res://
├── autoloads/
│   ├── EventBus.gd               # signals only, zero logic
│   ├── GameState.gd              # gold, lives, score, wave number
│   ├── WaveManager.gd            # wave data + multi-path spawning
│   ├── DamageCalculator.gd       # ALL damage math lives here only
│   ├── SaveManager.gd            # save/load all persistence
│   └── UnlockManager.gd          # IAP + unlock state
│
├── towers/
│   ├── base_tower.gd
│   ├── TowerArcher.tscn
│   ├── TowerMage.tscn
│   ├── TowerArtillery.tscn
│   ├── TowerBarracks.tscn
│   └── data/
│       ├── tower_archer.tres
│       ├── tower_mage.tres
│       ├── tower_artillery.tres
│       ├── tower_barracks.tres
│       └── upgrades/
│           ├── archer_upgrade_a.tres
│           ├── archer_upgrade_b.tres
│           ├── mage_upgrade_a.tres
│           └── mage_upgrade_b.tres
│
├── soldiers/
│   ├── base_soldier.gd
│   ├── Soldier.tscn
│   ├── Paladin.tscn
│   └── data/
│       ├── soldier_basic.tres
│       └── soldier_paladin.tres
│
├── enemies/
│   ├── base_enemy.gd
│   ├── EnemyBasic.tscn
│   ├── EnemyArmored.tscn
│   ├── EnemyFlying.tscn
│   ├── EnemyHealer.tscn
│   ├── EnemyFast.tscn
│   ├── bosses/
│   │   ├── base_boss.gd
│   │   └── Boss1.tscn
│   └── data/
│       ├── enemy_basic.tres
│       ├── enemy_armored.tres
│       ├── enemy_flying.tres
│       └── enemy_healer.tres
│
├── heroes/
│   ├── base_hero.gd
│   ├── HeroWarrior.tscn
│   ├── HeroMage.tscn
│   └── data/
│       ├── hero_warrior.tres
│       ├── hero_mage.tres
│       └── skills/
│           ├── skill_base.gd
│           ├── SkillSlash.tres
│           ├── SkillHeal.tres
│           └── SkillAoe.tres
│
├── spells/
│   ├── base_spell.gd
│   ├── SpellFireball.tscn
│   ├── SpellReinforcements.tscn
│   └── data/
│       ├── spell_fireball.tres
│       └── spell_reinforcements.tres
│
├── projectiles/
│   ├── Arrow.tscn
│   ├── Bullet.tscn
│   └── Fireball.tscn
│
├── systems/
│   ├── StatusEffect.gd           # base class
│   ├── SlowEffect.gd
│   ├── StunEffect.gd
│   ├── PoisonEffect.gd
│   └── ArmorBreakEffect.gd
│
├── map/
│   ├── Map.tscn                  # TileMap + multiple Path2Ds + fixed spots
│   │                             # + NavigationRegion2D + SpawnMarkers
│   ├── GridManager.gd            # tracks occupied/free tower spots
│   └── SpawnMarker.tscn          # edge-of-screen direction indicator UI
│
├── ui/
│   ├── HUD.tscn                  # gold, lives, wave info, spell buttons
│   ├── TowerShop.tscn            # bottom panel: select tower type
│   ├── TowerSpotMenu.tscn        # popup: build / upgrade / sell
│   ├── UpgradeMenu.tscn          # branching choice at level 3
│   ├── SkillBar.tscn             # hero skill buttons + cooldown overlay
│   ├── HeroHealthBar.tscn        # floating above hero
│   ├── SpellPanel.tscn           # global spell buttons + cooldown
│   ├── WaveDirectionUI.tscn      # spawn direction markers on screen edges
│   ├── WorldMap.tscn             # level select
│   ├── HeroRoom.tscn             # hero select + unlock screen
│   ├── UpgradeTree.tscn          # permanent upgrade tree
│   ├── Encyclopedia.tscn         # codex: towers, enemies, heroes
│   ├── EndlessLeaderboard.tscn   # online leaderboard for endless mode
│   └── GameOverScreen.tscn
│
├── progression/
│   ├── LevelData.tres            # per-level: paths, spots, waves, star thresholds
│   └── SkillTreeData.tres        # talent tree structure
│
└── main/
    └── Main.tscn
```

---

## 🔌 Autoloads

| Name | File | Purpose |
|---|---|---|
| EventBus | autoloads/EventBus.gd | Signals only |
| GameState | autoloads/GameState.gd | Gold, lives, score, wave |
| WaveManager | autoloads/WaveManager.gd | Multi-path spawn logic |
| DamageCalculator | autoloads/DamageCalculator.gd | All damage math |
| SaveManager | autoloads/SaveManager.gd | All persistence |
| UnlockManager | autoloads/UnlockManager.gd | IAP + unlock state |

---

## 📡 EventBus Signals — Complete List

```gdscript
# Enemy
signal enemy_spawned(enemy, path_id)
signal enemy_died(enemy, gold_value)
signal enemy_reached_end(enemy, lives_lost)

# Tower
signal tower_built(tower, spot_id)
signal tower_sold(tower, refund)
signal tower_upgraded(tower, new_level)
signal tower_branch_chosen(tower, branch)   # "A" or "B"
signal tower_spot_tapped(spot_id)
signal tower_range_preview_requested(tower) # show range circle

# Soldiers
signal soldier_spawned(soldier, tower)
signal soldier_died(soldier)
signal soldier_blocking(soldier, enemy)

# Wave
signal wave_started(wave_number, path_ids)  # which paths active this wave
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
signal challenge_mode_started(mode)         # "heroic" or "iron"

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
```

---

## ⚔️ Damage System

**Rule:** All damage through `DamageCalculator.calculate_damage(amount, type, target)` only.

```gdscript
enum DamageType { PHYSICAL, MAGIC, TRUE }

# PHYSICAL: final = amount * (1.0 - target.armor)
# MAGIC:    final = amount * (1.0 - target.magic_resist)
# TRUE:     final = amount  (ignores all resistances)
```

---

## 🗺️ Multiple Path System

Each level has multiple Path2D nodes. Enemies can spawn on different paths each wave.

```
Map.tscn
  Path2D_Left       ← path_id: "left"
    PathFollow2D    ← enemies spawned here
  Path2D_Right      ← path_id: "right"
    PathFollow2D
  Path2D_Top        ← path_id: "top"
    PathFollow2D
```

### Wave Direction Markers
- Each active path has a SpawnMarker at the screen edge showing direction + enemy icons
- Markers appear when wave countdown starts — before enemies spawn
- Markers update per wave as active paths change
- SpawnMarker position is defined per Path2D in LevelData.tres

### Wave Data with Multiple Paths
```gdscript
var waves: Array = [
  { "spawns": [
      { "path": "left",  "type": "basic",   "count": 8,  "interval": 1.0 },
      { "path": "right", "type": "fast",    "count": 4,  "interval": 1.5 },
  ]},
  { "spawns": [
      { "path": "left",  "type": "armored", "count": 5,  "interval": 2.0 },
      { "path": "top",   "type": "flying",  "count": 3,  "interval": 2.0 },
  ]},
]
```

### WaveManager Rules
- WaveManager reads path_id from wave data and spawns enemies on correct Path2D
- SpawnMarkers shown 3 seconds before wave starts
- `wave_started(wave_number, path_ids)` signal includes which paths are active
- WaveManager emits `spawn_direction_changed` whenever active paths change

---

## 🏰 Tower System

### Placement
- Fixed pre-defined spots only — Marker2D nodes in Map.tscn
- Tap empty spot → TowerSpotMenu → select tower type → tower built
- Tap occupied spot → TowerSpotMenu → upgrade / sell options
- Tap any tower → show range circle (circle node, visible = true, auto-hides after 2s)
- GridManager tracks occupied/free per spot_id

### Upgrade — Branching at Level 3
```
Level 1  →  Level 2  →  Level 3: PERMANENT BRANCH CHOICE
                           ├── Upgrade A (e.g. Ranger: DoT, vine slow)
                           └── Upgrade B (e.g. Musketeer: high damage, pierce)
```

### Tower Data
```gdscript
@export var tower_name: String
@export var tower_id: String
@export var requires_unlock: bool
@export var damage: float
@export var damage_type: DamageType
@export var attack_range: float
@export var attack_speed: float
@export var cost: int
@export var sell_value: int
@export var targets_flying: bool
@export var upgrade_cost_lvl2: int
@export var upgrade_cost_lvl3: int
@export var upgrade_a_scene: PackedScene
@export var upgrade_b_scene: PackedScene
@export var upgrade_a_data: Resource
@export var upgrade_b_data: Resource
@export var encyclopedia_entry: String    # shown in codex
```

---

## 🪖 Barracks / Soldier System

```
TowerBarracks → spawns → Soldier (CharacterBody2D)
  ├── walks to blocking_position near assigned path segment
  ├── engages first enemy in melee range
  ├── enemy enters COMBAT state — stops path progress
  ├── dies → respawn_timer → new soldier spawned
  └── collision layer 2 (cannot block flying layer 3)
```

- Max 3 soldiers per barracks
- blocking_position defined per tower spot in LevelData
- Soldiers cannot block flying enemies
- When soldier dies: enemy resumes WALKING state

### Soldier Data
```gdscript
@export var max_health: int
@export var attack_damage: float
@export var attack_speed: float
@export var armor: float
@export var respawn_time: float
@export var max_count: int = 3
@export var encyclopedia_entry: String
```

---

## 👾 Enemy System

### Enemy Data
```gdscript
@export var enemy_name: String
@export var max_health: int
@export var move_speed: float
@export var armor: float                 # 0.0–1.0 physical reduction
@export var magic_resist: float          # 0.0–1.0 magic reduction
@export var lives_worth: int
@export var gold_worth: int
@export var is_flying: bool              # layer 3, bypasses soldiers
@export var can_stealth: bool            # invisible at threshold HP
@export var stealth_threshold: float = 0.5
@export var regenerates: bool
@export var regen_rate: float
@export var heals_allies: bool
@export var heal_range: float
@export var heal_amount: float
@export var heal_interval: float = 3.0
@export var explodes_on_death: bool
@export var explosion_damage: float
@export var explosion_range: float
@export var spawns_on_death: bool
@export var spawn_scene: PackedScene
@export var spawn_count: int
@export var encyclopedia_entry: String
```

### Enemy States
```
WALKING   → progressing along assigned PathFollow2D
STUNNED   → speed = 0, counting stun Timer
COMBAT    → blocked by soldier, no path progress
STEALTHED → invisible to towers (AoE splash still hits)
DYING     → death animation, then queue_free()
```

### Enemy Health Bar Rules
- Health bar hidden by default
- Becomes visible when enemy takes any damage
- Auto-hides after 3 seconds of no damage via Timer
- Boss health bar always visible

---

## 🦸 Hero System

### Hero Data
```gdscript
@export var hero_name: String
@export var hero_id: String
@export var requires_unlock: bool
@export var max_health: int
@export var attack_damage: float
@export var attack_range: float
@export var attack_speed: float
@export var move_speed: float
@export var armor: float
@export var xp_per_level: Array[int]
@export var max_level: int = 10
@export var respawn_time: float = 30.0
@export var skills: Array[Resource]
@export var encyclopedia_entry: String
```

### Hero States
```
IDLE        → auto-attacking nearest enemy via Area2D
MOVING      → NavigationAgent2D to tapped location
COMBAT      → melee range, attacking
CASTING     → skill animation (brief movement lock)
DEAD        → death anim + respawn countdown in HUD
RESPAWNING  → reappearing at spawn position
```

- One hero on map at a time
- Selected in HeroRoom before level — cannot change mid-level
- Navigation target updates max every 0.2s via Timer
- Immune to instakill from normal enemies (not bosses)
- Always hits flying enemies regardless of layer
- Respawn timer starts immediately on death
- Gains XP from kills — towers do not

### Skill Data
```gdscript
@export var skill_name: String
@export var damage: float
@export var range: float
@export var cooldown: float
@export var target_type: TargetType     # SINGLE / AREA / SELF
@export var damage_type: DamageType
@export var icon: Texture2D
@export var vfx_scene: PackedScene
```

- Each skill is a separate script — never inside hero script
- Cooldown: radial fill overlay — never text
- Range: visible circle when skill selected

---

## 🌩️ Global Spell System

```gdscript
@export var spell_name: String
@export var cooldown: float
@export var damage: float
@export var damage_type: DamageType
@export var radius: float
@export var duration: float
@export var icon: Texture2D
@export var vfx_scene: PackedScene
```

- Tap spell button → targeting mode → tap map → spell fires
- Cooldown: radial fill overlay on SpellPanel button
- Spell logic in individual spell scripts only
- Upgradeable via permanent upgrade tree

---

## 🎮 Game Modes

### Campaign Mode
- Fixed levels on WorldMap
- 1–3 stars per level based on lives remaining
- Stars persist in SaveManager
- Each completed level unlocks next

### Heroic Mode (per level)
- Unlocked after 3-star campaign completion of that level
- Harder wave composition, same map
- Rewards 1 bonus star on completion

### Iron Mode (per level)
- Unlocked after Heroic completion
- 1 life only — instant game over on any enemy reaching end
- Rewards 1 bonus star on completion

### Endless Mode
- Separate entry from WorldMap
- Waves never stop — difficulty scales each wave
- Score = wave number × gold × lives multiplier
- Score submitted to online leaderboard on death
- No stars — leaderboard only

### Challenge Mode Rules in WaveManager
- WaveManager reads `current_mode` from GameState
- `current_mode` options: "campaign", "heroic", "iron", "endless"
- Heroic/Iron wave data defined separately in LevelData.tres
- Endless wave data generated procedurally by WaveManager

---

## 📖 Encyclopedia / Codex

- Accessible from HUD during gameplay and from main menu
- Three tabs: Towers | Enemies | Heroes
- Entry unlocked when player first encounters that entity
- Content pulled from `encyclopedia_entry` field in each .tres Resource
- New entries flash/notify in HUD icon when unlocked

### Encyclopedia Data per Entry
```gdscript
# In each .tres Resource file:
@export var encyclopedia_entry: String  # description, stats summary, tips
```

---

## 🏆 Online Leaderboard

- Endless mode only
- Score submitted automatically on game over
- Display: top 100 global + player's personal best + nearby ranks
- Implemented via Godot's built-in HTTPRequest node
- Backend: use a simple leaderboard service (e.g. LootLocker or GameJolt API)
- Phase 33 only — do not add leaderboard code before then

---

## 💾 Save System

SaveManager is the only script that reads/writes the save file.

```gdscript
{
  "total_stars": int,
  "levels": {
    "level_1": {
      "campaign_stars": int,      # 0-3
      "heroic_complete": bool,
      "iron_complete": bool
    },
  },
  "endless_best_score": int,
  "unlocked_heroes": Array[String],
  "unlocked_towers": Array[String],
  "permanent_upgrades": Array[String],
  "skill_points_spent": Dictionary,
  "encyclopedia_unlocked": Array[String],
  "iap_purchases": Array[String]
}
```

- Save on: level complete, IAP purchase, upgrade purchase, encyclopedia unlock
- Never auto-save mid-wave
- All other systems call SaveManager — never write saves directly

---

## 🔓 Unlock & IAP System

- Check `UnlockManager.is_unlocked(id)` before loading any hero or tower
- UnlockManager reads from SaveManager only
- IAP → `UnlockManager.unlock(id)` → `SaveManager.save()`
- Always show locked UI — never pretend locked content is available
- IAP integration is Phase 30 — no IAP code before then

---

## ⭐ Progression System

### Stars
- Campaign: 1–3 stars (18–20 lives = 3, 6–17 = 2, 1–5 = 1)
- Heroic complete: +1 bonus star
- Iron complete: +1 bonus star
- Max 5 stars per level
- Stars = permanent currency for upgrade tree

### Permanent Upgrade Tree
- Accessed from WorldMap
- Applies globally to all levels
- Examples: +10% archer damage, +1 spell charge, hero respawn –5s
- Each upgrade: star cost + prerequisite upgrade_id
- Stored in SaveManager

### Skill Tree / Talent Points
- Separate from permanent upgrades
- Points earned by leveling hero
- Applied per-hero, not globally
- Stored in SaveManager per hero_id

---

## 🗺️ Movement Architecture

### Enemies
```
Map.tscn
  Path2D_Left / Path2D_Right / Path2D_Top   ← multiple paths
    PathFollow2D                              ← enemies attach here
```
- Speed via progress_ratio increment
- Slow effects multiply speed by slow_factor
- No NavigationAgent2D for enemies

### Hero
```
Map.tscn
  NavigationRegion2D          ← full walkable area
  Hero (CharacterBody2D)
    NavigationAgent2D
    Area2D                    ← detects enemies in range
```
- Navigation updates max every 0.2s via Timer
- Towers do NOT affect NavigationRegion2D

### Soldiers
- Walk to pre-defined blocking_position near assigned path segment
- blocking_position defined in LevelData per tower spot

---

## 📱 Platform & Input

```
Project Settings:
  Stretch Mode:             canvas_items
  Stretch Aspect:           expand
  Emulate Touch From Mouse: ON
```

- All input via InputEventScreenTouch / InputEventScreenDrag only
- No InputEventMouseButton handlers ever
- No right-click mechanics ever
- All actions achievable with single tap
- Minimum touch target: 80×80 pixels
- Default test viewport: 375×812 (iPhone size)
- Design for phone first — scale up for PC

---

## ⚡ Performance Rules — Mobile Critical

- Hero navigation: max every 0.2s via Timer — never every frame
- Enemy healing: Timer-based only — never _physics_process
- Range detection: Area2D overlap only — never distance loops
- Particles: pool and reuse — never instantiate mid-wave
- Never call get_tree().get_nodes_in_group() in _physics_process
- Test with 30+ enemies across multiple paths before declaring phase complete
- UI animations: Tween only
- Health bars: use a pool of HealthBar nodes — never instantiate per enemy

---

## 🔢 Build Phases — NEVER SKIP OR COMBINE

```
Phase 1:  Project skeleton — autoloads, signals, folders
Phase 2:  Map + multiple Path2Ds + fixed tower spots
Phase 3:  SpawnMarkers on screen edges (direction indicators)
Phase 4:  One enemy walking one path and dying
Phase 5:  Damage type system + DamageCalculator
Phase 6:  One tower detecting, shooting, killing
Phase 7:  Gold + lives economy
Phase 8:  Tower placement — tap spot → select → build
Phase 9:  Tower sell + refund
Phase 10: Tower range circle preview on tap
Phase 11: Wave system — WaveManager + multi-path wave data
Phase 12: Win/lose conditions + GameOverScreen
Phase 13: Status effects — slow, then stun
Phase 14: Flying enemy — collision layer 3
Phase 15: Healer enemy — Timer-based ally healing
Phase 16: Barracks tower + soldier blocking
Phase 17: Enemy health bar — visible on hit, auto-hide
Phase 18: Hero movement + auto-attack
Phase 19: Hero XP + leveling
Phase 20: Hero skill 1 (single target)
Phase 21: Hero skills 2 + 3
Phase 22: Global spell 1 (area damage)
Phase 23: Global spell 2 (reinforcements)
Phase 24: Tower upgrade linear (levels 1→2→3)
Phase 25: Branching upgrade choice at level 3
Phase 26: Star rating system (campaign)
Phase 27: SaveManager — persist all progress
Phase 28: Permanent upgrade tree
Phase 29: WorldMap level select
Phase 30: HeroRoom — hero selection before level
Phase 31: Heroic + Iron challenge modes
Phase 32: Endless mode + score system
Phase 33: Online leaderboard
Phase 34: Encyclopedia / codex
Phase 35: Second hero type
Phase 36: UnlockManager — locked content states
Phase 37: IAP integration
Phase 38: Boss system — phases + special attacks
Phase 39: Second + third tower types
Phase 40: Skill tree / talent points per hero
Phase 41: Polish — sound, particles, animations, menus
```

**Git commit after every phase before starting the next.**

---

## 🛑 "Everything Broke" Protocol

1. Stop. Do not patch forward.
2. Open GitHub Desktop. Find last working commit.
3. Ask Claude: *"Here is the last working version of [script]. Here is the current broken version. What specifically changed and why?"*
4. If Claude cannot fix cleanly in one response → discard, restore last commit.
5. Never patch broken code with more code.
6. Never let Claude refactor something that was not broken.

---

## 🔄 Session Start Template

```
Current Phase: [X — name]
Last working commit: [what works]
This session task: [ONE feature only]
Relevant files: [list only needed files]

Rules:
- Godot 4.3, GDScript
- Never modify working scripts
- All communication via EventBus
- Stats in .tres files only
- Damage through DamageCalculator only
- State changes through change_state() only
- Unlock checks through UnlockManager only
- Save/load through SaveManager only
```

---

## 🎨 Asset Strategy

Use ColorRect placeholders for all visuals until Phase 41.
Do not mix art and mechanics.

- Free art: kenney.nl
- Free SFX: freesound.org
- SFX editing: Audacity

File naming: `entity_animation_00.png`
Examples: `enemy_orc_walk_00.png`, `tower_archer_idle_00.png`, `hero_knight_attack_00.png`

---

## 📋 Current Status

> Update after every session.

```
Working:
[ ] Skeleton          [ ] Map+paths+spots    [ ] SpawnMarkers
[ ] Enemy walking     [ ] Damage system      [ ] Basic tower
[ ] Economy           [ ] Placement          [ ] Sell
[ ] Range preview     [ ] Wave system        [ ] Win/lose
[ ] Status effects    [ ] Flying enemy       [ ] Healer enemy
[ ] Barracks          [ ] Enemy health bar   [ ] Hero movement
[ ] Hero XP           [ ] Skill 1            [ ] Skills 2+3
[ ] Spell 1           [ ] Spell 2            [ ] Tower upgrades
[ ] Branch choice     [ ] Stars              [ ] SaveManager
[ ] Upgrade tree      [ ] WorldMap           [ ] HeroRoom
[ ] Heroic+Iron       [ ] Endless mode       [ ] Leaderboard
[ ] Encyclopedia      [ ] Hero 2             [ ] UnlockManager
[ ] IAP               [ ] Boss system        [ ] Tower types 2+3
[ ] Skill tree        [ ] Polish

Known bugs: none yet
Last committed phase: none
Next task: Phase 1 — project skeleton
```
