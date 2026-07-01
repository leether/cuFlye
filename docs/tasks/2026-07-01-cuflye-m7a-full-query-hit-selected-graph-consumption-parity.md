# Task Card: cuFlye M7a Full Query-Hit Selected Graph-Consumption Parity

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6z's no-mutation timing attribution to the first selected
graph-consumption parity gate.

M6y/M6z prove that selected CPU handoff rows can be skipped, supplied by CUDA,
timed, and still stopped before graph mutation. M7a should cross the next
boundary carefully: build the graph-facing selected handoff from CUDA-supplied
selected rows plus CPU-owned residual rows, let it reach the controlled
consumption point, and prove canonical Flye artifacts remain identical.

## In Scope

- Add an opt-in selected graph-consumption parity mode after M6z gates pass.
- Use the M6y final merged ledger/object-vector shape as the graph-facing
  handoff source.
- Preserve CPU-owned residual rows explicitly.
- Compare default CPU canonical artifacts against the existing golden fixture.
- Record positive proof showing selected graph-consumption parity on the
  bounded toy fixture.
- Record negative proof that fails closed when selected CUDA-supplied rows are
  corrupted, missing, duplicated, or leaked back into CPU-owned handling.
- Store a compact DGX proof manifest under `tests/golden/`.

## Out of Scope

- No default GPU mode.
- No broad full-query-hit replacement outside the selected proof set.
- No claim that whole Flye is faster.
- No graph simplification or repeat-resolution algorithm changes.
- No unsupported-shape fallback hidden from metadata.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep the selected CUDA-supplied rows and CPU-owned residual rows separately
  auditable even after the graph-facing handoff is built.
- Fail closed before or at the controlled consumption gate if any M6z
  correctness/timing gate or graph-output parity gate fails.

## Deliverables

- Flye patch implementing the opt-in selected graph-consumption parity gate.
- ABI/design notes for the selected graph-consumption parity JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6z correctness and timing gates pass before graph-consumption parity is
      trusted.
- [ ] Positive DGX proof records selected CUDA-supplied rows and CPU-owned
      residual rows reaching the graph-facing handoff.
- [ ] Positive DGX proof preserves exact default CPU canonical artifacts on
      `toy-hifi`.
- [ ] Positive DGX proof records the graph-consumption parity status and row
      counts in machine-readable JSON.
- [ ] Negative proof fails closed when a selected CUDA-supplied row is missing,
      corrupted, duplicated, or leaked back into CPU-owned handling.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
