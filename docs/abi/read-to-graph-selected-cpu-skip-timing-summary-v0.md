# ABI: Read-to-Graph Selected CPU-Skip Timing Summary v0

Status: accepted in M7d

Created: 2026-07-01

## Purpose

`cuflye-m7d-read-to-graph-selected-cpu-skip-timing-summary-v0` compares the
M7c selected CPU-skip canary against a CPU-control run for the same selected
query ids.

The goal is not to prove speedup. The goal is to decide whether this boundary
is worth expanding before moving toward a default GPU mode.

## Inputs

The summary tool consumes:

- a CPU-control `read-to-graph-input-boundary-v0` dump;
- the M7c/M7d positive mutation canary JSON;
- the positive full-query-hit worker dry-run JSON;
- the positive worker response JSON;
- the selected query id list.

The CPU-control run must use the same Flye build and selected query ids, with
M7c CPU-skip disabled.

## Output

`tools/summarize_read_to_graph_selected_cpu_skip_timing.py` writes:

```text
cuflye-m7d-read-to-graph-selected-cpu-skip-timing-summary-v0
```

The M7d proof manifest embeds this summary under `timing_summary`.

## Fields

| Field | Meaning |
| --- | --- |
| `cpu_control.cpu_chain_dp_wall_ms` | CPU-control chain DP time for selected query summaries. |
| `cpu_control.cpu_divergence_filter_wall_ms` | CPU-control divergence-filter time for selected query summaries. |
| `cpu_control.cpu_chain_plus_divergence_wall_ms` | Selected CPU work that M7c can skip at this boundary. |
| `cuda_path.placeholder_insert_wall_ms` | M7d placeholder insertion time from `timing_ms.selected_cpu_skip_placeholder`. |
| `cuda_path.canary_rebuild_wall_ms` | Time to rebuild selected `goodChains` from worker rows. |
| `cuda_path.canary_compare_wall_ms` | Time to compare selected canary records. |
| `cuda_path.canary_substitution_wall_ms` | Time to fill graph-facing placeholders and verify records. |
| `cuda_path.graph_fill_total_ms` | Placeholder, rebuild, compare, and substitution total. |
| `cuda_path.worker_request_total_ms` | Full worker request time, including cold process/context overhead when present. |
| `cuda_path.worker_kernel_ms` | CUDA kernel time reported by the worker response. |
| `cuda_path.cold_cuda_path_total_ms` | Worker request total plus graph-fill total. |
| `cuda_path.hot_kernel_plus_graph_ms` | CUDA kernel time plus graph-fill total. |
| `roi.cold_cuda_path_faster_than_selected_cpu_control` | True only if cold CUDA path is faster than selected CPU-control chain/divergence. |
| `roi.hot_kernel_plus_graph_faster_than_selected_cpu_control` | True only if kernel plus graph-fill path is faster than selected CPU-control chain/divergence. |
| `checks` | Machine-readable consistency checks. |

## M7d DGX Result

The accepted M7d proof measured the M7c selected query ids
`5,6,7,8,9,10,11,12`:

```text
cpu_control_selected_chain_plus_divergence_ms=0.926453
cuda_graph_fill_total_ms=1.505974
cuda_worker_request_total_ms=353.124639
cuda_cold_path_total_ms=354.630613
cuda_hot_kernel_plus_graph_ms=54.250612
cold_cuda_path_faster_than_selected_cpu_control=false
hot_kernel_plus_graph_faster_than_selected_cpu_control=false
```

## Non-Claims

This ABI does not prove a GPU speedup. It proves that the selected
read-to-graph chain/divergence boundary is too small in the toy-hifi proof to
beat CPU, and that subsequent ROI should target heavier upstream work.
