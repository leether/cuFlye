# Task Card: cuFlye M5i Persistent Bulk Output Copy

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Remove the dominant device-to-host overhead in the M5g/M5h persistent
read-alignment arena by copying output records in bulk per shape group.

The core question this card must answer is:

```text
Can bulk output transfer preserve every per-read oracle diff while reducing the
persistent CUDA read-alignment total time on the larger M5h fixture harvest?
```

## Background

M5h expanded the read-alignment replay proof to `3546` valid toy-hifi fixtures
and `3781` total input records. The CUDA kernel/core path was already
`12.706503x` faster than CPU core work, but total persistent CUDA remained
`55.029972x` slower than CPU because the current persistent runner copied each
fixture's output records separately from device to host. The measured
persistent `device_to_host` time was `18.156663 ms` per timed run.

M5i targets that exact bottleneck without changing kernel semantics.

## In Scope

- Add an explicit persistent CUDA bulk-output mode to
  `cuflye-cuda-read-alignment-chain-replay`.
- Keep default CUDA, batch, heterogeneous, and persistent behavior unchanged.
- Copy one output buffer per shape group from device to host in persistent mode.
- Slice the copied host buffer into the same per-fixture `read-alignment-v1`
  outputs using the existing per-fixture `DeviceSummary` records.
- Compare current persistent mode against bulk-output persistent mode on the
  M5h larger fixture list.
- Validate and canonical-diff all CPU/current persistent/bulk persistent
  outputs against oracle and each other.

## Out of Scope

- No CUDA kernel DP semantic changes.
- No device-side prefix compaction yet.
- No graph mutation consumption.
- No default GPU mode.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No end-to-end Flye acceleration claim.

## C++/CUDA Style Constraints

- Keep standalone CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc`, `cudaFree`, direct owning `new` or
  `delete`, or direct `malloc`/`free`.
- Check copy sizes and offset arithmetic before bulk transfer.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- Explicit CLI flag and JSON execution mode for persistent bulk output.
- Updated ABI documentation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with scoped benefit or blocker.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] CUDA replay binary builds on DGX.
- [x] Bulk-output mode is explicit and requires persistent CUDA arena mode.
- [x] Bulk-output mode runs on the M5h larger fixture list.
- [x] Every selected bulk-output result validates as `read-alignment-v1`.
- [x] Bulk-output outputs canonical-diff `match` against every fixture oracle.
- [x] Bulk-output outputs canonical-diff `match` against current persistent
      outputs.
- [x] Bulk-output timing is compared against current persistent timing and CPU.
- [x] JSON records `cuda_execution_mode=persistent-arena-bulk-output`.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5i-proof-20260701T000634Z`
- Golden manifest:
  `tests/golden/cuflye-m5i-persistent-bulk-output-copy-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`, GPU `NVIDIA GB10`, CUDA arch `sm_121`.
- Fixture source: M5h toy-hifi larger harvest selected fixture list.
- Selected fixtures: `3546`
- Total input records: `3781`
- Output records: `3616`
- Shape groups: `4`

Warm benchmark timing with `5` warmups and `50` timed runs:

```text
cpu_mean_total_before_json_ms=0.333798
cpu_mean_core_ms=0.333798
current_persistent_cuda_mean_total_before_json_ms=17.862780
current_persistent_cuda_mean_kernel_ms=0.025782
current_persistent_cuda_device_to_host_ms=17.680561
bulk_persistent_cuda_mean_total_before_json_ms=0.302834
bulk_persistent_cuda_mean_kernel_ms=0.025953
bulk_persistent_cuda_device_to_host_ms=0.223648
bulk_total_speedup_vs_cpu=1.102247x
bulk_total_speedup_vs_current_persistent=58.985385x
bulk_d2h_speedup_vs_current_persistent_d2h=79.055306x
bulk_core_speedup_vs_cpu_core=12.861634x
```

Every oracle, CPU, current persistent CUDA, and bulk persistent CUDA
per-fixture `read-alignment-v1` output validated and canonical-diffed as
`match` across all `3546` selected fixtures.

Negative gate:

- `--cuda-persistent-bulk-output` without `--cuda-persistent-arena` fails
  closed with
  `--cuda-persistent-bulk-output requires --cuda-persistent-arena`.

Allowed M5i claim:

```text
cuFlye can run the bounded M5h read-alignment chain replay harvest through an
explicit persistent CUDA bulk-output mode faster than the CPU replay baseline
before TSV/JSON emission while preserving every per-read oracle diff.
```

Forbidden M5i claim:

```text
M5i does not prove default GPU mode, Flye graph mutation consumption,
edlib/base realignment replay, or end-to-end Flye acceleration.
```

Plain-language benefit assessment:

```text
This is the first read-alignment replay result where CUDA is faster for the
measured bounded pre-write hot path, not only inside the kernel. The win came
from removing thousands of tiny device-to-host output copies and replacing them
with one output-buffer copy per shape group. The next step is integration
safety: wire this behind a graph-facing dry-run seam before any graph mutation.
```
