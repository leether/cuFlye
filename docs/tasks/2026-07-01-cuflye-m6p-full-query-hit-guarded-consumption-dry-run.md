# Task Card: cuFlye M6p Full Query-Hit Guarded Consumption Dry-Run

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from session-scale worker proof toward graph-facing integration by parsing
session-validated CUDA full-query-hit raw-overlap rows into Flye-side typed
structures, while still refusing to mutate graph state.

## In Scope

- Reuse the M6n/M6o `session-file-v0` full-query-hit worker path.
- Add an explicit opt-in guarded dry-run mode for Flye-side raw-overlap
  rehydration.
- Validate row-key parity before any rehydration is marked eligible.
- Rehydrate validated worker rows into the narrowest Flye-side structure needed
  for a future read-to-graph consumption gate.
- Preserve `graph_mutation_consumed_worker_output=false`.
- Prove mismatch, truncated output, or corrupted worker output fails closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No graph mutation from worker output.
- No whole-Flye speedup claim.
- No full raw-overlap non-key parity claim unless a separate validator proves
  it.
- No new CUDA kernel.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Keep all new modes explicit, opt-in, deterministic, and fail-closed.
- Do not feed rehydrated objects into graph mutation until a later Task Card
  adds and proves a separate consumption gate.

## Deliverables

- Flye patch implementing the guarded rehydration dry-run seam.
- ABI or design documentation for the rehydrated raw-overlap object boundary.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.
- Next Task Card based on whether rehydration remains low risk.

## Acceptance Gates

- [ ] Positive session-file proof validates row-key parity before rehydration.
- [ ] Rehydrated row count matches the validated worker row count.
- [ ] Graph mutation remains disabled and audited as not consumed.
- [ ] Mismatch, truncated output, or corruption proof fails closed before graph
      mutation.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
