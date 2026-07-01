# Task Card: cuFlye M5x Read Alignment Selected CPU Bypass

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M5w full3546 guarded substitution proof into the first audited
selected-read CPU-bypass experiment for read-to-graph alignment.

The core question for this card is:

```text
Can Flye skip CPU pre-divergence chain DP for an explicit selected-read
allowlist, consume compact-binary CUDA-derived goodChains instead, preserve
exact canonical artifacts, and fail closed on any worker, validation, or
substitution issue?
```

## In Scope

- Add an opt-in CPU-bypass mode for the selected read-alignment allowlist only.
- Reuse `compact-binary-v0` validation and
  `verified-goodchains-v0` substitution.
- Keep the CPU path as default behavior.
- Preserve exact canonical Flye artifacts versus CPU baseline.
- Measure selected read-alignment CPU work avoided, CUDA request timing, seam
  timing, and full Flye elapsed time.
- Add at least one corruption or mismatch proof that fails closed before graph
  mutation and falls back to no consumption rather than silent CPU/GPU drift.

## Out of Scope

- No default GPU mode.
- No non-allowlisted `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's divergence filter unless separately proven.
- No speed claim unless CPU work is actually bypassed and exact artifacts still
  match.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Prefer explicit state objects over global mutable shortcuts.
- Use RAII for any new resource-owning C++ helper.
- Unsupported shapes, missing worker output, malformed compact binary payloads,
  and selected-read count mismatches must fail closed.

## Deliverables

- Flye patch for opt-in selected-read CPU bypass.
- DGX positive proof with exact canonical artifact match.
- DGX negative proof that prevents graph mutation consumption.
- Timing summary separating avoided CPU path, CUDA request time, Flye seam
  time, and full Flye elapsed time.
- Golden manifest under `tests/golden/`.
- Roadmap update with plain-language benefit and claim boundaries.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] Positive selected CPU-bypass mode consumes verified compact-binary
      CUDA-derived goodChains for the full3546 selected set.
- [x] Positive proof records that selected CPU chain DP was skipped rather
      than computed and then replaced.
- [x] Canonical Flye artifacts match CPU.
- [x] Negative mismatch/corruption case fails closed before graph mutation.
- [x] Timing summary separates CUDA request time, Flye seam time, avoided CPU
      work, and full Flye elapsed time.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Accepted on DGX with proof root:

```text
/tmp/cuflye-m5x-proof-20260701T050004Z
```

Positive selected CPU-bypass proof:

```text
fixture_count=3546
selected_cpu_bypass_mode=verified-goodchains-v0
selected_cpu_bypass_enabled=true
total_cpu_bypassed_reads=3546
total_cpu_predivergence_chains=0
total_cpu_good_chains=0
total_cpu_bypass_inserted_chains=3546
total_worker_records=3616
total_substituted_chains=3546
graph_mutation_consumed_worker_output=true
canonical_diff=match
worker_actual_wall_ms=4.145493
worker_request_total_ms=2.128259
worker_kernel_ms=0.042353
full_flye_elapsed_seconds=20.741208213
```

Negative truncation proof:

```text
proof_fault=truncate-compact-binary-payload
status=failed
decision=failed-closed-before-graph-mutation
flye_exit_status=1
selected_cpu_bypass_enabled=true
total_cpu_bypassed_reads=3546
total_cpu_predivergence_chains=0
graph_mutation_consumed_worker_output=false
total_worker_records=0
total_substituted_chains=0
worker_request_total_ms=1.670786
full_flye_elapsed_seconds=13.921030998
```

Golden manifest:

```text
tests/golden/cuflye-m5x-read-alignment-selected-cpu-bypass-dgx-aarch64.json
```

Plain-language benefit:

```text
M5x is the first real CPU-bypass milestone for read alignment: for the full3546
selected set, Flye no longer calculates CPU pre-divergence chains and then
replaces them; it leaves audited placeholders, consumes verified CUDA
goodChains, and still produces byte-equivalent canonical artifacts. The
measurable whole-toy Flye gain is tiny, about 0.024 seconds, so the honest
claim is local correctness plus a small scoped speed win, not a meaningful
end-to-end GPU Flye speedup.
```
