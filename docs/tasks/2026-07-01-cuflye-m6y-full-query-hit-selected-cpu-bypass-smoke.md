# Task Card: cuFlye M6y Full Query-Hit Selected CPU-Bypass Smoke

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6x's selected bypass dry-run ledger to the first guarded selected
CPU-bypass smoke.

M6x marks selected rows as bypassed in dry-run state, but it still primarily
proves accounting. M6y should prove the next boundary: selected full-query-hit
rows can be treated as CPU-selected-handoff-skipped, supplied by the
CUDA-derived bypass rows, while CPU-owned residual rows remain explicit and the
whole merged handoff is still blocked before graph mutation.

## In Scope

- Add an opt-in selected CPU-bypass smoke mode after M6x passes.
- Record selected CPU handoff rows as skipped in the smoke ledger.
- Record CUDA-derived selected bypass rows as the selected handoff supplier.
- Preserve CPU-owned residual rows and reasons from M6x.
- Record a final merged smoke ledger accounting for all CPU raw-overlap rows.
- Compare the merged smoke ledger against the CPU oracle row keys.
- Add a negative proof fault that makes a skipped selected CPU row leak back
  into the CPU-owned path or removes a bypassed selected row, and fail closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation or graph simplification change.
- No broad full-query-hit replacement outside the selected proof set.
- No whole-Flye speedup claim.
- No GPU-computed chain-input filtering or edge identity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and scoped to the live
  `RepeatGraph`.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Keep skipped CPU-selected rows, CUDA-supplied selected rows, and CPU-owned
  residual rows as separate explicit ledgers.
- Fail closed if any row-key, rehydration, ledger, binding, object-vector
  smoke, substitution-guard, verified-substitution, bypass-plan, selected
  bypass dry-run, or selected CPU-bypass smoke gate fails.

## Deliverables

- Flye patch implementing the opt-in selected CPU-bypass smoke audit.
- ABI/design notes for the selected CPU-bypass smoke JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p through M6x gates must pass before selected CPU-bypass smoke runs.
- [x] Positive DGX proof records nonzero selected CPU handoff rows as skipped.
- [x] Positive DGX proof records the same count as CUDA-derived selected
      bypass supplied rows.
- [x] Positive DGX proof preserves explicit CPU-owned residual rows.
- [x] Positive DGX proof accounts for all CPU raw-overlap rows in the final
      merged smoke ledger.
- [x] Positive DGX proof proves selected CPU-bypass smoke output is not
      consumed by graph mutation.
- [x] Negative proof fails closed before graph mutation when a skipped selected
      CPU row leaks back into the CPU-owned path or a selected bypass row is
      removed.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in Flye patch `0053` with an opt-in selected CPU-bypass smoke
mode:

- `CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_MODE=selected-cpu-bypass-smoke-v0`
- `CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_PROOF_FAULT=leak-first-skipped-cpu-row`

ABI/design notes:

- `docs/abi/read-to-graph-full-query-hit-selected-cpu-bypass-smoke-v0.md`

Golden proof:

- `tests/golden/cuflye-m6y-full-query-hit-selected-cpu-bypass-smoke-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m6y-proof-20260701T130000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_m6x_selected_bypass_status=passed
positive_m6y_selected_cpu_bypass_smoke_status=passed
positive_skipped_cpu_selected_rows=8
positive_cuda_supplied_selected_rows=8
positive_cpu_owned_residual_rows=28
positive_total_cpu_raw_overlap_rows=36
positive_final_merged_ledger_rows=36
positive_final_cuda_supplied_rows=8
positive_leaked_selected_cpu_rows=0
positive_missing_cuda_supplied_rows=0
positive_unexpected_cuda_supplied_rows=0
positive_cuda_supplied_row_key_diff_status=match
positive_final_merged_row_key_diff_status=match
positive_consumed=false
positive_not_consumed=true
positive_graph_mutation_consumed_worker_output=false
positive_selected_cpu_bypass_smoke_checks=22/22
negative_status=selected-cpu-bypass-smoke-failed-before-graph-mutation
negative_m6x_selected_bypass_status=passed
negative_m6y_selected_cpu_bypass_smoke_status=failed
negative_proof_fault=leak-first-skipped-cpu-row
negative_proof_fault_applied=true
negative_skipped_cpu_selected_rows=8
negative_cuda_supplied_selected_rows=8
negative_final_cuda_supplied_rows=7
negative_leaked_selected_cpu_rows=1
negative_final_merged_row_key_diff_status=match
negative_failed_checks=final_cuda_supplied_rows_match_supplier,leaked_selected_cpu_rows_zero
summary_checks=27/27
```

Allowed M6y claim:

```text
cuFlye can skip the 8 M6x-selected CPU handoff rows in a guarded smoke ledger,
supply the same 8 rows from CUDA-derived selected bypass output, preserve 28
CPU-owned residual rows, account for all 36 CPU raw-overlap rows in the final
merged handoff, and fail closed before graph mutation if a skipped selected CPU
row leaks back into CPU-owned handling.
```

Forbidden M6y claim:

```text
M6y does not prove whole-Flye speedup, default GPU mode, real graph mutation,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6y still does not make full Flye faster. It proves the selected rows can now
be treated as "CPU handoff skipped and CUDA supplied" under audit, while all
other rows stay CPU-owned and a bad handoff stops before graph mutation.
```

Next highest-ROI task:

```text
M6z: add selected CPU-bypass timing attribution. Now that M6y proves the
semantic skip boundary, measure the skipped CPU handoff work, CUDA supplier
handoff cost, seam overhead, and residual CPU work so the next integrated gate
can make or reject a real performance claim with numbers.
```
