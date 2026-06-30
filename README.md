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

## M1d CUDA Backend Stub

The CUDA backend selector exists but intentionally fails until a real kernel is
implemented:

```sh
scripts/build_flye_cpu.sh --apply-patches --clean
scripts/run_flye_fixture.sh --out-dir out/m1d/runs/toy-cuda-stub \
  --candidate-backend cuda \
  --cuda-device 0 \
  --cuda-memory-budget-bytes 1073741824
```

Expected stderr includes `adapter=stub`, the requested CUDA device, the memory
budget, and `CUDA candidate kernel is not implemented yet`. This path must never
silently fall back to CPU.

## M1e CUDA Runtime Probe

Before writing kernels, build and run the standalone CUDA runtime probe:

```sh
scripts/build_cuda_probe.sh
out/m1e/bin/cuflye-cuda-probe \
  --device 0 \
  --memory-budget-bytes 1073741824 \
  --json-output out/m1e/cuda_probe.json
```

The probe links `libcudart`, queries CUDA driver/runtime versions, selected
device properties, and free/total memory. It emits no candidate records.

## M1f CUDA Candidate Smoke

The first CUDA kernel prototype emits a small candidate-record-v1 TSV from a CPU
oracle sample:

```sh
scripts/build_cuda_candidate_smoke.sh --arch sm_121
out/m1f/bin/cuflye-cuda-candidate-smoke \
  --input-cpu-tsv out/m1b/f311460/runs/toy-default/candidates.tsv \
  --cpu-sample-output out/m1f/cpu-sample.tsv \
  --output-tsv out/m1f/gpu-candidates.tsv \
  --records 256 \
  --memory-budget-bytes 1048576 \
  --json-output out/m1f/cuda-candidate-smoke.json
tools/validate_candidate_dump.py out/m1f/gpu-candidates.tsv --expect-records 256
tools/diff_candidate_dumps.py out/m1f/cpu-sample.tsv out/m1f/gpu-candidates.tsv
```

This is not Flye acceleration yet. It proves that a CUDA kernel can produce
candidate ABI records that pass the same validator and diff gates as CPU oracle
data.

## M1g CUDA K-mer Join Smoke

The first GPU-generated candidate prototype performs a bounded k-mer equality
join over an explicit fixture:

```sh
scripts/build_cuda_kmer_join_smoke.sh --arch sm_121
out/m1g/bin/cuflye-cuda-kmer-join-smoke \
  --queries-tsv tests/fixtures/kmer-join-smoke-v0/queries.tsv \
  --index-tsv tests/fixtures/kmer-join-smoke-v0/index.tsv \
  --repetitive-kmers-tsv tests/fixtures/kmer-join-smoke-v0/repetitive-kmers.tsv \
  --cpu-output-tsv out/m1g/cpu-oracle.tsv \
  --output-tsv out/m1g/gpu-candidates.tsv \
  --memory-budget-bytes 1048576 \
  --json-output out/m1g/cuda-kmer-join-smoke.json
tools/diff_candidate_dumps.py \
  tests/fixtures/kmer-join-smoke-v0/expected.candidates.tsv \
  out/m1g/cpu-oracle.tsv
tools/diff_candidate_dumps.py out/m1g/cpu-oracle.tsv out/m1g/gpu-candidates.tsv
```

This still does not parse Flye reads or replace the Flye backend stub. It proves
that device code can generate ABI-valid candidate records from query/index
inputs using Flye-like equality-join and trivial-hit filtering semantics.

## Licensing

Original code in this repository is BSD-3-Clause by default.

Files copied from or substantially derived from NVIDIA GenomeWorks must remain
Apache-2.0. Use file-level SPDX identifiers to make mixed-license boundaries
explicit.

See `LICENSE`, `LICENSES/`, and `THIRD_PARTY_NOTICES.md`.
