# Task Card: cuFlye M4x GPU-First Overlap Substitution Perf Gate

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move beyond proof-only substitution by defining a bounded GPU-first path for
selected supported overlap shapes, while preserving a CPU-oracle audit mode.

## Background

M4w removed the duplicate warmup batch and reduced Flye-visible selected
worker/process time to `12.518829 ms`, but the positive toy-raw run still
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

- [ ] Patch series applies and builds through the M4x patch.
- [ ] GPU-first mode skips live CPU overlap for at least one selected supported
  query and records that decision in the substitution ledger.
- [ ] Audit mode catches a forced GPU/CPU mismatch and fails closed.
- [ ] Positive toy-raw artifacts still match CPU.
- [ ] Local and DGX syntax/style/ownership gates pass.
- [ ] Plain-language benefit assessment states whether wall time improved and
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
