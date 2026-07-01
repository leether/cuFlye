# Task Card: cuFlye M6v Full Query-Hit Verified Substitution Smoke

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6u's guarded substitution handoff into the first verified
substitution smoke for CUDA full-query-hit rows.

M6u proves that Flye can receive the CUDA-derived graph-facing object vector at
a guarded handoff and fail closed on a corrupted count before graph mutation.
M6v should add an opt-in no-mutation smoke path that validates whether the
guarded vector is eligible to replace the matched CPU-derived handoff for the
selected rows, records a rollback-safe substitution ledger, and still blocks
real graph mutation.

## In Scope

- Add an opt-in verified-substitution-smoke mode after M6u passes.
- Compare CUDA handoff objects with the matched CPU-derived selected handoff
  shape before any replacement is allowed.
- Record would-substitute row counts, query/edge accounting, and a
  rollback-safe substitution ledger.
- Prove the substitution decision is not consumed by graph mutation.
- Add a negative proof fault that corrupts the substitution ledger and fails
  closed before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No real graph mutation or graph simplification change.
- No unguarded replacement of Flye's CPU read-to-graph path.
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
  smoke, substitution-guard, or verified-substitution gate fails.

## Deliverables

- Flye patch implementing the opt-in verified-substitution smoke audit.
- ABI/design notes for the verified-substitution JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6p, M6q, M6s, M6t, and M6u gates must pass before verified
      substitution smoke runs.
- [ ] Positive DGX proof records nonzero would-substitute rows.
- [ ] Positive DGX proof substitution ledger count equals guarded handoff
      object count.
- [ ] Positive DGX proof proves the substitution decision is not consumed by
      graph mutation.
- [ ] Negative proof fails closed before graph mutation when the substitution
      ledger is intentionally corrupted.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
