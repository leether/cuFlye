# cuFlye Governance: Memory Ownership Rules and Scan

Status: completed

Date: 2026-06-30

Superseded by:

- `2026-06-30-cuflye-cuda-raii-resource-layer.md`

## Goal

Add memory/resource ownership rules to the local coding style and scan existing
cuFlye code for the most common C++ and CUDA leak patterns.

## Scope

Scanned original cuFlye C++/CUDA source, Flye patch files, scripts, tools, and
bench harnesses:

- `cuda/`
- `patches/flye/`
- `scripts/`
- `tools/`
- `bench/`

Generated outputs, upstream clone directories, and third-party source trees are
out of scope.

## Rules Added

- No direct `new`, `delete`, `malloc`, `calloc`, `realloc`, or `free` in
  original cuFlye business logic.
- Raw pointers are non-owning by default.
- Prefer standard containers, stack objects, and Rule of Zero.
- Resource-owning classes must be move-only when Rule of Zero is not possible.
- Reusable CUDA backend code must wrap allocation, stream, and event resources
  in move-only RAII types.
- Standalone M1 smoke prototypes may contain direct CUDA resource calls only as
  temporary proof code; that pattern must not enter M2+ backend integration.

## Scan Commands

```sh
rg -n "\bnew\b|delete\s*(\(|\[)|delete\s+[^;=]|\b(malloc|calloc|realloc|free)\s*\(" \
  cuda patches/flye scripts bench tools -S

rg -n "std::(shared_ptr|unique_ptr|weak_ptr|auto_ptr)|\b(shared_ptr|unique_ptr|weak_ptr|auto_ptr)\b" \
  cuda patches/flye scripts bench tools -S

rg -n "cuda(Malloc|Free|HostAlloc|FreeHost|MallocHost|StreamCreate|StreamDestroy|EventCreate|EventDestroy)\b" \
  cuda patches/flye -S --count-matches
```

## Findings

CPU ownership scan:

- No direct `new`, `delete`, `malloc`, `calloc`, `realloc`, or `free(` hits in
  the scanned scope.

Smart pointer scan:

- No `std::unique_ptr`, `std::shared_ptr`, `std::weak_ptr`, or `std::auto_ptr`
  hits in the scanned scope. This is acceptable for the current code because
  host memory is handled mostly through containers and stack values.

CUDA resource scan:

| File | Matches |
| --- | ---: |
| `cuda/cuflye_cuda_candidate_core_bench.cu` | 20 |
| `cuda/cuflye_cuda_candidate_smoke.cu` | 8 |
| `cuda/cuflye_cuda_kmer_encode_smoke.cu` | 20 |
| `cuda/cuflye_cuda_kmer_join_smoke.cu` | 20 |
| `cuda/cuflye_cuda_read_window_smoke.cu` | 24 |

No CUDA resource API hits were found in `patches/flye/`.

## Interpretation

Current CPU-side leak risk is low under the simple static scan: there are no
direct owning heap APIs in original cuFlye code or Flye patch files.

The main debt is CUDA resource lifetime in standalone M1 prototypes. These files
use direct `cudaMalloc`/`cudaFree`; the benchmark also uses direct CUDA event
create/destroy calls. That is acceptable for bounded smoke tools, but it should
not be copied into the integrated candidate backend.

## Follow-Up

Before M2 CUDA backend code consumes real packed Flye data, add a small
move-only CUDA RAII layer for:

- device buffers;
- optional host-pinned buffers if introduced;
- CUDA events if benchmark timing remains in C++;
- CUDA streams if asynchronous execution is introduced.

The RAII layer should become the only approved location for direct CUDA resource
API calls in reusable backend code.

## Follow-Up Status

Completed in `2026-06-30-cuflye-cuda-raii-resource-layer.md`: the standalone
CUDA prototypes now use `cuda/cuflye_cuda_raii.hpp`, and direct CUDA
allocation/event lifetime APIs are confined to that wrapper.
