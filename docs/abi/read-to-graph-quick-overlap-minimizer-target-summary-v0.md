# ABI: Read-to-Graph Quick-Overlap Minimizer Target Summary v0

Status: accepted in M8a

Created: 2026-07-01

## Purpose

`cuflye-m8a-read-to-graph-quick-overlap-minimizer-target-summary-v0`
selects a bounded read-to-graph query set where Flye CPU quick-overlap work is
large enough to justify the next CUDA candidate/minimizer milestone.

M8a is a target-selection and oracle-pack milestone. It does not feed CUDA
output into Flye graph logic.

## Inputs

`tools/plan_read_to_graph_quick_overlap_minimizer_target.py` consumes:

- a `read-to-graph-input-boundary-v0` dump;
- the accepted M7d proof manifest;
- optionally the accepted M6j warm-session CUDA proof manifest;
- optional M6b replay-pack output directory.

The tool validates the input-boundary dump, ranks supported query groups by
`quick_overlap_wall_ms`, and can emit a M6b replay pack for the selected query
ids.

## Selection Contract

Supported selected queries must satisfy the M6b replay-pack constraints:

- `raw_overlap_count > 0`;
- `chain_input_count > 0`;
- raw-overlap and chain-input counts are within the configured limits;
- selected chain-input rows have unique `read_begin` values.

The default ranking is:

```text
quick_overlap_wall_ms desc, query_id asc
```

## Output

The summary JSON records:

| Field | Meaning |
| --- | --- |
| `source` | Validated full input-boundary dump summary and canonical hash. |
| `selection_policy` | Query ranking and supported-shape limits. |
| `selected.query_ids` | Bounded M8a target query ids. |
| `selected.timing_ms.quick_overlap_wall_ms` | CPU-control quick-overlap time for the selected query set. |
| `selected.timing_ms.cpu_chain_plus_divergence_wall_ms` | Later chain/divergence work for the same selected query set. |
| `selected.quick_overlap_vs_m7d_selected_chain_divergence_ratio` | How much larger the M8a target is than the M7d rejected boundary. |
| `selected.m6j_hot_request_over_selected_quick_overlap_ratio` | Existing M6j hot request time divided by the selected Flye quick-overlap baseline, when an M6j proof is provided. |
| `unsupported_shape` | Excluded query counts and reasons. |
| `oracle_pack` | Optional M6b replay-pack manifest for the selected query set. |
| `cuda_target_contract` | The next CUDA input, output, correctness gate, and speed gate. |
| `checks` | Machine-readable M8a acceptance checks. |

## CUDA Follow-On Gate

The M8b CUDA follow-on must use the same selected query ids and compare against
the selected Flye CPU `quick_overlap_wall_ms` baseline. The minimum speed gate
is:

```text
hot CUDA worker request time < selected Flye quick_overlap_wall_ms
```

The preferred gate is at least `1.25x` speedup while preserving row-key parity,
chain-input replay parity, canonical Flye artifacts in capture mode, and
fail-closed unsupported-shape handling.

## Non-Claims

M8a does not prove default GPU mode, Flye graph consumption, whole-Flye
speedup, or CUDA speedup for the newly selected query set. It only selects the
next high-ROI CUDA target and emits a replayable CPU oracle pack for that
boundary.
