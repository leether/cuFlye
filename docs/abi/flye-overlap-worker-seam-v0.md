# Flye Overlap Worker Seam v0

Status: accepted in M4j; batch allowlist extension accepted in M4k; validation
gate accepted in M4l; shadow consumption proof accepted in M4m; graph
consumption guard dry-run accepted in M4o; typed rehydration dry-run accepted
in M4p; `OverlapRange` object rehydration dry-run accepted in M4q; verified
overlap-vector substitution smoke accepted in M4r; substitution session ledger
accepted in M4s; substitution timing attribution accepted in M4t; substitution
session batch cache accepted in M4u; persistent JSONL worker lifecycle accepted
in M4v; true file-backed persistent worker session accepted in M4w

Introduced: M4j

Scope: Flye-side proof seam that generates and invokes a cuFlye packed overlap
worker request after replay fixtures have been captured, then stops before graph
mutation.

## Purpose

M4j is the first Flye-side boundary for the M4i overlap worker. M4k extends that
boundary from one selected query to an explicit query-id allowlist. The seam does
not let GPU output feed downstream graph logic. Instead, Flye captures CPU
overlap replay fixtures, writes a worker request for those fixtures, optionally
invokes the M4i worker binary, records the response, and throws a controlled
stop.

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
| `CUFLYE_OVERLAP_WORKER_BIN` | Path to `cuflye-cuda-overlap-chain-replay`. Required for single-request and `jsonl-persistent-v0`; not used by `session-file-v0` because the worker is already running. |
| `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR` | Directory for request, response, batch JSON, logs, and worker outputs. |

Optional environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CUFLYE_OVERLAP_REPLAY_QUERY_ID` | unset | Capture only one signed Flye query id. Mutually exclusive with `CUFLYE_OVERLAP_REPLAY_QUERY_IDS`. |
| `CUFLYE_OVERLAP_REPLAY_QUERY_IDS` | unset | Comma-separated signed Flye query-id allowlist for batch seam proof. When worker mode is enabled, `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES` must equal the number of allowlisted ids. |
| `CUFLYE_OVERLAP_WORKER_DEVICE` | `CUFLYE_CUDA_DEVICE` or `0` | CUDA device id passed to the worker request. |
| `CUFLYE_OVERLAP_WORKER_KERNEL_MODE` | `serial` | Worker `cuda_kernel_mode`. |
| `CUFLYE_OVERLAP_WORKER_WARMUP_RUNS` | `0` | Worker warmup runs. |
| `CUFLYE_OVERLAP_WORKER_BENCHMARK_RUNS` | `1` | Worker timed runs. |
| `CUFLYE_OVERLAP_WORKER_MEMORY_BUDGET_BYTES` | unset | Optional worker memory budget. |
| `CUFLYE_OVERLAP_WORKER_VALIDATION_MODE` | `oracle-diff-v0` | Validate every worker output as `overlap-range-v1` and canonical-diff it against the captured CPU oracle before marking worker output consumption-eligible. |
| `CUFLYE_OVERLAP_WORKER_SHADOW_MODE` | unset | Optional M4m proof mode. `canonical-overlap-v0` parses worker output into Flye-side canonical overlap records and compares them against CPU overlap ranges captured in memory. |
| `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE` | unset | Optional M4v/M4w/M4x proof mode. `jsonl-persistent-v0` invokes the overlap worker once with a two-request JSONL lifecycle: a cold warmup request followed by the actual warm request. `session-file-v0` submits the actual request to an already-running file-backed worker session without a duplicate warmup request. Persistent modes require `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0` or `gpu-first-supported-v0`; GPU-first mode specifically requires `session-file-v0`. |
| `CUFLYE_OVERLAP_WORKER_SESSION_DIR` | unset | Required when `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`. Directory containing the worker session `session-ready.json`, `inbox/`, and `done/` files. |
| `CUFLYE_OVERLAP_WORKER_SESSION_POLL_MS` | `2` | Poll interval while waiting for session ready/done files. |
| `CUFLYE_OVERLAP_WORKER_SESSION_TIMEOUT_MS` | `600000` | Timeout for session ready/done waits. |
| `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE` | unset | Optional M4o proof mode. `dry-run-v0` evaluates graph-consumption preconditions and writes guard metadata without consuming worker output. |
| `CUFLYE_OVERLAP_REHYDRATION_MODE` | unset | Optional M4p proof mode. `typed-overlap-v0` rehydrates validated worker records into a typed Flye-side overlap vector after the M4o guard passes. |
| `CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT` | unset | Optional M4p negative-proof fault. `drop-first-worker-record` forces typed-vector mismatch after validation, shadow, and guard success. |
| `CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE` | unset | Optional M4q proof mode. `overlap-range-object-v0` converts typed records into actual Flye `OverlapRange` objects after M4p passes. |
| `CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT` | unset | Optional M4q negative-proof fault. `drop-first-overlap-range` forces object-vector mismatch after M4p success. |
| `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE` | unset | Optional M4r/M4s/M4u/M4x/M4y mode. `verified-overlap-range-v0` returns the verified worker-derived `OverlapRange` vector for one selected query after M4q passes. `verified-overlap-range-session-v0` records a per-query session ledger and evaluates each allowlisted supported query separately. `verified-overlap-range-session-batch-v0` verifies one allowlisted supported batch, reuses that batch output for later selected queries through a run-local cache, and is required by the M4v/M4w persistent lifecycle proof. `gpu-first-supported-v0` reuses a verified session batch cache before live CPU overlap for later selected supported queries. |
| `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE` | `full-v0` | Optional M4y ledger volume control. `full-v0` preserves existing selected and non-selected session ledger rows. `selected-only-v0` suppresses non-selected skip rows while preserving selected, cached, and fail-closed rows. |
| `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE` | unset | Optional M4x/M4y audit mode. `oracle-file-v0` compares GPU-first object vectors against the captured CPU `oracle.overlaps.tsv` from the verified fixture before accepting GPU-first substitution. |
| `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS` | unset | Optional M4y comma-separated signed query-id sample for GPU-first audit. When unset and audit mode is enabled, every GPU-first substitution is audited. When set, only listed GPU-first queries pay the oracle comparison. Requires `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE`. |
| `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT` | unset | Optional M4r/M4s/M4x negative-proof fault. `drop-first-substitution-overlap` forces substitution mismatch after M4q success. `force-unsupported-selected-shape` forces the selected query through the unsupported-shape fail-closed gate before worker invocation. `drop-first-gpu-first-overlap` forces a GPU-first audit mismatch after the verified session batch cache exists. |

## Generated Files

Given `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR=/path/to/seam`, Flye writes:

| File | Meaning |
| --- | --- |
| `worker-fixtures.txt` | Absolute or run-relative replay fixture directories. |
| `worker-query-ids.txt` | Captured signed query ids, one per replay fixture. |
| `worker-request.json` | `cuflye-overlap-worker-request-v0` request. |
| `worker-response.json` | `cuflye-overlap-worker-response-v0` response. |
| `worker-requests.jsonl` | M4v two-request persistent lifecycle input when `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0`. |
| `worker-request-warmup.json` | M4v cold warmup request, using the same fixture/query batch but separate warmup outputs. |
| `worker-response-warmup.json` | M4v cold warmup response. |
| `worker-session-submit.path` | M4w file-backed session submit proof when `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`; records the actual request path plus session ready/done file paths. |
| `worker-batch.json` | Underlying packed batch runner JSON. |
| `worker-batch-warmup.json` | M4v warmup batch runner JSON. |
| `worker-validation.json` | Flye-side ABI validation and CPU-oracle canonical diff summary for every worker output. |
| `worker-shadow.json` | Flye-side shadow parse and comparison summary when `CUFLYE_OVERLAP_WORKER_SHADOW_MODE=canonical-overlap-v0`. |
| `worker-graph-consumption-guard.json` | Dry-run graph-consumption guard summary when `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0`. |
| `worker-rehydration.json` | Typed overlap-vector rehydration dry-run summary when `CUFLYE_OVERLAP_REHYDRATION_MODE=typed-overlap-v0`. |
| `worker-object-rehydration.json` | Flye `OverlapRange` object-vector rehydration dry-run summary when `CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE=overlap-range-object-v0`. |
| `worker-vector-substitution.json` | Verified graph-facing overlap-vector substitution summary when `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE` selects a verified substitution mode, including M4x GPU-first. |
| `worker-vector-substitution.consumed` | Durable M4r one-shot sentinel written after a verified worker-derived overlap vector is returned; later Flye subprocesses skip worker invocation when this file exists. |
| `worker-vector-substitution-ledger.jsonl` | M4s/M4u/M4x/M4y session ledger. In default `full-v0` ledger mode it records selected, skipped, cached, GPU-first, or failed-closed substitution decisions. In `selected-only-v0` it suppresses non-selected skip rows but still records selected, cached, GPU-first, and fail-closed rows. |
| `worker-vector-substitution.query_<id>.consumed` | Durable M4s per-query sentinel written after a selected supported query returns a verified worker-derived overlap vector. |
| `worker-stdout.log` | Worker stdout. |
| `worker-stderr.log` | Worker stderr. |
| `seam-summary.json` | Flye-side seam metadata and stop proof. |
| `worker-output/` | Per-fixture worker overlap TSV output directories. |
| `worker-output-warmup/` | Per-fixture warmup overlap TSV output directories for M4v persistent lifecycle proof. |

The generated request uses:

```json
{
  "schema": "cuflye-overlap-worker-request-v0",
  "adapter_mode": "overlap-replay-batch-v0",
  "overlap_abi": "overlap-range-v1",
  "backend": "cuda",
  "batch_execution": "packed",
  "captured_query_ids_file": "/path/to/seam/worker-query-ids.txt",
  "replay_query_ids": "381,-71,649"
}
```

`replay_query_ids` is an optional audit string. It is emitted only when
`CUFLYE_OVERLAP_REPLAY_QUERY_IDS` is set; the worker ignores it and uses the
fixture list as the execution source of truth.

## Stop Boundary

After the worker exits successfully and the response file is readable, Flye
validates every worker output against the captured CPU oracle. When validation
passes, Flye writes `worker-validation.json`, writes `seam-summary.json`, and
throws an exception containing:

```text
cuFlye overlap worker seam stopped before graph mutation
```

This stop is intentional. It proves request generation and worker round-trip
without allowing GPU overlap output to change Flye graph construction.

M4l adds a separate consumption eligibility flag. A passing validation writes:

```json
{
  "validation_status": "passed",
  "worker_output_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

This means the worker output passed the current proof gate. It still does not
mean Flye graph logic consumed GPU output.

M4m adds optional shadow consumption proof mode. When
`CUFLYE_OVERLAP_WORKER_SHADOW_MODE=canonical-overlap-v0`, Flye preserves the CPU
overlap ranges for each captured query in memory, parses the validated worker
TSV output into the same canonical overlap representation, compares the two, and
writes:

```json
{
  "shadow_status": "passed",
  "shadow_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

This proves the worker output can cross one more in-memory boundary in shadow
mode. It still does not feed GPU output into graph mutation.

M4o adds optional graph-consumption guard dry-run mode. When
`CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0`, Flye evaluates whether the
validated and shadow-matched worker output would satisfy the minimum
preconditions for a future graph-consumption path, writes
`worker-graph-consumption-guard.json`, and still stops before graph mutation.
The successful dry-run state is:

```json
{
  "graph_guard_status": "passed",
  "graph_guard_eligibility": "eligible",
  "graph_consumption_state": "not-consumed",
  "graph_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

This proves the future consumption contract can be audited. It still does not
feed GPU output into graph mutation.

M4p adds optional typed rehydration dry-run mode. When
`CUFLYE_OVERLAP_REHYDRATION_MODE=typed-overlap-v0`, Flye requires the M4o guard
to be eligible, converts validated worker `overlap-range-v1` rows into a
Flye-side typed overlap vector, compares that vector against the CPU overlap
records captured in memory, writes `worker-rehydration.json`, and still stops
before graph mutation. The successful dry-run state is:

```json
{
  "overlap_rehydration_status": "passed",
  "overlap_rehydration_state": "not-consumed",
  "overlap_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

This proves a representation boundary after the guard. It still does not feed
GPU output into graph mutation.

M4q adds optional `OverlapRange` object rehydration dry-run mode. When
`CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE=overlap-range-object-v0`, Flye requires
M4p typed rehydration to pass, converts typed records into actual upstream Flye
`OverlapRange` objects, compares the object vector against CPU overlap records
captured in memory, writes `worker-object-rehydration.json`, and still stops
before graph mutation. The successful dry-run state is:

```json
{
  "overlap_object_rehydration_status": "passed",
  "overlap_object_rehydration_state": "not-consumed",
  "overlap_object_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

This proves one more representation boundary. It still does not feed GPU output
into graph mutation.

M4r adds optional verified overlap-vector substitution smoke mode. When
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-v0`, Flye
requires M4q object rehydration to pass, reloads the selected current query's
worker output as `OverlapRange` objects, verifies exact CPU equivalence again,
and returns that worker-derived object vector from the selected
`getSeqOverlaps` call. M4r is one-shot inside a Flye process: after the
selected substitution is accepted, later overlap calls do not re-invoke the
worker. The successful smoke state is:

```json
{
  "overlap_vector_substitution_status": "passed",
  "overlap_vector_substitution_state": "consumed",
  "overlap_vector_substitution_selected_source": "worker-overlap-range-object-vector",
  "graph_facing_returned_worker_output": true,
  "graph_mutation_consumed_worker_output": true
}
```

This is a graph-facing smoke substitution. It is still opt-in and CPU-verified;
it is not a production GPU mode or a speed claim.

M4s/M4u extend substitution into session-batch mode. When
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0`,
Flye waits until all allowlisted supported fixtures are captured, sends them as
one worker batch, validates and rehydrates that batch once, and keeps the
verified batch output in a run-local cache. Later selected supported queries can
reuse the verified batch output without starting another worker process.

M4v adds optional persistent worker lifecycle proof mode. When
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0` is set with session
batch substitution, Flye writes `worker-request-warmup.json` and
`worker-request.json`, combines them into `worker-requests.jsonl`, and invokes
the worker once with `--worker-requests-jsonl`. The warmup request writes only
to `worker-output-warmup/`; the actual request writes to `worker-output/` and
continues through the existing validation, shadow, graph guard, rehydration,
object rehydration, and exact substitution gates.

M4w adds a true Flye-visible persistent worker session. When
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0` is set with session batch
substitution, Flye waits for
`$CUFLYE_OVERLAP_WORKER_SESSION_DIR/session-ready.json`, writes only the actual
`worker-request.json`, submits that request path through
`$CUFLYE_OVERLAP_WORKER_SESSION_DIR/inbox/<request_id>.ready`, and waits for
`$CUFLYE_OVERLAP_WORKER_SESSION_DIR/done/<request_id>.ready.done`.
`worker-request-warmup.json`, `worker-response-warmup.json`, and
`worker-requests.jsonl` are not generated in this lifecycle. Worker startup and
CUDA context setup are recorded by the session worker, while Flye's
`worker_process_ms` measures only submit/wait time for the actual request.

M4x adds a bounded GPU-first substitution mode. When
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=gpu-first-supported-v0` is set with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`, Flye first builds the
same verified session batch cache as M4w. Later allowlisted supported query
calls that are already present in that cache may return the cached
worker-derived `OverlapRange` vector before computing live CPU overlaps. This
path appends `gpu-first-from-session-batch-cache` to
`worker-vector-substitution-ledger.jsonl` and writes
`seam-summary.json` with
`gpu-first-substitution-consumed-before-live-cpu-overlap`.

GPU-first mode is still opt-in, allowlisted, and shape-bounded. If
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0` is set, Flye compares the
GPU-first object vector against the captured CPU `oracle.overlaps.tsv` for that
fixture before accepting it. M4y adds
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS`; when this sample is set, only listed
GPU-first query ids pay the oracle comparison and any proof fault is applied
only inside that audit sample. Without audit mode, the GPU-first path relies on
the existing session batch cache having already passed validation, shadow,
guard, typed rehydration, and object rehydration.

M4y also adds `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE=selected-only-v0`
for sparse performance proofs. It suppresses `skipped-not-selected` and
`skipped-unsupported-non-selected-shape` rows, but it does not suppress
selected, cached, GPU-first, or fail-closed rows. The default remains
`full-v0`.

## Failure Semantics

The seam fails closed when:

- the mode is unknown;
- required environment variables are missing;
- both `CUFLYE_OVERLAP_REPLAY_QUERY_ID` and
  `CUFLYE_OVERLAP_REPLAY_QUERY_IDS` are set;
- an allowlist contains an empty, duplicate, or non-integer query id;
- worker allowlist mode sets `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES` to a value
  different from the allowlist length;
- fixture count has not reached `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`;
- the worker binary exits non-zero;
- the worker response file is missing or unreadable.
- `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE` is unsupported;
- persistent lifecycle mode is selected outside
  `verified-overlap-range-session-batch-v0` or `gpu-first-supported-v0`;
- `gpu-first-supported-v0` is selected without
  `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`;
- persistent lifecycle mode is selected and the warmup response file is missing
  or unreadable;
- `session-file-v0` is selected and `CUFLYE_OVERLAP_WORKER_SESSION_DIR` is
  missing;
- `session-file-v0` times out waiting for session ready or done files;
- `session-file-v0` receives a non-ok done file or a missing/unreadable actual
  worker response;
- `CUFLYE_OVERLAP_WORKER_VALIDATION_MODE` is unsupported;
- any worker output is missing, malformed, empty, not `overlap-range-v1`, or
  canonical-diffs `mismatch` against its captured `oracle.overlaps.tsv`.
- `CUFLYE_OVERLAP_WORKER_SHADOW_MODE` is unsupported;
- shadow mode is selected and the parsed worker records differ from the
  in-memory CPU overlap records for any captured query.
- `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE` is unsupported;
- graph-consumption dry-run mode is selected and a required guard precondition
  fails, including missing shadow mode or failed shadow comparison.
- `CUFLYE_OVERLAP_REHYDRATION_MODE` is unsupported;
- `CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT` is unsupported;
- typed rehydration dry-run mode is selected before the M4o guard is eligible;
- typed rehydration cannot represent a worker record in Flye-side types;
- a rehydrated typed vector differs from CPU overlap records captured in
  memory.
- `CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE` is unsupported;
- `CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT` is unsupported;
- object rehydration dry-run mode is selected before M4p typed rehydration is
  eligible;
- an `OverlapRange` object vector differs from CPU overlap records captured in
  memory.
- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE` is unsupported;
- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE` is unsupported;
- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT` is unsupported;
- `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE` is unsupported;
- `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS` is set without
  `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE`;
- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`
  is set without GPU-first audit mode;
- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE=selected-only-v0` is selected
  outside a session substitution mode;
- vector substitution smoke mode is selected before M4q object rehydration is
  eligible;
- the current CPU `OverlapRange` vector carries `kmerMatches` payload that the
  worker object vector cannot represent in M4r;
- the selected worker `OverlapRange` vector differs from the current CPU
  overlap vector.
- GPU-first audit mode is selected and the cached worker object vector differs
  from the captured CPU `oracle.overlaps.tsv`.

There is no silent CPU fallback when the seam is explicitly enabled.

On validation failure Flye writes `worker-validation.json`, writes
`seam-summary.json` with:

```json
{
  "status": "validation-failed-before-graph-mutation",
  "validation_status": "failed",
  "worker_output_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before graph mutation.

On guard precondition failure after validation passes, Flye writes
`worker-graph-consumption-guard.json`, writes `seam-summary.json` with:

```json
{
  "status": "guard-failed-before-graph-mutation",
  "validation_status": "passed",
  "graph_guard_status": "failed",
  "graph_consumption_state": "failed-closed",
  "graph_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before graph mutation.

On rehydration mismatch after validation, shadow comparison, and the M4o guard
pass, Flye writes `worker-rehydration.json`, writes `seam-summary.json` with:

```json
{
  "status": "rehydration-failed-before-graph-mutation",
  "validation_status": "passed",
  "shadow_status": "passed",
  "graph_guard_status": "passed",
  "overlap_rehydration_status": "failed",
  "overlap_rehydration_state": "failed-closed",
  "overlap_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before graph mutation.

On object rehydration mismatch after M4p typed rehydration passes, Flye writes
`worker-object-rehydration.json`, writes `seam-summary.json` with:

```json
{
  "status": "object-rehydration-failed-before-graph-mutation",
  "validation_status": "passed",
  "shadow_status": "passed",
  "graph_guard_status": "passed",
  "overlap_rehydration_status": "passed",
  "overlap_object_rehydration_status": "failed",
  "overlap_object_rehydration_state": "failed-closed",
  "overlap_object_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before graph mutation.

On verified vector substitution mismatch after M4q object rehydration passes,
Flye writes `worker-vector-substitution.json`, writes `seam-summary.json` with:

```json
{
  "status": "substitution-failed-before-graph-mutation",
  "validation_status": "passed",
  "shadow_status": "passed",
  "graph_guard_status": "passed",
  "overlap_rehydration_status": "passed",
  "overlap_object_rehydration_status": "passed",
  "overlap_vector_substitution_status": "failed",
  "overlap_vector_substitution_state": "failed-closed",
  "overlap_vector_substitution_consumed": false,
  "graph_facing_returned_worker_output": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before returning worker output to the graph-facing
overlap path.

On verified vector substitution success, Flye returns the worker-derived
`OverlapRange` vector for the selected query, writes
`worker-vector-substitution.consumed`, and marks the run-local substitution as
consumed. Later overlap calls from the same process or a later Flye subprocess
skip worker invocation when this sentinel exists, preserving M4r as a one-shot
smoke instead of accidentally broadening the supported shape contract.

In default M4s session mode, Flye appends every substitution decision to
`worker-vector-substitution-ledger.jsonl`. Selected supported queries are sent to
the worker one at a time and, after exact CPU equivalence checks, write a
per-query sentinel such as `worker-vector-substitution.query_353.consumed`.
Later calls for the same query append `skipped-already-substituted` to the
ledger. Non-selected unsupported shapes append
`skipped-unsupported-non-selected-shape` and do not invoke the worker. A selected
unsupported shape appends `failed-closed-unsupported-selected-shape`, writes
`worker-vector-substitution.json`, and exits non-zero before worker invocation or
graph mutation.

In M4y `selected-only-v0` ledger mode, non-selected rows are omitted from the
ledger. This only reduces proof IO and log volume; it does not broaden the
allowed graph-facing substitution surface.

On shadow mismatch after validation passes, Flye writes `worker-shadow.json`,
writes `seam-summary.json` with:

```json
{
  "status": "shadow-failed-before-graph-mutation",
  "validation_status": "passed",
  "shadow_status": "failed",
  "shadow_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and then exits non-zero before graph mutation.
