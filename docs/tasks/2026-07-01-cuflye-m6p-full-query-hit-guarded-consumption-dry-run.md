# Task Card: cuFlye M6p Full Query-Hit Guarded Consumption Dry-Run

Status: complete

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

- [x] Positive session-file proof validates row-key parity before rehydration.
- [x] Rehydrated row count matches the validated worker row count.
- [x] Graph mutation remains disabled and audited as not consumed.
- [x] Mismatch, truncated output, or corruption proof fails closed before graph
      mutation.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in
`patches/flye/2.9.6/0045-cuflye-read-to-graph-full-query-hit-rehydration-dry-run.patch`
with runner support in `scripts/run_flye_fixture.sh`.

ABI/design doc:

- `docs/abi/read-to-graph-full-query-hit-raw-overlap-rehydration-dry-run-v0.md`

DGX proof manifest:

- `tests/golden/cuflye-m6p-full-query-hit-guarded-consumption-dry-run-dgx-aarch64.json`

Proof summary:

```text
proof_root=/tmp/cuflye-m6p-proof-20260701T093152Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_row_key_matched=true
positive_rehydration_status=passed
positive_worker_records=36
positive_parsed_records=36
positive_rehydrated_records=36
positive_typed_row_key_status=match
positive_graph_mutation_consumed_worker_output=false
negative_status=rehydration-failed-before-graph-mutation
negative_row_key_matched=true
negative_rehydration_status=failed
negative_proof_fault=drop-first-rehydrated-record
negative_proof_fault_applied=true
negative_worker_records=36
negative_rehydrated_records=35
negative_typed_row_key_status=mismatch
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Plain-language benefit:

```text
M6p does not speed up full Flye yet. It proves that CUDA full-query-hit worker
output can pass one more real Flye-side boundary: after session-file worker
row-key parity, Flye can parse the worker raw-overlap rows into checked
OverlapRange-shaped records and canonicalize them back to the same row keys.
The negative proof shows this new boundary fails closed after row-key parity
has already passed, and graph mutation still receives nothing.
```

Follow-up:

```text
M6q should add a shadow consumption ledger for these rehydrated raw-overlap
records, still without mutating graph state, so the next step can reason about
which downstream read-to-graph path would be eligible for guarded consumption.
```
