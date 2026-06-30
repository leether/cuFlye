# cuFlye CUDA Runtime Probe v0

Status: active

Introduced: M1e

Scope: standalone CUDA runtime detection before CUDA candidate kernels exist.

## Purpose

M1e verifies that cuFlye can compile and link a CUDA Runtime API client on DGX,
select a device, query device properties, and check available memory against a
requested budget.

This is still not a candidate-generation backend. It emits no candidate records
and does not feed Flye's graph logic.

## Binary

The probe source is:

```text
cuda/cuflye_cuda_probe.cpp
```

Build command:

```sh
scripts/build_cuda_probe.sh
```

Default output:

```text
out/m1e/bin/cuflye-cuda-probe
```

## Runtime Contract

The probe accepts:

- `--device N`, default from `CUFLYE_CUDA_DEVICE`, otherwise `0`;
- `--memory-budget-bytes N`, default from `CUFLYE_CUDA_MEMORY_BUDGET_BYTES`;
- `--json-output PATH`.

It must:

- link against `libcudart`;
- call `cudaRuntimeGetVersion`;
- call `cudaDriverGetVersion`;
- call `cudaGetDeviceCount`;
- call `cudaSetDevice`;
- call `cudaGetDeviceProperties`;
- call `cudaMemGetInfo`;
- return non-zero if the requested memory budget is not satisfied;
- return non-zero if no CUDA device is available.

## JSON Fields

Required fields:

- `adapter`: `cuda-runtime-probe-v0`;
- `status`: `ok` or `insufficient_memory_budget`;
- `device`;
- `device_count`;
- `device_name`;
- `compute_capability`;
- `cuda_driver_version`;
- `cuda_runtime_version`;
- `global_memory_bytes`;
- `memory_free_bytes`;
- `memory_total_bytes`;
- `memory_budget_bytes`;
- `memory_budget_satisfied`;
- `multi_processor_count`;
- `warp_size`;
- `max_threads_per_block`;
- `shared_memory_per_block_bytes`;
- `registers_per_block`;
- `memory_bus_width_bits`.

## Boundary

M1e is allowed to prove CUDA runtime visibility only. The first real CUDA
candidate backend must still pass `candidate-record-v1` validation and candidate
diff against the CPU oracle before downstream Flye stages can use it.
