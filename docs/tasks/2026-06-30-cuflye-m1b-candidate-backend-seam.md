# Task Card: cuFlye M1b Candidate Backend Seam

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn M1a's candidate dump instrumentation into the smallest useful backend
selection seam for future CUDA candidate generation.

The core question this card must answer is:

```text
Can cuFlye select a candidate-generation backend without changing Flye output?
```

## Background

M1a proved that cuFlye can capture and compare Flye overlap candidate lists from
`OverlapDetector::getSeqOverlaps`. M1b keeps the original CPU implementation as
the only working backend, but moves candidate collection behind a selector so a
CUDA backend can be inserted later without changing chaining, graph, or
polishing code.

## In Scope

- Add a second Flye patch for the backend selector seam.
- Keep the default backend equal to upstream CPU behavior.
- Add explicit `CUFLYE_CANDIDATE_BACKEND=cpu` support.
- Fail fast on unsupported backend names.
- Extend fixture runner metadata for explicit backend runs.
- Validate default backend and explicit CPU backend equivalence on DGX.

## Out of Scope

- CUDA kernels.
- GPU memory layout.
- Candidate filtering changes.
- Chaining or overlap scoring changes.
- Graph or polishing changes.

## Deliverables

- `patches/flye/2.9.6/0002-cuflye-candidate-backend-seam.patch`
- `scripts/run_flye_fixture.sh --candidate-backend NAME`
- DGX proof that default backend and explicit `cpu` backend candidate dumps
  compare as `match`.
- DGX proof that an unknown backend fails fast.

## Acceptance Gates

- Patched Flye builds on DGX with both M1a and M1b patches applied.
- Default backend run emits the same candidate dump as explicit `cpu`.
- Default backend and explicit `cpu` produce matching Flye artifacts.
- Unsupported `CUFLYE_CANDIDATE_BACKEND` exits non-zero with a clear error.
- No large candidate dump file is committed.

## Execution Checklist

- [ ] Add backend seam patch.
- [ ] Extend fixture runner with backend selection.
- [ ] Build patched Flye on DGX.
- [ ] Run default-backend candidate fixture.
- [ ] Run explicit-CPU candidate fixture.
- [ ] Diff candidate dumps.
- [ ] Diff Flye artifacts.
- [ ] Verify unsupported backend failure.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
