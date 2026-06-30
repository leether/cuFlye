# Task Card: cuFlye M4t Substitution Session Timing Attribution

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Add timing attribution for M4s graph-facing substitution sessions so cuFlye can
separate CPU overlap time, CUDA worker time, process/IO overhead, validation
overhead, and ledger overhead before making the next optimization decision.

## Background

M4s proves multiple selected supported queries can return verified
CUDA-worker-derived `OverlapRange` vectors while final Flye artifacts still
match CPU. It does not prove speed. The next highest-ROI question is where time
is being spent: CUDA kernel work, worker process startup, file IO, validation
and rehydration gates, or ordinary Flye CPU stages.

M4t should turn the session ledger into a timing ledger without weakening any
M4s safety gate.

## In Scope

- Extend session ledger entries with bounded timing fields for selected queries.
- Record worker process elapsed time, validation time, shadow time, guard time,
  typed rehydration time, object rehydration time, substitution comparison time,
  and total seam time.
- Preserve M4s positive and negative semantics.
- Summarize timing by decision type and selected query id.
- Compare full Flye elapsed time against CPU baseline, while explicitly
  separating overhead from CUDA kernel time.
- Produce a DGX proof manifest with timing attribution and a plain-language
  ROI conclusion.

## Out of Scope

- No default GPU mode.
- No removal of validation or fail-closed gates.
- No unsupported-shape CUDA substitution.
- No production speedup claim unless the measured evidence supports it.
- No broad graph algorithm rewrite.

## Acceptance Gates

- [ ] Timing fields are documented in the session ledger ABI.
- [ ] Selected-query ledger entries include non-negative timing fields.
- [ ] Positive session still substitutes selected supported queries and matches
  CPU canonical artifacts.
- [ ] Negative mismatch and unsupported-shape sessions still fail closed.
- [ ] Proof manifest reports per-query and aggregate timing attribution.
- [ ] The benefit assessment explicitly states whether M4t shows speedup,
  overhead, or an unclear result.
- [ ] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Use standard library timing and stack-owned values.
- Keep timing collection best-effort and non-invasive; timing must not affect
  substitution eligibility.
- Keep all graph-facing returns behind exact CPU comparison.

## Deliverables

- Updated session ledger ABI documentation.
- Flye seam patch for timing attribution.
- DGX proof manifest with positive and negative timing runs.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
