# ABI: Read-to-Graph Full Query-Hit Selected CPU-Skip Canary v0

Status: accepted in M7c

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-cpu-skip-canary-v0` is an
opt-in canary layered after the M7b selected graph-consumption mutation canary.

M7b still lets Flye compute the selected CPU `_readAlignments` slice, then
replaces that slice after comparing CUDA-derived `goodChains` against it. M7c
changes that one bounded path: for the selected toy-hifi full-query-hit query
set, Flye skips the selected CPU chain/divergence push into `_readAlignments`,
inserts audited placeholders, and later fills those placeholders with rebuilt
CUDA-worker-derived `goodChains`.

## Activation

Enable the M6y/M6z selected bypass gates, M7a parity, and M7b mutation canary,
then add:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_MODE=selected-cpu-skip-canary-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_SKIP_CANARY_PROOF_FAULT=drop-first-cpu-skip-canary-chain
```

The mode is rejected unless
`CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE=selected-graph-consumption-mutation-canary-v0`
is also enabled.

## Output

M7c extends the M7b canary JSON rather than creating a second graph-mutation
file:

```text
full-query-hit-worker-selected-graph-consumption-mutation-canary.json
```

The positive worker dry-run audit must end with:

```json
{
  "raw_overlap_selected_graph_consumption_mutation_canary_status": "passed",
  "raw_overlap_selected_graph_consumption_mutation_canary_state": "consumed",
  "raw_overlap_selected_graph_consumption_mutation_canary_decision": "selected-cpu-skip-canary-substituted",
  "graph_mutation_consumed_worker_output": true
}
```

## Added Fields

M7c keeps the M7b fields and adds or specializes these fields:

| Field | Meaning |
| --- | --- |
| `selected_cpu_skip_canary_mode` | Requested M7c mode string. |
| `selected_cpu_skip_canary_proof_fault` | Empty or `drop-first-cpu-skip-canary-chain`. |
| `selected_cpu_skip_canary_enabled` | Whether the selected CPU-skip canary was active. |
| `selected_cpu_skip_canary_consumed` | True only when placeholders were filled from rebuilt CUDA-derived chains. |
| `selected_cpu_skip_canary_failed_closed` | True when M7c rejects the handoff before graph mutation commit. |
| `selected_cpu_skipped_queries` | Number of selected queries whose CPU read-to-graph chain/divergence push was skipped. |
| `selected_cpu_skip_cpu_slice_absent` | True only when no selected CPU `_readAlignments` slice exists before CUDA fill. |
| `selected_cpu_skip_rebuilt_chains_matched` | Whether rebuilt CUDA `goodChains` match the selected chain-input rows. |
| `residual_alignment_records_preserved` | Whether CPU-owned non-selected alignment records remain present after placeholder fill. |
| `cpu_slice_chains` | Must be `0` in M7c positive proof. |
| `cpu_slice_records` | Must be `0` in M7c positive proof. |
| `placeholder_forward_chains_filled` | Number of selected forward placeholders filled from rebuilt CUDA output. |
| `placeholder_complement_chains_filled` | Number of selected complement placeholders filled from rebuilt CUDA output. |
| `timing_ms.selected_cpu_skip_placeholder` | M7d timing for selected placeholder insertion and accounting. |

## Invariants

- M7c cannot run unless M7b selected graph-consumption mutation canary mode is
  enabled.
- The source-pack selected query set must be explicit and bounded.
- For every selected query, Flye may dump source-pack input data but must not
  push selected CPU `goodChains` into `_readAlignments`.
- The canary must observe `cpu_slice_chains=0` and `cpu_slice_records=0` before
  it can consume CUDA output.
- Rebuilt CUDA-derived selected `goodChains` must match the selected chain-input
  accounting.
- Exactly one forward and one complement placeholder must be filled for every
  selected toy-hifi query in this bounded canary.
- CPU-owned residual `_readAlignments` records must be preserved.
- Canonical Flye artifacts must match the CPU baseline.
- Negative proof with `drop-first-cpu-skip-canary-chain` must fail closed before
  graph mutation commit and must not fill placeholders.

## M7c DGX Proof Shape

The accepted M7c proof used `toy-hifi` selected query ids
`5,6,7,8,9,10,11,12` on DGX/GB10:

```text
selected_cpu_skipped_queries=8
cpu_slice_chains=0
cpu_slice_records=0
rebuilt_good_chains=8
placeholder_forward_chains_filled=8
placeholder_complement_chains_filled=8
timing_ms.selected_cpu_skip_placeholder=0.001616
positive_vs_baseline_canonical_artifacts=match
negative_proof_fault=drop-first-cpu-skip-canary-chain
negative_rebuilt_good_chains=7
negative_graph_mutation_consumed_worker_output=false
```

## Non-Claims

This ABI does not prove default GPU mode, whole-Flye speedup, broad
read-to-graph replacement, or production support beyond the bounded selected
toy-hifi canary. It proves that one selected CPU read-to-graph slice can be
skipped, supplied from CUDA-worker-derived `goodChains`, and guarded by
canonical artifact parity plus fail-closed negative proof.
