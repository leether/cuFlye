# Verified Overlap Vector Substitution Smoke v0

Status: accepted in M4r

Introduced: M4r

Scope: opt-in Flye-side substitution of a verified CUDA worker-derived
`std::vector<OverlapRange>` at the selected overlap return point.

## Purpose

`cuflye-verified-overlap-vector-substitution-smoke-v0` is the first
graph-facing substitution proof after M4q. M4q proves CUDA overlap worker output
can be rehydrated into actual Flye `OverlapRange` objects. M4r takes one
selected query and returns that verified object vector from `getSeqOverlaps`
instead of returning the original CPU vector.

The substitution is allowed only after exact CPU comparison succeeds. It is not
a production GPU mode and does not make an end-to-end speed claim.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-v0
```

Unsupported values fail closed.

The negative proof fault is:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap
```

This fault is disabled by default. It removes one candidate object after M4q
object rehydration has already passed, proving that substitution itself fails
closed on mismatch.

## Required Preconditions

M4r requires:

- M4q object rehydration `status=passed` and `eligible=true`.
- The selected fixture is the current captured query.
- Fixture count matches `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`.
- The CPU `OverlapRange` vector has no `kmerMatches` payload.
- The worker object vector canonicalizes exactly to the current CPU overlap
  vector.
- The audit JSON path is available.

The smoke is one-shot across the Flye run. After the selected substitution is
accepted, Flye writes `worker-vector-substitution.consumed` under
`CUFLYE_OVERLAP_WORKER_OUTPUT_DIR`. Later overlap calls, including calls from a
new `flye-modules` subprocess, see this sentinel and do not re-invoke the
worker. This keeps M4r scoped to one verified graph-facing return and avoids
widening the supported-shape contract by accident.

The worker output directory must be fresh for a proof run. The repository
runner removes and recreates `--overlap-worker-output-dir` before each run.

The `kmerMatches` precondition is deliberate. M4q objects leave `kmerMatches`
unset, so M4r must not substitute them for a CPU vector that carries alignment
payload not present in the worker output.

## Generated Files

When enabled, Flye writes:

```text
worker-vector-substitution.json
worker-vector-substitution.consumed
```

with schema:

```json
{
  "schema": "cuflye-verified-overlap-vector-substitution-smoke-v0",
  "status": "passed",
  "mode": "verified-overlap-range-v0",
  "state": "consumed",
  "decision": "verified-overlap-range-vector-substituted",
  "selected_overlap_source": "worker-overlap-range-object-vector",
  "eligible": true,
  "attempted": true,
  "accepted": true,
  "consumed": true,
  "failed_closed": false,
  "graph_facing_returned_worker_output": true,
  "graph_mutation_consumed_worker_output": true
}
```

`seam-summary.json` also records:

```json
{
  "status": "substitution-consumed-verified-overlap-vector",
  "overlap_vector_substitution_status": "passed",
  "overlap_vector_substitution_state": "consumed",
  "overlap_vector_substitution_accepted": true,
  "overlap_vector_substitution_consumed": true,
  "overlap_vector_substitution_selected_source": "worker-overlap-range-object-vector",
  "graph_facing_returned_worker_output": true,
  "graph_mutation_consumed_worker_output": true
}
```

## Failure Semantics

On unsupported selector, failed M4q object rehydration, missing selected fixture,
record mismatch, present CPU `kmerMatches`, or proof-fault mismatch, Flye writes
`worker-vector-substitution.json`, writes `seam-summary.json` with:

```json
{
  "status": "substitution-failed-before-graph-mutation",
  "overlap_vector_substitution_status": "failed",
  "overlap_vector_substitution_state": "failed-closed",
  "overlap_vector_substitution_accepted": false,
  "overlap_vector_substitution_consumed": false,
  "graph_facing_returned_worker_output": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before returning worker output.

There is no silent CPU fallback when the substitution selector is explicitly
enabled.

## M4r Benefit Assessment

In plain terms, M4r still does not prove Flye is faster. Its value is crossing
the first graph-facing safety boundary: one selected overlap query can return a
CUDA-derived `OverlapRange` vector, but only after exact CPU equivalence is
proved and only in an opt-in smoke mode.
