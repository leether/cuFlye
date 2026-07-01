# Task Card: cuFlye M8c Flye-Side M8b Worker Session Seam

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8b bounded hot-path CUDA advantage from standalone replay into the
Flye-side full-query-hit worker/session seam, while still preventing graph
mutation.

M8b proved the selected CUDA replay boundary can beat the same selected Flye
CPU quick-overlap baseline when the worker is warm. M8c should measure the
real seam overhead when Flye submits the M8b selected source pack through the
file-backed worker/session path.

## In Scope

- Reuse the M8b selected full-query-hit source pack and query ids.
- Run the Flye-side full-query-hit worker/session dry-run seam against that
  pack.
- Compare worker output against CPU replay row-key oracle and M8a chain-input
  oracle pack.
- Measure Flye-side submit/poll/request overhead separately from CUDA kernel
  time.
- Preserve canonical Flye artifacts and fail-closed behavior.

## Out of Scope

- No graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.
- No expansion beyond the M8b selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing Flye full-query-hit worker/session seam code.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved RAII wrappers.
- Keep all worker outputs diff-gated by canonical row-key comparison.
- Unsupported or mismatched worker output must fail closed before graph-facing
  consumption.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution for Flye submit/poll, worker request total, CUDA kernel,
  and validation diff.
- ROADMAP and Task Card updates that state whether seam overhead preserves or
  erases the M8b standalone hot-path advantage.

## Acceptance Gates

- [ ] Flye-side worker/session seam consumes the M8b selected source pack in
      dry-run/no-mutation mode.
- [ ] Worker row-key output matches CPU replay for the selected pack.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Capture/canonical Flye artifacts remain unchanged.
- [ ] Timing separates Flye submit/poll overhead, worker request total, and
      CUDA kernel time.
- [ ] Negative proof fails closed before graph-facing consumption.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
