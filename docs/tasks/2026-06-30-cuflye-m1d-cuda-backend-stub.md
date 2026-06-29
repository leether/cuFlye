# Task Card: cuFlye M1d CUDA Backend Stub

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Add the first explicit CUDA backend adapter path without implementing CUDA
kernels.

The core question this card must answer is:

```text
Can cuFlye select a CUDA candidate backend, report adapter settings, and fail safely?
```

## Background

M1c defined the candidate-record ABI and validator. Before writing CUDA kernels,
cuFlye needs a backend adapter path that is selectable, observable, and unable to
silently fall back to CPU. M1d adds that path as a fail-fast stub.

## In Scope

- Add `CUFLYE_CANDIDATE_BACKEND=cuda` as an accepted backend selector.
- Add CUDA stub adapter settings:
  - `CUFLYE_CUDA_DEVICE`
  - `CUFLYE_CUDA_MEMORY_BUDGET_BYTES`
- Extend the fixture runner with `--cuda-device` and
  `--cuda-memory-budget-bytes`.
- Fail fast with a clear "kernel not implemented" error.
- Prove CPU backend output remains unchanged.
- Validate on DGX.

## Out of Scope

- CUDA kernels.
- CUDA runtime linking.
- Device memory allocation.
- GPU property queries from C++.
- Candidate ABI production from CUDA.
- Downstream Flye changes.

## Deliverables

- `patches/flye/2.9.6/0003-cuflye-cuda-backend-stub.patch`
- `docs/abi/cuda-candidate-backend-v0.md`
- runner support for `--cuda-device` and `--cuda-memory-budget-bytes`
- DGX proof that `--candidate-backend cuda` fails with stub metadata
- DGX proof that CPU backend artifacts still match the oracle

## Acceptance Gates

- Patch series builds on DGX.
- `CUFLYE_CANDIDATE_BACKEND=cpu` still runs successfully.
- CPU backend artifacts match an earlier CPU oracle run.
- `CUFLYE_CANDIDATE_BACKEND=cuda` exits non-zero.
- CUDA stub error includes device id and memory budget.
- No CUDA output is treated as valid candidate data.

## Execution Checklist

- [x] Add CUDA backend stub patch.
- [x] Add CUDA stub contract doc.
- [x] Extend fixture runner with CUDA adapter settings.
- [x] Build patched Flye on DGX.
- [x] Run CPU backend artifact regression on DGX.
- [x] Run CUDA backend fail-fast proof on DGX.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` against cuFlye commit
`67ee037f0e4c7ca3da77ae7fbc3a6db13ba97d17` and upstream Flye commit
`886b8c17412cdf3a2868a28237bca6c5ad1da156`.

Patched build proof:

- Build manifest: `out/m1d/67ee037/build_manifest.json`
- Patch prefix detected before build:
  `0002-cuflye-candidate-backend-seam.patch`
- Applied patch series includes:
  - `0001-cuflye-candidate-dump.patch`
  - `0002-cuflye-candidate-backend-seam.patch`
  - `0003-cuflye-cuda-backend-stub.patch`

CPU regression proof:

- Run: `out/m1d/67ee037/runs/toy-cpu`
- Compared against: `out/m1b/f311460/runs/toy-cpu`
- Artifact diff report:
  `out/m1d/67ee037/runs/toy-cpu-vs-m1b.artifact-diff.json`
- Artifact diff status: `match`

CUDA stub proof:

- Run: `out/m1d/67ee037/runs/toy-cuda-stub`
- Backend: `cuda`
- `CUFLYE_CUDA_DEVICE=0`
- `CUFLYE_CUDA_MEMORY_BUDGET_BYTES=1073741824`
- Expected failure:
  `cuFlye CUDA candidate backend selected; adapter=stub; CUFLYE_CUDA_DEVICE=0; CUFLYE_CUDA_MEMORY_BUDGET_BYTES=1073741824; CUDA candidate kernel is not implemented yet`
- Metadata file:
  `out/m1d/67ee037/runs/toy-cuda-stub/run_metadata.pre.json`

Tracked compact proof:

- `tests/golden/toy-hifi-cuda-stub-dgx-aarch64.json`
