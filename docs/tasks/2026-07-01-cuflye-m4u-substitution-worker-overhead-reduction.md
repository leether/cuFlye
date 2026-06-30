# Task Card: cuFlye M4u Substitution Worker Overhead Reduction

Status: proposed

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

- [ ] Patch series applies and builds through the M4u patch.
- [ ] Positive toy-raw session still substitutes selected supported queries and
  matches CPU canonical artifacts.
- [ ] Mismatch and unsupported-shape negative sessions still fail closed.
- [ ] Timing proof shows reduced selected-query seam overhead versus M4t, or the
  proof explicitly explains why the attempted reduction did not work.
- [ ] Proof manifest records wall-clock comparison, selected-query timing, and
  aggregate timing by decision type.
- [ ] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Use stack values, `std::vector`, `std::map`, and RAII standard library
  objects for ownership.
- Do not introduce direct CUDA allocation/event ownership outside the approved
  CUDA RAII layer.
- Keep any worker lifecycle boundary explicit and fail-closed.

## Deliverables

- Flye seam and/or worker patch that reduces selected-query substitution
  overhead.
- Updated ABI documentation if the timing or worker contract changes.
- DGX proof manifest with positive and negative sessions.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
