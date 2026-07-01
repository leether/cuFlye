# Task Card: cuFlye M6j Persistent Full Query-Hit Replay Session

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M6i standalone full-query-hit replay binary into a warm session proof
so repeated replay requests avoid cold CUDA process and context setup while
preserving the same canonical row-key parity gates.

## In Scope

- Add a bounded worker/session mode for the M6i source-pack replay path.
- Support the accepted M6i source pack and `parallel-score` kernel mode first.
- Keep request and response metadata explicit: schema, kernel mode, device,
  timing, input shape, output path, and failure status.
- Preserve CPU-vs-CUDA row-key parity, CUDA A/B determinism, and fail-closed
  unsupported-shape behavior.
- Measure cold standalone time, warm session request time, CUDA kernel time,
  and CPU replay time on the same selected pack.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No new source-pack schema.
- No claim about full non-key raw-overlap field parity.
- No claim that whole Flye is faster.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse `cuda/cuflye_cuda_raii.hpp` for device resources and any session-level
  CUDA ownership.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs outside approved low-level RAII wrappers.
- Keep session failure modes fail-closed; malformed requests, unsupported
  shapes, and memory budget violations must produce explicit error metadata.
- Keep warm-session output deterministic or compare it through the existing
  canonical row-key diff gate.

## Deliverables

- A session-capable full-query-hit replay worker or benchmark harness.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded cold-vs-warm conclusion.

## Acceptance Gates

- [ ] M6i CPU-vs-serial and CPU-vs-parallel row-key parity still passes.
- [ ] Warm session CUDA A/B row-key diff remains `match`.
- [ ] Unsupported-shape fail-closed proof still passes through the session
      path.
- [ ] Matched CPU, cold CUDA, and warm-session CUDA timings are recorded.
- [ ] Any speedup claim is limited to the measured bounded request shape and is
      supported by the matched timing data.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
