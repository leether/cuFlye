# cuFlye

`cuFlye` is an unofficial, Flye-compatible CUDA acceleration project for
long-read genome assembly.

The target is not a clean-room GPU assembler. The target is a Flye-compatible
fork that keeps Flye's CLI, stage contracts, intermediate artifacts, and CPU
implementation as the reference oracle while moving selected hotspot kernels to
CUDA.

## Current Materials

- `CUDA_FLYE_DESIGN.md`: CUDA backend architecture and milestones.
- `GENOMEWORKS_NOTES.md`: source-level notes from NVIDIA GenomeWorks modules.
- `docs/tasks/`: Task Cards for bounded implementation slices.
- `scripts/`, `tools/`, `bench/`: M0 CPU oracle, canonical diff, and profiling
  harness.
- `upstream-flye/`: local research clone of Flye, ignored by this root repo.
- `GenomeWorks/`: local research clone of NVIDIA GenomeWorks, ignored by this
  root repo.

## M0 CPU Oracle

The first implementation milestone is a CPU reference harness. On a target
Linux/DGX host:

```sh
scripts/build_flye_cpu.sh --fetch-upstream
scripts/run_flye_fixture.sh --out-dir out/m0/runs/toy-a
scripts/run_flye_fixture.sh --out-dir out/m0/runs/toy-b
tools/diff_flye_runs.py out/m0/runs/toy-a out/m0/runs/toy-b
bench/profile_flye_cpu.sh --profile-dir out/m0/profiles/toy-hifi --threads 8
```

Generated runs and profiles live under `out/` and are intentionally ignored.

## M1a Candidate Oracle

Candidate dump instrumentation is stored as a Flye patch and must be enabled
explicitly:

```sh
scripts/build_flye_cpu.sh --apply-patches --clean
scripts/run_flye_fixture.sh --out-dir out/m1a/runs/toy-a \
  --candidate-dump out/m1a/runs/toy-a/candidates.tsv
scripts/run_flye_fixture.sh --out-dir out/m1a/runs/toy-b \
  --candidate-dump out/m1a/runs/toy-b/candidates.tsv
tools/diff_candidate_dumps.py \
  out/m1a/runs/toy-a/candidates.tsv \
  out/m1a/runs/toy-b/candidates.tsv
```

The patch does not change default Flye behavior when `CUFLYE_CANDIDATE_DUMP` is
unset.

## M1b Candidate Backend Seam

The candidate backend selector is intentionally explicit. The default backend is
the original CPU implementation, and the only accepted explicit value is
currently `cpu`:

```sh
scripts/build_flye_cpu.sh --apply-patches --clean
scripts/run_flye_fixture.sh --out-dir out/m1b/runs/toy-default \
  --candidate-dump out/m1b/runs/toy-default/candidates.tsv
scripts/run_flye_fixture.sh --out-dir out/m1b/runs/toy-cpu \
  --candidate-backend cpu \
  --candidate-dump out/m1b/runs/toy-cpu/candidates.tsv
tools/diff_candidate_dumps.py \
  out/m1b/runs/toy-default/candidates.tsv \
  out/m1b/runs/toy-cpu/candidates.tsv
```

Unknown `CUFLYE_CANDIDATE_BACKEND` values fail fast. CUDA work should add a new
backend behind this selector and prove candidate-list equivalence before
touching downstream graph logic.

## M1c Candidate ABI

The candidate record contract is defined in
`docs/abi/candidate-record-v1.md`. Validate candidate dumps before comparing
backends:

```sh
tools/validate_candidate_dump.py out/m1b/f311460/runs/toy-default/candidates.tsv \
  --expect-records 29035928 \
  --expect-raw-sha256 5e55b79e3cda21ce4d7e5e101a65f30b8fa9c3ba50b542faadbbb27d5c4bfebd
tools/validate_candidate_dump.py out/m1b/f311460/runs/toy-default/candidates.tsv \
  --compute-canonical-sha256 \
  --expect-canonical-sha256 97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b
```

The ABI gate checks schema, integer ranges, strand encoding, record count, raw
hash, and optional canonical hash. CUDA candidate prototypes must pass this gate
and `tools/diff_candidate_dumps.py` against the CPU oracle before downstream
Flye stages are considered.

## Licensing

Original code in this repository is BSD-3-Clause by default.

Files copied from or substantially derived from NVIDIA GenomeWorks must remain
Apache-2.0. Use file-level SPDX identifiers to make mixed-license boundaries
explicit.

See `LICENSE`, `LICENSES/`, and `THIRD_PARTY_NOTICES.md`.
