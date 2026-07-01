# Task Card: cuFlye M6q Full Query-Hit Shadow Consumption Ledger

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Extend M6p from typed raw-overlap rehydration into an audited shadow
consumption ledger that records which rehydrated CUDA full-query-hit rows would
be eligible for a future read-to-graph consumption path, while still refusing
to mutate graph state.

## In Scope

- Require M6p row-key parity and raw-overlap rehydration to pass first.
- Add an explicit opt-in ledger mode, disabled by default.
- Record a deterministic per-row or per-query ledger with:
  - worker row count;
  - rehydrated row count;
  - chain-input filter count;
  - unresolved `edge_id=0` count;
  - rows eligible only for future raw-overlap/chain-input shadowing;
  - graph mutation consumed flag, always false.
- Preserve session-file worker support.
- Prove the ledger fails closed if M6p rehydration is absent, failed, or
  intentionally corrupted.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No graph mutation from CUDA output.
- No default GPU mode.
- No whole-Flye speedup claim.
- No `GraphEdge*` object-vector consumption.
- No claim that non-key raw-overlap fields are fully equivalent beyond fields
  explicitly checked in the ledger.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Use deterministic ordering and machine-checkable JSON.
- Treat `edge_id=0` as unresolved at this M6 boundary.

## Deliverables

- Flye patch implementing the opt-in shadow consumption ledger.
- ABI/design documentation for the ledger schema.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.
- Next Task Card based on whether the ledger exposes a safe first consumption
  candidate.

## Acceptance Gates

- [ ] Ledger mode requires M6p rehydration `status=passed`.
- [ ] Positive DGX proof records `36` worker rows and `36` rehydrated rows for
      the selected toy-hifi full-query-hit pack.
- [ ] Ledger records unresolved `edge_id=0` rows explicitly rather than
      pretending graph edge identity exists.
- [ ] Graph mutation remains disabled and audited as not consumed.
- [ ] Negative proof fails closed when rehydration is absent or corrupted.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
