# Task Card: cuFlye M4r Verified Overlap Vector Substitution Smoke

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M4q `OverlapRange` object vector as a verified substitute for the
selected query's returned overlap vector in an opt-in smoke mode, then prove
the run either preserves graph artifacts or fails closed before graph mutation.

## Background

M4q proves that validated CUDA overlap worker output can become real upstream
Flye `OverlapRange` objects and still match the CPU overlap vector. The next
risk is not representation, but controlled graph-facing substitution: can Flye
return the verified object vector at the selected seam without changing default
CPU behavior or silently masking a mismatch?

M4r is the smallest step toward actual graph consumption. It is still a smoke
test, not a production GPU mode and not a speed claim.

## In Scope

- Add an explicit substitution smoke selector disabled by default.
- Require M4q object rehydration `status=passed` and `eligible=true`.
- Substitute only the already verified `OverlapRange` object vector for the
  selected fixture/query path.
- Keep exact CPU comparison as a precondition before any substitution.
- Record whether substitution was attempted, accepted, consumed, or rejected.
- Run a bounded Flye fixture and compare canonical graph/output artifacts.
- Include a negative proof where a mismatch prevents substitution and fails
  closed before graph mutation.
- Include a plain-language CUDA benefit assessment after proof.

## Out of Scope

- No default GPU mode.
- No unsupported-shape substitution.
- No silent CPU fallback.
- No large production dataset claim.
- No end-to-end speed claim.
- No broad rewrite of Flye graph logic.

## Acceptance Gates

- [x] Substitution smoke mode is documented and disabled by default.
- [x] M4q object rehydration success is mandatory before substitution can be
  considered.
- [x] Unsupported shape, missing object proof, or mismatch fails closed.
- [x] Positive smoke records the verified object vector as the selected overlap
  source only after exact CPU comparison.
- [x] Default CPU Flye fixture output remains unchanged.
- [x] Canonical graph/output artifacts are unchanged when substitution is accepted,
  or the run stops before graph mutation when it is rejected.
- [x] Audit metadata records selected query ids, consumed state, failed-closed
  state, and graph mutation status.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Do not introduce raw owning pointers in cuFlye seam code.
- Keep object ownership inside `std::vector<OverlapRange>` and stack values.
- Keep substitution behind an explicit selector and exact comparison gate.
- Do not broaden graph-facing changes beyond the selected seam.

## Deliverables

- [x] Substitution smoke ABI/design documentation.
- [x] Flye seam patch for verified overlap-vector substitution.
- [x] DGX proof manifest for positive and negative substitution smoke runs.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

Implementation commit: `a5139802951e3f752d56429195e8ec51e29ea020`

DGX proof:
`tests/golden/cuflye-m4r-verified-overlap-vector-substitution-smoke-dgx-aarch64.json`

The positive proof ran toy-raw with
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-v0`,
selected query `353`, and consumed the verified worker-derived
`OverlapRange` vector:

- validation, shadow comparison, graph guard, typed rehydration, and object
  rehydration all passed.
- `worker-vector-substitution.json` recorded `status=passed`,
  `state=consumed`, `cpu_records=8`, `worker_records=8`,
  `object_records=8`, and
  `graph_facing_returned_worker_output=true`.
- `worker-vector-substitution.consumed` was written as a durable one-shot
  sentinel, so later Flye subprocesses did not re-invoke the worker or
  overwrite `worker-response.json`.
- canonical Flye artifacts matched the CPU toy-raw run.

The negative proof injected
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap`.
Validation, shadow comparison, graph guard, typed rehydration, and object
rehydration still passed, but substitution detected the object-vector mismatch
and failed closed before returning worker output:

- `worker-vector-substitution.json` recorded `status=failed`,
  `state=failed-closed`, `consumed=false`, and
  `graph_facing_returned_worker_output=false`.
- `seam-summary.json` recorded
  `status=substitution-failed-before-graph-mutation`.

Plain-language CUDA benefit: M4r still does not prove Flye is faster. It proves
the first graph-facing boundary can be crossed safely for one supported query:
CUDA-worker overlap output became the vector returned to Flye, the final graph
artifacts stayed unchanged, and a mismatch still stopped before graph mutation.
