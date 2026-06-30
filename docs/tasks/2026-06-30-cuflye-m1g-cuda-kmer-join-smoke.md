# Task Card: cuFlye M1g CUDA K-mer Join Smoke Prototype

Status: active

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

- [ ] Add CUDA k-mer join smoke source.
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
