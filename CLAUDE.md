# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fantasy Tower Defense (Kingdom Rush Style)
> Godot 4.6.2 | GDScript | Android + iOS + PC | Touch + Mouse

---

## 🛠️ Development Commands

```bash
# Run the project (from Godot editor or CLI)
# Godot must be installed and in PATH as `godot` or full path used
godot --path . --editor          # Open in editor
godot --path .                   # Run the game directly

# The project entry point is res://ui/MainMenu.tscn (see project.godot)
# Default viewport: 375×812 (portrait, iPhone-sized)
# Rendering: GL Compatibility (mobile-first)
```

There is no build system, linter, or test suite — this is a pure GDScript/Godot project. All validation is done by running the game in the Godot editor.

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
11. **New content is authored as data, not code.** Every new hero / soldier / enemy / skill / spell / ability / item is a `.tres` resource composed from existing base classes + AbilityData components. Only subclass a base script when the variant needs genuinely new *structural* behavior (collision layer, multi-phase state machine, projectile vs. melee). Visual + stat + passive differences are never a reason to write a new script.
12. **One primitive for mechanics: AbilityData.** Every "verb on a unit" — passives, on-hit effects, auras, items, talents, endless modifiers, status effects — is an `AbilityData` Resource with a `Trigger` and an `apply(owner, ctx)` override. Units hold `abilities: Array[Resource]`; the `AbilityHost` dispatcher is owner-agnostic. If a new mechanic makes you reach for `if owner is BaseX` inside an ability, split the ability.
13. **Stable content IDs.** Every authored Resource has a `*_id: String` field (`hero_id`, `tower_id`, `enemy_id`, `soldier_id`, `spell_id`, `skill_id`, `ability_id`). IDs are the key used in save files, unlock checks, leaderboard payloads, and loot tables. **Never rename an ID after the first release** — doing so breaks save compatibility. Convention: `snake_case`, scoped by type (e.g. `hero_warrior`, `tower_archer`, `enemy_basic`, `spell_fireball`).

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
| Enemy health bars | Visible whenever HP is not full (stays after any damage) |
| Tower range preview | Circle shown when tower is tapped |

---

## 📁 Folder Structure

```
res://
├── autoloads/
│   ├── EventBus.gd               # signals only, zero logic
│   ├── GameState.gd              # gold, lives, score, wave, progression
│   ├── WaveManager.gd            # wave data + multi-path spawning + endless gen
│   ├── DamageCalculator.gd       # ALL damage math lives here only
│   ├── SaveManager.gd            # save/load all persistence (JSON)
│   ├── UnlockManager.gd          # IAP + unlock state (stub)
│   ├── SceneManager.gd           # scene transitions with fade
│   ├── ContentRegistry.gd        # master index of all content .tres
│   ├── PurchaseManager.gd       # IAP client stub
│   ├── VFXSpawner.gd            # FloatingText + DeathVFX spawner
│   └── SoundManager.gd          # SFX pool + music player
│
├── towers/
│   ├── base_tower.gd             # attack towers (archer, mage, artillery)
│   ├── TowerBarracks.gd          # soldier-spawning tower (separate control loop)
│   ├── TowerData.gd              # Resource: tower stats
│   ├── TowerUpgradeData.gd       # Resource: per-level upgrade stats + on-hit
│   ├── TowerArcher.tscn
│   ├── TowerBarracks.tscn
│   └── data/
│       ├── tower_archer.tres      # L1 stats + L2/L3 upgrades + Ranger/Musketeer branches
│       └── tower_barracks.tres
│
├── soldiers/
│   ├── base_soldier.gd
│   ├── SoldierData.gd            # Resource: soldier stats + abilities
│   ├── Soldier.tscn
│   └── data/
│       └── soldier_basic.tres
│
├── enemies/
│   ├── base_enemy.gd             # ground enemy with AbilityHost
│   ├── enemy_flying.gd           # subclass: collision layer 3 + visual (Rule 11 exception)
│   ├── enemy_healer.gd           # subclass: visual only (Rule 11 exception, Phase 41 removes)
│   ├── EnemyData.gd              # Resource: enemy stats + abilities
│   ├── EnemyBasic.tscn
│   ├── EnemyFlying.tscn
│   ├── EnemyHealer.tscn
│   └── data/
│       ├── enemy_basic.tres
│       ├── enemy_flying.tres
│       └── enemy_healer.tres      # HealAuraAbility as inline sub_resource
│
├── heroes/
│   ├── base_hero.gd              # movement, combat, XP, skills, selection
│   ├── HeroData.gd               # Resource: hero stats + skills + abilities
│   ├── HeroInputManager.gd       # tap-to-move routing
│   ├── HeroWarrior.tscn
│   ├── skills/                   # skill scripts (SkillData subclasses)
│   │   ├── skill_data.gd         # base Resource with TargetType enum
│   │   ├── slash_skill_data.gd
│   │   ├── shield_bash_skill_data.gd
│   │   └── rally_skill_data.gd
│   └── data/
│       ├── hero_warrior.tres
│       └── skills/               # skill .tres instances
│           ├── skill_slash.tres
│           ├── skill_shield_bash.tres
│           └── skill_rally.tres
│
├── spells/
│   ├── SpellData.gd              # base Resource with TargetType enum
│   ├── fireball_spell_data.gd
│   ├── reinforcements_spell_data.gd
│   ├── FireballVFX.gd + .tscn    # expanding-circle placeholder effect
│   └── data/
│       ├── spell_fireball.tres
│       └── spell_reinforcements.tres
│
├── projectiles/
│   └── Arrow.gd + Arrow.tscn     # homing projectile (future: Bullet, Fireball)
│
├── systems/
│   ├── AbilityData.gd            # base Resource: trigger enum + apply() virtual
│   ├── AbilityHost.gd            # per-unit dispatcher (RefCounted)
│   ├── UnitVisualData.gd         # Resource: shape, colors, accent for _draw()
│   ├── UnitVisualDrawer.gd       # static draw_unit() helper (not autoload)
│   ├── StatusEffect.gd           # base class (per-target mutable state)
│   ├── SlowEffect.gd
│   ├── StunEffect.gd
│   └── abilities/                # concrete AbilityData subclasses
│       ├── HealAuraAbility.gd
│       ├── OnHitBonusDamageAbility.gd
│       └── LifetimeAbility.gd
│
├── levels/
│   ├── Level1.gd + Level1.tscn   # @tool — editor-editable map + paths + spots
│   └── level1_waves.tres          # WaveList for campaign waves
│
├── waves/
│   ├── WaveData.gd               # Resource: one wave (spawns + countdown + bounty)
│   ├── WaveList.gd               # Resource: ordered array of WaveData
│   └── WaveSpawn.gd              # Resource: one spawn group (path + enemy + count)
│
├── map/
│   ├── GridManager.gd            # tracks occupied/free tower spots
│   ├── SpotInputManager.gd       # screen-tap → tower_spot_tapped routing
│   ├── SpawnMarker.gd + .tscn    # edge-of-screen direction indicators
│
├── progression/
│   └── UpgradeData.gd            # Resource: permanent upgrade node (star cost + effect)
│
├── ui/
│   ├── MainMenu.gd + .tscn       # entry point: title + Play + Reset
│   ├── WorldMap.gd + .tscn       # hub: level select + Upgrades/Endless/Scores/Codex
│   ├── LoadoutScreen.gd + .tscn  # pre-level: mode selector + hero/tower/spell preview
│   ├── HUD.gd + .tscn            # in-game: gold, lives, wave, hero XP, pause, speed
│   ├── TowerSpotMenu.gd + .tscn  # popup: build / upgrade / branch / sell / move rally
│   ├── TowerPlacer.gd            # build/sell/upgrade transaction handler
│   ├── SkillBar.gd + .tscn       # hero skill buttons with CooldownButton
│   ├── SpellPanel.gd + .tscn     # global spell buttons with CooldownButton
│   ├── CooldownButton.gd + .tscn # reusable radial-fill button (provider-agnostic)
│   ├── RangePreview.gd + .tscn   # tower range circle on tap
│   ├── PauseMenu.gd + .tscn      # in-game: resume / restart / quit to map
│   ├── GameOverScreen.gd + .tscn # victory (continue) / defeat (restart)
│   ├── UpgradeTree.gd + .tscn    # permanent upgrades (spend stars)
│   ├── EncyclopediaScreen.gd + .tscn # codex: auto-stat tabs (enemies/towers/heroes)
│   ├── LeaderboardScreen.gd + .tscn  # endless top scores
│   ├── world_map/
│   │   ├── LevelNodeData.gd      # Resource: one level entry
│   │   └── level_list.tres        # (optional, WorldMap uses inline sub_resources)
│   └── theme/
│       ├── ThemeColors.gd        # canonical color palette constants
│       └── game_theme.tres       # global Theme resource (buttons, panels, labels)
│
├── vfx/
│   ├── FloatingText.gd + .tscn   # Tween-based floating damage/gold/XP text
│   └── DeathVFX.gd + .tscn       # expanding ring + flash on enemy death
│
├── audio/
│   └── sfx/                      # drop .wav files here; SoundManager auto-detects
│
└── main/
    ├── Main.gd                   # gameplay orchestrator (wave start, signal logging)
    └── Main.tscn                 # instances Level1 + Towers + Hero + all UI
```

---

## 🔌 Autoloads

| Name | File | Purpose |
|---|---|---|
| EventBus | autoloads/EventBus.gd | Signals only |
| GameState | autoloads/GameState.gd | Gold, lives, score, wave, progression |
| WaveManager | autoloads/WaveManager.gd | Multi-path spawn + endless generation |
| DamageCalculator | autoloads/DamageCalculator.gd | All damage math |
| SaveManager | autoloads/SaveManager.gd | All persistence (JSON) |
| UnlockManager | autoloads/UnlockManager.gd | IAP + unlock state (stub) |
| SceneManager | autoloads/SceneManager.gd | Scene transitions with fade |
| ContentRegistry | autoloads/ContentRegistry.gd | Master index of all content .tres |
| PurchaseManager | autoloads/PurchaseManager.gd | IAP client stub (auto-succeeds) |
| VFXSpawner | autoloads/VFXSpawner.gd | FloatingText + DeathVFX on EventBus signals |
| SoundManager | autoloads/SoundManager.gd | SFX pool + music player (graceful missing files) |

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
signal tower_build_requested(spot_id, tower_id)
signal tower_sell_requested(spot_id)
signal tower_upgrade_requested(spot_id)
signal tower_branch_upgrade_requested(spot_id, branch_idx)
signal tower_menu_dismissed()

# Soldiers
signal soldier_spawned(soldier, tower)
signal soldier_died(soldier)
signal soldier_blocking(soldier, enemy)
signal barracks_rally_move_requested(barracks)

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

### Tower Upgrade System (Phase 24–25)
```gdscript
# TowerUpgradeData.gd — per-level stat override + on-hit effects
@export var upgrade_name: String
@export var damage: float
@export var attack_range: float
@export var attack_speed: float
@export var cost: int
@export var sell_value: int
@export var on_hit_slow_factor: float = 0.0
@export var on_hit_slow_duration: float = 0.0
@export var on_hit_stun_duration: float = 0.0
@export var tint: Color = Color.WHITE

# On TowerData:
@export var level_upgrades: Array[Resource]     # [L2_data, L3_linear]
@export var level_3_branches: Array[Resource]   # [Ranger, Musketeer] — overrides level_upgrades[1]
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

## 🧱 Modular content pattern (the rule for every new unit / skill / spell / item)

**Default rule:** every piece of new content is a `.tres` file plus (optionally) a `[sub_resource]` of AbilityData. Authoring flow for any variant:

```
new_orc_warlord.tres        (EnemyData: copy-paste of enemy_basic, bump HP)
  + sub_resource EnrageBelowHPAbility (trigger=ON_HIT_TAKEN, threshold=0.3, dmg_mult=1.5)
  + sub_resource DamageAuraAbility     (trigger=ON_INTERVAL, range=80, interval=0.5)
```

No new `.gd` required. Reference the data in a wave spawn; done.

### When subclass IS warranted
Only three categories justify a new script under `base_*.gd`:

| Category | Examples |
|---|---|
| Collision / scene-graph structure | `EnemyFlying` (collision layer 3), future `EnemyBoss` multi-phase rig |
| Fundamentally different control loop | `TowerBarracks` (spawns soldiers, no projectile), future `TowerWallBuilder` |
| Player-facing novel behavior | New hero that summons pets (extra child node management) |

If the variant is "same loop, different numbers + passives + visuals" → it's data. No subclass.

### Per-subsystem authoring contracts

| Subsystem | Base script (one) | Data Resource | Composition via |
|---|---|---|---|
| Enemies | `base_enemy.gd` | `EnemyData` | `abilities: Array[Resource]` |
| Soldiers | `base_soldier.gd` | `SoldierData` | `abilities: Array[Resource]` |
| Heroes | `base_hero.gd` | `HeroData` | `skills: Array[Resource]` (active) + `abilities: Array[Resource]` (passive) |
| Towers | `base_tower.gd` (attack) / `TowerBarracks` (spawner) | `TowerData` | Phase 24 adds `AttackPatternData` + on-hit `Array[AbilityData]` |
| Skills | `SkillData` subclass with `apply(hero, target)` | `SkillData` (+ subclass) | N/A — skill IS the mechanic |
| Spells | `SpellData` subclass with `apply(world_pos)` (Phase 22–23) | `SpellData` | Same pattern as SkillData |
| Items (future) | No script per item. `ItemData` Resource. | `ItemData` | `stat_modifiers` + `abilities: Array[Resource]`; equipping pushes both |
| Status effects | `StatusEffect` base + subclass | `StatusEffect` subclass | Runtime, not Resource — per-target mutable state |

### Adding a new hero (recipe, after Phase 35 template lands)
1. Copy `hero_warrior.tres` → `hero_ranger.tres`, edit stats.
2. Create 3 skill `.tres` files under `heroes/data/skills/`.
3. Create `HeroVisual_ranger.tres` (Phase 41 polish — till then override `_draw()` via subclass, documented exception).
4. Assign everything in a `HeroTemplate.tscn` instance.
5. Ship. No GDScript written.

### Adding a new soldier
1. Copy `soldier_basic.tres` → `soldier_paladin.tres`.
2. Attach an existing `HealAuraAbility` sub-resource in `abilities`.
3. Create a barracks variant `.tres` that references the new soldier data.

### Adding a new enemy
1. `enemy_warlord.tres` with stats + `abilities: [EnrageBelowHP, DamageAura]`.
2. Reference in a wave. Done.

### Adding a new ability (when mechanics genuinely new)
1. `systems/abilities/MyAbility.gd` — `extends "res://systems/AbilityData.gd"`, override `apply(owner, ctx)`.
2. Add `@export` fields for params.
3. Reference as sub-resource in any unit's `.tres`.

---

## 🧩 Ability System (composition layer)

**Rule:** Every "mechanic on top of base stats" — enemy traits, hero passives, tower on-hit effects, item-granted effects, talent-tree nodes, endless-mode modifiers — is an `AbilityData` Resource. One unifying primitive.

```gdscript
# systems/AbilityData.gd (Resource)
enum Trigger {
    ON_SPAWN,      # once, when attached
    ON_INTERVAL,   # every `interval` seconds
    ON_HIT_DEALT,  # owner damaged someone (ctx: target, amount)
    ON_HIT_TAKEN,  # owner took damage (ctx: source, amount)
    ON_KILL,       # owner killed someone (ctx: victim)
    ON_DEATH,      # owner died
    WHILE_ALIVE,   # passive (stat-stack use, no per-event dispatch)
    ON_EQUIP,      # item was equipped
    ON_UNEQUIP,
}

@export var ability_id: String
@export var trigger: int
@export var interval: float   # ON_INTERVAL only

func apply(owner, ctx) -> void:  # override in subclasses
    pass
```

`AbilityHost` (systems/AbilityHost.gd) is a RefCounted helper each unit holds. Populate from `data.abilities` in `_ready()`, call `tick(delta)` each `_physics_process`, call `trigger_event(event, ctx)` at lifecycle points. Same host reused by enemies, heroes, soldiers, towers.

### Authoring a new ability
1. Create `systems/abilities/MyAbility.gd` — `extends "res://systems/AbilityData.gd"` + override `apply(owner, ctx)`.
2. Add any per-ability fields (`@export`) — e.g. `heal_range`, `damage_mult`.
3. Reference it as a `[sub_resource]` inside the enemy/hero/item `.tres`, or save standalone and `ExtResource` it.

### Abilities implemented so far
- `HealAuraAbility` — ON_INTERVAL, heals other enemies in `heal_range`. Ports the Phase 15 shaman.
- `OnHitBonusDamageAbility` — ON_HIT_DEALT + duration, flat bonus damage per swing. Used by Rally skill as a temp buff.
- `LifetimeAbility` — ON_SPAWN + duration, calls `_die()` on owner when expired. Used by Reinforcements spell for timed soldiers.

### Abilities reserved for future phases
- `RegenAbility`, `ExplodeOnDeathAbility`, `SummonOnDeathAbility`, `EnrageBelowHPAbility`, `StealthBelowHPAbility` (enemies)
- `OnHitSlowAbility`, `OnHitBurnAbility`, `ChainLightningAbility`, `SplashDamageAbility` (tower projectiles, Phase 24+)
- `PassiveDamageBoost`, `LifestealAbility`, `BlockChanceAbility` (hero items, future)

### Discipline
- Abilities are **owner-agnostic**. No `if owner is BaseHero` inside an ability — if you need it, split the ability.
- Ability dispatch order within one trigger is array order. Document priority in a comment if it matters.
- `AbilityData` Resources are **shared** across instances. Cooldown / timing state lives on the host (or the unit), never on the data.

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
@export var xp_worth: int                # Phase 19 — hero last-hit XP
@export var attack_damage: float         # used when blocked in COMBAT
@export var attack_speed: float
@export var is_flying: bool              # layer 3, bypasses soldiers
@export var can_stealth: bool
@export var stealth_threshold: float = 0.5
# Phase 20.5: per-enemy mechanics (heal-aura, regen, explode-on-death,
# enrage, summon, stealth, etc.) are composed from AbilityData Resources.
# Drop a HealAuraAbility in here to make an enemy a healer; stack multiple
# to build hybrids. See "Ability System" below.
@export var abilities: Array[Resource] = []
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

### Health Bar Rules (enemies + soldiers)
- Health bar hidden only while HP is at max (full)
- Becomes visible the moment HP drops below max — stays visible for the rest of the unit's life
- Returning to full HP (heal) hides the bar again
- Boss health bar always visible, regardless of HP
- Applies to any unit with `current_health` / `max_health` (BaseEnemy, BaseSoldier). Extend the same rule to Hero when Phase 18 adds one.

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
@export var spell_id: String
@export var cast_range: float          # 0 = unlimited (anywhere on map)
@export var radius: float              # AoE radius at tap point
@export var damage: float
@export var damage_type: DamageType
@export var cooldown: float
@export var target_type: TargetType    # AREA / GLOBAL
@export var icon: Texture2D
@export var vfx_scene: PackedScene
```

- Tap spell button → targeting mode → tap map → spell fires
- Cooldown: radial fill overlay on SpellPanel button (same `CooldownButton` as skills)
- Spell logic in individual spell scripts (`SpellData` subclass with `apply(world_pos, caster)`)
- Upgradeable via permanent upgrade tree
- **Source = SpellPanel (not hero)** — spell kills don't grant hero XP, matching Kingdom Rush rules
- SpellPanel holds `@export spells: Array[Resource]` — Phase 30 LoadoutScreen will populate dynamically

### Spells implemented
| Spell | Type | Effect |
|---|---|---|
| Fireball | AoE | 55 magic dmg in 90 px radius, 25 s cooldown |
| Recruit (Reinforcements) | Summon | 4 militia with 20 s LifetimeAbility, 40 s cooldown |

---

## 🗡️ Skill System

```gdscript
# SkillData.gd (Resource, subclassed per skill)
enum TargetType { SINGLE, AREA, SELF }

@export var skill_name: String
@export var skill_id: String
@export var damage: float
@export var range: float               # 0 = use hero's attack_range
@export var cooldown: float
@export var target_type: TargetType
@export var damage_type: DamageType
@export var icon: Texture2D
@export var vfx_scene: PackedScene
```

- Each skill is a separate script — never inside hero script
- Cooldown: radial fill overlay — never text
- Range: visible circle when skill selected (drawn by hero's `_draw()`)
- **Skill-as-ability-factory pattern:** skills that grant buffs (Rally) construct a temporary `AbilityData` instance with a `duration` and push it into the hero's `_ability_host`. AbilityHost auto-removes on expiry. Zero bookkeeping code in the skill.

### Skills implemented (Knight)
| Skill | Target | Effect |
|---|---|---|
| Slash | SINGLE | 40 physical dmg, 6 s cooldown |
| Bash | AREA | 22 physical dmg in 70 px radius around tap, 10 s cooldown |
| Rally | SELF | Pushes OnHitBonusDamageAbility (+8 dmg, 10 s) onto hero, 18 s cooldown |

### SkillBar UI flow
- SINGLE: button → targeting mode → tap enemy in range → cast
- AREA: button → targeting mode → tap point in range → cast
- SELF: button → cast immediately (no targeting step)

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

## 🎯 Input Pipeline — Consumption Chain

Touch events flow through Godot in this order. Each layer either **consumes** (calls `set_input_as_handled()`) or lets the event pass to the next. Getting this wrong causes double-fires or stolen taps.

```
1. _input (all nodes, tree order top-down)
   ├── TowerBarracks._input   — consumes if rally-placement mode active
   ├── TowerSpotMenu._input   — swallows the release after menu just opened
   ├── SkillBar._input        — consumes if skill targeting armed
   └── SpellPanel._input      — consumes if spell targeting armed
       (both SkillBar + SpellPanel early-return if is_input_handled())

2. GUI phase (Control._gui_input)
   ├── TowerSpotMenu Backdrop (mouse_filter=STOP) — consumes when menu visible
   └── CooldownButton._gui_input — fires triggered(idx), accept_event()

3. Area2D picking → input_event signals
   └── TowerBarracks FlagArea — consumes on flag drag start

4. _unhandled_input (all nodes, tree order — only if not consumed above)
   ├── SpotInputManager        — emits tower_spot_tapped + CONSUMES
   ├── BaseHero._unhandled_input — toggles selection + consumes
   └── HeroInputManager        — calls hero.move_to + consumes (if hero is selected)
```

**Rules for adding new input handlers:**
- Declare which phase (1–4) it runs in.
- Always `set_input_as_handled()` when claiming an event.
- Always `if get_viewport().is_input_handled(): return` in `_input` if another handler at the same phase might compete.
- Test: "what if two modals are open simultaneously?"

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
Phase 17: Enemy health bar — visible while HP < max
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
[x] Skeleton          [x] Map+paths+spots    [x] SpawnMarkers
[x] Enemy walking     [x] Damage system      [x] Basic tower
[x] Economy           [x] Placement          [x] Sell
[x] Range preview     [x] Wave system        [x] Win/lose
[x] Status effects    [x] Flying enemy       [x] Healer enemy
[x] Barracks          [x] Enemy health bar   [x] Hero movement
[x] Hero XP           [x] Skill 1            [x] Skills 2+3
[x] Spell 1           [x] Spell 2            [x] Tower upgrades
[x] Branch choice     [x] Stars              [x] SaveManager
[x] Upgrade tree      [x] WorldMap           [x] HeroRoom
[x] Heroic+Iron       [x] Endless mode       [x] Leaderboard
[x] Encyclopedia      [x] Hero 2             [x] UnlockManager
[x] IAP               [x] Boss system        [x] Tower types 2+3
[x] Skill tree        [x] Polish

Extras beyond the phase list:
- Editor-editable Level1 (detour, before Phase 11)
- Draggable rally flag on barracks (Phase 16 follow-up)
- Tap-to-place rally via TowerSpotMenu "Move Rally" + range circle (Phase 17 follow-up 2)
- Soldier health bar (mirrors enemy bar; same damage/auto-hide rules)
- MainMenu + WorldMap + PauseMenu screen flow (pre-Phase 27 foundation)
- SceneManager autoload for all scene transitions
- Fast-forward (1x/2x/3x) + Reset Progress button

Known bugs: none
Last committed phase: Phase 16 (commit fde7ee0). Phases 17–41 and follow-ups uncommitted on disk.
Next task: All 41 phases complete. Game ready for content expansion and playtesting.
```
