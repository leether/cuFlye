# Task Card: cuFlye M5c CUDA Read Alignment Chain Benchmark

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Implement the first CUDA/CPU benchmark prototype for the bounded M5b
read-alignment replay fixture while preserving the `read-alignment-v1` oracle.

The core question this card must answer is:

```text
Can a standalone CUDA backend reproduce Flye's read-to-graph chain DP output at
the M5b replay boundary, and what is the measured hotpath ratio versus a C++
CPU baseline for the same fixture?
```

## Background

M5b isolated one selected toy-hifi read (`query_id=200`) and produced a compact
`read-alignment-replay-fixture-v0`. M5c turns that fixture into the first CUDA
read-to-graph chain DP benchmark. The result remains outside Flye graph
mutation and must be validated only at the replay oracle boundary.

## In Scope

- Add a standalone CUDA/C++ binary for M5b replay fixtures.
- Support explicit `cpu` and `cuda` backends.
- Emit `read-alignment-v1`.
- Validate CPU and CUDA outputs against `oracle.read-alignment.tsv`.
- Record warm repeated benchmark timing and compact DGX proof.
- Fail closed on unsupported or malformed replay fixtures.
- Fail closed on CUDA memory-budget violations before allocation.

## Out of Scope

- No Flye graph integration.
- No multi-read or batched fixture execution.
- No edlib/base realignment replay; M5c consumes M5b's recorded divergence
  acceptance flags.
- No default GPU mode.
- No end-to-end Flye speedup claim.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc` or `cudaFree` outside approved RAII
  wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Use explicit-width integer types at TSV, host/device transfer, and kernel
  boundaries.
- Keep backend selection explicit through CLI options.

## Deliverables

- `cuda/cuflye_cuda_read_alignment_chain_replay.cu`
- `scripts/build_cuda_read_alignment_chain_replay.sh`
- `docs/abi/cuda-read-alignment-chain-replay-v0.md`
- DGX proof manifest under `tests/golden/`
- Roadmap update with scoped timing claim

## Acceptance Gates

- [x] CUDA prototype builds on DGX.
- [x] CPU output validates as `read-alignment-v1`.
- [x] CUDA output validates as `read-alignment-v1`.
- [x] CPU and CUDA outputs canonical-diff `match` against the M5b oracle.
- [x] CPU and CUDA outputs canonical-diff `match` against each other.
- [x] Warm benchmark timing records CPU total/core and CUDA total/kernel.
- [x] Malformed or unsupported replay fixture fails closed.
- [x] CUDA memory budget failure happens before device allocation.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

DGX proof:
`/tmp/cuflye-m5c-proof-20260630T223044Z/out/m5c/dgx-cuda-read-alignment-chain-benchmark-proof.json`

Golden manifest:
`tests/golden/cuflye-m5c-cuda-read-alignment-chain-benchmark-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- GPU: `NVIDIA GB10`, CUDA arch `sm_121`
- CUDA compiler: `/usr/local/cuda/bin/nvcc`, CUDA `13.0`
- Fixture: M5b toy-hifi read `200`
- Input edge-overlap records: `4`
- Output `read-alignment-v1` records: `3`
- CPU, CUDA, and oracle canonical SHA-256:
  `c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802`
- CPU vs oracle diff: `match`
- CUDA vs oracle diff: `match`
- CPU vs CUDA diff: `match`
- Warmup runs: `5`
- Timed runs: `200`
- CPU mean total/core before JSON: `0.000482 ms`
- CUDA mean total before JSON: `0.137072 ms`
- CUDA mean kernel/core: `0.012329 ms`
- CUDA total speedup vs CPU: `0.003516x`
- CUDA kernel/core speedup vs CPU core: `0.039095x`
- Bad-schema negative gate: rejected before writing success JSON/TSV
- Memory-budget negative gate: `required=716`, `budget=1`, rejected before
  allocation and before writing success JSON/TSV

Conclusion: M5c proves the standalone CUDA backend can reproduce the M5b
read-alignment chain oracle exactly, but this single-read fixture is far too
small for GPU advantage. The next optimization target is batched multi-read
fixture collection and packed CUDA execution to raise GPU occupancy.
