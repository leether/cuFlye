# Task Card: cuFlye M3a Integration Path Decision

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Choose the next integration path after M2f proved that sparse CUDA candidate
generation can beat the measured CPU oracle for one real Flye pack.

The core question this card must answer is:

```text
How should cuFlye preserve the M2f CUDA-over-CPU advantage while moving from a
single-use external adapter toward a reusable Flye GPU backend?
```

## Background

M2f produced the first real-pack candidate-boundary speedup:

- CPU oracle: `943.032 ms`
- GPU-only backend total before JSON: `425.540 ms`
- GPU-only vs CPU oracle speedup: `2.22x`
- CUDA kernel: `6.361 ms`
- CUDA setup: `298.595 ms`
- Host prefix sum: `83.331 ms`
- Flye external adapter wall time to controlled stop: `0:03.34`

The kernel is no longer the bottleneck. The next bottlenecks are CUDA setup,
adapter/process overhead, host-side prefix/compaction, and the lack of
multi-query reuse.

## In Scope

- Compare in-process CUDA, a long-lived external worker, batched external
  adapter mode, and device-side compaction.
- Run one BDI/self-consistency calibration against the project desire.
- Choose the next milestone path.
- Seed the worker protocol contract for M3b.
- Update the roadmap so the next card is executable.

## Out of Scope

- No new CUDA kernel implementation.
- No Flye patch behavior change.
- No downstream graph logic.
- No full assembly speedup claim.
- No CPU fallback mode.

## BDI Calibration

Beliefs:

- M2f proves candidate-list equivalence and candidate-boundary speedup only; it
  does not prove full Flye assembly equivalence.
- The reusable backend must keep Flye patches small and C++11-compatible.
- Standalone CUDA code may remain CUDA C++14, but reusable code must obey the
  local RAII and deterministic-output rules.
- A one-process-per-query adapter will keep paying CUDA setup cost and will make
  multi-query speedups hard to preserve.

Desire:

- Build a community-shareable CUDA-driven Flye path that precisely preserves
  Flye semantics before making broader performance claims.

Intention:

- Use a long-lived external CUDA worker with a bounded batch protocol as the next
  integration path. Keep in-process CUDA as a later option only after worker
  overhead is measured.

## Decision

Choose:

```text
M3b: long-lived external CUDA worker with a file-backed request/response
protocol and warm CUDA context reuse.
```

This path keeps the Flye integration boundary narrow, preserves the M2f
candidate proof chain, and targets the measured setup/adapter overhead before
larger upstream-facing changes.

## Option Matrix

| Option | Main benefit | Main risk | M3 decision |
| --- | --- | --- | --- |
| In-process CUDA inside Flye | Lowest theoretical call overhead and direct memory reuse | Larger Flye patch, CUDA runtime linked into Flye, harder upstream review and deployment | Defer |
| Long-lived external worker | Amortizes CUDA setup, keeps Flye patch small, supports batches and fail-closed protocol | Requires lifecycle and protocol handling | Choose |
| Batched external adapter | Lowest short-term code change | Still fragile if it remains one-shot and file-heavy | Use only as a compatibility stepping stone |
| Device-side prefix/compaction first | Removes host prefix cost | Does not address the larger CUDA setup and adapter overhead | Defer until worker timing is known |

## C++/CUDA Style Constraints

- Keep Flye patch code C++11-compatible.
- Keep CUDA worker code CUDA C++14 unless a later Task Card justifies changing
  the standard.
- Use move-only RAII wrappers for CUDA allocations, events, streams, and future
  pinned host buffers.
- Do not add direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`,
  `cudaEventDestroy`, `cudaStreamCreate`, or `cudaStreamDestroy` outside the
  approved RAII layer.
- Use explicit-width integer types at protocol, TSV, JSON, and CUDA boundaries.
- Preserve deterministic candidate-record-v1 ordering or require a canonical
  diff gate before downstream use.
- Fail closed on unsupported request shapes. Silent CPU fallback remains
  disallowed.

## Deliverables

- M3a design decision under `docs/design/`.
- Worker protocol seed under `docs/abi/`.
- Roadmap updated to M3b.
- This Task Card marked completed with the next executable milestone.

## Acceptance Gates

- [x] Decision states one chosen integration path.
- [x] Decision explains why the other paths are not the next highest-ROI move.
- [x] Decision uses M2f timing evidence instead of generic GPU assumptions.
- [x] Worker protocol names request/response schema, failure semantics, and
  deterministic output gates.
- [x] Roadmap immediate next step points to M3b worker implementation.
- [x] No full Flye assembly speedup claim is introduced.

## Merge Note

M3a is a governance and architecture slice. It makes no runtime code changes.
The next implementation slice is M3b: build a minimal long-lived CUDA worker
that accepts a JSONL sequence of one or more real pack requests. The proof run
must process at least two requests in one worker process, emit the same
candidate-record-v1 output as M2f, and report first-request versus warm-request
timing.
