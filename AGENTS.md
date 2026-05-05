# AGENTS.md

Entry point for AI coding tools (Claude Code, Codex CLI, Aider, Cursor, etc.) working in this repo.

> **Fantasy Tower Defense** — Godot 4.6.2 / GDScript / Android + iOS + PC.

## Read these first, in order

1. **[CLAUDE.md](CLAUDE.md)** — invariants, core rules, autoload list, system contracts, conventions. The single most important file. Read fully before editing code.
2. **[STATUS.md](STATUS.md)** — current focus, next-up tasks, known issues. Read before proposing new work.
3. **[balance/BALANCE.md](balance/BALANCE.md)** — design intent for tuning: target curves, hardness bands, the Naked Baseline invariant, the 10-minute level duration rule. Read before any balance change.
4. **[SESSIONS.md](SESSIONS.md)** — chronological phase log of what's been built and why. Append a new entry at the end of every working session.

## Where things live

| Topic | Location |
|---|---|
| Engineering rules + invariants | [CLAUDE.md](CLAUDE.md) |
| Balance design intent | [balance/BALANCE.md](balance/BALANCE.md) |
| Balance tooling (read-only audit) | [balance/audit/](balance/audit/), [balance/report/](balance/report/) |
| Balance tooling (runtime sliders) | [balance/debug/](balance/debug/) |
| Balance test sandbox | [balance/test_range/](balance/test_range/) |
| Hardness scoring math | [balance/BalanceCalculator.gd](balance/BalanceCalculator.gd) |
| Autoloads (20 globals) | [autoloads/](autoloads/) — see CLAUDE.md "Autoloads" table |
| Towers / heroes / enemies / soldiers / items | [towers/](towers/), [heroes/](heroes/), [enemies/](enemies/), [soldiers/](soldiers/), [items/](items/) |
| Levels (.tscn + waves .tres) | [levels/](levels/) |
| Level templates | [levels/templates/](levels/templates/) |
| WorldMap / loadout / shop UI | [ui/](ui/) |
| Ability system | [systems/abilities/](systems/abilities/) |
| Unit tests (GUT) | [tests/unit/](tests/unit/) |

## House rules (most-violated, restated tersely)

- **Don't modify working scripts unless asked.** Append or add new scripts. (CLAUDE.md CORE RULE 1.)
- **All cross-system communication via EventBus signals.** No direct node references between unrelated systems.
- **Stats live in `.tres` Resource files, never hardcoded in scripts.**
- **Stable content IDs (`tower_id`, `hero_id`, etc.) match the filename basename and never rename after first release.** (CORE RULE 12.)
- **Use `load()` not `preload()` for shared-script `.tres` arrays in autoloads.** (CORE RULE 16 — works around Godot 4.4+ class_name preload race.)
- **Read [BALANCE.md](balance/BALANCE.md) before changing any number.** Balance targets are bands, not intuition.

## Running the game

```bash
godot --path . --editor    # open in editor
godot --path .             # run directly (entry: ui/MainMenu.tscn)
```

No build system, no linter. Validate by running in the Godot editor.

## Tests

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

CI runs the same on every push (.github/workflows/ci.yml).
