# Task Card: cuFlye M6w Full Query-Hit Selected Substitution Bypass Plan

Status: proposed

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

- [ ] M6p, M6q, M6s, M6t, M6u, and M6v gates must pass before bypass planning
      runs.
- [ ] Positive DGX proof records nonzero selected bypass-eligible rows.
- [ ] Positive DGX proof selected bypass count equals M6v substitution ledger
      count.
- [ ] Positive DGX proof records CPU-owned residual rows explicitly.
- [ ] Positive DGX proof proves the bypass plan is not consumed by graph
      mutation.
- [ ] Negative proof fails closed before graph mutation when the bypass ledger
      is intentionally corrupted.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
