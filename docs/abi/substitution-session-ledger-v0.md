# Substitution Session Ledger v0

Status: proposed for M4s

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

## Consumption Semantics

In session mode, Flye sends one selected supported query at a time to the worker.
Each accepted query writes its own durable sentinel:

```text
worker-vector-substitution.query_353.consumed
```

Later calls for that query append `skipped-already-substituted` to the ledger
and return the CPU vector. This keeps the smoke scope explicit while preventing
later unsupported Flye subprocess calls from overwriting accepted worker proof.

## M4s Benefit Assessment

In plain terms, M4s is still not a speed claim. Its value is auditability and
controlled breadth: more than one selected supported query can cross the
graph-facing substitution boundary, while every skipped or rejected query/shape
is recorded instead of being hidden behind a single sentinel.
