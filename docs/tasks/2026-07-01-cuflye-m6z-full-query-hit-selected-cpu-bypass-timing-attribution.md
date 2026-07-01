# Task Card: cuFlye M6z Full Query-Hit Selected CPU-Bypass Timing Attribution

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6y's correctness-only selected CPU-bypass smoke to a bounded timing
and attribution gate.

M6y proves that selected full-query-hit CPU handoff rows can be skipped and
supplied by CUDA-derived rows without reaching graph mutation. M6z should
measure that seam: how much CPU handoff work is skipped, how much CUDA supplier
handoff costs, how much seam accounting costs, and how much residual work stays
CPU-owned.

## In Scope

- Add opt-in timing attribution around the M6y selected CPU-bypass smoke seam.
- Record selected skipped CPU row counts, CUDA-supplied row counts, residual
  CPU-owned row counts, and final merged ledger row counts.
- Record coarse wall-clock timings for CPU selected handoff accounting, CUDA
  supplier read/rehydration, final merge accounting, and total smoke seam time.
- Preserve M6y positive and negative fail-closed behavior.
- Compare default CPU canonical artifacts against the existing golden fixture.
- Store a compact DGX proof manifest under `tests/golden/`.

## Out of Scope

- No default GPU mode.
- No graph mutation consumption.
- No claim that full Flye is faster.
- No broad full-query-hit replacement beyond the selected proof set.
- No CUDA kernel rewrite in this card unless it is required to expose existing
  worker timing already produced by the worker.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Use RAII and existing helper patterns for timers and JSON emission.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep timing metadata separate from semantic pass/fail checks; timing noise
  must not hide correctness failures.
- Fail closed before graph mutation if any M6y correctness gate fails.

## Deliverables

- Flye patch extending the M6y smoke JSON with timing-attribution fields or
  writing a sibling timing JSON.
- Runner switches or manifest fields needed to enable the timing attribution.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6y correctness gates still pass before timing attribution is trusted.
- [x] Positive DGX proof records selected skipped CPU rows, CUDA-supplied rows,
      CPU-owned residual rows, and final merged rows.
- [x] Positive DGX proof records nonzero, machine-readable timing fields for
      selected CPU skip accounting, CUDA supplier handoff, final merge
      accounting, and total selected CPU-bypass seam time.
- [x] Positive DGX proof preserves `consumed=false` and
      `graph_mutation_consumed_worker_output=false`.
- [x] Negative proof still fails closed before graph mutation on
      `leak-first-skipped-cpu-row`.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in Flye patch `0054` by extending the M6y selected CPU-bypass smoke
JSON with `timing_ms` and mirroring that object into the top-level worker
dry-run JSON.

Golden proof:

- `tests/golden/cuflye-m6z-full-query-hit-selected-cpu-bypass-timing-attribution-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m6z-proof-20260701T140000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_selected_cpu_bypass_smoke_checks=26/26
positive_skipped_cpu_selected_rows=8
positive_cuda_supplied_selected_rows=8
positive_cpu_owned_residual_rows=28
positive_final_merged_ledger_rows=36
positive_consumed=false
positive_graph_mutation_consumed_worker_output=false
positive_timing_selected_cpu_skip_accounting_ms=0.089280
positive_timing_cuda_supplier_handoff_ms=0.028721
positive_timing_final_merge_accounting_ms=0.005760
positive_timing_selected_cpu_bypass_smoke_total_ms=0.128913
negative_status=selected-cpu-bypass-smoke-failed-before-graph-mutation
negative_selected_cpu_bypass_smoke_checks=24/26
negative_failed_checks=final_cuda_supplied_rows_match_supplier,leaked_selected_cpu_rows_zero
negative_timing_selected_cpu_bypass_smoke_total_ms=0.127041
summary_checks=16/16
```

Allowed M6z claim:

```text
cuFlye can attribute the M6y selected CPU-bypass smoke seam on DGX: the selected
CPU skip accounting, CUDA supplier handoff, final merge accounting, and total
smoke seam timings are all machine-readable and nonzero while M6y correctness
and fail-closed behavior remain intact.
```

Forbidden M6z claim:

```text
M6z does not prove whole-Flye speedup, default GPU mode, or real graph mutation.
It only measures the selected CPU-bypass smoke seam.
```

Plain-language benefit:

```text
M6z still does not make full Flye faster. It tells us where the selected
CPU-bypass seam spends time on the toy proof: about 0.129 ms total, with most
of that in selected CPU skip accounting and a smaller CUDA supplier handoff.
That is enough to choose the next engineering step based on numbers instead of
guessing.
```

Next highest-ROI task:

```text
M7a: move from no-mutation smoke to a selected graph-consumption parity gate.
Use the CUDA-supplied selected rows plus CPU-owned residual rows at the actual
graph-facing handoff, preserve exact canonical artifacts, and fail closed if
the selected bypass changes graph output.
```
