# Task Card: cuFlye M4w True Persistent Overlap Worker Session

Status: completed

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

- [x] Patch series applies and builds through the M4w patch.
- [x] A persistent worker session processes at least one warm Flye actual
  request without a duplicate warmup request in the same Flye proof path.
- [x] Flye-visible worker/process timing for the actual request is lower than
  the M4u batch-run worker-process timing and lower than the M4v
  warmup-plus-actual worker-process timing.
- [x] Positive toy-raw artifacts still match CPU.
- [x] Mismatch and unsupported-shape negative sessions still fail closed.
- [x] Local and DGX syntax/style/ownership gates pass.

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

## Completion Notes

DGX proof:
`tests/golden/cuflye-m4w-true-persistent-overlap-worker-session-dgx-aarch64.json`

M4w used toy-raw query ids `353,381` with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`. The worker session wrote
`session-ready.json` after CUDA context setup, and Flye submitted only the
actual `worker-request.json`. The positive proof generated no warmup request,
warmup response, or JSONL request file.

Key positive metrics:

```text
request_ordinal: 1
worker_cuda_context_warm: true
timing_ms.request_total: 9.025404 ms
Flye-visible worker_process_ms: 14.157398 ms
M4u cold batch-run worker_process_ms: 440.793131 ms
M4v warmup-plus-actual worker_process_ms: 463.398560 ms
```

Plain-language assessment: M4w proves a real seam-level benefit. It removes the
duplicate warmup batch from the Flye proof path and cuts the selected
worker/process segment by about `96%` versus M4u/M4v. It is not yet whole-run
speedup: CPU toy-raw elapsed `73s`, while M4w elapsed `83s`, because the current
proof still computes CPU overlaps first as the live oracle before substituting
the verified CUDA output. The next ROI target is GPU-first supported
substitution with an audit gate, not more process-lifecycle tuning.
