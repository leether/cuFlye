# Task Card: cuFlye M1a Candidate Oracle and Backend Seam

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build the low-level candidate-generation oracle needed before CUDA kernels are
introduced.

The core question this card must answer is:

```text
Can cuFlye capture and compare Flye overlap candidate lists before CPU chaining?
```

## Background

M0 proved that a deterministic CPU Flye run can be rebuilt and compared on DGX.
M1 will eventually move candidate generation to CUDA, but the current oracle is
too coarse: it compares stage artifacts after chaining, repeat graph resolution,
and contig generation.

M1a creates a narrower proof surface inside `OverlapDetector::getSeqOverlaps`.
It must expose candidate matches generated from Flye's existing k-mer/minimizer
lookup without changing normal Flye behavior.

## In Scope

- Store cuFlye source patches for Flye 2.9.6 under `patches/flye/2.9.6/`.
- Extend `scripts/build_flye_cpu.sh` so patches can be applied explicitly.
- Add optional candidate dump instrumentation controlled by
  `CUFLYE_CANDIDATE_DUMP`.
- Add runner support for candidate dump paths.
- Add candidate dump canonical diff tooling.
- Validate on DGX with the toy HiFi fixture.

## Out of Scope

- CUDA kernels.
- Backend replacement.
- Flye graph algorithm changes.
- Default behavior changes when candidate dumping is disabled.
- Vendoring the full Flye source tree.

## Deliverables

- `patches/flye/2.9.6/0001-cuflye-candidate-dump.patch`
- `scripts/build_flye_cpu.sh --apply-patches`
- `scripts/run_flye_fixture.sh --candidate-dump PATH`
- `tools/diff_candidate_dumps.py`
- DGX proof that two deterministic candidate dumps match after canonical
  sorting.

## Acceptance Gates

- Unpatched M0 build path remains available.
- Patched Flye builds on DGX with `--apply-patches`.
- Normal run without `CUFLYE_CANDIDATE_DUMP` still passes M0 artifact diff.
- Candidate dump run emits TSV records with stable columns:
  `query_id`, `query_pos`, `kmer`, `target_id`, `target_pos`, `target_strand`.
- Two deterministic candidate dumps compare as `match`.
- No large candidate dump file is committed.

## Execution Checklist

- [x] Add patch overlay directory.
- [x] Add candidate dump patch.
- [x] Extend build script patch application.
- [x] Extend fixture runner with candidate dump support.
- [x] Add candidate dump diff tool.
- [x] Build patched Flye on DGX.
- [x] Run two deterministic candidate dump fixtures.
- [x] Diff candidate dumps.
- [x] Run normal M0 artifact diff against patched build.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` against cuFlye commit
`1458421209821ff27f1334406a0ab2337d839130` and upstream Flye commit
`886b8c17412cdf3a2868a28237bca6c5ad1da156`.

Patched build proof:

- Build manifest: `out/m1a/build_manifest.json`
- Applied patch: `patches/flye/2.9.6/0001-cuflye-candidate-dump.patch`

Candidate oracle proof:

- Run A: `out/m1a/runs/toy-candidate-a/candidates.tsv`
- Run B: `out/m1a/runs/toy-candidate-b/candidates.tsv`
- Records per run: `29035928`
- Raw TSV SHA-256 per run:
  `5e55b79e3cda21ce4d7e5e101a65f30b8fa9c3ba50b542faadbbb27d5c4bfebd`
- Canonical candidate SHA-256 per run:
  `97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b`
- Candidate diff report:
  `out/m1a/runs/toy-candidate-a-vs-b.candidate-diff.json`
- Candidate diff status: `match`

Behavioral regression proof:

- Candidate-run artifact diff:
  `out/m1a/runs/toy-candidate-a-vs-b.artifact-diff.json`
- Normal no-dump artifact diff:
  `out/m1a/runs/toy-normal-a-vs-b.artifact-diff.json`
- Both artifact diff reports returned `match` for all M0 tracked Flye outputs.

Tracked compact proof:

- `tests/golden/toy-hifi-candidate-dgx-aarch64.json`
