# Task Card: cuFlye M1i CUDA Read Window Smoke Prototype

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from one query k-mer per fixture row to GPU-generated query windows from
short read sequences.

The core question this card must answer is:

```text
Can CUDA generate candidate-record-v1 rows after sliding Flye-style k-mer windows across bounded read sequences?
```

## Background

M1h proved device-side 2-bit k-mer encoding and standard-form lookup keys from
individual DNA k-mer strings. M1i introduces read-level window generation, the
minimum standalone analogue of Flye `IterKmers`.

## In Scope

- Add a standalone CUDA read-window smoke prototype.
- Add a small fixture with query reads, index k-mers, repetitive k-mers, and
  expected candidate records.
- Build the prototype with `nvcc`.
- Generate a CPU oracle from the fixture.
- Generate GPU candidate records from the same fixture.
- Validate and diff expected, CPU, and GPU candidate TSVs.
- Validate on DGX.

## Out of Scope

- Flye backend integration.
- FASTQ/FASTA parsing.
- Full Flye `VertexIndex` upload.
- Reverse-complement target coordinate transforms during index construction.
- Performance claims.

## Deliverables

- `cuda/cuflye_cuda_read_window_smoke.cu`
- `scripts/build_cuda_read_window_smoke.sh`
- `tests/fixtures/read-window-smoke-v0/`
- `docs/abi/cuda-read-window-smoke-v0.md`
- `tests/golden/cuda-read-window-smoke-dgx-aarch64.json`
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

- [x] Add CUDA read-window smoke source.
- [x] Add build script.
- [x] Add fixture.
- [x] Add ABI/contract doc.
- [x] Build prototype on DGX with `nvcc`.
- [x] Generate CPU oracle and GPU TSV.
- [x] Validate expected, CPU oracle, and GPU TSV.
- [x] Diff expected vs CPU and CPU vs GPU.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `194356325d9a4e9670b9c9b2c04f082ff77afdb4` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

The smoke run used the `read-window-smoke-v0` fixture with `--kmer-size 4`: 2
query reads, 23 generated query windows, 10 index DNA k-mers, and 1 repetitive
DNA k-mer. The CUDA kernel evaluated 230 query/index pairs, generated query
k-mers by sliding read windows on device, computed forward 2-bit k-mer
representations, computed reverse complements and standard-form lookup keys,
skipped repetitive and trivial self hits, and emitted 6 candidate-record-v1
rows.

Expected fixture, CPU oracle, and GPU output all validated with raw SHA-256
`f0ef59dafc1a8efa5f007443d4c11191e3f03b2500c87874b40fa89f2803010d`; expected
vs CPU diff and CPU vs GPU diff both returned `match`.

Proof paths:

- Build manifest: `out/m1i/1943563/build_manifest.json`
- Runtime JSON: `out/m1i/1943563/cuda-read-window-smoke.json`
- Expected validator: `out/m1i/1943563/expected.validator.json`
- CPU validator: `out/m1i/1943563/cpu-oracle.validator.json`
- GPU validator: `out/m1i/1943563/gpu-candidates.validator.json`
- Expected vs CPU diff: `out/m1i/1943563/expected-vs-cpu.candidate-diff.json`
- CPU vs GPU diff: `out/m1i/1943563/cpu-vs-gpu.candidate-diff.json`
- Compact golden proof: `tests/golden/cuda-read-window-smoke-dgx-aarch64.json`

Negative budget gate also passed: `--memory-budget-bytes 1` failed before GPU
allocation with `CUDA read window smoke memory budget is smaller than required
device allocation`.
