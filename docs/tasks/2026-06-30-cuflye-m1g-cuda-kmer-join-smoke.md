# Task Card: cuFlye M1g CUDA K-mer Join Smoke Prototype

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from GPU candidate-record copying to GPU candidate-record generation on a
bounded fixture.

The core question this card must answer is:

```text
Can a CUDA kernel generate a small candidate-record-v1 TSV from query k-mers and a k-mer index fixture?
```

## Background

M1f proved the ABI output path by copying CPU oracle records through a CUDA
kernel. M1g must add real device-side candidate generation logic, but it remains
standalone and deliberately small. It uses explicit query/index TSV fixtures so
the join semantics can be tested without yet embedding CUDA into Flye's
`VertexIndex`.

## In Scope

- Add a standalone CUDA k-mer join smoke prototype.
- Add a small fixture with query k-mers, index entries, repetitive k-mers, and
  expected candidate records.
- Build the prototype with `nvcc`.
- Generate a CPU oracle from the fixture.
- Generate GPU candidate records from the same fixture.
- Validate and diff expected, CPU, and GPU candidate TSVs.
- Validate on DGX.

## Out of Scope

- Flye backend integration.
- FASTQ/FASTA parsing.
- Device-side 2-bit k-mer encoding.
- Device-side `Kmer::standardForm()`.
- Full Flye `VertexIndex` upload.
- Performance claims.

## Deliverables

- `cuda/cuflye_cuda_kmer_join_smoke.cu`
- `scripts/build_cuda_kmer_join_smoke.sh`
- `tests/fixtures/kmer-join-smoke-v0/`
- `docs/abi/cuda-kmer-join-smoke-v0.md`
- `tests/golden/cuda-kmer-join-smoke-dgx-aarch64.json`
- DGX proof that GPU TSV validates and matches CPU oracle and expected fixture

## Acceptance Gates

- Prototype builds on DGX with `nvcc`.
- Runtime JSON validates with `python3 -m json.tool`.
- Expected fixture TSV passes `tools/validate_candidate_dump.py`.
- CPU oracle TSV passes `tools/validate_candidate_dump.py`.
- GPU output TSV passes `tools/validate_candidate_dump.py`.
- `tools/diff_candidate_dumps.py` returns `match` for expected vs CPU.
- `tools/diff_candidate_dumps.py` returns `match` for CPU vs GPU.
- Memory budget gate is recorded.
- No large generated output file is committed.

## Execution Checklist

- [x] Add CUDA k-mer join smoke source.
- [x] Add build script.
- [x] Add fixture.
- [x] Add ABI/contract doc.
- [x] Build prototype on DGX with `nvcc`.
- [x] Generate CPU oracle and GPU TSV.
- [x] Validate expected, CPU oracle, and GPU TSV.
- [x] Diff expected vs CPU and CPU vs GPU.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `2d83322bf70dae9471f9d1272bd8a4d832f0361d` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

The smoke run used the `kmer-join-smoke-v0` fixture: 6 query k-mers, 10 index
entries, and 1 repetitive lookup k-mer. The CUDA kernel evaluated 60 query/index
pairs, skipped repetitive and trivial self hits, and emitted 6
candidate-record-v1 rows.

Expected fixture, CPU oracle, and GPU output all validated with raw SHA-256
`c07761a6cf2dca8d2c3d511b938b454d8e272e0f035a147a59674f1c1c2c67ad`; expected
vs CPU diff and CPU vs GPU diff both returned `match`.

Proof paths:

- Build manifest: `out/m1g/2d83322/build_manifest.json`
- Runtime JSON: `out/m1g/2d83322/cuda-kmer-join-smoke.json`
- Expected validator: `out/m1g/2d83322/expected.validator.json`
- CPU validator: `out/m1g/2d83322/cpu-oracle.validator.json`
- GPU validator: `out/m1g/2d83322/gpu-candidates.validator.json`
- Expected vs CPU diff: `out/m1g/2d83322/expected-vs-cpu.candidate-diff.json`
- CPU vs GPU diff: `out/m1g/2d83322/cpu-vs-gpu.candidate-diff.json`
- Compact golden proof: `tests/golden/cuda-kmer-join-smoke-dgx-aarch64.json`

Negative budget gate also passed: `--memory-budget-bytes 1` failed before GPU
allocation with `CUDA k-mer join smoke memory budget is smaller than required
device allocation`.
