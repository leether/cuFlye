# Task Card: cuFlye M5b Read Alignment Replay Fixture

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Isolate one bounded read-to-graph alignment chain fixture from Flye so the
`ReadAligner::chainReadAlignments` contract can be replayed outside a full Flye
run before CUDA work starts.

## Background

M5a defines `read-alignment-v1` after `ReadAligner::alignReads`. M5b moves one
step upstream: capture the selected read, graph-edge overlap inputs, graph
connectivity needed by the chain DP, chain divergence decisions, and the
accepted oracle chain.

## In Scope

- Add an opt-in `CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR` fixture dump.
- Require `--threads 1` and a positive
  `CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID`.
- Capture `read.tsv`, `edge-sequences.tsv`, `edge-overlaps.tsv`,
  `chain-divergence.tsv`, `oracle.read-alignment.tsv`, and `manifest.json`.
- Add a CPU replay tool that reproduces the accepted chain output as
  `read-alignment-v1`.
- DGX proof on one selected toy read where replay output canonical-diffs
  `match` against the fixture oracle.

## Out of Scope

- No CUDA read-alignment kernel.
- No multi-read replay batch.
- No graph mutation changes.
- No end-to-end Flye speedup claim.

## Acceptance Gates

- [x] Patch series applies and builds through `0026`.
- [x] DGX fixture dump captures one selected read and non-empty edge-overlap
      inputs.
- [x] CPU replay output validates as `read-alignment-v1`.
- [x] CPU replay output canonical-diffs `match` against
      `oracle.read-alignment.tsv`.
- [x] Multi-thread fixture dump fails closed.
- [x] No C++ direct resource ownership is introduced.

## C++ Style Constraints

- Use RAII file handles only.
- Keep fixture dump side-effect-free with respect to `_readAlignments`.
- Do not introduce `new`, `delete`, `malloc`, `free`, or direct CUDA resource
  calls.

## Deliverables

- `patches/flye/2.9.6/0026-cuflye-read-alignment-replay-fixture-dump.patch`
- `tools/replay_read_alignment_chains.py`
- runner support for read-alignment replay fixture env vars
- DGX proof manifest and golden index update

## Completion Notes

DGX proof:
`/tmp/cuflye-m5b-proof-20260630T221339Z/out/m5b/dgx-read-alignment-replay-fixture-proof.json`

Golden manifest:
`tests/golden/cuflye-m5b-read-alignment-replay-fixture-dgx-aarch64.json`

The selected toy-hifi read is query `200`. The replay fixture contains one
selected read, four graph-edge overlap inputs, one candidate chain, and one
accepted oracle chain. The replay tool emits three `read-alignment-v1` records
with canonical SHA-256:

```text
c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
```

The replay-vs-oracle canonical diff is `match`.

The negative DGX run enabled fixture dumping with `--threads 2`; Flye exited
with status `1`, found the fail-closed message
`cuFlye read alignment replay fixture dump requires --threads 1`, and produced
no replay fixture manifest.
