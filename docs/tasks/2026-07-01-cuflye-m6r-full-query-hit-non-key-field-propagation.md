# Task Card: cuFlye M6r Full Query-Hit Non-Key Field Propagation

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move past M6q's zero-chain-input worker-output blocker by propagating
source-pack oracle-only raw-overlap metadata into CUDA full-query-hit worker
output after row-key replay succeeds.

M6q showed that selected query ids `5..12` already produce `36` CUDA worker
rows, but every worker row still had `passes_chain_input_filter=0` and
`edge_id=0`. A local source-pack scan shows the CPU oracle rows for those same
queries do contain chain-input-positive rows and resolved edge ids. Therefore
the next blocker is metadata propagation, not query selection.

## In Scope

- Add a deterministic selector/profiler that proves whether a source pack has
  nonzero `passes_chain_input_filter=1` rows.
- Extend the CUDA full-query-hit replay worker so host-side output writing
  backfills oracle-only raw-overlap metadata by row key:
  - `edge_id`;
  - `seq_divergence`;
  - `passes_chain_input_filter`.
- Keep CUDA kernel row-key generation unchanged.
- Fail closed if a CUDA output row lacks a matching oracle metadata row key.
- Run the existing session-file worker plus M6p/M6q gates.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No graph mutation from CUDA output.
- No claim that the GPU kernel computes chain-input filtering or edge identity.
- No `GraphEdge*` binding or object-vector consumption yet.
- No whole-Flye speedup claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep CUDA resource ownership in existing RAII wrappers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle calls.
- Keep host metadata propagation deterministic and row-key checked.
- Keep all GPU output behind row-key, rehydration, and ledger gates.

## Deliverables

- Source-pack selector/profiler tool.
- CUDA full-query-hit worker metadata propagation patch.
- DGX golden manifest proving nonzero worker-output chain-input rows.
- Updated ROADMAP, golden index, and this Task Card.
- Next Task Card based on whether graph-edge identity is sufficient for a
  no-mutation object binding dry-run.

## Acceptance Gates

- [x] Selector proves the selected source pack has nonzero
      `passes_chain_input_filter=1` oracle rows.
- [x] CUDA full-query-hit worker row-key diff still matches the CPU oracle.
- [x] Worker output now records nonzero `passes_chain_input_filter=1` rows.
- [x] Worker output now records resolved nonzero `edge_id` rows when the oracle
      has them.
- [x] M6p rehydration passes for the selected query set.
- [x] M6q shadow ledger passes and records nonzero
      `chain_input_filter_rows`.
- [x] Graph mutation remains disabled and audited as not consumed.
- [x] Negative proof fails closed before graph mutation.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in:

- `cuda/cuflye_cuda_full_query_hit_replay.cu`
- `tools/select_read_to_graph_chain_input_positive.py`
- `tests/golden/cuflye-m6r-full-query-hit-non-key-field-propagation-dgx-aarch64.json`

Proof summary:

```text
proof_root=/tmp/cuflye-m6r-proof-20260701T105200Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
source_selection_chain_input_rows=8
source_selection_raw_rows=36
positive_status=passed
positive_row_key_matched=true
positive_external_row_key_status=match
positive_rehydration_status=passed
positive_worker_records=36
positive_rehydrated_records=36
positive_shadow_ledger_status=passed
positive_shadow_ledger_rows=36
positive_chain_input_filter_rows=8
positive_unresolved_edge_id_zero_rows=0
positive_resolved_edge_id_rows=36
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
M6r still does not make full Flye faster, and it does not prove the GPU computes
edge identity or chain-input filtering. It does remove a real integration
blocker: the CUDA full-query-hit worker can now preserve the CPU oracle's
non-key raw-overlap metadata after row-key replay succeeds. The ledger now sees
8 chain-input-positive rows and 36 resolved edge-id rows, while graph mutation
remains disabled. That makes the next useful step a graph-edge object binding
dry-run instead of another metadata plumbing pass.
```
