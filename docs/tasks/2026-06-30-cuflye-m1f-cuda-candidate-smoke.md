# Task Card: cuFlye M1f CUDA Candidate Smoke Prototype

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build the first minimal CUDA kernel that emits candidate-record-v1 output.

The core question this card must answer is:

```text
Can a CUDA kernel produce a small ABI-valid candidate TSV that matches the CPU oracle sample?
```

## Background

M1e proved CUDA runtime visibility and memory-budget probing. M1f moves from
runtime detection to a minimal CUDA output path. It deliberately avoids Flye
k-mer lookup and graph changes; the kernel only copies sampled CPU oracle
candidate structs to GPU output so the ABI writer and validation gates can be
exercised.

## In Scope

- Add a standalone CUDA candidate smoke prototype.
- Build it with `nvcc`.
- Read a bounded CPU oracle candidate sample.
- Emit GPU-produced candidate-record-v1 TSV.
- Validate the GPU TSV.
- Diff the GPU TSV against the CPU sample.
- Validate on DGX.

## Out of Scope

- Flye backend integration.
- GPU k-mer lookup.
- Device-side sorting.
- Full candidate dump generation.
- Performance claims.

## Deliverables

- `cuda/cuflye_cuda_candidate_smoke.cu`
- `scripts/build_cuda_candidate_smoke.sh`
- `docs/abi/cuda-candidate-smoke-v0.md`
- DGX proof that GPU TSV validates and matches CPU sample

## Acceptance Gates

- Prototype builds on DGX with `nvcc`.
- Runtime JSON validates with `python3 -m json.tool`.
- GPU output TSV passes `tools/validate_candidate_dump.py`.
- CPU sample TSV passes `tools/validate_candidate_dump.py`.
- `tools/diff_candidate_dumps.py` returns `match`.
- Memory budget gate is recorded.
- No large candidate dump file is committed.

## Execution Checklist

- [ ] Add CUDA candidate smoke source.
- [ ] Add build script.
- [ ] Add ABI/contract doc.
- [ ] Build prototype on DGX with `nvcc`.
- [ ] Generate CPU sample and GPU TSV.
- [ ] Validate CPU sample and GPU TSV.
- [ ] Diff CPU sample and GPU TSV.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
