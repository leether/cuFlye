# Substitution Session Ledger v0

Status: accepted in M4s; timing attribution accepted in M4t; session batch
cache accepted in M4u

Introduced: M4s

Scope: opt-in session ledger for verified graph-facing overlap-vector
substitution decisions.

## Purpose

`cuflye-overlap-vector-substitution-ledger-entry-v0` extends the M4r single
substitution smoke into a session-level audit trail. M4r proved one selected
query can return a verified CUDA-worker-derived `std::vector<OverlapRange>`.
M4s records every substitution decision for the run: substituted, skipped, or
failed closed.

The ledger is still a proof boundary. It is not a default GPU mode and does not
make an end-to-end speed claim.

## Selector

Session ledger mode is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-v0
```

M4s requires a deterministic query allowlist:

```text
CUFLYE_OVERLAP_REPLAY_QUERY_IDS=353,381
```

M4u adds an opt-in session batch/cache mode:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0
```

In this mode, selected supported queries may be deferred until the configured
allowlist-sized batch is available. The worker output is validated once for the
batch, then later selected query calls may reuse that verified batch output, but
the graph-facing return still requires an exact comparison against the current
CPU `OverlapRange` vector.

The existing M4r single-smoke selector remains valid:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-v0
```

## Shape Contract

M4s uses the same CUDA overlap-chain shape boundary as M4c/M4r:

- `only_max_ext=true`
- `keep_alignment=false`
- `nucl_alignment=false`
- `partition_bad_mappings=false`
- `max_overlaps=0`

Selected supported shapes may be sent to the worker. Selected unsupported
shapes fail closed before worker invocation. Non-selected unsupported shapes are
recorded as skipped and do not overwrite accepted proof files.

The unsupported-shape negative proof fault is:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=force-unsupported-selected-shape
```

The existing mismatch negative proof fault remains:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap
```

## Generated Files

Given `CUFLYE_OVERLAP_WORKER_OUTPUT_DIR=/path/to/seam`, M4s writes:

```text
worker-vector-substitution-ledger.jsonl
worker-vector-substitution.query_<id>.consumed
```

Each ledger line is one compact JSON object:

```json
{
  "schema": "cuflye-overlap-vector-substitution-ledger-entry-v0",
  "mode": "verified-overlap-range-session-v0",
  "query_id": 353,
  "selected": true,
  "supported_shape": true,
  "decision": "substituted",
  "reason": "selected supported shape evaluated by worker",
  "attempted": true,
  "accepted": true,
  "consumed": true,
  "failed_closed": false,
  "graph_facing_returned_worker_output": true,
  "graph_mutation_consumed_worker_output": true,
  "cpu_records": 8,
  "worker_records": 8,
  "object_records": 8,
  "timing_ms": {
    "cpu_overlap_ms": 12.3,
    "request_io_ms": 0.2,
    "worker_process_ms": 18.1,
    "validation_ms": 0.5,
    "shadow_ms": 0.3,
    "graph_guard_ms": 0.1,
    "typed_rehydration_ms": 0.4,
    "object_rehydration_ms": 0.3,
    "substitution_comparison_ms": 0.2,
    "ledger_entry_build_ms": 0.01,
    "seam_total_ms": 20.2
  },
  "shape": {
    "max_overlaps": 0,
    "keep_alignment": false,
    "only_max_ext": true,
    "nucl_alignment": false,
    "partition_bad_mappings": false
  }
}
```

Possible `decision` values are:

- `substituted`: selected supported query returned the verified worker-derived
  `OverlapRange` vector.
- `skipped-not-selected`: query is outside the deterministic substitution
  allowlist.
- `skipped-unsupported-non-selected-shape`: query is outside the allowlist and
  its shape is outside the CUDA overlap-chain contract.
- `skipped-already-substituted`: a durable per-query substitution sentinel
  already exists, so later Flye subprocesses do not re-invoke the worker.
- `failed-closed`: selected supported query reached substitution comparison but
  did not pass.
- `failed-closed-unsupported-selected-shape`: selected query had an unsupported
  shape and failed closed before worker invocation.
- `deferred-session-batch-waiting`: selected supported query was captured but
  returned CPU output while waiting for enough selected fixtures to amortize a
  batch worker invocation.
- `substituted-from-session-batch-run`: selected supported query returned a
  verified worker-derived `OverlapRange` vector from the batch worker invocation.
- `substituted-from-session-batch-cache`: selected supported query returned a
  verified worker-derived `OverlapRange` vector by reusing the already validated
  session batch output.

## Consumption Semantics

In session mode, Flye sends one selected supported query at a time to the worker.
Each accepted query writes its own durable sentinel:

```text
worker-vector-substitution.query_353.consumed
```

Later calls for that query append `skipped-already-substituted` to the ledger
and return the CPU vector. This keeps the smoke scope explicit while preventing
later unsupported Flye subprocess calls from overwriting accepted worker proof.

## Timing Attribution

M4t adds a `timing_ms` object to every ledger entry. Timing fields are
best-effort observations and must not affect substitution eligibility.

| Field | Meaning |
| --- | --- |
| `cpu_overlap_ms` | Time spent in the current `getSeqOverlaps` call before the cuFlye replay seam. |
| `request_io_ms` | Time spent creating the seam output directory and writing request/list JSON files. |
| `worker_process_ms` | Wall time spent in the external overlap worker process. |
| `validation_ms` | Time spent validating worker output and writing validation JSON. |
| `shadow_ms` | Time spent parsing and comparing shadow overlap records. |
| `graph_guard_ms` | Time spent evaluating and writing graph-consumption guard metadata. |
| `typed_rehydration_ms` | Time spent rehydrating typed overlap records and writing rehydration JSON. |
| `object_rehydration_ms` | Time spent constructing Flye `OverlapRange` objects and writing object rehydration JSON. |
| `substitution_comparison_ms` | Time spent comparing the worker-derived object vector against current CPU overlaps and writing substitution JSON. |
| `ledger_entry_build_ms` | Time spent building the JSONL ledger entry. |
| `seam_total_ms` | Total observed seam time for the selected or skipped decision before ledger append. |

All timing fields are milliseconds and must be non-negative. They are intended
for ROI attribution, not deterministic correctness checks.

## M4t Benefit Assessment

In plain terms, M4t is still not a speed claim. Its value is attribution:
cuFlye can now tell whether a graph-facing substitution attempt is spending time
in CPU overlap generation, request/file IO, external worker process execution,
validation, shadow comparison, rehydration, substitution comparison, or ledger
writing. The M4t DGX proof showed exact artifact preservation, but the positive
substitution run was slower than the CPU baseline, so the next optimization
should reduce seam overhead before broadening substitution scope.

## M4u Benefit Assessment

M4u reduces selected-query seam overhead but still does not prove end-to-end
Flye speedup. The DGX proof showed one selected query deferred, one selected
query substituted from a batch worker run, and one later selected query
substituted from the verified batch cache with `worker_process_ms=0`. Selected
substitution worker-process average fell by `46.808247%` versus M4t, while
canonical Flye artifacts still matched CPU.

## M4s Benefit Assessment

In plain terms, M4s is still not a speed claim. Its value is auditability and
controlled breadth: more than one selected supported query can cross the
graph-facing substitution boundary, while every skipped or rejected query/shape
is recorded instead of being hidden behind a single sentinel.
