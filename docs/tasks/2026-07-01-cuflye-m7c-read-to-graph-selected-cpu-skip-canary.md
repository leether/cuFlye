# Task Card: cuFlye M7c Read-to-Graph Selected CPU-Skip Canary

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M7b's post-hoc selected graph-consumption mutation canary to the
first tiny selected CPU-skip canary in the read-to-graph path.

M7b proves CUDA full-query-hit output can be rebuilt into Flye `goodChains` and
substituted into the selected graph-facing slice without changing canonical
artifacts. M7c should prove the selected query CPU read-to-graph work can be
skipped before that slice exists, then supplied from the CUDA handoff under the
same parity and fail-closed gates.

## In Scope

- Add an opt-in selected CPU-skip canary after M7b.
- Restrict the canary to the bounded toy-hifi selected query set.
- Record selected query IDs, skipped CPU query count, skipped CPU row count, and
  CUDA-supplied replacement chain count.
- Rebuild selected graph-facing chains from CUDA worker output without relying
  on the selected CPU slice as the source of truth.
- Preserve CPU-owned residual query work and account it separately.
- Compare canonical Flye artifacts against the CPU golden.
- Record positive proof that selected CPU read-to-graph work is skipped and
  CUDA output supplies the selected chains.
- Record negative proof that missing/corrupted selected CUDA output fails closed
  before graph mutation commit.

## Out of Scope

- No default GPU mode.
- No full read-to-graph replacement.
- No broad benchmark claim beyond the selected query canary.
- No graph simplification or repeat-resolution algorithm changes.
- No hidden fallback that recomputes selected CPU work after a CUDA failure.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep the selected CPU-skip accounting explicit in JSON and fail closed on any
  mismatch.
- Preserve deterministic output ordering or add a canonical sort/diff gate.

## Deliverables

- Flye patch implementing the opt-in selected CPU-skip canary.
- ABI/design notes for the selected CPU-skip canary JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M7b mutation canary passes before selected CPU skip is allowed.
- [x] Positive DGX proof records nonzero selected CPU read-to-graph work skipped.
- [x] Positive DGX proof records CUDA-supplied selected chains consumed by the
      graph-facing slice.
- [x] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [x] Positive DGX proof records timing for skipped CPU work, CUDA handoff, and
      graph-facing substitution.
- [x] Negative proof fails closed before graph mutation commit when selected
      CUDA output is missing, corrupted, duplicated, or reordered.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M7c.

Implemented Flye patch `0057` and runner flags for
`selected-cpu-skip-canary-v0`. The bounded `toy-hifi` selected query set
`5,6,7,8,9,10,11,12` now skips the selected CPU `_readAlignments` slice,
inserts placeholders, rebuilds selected `goodChains` from CUDA worker output,
and fills 8 forward plus 8 complement placeholders.

DGX proof:

```text
proof_root=/tmp/cuflye-m7c-proof-20260701T180000Z
fixture=toy-hifi
baseline_matches_golden=true
positive_status=passed
positive_canary_checks=18/18
positive_selected_cpu_skipped_queries=8
positive_cpu_slice_chains=0
positive_cpu_slice_records=0
positive_worker_records=36
positive_chain_input_rows=8
positive_rebuilt_good_chains=8
positive_placeholder_forward_chains_filled=8
positive_placeholder_complement_chains_filled=8
positive_total_read_alignments_before=7092
positive_total_read_alignments_after=7092
positive_vs_baseline_canonical_artifacts=match
positive_canary_total_ms=1.58868
negative_status=failed
negative_state=failed-closed
negative_proof_fault=drop-first-cpu-skip-canary-chain
negative_rebuilt_good_chains=7
negative_placeholder_forward_chains_filled=0
negative_placeholder_complement_chains_filled=0
negative_graph_mutation_consumed_worker_output=false
summary_checks=20/20
```

Allowed claim: cuFlye can opt in to skip the selected read-to-graph CPU
chain/divergence slice for 8 toy-hifi full-query-hit queries, fill
graph-facing placeholders with CUDA-worker-derived `goodChains`, preserve
canonical Flye artifacts, and fail closed before graph mutation when selected
CUDA output is corrupted.

Forbidden claim: M7c does not prove default GPU mode, whole-Flye speedup, broad
read-to-graph replacement, or production support beyond the bounded toy-hifi
selected CPU-skip canary.
