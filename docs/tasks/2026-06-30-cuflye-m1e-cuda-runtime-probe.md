# Task Card: cuFlye M1e CUDA Runtime Probe

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Add and validate a standalone CUDA runtime probe before implementing candidate
kernels.

The core question this card must answer is:

```text
Can cuFlye compile, link, and run CUDA Runtime API detection on DGX?
```

## Background

M1d added a safe `cuda` backend stub that fails before producing candidate
records. M1e checks the next dependency: whether this repo can build and run a
CUDA runtime client that queries device properties and memory budget status.

## In Scope

- Add a standalone CUDA runtime probe source file.
- Add a build script for the probe.
- Link against CUDA runtime without requiring `nvcc`.
- Query CUDA driver/runtime versions, device count, selected device properties,
  and memory availability.
- Emit compact JSON.
- Validate on DGX.

## Out of Scope

- CUDA kernels.
- Flye backend replacement.
- Candidate record production.
- Device memory allocation for candidate data.
- Changes to Flye graph or polishing logic.

## Deliverables

- `cuda/cuflye_cuda_probe.cpp`
- `scripts/build_cuda_probe.sh`
- `docs/abi/cuda-runtime-probe-v0.md`
- DGX proof that the probe builds and returns `status=ok`

## Acceptance Gates

- Probe builds on DGX with `g++` and `libcudart`.
- Probe JSON validates with `python3 -m json.tool`.
- Probe reports at least one CUDA device.
- Probe reports selected device name and compute capability.
- Probe reports CUDA runtime and driver versions.
- Probe reports free and total memory.
- Probe reports memory budget satisfied for a small budget.
- No candidate records are emitted.

## Execution Checklist

- [x] Add CUDA runtime probe source.
- [x] Add probe build script.
- [x] Add probe ABI/contract doc.
- [x] Build probe locally where possible or syntax-check scripts.
- [x] Build probe on DGX.
- [x] Run probe on DGX with a memory budget.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` against cuFlye commit
`d08667db341dba4301835f3bb21ccac41a3f0b13`.

Build proof:

- Build script: `scripts/build_cuda_probe.sh`
- Source: `cuda/cuflye_cuda_probe.cpp`
- Build manifest: `out/m1e/d08667d/build_manifest.json`
- Output binary: `out/m1e/d08667d/bin/cuflye-cuda-probe`
- Compiler: `g++`
- CUDA include dir: `/usr/local/cuda/include`
- CUDA runtime lib dir: `/usr/local/cuda/lib64`

Runtime proof:

- JSON report: `out/m1e/d08667d/cuda_probe.ok.json`
- Adapter: `cuda-runtime-probe-v0`
- Status: `ok`
- Device count: `1`
- Device 0: `NVIDIA GB10`
- Compute capability: `12.1`
- CUDA driver version: `13000`
- CUDA runtime version: `13000`
- Total memory: `130594660352` bytes
- Observed free memory: `16678821888` bytes
- Requested memory budget: `1073741824` bytes
- Memory budget satisfied: `true`

Negative budget proof:

- JSON report: `out/m1e/d08667d/cuda_probe.insufficient.json`
- Requested memory budget: `999999999999999` bytes
- Status: `insufficient_memory_budget`
- Memory budget satisfied: `false`

Tracked compact proof:

- `tests/golden/cuda-runtime-probe-dgx-aarch64.json`
