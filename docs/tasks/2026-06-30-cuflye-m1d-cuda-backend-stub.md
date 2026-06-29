# Task Card: cuFlye M1d CUDA Backend Stub

Status: active

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

- [ ] Add CUDA backend stub patch.
- [ ] Add CUDA stub contract doc.
- [ ] Extend fixture runner with CUDA adapter settings.
- [ ] Build patched Flye on DGX.
- [ ] Run CPU backend artifact regression on DGX.
- [ ] Run CUDA backend fail-fast proof on DGX.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
