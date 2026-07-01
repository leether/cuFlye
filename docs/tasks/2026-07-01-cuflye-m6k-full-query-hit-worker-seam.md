# Task Card: cuFlye M6k Full Query-Hit Worker Seam

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Convert the M6j `--repeat-count` warm benchmark into a real full-query-hit
worker or Flye-side dry-run seam so the bounded hot-path advantage can be
requested through an integration boundary instead of an in-process benchmark
loop.

## In Scope

- Add a request/response boundary for the M6j `parallel-score` replay path.
- Preserve explicit metadata: schema, kernel mode, device, request ordinal,
  timing, source-pack shape, output path, and error status.
- Keep the M6j selected source pack as the first supported shape.
- Preserve CPU-vs-worker row-key parity, worker A/B determinism, and
  fail-closed unsupported-shape behavior.
- Compare cold process, warm worker request, and CPU replay timing on the same
  selected pack.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No larger source-pack shape expansion.
- No full non-key raw-overlap parity claim.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse `cuda/cuflye_cuda_raii.hpp` for device resources and any worker-level
  CUDA ownership.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs outside approved low-level RAII wrappers.
- Request failures must be fail-closed with explicit metadata.
- Worker output must be deterministic or checked through canonical row-key diff.

## Deliverables

- Full-query-hit worker or Flye-side dry-run seam.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded worker-boundary conclusion.

## Acceptance Gates

- [ ] Worker/Flye-seam output row-key diff matches CPU replay.
- [ ] Worker A/B row-key diff remains `match`.
- [ ] Unsupported-shape fail-closed proof passes through the worker boundary.
- [ ] Warm worker request timing preserves the M6j bounded hot-path advantage
      within the same selected source-pack shape.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
