# Flye Overlap Worker Seam v0

Status: accepted in M4j; batch allowlist extension accepted in M4k; validation
gate accepted in M4l; shadow consumption proof accepted in M4m

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
| `CUFLYE_OVERLAP_WORKER_BIN` | Path to `cuflye-cuda-overlap-chain-replay`. |
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

## Generated Files

Given `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR=/path/to/seam`, Flye writes:

| File | Meaning |
| --- | --- |
| `worker-fixtures.txt` | Absolute or run-relative replay fixture directories. |
| `worker-query-ids.txt` | Captured signed query ids, one per replay fixture. |
| `worker-request.json` | `cuflye-overlap-worker-request-v0` request. |
| `worker-response.json` | `cuflye-overlap-worker-response-v0` response. |
| `worker-batch.json` | Underlying packed batch runner JSON. |
| `worker-validation.json` | Flye-side ABI validation and CPU-oracle canonical diff summary for every worker output. |
| `worker-shadow.json` | Flye-side shadow parse and comparison summary when `CUFLYE_OVERLAP_WORKER_SHADOW_MODE=canonical-overlap-v0`. |
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
- `CUFLYE_OVERLAP_WORKER_VALIDATION_MODE` is unsupported;
- any worker output is missing, malformed, empty, not `overlap-range-v1`, or
  canonical-diffs `mismatch` against its captured `oracle.overlaps.tsv`.
- `CUFLYE_OVERLAP_WORKER_SHADOW_MODE` is unsupported;
- shadow mode is selected and the parsed worker records differ from the
  in-memory CPU overlap records for any captured query.

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
