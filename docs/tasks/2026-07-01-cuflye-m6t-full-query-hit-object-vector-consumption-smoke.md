# Task Card: cuFlye M6t Full Query-Hit Object Vector Consumption Smoke

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6s graph-edge binding into a no-mutation object-vector consumption
smoke test for CUDA full-query-hit rows.

M6s proves that every chain-input-positive selected worker row can bind back to
a live Flye `GraphEdge*`. M6t should build the first graph-facing in-memory
object vector from those rows, account every object, and still prevent that
vector from being returned into Flye's mutating read-to-graph path.

## In Scope

- Add an opt-in object-vector smoke mode after M6s graph-edge binding passes.
- Construct bounded graph-facing objects from chain-input-positive worker rows
  using the live `GraphEdge*` bindings.
- Record deterministic object counts by query and edge.
- Prove the constructed vector is not consumed by graph mutation.
- Add a negative proof fault that corrupts object accounting and fails closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No replacement of Flye's CPU read-to-graph path.
- No real graph mutation or graph simplification change.
- No whole-Flye speedup claim.
- No GPU-computed chain-input filtering or edge identity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Use non-owning `GraphEdge*` only when the owner and lifetime are the live
  `RepeatGraph`.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Fail closed if any row-key, rehydration, ledger, binding, or object
  accounting gate fails.

## Deliverables

- Flye patch implementing the opt-in object-vector smoke audit.
- ABI/design notes for the object-vector smoke JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6p, M6q, and M6s gates must pass before object-vector smoke runs.
- [ ] Positive DGX proof records nonzero constructed graph-facing objects.
- [ ] Positive DGX proof accounts every object by query and edge.
- [ ] Positive DGX proof proves the object vector is not consumed by graph
      mutation.
- [ ] Negative proof fails closed before graph mutation when object accounting
      is intentionally corrupted.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
