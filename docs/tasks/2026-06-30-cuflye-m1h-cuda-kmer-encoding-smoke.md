# Task Card: cuFlye M1h CUDA K-mer Encoding Smoke Prototype

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Remove the M1g integer lookup shortcut and make CUDA compute Flye-style k-mer
representations and standard-form lookup keys from DNA strings.

The core question this card must answer is:

```text
Can a CUDA kernel compute Flye-compatible 2-bit k-mers and standard forms before generating candidate-record-v1 rows?
```

## Background

M1g proved GPU-side equality join over a flattened k-mer index fixture, but the
fixture still supplied `query_kmer` and `lookup_kmer` as integers. M1h moves one
semantic step closer to Flye by using DNA k-mer sequences as input and computing
the forward k-mer, reverse complement, and standard-form lookup key on GPU.

## In Scope

- Add a standalone CUDA k-mer encode smoke prototype.
- Add a small fixture with query k-mer strings, index k-mer strings, repetitive
  k-mer strings, and expected candidate records.
- Build the prototype with `nvcc`.
- Generate a CPU oracle from the fixture.
- Generate GPU candidate records from the same fixture.
- Validate and diff expected, CPU, and GPU candidate TSVs.
- Validate on DGX.

## Out of Scope

- Flye backend integration.
- FASTQ/FASTA parsing.
- Sliding windows across full reads.
- Full Flye `VertexIndex` upload.
- Reverse-complement coordinate transforms for index construction.
- Performance claims.

## Deliverables

- `cuda/cuflye_cuda_kmer_encode_smoke.cu`
- `scripts/build_cuda_kmer_encode_smoke.sh`
- `tests/fixtures/kmer-encode-smoke-v0/`
- `docs/abi/cuda-kmer-encode-smoke-v0.md`
- `tests/golden/cuda-kmer-encode-smoke-dgx-aarch64.json`
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

- [x] Add CUDA k-mer encode smoke source.
- [x] Add build script.
- [x] Add fixture.
- [x] Add ABI/contract doc.
- [x] Build prototype on DGX with `nvcc`.
- [x] Generate CPU oracle and GPU TSV.
- [x] Validate expected, CPU oracle, and GPU TSV.
- [x] Diff expected vs CPU and CPU vs GPU.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `bb8f54017d330e09dc80a6cc0d073104abde2c82` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

The smoke run used the `kmer-encode-smoke-v0` fixture with `--kmer-size 4`: 6
query DNA k-mers, 10 index DNA k-mers, and 1 repetitive DNA k-mer. The CUDA
kernel evaluated 60 query/index pairs, computed forward 2-bit k-mer
representations, computed reverse complements and standard-form lookup keys,
skipped repetitive and trivial self hits, and emitted 6 candidate-record-v1
rows.

Expected fixture, CPU oracle, and GPU output all validated with raw SHA-256
`c07761a6cf2dca8d2c3d511b938b454d8e272e0f035a147a59674f1c1c2c67ad`; expected
vs CPU diff and CPU vs GPU diff both returned `match`.

Proof paths:

- Build manifest: `out/m1h/bb8f540/build_manifest.json`
- Runtime JSON: `out/m1h/bb8f540/cuda-kmer-encode-smoke.json`
- Expected validator: `out/m1h/bb8f540/expected.validator.json`
- CPU validator: `out/m1h/bb8f540/cpu-oracle.validator.json`
- GPU validator: `out/m1h/bb8f540/gpu-candidates.validator.json`
- Expected vs CPU diff: `out/m1h/bb8f540/expected-vs-cpu.candidate-diff.json`
- CPU vs GPU diff: `out/m1h/bb8f540/cpu-vs-gpu.candidate-diff.json`
- Compact golden proof: `tests/golden/cuda-kmer-encode-smoke-dgx-aarch64.json`

Negative budget gate also passed: `--memory-budget-bytes 1` failed before GPU
allocation with `CUDA k-mer encode smoke memory budget is smaller than required
device allocation`.
