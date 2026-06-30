# cuFlye CUDA Overlap Worker Protocol v0

Status: draft for M4i

Introduced: M4i

Scope: control-plane protocol for running the M4h packed overlap-chain replay
boundary through a governed external CUDA worker.

## Purpose

The overlap worker protocol moves the M4h packed replay executable toward a
Flye-callable boundary while keeping graph mutation out of scope. The worker is
file-backed and proof-oriented: requests name replay fixture lists and output
locations, and responses report validation metadata, worker timing, and
fail-closed errors.

M4i uses an overlap-specific protocol instead of extending the M3
candidate-worker protocol because the ABI, output files, failure modes, and
proof gates are different:

- M3 worker requests produce `candidate-record-v1`.
- M4i worker requests produce per-fixture `overlap-range-v1` TSV files.
- M4i requests must preserve per-query overlap provenance and oracle-diff gates
  before any downstream Flye graph logic can consume the output.

The worker still follows the M3 file-backed JSON/JSONL pattern so the integration
model remains familiar and debuggable.

## Request Schema

Schema name:

```text
cuflye-overlap-worker-request-v0
```

Minimum supported JSON request:

```json
{
  "schema": "cuflye-overlap-worker-request-v0",
  "request_id": "top9-packed-0001",
  "adapter_mode": "overlap-replay-batch-v0",
  "overlap_abi": "overlap-range-v1",
  "backend": "cuda",
  "batch_execution": "packed",
  "cuda_kernel_mode": "serial",
  "device": 0,
  "batch_fixtures_file": "/path/to/top9-fixtures.txt",
  "batch_output_dir": "/path/to/output/top9-packed-0001",
  "batch_json_output": "/path/to/output/top9-packed-0001.batch.json",
  "response_json": "/path/to/output/top9-packed-0001.response.json"
}
```

Required fields:

| Field | Meaning |
| --- | --- |
| `schema` | Must equal `cuflye-overlap-worker-request-v0`. |
| `request_id` | Caller-provided id echoed in the response. |
| `adapter_mode` | M4i supports `overlap-replay-batch-v0` only. |
| `overlap_abi` | Must equal `overlap-range-v1`. |
| `backend` | M4i worker supports `cuda` only. |
| `batch_execution` | M4i worker supports `packed` only. |
| `cuda_kernel_mode` | `serial` or `parallel-reduce`. |
| `device` | CUDA device id. |
| `batch_fixtures_file` | Text file listing replay fixture directories. |
| `batch_output_dir` | Directory for per-fixture overlap TSV output. |
| `batch_json_output` | Path for the underlying batch runner JSON. |
| `response_json` | Worker response JSON path. |

Optional fields:

| Field | Meaning |
| --- | --- |
| `memory_budget_bytes` | Hard budget checked before CUDA allocation. |
| `warmup_runs` | Warmup runs inside the packed batch request. Default `0`. |
| `benchmark_runs` | Timed runs inside the packed batch request. Default `1`. |
| `expected_fixture_count` | Optional expected number of replay fixtures. |

## Response Schema

Schema name:

```text
cuflye-overlap-worker-response-v0
```

Successful response:

```json
{
  "schema": "cuflye-overlap-worker-response-v0",
  "request_id": "top9-packed-0001",
  "status": "ok",
  "request_ordinal": 2,
  "worker_cuda_context_warm": true,
  "worker_context_setup_ms": 260.0,
  "worker_device_arena_enabled": true,
  "worker_device_arena_allocations": 0,
  "worker_device_arena_reuses": 7,
  "worker_device_arena_capacity_bytes": 3217966,
  "adapter_mode": "overlap-replay-batch-v0",
  "overlap_abi": "overlap-range-v1",
  "batch_execution": "packed",
  "cuda_kernel_mode": "serial",
  "fixture_count": 9,
  "output_records": 382,
  "kernel_launches_per_timed_run": 1,
  "batch_json_output": "/path/to/output/top9-packed-0001.batch.json",
  "batch_output_dir": "/path/to/output/top9-packed-0001",
  "timing_ms": {
    "worker_uptime": 1000.0,
    "request_total": 10.0,
    "backend_total_before_write": 6.9,
    "worker_overhead": 3.1,
    "parse": 0.5,
    "write_output": 0.5,
    "kernel": 6.8
  }
}
```

Failure response:

```json
{
  "schema": "cuflye-overlap-worker-response-v0",
  "request_id": "top9-packed-unsupported",
  "status": "error",
  "request_ordinal": 1,
  "error_code": "request-failed",
  "error_message": "unsupported overlap worker batch_execution",
  "cuda_error_code": null,
  "cuda_error_name": null,
  "cuda_error_text": null
}
```

## Worker Modes

Single-request debug mode:

```text
cuflye-cuda-overlap-chain-replay --worker-request-json /path/to/request.json
```

Proof mode:

```text
cuflye-cuda-overlap-chain-replay --worker-requests-jsonl /path/to/requests.jsonl
```

Each non-empty JSONL line is one `cuflye-overlap-worker-request-v0` object. M4i
requires at least two requests in JSONL proof mode so the proof can distinguish
first-request and warm-worker timing.

## Ordering and Determinism

Worker output must preserve `overlap-range-v1` semantics:

- per-fixture overlap TSV files use the same fields as `overlap-range-v1`;
- per-query provenance is carried by the fixture list and response JSON;
- canonical sorting and diff gates must pass before any downstream Flye graph
  logic can consume the output.

M4i does not require the C++ worker to compute SHA-256. Proof runs compute hashes
with `tools/validate_overlap_dump.py` and compare outputs with
`tools/diff_overlap_dumps.py`.

## Failure Semantics

The worker must fail closed when:

- the request schema is unknown;
- `adapter_mode` is not `overlap-replay-batch-v0`;
- `overlap_abi` is not `overlap-range-v1`;
- `backend` is not `cuda`;
- `batch_execution` is not `packed`;
- required files or output paths are missing;
- an optional expected fixture count does not match;
- the input shape exceeds the declared memory budget;
- CUDA device selection, allocation, copy, kernel launch, or synchronization
  fails.

There is no silent CPU fallback.

## C++/CUDA Ownership Rules

Worker code must follow `docs/CODING_STYLE.md`:

- own CPU memory with standard containers or stack objects;
- own CUDA allocations, streams, and events with move-only RAII wrappers;
- report CUDA failures with numeric code, CUDA error name, and CUDA error text;
- check integer multiplication before allocation;
- keep raw pointers non-owning and local to clearly bounded calls.
