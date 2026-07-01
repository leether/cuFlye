# Task Card: cuFlye M5x Read Alignment Selected CPU Bypass

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M5w full3546 guarded substitution proof into the first audited
selected-read CPU-bypass experiment for read-to-graph alignment.

The core question for this card is:

```text
Can Flye skip CPU pre-divergence chain DP for an explicit selected-read
allowlist, consume compact-binary CUDA-derived goodChains instead, preserve
exact canonical artifacts, and fail closed on any worker, validation, or
substitution issue?
```

## In Scope

- Add an opt-in CPU-bypass mode for the selected read-alignment allowlist only.
- Reuse `compact-binary-v0` validation and
  `verified-goodchains-v0` substitution.
- Keep the CPU path as default behavior.
- Preserve exact canonical Flye artifacts versus CPU baseline.
- Measure selected read-alignment CPU work avoided, CUDA request timing, seam
  timing, and full Flye elapsed time.
- Add at least one corruption or mismatch proof that fails closed before graph
  mutation and falls back to no consumption rather than silent CPU/GPU drift.

## Out of Scope

- No default GPU mode.
- No non-allowlisted `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's divergence filter unless separately proven.
- No speed claim unless CPU work is actually bypassed and exact artifacts still
  match.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Prefer explicit state objects over global mutable shortcuts.
- Use RAII for any new resource-owning C++ helper.
- Unsupported shapes, missing worker output, malformed compact binary payloads,
  and selected-read count mismatches must fail closed.

## Deliverables

- Flye patch for opt-in selected-read CPU bypass.
- DGX positive proof with exact canonical artifact match.
- DGX negative proof that prevents graph mutation consumption.
- Timing summary separating avoided CPU path, CUDA request time, Flye seam
  time, and full Flye elapsed time.
- Golden manifest under `tests/golden/`.
- Roadmap update with plain-language benefit and claim boundaries.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] Positive selected CPU-bypass mode consumes verified compact-binary
      CUDA-derived goodChains for the full3546 selected set.
- [ ] Positive proof records that selected CPU chain DP was skipped rather
      than computed and then replaced.
- [ ] Canonical Flye artifacts match CPU.
- [ ] Negative mismatch/corruption case fails closed before graph mutation.
- [ ] Timing summary separates CUDA request time, Flye seam time, avoided CPU
      work, and full Flye elapsed time.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
