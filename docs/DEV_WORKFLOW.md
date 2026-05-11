# DEV_WORKFLOW.md

Fast local verification workflow for Claude Code, Codex, and human sessions.

## Godot Binary

Prefer `godot` when it is on PATH. On this Windows machine, the known console binary is:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe"
```

Use the console binary for automated checks because PowerShell can capture its output.

## Commands

VS Code tasks are available in `.vscode/tasks.json`:

- `Godot: Version`
- `Godot: Headless Boot`
- `Godot: GUT Tests` (default test task)
- `Godot: Open Editor`
- `Godot: Run Game`

Version check:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --version
```

Headless boot check:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --quit
```

Full unit suite:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Run in editor:

```powershell
& "C:\Godot_v4.6.2-stable_win64.exe (1)\Godot_v4.6.2-stable_win64_console.exe" --path . --editor
```

## Good Output

Headless boot should load the autoloads and print a clean ContentRegistry line similar to:

```text
[ContentRegistry] loaded - 7 enemies, 5 towers, 3 heroes, 3 trees, 24 item_bases, 15 affixes, 4 pools, 5 levels
```

GUT should end with:

```text
Tests                35
Passing Tests        35
Asserts              258
---- All tests passed! ----
```

Expected warnings today:

- GUT ignores `tests/unit/test_helpers.gd` because it is a helper, not a test.
- Save tests intentionally exercise corrupt JSON and unknown save versions.
- Some optional audio files are missing in tests.

Unexpected failures:

- Any failing test.
- Any `[ContentRegistry/DRIFT]` line.
- Any post-summary freed-instance or signal error.
- Any crash with signal 11 that prevents project logs from printing.

## If Headless Godot Crashes

The local Windows headless runner has shown intermittent `signal 11` crashes before project logs. When that happens:

1. Close and reopen the PowerShell / VS Code terminal.
2. Rerun the same command once.
3. If it still crashes before project logs, mark verification as blocked.
4. Do not claim tests passed unless GUT reaches the run summary.
5. Verify visually in the Godot editor or defer to CI.

## Manual Editor Checks

Use the editor for anything visual, touch-driven, or feel-dependent:

- Mobile HUD and safe area.
- Radial tower menu.
- Skill targeting.
- Wave-call button.
- Hero movement and selection.
- Equipment and hero hub screens.
- Balance feel and level pacing.

For mobile UI work, check at least a phone-like landscape ratio and a tablet-like ratio.
