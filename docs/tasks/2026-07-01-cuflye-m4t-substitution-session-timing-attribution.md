# Task Card: cuFlye M4t Substitution Session Timing Attribution

Status: completed

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

- [x] Timing fields are documented in the session ledger ABI.
- [x] Selected-query ledger entries include non-negative timing fields.
- [x] Positive session still substitutes selected supported queries and matches
  CPU canonical artifacts.
- [x] Negative mismatch and unsupported-shape sessions still fail closed.
- [x] Proof manifest reports per-query and aggregate timing attribution.
- [x] The benefit assessment explicitly states whether M4t shows speedup,
  overhead, or an unclear result.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Use standard library timing and stack-owned values.
- Keep timing collection best-effort and non-invasive; timing must not affect
  substitution eligibility.
- Keep all graph-facing returns behind exact CPU comparison.

## Deliverables

- [x] Updated session ledger ABI documentation.
- [x] Flye seam patch for timing attribution.
- [x] DGX proof manifest with positive and negative timing runs.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

Implementation commit: `2c01201de057170273ad0c633d3579e1f29ce683`

DGX proof:
`tests/golden/cuflye-m4t-substitution-session-timing-attribution-dgx-aarch64.json`

Positive session:

- CPU toy-raw baseline elapsed: `87s`
- substitution/timing toy-raw elapsed: `99s`
- wall-clock ratio: `1.137931`
- selected toy-raw query ids: `353,381`
- substituted query ids: `353,381`
- ledger decision counts:
  - `substituted`: `2`
  - `skipped-already-substituted`: `5`
  - `skipped-not-selected`: `1892`
  - `skipped-unsupported-non-selected-shape`: `987`
- canonical Flye graph/output artifacts matched the CPU toy-raw baseline.

Selected-query timing:

- query `353`: CPU overlap `1.307334 ms`, worker process `452.297705 ms`,
  seam total `469.227281 ms`
- query `381`: CPU overlap `18.568655 ms`, worker process `376.389273 ms`,
  seam total `395.499113 ms`

Mismatch negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap`
- substitution recorded `status=failed`, `state=failed-closed`, and
  non-negative timing fields.
- ledger recorded a `failed-closed` decision.

Unsupported-shape negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=force-unsupported-selected-shape`
- selected query failed closed before worker invocation.
- selected unsupported entry recorded `worker_process_ms=0`.
- ledger recorded `failed-closed-unsupported-selected-shape`.

Plain-language CUDA benefit: M4t does not show end-to-end Flye speedup. It gives
the project a useful timing ruler. The CUDA substitution path still preserves
exact Flye artifacts, but the current seam spends hundreds of milliseconds per
selected query in external worker/process and file/validation overhead. The next
highest-ROI work is reducing that overhead before increasing substitution
scope.
