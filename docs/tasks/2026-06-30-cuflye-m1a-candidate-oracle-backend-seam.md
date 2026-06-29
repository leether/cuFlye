# Task Card: cuFlye M1a Candidate Oracle and Backend Seam

Status: active

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

- [ ] Add patch overlay directory.
- [ ] Add candidate dump patch.
- [ ] Extend build script patch application.
- [ ] Extend fixture runner with candidate dump support.
- [ ] Add candidate dump diff tool.
- [ ] Build patched Flye on DGX.
- [ ] Run two deterministic candidate dump fixtures.
- [ ] Diff candidate dumps.
- [ ] Run normal M0 artifact diff against patched build.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
