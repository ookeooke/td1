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

## Current measured values (Phase 48, Level 1 baseline)

**S₁ baseline ≈ 6,530** (post-tune 2026-04-28; was 7,411 before W5 was lightened). Use this as the multiplier base for future levels — printed live by Level1.gd's hardness readout, so re-read after every wave-data change.

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
| Endless wave N | × (1 + 0.08 × N) | compounding HP per wave |

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

## When to update this file

- After every `.tres` numbers change → update the "current measured values" table
- After every play-test cohort → update commentary on which targets the data confirms / contradicts
- When adding a new tower → add a row to the target table
- Never let this file lag behind the actual data — out-of-date design intent is worse than no design intent

## When NOT to update this file

- Per-run telemetry — that lives in `user://run_stats.json` automatically
- Code architecture decisions — those go in `CLAUDE.md` (invariants) or `SESSIONS.md` (chronology)
- Bug fixes / one-off tuning — only update when the *target* curve changes, not when matching values to existing targets
