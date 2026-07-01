# Task Card: cuFlye M5y Read Alignment Post-Bypass Attribution

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Attribute the remaining Flye wall time after M5x selected CPU-bypass and choose
the next performance boundary based on measured evidence rather than momentum.

The core question for this card is:

```text
After selected read-alignment chain DP is bypassed, is the next highest-ROI
CUDA target still read alignment, or has the bottleneck moved earlier to
overlap/minimizer discovery or later to another graph/polishing stage?
```

## In Scope

- Compare CPU baseline, M5w verified substitution, and M5x selected CPU-bypass
  timing on the toy-hifi proof.
- Add stage-level timing attribution around read-to-graph alignment, worker
  request, substitution, and full Flye elapsed time.
- If an approved small real/sampled dataset is available on DGX, run the same
  attribution there without changing scientific parameters.
- Recommend the next CUDA boundary with allowed and forbidden speed claims.

## Out of Scope

- No new default GPU mode.
- No broad rewrite of read alignment.
- No new kernel unless attribution shows a specific hot boundary.
- No performance claim from unverified artifacts.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep instrumentation opt-in and deterministic.
- Do not reformat upstream Flye code.
- Avoid new dependencies.

## Deliverables

- Timing attribution proof manifest under `tests/golden/`.
- Roadmap update with the next boundary decision.
- Plain-language benefit assessment explaining whether M5x is enough to move on
  or whether read-alignment needs a larger workload proof.

## Acceptance Gates

- [ ] CPU, M5w, and M5x timing sources are recorded with exact proof paths.
- [ ] Stage attribution separates worker request time from full Flye elapsed
      time.
- [ ] Any real/sampled dataset run records source path, parameters, and
      canonical artifact status.
- [ ] Next-boundary recommendation names the bottleneck and claim boundary.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
