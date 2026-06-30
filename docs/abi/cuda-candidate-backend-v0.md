# cuFlye CUDA Candidate Backend Stub v0

Status: superseded by `docs/abi/cuda-candidate-adapter-shell-v0.md`

Introduced: M1d

Scope: backend selection and fail-fast behavior for
`CUFLYE_CANDIDATE_BACKEND=cuda`.

## Purpose

This document defines the first CUDA backend adapter contract. It does not
define a CUDA kernel yet. Its purpose is to make the CUDA path explicit,
observable, and safe before device code exists.

## Current Behavior

When Flye is built with cuFlye patch `0003-cuflye-cuda-backend-stub.patch`,
`CUFLYE_CANDIDATE_BACKEND=cuda` is accepted as a backend selector.

The backend then initializes the stub adapter by reading:

- `CUFLYE_CUDA_DEVICE`, default `0`;
- `CUFLYE_CUDA_MEMORY_BUDGET_BYTES`, default `unbounded`.

After recording those values in the error message, it fails non-zero with:

```text
cuFlye CUDA candidate backend selected; adapter=stub; ...
CUDA candidate kernel is not implemented yet
```

This is intentional. No CUDA candidate records are emitted in M1d.

## Non-Goals

M1d does not:

- link against CUDA runtime libraries;
- allocate device memory;
- query GPU properties from C++;
- emit CUDA candidate records;
- alter the CPU backend;
- silently fall back from CUDA to CPU.

## Required Failure Semantics

The CUDA stub must fail before candidate sorting, chaining, repeat graph logic,
or polishing can run. A failed CUDA stub run is successful only when stderr
contains:

- `CUFLYE_CANDIDATE_BACKEND=cuda` was selected through runner metadata or command
  context;
- `adapter=stub`;
- the requested `CUFLYE_CUDA_DEVICE`;
- the requested `CUFLYE_CUDA_MEMORY_BUDGET_BYTES`;
- `CUDA candidate kernel is not implemented yet`.

## Superseding Contract

M2a replaced this stub with an external packed adapter shell. See
`docs/abi/cuda-candidate-adapter-shell-v0.md`.

The first real candidate backend beyond the shell should:

- query CUDA device properties;
- enforce a device-memory budget;
- emit candidate-record-v1 compatible records;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the CPU oracle.

M1e provides the standalone runtime probe for the first two bullets; see
`docs/abi/cuda-runtime-probe-v0.md`.
