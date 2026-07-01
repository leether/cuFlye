# Task Card: cuFlye M6q Full Query-Hit Shadow Consumption Ledger

Status: completed

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

- [x] Ledger mode requires M6p rehydration `status=passed`.
- [x] Positive DGX proof records `36` worker rows and `36` rehydrated rows for
      the selected toy-hifi full-query-hit pack.
- [x] Ledger records unresolved `edge_id=0` rows explicitly rather than
      pretending graph edge identity exists.
- [x] Graph mutation remains disabled and audited as not consumed.
- [x] Negative proof fails closed when the ledger is intentionally corrupted
      after M6p rehydration passes.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in:

- `patches/flye/2.9.6/0046-cuflye-read-to-graph-full-query-hit-shadow-ledger.patch`
- `docs/abi/read-to-graph-full-query-hit-shadow-consumption-ledger-v0.md`
- `tests/golden/cuflye-m6q-full-query-hit-shadow-consumption-ledger-dgx-aarch64.json`

Proof summary:

```text
proof_root=/tmp/cuflye-m6q-proof-20260701T095436Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_worker_records=36
positive_rehydrated_records=36
positive_shadow_ledger_rows=36
positive_chain_input_filter_rows=0
positive_unresolved_edge_id_zero_rows=36
positive_resolved_edge_id_rows=0
positive_graph_edge_consumption_candidate_rows=0
positive_graph_mutation_consumed_worker_output=false
negative_status=shadow-ledger-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=failed
negative_proof_fault=drop-first-ledger-row
negative_proof_fault_applied=true
negative_rehydrated_records=36
negative_shadow_ledger_rows=35
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Plain-language benefit:

```text
M6q still does not speed up full Flye. It turns the M6p rehydrated CUDA output
into a decision ledger: all 36 selected worker rows are safe to account as
future raw-overlap shadow rows, but none pass the chain-input filter and none
have resolved graph-edge identity. That makes the next blocker concrete instead
of vague: the next useful step is not to mutate the graph yet, but to define a
chain-input or edge-identity gate.
```
