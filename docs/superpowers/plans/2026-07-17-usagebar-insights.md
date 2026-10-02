# UsageBar Insights Plan (v1.2)

User approved features 1–4. Executed inline by the same agent.

1. **Burn-rate projection** — `Projection.forecast(percent, resetsAt, windowMinutes, now)` in Core.
   Linear rate from window start (resetsAt − window) to now; project time-to-100%; flag
   `willHitBeforeReset`. `LimitBar` gains `windowMinutes: Int?` (Claude 300/10080, Codex from
   `window_minutes`). Shown as a one-line warning under a bar only when on pace to hit before reset.
2. **Model breakdown** — `Aggregation.modelBreakdown(events, since)` → `[ModelCost]` sorted by cost.
   Providers retain events; `ProviderSnapshot.modelBreakdown`. Shown as "By model: Opus $X · …" (top 3).
3. **Cost by project** — Claude `cwd` field (exact) → project name; cost accumulated per project;
   `ProviderSnapshot.projectBreakdown: [ProjectCost]` (Claude only). Shown "By project: … " (top 3).
4. **Comparative selector** — replace the segmented Picker with a custom row showing all three
   providers' session bars + % at once; tapping selects (comparison + navigation in one control).

Core is TDD'd; providers/UI verified by build + `--check` + live install.
