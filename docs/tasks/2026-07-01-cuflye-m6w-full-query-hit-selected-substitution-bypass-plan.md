# Task Card: cuFlye M6w Full Query-Hit Selected Substitution Bypass Plan

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6v's verified would-substitute ledger into a guarded selected
CPU-bypass plan for read-to-graph full-query-hit rows.

M6v proves that the CUDA-derived would-substitute ledger matches the selected
CPU handoff rows by row key and order, while still blocking graph mutation.
M6w should turn that verified ledger into an explicit bypass decision ledger:
which selected CPU handoff rows could be skipped, which rows remain CPU-owned,
and why the graph path is still protected until a later consumption gate.

## In Scope

- Add an opt-in selected-substitution-bypass-plan mode after M6v passes.
- Record selected rows eligible for CPU handoff bypass.
- Record non-selected or unsupported rows as CPU-owned.
- Prove selected bypass count equals M6v verified substitution ledger count.
- Preserve a rollback-safe ledger with query/edge accounting and row-key proof.
- Add a negative proof fault that corrupts the bypass ledger and fails closed
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
- Fail closed if any row-key, rehydration, ledger, binding, object-vector
  smoke, substitution-guard, verified-substitution, or bypass-plan gate fails.

## Deliverables

- Flye patch implementing the opt-in selected bypass-plan audit.
- ABI/design notes for the bypass-plan JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p, M6q, M6s, M6t, M6u, and M6v gates must pass before bypass planning
      runs.
- [x] Positive DGX proof records nonzero selected bypass-eligible rows.
- [x] Positive DGX proof selected bypass count equals M6v substitution ledger
      count.
- [x] Positive DGX proof records CPU-owned residual rows explicitly.
- [x] Positive DGX proof proves the bypass plan is not consumed by graph
      mutation.
- [x] Negative proof fails closed before graph mutation when the bypass ledger
      is intentionally corrupted.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed on DGX with proof root:

```text
/tmp/cuflye-m6w-proof-20260701T114500Z
```

Implemented:

- Flye patch:
  `patches/flye/2.9.6/0051-cuflye-read-to-graph-full-query-hit-selected-bypass-plan.patch`
- ABI note:
  `docs/abi/read-to-graph-full-query-hit-selected-bypass-plan-v0.md`
- Runner switches for:
  `--read-to-graph-full-query-hit-selected-bypass-plan-mode` and
  `--read-to-graph-full-query-hit-selected-bypass-plan-proof-fault`
- Golden proof:
  `tests/golden/cuflye-m6w-full-query-hit-selected-bypass-plan-dgx-aarch64.json`

DGX proof summary:

```text
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_selected_bypass_plan_status=passed
positive_selected_bypass_eligible_rows=8
positive_selected_bypass_ledger_rows=8
positive_verified_substitution_ledger_rows=8
positive_cpu_owned_residual_rows=28
positive_cpu_owned_missing_bypass_rows=0
positive_total_cpu_raw_overlap_rows=36
positive_bypass_row_key_diff_status=match
positive_bypass_ordered_row_key_matched=true
positive_plan_checks=18/18
negative_status=selected-bypass-plan-failed-before-graph-mutation
negative_selected_bypass_plan_status=failed
negative_proof_fault=drop-first-bypass-ledger-row
negative_proof_fault_applied=true
negative_selected_bypass_ledger_rows=7
negative_cpu_owned_residual_rows=29
negative_cpu_owned_missing_bypass_rows=1
negative_bypass_row_key_diff_status=mismatch
negative_graph_mutation_consumed_worker_output=false
summary_checks=24/24
```

Allowed M6w claim:

```text
cuFlye can turn the M6v verified selected substitution ledger into an explicit
selected CPU-bypass plan: 8 selected rows are bypass-eligible, 28 residual rows
remain CPU-owned, all 36 CPU raw-overlap rows are accounted for, and a corrupt
bypass ledger fails closed before graph mutation.
```

Forbidden M6w claim:

```text
M6w does not prove whole-Flye speedup, real graph mutation, default GPU mode,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6w still does not make full Flye faster. It tells us exactly which rows are
safe candidates to skip on the CPU side and which rows must stay CPU-owned, so
the next milestone can try a real selected bypass without guessing.
```
