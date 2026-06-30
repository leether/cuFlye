# Task Card: cuFlye M5f Heterogeneous Read Alignment Batch

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Increase useful real read-alignment work per CUDA invocation path by allowing a
single real fixture list to contain multiple supported read-alignment shapes.

The core question this card must answer is:

```text
Can cuFlye take a heterogeneous set of real Flye read-alignment replay fixtures,
group them by supported CUDA shape, run packed CPU/CUDA batches per group, and
still preserve every per-read read-alignment-v1 oracle diff?
```

## Background

M5e proved packed CUDA correctness for a same-shape 19-read real batch, but the
toy-hifi harvest contained `68` real fixtures across multiple small shapes. The
same-shape restriction forced the proof to leave most real reads unused. M5f
adds an explicit heterogeneous grouping mode before any graph-facing
integration.

## In Scope

- Add an explicit `--allow-heterogeneous-batch` CLI flag to
  `cuflye-cuda-read-alignment-chain-replay`.
- Keep the default mixed-shape behavior fail-closed.
- Group heterogeneous fixture lists by CUDA-supported shape:
  `alignment_input_records`, chain-divergence row count, and replay parameters.
- Execute each shape group through the existing packed CPU/CUDA batch path.
- Preserve one output `read-alignment-v1` TSV per real fixture.
- Record shape-group metadata in batch JSON.
- Validate all CPU and CUDA outputs against per-read oracles and each other.
- Record timing and a plain-language benefit assessment.

## Out of Scope

- No new CUDA kernel algorithm.
- No graph mutation consumption.
- No default GPU mode.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No end-to-end Flye acceleration claim.

## C++/CUDA Style Constraints

- Keep standalone CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc`, `cudaFree`, direct owning `new` or
  `delete`, or direct `malloc`/`free`.
- Check buffer sizing and narrow ABI conversions before allocation or kernel
  launch.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- `--allow-heterogeneous-batch` in
  `cuda/cuflye_cuda_read_alignment_chain_replay.cu`
- Updated ABI documentation for grouped heterogeneous batch JSON
- DGX proof manifest under `tests/golden/`
- Roadmap update with scoped benefit or blocker

## Acceptance Gates

- [x] CUDA replay binary builds on DGX.
- [x] Default mixed-shape batch still fails closed.
- [x] Explicit heterogeneous mode runs all selected real fixtures.
- [x] Batch JSON records shape groups and per-fixture output paths.
- [x] CPU heterogeneous outputs validate as `read-alignment-v1` for every
      fixture.
- [x] CUDA heterogeneous outputs validate as `read-alignment-v1` for every
      fixture.
- [x] CPU and CUDA per-fixture outputs canonical-diff `match` against each
      fixture's oracle.
- [x] CPU and CUDA per-fixture outputs canonical-diff `match` against each
      other.
- [x] CUDA memory-budget negative gate fails before writing success JSON/TSV.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

DGX proof:
`/tmp/cuflye-m5f-proof-20260630T231847Z/out/m5f/dgx-heterogeneous-read-alignment-batch-proof.json`

Golden manifest:
`tests/golden/cuflye-m5f-heterogeneous-read-alignment-batch-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- GPU: `NVIDIA GB10`, CUDA arch `sm_121`
- Source fixtures: M5e toy-hifi multi-query harvest
- Heterogeneous fixture count: `68`
- Shape groups: `4`
- Shape group sizes:
  - `1` input record: `30` reads
  - `2` input records: `11` reads
  - `3` input records: `19` reads
  - `4` input records: `8` reads
- Total input records: `141`
- Total output `read-alignment-v1` records: `114`
- CPU, CUDA, and oracle per-fixture canonical diffs: all `match`
- CPU mean total/core before JSON: `0.021866 ms`
- CUDA mean total before JSON: `0.899946 ms`
- CUDA mean kernel/core: `0.044258 ms`
- CUDA total speedup vs CPU: `0.024297x`
- CUDA total slowdown vs CPU: `41.157322x`
- CUDA kernel/core speedup vs CPU core: `0.494058x`
- CUDA required bytes: `9595`
- Default mixed-shape negative gate: rejected without
  `--allow-heterogeneous-batch`
- Memory-budget negative gate: `budget=1`, rejected before writing success
  JSON/TSV.

Conclusion: M5f expands correctness coverage from one same-shape group to all
`68` real toy-hifi read fixtures by grouping four supported shapes. It does not
show a speedup; the batch is still tiny and pays four CUDA launch/setup paths.
The next ROI target is a persistent grouped worker with reusable device buffers
and then larger non-toy fixture harvests.
