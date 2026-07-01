# Task Card: cuFlye M6x Full Query-Hit Selected Bypass Dry-Run

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M6w selected bypass plan into the first guarded selected-bypass
execution dry-run.

M6w only records which selected full-query-hit rows could bypass the CPU handoff
and which rows remain CPU-owned. M6x should exercise that boundary in an
opt-in dry-run: selected rows are supplied by the verified CUDA-derived object
vector for downstream handoff accounting, residual rows stay CPU-owned, and the
whole merged ledger is still stopped before graph mutation.

## In Scope

- Add an opt-in selected-bypass dry-run mode after M6w passes.
- Mark selected rows as actually bypassed in the dry-run ledger.
- Preserve CPU-owned residual rows and reasons from M6w.
- Compare bypassed selected row keys against the M6w selected bypass ledger.
- Record a merged bypass-plus-CPU-owned accounting ledger for all CPU
  raw-overlap rows.
- Add a negative proof fault that corrupts the selected bypass payload and
  fails closed before graph mutation.
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
- Keep selected bypass state explicit and auditable; no hidden global state.
- Fail closed if any row-key, rehydration, ledger, binding, object-vector
  smoke, substitution-guard, verified-substitution, bypass-plan, or selected
  bypass dry-run gate fails.

## Deliverables

- Flye patch implementing the opt-in selected-bypass dry-run audit.
- ABI/design notes for the selected-bypass dry-run JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p through M6w gates must pass before selected bypass dry-run runs.
- [x] Positive DGX proof records nonzero selected rows as actually bypassed in
      dry-run state.
- [x] Positive DGX proof bypassed row count equals M6w selected bypass ledger
      count.
- [x] Positive DGX proof preserves explicit CPU-owned residual rows.
- [x] Positive DGX proof accounts for all CPU raw-overlap rows in the merged
      bypass-plus-CPU-owned ledger.
- [x] Positive DGX proof proves selected bypass output is not consumed by graph
      mutation.
- [x] Negative proof fails closed before graph mutation when the selected
      bypass payload is intentionally corrupted.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed on DGX with proof root:

```text
/tmp/cuflye-m6x-proof-20260701T123000Z
```

Implemented:

- Flye patch:
  `patches/flye/2.9.6/0052-cuflye-read-to-graph-full-query-hit-selected-bypass-dry-run.patch`
- ABI note:
  `docs/abi/read-to-graph-full-query-hit-selected-bypass-dry-run-v0.md`
- Runner switches for:
  `--read-to-graph-full-query-hit-selected-bypass-dry-run-mode` and
  `--read-to-graph-full-query-hit-selected-bypass-dry-run-proof-fault`
- Golden proof:
  `tests/golden/cuflye-m6x-full-query-hit-selected-bypass-dry-run-dgx-aarch64.json`

DGX proof summary:

```text
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_bypass_plan_status=passed
positive_selected_bypass_dry_run_status=passed
positive_selected_bypassed_rows=8
positive_bypass_plan_ledger_rows=8
positive_cpu_owned_residual_rows=28
positive_merged_ledger_rows=36
positive_total_cpu_raw_overlap_rows=36
positive_selected_bypass_missing_rows=0
positive_selected_bypass_unexpected_rows=0
positive_row_key_diff_status=match
positive_ordered_row_key_matched=true
positive_selected_bypass_checks=17/17
negative_status=selected-bypass-dry-run-failed-before-graph-mutation
negative_bypass_plan_status=passed
negative_selected_bypass_dry_run_status=failed
negative_proof_fault=drop-first-selected-bypass-row
negative_proof_fault_applied=true
negative_selected_bypassed_rows=7
negative_bypass_plan_ledger_rows=8
negative_cpu_owned_residual_rows=28
negative_merged_ledger_rows=36
negative_selected_bypass_missing_rows=1
negative_row_key_diff_status=mismatch
summary_checks=28/28
```

Allowed M6x claim:

```text
cuFlye can mark the 8 M6w-selected full-query-hit rows as actually bypassed in
dry-run state, preserve 28 CPU-owned residual rows, account for all 36 CPU
raw-overlap rows in a merged ledger, and fail closed before graph mutation when
the selected bypass payload is corrupted.
```

Forbidden M6x claim:

```text
M6x does not prove whole-Flye speedup, default GPU mode, real graph mutation,
or GPU-computed chain-input filtering/edge identity.
```

Plain-language benefit:

```text
M6x still does not make full Flye faster. It is the first step where selected
rows are no longer only "eligible" on paper: they are marked as bypassed in a
dry-run execution ledger, while the rest remains CPU-owned and the graph is
still protected.
```
