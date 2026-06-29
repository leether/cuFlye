# Task Card: cuFlye M1b Candidate Backend Seam

Status: completed

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

- [x] Add backend seam patch.
- [x] Extend fixture runner with backend selection.
- [x] Build patched Flye on DGX.
- [x] Run default-backend candidate fixture.
- [x] Run explicit-CPU candidate fixture.
- [x] Diff candidate dumps.
- [x] Diff Flye artifacts.
- [x] Verify unsupported backend failure.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` against cuFlye commit
`f31146052d35f7eebb9c9bdb940a4a04a2c6a275` and upstream Flye commit
`886b8c17412cdf3a2868a28237bca6c5ad1da156`.

Patched build proof:

- Build manifest: `out/m1b/f311460/build_manifest.json`
- Applied patches:
  - `patches/flye/2.9.6/0001-cuflye-candidate-dump.patch`
  - `patches/flye/2.9.6/0002-cuflye-candidate-backend-seam.patch`
- Idempotent rebuild message:
  `Patch series already applied through 0002-cuflye-candidate-backend-seam.patch`

Backend equivalence proof:

- Default backend run: `out/m1b/f311460/runs/toy-default/candidates.tsv`
- Explicit CPU backend run: `out/m1b/f311460/runs/toy-cpu/candidates.tsv`
- Records per run: `29035928`
- Raw TSV SHA-256 per run:
  `5e55b79e3cda21ce4d7e5e101a65f30b8fa9c3ba50b542faadbbb27d5c4bfebd`
- Canonical candidate SHA-256 per run:
  `97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b`
- Candidate diff report:
  `out/m1b/f311460/runs/toy-default-vs-cpu.candidate-diff.json`
- Candidate diff status: `match`

Behavioral regression proof:

- Artifact diff report:
  `out/m1b/f311460/runs/toy-default-vs-cpu.artifact-diff.json`
- Artifact diff status: `match` for all M0 tracked Flye outputs.

Negative backend proof:

- Command used `--candidate-backend bogus`.
- Expected failure appeared in stderr:
  `Unsupported CUFLYE_CANDIDATE_BACKEND: bogus`

Tracked compact proof:

- `tests/golden/toy-hifi-backend-dgx-aarch64.json`
