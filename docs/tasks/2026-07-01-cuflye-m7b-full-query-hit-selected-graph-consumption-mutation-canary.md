# Task Card: cuFlye M7b Full Query-Hit Selected Graph-Consumption Mutation Canary

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M7a's not-consumed graph-facing parity gate to the first tiny,
guarded selected graph-consumption mutation canary.

M7a proves the final merged handoff can be represented as live graph-facing
rows. M7b should allow that selected handoff to reach the actual graph mutation
path only on a bounded opt-in toy fixture, then prove canonical Flye artifacts
match the CPU golden.

## In Scope

- Add an opt-in selected graph-consumption mutation canary after M7a passes.
- Restrict the canary to the bounded selected query set and explicit proof
  fixture.
- Preserve CPU-owned residual rows and selected CUDA-supplied rows as separate
  audit ledgers.
- Compare canonical Flye artifacts against the CPU golden.
- Record positive proof that graph mutation can consume the selected handoff
  without changing canonical artifacts.
- Record negative proof that fails closed before committing graph mutation when
  the selected handoff is corrupted.

## Out of Scope

- No default GPU mode.
- No broad full-query-hit replacement.
- No whole-Flye speedup claim unless artifact parity and timing both pass.
- No graph simplification or repeat-resolution algorithm changes.
- No hidden fallback.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep mutation canary state explicit in JSON and fail closed on any mismatch.

## Deliverables

- Flye patch implementing the opt-in mutation canary.
- ABI/design notes for the mutation canary JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M7a graph-facing parity passes before mutation canary is allowed.
- [x] Positive DGX proof reaches the selected graph mutation path with the
      merged CUDA-supplied plus CPU-owned handoff.
- [x] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [x] Positive DGX proof records timing for canary handoff and graph mutation.
- [x] Negative proof fails closed before graph mutation commit when selected
      handoff rows are corrupted, missing, duplicated, or reordered.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by Flye patch:

- `patches/flye/2.9.6/0056-cuflye-read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary.patch`

Design and proof:

- `docs/abi/read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-v0.md`
- `tests/golden/cuflye-m7b-full-query-hit-selected-graph-consumption-mutation-canary-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m7b-proof-20260701T170000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
baseline_matches_golden=true
positive_status=passed
positive_checks=16/16
positive_consumed=true
positive_graph_mutation_consumed_worker_output=true
positive_worker_records=36
positive_chain_input_rows=8
positive_rebuilt_good_chains=8
positive_substituted_forward_chains=8
positive_substituted_complement_chains=8
positive_read_alignments_before=7092
positive_read_alignments_after=7092
positive_vs_baseline_canonical_artifacts=match
positive_canary_total_ms=1.6067
negative_status=failed
negative_state=failed-closed
negative_proof_fault=drop-first-canary-chain
negative_proof_fault_applied=true
negative_rebuilt_good_chains=7
negative_cpu_slice_chains=8
negative_read_alignments_before=7092
negative_read_alignments_after=7092
negative_substituted_forward_chains=0
negative_substituted_complement_chains=0
negative_graph_mutation_consumed_worker_output=false
summary_checks=15/15
```

Allowed M7b claim:

```text
cuFlye can rebuild the selected full-query-hit CUDA handoff into Flye
goodChains, substitute 8 selected forward chains plus 8 complement chains into
the graph-facing read-alignment slice, and preserve canonical Flye artifacts on
DGX.
```

Forbidden M7b claim:

```text
M7b does not prove whole-Flye speedup or default GPU mode. The selected CPU
slice still exists before the canary compares against it, so this is a guarded
consumption proof, not real selected CPU work elimination.
```

Next highest-ROI task:

```text
M7c: turn the M7b post-hoc selected substitution into a selected CPU-skip
canary. The selected query CPU read-to-graph work must be skipped before the
graph-facing slice is rebuilt from CUDA output, with canonical artifact parity
and fail-closed negative proof.
```
