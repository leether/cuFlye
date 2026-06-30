# Task Card: cuFlye M1e CUDA Runtime Probe

Status: active

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

- [ ] Add CUDA runtime probe source.
- [ ] Add probe build script.
- [ ] Add probe ABI/contract doc.
- [ ] Build probe locally where possible or syntax-check scripts.
- [ ] Build probe on DGX.
- [ ] Run probe on DGX with a memory budget.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
