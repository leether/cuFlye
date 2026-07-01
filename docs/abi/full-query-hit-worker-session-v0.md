# Full Query-Hit Worker Session v0

Status: active

Introduced: M6n

Scope: file-backed session lifecycle for the CUDA full-query-hit worker used by
the Flye read-to-graph dry-run seam.

## Purpose

`session-file-v0` lets separate Flye seam invocations attach to one already
running CUDA full-query-hit worker process. The worker keeps its CUDA context,
parsed source pack, and device buffers alive across compatible requests. Flye
still validates worker output by CPU oracle row key and stops before graph
mutation.

This protocol replaces the M6m JSONL proof shape for cross-process reuse. It
does not make CUDA the default path and does not feed CUDA output into Flye
graph logic.

## Worker Startup

```text
cuflye-cuda-full-query-hit-replay \
  --worker-session-dir SESSION_DIR \
  --worker-session-max-requests N \
  --worker-session-poll-ms 2 \
  --worker-session-timeout-ms 600000 \
  --device 0
```

The worker creates:

```text
SESSION_DIR/session-ready.json
SESSION_DIR/inbox/
SESSION_DIR/processing/
SESSION_DIR/done/
```

`session-ready.json` uses schema
`cuflye-full-query-hit-worker-session-v0` and records the device, worker pid,
poll interval, timeout, processed request count, and whether a replay session
has been initialized.

## Flye Environment

Flye enables this lifecycle with:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_LIFECYCLE_MODE=session-file-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_DIR=SESSION_DIR
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR=/path/to/worker-audit
```

Optional:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_POLL_MS=2
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_SESSION_TIMEOUT_MS=600000
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE=0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES=<bytes>
```

`session-file-v0` does not require
`CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN` because Flye attaches to an
already running worker session.

## Submit File

Flye writes the normal
`cuflye-full-query-hit-worker-request-v0` JSON to:

```text
WORKER_OUTPUT_DIR/full-query-hit-worker-request.json
```

Then it atomically submits a ready file:

```text
SESSION_DIR/inbox/REQUEST_ID.ready
```

The ready file body is the request JSON path. Flye also writes an audit sidecar:

```text
WORKER_OUTPUT_DIR/full-query-hit-worker-session-submit.txt
```

with:

```text
schema=cuflye-full-query-hit-worker-session-submit-v0
request_id=REQUEST_ID
request_json=/path/to/full-query-hit-worker-request.json
ready_file=SESSION_DIR/inbox/REQUEST_ID.ready
done_file=SESSION_DIR/done/REQUEST_ID.ready.done
```

Request ids are deterministic, sanitized file stems derived from the worker
output root. They include multiple trailing path components so two output roots
named `worker` under different parents do not collide.

## Worker Processing

The worker polls `SESSION_DIR/inbox` for `*.ready`, moves each file into
`SESSION_DIR/processing`, reads the request JSON path from the file body, runs
the request, and writes the normal response JSON requested by Flye.

For a successful request it writes:

```text
SESSION_DIR/done/REQUEST_ID.ready.done
```

with:

```text
status=ok
response_json=/path/to/full-query-hit-worker-response.json
```

For a failed request it writes the same done file with:

```text
status=error
response_json=/path/to/full-query-hit-worker-response.json
```

and writes `session-error.json` before exiting non-zero.

After `--worker-session-max-requests` successful requests, the worker writes
`session-complete.json` and exits zero.

## Compatibility

The first valid request initializes the worker replay session. A later request
is warm only when these fields match the initialized session:

- `source_pack_dir`
- `device`
- `kernel_mode`
- memory-budget compatibility

Compatible warm requests report:

```json
{
  "worker_cuda_context_warm": true,
  "timing_ms": {
    "parse": 0.0,
    "device_allocation": 0.0,
    "host_to_device": 0.0
  }
}
```

Unsupported shapes fail closed. The accepted M6n negative proof uses
`memory_budget_bytes=1`, produces response status `error`, and leaves
`graph_mutation_consumed_worker_output=false`.

## Flye Audit

Flye writes:

```text
WORKER_OUTPUT_DIR/full-query-hit-worker-dry-run.json
```

Positive session-file proof records:

```json
{
  "worker_lifecycle_mode": "session-file-v0",
  "worker_session_dir": ".../session",
  "worker_session_submit_path": ".../full-query-hit-worker-session-submit.txt",
  "worker_session_done_path": ".../done/REQUEST_ID.ready.done",
  "actual_worker_cuda_context_warm": true,
  "actual_request_timing_ms": {
    "request_total": 52.7358,
    "parse": 0,
    "device_allocation": 0,
    "host_to_device": 0
  },
  "row_key_matched": true,
  "graph_mutation_consumed_worker_output": false
}
```

The row-key contract is unchanged from M6l/M6m:

```text
query_id, read_id, read_begin, read_end, read_len,
edge_seq_id, edge_begin, edge_end, edge_len, score
```

## Non-Goals

M6n does not:

- mutate Flye graph state with CUDA output;
- claim whole-Flye speedup;
- prove full non-key raw-overlap field parity;
- provide daemon lifecycle management beyond a bounded worker process;
- make CUDA the default Flye path.
