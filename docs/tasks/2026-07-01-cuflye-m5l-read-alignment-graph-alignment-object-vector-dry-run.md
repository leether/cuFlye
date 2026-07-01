# Task Card: cuFlye M5l Read Alignment GraphAlignment Object-Vector Dry Run

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Group validated CUDA read-alignment typed segments into a shadow
`std::vector<GraphAlignment>` object vector and compare it against Flye's CPU
`_readAlignments` slice, without replacing `_readAlignments` or feeding CUDA
output into graph mutation.

The core question this card must answer is:

```text
Can validated CUDA read-alignment rows become the same object-vector shape Flye
uses internally, and match the CPU _readAlignments slice for selected reads,
while still staying not-consumed?
```

## Background

M5k proved that worker TSV rows can survive checked Flye-side typed conversion
into GraphAlignment-shaped records. That was still a flat typed representation.

M5l moves one representation boundary closer to real consumption: the worker
records must become a shadow `std::vector<GraphAlignment>` and match the
corresponding CPU `_readAlignments` slice.

## In Scope

- Add a Flye patch for
  `CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE=graph-alignment-object-vector-v0`.
- Require M5k typed rehydration success before object-vector comparison.
- Group typed segments into a shadow `std::vector<GraphAlignment>`.
- Compare the shadow vector against CPU `_readAlignments` chains for the same
  selected read ids.
- Write `read-alignment-worker-object-rehydration.json`.
- Extend `read-alignment-seam-summary.json` with object-vector status fields.
- Add runner flags for object rehydration mode and proof fault.
- Prove positive and negative behavior on DGX.

## Out of Scope

- No replacement of Flye `_readAlignments`.
- No graph mutation consumption.
- No default GPU mode.
- No end-to-end Flye acceleration claim.
- No long-lived read-alignment worker protocol yet.
- No substitution of object-vector output into repeat resolution.

## C++/CUDA Style Constraints

- Keep Flye patch code compatible with Flye 2.9.6's C++ standard.
- Do not introduce direct owning `new`, `delete`, `malloc`, or `free`.
- Use stack values, STL containers, checked conversions, and file RAII.
- Every explicit CUDA/read-alignment seam must fail closed.
- Every path written by the seam must be recorded in JSON metadata.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- `patches/flye/2.9.6/0030-cuflye-read-alignment-graph-alignment-object-vector-dry-run.patch`
- `docs/abi/read-alignment-graph-alignment-object-vector-dry-run-v0.md`
- runner support for read-alignment object rehydration env vars
- DGX proof manifest under `tests/golden/`
- Roadmap and golden index updates
- Plain-language CUDA benefit assessment

## Acceptance Gates

- [x] Patch series applies through `0030` and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive dry-run invokes the CUDA worker from Flye.
- [x] Positive dry-run validates every worker output against CPU oracle TSV.
- [x] Positive dry-run writes M5k rehydration JSON with `status=passed`.
- [x] Positive dry-run writes object-vector JSON with
      `status=passed`, `state=not-consumed`, and
      `object_representation=graph-alignment-object-vector-v0`.
- [x] Positive dry-run records
      `graph_mutation_consumed_worker_output=false`.
- [x] Positive dry-run stops before graph mutation.
- [x] Negative proof fault fails closed after M5k typed rehydration pass.
- [x] Local syntax/style gates pass.
- [x] C++ ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

```text
proof_root=/tmp/cuflye-m5l-proof-20260701T010956Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_object_rehydration_status=passed
read_alignment_object_rehydration_state=not-consumed
object_representation=graph-alignment-object-vector-v0
total_object_records=7
total_object_chains=4
graph_mutation_consumed_worker_output=false
```

The negative proof enabled
`CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-graph-alignment-chain`
for query ids `5,47`. Worker validation, graph guard, and M5k typed
rehydration all passed first. M5l then detected the shadow object-vector
mismatch and failed closed with:

```text
read_alignment_object_rehydration_status=failed
read_alignment_object_rehydration_state=failed-closed
read_alignment_object_rehydration_decision=failed-closed-before-graph-mutation
graph_mutation_consumed_worker_output=false
```

Allowed M5l claim:

```text
cuFlye can convert validated CUDA read-alignment output into a shadow
std::vector<GraphAlignment>, prove that it matches the CPU _readAlignments
slice, and still stop before graph mutation.
```

Forbidden M5l claim:

```text
M5l does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```
