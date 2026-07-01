# Task Card: cuFlye M7d Read-to-Graph Selected CPU-Skip Timing Expansion

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn M7c's correctness canary into an evidence-backed ROI decision by measuring
the selected CPU work that is actually skipped, the CUDA handoff cost, and the
graph-facing placeholder fill cost under larger selected sets.

M7c proves the selected CPU slice can be absent and supplied from CUDA output.
M7d should answer whether expanding that selected set is worth doing before
moving to a default GPU path.

## In Scope

- Add timing attribution around selected CPU-skip decisions in the Flye patch.
- Record per-query and aggregate skipped CPU chain/divergence timing when the
  M7c mode is disabled and equivalent selected queries run on CPU.
- Record M7c placeholder creation, CUDA rebuild, placeholder fill, and final
  parity timing.
- Expand the selected query set only when the shape remains supported by the
  existing CUDA full-query-hit worker and fail-closed gates.
- Produce a DGX manifest that compares skipped CPU time against CUDA worker and
  graph-facing substitution costs.
- Preserve canonical Flye artifacts and fail-closed negative proof.

## Out of Scope

- No default GPU mode.
- No broad read-to-graph replacement.
- No unsupported large-genome claim.
- No CUDA kernel rewrite beyond existing full-query-hit worker behavior unless
  timing proves it is the limiting factor.
- No silent CPU fallback after a selected CUDA failure.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep timing records deterministic enough for comparison, but exclude timing
  values from canonical correctness hashes.
- Fail closed on unsupported shapes or timing/proof accounting mismatches.

## Deliverables

- Flye patch or script updates for selected CPU-skip timing attribution.
- ABI/design notes for the timing expansion fields if new JSON fields are
  introduced.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M7c selected CPU-skip canary still passes unchanged.
- [x] Positive DGX proof records matched CPU-control timing for the same
      selected query set.
- [x] Positive DGX proof records selected CPU skipped time, CUDA worker time,
      rebuild time, placeholder fill time, and total canary time.
- [x] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [x] Negative proof fails closed before graph mutation commit.
- [x] Summary states clearly whether the selected expanded path has a measured
      CUDA-side advantage or remains blocked by handoff/worker overhead.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M7d.

Implemented Flye patch `0058` to add
`timing_ms.selected_cpu_skip_placeholder` to the M7c canary JSON, exposed
`--read-alignment-input-boundary-dump` in `scripts/run_flye_fixture.sh`, and
added `tools/summarize_read_to_graph_selected_cpu_skip_timing.py` for CPU
control versus CUDA-path ROI summaries.

DGX proof:

```text
proof_root=/tmp/cuflye-m7d-proof-20260701T190000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
control_matches_golden=true
positive_status=passed
positive_canary_checks=18/18
positive_vs_control_canonical_artifacts=match
positive_selected_cpu_skipped_queries=8
positive_cpu_slice_chains=0
positive_cpu_slice_records=0
positive_placeholder_forward_chains_filled=8
positive_placeholder_complement_chains_filled=8
positive_placeholder_insert_ms=0.001616
positive_graph_fill_total_ms=1.505974
cpu_control_selected_chain_plus_divergence_ms=0.926453
cuda_worker_request_total_ms=353.124639
cuda_cold_path_total_ms=354.630613
cuda_hot_kernel_plus_graph_ms=54.250612
cold_cuda_path_faster_than_selected_cpu_control=false
hot_kernel_plus_graph_faster_than_selected_cpu_control=false
negative_status=failed
negative_state=failed-closed
negative_proof_fault=drop-first-cpu-skip-canary-chain
negative_graph_mutation_consumed_worker_output=false
summary_checks=10/10
```

Result: M7d intentionally does not expand this boundary further. The same
selected query set has only `0.926453 ms` of CPU chain/divergence work to skip,
while even the hot kernel plus graph-fill path costs `54.250612 ms`. The next
ROI target should move upstream to quick-overlap/minimizer candidate discovery.
