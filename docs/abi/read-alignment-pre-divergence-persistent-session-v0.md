# cuFlye Read Alignment Pre-Divergence Persistent Session v0

Status: accepted

Introduced: M5r

Scope: file-backed worker protocol for selected Flye read-alignment
pre-divergence batch dry-runs.

## Purpose

M5r lets Flye submit selected pre-divergence read-alignment replay batches to a
long-lived CUDA worker without starting a fresh worker process for each batch.
The worker keeps the CUDA context warm and may keep a persistent device arena
alive across requests with the same fixture list and shape contract.

This protocol is not a default GPU mode and does not let GPU output mutate the
Flye graph. It is an explicit dry-run seam for exactness and timing proof.

## Flye Environment

Flye enables this protocol only when all of the following are set:

```text
CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE=batch-dry-run-v0
CUFLYE_READ_ALIGNMENT_WORKER_LIFECYCLE_MODE=session-file-v0
CUFLYE_READ_ALIGNMENT_WORKER_SESSION_DIR=<session-dir>
```

Optional settings:

```text
CUFLYE_READ_ALIGNMENT_WORKER_DEVICE=0
CUFLYE_READ_ALIGNMENT_WORKER_WARMUP_RUNS=0
CUFLYE_READ_ALIGNMENT_WORKER_BENCHMARK_RUNS=1
CUFLYE_READ_ALIGNMENT_WORKER_MEMORY_BUDGET_BYTES=<bytes>
CUFLYE_READ_ALIGNMENT_WORKER_SESSION_POLL_MS=2
CUFLYE_READ_ALIGNMENT_WORKER_SESSION_TIMEOUT_MS=600000
```

In session mode Flye does not require `CUFLYE_READ_ALIGNMENT_WORKER_BIN`; the
worker must already be running.

## Worker Startup

The CUDA worker is started with:

```text
cuflye-cuda-read-alignment-chain-replay \
  --worker-session-dir <session-dir> \
  --worker-session-max-requests 2 \
  --worker-session-poll-ms 2 \
  --worker-session-timeout-ms 600000 \
  --device 0
```

The worker creates:

```text
<session-dir>/session-ready.json
<session-dir>/inbox/
<session-dir>/processing/
<session-dir>/done/
```

`session-ready.json` uses schema
`cuflye-read-alignment-worker-session-v0` and records session status, worker
PID, device id/name, CUDA context setup time, poll/timeout values, processed
request count, and whether a device arena is initialized.

## Request Submission

Flye writes a request JSON path to:

```text
<session-dir>/inbox/<request-id>.ready.pending
```

Then Flye atomically renames it to:

```text
<session-dir>/inbox/<request-id>.ready
```

The worker renames that file into `processing/`, reads the request JSON path,
executes the request, writes the normal response JSON, and finishes with:

```text
<session-dir>/done/<request-id>.ready.done
```

The done file starts with `status=ok\n` on success. Any missing file, timeout,
non-ok done status, response mismatch, unsupported request field, CUDA failure,
or session lifecycle error is fail-closed before graph mutation.

## Request JSON

Request schema:

```text
cuflye-read-alignment-worker-request-v0
```

Required flat JSON fields:

```text
request_id
adapter_mode=read-alignment-predivergence-batch-v0
read_alignment_abi=read-alignment-v1
output_mode=pre-divergence-chains
backend=cuda
cuda_execution_mode=persistent-arena-bulk-output
device
batch_fixtures_file
batch_output_dir
batch_json_output
response_json
allow_heterogeneous_batch=true
cuda_persistent_arena=true
cuda_persistent_bulk_output=true
emit_pre_divergence_chains=true
warmup_runs
benchmark_runs
expected_fixture_count
```

Optional field:

```text
memory_budget_bytes
```

Unsupported values are rejected. Silent CPU fallback is not allowed.

## Response JSON

Response schema:

```text
cuflye-read-alignment-worker-response-v0
```

Success response records:

- `request_ordinal`;
- `worker_cuda_context_warm`;
- `worker_context_setup_ms`;
- `worker_device_arena_cache_hit`;
- `worker_device_arena_created`;
- `worker_device_arena_capacity_bytes`;
- `fixture_count`, `output_records`;
- `batch_json_output`, `batch_output_dir`;
- `timing_ms.request_total`;
- `timing_ms.backend_mean_total_before_json`;
- `timing_ms.worker_overhead`;
- one-time arena setup/allocation/host-to-device timing.

Error responses use the same schema with `status=error` and include an
`error_message`.

## M5r Proof Shape

The Flye proof submits two requests to one session:

1. Warmup request: builds CUDA context-visible state and creates the persistent
   device arena.
2. Actual request: uses the same fixture list and must report
   `worker_device_arena_cache_hit=true`.

The positive proof must preserve exact canonical Flye artifacts versus a CPU
baseline. The negative proof must fail closed before graph mutation.
