# Task Card: cuFlye M6x Full Query-Hit Selected Bypass Dry-Run

Status: proposed

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

- [ ] M6p through M6w gates must pass before selected bypass dry-run runs.
- [ ] Positive DGX proof records nonzero selected rows as actually bypassed in
      dry-run state.
- [ ] Positive DGX proof bypassed row count equals M6w selected bypass ledger
      count.
- [ ] Positive DGX proof preserves explicit CPU-owned residual rows.
- [ ] Positive DGX proof accounts for all CPU raw-overlap rows in the merged
      bypass-plus-CPU-owned ledger.
- [ ] Positive DGX proof proves selected bypass output is not consumed by graph
      mutation.
- [ ] Negative proof fails closed before graph mutation when the selected
      bypass payload is intentionally corrupted.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
