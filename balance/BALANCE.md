# BALANCE.md

Design intent for tuning the game. Single source of truth for **what numbers should be** vs the `.tres` files which are **what numbers are**.

This file lives under `balance/` because the whole folder is dev-only. The export preset (`export_presets.cfg`) excludes `balance/*` so this doc, the BalanceCalculator, and the Test Range scene never end up in shipped APKs.

---

## Folder layout

```
balance/
├── BALANCE.md                    ← this file
├── BalanceCalculator.gd          ← hardness scoring (called from @tool Level1)
├── test_range/                   ← in-editor sandbox
│   ├── TestRange.tscn / .gd
│   └── TestRangeMap.tscn / .gd
└── snapshots/                    ← optional: hand-saved telemetry milestones
```

**To remove all balance infrastructure:** delete this folder. Everything inside is gated by `OS.is_debug_build()` or stripped at export — no production code path depends on anything here.

---

## Industry conventions used

The two metrics every TD designer tracks (Kingdom Rush wiki, TDS wiki, gamedev.net writeups):

1. **DPS = damage × attack_speed** (or burst form for clip weapons)
2. **gold per DPS = cumulative_cost / DPS** — *lower is better*

Plus enemy-side:
- **Effective HP** = `max_health / (1 - armor)` for physical, `/ (1 - magic_resist)` for magic. Wave difficulty = sum of EHP, not raw HP.
- **Difficulty score per enemy** = `2·EHP + 50·lives_worth + 0.02·move_speed`. Two for HP and lives because they directly compress player time. Used by `BalanceCalculator.score_level()`.

---

## Design intent — leaderboards reframe balance

Online leaderboards per level are a planned feature. This changes what "balanced" means and which failure modes matter. Read this before tuning any number that affects player power.

### The reframe

Without leaderboards, balance means "every loadout clears every level at roughly the same difficulty." With leaderboards, balance means "many distinct loadouts can compete at the top." These are different goals, and the second is easier.

- **Slightly over-tuned gear is intentional, not a bug.** The metagame *is* finding strong combos. Players grind for "broken" builds; that's the loop.
- **Narrowness is the failure mode, not power.** If one combo dominates >60% of top-100 slots on any ladder, the meta has collapsed. If 20+ distinct combos can crack the top-100, the design is healthy *even if* each one is technically strong.
- **Score discrimination is the new tuning metric.** The question stops being "can a Naked Baseline player clear L3?" (still required — see Naked Baseline invariant) and adds "does a PPT-5 loadout meaningfully out-score a PPT-3 loadout on L3?" If higher gear → higher score, gear matters. If not, the level is gear-irrelevant and ladder-dead.

### Top-combo dominance bands

| State | Top-combo share of top-100 | Action |
|---|---|---|
| Healthy | <40% | Ship — diverse meta, many viable builds |
| Acceptable | 40–60% | One strong meta + counters; tolerable |
| Stale | 60–80% | Meta collapsed; needs rebalance patch |
| Broken | >80% | Ladder dead; emergency patch |

Measurable from leaderboard data once shipped. Until then, slider-panel multi-build playtesting is the proxy.

### Multi-ladder design

Don't ship one leaderboard per level. Ship 4–5 ladders against the same play data — dramatic replayability win for ~one extra column on the leaderboard table:

- **Overall** — highest raw score
- **Naked Baseline** — PPT ≤ `min_ppt + 1` only (PoE SSF / Diablo HC pattern; fanatic following)
- **Iron** — single-life mode only
- **Speed** — fastest clear time
- **Per hero** — best score per `hero_id`

The genius move is multiple bonuses with different optimization paths: glass-cannon Mage maxes time + combo bonus, tanky low-PPT warrior maxes lives + low-PPT bonus, Iron-mode runner maxes difficulty mult. Same level, three top-100 builds — that's a healthy ladder.

### Score formula sketch (not implemented yet)

```
score = base_clear_bonus
      + time_bonus           // faster clear = more (rewards execution)
      + lives_bonus          // fewer leaks = more (rewards consistency)
      + combo_bonus          // multi-kills / perfect blocks (rewards skill)
      + difficulty_mult      // Heroic ×1.5, Iron ×2.0 (rewards opt-in challenge)
      + low_ppt_bonus        // PPT-bracketed bonus (rewards naked / low-gear runs)
```

Each bonus optimized by a different build → diverse meta naturally. Author score events now with this shape in mind to avoid retrofits later.

### Power creep budget

Leaderboards die when patches invalidate old scores. Two industry patterns:

- **Seasonal reset** (Diablo / PoE) — wipe leaderboards every N months, fresh meta. Aligns with future live-IAP / events work; content commitment.
- **Version-tagged scores** — record `game_version` on each entry, separate boards per major version. Cheap, less dramatic. **Recommended for solo dev.**

Either way, every leaderboard entry must record the game version it was set under. Without that, a buff to one tower silently invalidates every prior score on every level it appears in.

### What this means for the rest of this document

- **Naked Baseline (§ Invariants below) becomes more important, not less** — it's the floor for the low-PPT challenge ladder, a real player demographic.
- **Per-tower g/DPS bands (§ Target curves) tolerate more spread** — slight overshoots are acceptable if they enable a build niche, not just raw efficiency.
- **The PPT framework** (next section) doubles as the axis players climb on, not only the designer's tuning aid.

---

## Player Power Tier (PPT)

The single scalar that summarizes a player loadout's strength, used by the audit + slider tooling and (future) leaderboards. **Read this before tuning any level's enemy mix or any content's `power_tier` field.**

### Why one scalar

You can't balance combinations. With ~10 heroes × N skills × hundreds of gear × tower picks × mode multipliers, the combination space is in the millions. Diablo and Path of Exile solve this by collapsing player power into a single number: PoE has `monster_level` vs `character_level`; we have `target_ppt` vs `effective_ppt`. Levels are authored against PPT bands, not specific loadouts.

### How content contributes

Every authored asset has a `power_tier` field (1–10):

| Resource | Field | Default | Notes |
|---|---|---|---|
| `HeroData.power_tier` | int 1–10 | 1 | 1 = warrior, 5 = legendary hero |
| `SkillData.power_tier` | int 1–10 | 1 | 1 = basic ability, 5 = ult |
| `ItemBase.power_tier` | int 0–10 | 0 (derive from rarity) | 0 → COMMON=1, MAGIC=2, RARE=3, EPIC=4, LEGENDARY=5 via `resolve_power_tier()` |
| `UpgradeData.power_tier` | int 0–10 | 1 | per-upgrade contribution |
| `TowerData.power_tier` | int 1–10 | 1 | loadout-pick PPT only; upgrade tiers not factored here |

### Effective player PPT formula

`LoadoutState.get_effective_ppt()` returns:

```
total = hero.power_tier        × 0.40
      + avg(equipped_skills)   × 0.20
      + avg(equipped_items)    × 0.30
      + avg(loadout_towers)    × 0.10
      + min(1.0, talent_count   × 0.10)   // capped bonus
      + min(1.0, upgrade_count  × 0.10)   // capped bonus
```

Hero+gear bias is intentional — those move the most across a campaign. Towers contribute only 10% because they're a *pick* (everyone has access from level 1), not a power upgrade. Bonus contributions cap at +1.0 each so grinding upgrades can't inflate PPT past the design ceiling.

**Calibration:** Naked Baseline (warrior, default skills, starter gear, no talents/upgrades, default 4 towers) computes to ~1.0. A mid-campaign loadout with rare gear + some talents trends 2–4. Endgame trends 5+. Numbers drift slightly with content; treat the formula coefficients as design knobs, document changes in SESSIONS.md.

### Per-level PPT band

Each `LevelNodeData` carries:

- `min_ppt` — Naked Baseline floor (one-star achievable at this PPT or above)
- `target_ppt` — designed-for sweet spot the audit screen compares hardness against

### Audit drift formula

```
expected_hardness = target_ppt × PPT_TO_HARDNESS_FACTOR    // = 3000.0
actual_hardness   = score_level(wave_list)
drift_pct         = (actual - expected) / expected × 100
```

`PPT_TO_HARDNESS_FACTOR = 3000.0` is calibrated so L1 (target_ppt=2, actual hardness ≈ 6,530) lands at slight under-tune (~9% below target) — intended early-game gentleness. Re-calibrate the constant if Naked Baseline math shifts substantially; **do not** rebalance L1 to fit the constant.

### PPT-banded target curve

| Level | Target PPT | Implied target hardness | BALANCE.md prior multiplier |
|---|---|---|---|
| Level 1 | 2 | 6,000 | 1.00× S₁ ≈ 6,530 ✓ |
| Level 2 | 3 | 9,000 | 1.30× ≈ 8,500 (slight overshoot — fine, keeps level interesting) |
| Level 3 | 4 | 12,000 | 1.65× ≈ 10,800 |
| Level 4 | 5 | 15,000 | 2.10× ≈ 13,700 |
| Level 5 | 6 | 18,000 | 2.70× ≈ 17,600 |

The PPT-banded curve is the canonical target going forward; the legacy multiplier-based curve lower in this doc is preserved for historical reference but defer to PPT.

### Adding new content — PPT checklist

When authoring a new tower / hero / skill / item / upgrade:

1. Set `power_tier` on the new `.tres`. Match it to similar-feel content already authored (don't invent values).
2. Open the audit screen — note which levels' drift changed (> ±5% shift = real impact).
3. If a level fell out of band, retune that level (not the new content) unless the new content is genuinely overpowered for its rarity tier.
4. Update [BALANCE.md](BALANCE.md) tower table if the new content is a tower.

### Limits of the abstraction

- **PPT is approximate, not exact.** A Mage build at PPT 4 doesn't play identically to a Knight build at PPT 4. PoE lives with this; so will we.
- **PPT ignores synergies.** Combo X + Y might be worth 2× the sum of their tiers. The audit can't see this — only telemetry can. Flag combos that win >60% of any leaderboard for individual review.
- **PPT is loadout-snapshot.** A player's PPT changes mid-run as they buy towers + level the hero. Audit is pre-level only; in-run scaling isn't tracked.

---

## Current measured values (Phase 48, Level 1 baseline)

**S₁ baseline ≈ 14,878** (audit screen, 2026-05-03). The earlier post-tune number of 6,530 (2026-04-28) is stale — commit f226988 on 2026-04-30 substantially raised every enemy's HP and armor (basic 0→18 HP, armored 20→35 HP, armor 0.3→0.45, flying 8→14 HP, healer 18→30 HP, scout 6→10 HP, boss 200→320 HP / armor 0.3→0.45). Hardness scaled ~2.28× across the level.

Recalibrated `PPT_TO_HARDNESS_FACTOR` from 3,000 → 7,500 so L1 (target_ppt=2) reads ~-1% drift on the audit. **Test stub levels L2/L3/L4 were authored against the old 3,000 factor**, so they currently read under-tuned (red drift) on the audit; that's expected and serves as a worked example of "your stubs need a retune pass after a stat change." Use the Sliders panel to refind right enemy counts.

Below table preserved for historical comparison; numbers are the pre-2026-04-30 state, NOT current.

### Per-tower g/DPS (read directly from `towers/data/*.tres`)

All values reflect post-tune state as of 2026-04-28 (full upgrade chain authoring pass).

| Tower | Tier | Build $ | Cumul $ | Damage | Atk/s | DPS | g/DPS cumul | Notes |
|---|---|---|---|---|---|---|---|---|
| Archer | L1 | 50 | 50 | 4.0 | 1.20 | 4.80 | **10.4** | physical |
| Archer | L2 | 75 | 125 | 7.0 | 1.35 | 9.45 | **13.2** | |
| Archer | L3 main | 120 | 245 | 12.0 | 1.50 | 18.00 | **13.6** | |
| Archer | L3 Ranger | 140 | 265 | 10.0 | 1.40 | 14.00 | **18.9** | + slow 45% / 1.5s |
| Archer | L3 Musketeer | 160 | 285 | 22.0 | 0.75 | 16.50 | **17.3** | high-burst single |
| Mage | L1 | 90 | 90 | 8.0 | 0.70 | 5.60 | **16.1** | magic, 150 splash, hits flying |
| Mage | L2 | 75 | 165 | 17.0 | 0.85 | 14.45 | **11.4** | "Sage Tower" (authored 2026-04-28) |
| Mage | L3 main | 120 | 285 | 32.0 | 1.00 | 32.00 | **8.9** | "Wizard Tower" |
| Mage | L3 Archmage | 140 | 305 | 28.0 | 1.20 | 33.60 | **9.1** | sustained DPS branch |
| Mage | L3 Necromancer | 160 | 325 | 38.0 | 0.85 | 32.30 | **10.1** | + 0.5s stun branch |
| Ice | L1 | 85 | 85 | **4.5** | 1.00 | 4.50 | **18.9** | + 30% slow / 1.0s, hits flying — *tuned 2026-04-28: was 3.0/3.0 DPS at 28.3 g/DPS* |
| Ice | L2 | 100 | 185 | 12.0 | 1.20 | 14.40 | **12.85** | + 50% slow / 1.5s |
| Ice | L3 main | 130 | 315 | 25.0 | 1.40 | 35.00 | **9.0** | "Blizzard Tower" (authored), + 65% slow / 2.0s |
| Ice | L3 Glacier | 140 | 325 | 24.0 | 1.50 | 36.00 | **9.0** | extreme slow 75% / 2.5s |
| Ice | L3 Permafrost | 150 | 335 | 30.0 | 1.30 | 39.00 | **8.6** | + 0.4s stun on top of slow |
| Artillery | L1 | 120 | 120 | 25.0 | 0.40 | 10.00 | **12.0** | 200 AoE, ground only |
| Artillery | L2 | 75 | 195 | 36.0 | 0.50 | 18.00 | **10.8** | "Cannon" (authored), 200 AoE |
| Artillery | L3 main | 120 | 315 | 70.0 | 0.60 | 42.00 | **7.5** | "Mortar" (authored) |
| Artillery | L3 Howitzer | 140 | 335 | 100.0 | 0.40 | 40.00 | **8.4** | nuke-per-shot branch |
| Artillery | L3 Triple Cannon | 160 | 355 | 30.0 | 1.40 | 42.00 | **8.5** | rapid-AoE branch |
| Barracks | L1 | 70 | 70 | (block-only) | — | — | — | 3 militia (22 HP) |
| Barracks | L2 | 90 | 160 | 6.0×3 | 1.10 | 19.80 | **8.1** | 3 elite militia (34 HP, 0.15 armor) |
| Barracks | L3 | 140 | 300 | 10.0×3 | 1.10 | 33.00 | **9.1** | "Veteran Garrison" — 3 vets (50 HP, 0.25 armor), rally 500px |

**Effective AoE bonus for Artillery** (typical mid-game, 3-target hit): cumul g/DPS divides by ~3, putting Artillery L3 main at ~2.5 g/DPS vs 4 enemies — still the best in class for crowd-clearing as designed.

### Per-wave hardness (Level 1, from BalanceCalculator)

Pre-tune (2026-04-28 baseline): W1=582, W2=816, W3=936, W4=1538, W5=**3588**, total=7461 (net 7411). The W5 cliff (2.33× ratio over W4) was the most painful spike.

Post-tune (2026-04-28 — counts cut on Spawn_W5_LeftBasic 12→7, _LeftArmor 4→3, _RightScouts 8→4, _RightArmor 3→2, _TopFly 6→4):

| Wave | Score | Ratio to prev | Notes |
|---|---|---|---|
| W1 | 582 | — | tutorial |
| W2 | 816 | 1.40× | smooth |
| W3 | 936 | 1.14× | gentle (could ramp slightly when authoring more enemy variety) |
| W4 (boss) | 1538 | **1.64×** | boss spike — fine for finale-of-act |
| W5 (gauntlet) | ≈2710 | **≈1.76×** | tuned — finale-appropriate, no longer a cliff |
| **Total** | ≈6580 | | (net ≈6530 after gold buffer) |

Re-run the editor to confirm post-tune numbers — exact integer depends on how the calculator rounds individual enemies.

---

## Target curves

### Per-tower g/DPS bands

The philosophy: cost-efficiency improves across upgrades (rewards committing), but L3 branches are *sidegrades* not strict downgrades.

| Tier | Target g/DPS cumul | Why |
|---|---|---|
| L1 | 16 – 22 | "first placement" — affordable but inefficient per dollar |
| L2 | 10 – 13 | mid-investment — clearly better than 2× L1 for footprint reasons |
| L3 main | 7 – 9 | committed-investment payoff |
| L3 branch | 8 – 10 | similar g/DPS to main, different *kit* (utility, AoE, range, damage type) |

### Per-tower status (post-authoring pass 2026-04-28)

All tower upgrade chains are now fully populated. Status against the g/DPS target bands:

| Status | Towers / tiers |
|---|---|
| ✓ on target (in band) | Archer L1, L2, L3 main · Mage L1, L2, L3 main, Archmage, Necromancer · Ice L1, L2, L3 main, Glacier, Permafrost · Artillery L1, L2, L3 main, Howitzer, Triple Cannon · Barracks L1, L2, L3 |
| ⚠ off target (slightly over) | **Archer L3 Ranger** — g/DPS 18.9 vs target 8–10. Buff damage 10→22 (DPS 30.8) → cumul g/DPS 10.2. |
| ⚠ off target (slightly over) | **Archer L3 Musketeer** — g/DPS 17.3 vs target 8–10. Buff damage 22→32 (DPS 24) → cumul g/DPS 11.9 — still slightly over but burst kit justifies. |

The Archer branch overshoots are flagged for a follow-up pass once telemetry shows whether players ever pick them; bumping their damage is the easiest tune.

The single-best-value tower at full upgrade is now **Artillery L3 main (Mortar)** at 7.5 cumul g/DPS with 200-radius AoE — best in class for crowd-clearing, by design. Compact, even spread across the rest at 8.4–10.2.

### Per-level hardness target curve

Each new campaign level should target a multiple of S₁ ≈ 6,530 (post-tune):

| Level | Target multiplier | Target score |
|---|---|---|
| Level 1 | 1.00× | ~6,530 (baseline) |
| Level 2 | 1.30× | ~8,500 |
| Level 3 | 1.65× | ~10,800 |
| Level 4 | 2.10× | ~13,700 |
| Level 5 | 2.70× | ~17,600 |

**Why ~1.30× and not 1.5×:** Players gain meta-power between levels (talents, upgrades, more towers). A 1.5× enemy ramp on top of +20% player power feels punishing.

### Mode multipliers

| Mode | Multiplier | What changes |
|---|---|---|
| Campaign | 1.00× | baseline |
| Heroic | 1.30× | +30% enemy HP — tests defensive depth |
| Iron | 1.30× + 1 life | +30% enemy speed, 1 life — tests perfect play |
| Endless wave N | × (1 + 0.08 × N) | linear additive HP per wave (W10 = 1.8×, W30 = 3.4×) |

---

## Authored economy + pressure curve

The level designer authors three numbers; everything else (per-wave bounties, enemy gold drops, countdowns) becomes a *derived quantity* the readout compares actual against.

### The three knobs

Per-level, in [ui/world_map/LevelNodeData.gd](../ui/world_map/LevelNodeData.gd) → [ui/world_map/level_list.tres](../ui/world_map/level_list.tres):

| Field | Example (L1) | Meaning |
|---|---|---|
| `target_duration_sec` | 360 | Passive run length floor |
| `gold_budget_total` | 700 | Max gold from kills + bounties (no early-calls) |
| `wave_pressure_targets` | [0.4, 0.5, 0.6, 0.8, 0.9] | Per-wave gear pressure target |
| `wave_gold_shares` | [0.10, 0.11, 0.16, 0.23, 0.40] | % of `gold_budget_total` per wave; sums to 1.0 |
| `wave_time_shares` | [0.13, 0.16, 0.20, 0.23, 0.28] | % of `target_duration_sec` per wave; sums to 1.0 |
| `early_call_window_sec` | 10 | Send-Wave button visible only in last N seconds of countdown |

### Gear pressure

The headline metric. For each wave:

```
required_dps   = wave_required_damage / wave_spawn_window
affordable_dps = cumul_gold_at_wave_start × dps_per_gold   (Archer L1 = 0.096)
gear_pressure  = required_dps / affordable_dps
```

Bands:

| Pressure | Read |
|---|---|
| < 0.5 | Trivial — too much gold, towers idle |
| 0.5 – 0.8 | Comfortable — has buy options, mistakes survivable |
| 0.8 – 1.0 | Tight — must commit to right damage type, no slack |
| > 1.0 | Gear-gated — Naked Baseline at risk |

Authoring rule: peak wave pressure ≤ 1.0 with default loadout (Naked Baseline invariant — CORE RULE 18).

### Early-call mechanic (risk + reward — CORE RULE 19)

Calling next wave early is BOTH an economic decision AND a difficulty decision:

- **Reward:** bonus gold scales with how early you click
- **Risk:** the next wave starts while prior wave's stragglers are still alive — concurrent threat from both waves on the map at once

The countdown for wave N+1 begins when **wave N finishes spawning** (NOT when wave N is fully cleared). Without this, calling early is free money — overlap is what gives the bonus a cost.

**Send-Wave button is visible the entire countdown (KR-canonical).** The window caps *bonus magnitude*, not *button availability* — gating button visibility creates "where's the button" dead time, which is exactly what the design tries to avoid.

```
bonus = min(countdown_remaining, early_call_window_sec)
```

| Click moment | Bonus | Board state |
|---|---|---|
| T=0 of 25s countdown | `min(25, 10) = 10g` (max) | Maximum overlap — prior wave's tail still spawning/walking |
| T=mid (15s remaining) | `min(15, 10) = 10g` (still max) | Heavy overlap |
| T=20 (5s remaining) | `min(5, 10) = 5g` (shrinking) | Light overlap |
| Wait full countdown | 0g | Clean board, normal start |

Three valid playstyles: aggressive (+gold, +pressure), balanced (less gold, less pressure), passive (no gold, clean start). Player has agency every second of the countdown — no dead waiting.

```
max_gold_with_early_calls = gold_budget_total + (wave_count × early_call_window_sec)
```

For L1 (5 waves × 10s = 50g max), early-call swing is ~7% of budget — meaningful tactical reward without distorting the authored economy.

Implementation: [autoloads/WaveManager.gd](../autoloads/WaveManager.gd) splits `_on_spawning_complete` (triggers next countdown) from `_maybe_pay_bounty` (triggers wave_completed + bounty when alive→0). Per-wave alive counts tracked in `_alive_per_wave: Dictionary` so the right bounty pays at the right moment, even when waves run concurrently.

### Editor readout

`Level<N>.gd._print_hardness_readout` calls `BalanceCalculator.level_pressure_report()` and prints:

```
[Level1/Pressure] total=700/700g (+0%)  W1 g=70/70 p=0.40/0.40  W2 g=77/77 p=0.51/0.50 ...
[Level1/DRIFT]    WARN W3 pressure actual=0.85 vs target=0.60 (+42%)   ← if drifted
```

Drift bands:

| Drift | State | Action |
|---|---|---|
| <±15% | green | ship it |
| ±15–25% | yellow | tune soon |
| >±25% | red | retune now |

### Authoring workflow

1. Open `level_list.tres`. Set `target_duration_sec`, `gold_budget_total`, `wave_pressure_targets`.
2. Set `wave_gold_shares` and `wave_time_shares` (each sums to 1.0). Default: heavier on later waves (40% of gold + 28% of time on the climax wave).
3. Open the level scene. Readout prints actuals vs targets per wave.
4. If gold drifts: adjust enemy `gold_worth` and per-wave `bounty` until each wave hits its target.
5. If pressure drifts: adjust enemy quantities (more = higher pressure, fewer = lower). Don't adjust individual enemy stats — that breaks pressure measurements.
6. Verify Naked Baseline still 1-stars with default loadout.
7. Three runs hit all KPI bands (final gold 50–200g, spend 70–90%, hero 15–35%, top tower <60%, towers built ≥5) → ship.

One knob (the pressure curve) drives the difficulty. The system tells you when it drifts.

---

## Gold budget & pacing

Hardness measures the *threat*; budget measures the *means*. Both must agree per level — a level with target hardness 6,500 and budget 400g is gear-gated; a level with hardness 6,500 and budget 1,500g is trivial. Authoring formula:

| Metric | Formula | Source |
|---|---|---|
| Per-wave gold | `Σ(enemy.gold_worth × spawn.count) + wave.bounty` | `BalanceCalculator.wave_gold()` |
| Natural budget | `starting_gold + Σ wave_gold` | `score_level_breakdown.gold_natural` |
| Max budget | `natural + Σ wave.countdown` (early-calls) | `score_level_breakdown.gold_max_with_early_calls` |
| Early-call swing | `max - natural` | `score_level_breakdown.early_call_swing` |

The **swing** is the design lever — it's how much extra gold an aggressive player earns over a passive one. Tune it to ~10–20% of the natural budget; smaller and the early-call mechanic doesn't matter, larger and the optimal play is "always call immediately" (which destroys pacing).

### Early-call formula

`bonus_gold = ceil(countdown_remaining_seconds)` — Kingdom Rush convention. 1 second saved = 1 gold. No fraction-of-total cap. Implemented in [WaveManager.call_early_wave()](../autoloads/WaveManager.gd) and emitted via `EventBus.early_wave_triggered(bonus_gold)`.

### Per-wave pressure (density)

`density = total_count / spawn_window_seconds` where `spawn_window = max emitter (start_delay + (count-1)·interval)`. Surfaces the difference between "10 enemies in 10s" (high pressure) and "10 enemies in 60s" (low pressure) at equal EHP. The hardness score deliberately doesn't fold density in — keeps the scoring monotonic — but the editor readout prints density per wave so authors can spot pacing cliffs that the score misses.

Rule of thumb: density should ramp gently across waves (e.g. 0.6 → 0.8 → 1.0 → 1.2 → 1.5 e/s). A density jump of >2× wave-over-wave is a pacing cliff even if the hardness ratio looks fine.

### Level duration — 10-minute target (rule, L4+)

Every campaign level authored from L4 onward targets **~600s of actual play time** on normal speed for a typical winning Naked Baseline run. Wave count is the primary variety knob — pick 5–14 waves to fit the level's theme; long-haul attrition levels run more waves, sprint-finale levels run fewer. Authored floor time (countdowns + spawn windows) should land around **800–900s** so that a player who calls early and speed-kills still lands near 600s actual.

**Levels predating this rule (L1–L3) are grandfathered.** Their `target_duration_sec` reflects the original 4-5 min design and should not be retuned.

**Verify before shipping a new level:**
1. Run the level once in-editor — `[LevelN/Duration] floor=Xs target=Ys gap=Z%` should read floor between 800-900s.
2. Play it 5+ times in campaign mode. After three completed runs, BalanceReport's per-level health table shows `Avg dur` per level with a `dur ±X%` flag firing on L4+ when actual drifts >25% from `target_duration_sec`.
3. If avg < 480s (under target by >20%): add a wave or stretch a spawn interval.
4. If avg > 720s (over target by >20%): cut a wave or shorten the longest spawn window.

The rule applies to **campaign / heroic / iron**. Endless duration is unbounded by definition; mode multipliers (Heroic 1.30× HP, Iron 1.30× speed + 1 life) shift actual play time by ±15% within band — flag as drift, not failure.

Implementation: `BalanceCalculator.level_floor_time(wave_list)` returns the authored sum (countdowns + spawn windows). `RunStats.duration_s` captures actual play time per run; `BalanceReport._render_per_level_health` averages it and gates the drift flag on `LevelNodeData.unlock_order >= 4`.

### Min playing time (legacy, applies to L1–L3 only)

For grandfathered levels there is no authored minimum. Total floor time = Σ wave_duration + max(enemy travel time on slowest path). The level can't end faster than enemies physically walk. If a grandfathered level feels too short, add waves or stretch spawn intervals — don't add a clock. **For new levels, defer to the 10-minute target rule above.**

### Hardness tiers

Text label rendered next to raw score on WorldMap cards. Bands match `BalanceCalculator.tier_for_score()`:

| Tier | Score range |
|---|---|
| Tutorial | < 4,000 |
| Easy | 4,000 – 7,000 |
| Medium | 7,000 – 11,000 |
| Hard | 11,000 – 16,000 |
| Brutal | 16,000+ |

---

## Invariants

Hard rules. If a change breaks one of these, the change is wrong — re-tune until the rule holds.

### Naked Baseline

Every campaign level must be **1-starable** with all of:

- Default selected hero (`hero_warrior`)
- Zero equipped items
- Zero purchased meta-upgrades
- Zero hero talents

This is the floor every level is balanced against. The per-level hardness target curve (§ "Per-level hardness target curve" above) sets the *ceiling* — what a fully-geared player should find challenging. The Naked Baseline sets the *floor* — what an unequipped player should still be able to clear, even if barely.

Gear, talents, and upgrades are *bonuses* that ease a level or unlock 3-star runs. They are never *requirements* for basic progression.

**Why:** prevents gear-gating. Without this rule, equipment loot becomes mandatory grind and a player who skips the loot loop hits a wall. With this rule, gear stays motivational rather than mandatory.

**How to verify** before a level ships:
1. Delete `user://savegame.save` (clean save)
2. Pick `hero_warrior` in the loadout
3. Confirm inventory is empty (`InventoryManager.get_all_equipped(hero_id).is_empty()`)
4. Play campaign mode end-to-end
5. If you can't 1-star, the level is gear-gated — tune it down before merging

---

## Loot drop curve

Drops should be rare and exciting. Target **1–3 pickups per typical level**, with bosses guaranteed as the predictable celebration anchor. A flooded inventory makes every drop noise; the dopamine loop is "ooh, what is it?", which only works when drops are infrequent.

### Knobs

| Source | File | Value | Why |
|---|---|---|---|
| Trash drop chance | [items/data/loot_table_default.tres](../items/data/loot_table_default.tres) | `drop_chance = 0.015` | Flat rate. Levels of 48–206 enemies → expected 0.7–3.1 drops. Variance is intentional: short levels are usually dry, long levels reward grinding. |
| Boss drop chance | [items/data/loot_table_boss_orc.tres](../items/data/loot_table_boss_orc.tres) | `drop_chance = 1.0` | Every boss kill = guaranteed drop. The KR-canonical "you cleared the wave, here's your prize" moment. |
| Wooden Sword weight | default table entry | `1.0` (was `2.0`) | 0-affix common stays in pool but no longer dominates. Per user direction: "small improvement is still improvement," don't yank it. |
| Demon Core weight | default table entry | `0.08` | ≈0.02% per kill. ~1 in 5000 kills, true mythic. Bosses bias higher (`0.25`). |

### Per-rarity affix value scaling

Without scaling, a Demon Core's 4 affix slots roll the same value range as an Iron Sword's 1 slot. Rarity changes *how many* affixes, not *how good*. Scaling fixes that — applied in [autoloads/LootRoller.gd](../autoloads/LootRoller.gd) `_rarity_value_multiplier()`:

| Rarity | ItemBase enum | Multiplier | Example: damage_flat 5 base roll |
|---|---|---|---|
| 0 | COMMON | 1.0× | 5 (irrelevant — Wooden has 0 affix slots) |
| 1 | MAGIC | 1.0× | 5 (Iron Sword baseline) |
| 2 | RARE | 1.25× | 6 |
| 3 | EPIC | 1.5× | 8 |
| 4 | LEGENDARY | 2.0× | 10 |

Re-rounded to int when `AffixData.value_is_int = true` so display stays clean.

### Why flat rate, not per-level

Authoring per-level loot tables (with calibrated `drop_chance` per level length) was considered and rejected. The flat-variance choice means *each level naturally tunes itself by length* with zero authoring overhead. If playtesting shows L1/L2 dry-spell frustration, the next lever is a **pity counter** (force-drop on a level that ended with zero trash drops), not per-level tables.

### Verification

- Run L1–L4 in editor; expected 0–2 drops on L1/L2, 1–2 on L3, 2–4 on L4 (incl. boss).
- Force-roll a Demon Core in Test Range; affix values should be ~2× an Iron Sword roll of the same affix.
- Inventory shouldn't fill up over a campaign — that's the regression to watch for if `drop_chance` creeps back up.

---

## Future direction — Two-Brain Stat Architecture

**Status: Phase 49+. Not implemented. Design captured here so it doesn't get lost.**

The proposal: split hero gear stats into two categories so high-tier gear can scale without making towers irrelevant.

### A. Hero-Only stats (current behavior of all affixes)

Affect the hero's performance as a mobile unit:

- **Vitality** — max HP, HP regen (matters most for blocking heroes)
- **Haste** — attack speed, skill cooldown
- **Might** — flat damage on basic attacks

This is what every existing AffixData rolls today (`max_health`, `damage`, `attack_speed_pct`, etc.).

### B. Command stats (new)

Multipliers for towers within the hero's *aura* radius:

- **Tactics** — +X% range on nearby towers
- **Engineering** — −X% upgrade cost on nearby towers
- **Lethality** — +X% crit chance/damage on nearby tower shots

### Why this matters

Without Command stats, every gear pass either makes the hero overpowered (and towers irrelevant) or makes gear pointless. Command stats let high-tier gear scale strongly while keeping the hero a *commander* rather than a damage dealer — the Kingdom Rush pattern.

### Cost to implement (deferred)

~1–2 weeks of solo dev:

1. New `AbilityData` subclasses: `AuraTowerRangeAbility`, `AuraTowerCritAbility`, `AuraTowerCostAbility`
2. Aura system on the hero — radius check + apply/remove on tower entry/exit
3. `BaseTower` queries nearby heroes for command bonuses (cache + refresh on hero move)
4. EquipmentScreen UI redesigned — split stats column into "Personal" vs "Command"
5. New affix pools so loot rolls Command stats on appropriate slots

### Caveat

The failure mode "+500 sword makes hero solo the map" depends on hero base DPS scaling freely. Today Knight base DPS is ~6, Mage ~3.2 — current `_pct` affixes already inflate this dangerously. **Capping pct affixes at +50% per slot is a complementary control, not a substitute** for the Two-Brain split. Both should land together when this work happens.

### Mechanical-effect items (the other half)

A second future direction worth pairing with Two-Brain: high-tier gear should grant *mechanical* effects, not just stat numbers. Examples:

- "Sergeant's Banner": Recruit spell summons 5 soldiers instead of 4
- "Tactician's Cloak": +60s to wave countdown
- "Frost Ring": Mage's basic attack chains to 2 nearby enemies

Mechanical effects don't roll random magnitudes — they're either active or not. Cleaner balance than stacked pct affixes, more interesting than flat numbers.

---

## Telemetry

`autoloads/RunStats.gd` writes to `user://run_stats.json` after every campaign/heroic/iron run. Capped at last 50. Test Range runs are excluded (mode = "test_range").

Each record has: tower placements, max levels reached, branch choices, lives lost per wave, hero deaths, spells cast, duration, outcome, stars earned.

To get aggregate views (which towers carry, where lives leak), build `balance/report/BalanceReport.gd` — reads `run_stats.json`, rolls up across runs, displays in-editor.

---

## Supply vs Demand model

Layered on top of PPT + Naked Baseline. Two headline numbers per level:

- **player_supply** — total effective damage the player can produce over the level's `target_duration_sec`, segmented by source (towers, hero, skills, control, blocking).
- **level_demand** — total EHP the player must remove plus archetype premiums (boss EHP × `boss_demand_weight`, healer/regen abilities → `ability_ehp_add`, etc.) plus block_cost.
- **safety_ratio** = supply / demand. Banded for color: red < 1.00, orange < 1.15, green < 1.40, blue < 2.00, grey ≥ 2.00. Bands live on `BalanceModelConfig` — designers edit `.tres`, not code.

Drill-down vectors identify the **bottleneck** (the axis where the player struggles): `anti_air`, `armored`, `magic_res`, `swarm`, `boss`, `rush`, `gold`. The lowest sub-ratio < 1.0 names the bottleneck; "none" if all ≥ 1.0. Visible in the per-level row of the Supply / Demand report.

### Principles

- **Don't collapse to one number.** The safety_ratio is the headline; the per-axis bars are how you debug a level. (Riot's champion balance framework — same lesson.)
- **PPT + Naked Baseline stays the floor.** Supply/Demand is *additional*, never a replacement. A level still has to be one-starable at `min_ppt`.
- **Don't flatten CC to flat damage.** Apply slow/stun as a DPS multiplier on the affected enemy *during* the CC window, capped at `control_stack_cap` fraction of `kill_window`. (SMITE diminishing-returns precedent.)
- **Don't invent weights from intuition.** Every weight in `BalanceModelConfig` ships at 1.0 (or the historical hardcoded value). Move it only when ≥3 levels drift in the same direction in the predicted-vs-observed table.
- **Track effective:theoretical DPS.** Community-observed range 50–80% — towers spend cycles out of range, on dead targets, between projectiles. Calibrate per-level from `RunStats.damage_by_tower`. Default `effective_to_theoretical_dps_ratio = 0.65`.

### Closing the audited gaps

Pre-supply/demand, several `EnemyData` fields were authored but never scored:

- **Abilities** (RegenAbility, HealAuraAbility) — now contribute `ability_ehp_add`. A healer's `heal_amount × heal_aura_avg_targets / interval × kill_window` is added to the wave's EHP demand.
- **`magic_resist`** — was diagnostic only. Now feeds the `magic_resist_ehp` demand vector vs `physical_supply`.
- **`is_flying`** — drives the `flying_ehp` demand vector vs `anti_air_supply`.
- **`is_boss` + `boss_phases`** — `boss_ehp` × `boss_demand_weight × (1 + phase_count × phase_bonus)`.
- **`bypass_engagement`** — feeds `bypass_pressure` vs `segment_blocking`.
- **`attack_damage` × `attack_speed`** — feeds `block_cost` (drain on supply during enemy engagement).

### Per-tier tower weights + supply segmentation

Every tower is evaluated at every reachable tier independently — `tower_avg_dps_per_gold(tower)` averages L1 / L2 / L3 linear / branch DPS-per-gold weighted by `tier_l1_weight` / `tier_l2_weight` / `tier_l3_linear_weight` / `tier_branch_weight`. Push a tier's weight to 0.5 if data shows players never reach it.

Supply is segmented and tagged by `damage_type` / `targets_flying` / `aoe_radius` / on-hit control so each segment's contribution to anti-air / armored / swarm / boss demand can be compared independently.

### Calibration loop

The Supply/Demand report's right-hand column reads `RunStats.get_history()` and shows observed `win_pct` + `avg_leaks` per level. Drift flags:

- safety ≥ green_max but win% < 0.5 → `⚠ harder` (model under-predicts).
- safety < red_max but win% > 0.85 → `⚠ easier` (model over-predicts).

When ≥3 levels flag in the same direction, re-fit per-segment weights — never tune individual numbers from intuition.

### Read order before changing weights

1. Open the report (WorldMap → S/D Report, debug-only).
2. Identify the level whose drift is flagged.
3. Read the drill-down (demand vector, supply vector, sub-ratios).
4. Move the *one* weight that maps to the bottleneck (e.g. flying-heavy levels miscalibrated → adjust `flying_demand_weight`, never blanket-tune all archetype weights).
5. Click Refresh; verify the level's drift flag clears without breaking neighbors.
6. If the change holds across 3+ levels, click "Save Weights" to persist to `balance_model_config.tres`.

---

## Pacing targets (Phase 48 — KR-feel pass, 2026-05-07)

Premium TDs (Kingdom Rush canon) keep enemies on screen long enough for the player to read the wave, watch projectiles arc, and react. Pre-pass our basics crossed L1 in ~14 s at 1× / ~5 s at 3×, which felt frantic and prevented hero/soldier melee duels from lasting more than a swing or two. This pass biases toward "deliberate at 1×, brisk at 2×, still readable at 3×."

### Travel-time bands (L1, 1991 px reference path)

| Enemy class | Target 1× | Target 3× | Speed band (px/s) |
|---|---:|---:|---:|
| Heavies (Brute, Boss base) | 25–30 s | ≥ 8 s | 65–80 |
| Armored / Healer | 20–28 s | ≥ 7 s | 75–100 |
| Basic chasers | 18–24 s | ≥ 6.5 s | 90–110 |
| Flying | 14–18 s | ≥ 5 s | 110–140 |
| Fast runners (Scout) | 11–14 s | ≥ 4 s | 140–180 |

Anything below the 3× floor means a single tower can barely engage — the projectile lifetime exceeds the engagement window. Don't drop speeds below the band.

### HP bias for "fight-feel"

Squishy chasers (Basic, Scout, Flying, Healer) carry **+30 % HP** vs the pre-pass values so hero/soldier engagements last 3+ swings instead of 1–2. Heavies (Brute, Armored, Boss) keep their existing HP — they were already in the right band. The intent is *more time per enemy in combat*, not *more enemies surviving*.

### Tower range bias

Combat-tower L1 ranges trimmed by ~10 % (Archer 400→360, Ice 350→315) and Artillery by ~12.5 % (600→525). L2/L3 ranges scaled proportionally. Mage stays at 300. Compresses engagement zones so the player visually sees enemies *enter* and *exit* tower coverage rather than getting shot the whole way across the map. Range-trim is uniform across each tower's progression so upgrade-relative gain stays the same.

### Speed button policy — keep 1×/2×/3×

No mainline Kingdom Rush ships fast-forward; Ironhide has refused the request for ~13 years. Our 3× is a deliberate UX advantage. With the pacing pass applied, basics at 3× = ~7 s — comfortably above the "single tower can engage" floor. Do not narrow `HUD.SPEED_OPTIONS` without strong playtest signal.

### Verification on next play-test

- Stopwatch a basic enemy on L1 from spawn → keep at 1×: should land in 18–24 s.
- A hero vs. armored squad melee duel should last > 5 s before either side dies.
- Per-enemy archer-shot count should be ~3–5 across L1 coverage, not 1–2.
- Re-run `BalanceCalculator.score_level()` on Level 1 — slower + tougher chasers raises tower DPS efficiency, so hardness will rise. If it overshoots the L1 PPT=2 target band (~15,000), reduce the chaser HP bump from +30 % to +20 %.

---

## When to update this file

- After every `.tres` numbers change → update the "current measured values" table
- After every play-test cohort → update commentary on which targets the data confirms / contradicts
- When adding a new tower → add a row to the target table
- Never let this file lag behind the actual data — out-of-date design intent is worse than no design intent

## When NOT to update this file

- Per-run telemetry — that lives in `user://run_stats.json` automatically
- Code architecture decisions — those go in `CLAUDE.md` (invariants) or `SESSIONS.md` (chronology)
- Bug fixes / one-off tuning — only update when the *target* curve changes, not when matching values to existing targets
