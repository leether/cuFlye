# Task Card: cuFlye M6o Session Scale Performance Gate

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Measure whether the M6n file-backed full-query-hit worker session keeps its
advantage when more than two selected Flye seam requests are submitted through
one live worker.

## In Scope

- Reuse the M6n `session-file-v0` protocol without changing graph state.
- Submit several compatible selected full-query-hit windows through one worker
  session.
- Record cold request, warm request, amortized per-request timing, and row-key
  diff results.
- Include at least one incompatible or memory-budget negative proof that fails
  closed.
- Decide whether the next guarded graph-consumption step has enough measured
  ROI to proceed.

## Out of Scope

- No default GPU mode.
- No graph mutation from worker output.
- No full raw-overlap non-key parity claim.
- No new CUDA kernel unless the session-scale proof shows the current kernel is
  no longer the limiting risk.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer proof harness and manifest changes before adding new C++ code.
- Keep Flye patches C++11-compatible if any seam code changes are required.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Keep all new modes explicit, opt-in, deterministic, and fail-closed.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Updated ROADMAP conclusion with cold, warm, and amortized timing.
- Any runner-script support needed to repeat session submissions safely.
- Next Task Card based on the measured ROI.

## Acceptance Gates

- [ ] One file-backed worker session processes at least four compatible actual
      requests.
- [ ] Every warm request reports `worker_cuda_context_warm=true`.
- [ ] Warm requests report zero parse, device allocation, and host-to-device
      copy timing.
- [ ] Row-key diff matches the CPU raw-overlap oracle for every validated
      actual request.
- [ ] Negative proof fails closed before graph mutation.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
