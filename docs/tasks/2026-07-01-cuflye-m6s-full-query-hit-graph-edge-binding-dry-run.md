# Task Card: cuFlye M6s Full Query-Hit Graph Edge Binding Dry-Run

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M6r worker output, which now carries nonzero
`passes_chain_input_filter` and resolved `edge_id` values, to prove a
no-mutation Flye-side graph-edge binding audit before any real read-to-graph
graph mutation is allowed.

M6r removed the metadata propagation blocker, but the ledger still reports zero
graph-edge consumption candidates because no `GraphEdge*` object binding has
been attempted. M6s should answer the next narrow question: can every
chain-input-positive CUDA raw-overlap row be deterministically matched back to a
live Flye graph edge object without changing graph state?

## In Scope

- Add a no-mutation graph-edge binding audit mode after M6q shadow ledger
  passes.
- For rehydrated rows with `passes_chain_input_filter=1`, resolve `edge_id`
  against the live Flye graph edge collection.
- Record deterministic per-row/per-query binding counts:
  - chain-input-positive rows inspected;
  - rows with resolved nonzero `edge_id`;
  - rows whose `edge_id` maps to a live `GraphEdge*`;
  - rows rejected because the live graph edge is missing or ambiguous.
- Fail closed if any required row cannot bind cleanly.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No graph mutation from CUDA output.
- No replacement of Flye's CPU read-to-graph path.
- No default GPU mode.
- No whole-Flye speedup claim.
- No attempt to compute chain-input filtering or edge identity on GPU.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Keep all graph-edge pointer handling non-owning and audit-only.
- Every future-consumption row must remain behind row-key, rehydration, ledger,
  and graph-edge binding gates.

## Deliverables

- Flye patch implementing the opt-in graph-edge binding dry-run audit.
- ABI/design notes for the graph-edge binding audit JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p rehydration and M6q shadow ledger must pass before binding runs.
- [x] Positive DGX proof records nonzero chain-input-positive rows.
- [x] Positive DGX proof records nonzero live graph-edge bindings.
- [x] Binding audit proves graph mutation remains disabled and not consumed.
- [x] Negative proof fails closed before graph mutation when a binding row is
      intentionally corrupted or dropped.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in:

- `patches/flye/2.9.6/0047-cuflye-read-to-graph-full-query-hit-graph-edge-binding.patch`
- `docs/abi/read-to-graph-full-query-hit-graph-edge-binding-dry-run-v0.md`
- `tests/golden/cuflye-m6s-full-query-hit-graph-edge-binding-dry-run-dgx-aarch64.json`

Proof summary:

```text
proof_root=/tmp/cuflye-m6s-proof-20260701T120300Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_chain_input_filter_rows=8
positive_graph_edge_binding_rows=8
positive_graph_edge_binding_resolved_edge_id_rows=8
positive_graph_edge_binding_live_edge_rows=8
positive_graph_edge_binding_missing_edge_rows=0
positive_graph_mutation_consumed_worker_output=false
negative_status=graph-edge-binding-failed-before-graph-mutation
negative_rehydration_status=passed
negative_shadow_ledger_status=passed
negative_graph_edge_binding_status=failed
negative_proof_fault=drop-first-binding-row
negative_proof_fault_applied=true
negative_chain_input_filter_rows=8
negative_graph_edge_binding_rows=7
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Plain-language benefit:

```text
M6s still does not make full Flye faster and still does not mutate the graph.
It proves the next critical safety gate: the 8 chain-input-positive CUDA
full-query-hit rows can be resolved from row-key-validated TSV, through M6p
rehydration and M6q ledger, all the way back to live Flye GraphEdge objects.
The next useful step is a no-mutation object-vector consumption smoke: construct
the candidate graph-facing objects, account them, and still refuse to return
them to Flye's mutating graph path.
```
