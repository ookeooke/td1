# Agent Briefs

Reusable scout briefs for Claude Code, Codex, and GPT review passes.

Agents are for investigation first. Default mode is report-only.

Use like:

```text
Use docs/agents/balance_scout.md in level mode.
Report only, no edits.
Check Level 4 and Level 5.
```

Rules:

- Agents do not edit files unless explicitly asked.
- Agents return findings, evidence, risks, and one recommended next task.
- Main Claude implements one selected task after the report.
- Keep reports short enough to act on.

Suggested workflow:

1. Run one or more scouts.
2. Pick one recommendation.
3. Ask Claude Code to implement only that task.
4. Verify with `docs/DEV_WORKFLOW.md`.
