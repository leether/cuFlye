# Task Card: cuFlye M4x GPU-First Overlap Substitution Perf Gate

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move beyond proof-only substitution by defining a bounded GPU-first path for
selected supported overlap shapes, while preserving a CPU-oracle audit mode.

## Background

M4w removed the duplicate warmup batch and reduced Flye-visible selected
worker/process time to `14.157398 ms`, but the positive toy-raw run still
elapsed `83s` versus `73s` for CPU. The reason is structural: the current seam
computes CPU overlaps first, uses that live CPU vector as the oracle, then
substitutes the verified CUDA-derived vector. That proves equivalence but cannot
produce whole-run speedup.

## In Scope

- Define an explicit `gpu-first-supported-v0` substitution mode for allowlisted
  supported replay shapes.
- Keep `verified-overlap-range-session-batch-v0` as the proof/oracle mode.
- Add an audit mode that can run CPU comparison on sampled or selected queries
  without making every GPU-first query pay full live CPU overlap cost.
- Preserve exact artifact diff against CPU for toy-raw proof runs.
- Preserve fail-closed behavior for unsupported shapes and audit mismatches.

## Out of Scope

- No default GPU mode.
- No broad unsupported-shape substitution.
- No graph algorithm rewrite.
- No removal of the CPU oracle; this task only separates proof mode from a
  bounded performance mode.

## Acceptance Gates

- [x] Patch series applies and builds through the M4x patch.
- [x] GPU-first mode skips live CPU overlap for at least one selected supported
  query and records that decision in the substitution ledger.
- [x] Audit mode catches a forced GPU/CPU mismatch and fails closed.
- [x] Positive toy-raw artifacts still match CPU.
- [x] Local and DGX syntax/style/ownership gates pass.
- [x] Plain-language benefit assessment states whether wall time improved and
  why.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Keep GPU-first state explicit in ledger and seam summary.
- Any bypass of live CPU overlap must be opt-in, allowlisted, and auditable.

## Deliverables

- GPU-first substitution ABI update.
- Flye seam implementation behind a new explicit mode.
- DGX proof manifest with positive and forced-mismatch audit runs.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

DGX proof:
`tests/golden/cuflye-m4x-gpu-first-overlap-substitution-perf-gate-dgx-aarch64.json`

Remote proof directory:
`/tmp/cuflye-m4x-proof-20260630T210115Z`

Positive proof used toy-raw query ids `353,381` with
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=gpu-first-supported-v0` and
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`.

Selected ledger evidence:

```text
353 deferred-session-batch-waiting cpu_overlap_ms=0.939491 worker_process_ms=0.0
381 substituted-from-session-batch-run cpu_overlap_ms=9.166123 worker_process_ms=12.997414
353 gpu-first-from-session-batch-cache cpu_overlap_ms=0.0 worker_process_ms=0.0
```

Positive CPU vs GPU-first artifact diff: `match`.

Audit negative used
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0` with
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
It failed closed with:

```text
status=gpu-first-substitution-failed-before-live-cpu-overlap
error=gpu-first audit object vector differs from captured CPU oracle
graph_mutation_consumed_worker_output=false
```

Plain-language assessment: M4x proves the first real GPU-first graph-facing
shortcut. After the verified session batch exists, query `353` returned the
cached CUDA-worker `OverlapRange` vector with no live CPU overlap and no new
worker request. This is a real seam-level benefit, but it is not an end-to-end
speedup yet: CPU toy-raw took `72s`, while M4x positive took `84s`, because
only one selected cached overlap was bypassed and the rest of Flye remains
CPU-bound.
