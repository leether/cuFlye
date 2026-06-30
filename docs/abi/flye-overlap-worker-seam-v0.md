# Flye Overlap Worker Seam v0

Status: draft for M4j

Introduced: M4j

Scope: Flye-side proof seam that generates and invokes a cuFlye packed overlap
worker request after replay fixtures have been captured, then stops before graph
mutation.

## Purpose

M4j is the first Flye-side boundary for the M4i overlap worker. It does not let
GPU output feed downstream graph logic. Instead, Flye captures CPU overlap replay
fixtures, writes a worker request for those fixtures, optionally invokes the
M4i worker binary, records the response, and throws a controlled stop.

The seam exists so later milestones can integrate worker output behind the same
request/response and validation gates without changing default CPU behavior.

## Environment Selector

The seam is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_WORKER_MODE=packed-replay-v0
```

Required environment when enabled:

| Variable | Meaning |
| --- | --- |
| `CUFLYE_OVERLAP_REPLAY_DUMP_DIR` | Root where Flye writes replay fixture directories. |
| `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES` | Number of replay fixtures to collect before invoking the worker. |
| `CUFLYE_OVERLAP_WORKER_BIN` | Path to `cuflye-cuda-overlap-chain-replay`. |
| `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR` | Directory for request, response, batch JSON, logs, and worker outputs. |

Optional environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CUFLYE_OVERLAP_WORKER_DEVICE` | `CUFLYE_CUDA_DEVICE` or `0` | CUDA device id passed to the worker request. |
| `CUFLYE_OVERLAP_WORKER_KERNEL_MODE` | `serial` | Worker `cuda_kernel_mode`. |
| `CUFLYE_OVERLAP_WORKER_WARMUP_RUNS` | `0` | Worker warmup runs. |
| `CUFLYE_OVERLAP_WORKER_BENCHMARK_RUNS` | `1` | Worker timed runs. |
| `CUFLYE_OVERLAP_WORKER_MEMORY_BUDGET_BYTES` | unset | Optional worker memory budget. |

## Generated Files

Given `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR=/path/to/seam`, Flye writes:

| File | Meaning |
| --- | --- |
| `worker-fixtures.txt` | Absolute or run-relative replay fixture directories. |
| `worker-request.json` | `cuflye-overlap-worker-request-v0` request. |
| `worker-response.json` | `cuflye-overlap-worker-response-v0` response. |
| `worker-batch.json` | Underlying packed batch runner JSON. |
| `worker-stdout.log` | Worker stdout. |
| `worker-stderr.log` | Worker stderr. |
| `seam-summary.json` | Flye-side seam metadata and stop proof. |
| `worker-output/` | Per-fixture worker overlap TSV output directories. |

The generated request uses:

```json
{
  "schema": "cuflye-overlap-worker-request-v0",
  "adapter_mode": "overlap-replay-batch-v0",
  "overlap_abi": "overlap-range-v1",
  "backend": "cuda",
  "batch_execution": "packed"
}
```

## Stop Boundary

After the worker exits successfully and the response file is readable, Flye
writes `seam-summary.json` and throws an exception containing:

```text
cuFlye overlap worker seam stopped before graph mutation
```

This stop is intentional. It proves request generation and worker round-trip
without allowing GPU overlap output to change Flye graph construction.

## Failure Semantics

The seam fails closed when:

- the mode is unknown;
- required environment variables are missing;
- fixture count has not reached `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`;
- the worker binary exits non-zero;
- the worker response file is missing or unreadable.

There is no silent CPU fallback when the seam is explicitly enabled.
