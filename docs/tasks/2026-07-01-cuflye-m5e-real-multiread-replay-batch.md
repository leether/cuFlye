# Task Card: cuFlye M5e Real Multi-Read Replay Batch

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Replace the M5d replicated-read evidence with a real multi-read replay fixture
harvest and packed CUDA execution while preserving per-read oracle diffs.

The core question this card must answer is:

```text
Can cuFlye capture several real Flye read-alignment replay fixtures, execute
them as one packed CUDA batch, and keep every per-read read-alignment-v1 output
identical to the CPU oracle?
```

## Background

M5d proved the read-alignment chain kernel can beat the C++ CPU baseline when
the GPU receives enough independent work, but it used repeated copies of one
toy-hifi read. That was useful for the occupancy question, not for a real Flye
pipeline claim. M5e moves to real multiple reads harvested from one Flye run.

## In Scope

- Add opt-in multi-query replay fixture dumping with
  `CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS`.
- Keep the existing single-query `CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID`
  contract working.
- Dump each selected read under `query_<id>/` in multi-query mode.
- Add packed batch mode to `cuflye-cuda-read-alignment-chain-replay`.
- Require same-shape fixtures for the first packed kernel contract:
  `alignment_input_records`, chain-divergence rows, and replay parameters must
  match.
- Emit one `read-alignment-v1` TSV per real fixture.
- Validate CPU and CUDA batch outputs against each fixture's oracle and against
  each other.
- Record scoped timing and a plain-language benefit assessment.

## Out of Scope

- No Flye graph mutation consumption.
- No default GPU mode.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No heterogeneous-shape CUDA batch scheduler.
- No end-to-end Flye acceleration claim.

## C++/CUDA Style Constraints

- Keep Flye patch code C++11-compatible and close to upstream style.
- Keep standalone CUDA code CUDA C++14.
- Use existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc`, `cudaFree`, direct owning `new` or
  `delete`, or direct `malloc`/`free`.
- Check buffer sizing and narrow ABI conversions before allocation or kernel
  launch.
- Fail closed on unsupported batch shapes instead of silently falling back.

## Deliverables

- `patches/flye/2.9.6/0027-cuflye-read-alignment-multi-replay-fixture-dump.patch`
- `scripts/run_flye_fixture.sh` support for
  `--read-alignment-replay-query-ids`
- Real batch CLI and JSON output in
  `cuda/cuflye_cuda_read_alignment_chain_replay.cu`
- Updated ABI documentation
- DGX proof manifest under `tests/golden/`
- Roadmap update with scoped benefit or blocker

## Acceptance Gates

- [x] Patch series builds on DGX through `0027`.
- [x] Multi-query replay dumping creates at least two real `query_<id>`
      fixture directories from one Flye run.
- [x] Same-shape real fixture list is selected deterministically.
- [x] CPU batch output validates as `read-alignment-v1` for every fixture.
- [x] CUDA batch output validates as `read-alignment-v1` for every fixture.
- [x] CPU and CUDA per-fixture outputs canonical-diff `match` against each
      fixture's oracle.
- [x] CPU and CUDA per-fixture outputs canonical-diff `match` against each
      other.
- [x] Batch JSON records fixture count, total input records, per-fixture output
      paths, timing, and CUDA memory facts when backend is CUDA.
- [x] Unsupported mixed-shape batch fails closed.
- [x] CUDA memory-budget negative gate fails before writing success JSON/TSV.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

DGX proof:
`/tmp/cuflye-m5e-proof-20260630T230250Z/out/m5e/dgx-real-multiread-replay-batch-proof.json`

Golden manifest:
`tests/golden/cuflye-m5e-real-multiread-replay-batch-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- GPU: `NVIDIA GB10`, CUDA arch `sm_121`
- Patch series: Flye 2.9.6 plus patches through
  `0027-cuflye-read-alignment-multi-replay-fixture-dump.patch`
- Multi-query harvest dumped `68` real `query_<id>` fixture directories from
  one toy-hifi Flye run.
- Selected same-shape batch: `19` real reads, each with `3` input edge-overlap
  records and `1` chain-divergence row.
- Selected query ids:
  `1069,1100,1229,1252,1279,1480,1500,1584,1716,1820,1909,1930,1989,2080,2214,2332,2345,2390,667`
- Total input records: `57`
- Total output `read-alignment-v1` records: `38`
- CPU, CUDA, and oracle per-fixture canonical diffs: all `match`
- CPU mean total/core before JSON: `0.003566 ms`
- CUDA mean total before JSON: `0.233540 ms`
- CUDA mean kernel/core: `0.011199 ms`
- CUDA total speedup vs CPU: `0.015269x`
- CUDA total slowdown vs CPU: `65.490746x`
- CUDA kernel/core speedup vs CPU core: `0.318421x`
- CUDA required bytes: `9595`
- Mixed-shape negative gate: rejected with
  `unsupported read-alignment batch: alignment_input_records differ`
- Memory-budget negative gate: `budget=1`, rejected before writing success
  JSON/TSV.

Conclusion: M5e removes the replicated-read limitation and proves packed CUDA
correctness for a real multi-read batch. It does not show a speedup on this
small toy batch; launch/copy overhead dominates. The next ROI target is larger
real batches, heterogeneous packing, or a persistent read-alignment worker.
