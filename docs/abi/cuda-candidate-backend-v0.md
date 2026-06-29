# cuFlye CUDA Candidate Backend Stub v0

Status: active

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

## Next Contract

The next CUDA milestone should replace this stub with a real backend adapter
that:

- queries CUDA device properties;
- enforces a device-memory budget;
- emits candidate-record-v1 compatible records;
- passes `tools/validate_candidate_dump.py`;
- passes `tools/diff_candidate_dumps.py` against the CPU oracle.
