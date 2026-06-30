# Task Card: cuFlye M4u Substitution Worker Overhead Reduction

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce the graph-facing substitution seam overhead exposed by M4t, while keeping
the M4s/M4t exact artifact and fail-closed guarantees.

## Background

M4t proved that timing attribution works and that selected supported
substitution still preserves canonical Flye artifacts. It also showed the
current integration path is not faster end to end: the CPU toy-raw baseline
elapsed `87s`, while the substitution/timing run elapsed `99s`. For selected
queries, worker process time alone was `452.297705 ms` for query `353` and
`376.389273 ms` for query `381`.

The next ROI target is therefore not broader substitution scope. It is reducing
the per-selected-query seam cost: external process startup, request/response
file IO, and repeated validation scaffolding.

## In Scope

- Design and implement one bounded overhead-reduction path for selected
  supported substitution.
- Prefer a minimal persistent-worker or amortized request path over changing
  Flye graph semantics.
- Preserve the `timing_ms` ledger fields and add any new overhead fields only if
  they stay backward-compatible.
- Keep exact CPU comparison before graph-facing worker output is returned.
- Preserve mismatch and unsupported-shape fail-closed behavior.
- Compare M4u wall-clock and selected-query timing against the M4t proof.

## Out of Scope

- No default GPU mode.
- No unsupported-shape CUDA substitution.
- No removal of validation, shadow, rehydration, or exact CPU comparison gates.
- No large production dataset claim.
- No graph algorithm rewrite.

## Acceptance Gates

- [x] Patch series applies and builds through the M4u patch.
- [x] Positive toy-raw session still substitutes selected supported queries and
  matches CPU canonical artifacts.
- [x] Mismatch and unsupported-shape negative sessions still fail closed.
- [x] Timing proof shows reduced selected-query seam overhead versus M4t, or the
  proof explicitly explains why the attempted reduction did not work.
- [x] Proof manifest records wall-clock comparison, selected-query timing, and
  aggregate timing by decision type.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Use stack values, `std::vector`, `std::map`, and RAII standard library
  objects for ownership.
- Do not introduce direct CUDA allocation/event ownership outside the approved
  CUDA RAII layer.
- Keep any worker lifecycle boundary explicit and fail-closed.

## Deliverables

- [x] Flye seam and/or worker patch that reduces selected-query substitution
  overhead.
- [x] Updated ABI documentation if the timing or worker contract changes.
- [x] DGX proof manifest with positive and negative sessions.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Implementation Notes

M4u starts with an opt-in Flye seam mode:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0
```

The first selected supported query can be recorded as
`deferred-session-batch-waiting` and return CPU output. Once the allowlist-sized
batch is available, Flye invokes the CUDA overlap worker once, validates the
batch output, and caches the verified worker output for later selected query
calls. Cached returns still run the final exact CPU comparison before returning
worker-derived `OverlapRange` objects.

## Completion Notes

Implementation commit: `e1d38fa00546a2d22bbcb3de19f43948165a3db3`

DGX proof:
`tests/golden/cuflye-m4u-substitution-worker-overhead-reduction-dgx-aarch64.json`

Positive batch/cache session:

- CPU toy-raw baseline elapsed: `84s`
- batch/cache substitution toy-raw elapsed: `91s`
- wall-clock ratio: `1.083333`
- ledger decision counts:
  - `deferred-session-batch-waiting`: `1`
  - `substituted-from-session-batch-run`: `1`
  - `substituted-from-session-batch-cache`: `1`
  - `skipped-already-substituted`: `4`
  - `skipped-not-selected`: `1892`
  - `skipped-unsupported-non-selected-shape`: `987`
- canonical Flye graph/output artifacts matched the CPU toy-raw baseline.

Selected-query timing:

- query `353`: `deferred-session-batch-waiting`, worker process `0 ms`, seam
  total `1.10794 ms`
- query `381`: `substituted-from-session-batch-run`, worker process
  `440.793131 ms`, seam total `455.366044 ms`
- query `353`: `substituted-from-session-batch-cache`, worker process `0 ms`,
  seam total `2.418058 ms`

M4t comparison:

- M4t selected worker-process average: `414.343489 ms`
- M4u selected worker-process average: `220.396566 ms`
- worker-process average reduction: `46.808247%`
- M4t selected seam-total average: `432.363197 ms`
- M4u selected seam-total average: `228.892051 ms`
- seam-total average reduction: `47.060237%`

Mismatch negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-overlap`
- query `353` was deferred; query `381` failed closed at exact substitution
  comparison.

Unsupported-shape negative proof:

- `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=force-unsupported-selected-shape`
- selected query `353` failed closed before worker invocation and recorded
  `worker_process_ms=0`.

Plain-language CUDA benefit: M4u still does not make Flye faster end to end.
It does prove a useful integration improvement: one worker run can be amortized
across a later cached selected substitution without changing final Flye
artifacts, cutting selected substitution worker-process and seam-total average
timing by roughly `47%` versus M4t. The next ROI target is a real persistent
worker lifecycle so this overhead reduction is not limited to cacheable repeated
queries.
