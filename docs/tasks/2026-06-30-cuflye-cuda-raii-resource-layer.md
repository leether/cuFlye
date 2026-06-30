# cuFlye CUDA RAII Resource Layer

Status: completed

Date: 2026-06-30

## Goal

Replace direct CUDA resource ownership in standalone CUDA prototypes with a
small move-only RAII layer before reusable M2 backend code is added.

## Context

The memory ownership scan found no direct CPU heap allocation APIs in cuFlye
business logic, but it did find direct `cudaMalloc`/`cudaFree` in M1 smoke
prototypes and direct CUDA event create/destroy calls in the candidate-core
benchmark.

Those calls were acceptable for bounded proof tools, but they should not become
the ownership pattern for the integrated candidate backend.

## Allowed Scope

- Add a header-only CUDA RAII utility under `cuda/`.
- Refactor standalone CUDA prototypes to use the utility for device buffers.
- Refactor the benchmark to use the utility for CUDA events.
- Keep kernel inputs as non-owning raw pointers obtained from wrapper `.get()`.
- Preserve existing CLI flags, JSON fields, TSV output, and kernel semantics.

## Excluded Scope

- No Flye patch changes.
- No new CUDA streams or host-pinned memory.
- No asynchronous execution model.
- No benchmark claim changes.
- No build-system split into a shared CUDA library yet.

## Deliverables

- `cuda/cuflye_cuda_raii.hpp`
- `cuda/cuflye_cuda_candidate_smoke.cu` uses `DeviceBuffer`.
- `cuda/cuflye_cuda_kmer_join_smoke.cu` uses `DeviceBuffer`.
- `cuda/cuflye_cuda_kmer_encode_smoke.cu` uses `DeviceBuffer`.
- `cuda/cuflye_cuda_read_window_smoke.cu` uses `DeviceBuffer`.
- `cuda/cuflye_cuda_candidate_core_bench.cu` uses `DeviceBuffer` and
  `CudaEvent`.

## Acceptance Gates

- Direct CUDA allocation and event lifetime APIs appear only in
  `cuda/cuflye_cuda_raii.hpp`.
- No direct CPU heap allocation expressions are introduced.
- No raw owning `device* = nullptr` pointer variables remain in CUDA prototype
  `main` functions.
- Local static checks pass.
- DGX CUDA build/run is still required before treating this as runtime-proven.

## Scan Commands

```sh
rg -n "cuda(Malloc|Free|HostAlloc|FreeHost|MallocHost|StreamCreate|StreamDestroy|EventCreate|EventDestroy)\b" \
  cuda patches/flye -S

rg -n "\bnew\b|delete\s*(\(|\[)|delete\s+[^;=]|\b(malloc|calloc|realloc|free)\s*\(" \
  cuda patches/flye scripts bench tools -S

rg -n "\b[A-Za-z_][A-Za-z0-9_:<>]*\s*\*\s*device[A-Za-z0-9_]*\s*=\s*nullptr|cudaEvent_t\s+[A-Za-z0-9_]+\s*=\s*nullptr" \
  cuda/*.cu cuda/*.cpp -S
```

## Findings

CUDA resource APIs:

- `cudaMalloc`, `cudaFree`, `cudaEventCreate`, and `cudaEventDestroy` appear
  only in `cuda/cuflye_cuda_raii.hpp`.
- No direct CUDA resource API calls remain in Flye patches.

CPU heap allocation APIs:

- No direct `new`, `delete` expression, `malloc`, `calloc`, `realloc`, or
  `free(` hits in the scanned scope.

Owning CUDA pointer declarations:

- No `device* = nullptr` pointer variables or raw `cudaEvent_t = nullptr`
  variables remain in CUDA prototype `main` functions.

Local verification:

- `git diff --check` passed.
- Static resource scans passed with the findings above.
- Local `nvcc` was not installed on the Mac workspace, so CUDA compilation and
  smoke execution were not run in this turn.

## Follow-Up

M2 backend code should use this RAII layer or a stricter successor. If M2 needs
host-pinned memory or streams, add move-only wrappers here before introducing
those resources into backend code.
