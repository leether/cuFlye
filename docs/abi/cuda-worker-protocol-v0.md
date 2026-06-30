# cuFlye CUDA Worker Protocol v0

Status: draft for M3b

Introduced: M3a

Scope: control-plane protocol between the Flye candidate backend seam and a
long-lived external CUDA worker.

## Purpose

The worker protocol replaces the current one-shot external adapter shape with a
request/response contract that can keep CUDA context and reusable buffers warm
across candidate-generation requests.

The protocol is intentionally file-backed for M3b. This keeps the Flye patch
small and debuggable while the project proves warm-worker timing and candidate
equivalence.

## Request Schema

Schema name:

```text
cuflye-worker-request-v0
```

Minimum JSON request:

```json
{
  "schema": "cuflye-worker-request-v0",
  "request_id": "query-neg253-0001",
  "adapter_mode": "pack-dump-v0",
  "candidate_abi": "candidate-record-v1",
  "kmer_size": 17,
  "device": 0,
  "memory_budget_bytes": 4294967296,
  "reads_tsv": "/path/to/query/reads.tsv",
  "index_tsv": "/path/to/query/index.tsv",
  "repetitive_kmers_tsv": "/path/to/query/repetitive-kmers.tsv",
  "output_tsv": "/path/to/output/candidates.tsv",
  "response_json": "/path/to/output/response.json"
}
```

Required fields:

| Field | Meaning |
| --- | --- |
| `schema` | Must equal `cuflye-worker-request-v0`. |
| `request_id` | Caller-provided id echoed in the response. |
| `adapter_mode` | M3b supports `pack-dump-v0` only. |
| `candidate_abi` | Must equal `candidate-record-v1`. |
| `kmer_size` | Flye k-mer size used by the candidate boundary. |
| `device` | CUDA device id. |
| `reads_tsv` | Pack-dump reads TSV. |
| `index_tsv` | Pack-dump index TSV. |
| `repetitive_kmers_tsv` | Pack-dump repetitive k-mer TSV. |
| `output_tsv` | Candidate-record-v1 output path. |
| `response_json` | Worker response JSON path. |

Optional fields:

| Field | Meaning |
| --- | --- |
| `memory_budget_bytes` | Hard budget checked before CUDA allocation. |
| `query_id` | Optional expected query id for fail-closed validation. |
| `expected_read_count` | Optional expected read count. |
| `expected_index_entries` | Optional expected index entry count. |
| `backend_json` | Optional path for the underlying read-window backend JSON. |

## Response Schema

Schema name:

```text
cuflye-worker-response-v0
```

Successful response:

```json
{
  "schema": "cuflye-worker-response-v0",
  "request_id": "query-neg253-0001",
  "status": "ok",
  "request_ordinal": 2,
  "worker_cuda_context_warm": true,
  "worker_context_setup_ms": 298.595,
  "candidate_abi": "candidate-record-v1",
  "output_tsv": "/path/to/output/candidates.tsv",
  "records": 15571,
  "output_strategy": "sparse-offsets-v1",
  "dense_pair_output_materialized": false,
  "device": 0,
  "device_name": "NVIDIA GB10",
  "timing_ms": {
    "worker_uptime": 1000.0,
    "request_total": 425.54,
    "backend_total_before_json": 425.54,
    "cuda_setup": 0.0,
    "input_parse": 4.783,
    "device_allocation": 9.169,
    "host_to_device": 4.428,
    "kernel": 6.361,
    "host_prefix_sum": 83.331,
    "output_device_to_host": 0.094,
    "write_output": 0.676
  },
  "device_allocation_bytes": 260459496,
  "memory_budget_satisfied": true
}
```

Failure response:

```json
{
  "schema": "cuflye-worker-response-v0",
  "request_id": "query-neg253-0001",
  "status": "error",
  "error_code": "unsupported-shape",
  "error_message": "M3b supports pack-dump-v0 query requests only",
  "cuda_error_code": null,
  "cuda_error_name": null,
  "cuda_error_text": null
}
```

## Worker Modes

M3b proof mode:

```text
cuflye-cuda-worker --requests-jsonl /path/to/requests.jsonl
```

Each non-empty line is one `cuflye-worker-request-v0` object. The worker must
process requests sequentially in one process so M3b can measure first-request
versus warm-request timing.

M3b may also provide a debugging mode:

```text
cuflye-cuda-worker --request-json /path/to/request.json
```

The debugging mode is useful for development but does not prove warm-worker
reuse.

M3c worker mode:

```text
cuflye-cuda-worker --serve --request-dir /path/to/requests
```

This mode is reserved for a later Task Card. It should reuse the same request and
response schemas.

## Ordering and Determinism

Worker output must preserve candidate-record-v1 semantics:

- records are sorted by query id, query position, k-mer, target id, target
  position, and target strand;
- exact byte-for-byte output is preferred;
- if byte-for-byte output cannot be preserved, a canonical sort/diff gate must
  pass before Flye consumes the output.

M3b does not require the C++ worker to compute SHA-256. Proof runs should compute
canonical hashes with `tools/validate_candidate_dump.py` and compare outputs with
`tools/diff_candidate_dumps.py`.

## Failure Semantics

The worker must fail closed when:

- the request schema is unknown;
- `adapter_mode` is not `pack-dump-v0`;
- `candidate_abi` is not `candidate-record-v1`;
- required files are missing or unreadable;
- the input shape exceeds the declared memory budget;
- CUDA device selection, allocation, copy, kernel launch, or synchronization
  fails;
- candidate output fails validation;
- optional expected counts do not match.

There is no silent CPU fallback.

## C++/CUDA Ownership Rules

Reusable worker code must follow `docs/CODING_STYLE.md`:

- own CPU memory with standard containers or stack objects;
- own CUDA allocations, streams, and events with move-only RAII wrappers;
- report CUDA failures with numeric code, CUDA error name, and CUDA error text;
- check integer multiplication before allocation;
- keep raw pointers non-owning and local to clearly bounded calls.
