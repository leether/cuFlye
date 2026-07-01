# Task Card: cuFlye M5w Read Alignment Compact Binary Substitution Scale-Up

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Scale the M5v compact-binary vector-substitution proof from the selected
batch64 smoke to the broader full3546 selected read-alignment fixture set.

The core question for this card is:

```text
Can the guarded compact-binary CUDA read-alignment substitution path consume a
large selected set inside Flye, preserve exact artifacts, and keep the CUDA
integration path competitive when the fixed session overhead is amortized?
```

## In Scope

- Reuse the M5v compact-binary substitution seam without changing default
  behavior.
- Select the full3546 valid read-alignment fixture set harvested in M5h/M5t.
- Preserve exact canonical Flye artifacts versus CPU.
- Measure worker timing, Flye seam wall timing, compact binary size, and
  substitution count against M5u/M5v batch64 and M5t full3546 session payload
  evidence.
- Add mismatch or corruption negative proof with the scale-up configuration.

## Out of Scope

- No default GPU mode.
- No unbounded non-allowlisted `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's CPU divergence/base-alignment stages.
- No whole-Flye speed claim unless canonical artifacts match and timing evidence
  covers the broader selected path.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Prefer runner/proof tooling and env selection over broad code changes.
- Unsupported shapes and corrupted payloads must fail closed.

## Deliverables

- Full3546 selected-query proof runner or documented command.
- Positive DGX proof preserving exact artifacts and reporting substituted-chain
  counts.
- Negative DGX proof that blocks substitution before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with timing and benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] Positive full3546 selected substitution validates compact binary and
      reports substitution consumption for all selected chains present in
      `_readAlignments`.
- [ ] Canonical Flye artifacts match CPU.
- [ ] Negative mismatch/corruption case fails closed before graph mutation.
- [ ] Timing summary separates CUDA request time, Flye session wall time, and
      full Flye elapsed time.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
