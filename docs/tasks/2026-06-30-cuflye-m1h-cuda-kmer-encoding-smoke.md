# Task Card: cuFlye M1h CUDA K-mer Encoding Smoke Prototype

Status: active

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

- [ ] Add CUDA k-mer encode smoke source.
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
