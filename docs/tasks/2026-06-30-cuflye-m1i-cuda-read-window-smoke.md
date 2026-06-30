# Task Card: cuFlye M1i CUDA Read Window Smoke Prototype

Status: active

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

- [ ] Add CUDA read-window smoke source.
- [ ] Add build script.
- [ ] Add fixture.
- [ ] Add ABI/contract doc.
- [ ] Build prototype on DGX with `nvcc`.
- [ ] Generate CPU oracle and GPU TSV.
- [ ] Validate expected, CPU oracle, and GPU TSV.
- [ ] Diff expected vs CPU and CPU vs GPU.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
