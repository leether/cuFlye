# Task Card: cuFlye M8a Read-to-Graph Quick-Overlap Minimizer Target

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the performance target upstream from selected chain/divergence work to
read-to-graph quick-overlap/minimizer candidate discovery.

M7d showed the selected CPU chain/divergence boundary is too small to beat CPU:
`0.926453 ms` of selected CPU-control work versus `54.250612 ms` for hot CUDA
kernel plus graph-fill. Earlier M6a/M7d input-boundary timing shows
quick-overlap/minimizer work is orders of magnitude larger, so M8a should
define and prove the next CUDA target there.

## In Scope

- Add or reuse CPU-control profiling for read-to-graph quick-overlap/minimizer
  discovery at query and aggregate levels.
- Select a bounded set of queries where quick-overlap work dominates selected
  chain/divergence work.
- Define the next CUDA ABI boundary for minimizer/query-hit candidate discovery
  before chain-input filtering.
- Produce a CPU oracle and replayable fixture pack for that boundary.
- Add a DGX proof manifest that compares the candidate boundary timing against
  M7d and states the expected CUDA ROI.

## Out of Scope

- No default GPU mode.
- No graph mutation consumption in M8a.
- No claim that M8a itself accelerates Flye.
- No broad genome-scale benchmark without a bounded oracle and canonical gate.
- No silent CPU fallback in later CUDA paths.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep GPU-target ABI records deterministic or compare through a canonical
  sort/diff gate.
- Preserve canonical Flye artifacts for all profiling/source-pack modes.

## Deliverables

- Task-local design notes or ABI notes for the quick-overlap/minimizer target.
- CPU-control timing summary and selected query pack.
- DGX golden proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] CPU-control quick-overlap/minimizer timing is recorded for a bounded query
      set and full toy-hifi control run.
- [x] Selected M8a query set has materially larger CPU-control target time than
      the M7d selected chain/divergence boundary.
- [x] A replayable CPU oracle pack is emitted for the chosen boundary.
- [x] Canonical Flye artifacts match CPU golden when profiling/source-pack mode
      is enabled.
- [x] Summary states what CUDA kernel/prototype should be implemented next and
      what speedup threshold would justify graph-facing integration.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M8a.

Implemented `tools/plan_read_to_graph_quick_overlap_minimizer_target.py` and
ABI notes in
`docs/abi/read-to-graph-quick-overlap-minimizer-target-summary-v0.md`.

DGX proof:

```text
proof_root=/tmp/cuflye-m8a-proof-20260701T203000Z
golden=tests/golden/cuflye-m8a-read-to-graph-quick-overlap-minimizer-target-dgx-aarch64.json
source_input_boundary_sha256=674a6bc7ffb42a058859254ac78aa83b374c578a18d17a339bd2e6a669d6d628
source_queries=3577
source_raw_overlap_records=5092
source_chain_input_records=3814
source_total_quick_overlap_ms=3898.425897
control_matches_golden=true
selected_query_count=16
selected_query_ids=2145,2160,2146,2152,2161,2167,2148,2154,2157,2163,2165,2149,84,2150,5,361
selected_raw_overlap_records=27
selected_chain_input_records=18
selected_quick_overlap_ms=79.294112
selected_chain_plus_divergence_ms=3.481934
m7d_selected_chain_plus_divergence_ms=0.926453
selected_quick_overlap_vs_m7d_ratio=85.58892032299534
m6j_reference_warm_request_best_ms=52.199131
m6j_reference_hot_request_over_selected_quick_overlap=0.6582976930241681
oracle_pack_replay_status=match
oracle_chain_input_records=18
summary_checks=7/7
```

M8a does not prove CUDA speedup for the new query set. It proves the next target
is worth running: the selected Flye CPU quick-overlap budget is `79.294112 ms`,
so M8b must capture a full-query-hit source pack for the same query ids and
show whether the warm CUDA replay request can beat that exact baseline while
preserving row-key and chain-input oracle gates.
