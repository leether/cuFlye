# Task Card: cuFlye M5y Read Alignment Post-Bypass Attribution

Status: accepted

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

- [x] CPU, M5w, and M5x timing sources are recorded with exact proof paths.
- [x] Stage attribution separates worker request time from full Flye elapsed
      time.
- [x] Any real/sampled dataset run records source path, parameters, and
      canonical artifact status.
- [x] Next-boundary recommendation names the bottleneck and claim boundary.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Accepted on DGX with proof root:

```text
/tmp/cuflye-m5y-proof-20260701T051312Z
```

Timing attribution sources:

```text
cpu_baseline=/tmp/cuflye-m5r-proof-20260701T032358Z/out/m5r/flye-cpu-baseline
m5w_attribution=/tmp/cuflye-m5y-proof-20260701T051312Z/out/m5y/flye-m5w-attribution-full3546
m5x_attribution=/tmp/cuflye-m5y-proof-20260701T051312Z/out/m5y/flye-m5x-attribution-full3546
```

Positive M5w attribution proof:

```text
canonical_diff=match
compact_binary_validation=ok
fixture_count=3546
total_cpu_predivergence_chains=3546
total_cpu_bypassed_reads=0
total_cpu_chain_dp_wall_ms=1.034468
total_cpu_divergence_filter_wall_ms=174.507361
total_gpu_divergence_filter_wall_ms=167.293184
total_replay_fixture_dump_wall_ms=797.055909
vector_substitution_wall_ms=14.897338
worker_request_total_ms=2.510887
full_flye_elapsed_seconds=20.81
```

Positive M5x attribution proof:

```text
canonical_diff=match
compact_binary_validation=ok
fixture_count=3546
total_cpu_predivergence_chains=0
total_cpu_bypassed_reads=3546
total_cpu_bypass_inserted_chains=3546
total_cpu_chain_dp_wall_ms=0.0
total_cpu_divergence_filter_wall_ms=0.0
total_gpu_divergence_filter_wall_ms=167.315051
total_replay_fixture_dump_wall_ms=759.316593
vector_substitution_wall_ms=20.1518
worker_request_total_ms=5.675857
full_flye_elapsed_seconds=20.88
```

Golden manifest:

```text
tests/golden/cuflye-m5y-read-alignment-post-bypass-attribution-dgx-aarch64.json
```

Next recommended boundary:

```text
M6a: move upstream to the read-to-graph overlap/minimizer input boundary and
define a candidate-generation oracle before adding more CUDA kernels, because
selected chain-DP bypass is not the dominant toy-hifi wall-time bottleneck.
```

Plain-language benefit:

```text
M5y proves the selected CPU work really is bypassed and the final Flye artifacts
still match CPU exactly. The bypassed CPU chain DP itself is only about 1 ms on
the toy-hifi selected set; the skipped CPU divergence filter is about 175 ms,
but Flye still runs the GPU-derived divergence filter and the proof still pays
fixture/audit overhead. So this is a correctness and attribution win, not a
meaningful whole-Flye speedup. The next ROI is earlier in read-to-graph
candidate discovery.
```
