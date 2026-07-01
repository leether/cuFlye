# Task Card: cuFlye M7a Full Query-Hit Selected Graph-Consumption Parity

Status: completed

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

- [x] M6z correctness and timing gates pass before graph-consumption parity is
      trusted.
- [x] Positive DGX proof records selected CUDA-supplied rows and CPU-owned
      residual rows reaching the graph-facing handoff.
- [x] Positive DGX proof preserves exact default CPU canonical artifacts on
      `toy-hifi`.
- [x] Positive DGX proof records the graph-consumption parity status and row
      counts in machine-readable JSON.
- [x] Negative proof fails closed when a selected CUDA-supplied row is missing,
      corrupted, duplicated, or leaked back into CPU-owned handling.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in Flye patch `0055` as an opt-in graph-facing parity gate after
M6z:

- `CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE=selected-graph-consumption-parity-v0`
- `CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_PROOF_FAULT=drop-first-graph-facing-row`

ABI/design notes:

- `docs/abi/read-to-graph-full-query-hit-selected-graph-consumption-parity-v0.md`

Golden proof:

- `tests/golden/cuflye-m7a-full-query-hit-selected-graph-consumption-parity-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m7a-proof-20260701T150000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_artifact_hashes_match_golden=true
positive_status=passed
positive_graph_consumption_parity_checks=13/13
positive_graph_facing_rows=36
positive_final_merged_ledger_rows=36
positive_graph_facing_cuda_supplied_rows=8
positive_graph_facing_cpu_owned_rows=28
positive_missing_graph_edge_rows=0
positive_dropped_graph_facing_rows=0
positive_consumed=false
positive_graph_mutation_consumed_worker_output=false
negative_status=selected-graph-consumption-parity-failed-before-graph-mutation
negative_proof_fault=drop-first-graph-facing-row
negative_proof_fault_applied=true
negative_graph_facing_rows=35
negative_failed_checks=dropped_graph_facing_rows_zero,graph_facing_cuda_rows_match_smoke,graph_facing_rows_match_final_merged_ledger
summary_checks=12/12
```

Allowed M7a claim:

```text
cuFlye can take the M6y/M6z final merged handoff and prove all 36 rows are
graph-facing live-edge rows on DGX: 8 CUDA-supplied selected rows and 28
CPU-owned residual rows, with zero missing graph edges and fail-closed behavior
when a graph-facing row is dropped.
```

Forbidden M7a claim:

```text
M7a does not prove whole-Flye speedup, default GPU mode, or real graph mutation.
It is still a not-consumed graph-facing parity gate.
```

Plain-language benefit:

```text
M7a proves the selected CUDA rows are no longer just TSV/ledger data: combined
with CPU-owned residual rows, they can all be mapped to live graph-facing rows.
This removes the edge-identity blocker that appeared during the first attempt,
but it still does not make Flye faster because the graph is not mutated yet.
```

Next highest-ROI task:

```text
M7b: attempt a guarded selected graph-consumption mutation canary on toy-hifi.
Only after M7a parity passes should a tiny opt-in path let the selected handoff
reach the actual graph mutation path and compare canonical artifacts against
the CPU golden.
```
