# Read Alignment Vector Substitution Smoke v0

Status: accepted for M5m

Introduced: M5m

Scope: opt-in substitution of verified CUDA-derived read-alignment
`GraphAlignment` object vectors into a bounded `_readAlignments` slice.

## Purpose

`cuflye-read-alignment-vector-substitution-smoke-v0` is the first
read-alignment graph-facing consumption contract. M5l proves that worker output
can become a shadow `std::vector<GraphAlignment>` and match the CPU slice. M5m
allows that verified object vector to replace the matching forward chains in
`_readAlignments` for selected reads.

This is still a smoke test. CPU read alignment is still computed first, the
mode is disabled by default, and exact artifact parity is mandatory.

## Selector

```text
CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_MODE=verified-graph-alignment-v0
```

Required upstream gates:

```text
CUFLYE_READ_ALIGNMENT_WORKER_MODE=cuda-bulk-persistent-v0
CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE=dry-run-v0
CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE=typed-graph-alignment-v0
CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE=graph-alignment-object-vector-v0
```

The mode fails closed if M5l object-vector rehydration is absent or failed.

## Substitution Semantics

For every selected query id:

1. Flye validates worker TSV rows against the CPU oracle.
2. Flye rehydrates rows into typed read-alignment records.
3. Flye groups typed records into `std::vector<GraphAlignment>`.
4. Flye canonicalizes that object vector and compares it to the current CPU
   `_readAlignments` slice.
5. Only after exact comparison passes for all selected queries, Flye replaces
   the matching forward chains in a temporary `_readAlignments` copy and swaps
   it into place.

Complement chains are not replaced in M5m. Global `_readAlignments` order is
preserved.

## Generated Files

When enabled, Flye writes:

```text
read-alignment-vector-substitution.json
```

with schema:

```json
{
  "schema": "cuflye-read-alignment-vector-substitution-smoke-v0",
  "status": "passed",
  "mode": "verified-graph-alignment-v0",
  "state": "consumed",
  "decision": "verified-graph-alignment-object-vector-substituted",
  "eligible": true,
  "attempted": true,
  "accepted": true,
  "consumed": true,
  "graph_facing_returned_worker_output": true,
  "graph_mutation_consumed_worker_output": true
}
```

`read-alignment-seam-summary.json` records matching substitution fields and
sets `graph_mutation_consumed_worker_output=true` only when substitution is
accepted and Flye continues past the seam.

## Negative Proof Fault

```text
CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-chain
```

The fault is proof-only. It removes the first rehydrated object-vector chain
after M5l passes, forcing the exact substitution comparison to fail closed
before graph mutation.

## M5m Benefit Assessment

M5m still does not prove cuFlye is faster. Its value is integration safety:
verified CUDA read-alignment output can cross the first real `_readAlignments`
consumption boundary while preserving exact Flye artifacts, and a mismatch still
stops before graph mutation.

Accepted DGX proof:

```text
proof_root=/tmp/cuflye-m5m-proof-20260701T013646Z
positive_query_ids=5,47,200,204
vector_substitution_status=passed
vector_substitution_state=consumed
total_substituted_chains=4
graph_mutation_consumed_worker_output=true
positive_vs_cpu_canonical_diff=match
negative_fault=drop-first-substitution-chain
negative_vector_substitution_state=failed-closed
negative_graph_mutation_consumed_worker_output=false
```
