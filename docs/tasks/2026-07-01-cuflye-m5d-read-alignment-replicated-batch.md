# Task Card: cuFlye M5d Read Alignment Replicated Batch

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M5c single-read correctness benchmark into a replicated-batch CUDA
occupancy test without changing the `read-alignment-v1` representative oracle.

The core question this card must answer is:

```text
If the same bounded read-alignment chain DP work is available many times in one
launch, can CUDA beat the C++ CPU baseline for the benchmark hotpath?
```

## Background

M5c proved CUDA correctness for toy-hifi read `200`, but the fixture has only
four edge-overlap records. The GPU path was much slower because one tiny read
does not provide enough parallel work. M5d adds a controlled
`--replicate-fixture` benchmark mode: it runs the same fixture contract many
independent times, keeps only the first representative TSV for oracle diff, and
records batch timing in JSON.

## In Scope

- Add `--replicate-fixture N` to the M5c binary.
- CPU backend repeats the same fixture work `N` times.
- CUDA backend packs `N` copies and launches one block per logical fixture.
- Preserve the first representative output as `read-alignment-v1`.
- Validate representative CPU and CUDA outputs against the M5b oracle.
- Record total/core timing and scoped speedup for the replicated batch.
- Fail closed on CUDA memory-budget violations for the full replicated buffer.

## Out of Scope

- No claim that replicated fixture timing equals real multi-read Flye timing.
- No real multi-read fixture harvest.
- No graph mutation consumption.
- No default GPU mode.
- No end-to-end Flye speedup claim.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc` or `cudaFree` outside approved RAII
  wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Bound and check replicated buffer sizes before allocation.

## Deliverables

- `--replicate-fixture` CLI and JSON fields in
  `cuda/cuflye_cuda_read_alignment_chain_replay.cu`
- Updated ABI documentation for representative-output batch behavior
- DGX proof manifest under `tests/golden/`
- Roadmap update with scoped speedup or blocker

## Acceptance Gates

- [x] CUDA replicated batch builds on DGX.
- [x] Representative CPU output validates as `read-alignment-v1`.
- [x] Representative CUDA output validates as `read-alignment-v1`.
- [x] CPU and CUDA representative outputs canonical-diff `match` against the
      M5b oracle.
- [x] Replicated-batch JSON records `batch_size` and `total_input_records`.
- [x] CUDA batch total or core timing beats CPU for a scoped replicated-batch
      proof, or the blocker is recorded.
- [x] Memory-budget negative gate uses the replicated buffer size.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

DGX proof:
`/tmp/cuflye-m5d-proof-20260630T224019Z/out/m5d/dgx-read-alignment-replicated-batch-proof.json`

Golden manifest:
`tests/golden/cuflye-m5d-read-alignment-replicated-batch-dgx-aarch64.json`

Selected proof:

- Host: `edgexpert-45d2` (`aarch64`)
- GPU: `NVIDIA GB10`, CUDA arch `sm_121`
- Fixture: M5b toy-hifi read `200`, replicated `4096` times
- Total edge-overlap records processed per benchmark run: `16384`
- Representative `read-alignment-v1` output records: `3`
- CPU, CUDA, and oracle canonical SHA-256:
  `c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802`
- CPU vs oracle diff: `match`
- CUDA vs oracle diff: `match`
- CPU vs CUDA diff: `match`
- Warmup runs: `5`
- Timed runs: `200`
- CPU mean total/core before JSON: `1.031995 ms`
- CUDA mean total before JSON: `0.323783 ms`
- CUDA mean kernel/core: `0.030339 ms`
- CUDA total speedup vs CPU: `3.187304x`
- CUDA kernel/core speedup vs CPU core: `34.015459x`
- CUDA required bytes for selected replicated batch: `2916353`
- Memory-budget negative gate: `budget=1`, rejected before writing success
  JSON/TSV.

Conclusion: this is the first read-alignment chain DP proof where CUDA beats
CPU, but the claim is limited to a controlled replicated batch. It demonstrates
that the GPU path can win once there is enough parallel chain-DP work; it does
not yet prove real multi-read Flye acceleration.
