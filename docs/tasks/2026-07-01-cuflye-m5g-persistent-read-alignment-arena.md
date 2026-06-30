# Task Card: cuFlye M5g Persistent Read Alignment Arena

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce M5f grouped CUDA overhead by keeping per-shape device buffers allocated
and populated across repeated benchmark runs.

The core question this card must answer is:

```text
Can a persistent CUDA arena for grouped read-alignment replay preserve every
per-read oracle diff while reducing CUDA overhead versus the M5f cold grouped
batch path?
```

## Background

M5f proved correctness for a heterogeneous `68`-read toy-hifi batch, but every
timed run repeated CUDA setup, allocation, host-to-device copies, kernel
launches, and device-to-host copies for four shape groups. The result was
correct but slow: CUDA total was `0.899946 ms` versus CPU `0.021866 ms`.

M5g tests the next overhead lever before graph-facing integration: a persistent
arena that allocates and copies static fixture inputs once, then benchmarks the
steady-state grouped kernel/output path.

## In Scope

- Add an explicit CUDA-only persistent arena mode to
  `cuflye-cuda-read-alignment-chain-replay`.
- Keep default batch behavior unchanged.
- Keep mixed-shape input fail-closed unless `--allow-heterogeneous-batch` is
  set.
- Allocate one reusable CUDA buffer set per shape group.
- Copy static overlap/divergence inputs once before warm/timed runs.
- Run warm/timed benchmark iterations without per-run device allocation or
  host-to-device copies.
- Emit the same per-fixture `read-alignment-v1` TSV outputs.
- Record one-time arena setup/allocation/H2D costs separately from steady-state
  benchmark timing.
- Compare persistent arena timing against the M5f cold grouped CUDA path.

## Out of Scope

- No Flye graph mutation consumption.
- No default GPU mode.
- No long-lived external process protocol yet.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No end-to-end Flye acceleration claim.

## C++/CUDA Style Constraints

- Keep standalone CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc`, `cudaFree`, direct owning `new` or
  `delete`, or direct `malloc`/`free`.
- Check aggregate persistent arena memory before allocation.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- Persistent arena CLI and JSON timing fields in
  `cuda/cuflye_cuda_read_alignment_chain_replay.cu`
- Updated ABI documentation
- DGX proof manifest under `tests/golden/`
- Roadmap update with scoped benefit or blocker

## Acceptance Gates

- [x] CUDA replay binary builds on DGX.
- [x] Persistent arena mode is explicit and CUDA-only.
- [x] Default mixed-shape batch still fails closed.
- [x] Persistent heterogeneous mode runs all selected real fixtures.
- [x] CPU/CUDA persistent outputs canonical-diff `match` against every
      fixture oracle.
- [x] Persistent CUDA outputs canonical-diff `match` against cold CUDA grouped
      outputs.
- [x] JSON records one-time setup/allocation/H2D and steady-state benchmark
      timing separately.
- [x] Persistent arena CUDA timing is compared against M5f cold grouped CUDA
      timing.
- [x] CUDA memory-budget negative gate uses aggregate persistent arena memory.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5g-proof-20260630T233335Z`
- Golden manifest:
  `tests/golden/cuflye-m5g-persistent-read-alignment-arena-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`, GPU `NVIDIA GB10`, compute capability
  `12.1`
- Fixture source: M5e toy-hifi read-alignment replay fixture harvest.
- Selected fixtures: `68` real read fixtures grouped into `4` CUDA shape
  groups.
- Total input records: `141`
- Output records: `114`
- CPU mean total before JSON: `0.010628 ms`
- Cold grouped CUDA mean total before JSON: `0.871576 ms`
- Persistent CUDA mean total before JSON: `0.377181 ms`
- Persistent CUDA speedup versus cold grouped CUDA: `2.310763x`
- Persistent CUDA speedup versus CPU: `0.028177x`
- Persistent CUDA slowdown versus CPU: `35.489368x`
- Persistent CUDA core speedup versus cold CUDA core: `2.158264x`
- Persistent CUDA core speedup versus CPU core: `0.529441x`
- One-time arena setup/allocation/H2D cost: `243.870057 ms`

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match`.

Negative gates:

- `--cuda-persistent-arena --backend cpu` fails closed with
  `--cuda-persistent-arena requires --backend cuda`.
- Persistent CUDA with `--memory-budget-bytes 1` fails closed with
  `CUDA memory budget exceeded for persistent read-alignment arena`.
- Default mixed-shape batch without `--allow-heterogeneous-batch` still fails
  closed.

Allowed M5g claim:

```text
cuFlye can explicitly reuse per-shape CUDA read-alignment arenas across
benchmark iterations for the 68-read heterogeneous M5e replay fixture set while
preserving every per-read oracle diff.
```

Forbidden M5g claim:

```text
M5g does not prove end-to-end Flye acceleration, default GPU mode, graph
mutation consumption, edlib/base realignment replay, or CUDA read-alignment
speedup over CPU for this small fixture set.
```

Plain-language benefit assessment:

```text
Persistent arena removed enough CUDA setup/allocation/copy overhead to make the
CUDA path 2.31x faster than the previous cold grouped CUDA path. The batch is
still far too small for GPU to beat CPU, so the advantage is architectural:
we now know reuse is the right direction, but need larger real batches or a
long-lived worker before this can become a CPU-beating path.
```
