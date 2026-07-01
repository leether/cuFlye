# Flye Full Query-Hit Worker Dry-Run Seam v0

Status: active

M6l connects the M6k `cuflye-full-query-hit-worker-request-v0` protocol to a
real Flye read-to-graph run. M6m extends that seam with an optional JSONL
lifecycle mode. M6n adds `session-file-v0`, a file-backed worker session that
separate Flye seam invocations can attach to. It is intentionally a dry-run
seam: Flye generates the selected source pack, calls the CUDA worker, validates
raw-overlap row-key parity, writes audit metadata, and stops before graph
mutation.

## Environment

Required:

```text
CUFLYE_READ_TO_GRAPH_SOURCE_PACK_DIR=/path/to/source-pack-root
CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS=5,6,7,8,9,10,11,12
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN=/path/to/cuflye-cuda-full-query-hit-replay
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR=/path/to/worker-audit
```

Optional:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE=0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_KERNEL_MODE=parallel-score
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR=/path/to/session
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_POLL_MS=2
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_TIMEOUT_MS=600000
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES=<bytes>
```

`parallel-score` is the only supported kernel mode. The mode requires
`--threads 1` because the selected source-pack oracle must be deterministic.
The lifecycle mode is empty by default; supported non-empty lifecycle modes are
`jsonl-persistent-v0` and `session-file-v0`. In `session-file-v0`, Flye attaches
to an already-running worker and does not require
`CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN`.

## Worker Request

Flye writes:

```text
$CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR/full-query-hit-worker-request.json
```

The request uses:

```text
schema=cuflye-full-query-hit-worker-request-v0
adapter_mode=full-query-hit-replay-v0
raw_overlap_abi=cuflye-read-to-graph-raw-overlap-v0
kernel_mode=parallel-score
```

The worker output is:

```text
full-query-hit-worker.raw-overlaps.tsv
```

## JSONL Lifecycle

When `CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE` is
`jsonl-persistent-v0`, Flye writes a two-line JSONL request file:

```text
full-query-hit-worker-requests.jsonl
```

The first request is a warmup request:

```text
request_id=read-to-graph-full-query-hit-warmup
output_tsv=full-query-hit-worker-warmup.raw-overlaps.tsv
response_json=full-query-hit-worker-warmup-response.json
```

The second request is the actual request that Flye validates:

```text
request_id=read-to-graph-full-query-hit-actual
output_tsv=full-query-hit-worker.raw-overlaps.tsv
response_json=full-query-hit-worker-response.json
```

The positive M6m gate requires:

```text
warmup status=ok
actual status=ok
actual worker_cuda_context_warm=true
actual row-key diff=match
```

Only the actual request output is eligible for row-key validation. The warmup
output is proof metadata only and is not eligible for graph consumption.

## Audit

Flye writes:

```text
full-query-hit-worker-dry-run.json
```

The positive path records:

```json
{
  "schema": "cuflye-read-to-graph-full-query-hit-worker-dry-run-v0",
  "status": "passed",
  "decision": "stopped-before-graph-mutation",
  "worker_lifecycle_mode": "jsonl-persistent-v0",
  "worker_requests_jsonl": ".../full-query-hit-worker-requests.jsonl",
  "worker_warmup_response_ok": true,
  "actual_worker_cuda_context_warm": true,
  "worker_context_setup_ms": 312.078,
  "actual_request_timing_ms": {
    "request_total": 52.2432,
    "kernel": 52.179,
    "parse": 0,
    "device_allocation": 0,
    "host_to_device": 0
  },
  "graph_facing_validation_timing_ms": {
    "row_key_diff": 0.028,
    "raw_overlap_rehydration": 0.113,
    "raw_overlap_shadow_ledger": 0.057,
    "raw_overlap_graph_edge_binding": 0.053,
    "raw_overlap_object_vector_smoke": 0.062,
    "graph_facing_validation_total": 0.313,
    "no_mutation_seam_total": 66.499
  },
  "row_key_matched": true,
  "worker_output_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

The negative path records:

```json
{
  "status": "failed-before-graph-mutation",
  "decision": "fail-closed-before-graph-mutation",
  "worker_output_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false,
  "failed_closed": true
}
```

## Row-Key Gate

M6l uses the same row-key contract as
`tools/diff_read_to_graph_raw_overlap_row_keys.py`:

```text
query_id, read_id, read_begin, read_end, read_len,
edge_seq_id, edge_begin, edge_end, edge_len, score
```

`source_order`, `raw_overlap_count`, `chain_input_count`, `edge_id`,
`seq_divergence`, and `passes_chain_input_filter` are not part of this M6l
correctness claim.

M6m keeps the same row-key claim. It adds timing attribution for the actual
warm request but does not expand correctness beyond the row key.

M6n keeps the same row-key claim for `session-file-v0`. It adds session attach
metadata and proves that a second separate Flye seam request can reuse the same
worker process with `worker_cuda_context_warm=true`.

M8d adds `graph_facing_validation_timing_ms` when raw-overlap rehydration or
shadow-ledger modes are enabled. The fields separate row-key diff,
rehydration, shadow-ledger accounting, their validation total, and the
no-mutation seam total used for bounded M8 performance claims.

M8e extends the same timing object with `raw_overlap_graph_edge_binding` and
`raw_overlap_object_vector_smoke`. These fields measure the next graph-facing
gates separately from worker wall time, row-key diff, rehydration, and
shadow-ledger accounting.

## Non-Goals

M6l/M6m/M6n do not:

- mutate Flye graph state with CUDA output;
- make CUDA the default path;
- claim whole-Flye acceleration;
- prove full raw-overlap field parity beyond the row key.
