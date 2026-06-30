# Task Card: cuFlye M4h Packed Multi-Query Overlap Kernel

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move overlap-chain replay from one kernel launch per fixture toward a packed
multi-query CUDA execution boundary.

The core question this card must answer is:

```text
Can packing multiple real replay-match fixtures into fewer CUDA launches reduce
overlap-chain overhead while preserving per-query overlap-range-v1 hashes?
```

## Background

M4g proved that a single-process batch worker can validate the M4f top-9
replay-match fixtures while reusing CUDA context and device buffers. It also
showed that this reuse is not enough for a CUDA speedup: CPU batch mean total
before write was `9.217960 ms`, serial CUDA was `36.781822 ms`, and parallel
CUDA was `45.264240 ms`.

The next likely bottleneck is still launch granularity and per-query device
work, not fixture capture or output validation.

## In Scope

- Define a packed multi-query device layout for the supported M4f/M4g fixture
  shape.
- Preserve explicit per-query provenance and output ownership.
- Run more than one replay fixture through fewer CUDA launches than M4g.
- Emit per-fixture overlap TSVs or a combined output with unambiguous query
  boundaries.
- Validate every query output as `overlap-range-v1`.
- Canonical-diff every query output against its CPU oracle.
- Benchmark against M4g CPU batch and M4g CUDA batch worker timings.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No semantic changes to overlap scoring, predecessor selection, or filters.
- No synthetic fixture duplication as a speed claim.
- No workload-level Flye GPU mode claim.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Use existing RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Prefer explicit packed-offset structs and bounds checks over ad hoc pointer
  arithmetic.
- Keep packed-query provenance explicit in JSON output.
- Fail closed on unsupported fixture shapes.

## Deliverables

- Packed multi-query overlap replay CUDA mode or prototype.
- DGX proof over the M4g top replay-match fixtures.
- Timing comparison against M4g CPU batch, serial CUDA batch, and parallel CUDA
  batch worker.
- Updated roadmap claim boundaries based on measured result.

## Acceptance Gates

- Every selected query output validates as `overlap-range-v1`.
- Every selected query output canonical-diffs `match` against its oracle.
- CUDA launch count is lower than M4g per-fixture CUDA execution for the same
  selected batch, or the proof records why not.
- Device memory capacity and per-query offsets are recorded.
- If packed CUDA is faster than CPU batch, the claim is scoped to the M4g real
  replay-match batch.
- If packed CUDA is not faster, proof records the remaining bottleneck.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [x] Design packed multi-query input/output contract.
- [x] Implement packed device layout and bounds-checked offsets.
- [x] Implement packed CUDA execution mode with fewer launches where possible.
- [x] Validate per-query outputs on DGX.
- [x] Diff per-query outputs against oracles.
- [x] Record timing summary, launch count, and speed ratios.
- [x] Run ownership/resource scan.
- [x] Record compact DGX proof and close this card.

## Merge Note

Implementation commit:
`bfc338864818b7e8a4bf486580138c753a49281f`.

DGX proof:
`tests/golden/cuflye-m4h-packed-multi-query-overlap-kernel-dgx-aarch64.json`.

M4h added `--batch-execution packed` for the overlap-chain replay runner. The
packed path concatenates multiple replay-match fixtures into one device layout,
copies query-specific `DeviceParams`, runs all target groups in a single CUDA
kernel launch per timed batch, and then splits outputs back by fixture for the
same `overlap-range-v1` validation and oracle diff gates.

The proof passed all correctness gates:

- CPU, per-fixture serial CUDA, per-fixture parallel CUDA, packed serial CUDA,
  and packed parallel CUDA all validated `9` top replay-match fixtures.
- Every output canonical-diffed `match` against the fixture oracle.
- Packed serial CUDA reduced launch count from `9` per timed run to `1`.
- Packed layout recorded `54694` candidate records, `892` target groups, and
  `9` parameter records.
- Syntax/style gates and CUDA ownership scan passed.

Measured batch timing on DGX `NVIDIA GB10` with `3` warmup runs and `20` timed
runs:

- CPU batch mean total before write: `14.977639 ms`.
- Per-fixture serial CUDA mean total before write: `36.093412 ms`.
- Per-fixture parallel CUDA mean total before write: `38.754444 ms`.
- Packed serial CUDA mean total before write: `6.906646 ms`.
- Packed parallel CUDA mean total before write: `7.308527 ms`.
- Packed serial CUDA speedup vs current CPU batch: `2.168584x`.
- Packed serial CUDA speedup vs M4g CPU baseline: `1.334651x`.

Conclusion: the project now has a bounded CUDA overlap-chain speedup on a real
replay-match fixture batch, with exact oracle parity. This is still not a Flye
stage or end-to-end `flye --gpu` speed claim.
