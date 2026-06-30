# Task Card: cuFlye M4v Persistent Overlap Worker Lifecycle

Status: completed

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

- [x] Patch series applies and builds through the M4v patch.
- [x] Persistent lifecycle proof processes at least two sequential supported
  batch requests.
- [x] Warm-request worker-process or equivalent request-lifecycle timing is
  lower than the M4u batch-run worker-process timing.
- [x] Positive toy-raw artifacts still match CPU.
- [x] Mismatch and unsupported-shape negative sessions still fail closed.
- [x] Local and DGX syntax/style/ownership gates pass.

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

## Completion Notes

Implementation commit: `116d6458b7a0db94fb68cd74ab8178bf3322dc48`

DGX proof:
`tests/golden/cuflye-m4v-persistent-overlap-worker-lifecycle-dgx-aarch64.json`

Positive persistent lifecycle session:

- CPU toy-raw baseline elapsed: `82s`
- persistent lifecycle toy-raw elapsed: `88s`
- wall-clock ratio: `1.073171`
- `worker-requests.jsonl` contained `2` requests: cold warmup, then actual.
- warmup response: `request_ordinal=1`,
  `worker_cuda_context_warm=false`
- actual response: `request_ordinal=2`,
  `worker_cuda_context_warm=true`
- actual warm request `timing_ms.request_total`: `8.223469 ms`
- actual warm request backend mean before write: `5.530894 ms`
- actual warm request worker overhead: `2.692575 ms`
- canonical Flye graph/output artifacts matched the CPU toy-raw baseline.

Ledger decision counts:

- `deferred-session-batch-waiting`: `1`
- `substituted-from-session-batch-run`: `1`
- `substituted-from-session-batch-cache`: `1`
- `skipped-already-substituted`: `4`
- `skipped-not-selected`: `1892`
- `skipped-unsupported-non-selected-shape`: `987`

M4u comparison:

- M4u batch-run worker process: `440.793131 ms`
- M4v actual warm request total: `8.223469 ms`
- request-lifecycle reduction versus M4u batch-run worker process:
  `98.134393%`
- request-lifecycle speedup versus M4u batch-run worker process:
  `53.601847x`

Mismatch negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap`
- query `353` deferred while waiting for the batch.
- query `381` failed closed with
  `status=substitution-failed-before-graph-mutation`.
- validation, shadow, graph guard, typed rehydration, and object rehydration
  passed before exact substitution comparison rejected the worker vector.
- `graph_mutation_consumed_worker_output=false`.

Unsupported-shape negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=force-unsupported-selected-shape`
- query `353` failed closed before worker invocation.
- no `worker-response.json` or `worker-requests.jsonl` was written for that
  negative session.
- ledger recorded `failed-closed-unsupported-selected-shape` with
  `worker_process_ms=0`.

Plain-language benefit assessment:

M4v still does not prove end-to-end Flye GPU speedup: CPU toy-raw was `82s`,
and the persistent lifecycle run was `88s`. The real benefit is narrower but
important: the actual warm worker request ran with CUDA context already warm and
took `8.223469 ms`, compared with the M4u cold batch-run worker process time of
`440.793131 ms`. That is a `98.134393%` reduction in measured per-request
lifecycle cost. In plain terms, we proved the expensive startup/CUDA context
tax can be removed at the worker seam, but the current proof still pays for a
warmup request inside one Flye run and is not yet a whole-stage speedup.
