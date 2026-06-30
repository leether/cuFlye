# Task Card: cuFlye M1f CUDA Candidate Smoke Prototype

Status: completed

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
- `tests/golden/cuda-candidate-smoke-dgx-aarch64.json`
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

- [x] Add CUDA candidate smoke source.
- [x] Add build script.
- [x] Add ABI/contract doc.
- [x] Build prototype on DGX with `nvcc`.
- [x] Generate CPU sample and GPU TSV.
- [x] Validate CPU sample and GPU TSV.
- [x] Diff CPU sample and GPU TSV.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `23bc8f7d8608d6d7a2e008c58ece516708f5d6e4` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

The smoke run sampled 256 records from the M1b toy CPU oracle dump and emitted
the same candidate-record-v1 TSV through a CUDA kernel output path. CPU sample
and GPU output both validated with raw SHA-256
`bb486a72536cfd97978db29354b4f28220e62e4f9f4fa7b9a1b84ecc5182200b`; candidate
diff status was `match`.

Proof paths:

- Build manifest: `out/m1f/23bc8f7/build_manifest.json`
- Runtime JSON: `out/m1f/23bc8f7/cuda-candidate-smoke.json`
- CPU validator: `out/m1f/23bc8f7/cpu-sample.validator.json`
- GPU validator: `out/m1f/23bc8f7/gpu-candidates.validator.json`
- Candidate diff: `out/m1f/23bc8f7/cpu-vs-gpu.candidate-diff.json`
- Compact golden proof: `tests/golden/cuda-candidate-smoke-dgx-aarch64.json`

Negative budget gate also passed: `--memory-budget-bytes 1` failed before GPU
allocation with `CUDA candidate smoke memory budget is smaller than required
device allocation`.
