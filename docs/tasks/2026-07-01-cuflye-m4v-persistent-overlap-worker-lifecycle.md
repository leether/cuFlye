# Task Card: cuFlye M4v Persistent Overlap Worker Lifecycle

Status: in_progress

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce the remaining per-batch external worker startup overhead by introducing
an explicit persistent overlap-worker lifecycle, while preserving the M4u
batch/cache proof boundaries.

## Background

M4u reduced selected substitution worker-process average by `46.808247%` versus
M4t by reusing a verified session batch output. That benefit depends on a later
selected query being cache-compatible. The batch run itself still paid
`440.793131 ms` of worker-process time, mostly external process and CUDA runtime
startup overhead.

The next ROI target is to keep a worker process warm across requests or provide
an equivalent lifecycle boundary that avoids paying process startup for every
batch run.

## In Scope

- Define a persistent-worker lifecycle contract for overlap worker requests.
- Implement the smallest worker/seam path that can process at least two
  sequential batch requests without starting a new worker process each time.
- Keep request/response files or add a bounded line protocol only if it remains
  inspectable in proof artifacts.
- Preserve validation, shadow comparison, graph guard, rehydration, object
  rehydration, exact CPU comparison, and fail-closed behavior.
- Record timing that separates first-start cost from warm-request cost.
- Compare M4v warm-request timing against M4u batch-run timing.

## Out of Scope

- No default GPU mode.
- No unsupported-shape CUDA substitution.
- No removal of exact CPU comparison.
- No broad Flye graph rewrite.
- No production dataset speedup claim.

## Acceptance Gates

- [ ] Patch series applies and builds through the M4v patch.
- [ ] Persistent lifecycle proof processes at least two sequential supported
  batch requests.
- [ ] Warm-request worker-process or equivalent request-lifecycle timing is
  lower than the M4u batch-run worker-process timing.
- [ ] Positive toy-raw artifacts still match CPU.
- [ ] Mismatch and unsupported-shape negative sessions still fail closed.
- [ ] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Keep process handles, pipes, temporary files, and CUDA resources behind RAII
  wrappers or stack-owned standard library objects.
- Do not introduce direct CUDA allocation/event ownership outside the approved
  CUDA RAII layer.
- Keep lifecycle shutdown explicit and fail-closed.

## Deliverables

- Persistent-worker lifecycle ABI documentation.
- Flye seam and worker implementation for warm sequential batch requests.
- DGX proof manifest with positive and negative sessions.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
