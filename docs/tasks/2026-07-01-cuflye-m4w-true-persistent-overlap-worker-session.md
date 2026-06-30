# Task Card: cuFlye M4w True Persistent Overlap Worker Session

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M4v warm-request lifecycle proof into a Flye-visible persistent worker
session that does not need to spend one duplicate warmup batch inside each proof
run.

## Background

M4v proved that the actual warm overlap-worker request can run as
`request_ordinal=2` with `worker_cuda_context_warm=true` and
`timing_ms.request_total=8.223469 ms`, versus the M4u cold batch-run worker
process time of `440.793131 ms`.

That is a strong lifecycle-seam win, but the M4v Flye run still launches one
external worker process and sends a duplicate warmup request before the actual
request. Therefore M4v is not an end-to-end Flye speedup.

## In Scope

- Define a true persistent worker session contract that can keep the CUDA
  worker alive outside a single synthetic warmup-plus-actual JSONL file.
- Keep requests file-backed and inspectable.
- Record worker startup/context setup separately from Flye-visible request
  latency.
- Make the Flye seam consume the actual request output through the existing
  validation, shadow, graph guard, rehydration, object rehydration, and exact
  substitution gates.
- Preserve positive artifact parity and mismatch/unsupported fail-closed
  behavior.

## Out of Scope

- No default GPU mode.
- No broad unsupported-shape substitution.
- No graph algorithm rewrite.
- No end-to-end speed claim unless the wall-time gate passes.

## Acceptance Gates

- [ ] Patch series applies and builds through the M4w patch.
- [ ] A persistent worker session processes at least one warm Flye actual
  request without a duplicate warmup request in the same Flye proof path.
- [ ] Flye-visible worker/process timing for the actual request is lower than
  the M4u batch-run worker-process timing and lower than the M4v
  warmup-plus-actual worker-process timing.
- [ ] Positive toy-raw artifacts still match CPU.
- [ ] Mismatch and unsupported-shape negative sessions still fail closed.
- [ ] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Keep process/session resources behind stack-owned standard library objects or
  explicit RAII wrappers.
- Do not introduce direct CUDA allocation/event ownership outside the approved
  CUDA RAII layer.
- Keep lifecycle shutdown explicit and fail-closed.

## Deliverables

- Persistent worker session ABI update.
- Flye seam and worker implementation for a true warm session request.
- DGX proof manifest with positive and negative sessions.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
