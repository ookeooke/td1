# Unified Hero Chooser Design

> Reference spec for the HeroesHub choosers (Hero Overview · Equipment · Skills).
> Read before touching `ui/HeroesHub.*`, `ui/EquipmentScreen.*`,
> `ui/HeroSkillsPage.*`, or adding `ui/HeroSkillMap.gd`.
> Authored 2026-05-18. Source: 5 internet-research scouts + user 5-phase plan.

---

## 1. Purpose & scope

WorldMap's **Hero** button opens **HeroesHub** — a master–detail shell
(TopBar + 140px sidebar hero chooser + swappable embedded page). It hosts three
choosers:

- **Hero Overview** — pick the active hero, read its stats.
- **Equipment** — slot gear into a paperdoll from an inventory grid.
- **Skills** — learn / equip active skills, passives, mods; unlock slots.

They already share clean `EventBus.hero_selected` wiring (Preventive Bug Rule 3)
but **diverge in detail-panel layout and commit interaction**. The Skills screen
is also a list-heavy "admin" UI with no progression feel.

Goal: make the three feel like **one AAA mobile-first hero-management system**,
built **additively** — no rewrites of ship-tested scripts, no save-key or
content-ID changes (CORE RULE 1; "finish existing, don't rebuild" memory).
**Non-goal:** a data-driven LevelData-style refactor or a monolithic `ChooserHub`
class — the shared skeleton is a *pattern*, not a forced abstraction.

---

## 2. Unified skeleton

Generalize the **existing** HeroesHub layout. Every chooser is a master area
(left) + a persistent **fixed right detail panel**, with the primary action in
the bottom-right thumb zone.

```
┌──────────────────────────────────────────────────────────────┐
│ TopBar:  ✕ back        <SCREEN TITLE>            ★ meta gold   │  ~80px
├──────┬────────────────────────────────────┬───────────────────┤
│ NAV  │  MASTER AREA                       │  DETAIL PANEL      │
│ RAIL │  (varies per screen:               │  (constant frame, │
│ 140px│   roster / paperdoll+grid /        │   body varies)    │
│  ▲   │   skill map)                       │  icon · name      │
│ hero │                                    │  badge · rank     │
│ list │      ● selected element            │  stat / diff rows │
│  ▼   │                                    │  lock reason      │
│ ──── │                                    │  ───────────────  │
│ nav  │                                    │  [ ACTION BTN ]   │  ← bottom-right
└──────┴────────────────────────────────────┴───────────────────┘
   constant            varies                 frame constant
```

| Screen | Master renderer | Detail body | Confirm verb |
|---|---|---|---|
| Hero Overview | sidebar roster (existing) | hero stats / readiness | Select (non-destructive) |
| Equipment | paperdoll + inventory grid | item stats + compare delta | Equip / Replace / Unequip / Sell |
| Skills | **HeroSkillMap** constellation + equipped strip | node stats + next-rank diff | Learn / Upgrade / Equip / Pick Mod |

The 140px sidebar (hero list + page-nav) and TopBar are **already** the shared
chrome — `HeroesHub._embed_screen()` hides each embedded screen's own
TopBar/Background and pulls its Body up. We reuse that, not replace it.

---

## 3. Constant vs. variable contract

**Constant across all three** (the learnability contract):

- Nav rail position + behavior; page-swap via `_open_sub_view`.
- Selection affordance: single highlight/outline on the selected element.
- Detail-panel **position** (fixed right) and **primary-action placement**
  (bottom-right of the panel).
- The one interaction rule (§4).
- Back/dismiss; visual design tokens (`ThemeColors`), fonts, spacing.
- Hero-swap clears selection + any armed action.

**Varies per screen** (content only):

- Master renderer (roster vs. paperdoll+grid vs. skill map).
- Detail-body rows (hero stats vs. item affixes vs. node effect/diff).
- Confirm verb + validity rule.

---

## 4. The one interaction rule

```
tap content  →  inspect in right panel  →  tap action button
             →  (two-step confirm if it spends points or is destructive)
             →  commit
```

- **Tapping a tile / node / item never commits.** It only selects + inspects.
- **Actions live on panel buttons**, not on the master tile.
- **Two-step arm→confirm** for: skill-point spend (Learn/Upgrade), Equip/Replace/
  Unequip, Sell. First button tap arms (button restyles to a distinct
  armed/confirm color + label e.g. "Sell? +Ng"); second tap on the same button
  commits. Mirrors `TowerRadialMenu` / `TowerIconButton.set_armed()`.
- **Single-tap carve-outs** (non-destructive, reversible): hero Select, tab
  switches, target-cycle-style toggles.
- Selecting a different element clears the armed action. Hero change clears
  selection + arm.

This generalizes Equipment's existing sell-only two-step to every spend/destroy
action and removes HeroSkillsPage's "instant commit on tap" (its current pain).

---

## 5. Right detail-panel spec

One panel layout, three bodies. Top→bottom:

1. Icon (procedural — `SkillGlyph` / `ItemGlyph` / hero portrait draw).
2. Name + kind/rarity badge.
3. Current state line: rank `X/3`, equipped status, or slot fill.
4. **Stat / effect rows** via `StatRow` + `StatIcon`.
5. **Diff vs. current** when applicable (next rank, or item-vs-equipped):
   reuse `TowerStatsCard._diff_bbcode()` semantics — **green = gain, red = loss,
   dim = unchanged**. Do not reinvent the coloring.
6. **Lock / unavailable reason rendered here** (not toast-only): "Requires
   Shield Bash R2", "Hero level 4", "Locked — unlock for €X".
7. Bottom-right **primary action button** (the only commit surface).

Equipment keeps tap-item→inspect; its modal bottom-sheet is replaced by this
panel (Phase 4). Because the bottom-sheet's dim backdrop (mis-tap protection on
a dense grid) goes away, grid cells must **consume** their tap (no pass-through).

---

## 6. Skill-map spec (the new product piece)

A Path-of-Exile-lite constellation replacing the Skills list. Driven entirely by
**existing** `HeroSkillTreeData` / `HeroSkillNodeData` — Phase-0 audit confirmed
the data is rich enough; **no `.tres` changes**.

**Node kinds** (`HeroSkillNodeData.Kind`): `ACTIVE_RANK`, `PASSIVE_RANK`, `MOD`,
`SLOT_UNLOCK`, `CAPSTONE`. Edges = `prerequisite_ids`. Clustering = `target_id`
(all ranks+mods of one skill share a `target_id`). Progression axis =
`level_required` (1→10).

**Runtime layout heuristic (deterministic, no authored positions):**

- **X** = `level_required` (1..10) → left-to-right progression.
- **Y lanes** by kind: `ACTIVE_RANK` upper band, `PASSIVE_RANK` lower band,
  `MOD` attached adjacent to its `target_id`'s active node, `SLOT_UNLOCK` as
  full-height gate markers at their `level_required`, `CAPSTONE` center-right
  at the far edge.
- Within a `target_id` cluster, order by `rank`; chain prereq → dependent.
- Draw a connector line for every `prerequisite_ids` entry.

**Visual:** distinct shape+color per kind (active = circle/blue-gold, passive =
hex/purple, mod = small circle near parent, slot = wide gate, capstone = large
gold). **Node states:** locked-dim / available / purchased-bright / equipped-ring
/ selected-outline. Hit area ≥ 80px.

**Contract:** `HeroSkillMap` is a new `Control` (Phase 2). `setup(hero_id)`,
`set_selected_node(node_id)`, emits `node_selected(node_id)`. **It commits
nothing** — all purchase/equip/mod actions go through the §5 panel buttons,
calling the **unchanged** `LoadoutState` / `MetaProgression` mutators.

---

## 7. Reusable components (compose, don't write new)

| Need | Reuse | Path |
|---|---|---|
| Palette / tokens | `ThemeColors` | `ui/theme/ThemeColors.gd` |
| Mobile safe area | `SafeAreaMargin` + `DisplayUtils.get_safe_insets()` | `ui/SafeAreaMargin.gd` |
| Selectable tile + armed→confirm state machine | `TowerIconButton`, `ItemIcon`, `HeroCard` | `ui/TowerIconButton.gd`, `ui/ItemIcon.gd`, `ui/HeroCard.gd` |
| Gain/loss/dim diff coloring | `TowerStatsCard._diff_bbcode()` | `ui/TowerStatsCard.gd` |
| Stat row (icon+label+value, flash) | `StatRow` + `StatIcon` | `ui/StatRow.gd`, `ui/StatIcon.gd` |
| Skill pictograms | `SkillGlyph.draw()` | `ui/SkillGlyph.gd` |
| Embed a page into the hub | `HeroesHub._embed_screen()` | `ui/HeroesHub.gd` |
| Hero-swap signal | `EventBus.hero_selected` (connect `_ready`, disconnect `_exit_tree`) | autoload |
| Skill tree access | `ContentRegistry.find_skill_tree(hero_id)` → `HeroSkillTreeData` | autoload |

---

## 8. Mobile UX checklist (every chooser must pass)

1. Every interactive element ≥ 80×80px.
2. ≥ 16px spacing between adjacent targets.
3. Primary action bottom-right of the detail panel.
4. Back/Cancel bottom-left, not adjacent to primary.
5. Nothing tappable in top-center / dead-center.
6. List/page nav on the side rail within thumb arc.
7. All UI inside safe-area insets (landscape side notch + home indicator).
8. Anchor-based layout, not fixed pixels.
9. Body text ≥ 14–16px; item/skill names 16px+ bold.
10. Text contrast ≥ 4.5:1; passes grayscale-separation.
11. Scrim/outline behind text drawn over artwork.
12. Icons paired with a text label (no icon-only actions).
13. Buttons consume taps — no pass-through to the master/grid beneath.
14. Spend/destructive picks use the two-step confirm (§4).
15. Verified on phone (5") and tablet (4:3) aspect in-editor before sign-off.

---

## 9. Per-screen wireframes

**Hero Overview**
```
[✕]            CHOOSE YOUR HERO                      ★ 1240
┌──────┬──────────────────────────────┬────────────────────┐
│ P1 ● │   [ big hero portrait ]      │ WARRIOR  Melee·Lv7 │
│ P2   │                              │ HP ███░ DMG ██░    │
│ P3   │                              │ Skill1 Shield Bash │
│ 🔒P4 │                              │ Skill2 Rally Cry   │
│ ──── │                              │ XP ▓▓▓▓░░ L7→L8    │
│ Over │                              │                    │
│ Equip│                              │      [ SELECT ]    │
│ Skill│                              │                    │
└──────┴──────────────────────────────┴────────────────────┘
```

**Equipment**
```
[✕]              EQUIPMENT                           ★ 1240
┌──────┬───────────────┬──────────────┬────────────────────┐
│ rail │  PAPERDOLL    │ BAG GRID     │ Iron Helm  (Rare)  │
│      │   (head)      │ ▣▣▣▣▣▣       │ +4 Armor   ▲       │
│ hero │  [body slots] │ ▣▣●▣▣▣       │ vs equipped:       │
│ list │   (ring)(rng) │ ▣▣▣▣▣▣       │  Armor 12→16 ▲     │
│      │   (weapon)    │ [Gear|Relic] │                    │
│ nav  │               │              │ [Equip] (arm→ok)   │
└──────┴───────────────┴──────────────┴────────────────────┘
```

**Skills (HeroSkillMap)**
```
[✕]               SKILLS — WARRIOR                   ★ 3pts
┌──────┬───────────────────────────────┬───────────────────┐
│ rail │ Active:[Bash][Rally][+]       │ Shield Bash  R2/3 │
│      │ Passive:[Endur][--][lock L9]  │ ACTIVE · equipped │
│ hero │  ─ active lane ─              │ Dmg 60→75 ▲       │
│ list │  ○──○ shield_bash ─◌ mods     │ CD 8s  AoE 90     │
│      │  ─ passive lane ─             │ Next: R3 (L6,1pt) │
│ nav  │  ⬢ endurance  ⬢ resilient     │ [Upgrade] arm→ok  │
│      │            ▣gate L8   ★cap    │                   │
└──────┴───────────────────────────────┴───────────────────┘
```

---

## 10. Implementation roadmap (binding order)

1. **Phase 0 — data go/no-go.** ✅ GO (this doc, §6). Runtime layout, no `.tres`.
2. **Phase 1 — hero selector scroll affordance** (`HeroesHub.tscn/.gd`). Visible
   ▲/▼ arrows around the rail; scroll ~one button height; dim at extremes;
   scroll selected into view on `hero_selected`.
3. **Phase 2 — `ui/HeroSkillMap.gd`** (new file, inspect-only, §6).
4. **Phase 3 — host map in `HeroSkillsPage.gd`** (additive; old list behind a
   flag until verified). Equipped strip + map + §5 panel; existing mutators.
5. **Phase 4 — Equipment detail panel** (`EquipmentScreen.gd/.tscn`):
   bottom-sheet → fixed right panel; keep sell two-step; grid cells consume taps.
6. **Phase 5 — polish + safety**: distinct selection vs armed colors; touch
   consumption; no PC mouse+touch double-fire; reasons in-panel; empty states.

Each phase independently shippable + editor-verifiable. SESSIONS.md entry +
STATUS.md update after implementation.

---

## 11. References

- Kingdom Rush UI analysis — emilym.space
- Game UI Database (character select / Diablo IV / Genshin) — gameuidatabase.com
- Diablo Immortal controls — diabloimmortal.wiki.fextralife.com
- Wild Rift "Choose your loadout" — interfaceingame.com
- Master–detail interface pattern — Wikipedia / webapphuddle.com
- Thumb-zone & WCAG 2.5.8 target size — parachutedesign.ca, w3.org/WAI
- Exile-UI item info / Last Epoch tooltip redesign — github.com/Lailloken, forum.lastepoch.com
